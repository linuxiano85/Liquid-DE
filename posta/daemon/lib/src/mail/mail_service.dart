import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../accounts/account_service.dart';
import '../db/attachment_store.dart';
import '../db/mail_store.dart';
import '../filter/ad_features.dart';
import '../filter/ad_filter.dart';
import '../mime/message_reader.dart';
import '../transport/mail_transport.dart';
import 'composer.dart';
import 'message_store.dart';
import 'notifier.dart';
import 'smtp_sender.dart';

/// Funzione che spedisce via SMTP (sostituibile nei test).
typedef SmtpSend = Future<List<String>> Function(
    TransportConfig config, String from, List<String> recipients, Uint8List raw);

/// Errore di un'operazione chiesta dall'utente, con un motivo che la UI
/// sa mostrare.
class MailOperationException implements Exception {
  MailOperationException(this.reason, this.message);

  /// `notFound`, `tooLarge`, `unreadable`, `offline`, `server`, `noFolder`,
  /// `invalidPath`, `exists`.
  final String reason;
  final String message;
  @override
  String toString() => 'MailOperationException($reason): $message';
}

/// Connessione IMAP "comandi" di un account, separata da quella della
/// sincronizzazione (occupata dall'IDLE). Le operazioni passano una alla
/// volta; la connessione si apre alla prima e si chiude dopo [idleClose]
/// senza lavoro. Gmail ne permette 15 per account, qui se ne usano due.
class CommandChannel {
  CommandChannel(this.accountId, this.accounts, this.transportFactory,
      {this.idleClose = const Duration(minutes: 2)});

  final int accountId;
  final AccountService accounts;
  final TransportFactory transportFactory;
  final Duration idleClose;

  MailTransport? _transport;
  Future<void> _tail = Future.value();
  Timer? _closer;

  /// Esegue [op] dopo quelle già in coda. Una connessione caduta nel
  /// frattempo (sospensione, cambio di rete) si riapre e si riprova una volta.
  Future<T> run<T>(Future<T> Function(MailTransport t) op) {
    final result = _tail.then((_) => _runNow(op));
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<T> _runNow<T>(Future<T> Function(MailTransport t) op) async {
    _closer?.cancel();
    try {
      for (var attempt = 0;; attempt++) {
        final t = await _connected();
        try {
          return await op(t);
        } on MailTransportException catch (e) {
          final lost = e.kind == TransportErrorKind.connectionLost ||
              e.kind == TransportErrorKind.timeout;
          if (!lost || attempt > 0) rethrow;
          _transport = null;
          unawaited(t.abort());
        }
      }
    } finally {
      _closer = Timer(idleClose, close);
    }
  }

  Future<MailTransport> _connected() async {
    final existing = _transport;
    if (existing != null && existing.isConnected) return existing;
    final config = await accounts.transportConfigFor(accountId);
    if (config == null) {
      throw MailOperationException('offline', 'Password non presente nel portachiavi');
    }
    final t = transportFactory(config);
    await t.connect();
    return _transport = t;
  }

  Future<void> close() async {
    _closer?.cancel();
    final t = _transport;
    _transport = null;
    if (t != null) await t.disconnect();
  }
}

/// Operazioni sulla posta chieste dall'interfaccia, e il lavoro sui corpi
/// fatto durante la sincronizzazione.
class MailService {
  MailService({
    required this.accounts,
    required this.store,
    required this.messages,
    required this.attachments,
    required this.transportFactory,
    this.filter,
    this.onFoldersChanged,
    this.maxAutoBodyBytes = 2 * 1024 * 1024,
    this.maxBodyBytes = 64 * 1024 * 1024,
    this.readTimeout = const Duration(seconds: 10),
    this.maxInlineImageBytes = 5 * 1024 * 1024,
    SmtpSend? smtpSend,
    MessageComposer? composer,
    this.maxAttachmentBytes = 25 * 1024 * 1024,
    this.onNewMail,
    this.notifyWindow = const Duration(minutes: 30),
    DateTime Function()? clock,
  })  : _clock = clock ?? DateTime.now,
        smtpSend = smtpSend ?? SmtpSender().send,
        composer = composer ?? MessageComposer();

  final SmtpSend smtpSend;

  /// Posta nuova da annunciare (notifica della scrivania).
  final void Function(int accountId, List<NewMail> mails)? onNewMail;

  /// Si annunciano solo le email arrivate da poco: il primo scaricamento di
  /// un account (30 giorni di posta) non deve riempire lo schermo di avvisi.
  final Duration notifyWindow;
  final DateTime Function() _clock;
  final MessageComposer composer;

  /// Totale degli allegati di un messaggio: è il limite di Gmail e Outlook.
  final int maxAttachmentBytes;

  final AccountService accounts;
  final MailStore store;
  final MessageStore messages;
  final AttachmentStore attachments;
  final TransportFactory transportFactory;
  final AdFilter? filter;

  /// Chiamato dopo spostamenti e cancellazioni: la UI ricarica le liste e la
  /// sincronizzazione conferma lo stato con il server.
  final void Function(int accountId, Set<int> folderIds)? onFoldersChanged;

  /// Oltre questa dimensione il corpo non si scarica in sottofondo, solo
  /// quando l'utente apre il messaggio.
  final int maxAutoBodyBytes;

  /// Oltre questa nemmeno all'apertura (resta il sorgente sul server).
  final int maxBodyBytes;
  final Duration readTimeout;
  final int maxInlineImageBytes;

  final Map<int, CommandChannel> _channels = {};

  CommandChannel _channel(int accountId) => _channels.putIfAbsent(
      accountId, () => CommandChannel(accountId, accounts, transportFactory));

  Future<void> closeAll() async {
    final all = _channels.values.toList();
    _channels.clear();
    await Future.wait(all.map((c) => c.close()));
  }

  Future<void> forgetAccount(int accountId) async => _channels.remove(accountId)?.close();

  MessageLocation _locate(int id) {
    final loc = messages.locate(id);
    if (loc == null) throw MailOperationException('notFound', 'Messaggio inesistente');
    return loc;
  }

  // ── Corpi ───────────────────────────────────────────────────────────

  /// Scarica, legge e salva il corpo del messaggio [uid] usando [t] (cartella
  /// già selezionata). Restituisce ciò che ha letto, o null se il messaggio
  /// è sparito, troppo grande o illeggibile (lo stato resta registrato).
  Future<ReadMessage?> _fetchAndSave(MailTransport t, int messageId, int uid, int maxBytes) async {
    final Uint8List? raw;
    try {
      raw = await t.fetchRaw(uid, maxBytes: maxBytes);
    } on MailTransportException catch (e) {
      if (e.kind != TransportErrorKind.tooLarge) rethrow;
      messages.setBodyState(messageId, BodyState.tooLarge);
      return null;
    }
    if (raw == null) return null;
    final ReadMessage read;
    try {
      read = await readMessage(raw, timeout: readTimeout, maxBytes: maxBodyBytes);
    } on MessageReadTimeout {
      messages.setBodyState(messageId, BodyState.unreadable);
      return null;
    }
    final hashes = <String>[];
    for (final a in read.attachments) {
      hashes.add(await attachments.put(a.bytes));
    }
    messages.saveBody(messageId, read, hashes);
    return read;
  }

  /// Corpi mancanti dei messaggi più recenti di una cartella, scaricati in
  /// sottofondo dalla sincronizzazione (con la sua connessione, cartella già
  /// selezionata). Sulla Posta in arrivo passa anche il filtro.
  Future<int> prefetchBodies(MailTransport t, int accountId, int folderId,
      {required bool isInbox, int limit = 40}) async {
    final todo = messages.needingBody(folderId, limit: limit);
    if (todo.isEmpty) return 0;
    Set<int> promotions = const {};
    final f = filter;
    if (isInbox && f != null && t.supports('X-GM-EXT-1')) {
      // Gmail ha già classificato i messaggi: una sola ricerca per tutto il
      // lotto, con la stessa estensione che usa Thunderbird.
      final uids = todo.map((m) => m.uid).join(',');
      try {
        promotions = (await t.searchUidsRaw('UID $uids X-GM-RAW "category:promotions"')).toSet();
      } on MailTransportException catch (e) {
        if (e.kind != TransportErrorKind.protocol) rethrow;
      }
    }
    var done = 0;
    final toTrash = <({int id, int uid})>[];
    for (final m in todo) {
      final read = await _fetchAndSave(t, m.id, m.uid, maxAutoBodyBytes);
      if (read == null) continue;
      done++;
      if (isInbox && f != null) {
        final action = _judge(f, accountId, m.id, read, promotions.contains(m.uid));
        if (action == FilterAction.move) toTrash.add(m);
      }
    }
    if (isInbox && onNewMail != null) {
      final moved = {for (final m in toTrash) m.id};
      final since = _clock().subtract(notifyWindow).millisecondsSinceEpoch;
      final fresh = <NewMail>[];
      for (final m in todo) {
        if (moved.contains(m.id)) continue;
        final d = messages.detail(m.id);
        if (d == null || d['bodyState'] != BodyState.saved) continue;
        if (d['seen'] == true || d['adMarked'] == true || (d['date'] as int) < since) continue;
        final from = (d['fromName'] as String?)?.trim();
        fresh.add(NewMail(
          from: (from == null || from.isEmpty) ? (d['fromAddress'] as String? ?? '') : from,
          subject: d['subject'] as String? ?? '',
        ));
      }
      if (fresh.isNotEmpty) onNewMail!(accountId, fresh);
    }
    if (toTrash.isNotEmpty) {
      final trash = messages.folderByRole(accountId, 'trash');
      if (trash != null) {
        await t.moveMessages([for (final m in toTrash) m.uid], trash.path);
        messages.removeLocal([for (final m in toTrash) m.id]);
        onFoldersChanged?.call(accountId, {folderId, trash.id});
      }
    }
    return done;
  }

  FilterAction _judge(AdFilter f, int accountId, int messageId, ReadMessage read, bool promo) {
    final detail = messages.detail(messageId)!;
    final features = MessageFeatures(
      subject: detail['subject'] as String,
      fromAddress: detail['fromAddress'] as String?,
      bodyText: read.textPlain,
      headers: read.headers,
      providerSaysPromotion: promo,
      trackersRemoved: read.html?.trackersRemoved ?? 0,
    );
    final key = (detail['messageId'] as String?)?.trim();
    final v = f.process(
      accountId: accountId,
      messageRowId: messageId,
      messageKey: (key == null || key.isEmpty) ? 'riga:$messageId' : key,
      features: features,
    );
    if (v.action == FilterAction.mark) messages.setAdMarked(messageId, true);
    return v.action;
  }

  /// Il messaggio per la vista di lettura. Se il corpo non c'è ancora lo
  /// scarica ora (anche se grande, fino a [maxBodyBytes]).
  Future<Map<String, Object?>> getMessage(int id, {bool allowRemoteImages = false}) async {
    final loc = _locate(id);
    final state = messages.bodyState(id);
    if (state != BodyState.saved && state != BodyState.unreadable) {
      await _guardServer(() => _channel(loc.accountId).run((t) async {
            await t.selectFolder(loc.path);
            await _fetchAndSave(t, id, loc.uid, maxBodyBytes);
          }));
    }
    final detail = messages.detail(id);
    if (detail == null) throw MailOperationException('notFound', 'Messaggio inesistente');
    final html = detail['html'] as String?;
    if (html != null) {
      final prepared = await _prepareHtml(html, id, allowRemoteImages: allowRemoteImages);
      detail['html'] = prepared.html;
      // href → dominio vero, per avvisare al clic: il testo ricco di Qt non
      // vede gli attributi data-, quindi l'elenco viaggia a parte.
      detail['deceptiveTargets'] = prepared.deceptive;
    }
    return detail;
  }

  /// Ultimi ritocchi all'HTML già sanificato: immagini interne (cid:)
  /// incorporate come data:, immagini remote attivate solo se l'utente l'ha
  /// chiesto per questo messaggio.
  Future<({String html, Map<String, String> deceptive})> _prepareHtml(String html, int messageId,
      {required bool allowRemoteImages}) async {
    final doc = html_parser.parseFragment(html);
    final byCid = <String, Map<String, Object?>>{};
    for (final a in messages.attachments(messageId)) {
      final cid = a['contentId'] as String?;
      if (cid != null) byCid[cid] = a;
    }
    for (final img in doc.querySelectorAll('img')) {
      final src = img.attributes['src'] ?? '';
      if (src.startsWith('liquid-cid:')) {
        final cid = src.substring('liquid-cid:'.length);
        final a = byCid[cid] ?? byCid[Uri.decodeComponent(cid)];
        final mime = a?['mime'] as String? ?? '';
        final size = a?['size'] as int? ?? 0;
        final bytes = (a == null || !mime.startsWith('image/') || size > maxInlineImageBytes)
            ? null
            : await attachments.read(a['sha256'] as String);
        if (bytes == null) {
          img.remove();
        } else {
          img.attributes['src'] = 'data:$mime;base64,${base64.encode(bytes)}';
        }
      }
      final remote = img.attributes['data-liquid-remote-src'];
      if (remote != null) {
        if (allowRemoteImages) {
          img.attributes['src'] = remote;
          img.attributes.remove('data-liquid-remote-src');
        } else {
          // Bloccata: non si manda proprio. Un <img> senza src con larghezza
          // e altezza lascerebbe un riquadro vuoto grande quanto l'immagine
          // (una newsletter si apriva con mezzo schermo bianco). L'avviso
          // "N immagini remote bloccate · Mostra" sta sopra il messaggio.
          img.remove();
        }
      }
    }
    final deceptive = <String, String>{
      for (final a in doc.querySelectorAll('a[data-liquid-deceptive]'))
        if (a.attributes['href'] != null) a.attributes['href']!: a.attributes['data-liquid-deceptive']!,
    };
    return (
      html: doc.nodes.map((n) => n is dom.Element ? n.outerHtml : n.text ?? '').join(),
      deceptive: deceptive,
    );
  }

  // ── Azioni ──────────────────────────────────────────────────────────

  Map<int, List<MessageLocation>> _byFolder(List<int> ids) {
    final out = <int, List<MessageLocation>>{};
    for (final id in ids) {
      final loc = _locate(id);
      out.putIfAbsent(loc.folderId, () => []).add(loc);
    }
    return out;
  }

  Future<T> _guardServer<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on MailTransportException catch (e) {
      throw MailOperationException(
          e.kind.retryable ? 'offline' : 'server', e.message);
    } on AccountException catch (e) {
      throw MailOperationException('offline', e.message);
    }
  }

  /// Segna letti/non letti e importanti. Subito in locale, poi sul server.
  Future<void> setFlags(List<int> ids, {bool? seen, bool? flagged}) async {
    for (final group in _byFolder(ids).values) {
      final loc = group.first;
      final uids = [for (final m in group) m.uid];
      final rows = [for (final m in group) m.messageId];
      Future<void> apply(int mask, bool add) async {
        messages.applyFlags(rows, mask, add: add);
        await _guardServer(() => _channel(loc.accountId).run((t) async {
              await t.selectFolder(loc.path);
              await t.storeFlags(uids, mask, add: add);
            }));
      }

      if (seen != null) await apply(MessageFlags.seen, seen);
      if (flagged != null) await apply(MessageFlags.flagged, flagged);
    }
  }

  /// Sposta in un'altra cartella dello stesso account.
  Future<void> move(List<int> ids, int toFolderId) async {
    final dest = messages.folder(toFolderId);
    if (dest == null) throw MailOperationException('noFolder', 'Cartella di destinazione inesistente');
    for (final group in _byFolder(ids).values) {
      final loc = group.first;
      if (loc.accountId != dest.accountId) {
        throw MailOperationException('noFolder', 'La cartella è di un altro account');
      }
      if (loc.folderId == toFolderId) continue;
      await _guardServer(() => _channel(loc.accountId).run((t) async {
            await t.selectFolder(loc.path);
            await t.moveMessages([for (final m in group) m.uid], dest.path);
          }));
      messages.removeLocal([for (final m in group) m.messageId]);
      onFoldersChanged?.call(loc.accountId, {loc.folderId, toFolderId});
    }
  }

  /// Nel Cestino; dal Cestino, cancellati per sempre.
  Future<void> delete(List<int> ids) async {
    for (final group in _byFolder(ids).values) {
      final loc = group.first;
      final rows = [for (final m in group) m.messageId];
      final uids = [for (final m in group) m.uid];
      final trash = messages.folderByRole(loc.accountId, 'trash');
      if (loc.role == 'trash' || trash == null) {
        await _guardServer(() => _channel(loc.accountId).run((t) async {
              await t.selectFolder(loc.path);
              await t.deleteMessages(uids);
            }));
        messages.removeLocal(rows);
        onFoldersChanged?.call(loc.accountId, {loc.folderId});
      } else {
        await move(rows, trash.id);
      }
    }
  }

  /// Fuori dalla Posta in arrivo: nella cartella Archivio (con Gmail, "Tutti
  /// i messaggi", dove l'email resta comunque).
  Future<void> archive(List<int> ids) async {
    for (final group in _byFolder(ids).values) {
      final loc = group.first;
      final archive = messages.folderByRole(loc.accountId, 'archive');
      if (archive == null) {
        throw MailOperationException('noFolder', 'Questo account non ha una cartella Archivio');
      }
      await move([for (final m in group) m.messageId], archive.id);
    }
  }

  /// Copia un allegato in [destination] (percorso assoluto scelto
  /// dall'utente). Non sovrascrive un file esistente.
  Future<String> saveAttachment(int attachmentId, String destination) async {
    final a = messages.attachment(attachmentId);
    if (a == null) throw MailOperationException('notFound', 'Allegato inesistente');
    if (!destination.startsWith('/') || destination.contains('\u0000')) {
      throw MailOperationException('invalidPath', 'Serve un percorso assoluto');
    }
    final file = File(destination);
    if (await file.exists()) {
      throw MailOperationException('exists', 'Esiste già un file con questo nome');
    }
    final bytes = await attachments.read(a['sha256'] as String);
    if (bytes == null) throw MailOperationException('notFound', 'Allegato non più in archivio');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return destination;
  }

  // ── Invio ───────────────────────────────────────────────────────────

  static const _mimeByExtension = {
    'pdf': 'application/pdf', 'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
    'gif': 'image/gif', 'webp': 'image/webp', 'txt': 'text/plain', 'zip': 'application/zip',
    'doc': 'application/msword', 'odt': 'application/vnd.oasis.opendocument.text',
    'ods': 'application/vnd.oasis.opendocument.spreadsheet',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'mp3': 'audio/mpeg', 'mp4': 'video/mp4', 'csv': 'text/csv', 'ics': 'text/calendar',
  };

  List<String> _addresses(List<String> raw, String field) {
    final out = <String>[];
    for (final a in raw) {
      final n = normalizeAddress(a);
      if (n == null) throw MailOperationException('invalidAddress', 'Indirizzo non valido in $field: $a');
      out.add(n);
    }
    return out;
  }

  /// Gmail salva da solo una copia di ogni messaggio inviato in "Posta
  /// inviata": aggiungerla noi la duplicherebbe (Thunderbird fa lo stesso).
  static bool _savesSentItself(AccountRecord a) =>
      a.provider == 'gmail' ||
      a.imapHost == 'imap.gmail.com' ||
      a.imapHost == 'imap.googlemail.com';

  /// Compone e spedisce. Restituisce `{refused, savedToSent}`: i destinatari
  /// che il server ha rifiutato (gli altri l'hanno ricevuto) e se la copia è
  /// in Inviata.
  Future<Map<String, Object?>> send({
    required int accountId,
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    required String subject,
    required String text,
    int? replyToId,
    List<String> attachmentPaths = const [],
  }) async {
    final account = store.getAccount(accountId);
    if (account == null) throw MailOperationException('notFound', 'Account inesistente');
    final toA = _addresses(to, 'A');
    final ccA = _addresses(cc, 'Cc');
    final bccA = _addresses(bcc, 'Ccn');
    final all = {...toA, ...ccA, ...bccA};
    if (all.isEmpty) throw MailOperationException('invalidAddress', 'Serve almeno un destinatario');
    if (all.length > 100) throw MailOperationException('invalidAddress', 'Al massimo 100 destinatari');

    final attachmentsOut = <OutgoingAttachment>[];
    var total = 0;
    for (final path in attachmentPaths) {
      final f = File(path);
      if (!path.startsWith('/') || FileSystemEntity.typeSync(path) != FileSystemEntityType.file) {
        throw MailOperationException('invalidPath', 'Allegato non trovato: $path');
      }
      total += await f.length();
      if (total > maxAttachmentBytes) {
        throw MailOperationException('tooLarge',
            'Allegati oltre ${maxAttachmentBytes ~/ (1024 * 1024)} MB: troppo grandi per la posta');
      }
      final name = path.split('/').last;
      final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
      attachmentsOut.add(OutgoingAttachment(
          name, _mimeByExtension[ext] ?? 'application/octet-stream', await f.readAsBytes()));
    }

    MessageLocation? original;
    String? inReplyTo;
    if (replyToId != null) {
      original = _locate(replyToId);
      inReplyTo = (messages.detail(replyToId)?['messageId'] as String?)?.trim();
    }
    final composed = composer.compose(OutgoingMessage(
      fromAddress: account.email,
      fromName: account.name == account.email ? null : account.name,
      to: toA,
      cc: ccA,
      bcc: bccA,
      subject: subject,
      text: text,
      inReplyTo: (inReplyTo == null || inReplyTo.isEmpty) ? null : inReplyTo,
      attachments: attachmentsOut,
    ));

    final config = await accounts.transportConfigFor(accountId, smtp: true);
    if (config == null) throw MailOperationException('offline', 'Password non presente nel portachiavi');
    final List<String> refused;
    try {
      refused = await smtpSend(config, account.email, all.toList(), composed.raw);
    } on SendException catch (e) {
      throw MailOperationException(e.failure.name, e.message);
    }

    // Da qui in poi il messaggio è partito: un errore nel salvare la copia o
    // nel segnare "risposto" non deve far credere all'utente che non sia
    // stato inviato.
    var savedToSent = _savesSentItself(account);
    final sent = messages.folderByRole(accountId, 'sent');
    if (!savedToSent && sent != null) {
      try {
        await _channel(accountId).run((t) => t.append(sent.path, composed.raw, flags: MessageFlags.seen));
        savedToSent = true;
        onFoldersChanged?.call(accountId, {sent.id});
      } on Object catch (e) {
        stderr.writeln('[posta] copia in Inviata non riuscita: $e');
      }
    }
    if (original != null) {
      try {
        messages.applyFlags([original.messageId], MessageFlags.answered, add: true);
        final o = original;
        await _channel(accountId).run((t) async {
          await t.selectFolder(o.path);
          await t.storeFlags([o.uid], MessageFlags.answered, add: true);
        });
      } on Object catch (e) {
        stderr.writeln('[posta] segno "risposto" non riuscito: $e');
      }
    }
    return {'refused': refused, 'savedToSent': savedToSent, 'messageId': composed.messageId};
  }
}
