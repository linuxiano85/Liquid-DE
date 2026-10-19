import 'dart:async';
import 'dart:io';

import '../accounts/account_service.dart';
import '../db/mail_store.dart';
import '../transport/mail_transport.dart';
import '../transport/retry.dart';
import 'folder_sync.dart';

/// Stato di un account, mostrato dalla UI.
enum SyncPhase {
  stopped,
  connecting,
  syncing,

  /// Aggiornato e in ascolto (IDLE) di novità.
  watching,

  /// Rete o server non disponibili: nuovo tentativo automatico.
  offline,

  // Stati che richiedono l'utente: nessun tentativo automatico finché non
  // cambia qualcosa (syncNow, nuova password, sblocco del portachiavi).
  authFailed,

  /// Accesso con Google revocato o scaduto: va rifatto dal browser.
  oauthReauth,
  untrustedCertificate,
  needsPassword,
  keyringLocked,
  keyringUnavailable,
}

sealed class SyncEvent {
  const SyncEvent(this.accountId);
  final int accountId;
}

class SyncStateEvent extends SyncEvent {
  const SyncStateEvent(super.accountId, this.phase,
      {this.message, this.retryIn, this.certificateSha256});
  final SyncPhase phase;
  final String? message;
  final Duration? retryIn;
  final String? certificateSha256;

  Map<String, Object?> toJson() => {
        'accountId': accountId,
        'phase': phase.name,
        if (message != null) 'message': message,
        if (retryIn != null) 'retryInSeconds': retryIn!.inMilliseconds / 1000,
        if (certificateSha256 != null) 'certificateSha256': certificateSha256,
      };
}

class MailChangedEvent extends SyncEvent {
  const MailChangedEvent(super.accountId, this.report);
  final SyncReport report;
  Map<String, Object?> toJson() => {'accountId': accountId, ...report.toJson()};
}

enum _Wake { stop, syncAll, inboxChanged, lost }

/// Tiene un account sincronizzato: connessione, sync completa, IDLE sulla
/// Posta in arrivo, sync periodica delle altre cartelle, riconnessione con
/// backoff. Tutte le operazioni IMAP passano da un solo ciclo, quindi non
/// si sovrappongono mai sulla stessa connessione.
class AccountSyncRunner {
  AccountSyncRunner({
    required this.accountId,
    required this.accounts,
    required this.store,
    required this.transportFactory,
    required this.onEvent,
    Backoff? backoff,
    this.otherFoldersEvery = const Duration(minutes: 15),
    this.lockedRetryEvery = const Duration(minutes: 2),
    this.changeDebounce = const Duration(milliseconds: 300),
    this.window = const Duration(days: 30),
    this.batchSize = 200,
    this.afterFolderSync,
  }) : backoff = backoff ?? Backoff();

  /// Lavoro da fare dopo la sync di una cartella, con la stessa connessione
  /// e la cartella ancora selezionata: è qui che si scaricano i corpi e passa
  /// il filtro. Un suo errore di rete conta come un errore della sync.
  final Future<void> Function(MailTransport t, int folderId, String path, String role)?
      afterFolderSync;

  final int accountId;
  final AccountService accounts;
  final MailStore store;
  final TransportFactory transportFactory;
  final void Function(SyncEvent event) onEvent;
  final Backoff backoff;
  final Duration otherFoldersEvery;
  final Duration lockedRetryEvery;

  /// Le notifiche del server arrivano spesso a raffica (FETCH + EXPUNGE +
  /// EXISTS): si aspetta un attimo e si fa una sola sync.
  final Duration changeDebounce;
  final Duration window;
  final int batchSize;

  SyncPhase _phase = SyncPhase.stopped;
  SyncPhase get phase => _phase;
  SyncStateEvent? _lastState;
  SyncStateEvent? get lastState => _lastState;

  bool _stopping = false;
  Future<void>? _loop;
  Completer<_Wake>? _wake;
  MailTransport? _transport;

  /// Numero di tentativi di connessione: utile per verificare che gli
  /// errori definitivi non vengano ritentati a ripetizione.
  int connectAttempts = 0;

  /// Errori imprevisti intercettati (per i log e per i test).
  final List<Object> unexpectedErrors = [];

  void _logError(Object e, StackTrace st) {
    unexpectedErrors.add(e);
    stderr.writeln('[sync $accountId] errore imprevisto: $e');
  }

  void start() {
    if (_loop != null) throw StateError('Già avviato');
    _stopping = false;
    _loop = _run();
  }

  Future<void> stop() async {
    _stopping = true;
    _signal(_Wake.stop);
    // Interrompe un'eventuale operazione di rete in corso invece di aspettarla.
    final t = _transport;
    if (t != null) unawaited(t.abort());
    await _loop?.timeout(const Duration(seconds: 10), onTimeout: () {});
    _loop = null;
  }

  /// Sync immediata: dopo il risveglio dalla sospensione, un cambio di rete,
  /// una nuova password o lo sblocco del portachiavi. Interrompe le attese.
  void syncNow() => _signal(_Wake.syncAll);

  /// Segnale arrivato mentre il ciclo era occupato (es. risveglio durante una
  /// sync): non va perso, viene servito al prossimo punto di attesa.
  _Wake? _pending;

  void _signal(_Wake w) {
    final c = _wake;
    if (c != null && !c.isCompleted) {
      c.complete(w);
    } else if (w == _Wake.syncAll) {
      _pending = w;
    }
  }

  _Wake? _takePending() {
    final p = _pending;
    _pending = null;
    return p;
  }

  void _setPhase(SyncPhase phase,
      {String? message, Duration? retryIn, String? certificateSha256}) {
    _phase = phase;
    final e = SyncStateEvent(accountId, phase,
        message: message, retryIn: retryIn, certificateSha256: certificateSha256);
    _lastState = e;
    onEvent(e);
  }

  /// Attende un segnale; con [timeout] riprende da sola allo scadere.
  Future<_Wake> _waitWake([Duration? timeout]) {
    final c = Completer<_Wake>();
    _wake = c;
    if (_stopping) {
      c.complete(_Wake.stop);
    } else {
      final p = _takePending();
      if (p != null) c.complete(p);
    }
    final f = c.future;
    return timeout == null ? f : f.timeout(timeout, onTimeout: () => _Wake.syncAll);
  }

  Future<void> _run() async {
    var retriedToken = false;
    while (!_stopping) {
      _setPhase(SyncPhase.connecting);
      final TransportConfig? config;
      try {
        config = await accounts.transportConfigFor(accountId);
      } on AccountException catch (e) {
        switch (e.reason) {
          case AccountErrorReason.notFound:
            _stopping = true;
            continue;
          case AccountErrorReason.keyringLocked:
            _setPhase(SyncPhase.keyringLocked, message: e.message);
            await _waitWake(lockedRetryEvery);
          case AccountErrorReason.oauthReauth:
            _setPhase(SyncPhase.oauthReauth, message: e.message);
            await _waitWake();
          case AccountErrorReason.unreachable:
            // Rinnovo del token non riuscito per la rete: come un server giù.
            final wait = backoff.next();
            _setPhase(SyncPhase.offline, message: e.message, retryIn: wait);
            await _waitWake(wait);
          default:
            _setPhase(SyncPhase.keyringUnavailable, message: e.message);
            await _waitWake(lockedRetryEvery);
        }
        continue;
      }
      if (config == null) {
        _setPhase(SyncPhase.needsPassword, message: 'Password non presente nel portachiavi');
        await _waitWake();
        continue;
      }

      final transport = transportFactory(config);
      _transport = transport;
      try {
        connectAttempts++;
        await transport.connect();
        retriedToken = false;
        await _syncAll(transport);
        // Il backoff si azzera solo dopo una sync riuscita: un server che
        // accetta la connessione e poi cade subito non deve essere
        // martellato senza pause.
        backoff.reset();
        await _watchLoop(transport);
      } on MailTransportException catch (e) {
        if (_stopping) break;
        switch (e.kind) {
          case TransportErrorKind.authFailed when !retriedToken && accounts.isOAuth(accountId):
            // Il token può essere rifiutato prima della scadenza (revocato,
            // orologio sbagliato): uno nuovo, e un solo altro tentativo.
            retriedToken = true;
            accounts.forgetAccessToken(accountId);
          case TransportErrorKind.authFailed || TransportErrorKind.appPasswordRequired:
            _setPhase(SyncPhase.authFailed, message: e.message);
            await _waitWake();
          case TransportErrorKind.tlsUntrusted:
            _setPhase(SyncPhase.untrustedCertificate,
                message: e.message, certificateSha256: e.certificateSha256);
            await _waitWake();
          default:
            final wait = backoff.next();
            _setPhase(SyncPhase.offline, message: e.message, retryIn: wait);
            await _waitWake(wait);
        }
      } catch (e, st) {
        // Qualsiasi altro errore (bug, risposta del server inattesa, database
        // occupato) non deve fermare per sempre la sincronizzazione
        // dell'account: si registra e si riprova con il backoff.
        if (_stopping) break;
        _logError(e, st);
        final wait = backoff.next();
        _setPhase(SyncPhase.offline, message: 'Errore imprevisto durante la sincronizzazione', retryIn: wait);
        await _waitWake(wait);
      } finally {
        _transport = null;
        if (_stopping) {
          await transport.abort();
        } else {
          await transport.disconnect();
        }
      }
    }
    _setPhase(SyncPhase.stopped);
  }

  String _inboxPath = 'INBOX';
  Map<String, int> _folderIds = const {};
  Map<String, String> _roles = const {};

  Future<void> _syncAll(MailTransport transport) async {
    _setPhase(SyncPhase.syncing);
    final remote = await transport.listFolders();
    final ids = _folderIds = store.syncFolderList(
        accountId, [for (final f in remote) (path: f.path, role: f.role)]);
    _roles = {for (final f in remote) f.path: f.role};
    _inboxPath = remote.firstWhere((f) => f.role == 'inbox',
        orElse: () => const RemoteFolder('INBOX', 'inbox')).path;
    // Prima la Posta in arrivo: è ciò che l'utente vuole vedere subito.
    final ordered = [_inboxPath, ...ids.keys.where((p) => p != _inboxPath)];
    for (final path in ordered) {
      if (_stopping) return;
      final id = ids[path];
      if (id == null) continue;
      await _syncFolder(transport, id, path);
    }
  }

  Future<void> _syncFolder(MailTransport transport, int folderId, String path) async {
    final report = await FolderSync(store, transport, window: window, batchSize: batchSize)
        .sync(folderId, path);
    if (report.changed) onEvent(MailChangedEvent(accountId, report));
    final after = afterFolderSync;
    if (after != null && !_stopping) {
      await after(transport, folderId, path, _roles[path] ?? 'other');
    }
  }

  Future<void> _watchLoop(MailTransport transport) async {
    var nextFullSync = DateTime.now().add(otherFoldersEvery);
    while (!_stopping) {
      await transport.selectFolder(_inboxPath);
      final wake = Completer<_Wake>();
      _wake = wake;
      final pending = _takePending();
      if (pending != null) wake.complete(pending);
      final sub = transport.watch().listen((event) {
        if (wake.isCompleted) return;
        if (event is ConnectionLostEvent) {
          wake.complete(_Wake.lost);
        } else {
          wake.complete(_Wake.inboxChanged);
        }
      }, onDone: () {
        if (!wake.isCompleted) wake.complete(_Wake.lost);
      });
      _setPhase(SyncPhase.watching);
      final untilFull = nextFullSync.difference(DateTime.now());
      final reason = await wake.future.timeout(
          untilFull.isNegative ? Duration.zero : untilFull,
          onTimeout: () => _Wake.syncAll);
      await sub.cancel();

      switch (reason) {
        case _Wake.stop:
          await transport.stopWatching();
          return;
        case _Wake.lost:
          throw MailTransportException(
              TransportErrorKind.connectionLost, 'Connessione persa durante l\'ascolto');
        case _Wake.inboxChanged:
          await transport.stopWatching();
          await Future<void>.delayed(changeDebounce);
          _setPhase(SyncPhase.syncing);
          final id = _folderIds[_inboxPath];
          if (id != null) {
            await _syncFolder(transport, id, _inboxPath);
          } else {
            await _syncAll(transport);
          }
        case _Wake.syncAll:
          await transport.stopWatching();
          await _syncAll(transport);
          nextFullSync = DateTime.now().add(otherFoldersEvery);
      }
    }
  }
}
