import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:liquid_maild/liquid_maild.dart';
import 'package:path/path.dart' as p;

/// Avvio: `liquid-maild [--port N]`.
/// Il daemon termina in modo pulito con SIGINT/SIGTERM e cancella i file
/// di runtime, così la UI non trova un token o una porta non più validi.
void main(List<String> args) {
  // Rete di sicurezza: un errore asincrono sfuggito a una libreria (è
  // successo con un evento IMAP tardivo, vedi _SafeImapClient) non deve
  // spegnere la posta di tutta la sessione. Si registra e si continua: ogni
  // gestore di account ha già la sua ripresa con backoff.
  runZonedGuarded(() => _main(args), (error, stack) {
    stderr.writeln('[liquid-maild] errore non gestito, il daemon continua: $error');
  });
}

Future<void> _main(List<String> args) async {
  var port = 0;
  final i = args.indexOf('--port');
  if (i >= 0 && i + 1 < args.length) {
    final parsed = int.tryParse(args[i + 1]);
    if (parsed == null || parsed < 0 || parsed > 65535) {
      stderr.writeln('Porta non valida: ${args[i + 1]}');
      exit(64);
    }
    port = parsed;
  }

  final RuntimeFiles files;
  try {
    files = RuntimeFiles.fromEnvironment();
  } on StateError catch (e) {
    stderr.writeln(e.message);
    exit(78);
  }
  // Prima di qualunque altra cosa: un secondo daemon non deve toccare né i
  // file del primo né il database. Il lanciatore riconosce il codice 75 e
  // si collega al daemon già attivo.
  if (!await files.acquireInstanceLock()) {
    stderr.writeln('liquid-maild è già in esecuzione in questa sessione');
    exit(75);
  }

  final MailDatabase database;
  final dataDir = _dataDirectory();
  try {
    await Directory(dataDir).create(recursive: true);
    final chmod = await Process.run('chmod', ['700', dataDir]);
    if (chmod.exitCode != 0) {
      stderr.writeln('Impossibile proteggere $dataDir (chmod 700): ${chmod.stderr}');
      exit(73);
    }
    database = MailDatabase.open(p.join(dataDir, 'mail.db'));
  } on DatabaseCorruptException catch (e) {
    stderr.writeln('$e\nSposta o elimina il file per ricostruire la cache dal server.');
    exit(65);
  } on DatabaseTooNewException catch (e) {
    stderr.writeln('$e\nAggiorna Liquid Mail.');
    exit(65);
  }

  final secrets = SecretServiceStore();
  final store = MailStore(database);
  final accounts = AccountService(
    store: store,
    secrets: secrets,
    autoconfig: Autoconfig(),
    transportFactory: EnoughImapTransport.new,
    // Il client Google del progetto Liquid, fuori dal repository: senza il
    // file resta la password per le app.
    googleOAuth: () {
      final c = OAuthClientCredentials.load(OAuthClientCredentials.defaultPath());
      return c == null ? null : GoogleOAuth(c);
    },
  );
  late final Daemon daemon;
  late final SyncManager sync;
  final filter = AdFilter(FilterStore(database));
  final notifier = DesktopNotifier();
  final mail = MailService(
    accounts: accounts,
    store: store,
    messages: MessageStore(database),
    attachments: AttachmentStore(Directory(p.join(dataDir, 'allegati'))),
    transportFactory: EnoughImapTransport.new,
    filter: filter,
    onNewMail: (_, mails) => notifier.announce(mails),
    onFoldersChanged: (accountId, folders) {
      daemon.notifyFoldersChanged(accountId, folders);
      // Il server ha l'ultima parola: una sync conferma lo stato delle cartelle.
      sync.syncNow(accountId);
    },
  );
  sync = SyncManager(
    accounts: accounts,
    store: store,
    transportFactory: EnoughImapTransport.new,
    onEvent: (e) => daemon.forwardSyncEvent(e),
    afterFolderSync: (t, accountId, folderId, path, role) async {
      // Corpi scaricati in sottofondo dove servono subito: Posta in arrivo
      // (con il filtro) e Inviata (per la ricerca e la vista Chat).
      if (role != 'inbox' && role != 'sent') return;
      final done = await mail.prefetchBodies(t, accountId, folderId, isInbox: role == 'inbox');
      if (done > 0) daemon.notifyFoldersChanged(accountId, {folderId});
    },
  );
  DBusClient? systemBus;
  try {
    systemBus = DBusClient.system();
  } catch (_) {}
  daemon = Daemon(
    runtimeFiles: files,
    port: port,
    accounts: accounts,
    sync: sync,
    resumes: systemBus == null ? null : logindResumes(systemBus),
    filter: filter,
    mail: mail,
  );
  try {
    await daemon.start();
  } on SocketException catch (e) {
    stderr.writeln('Impossibile aprire la porta $port: ${e.message}');
    exit(69);
  }
  stdout.writeln('liquid-maild $daemonVersion in ascolto su 127.0.0.1:${daemon.rpc.port}');

  final done = Completer<void>();
  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signal.watch().listen((_) async {
      if (done.isCompleted) return;
      await daemon.stop();
      await secrets.close();
      await notifier.close();
      await systemBus?.close();
      database.close();
      await files.releaseInstanceLock();
      done.complete();
    });
  }
  await done.future;
  exit(0);
}

/// $XDG_DATA_HOME/liquid-mail, oppure ~/.local/share/liquid-mail.
String _dataDirectory() {
  final env = Platform.environment;
  final xdg = env['XDG_DATA_HOME'];
  final base = (xdg != null && xdg.isNotEmpty)
      ? xdg
      : p.join(env['HOME'] ?? '/tmp', '.local', 'share');
  return p.join(base, 'liquid-mail');
}
