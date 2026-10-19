import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:enough_mail_plus/enough_mail.dart' as em;

import '../db/mail_store.dart';
import 'mail_transport.dart';

/// [MailTransport] basato su `enough_mail_plus`.
///
/// Questo è l'UNICO file del daemon che importa la libreria IMAP.
class EnoughImapTransport implements MailTransport {
  EnoughImapTransport(this.config);

  final TransportConfig config;
  em.ImapClient? _client;
  StreamController<TransportEvent>? _watchController;
  StreamSubscription<em.ImapEvent>? _eventSub;
  Timer? _idleRefreshTimer;
  bool _watching = false;

  /// Operazioni in corso, interrompibili da [abort]. Ognuna si registra e
  /// si toglie appena finisce: nulla resta agganciato a lungo. (Un unico
  /// Future "di interruzione" con un ascoltatore per comando tratteneva ogni
  /// risultato per tutta la vita della connessione: perdita trovata con
  /// tool/leak_check.dart.)
  final Set<void Function()> _aborters = {};
  bool _aborted = false;

  Future<T> _abortable<T>(Future<T> f, String what) {
    if (_aborted) {
      return Future.error(
          MailTransportException(TransportErrorKind.connectionLost, 'Connessione interrotta ($what)'));
    }
    final c = Completer<T>();
    void abort() {
      if (!c.isCompleted) {
        c.completeError(
            MailTransportException(TransportErrorKind.connectionLost, 'Connessione interrotta ($what)'));
      }
    }

    _aborters.add(abort);
    f.then((v) {
      if (!c.isCompleted) c.complete(v);
    }, onError: (Object e, StackTrace st) {
      if (!c.isCompleted) c.completeError(e, st);
    }).whenComplete(() => _aborters.remove(abort));
    return c.future;
  }

  /// Cartella selezionata. È lo stesso oggetto che la libreria aggiorna
  /// quando arrivano risposte EXISTS, quindi il conteggio resta attuale.
  em.Mailbox? _selected;

  em.ImapClient get _requireClient {
    final c = _client;
    if (c == null || !c.isConnected) {
      throw MailTransportException(
          TransportErrorKind.connectionLost, 'Non connesso al server');
    }
    return c;
  }

  @override
  bool get isConnected => _client?.isConnected ?? false;

  @override
  Future<void> connect() async {
    if (isConnected) return;
    _aborted = false;
    String? presentedFingerprint;
    final trusted = config.trustedCertSha256?.toLowerCase();
    final client = _connecting = _SafeImapClient(
      defaultResponseTimeout: config.responseTimeout,
      securityContext: config.securityContext,
      // Chiamato SOLO quando la verifica normale fallisce. Si accetta
      // esclusivamente il certificato che l'utente ha approvato per impronta;
      // in ogni altro caso la connessione cade prima di inviare la password.
      onBadCertificate: (cert) {
        final fp = sha256.convert(cert.der).toString();
        presentedFingerprint = fp;
        return trusted != null && _constantTimeEquals(fp, trusted);
      },
    );
    final where = '${config.host}:${config.port}';
    Future<T> abortable<T>(Future<T> f) => _abortable(f, where);

    // Fase 1: canale cifrato.
    try {
      // Il timeout interno della libreria copre solo l'apertura del socket;
      // quello esterno copre anche il saluto del server, che altrimenti
      // potrebbe non arrivare mai e bloccare il daemon per sempre.
      await abortable(client
          .connectToServer(config.host, config.port,
              isSecure: config.security == ConnectionSecurity.tls,
              timeout: config.connectTimeout)
          .timeout(config.connectTimeout));
      if (config.security == ConnectionSecurity.starttls) {
        await abortable(_upgradeWithStartTls(client));
      }
    } catch (e) {
      await _quietDisconnect(client);
      final error = _translate(e, phase: 'connessione a $where');
      if (error.kind == TransportErrorKind.tlsUntrusted) {
        throw MailTransportException(error.kind, error.message,
            cause: error.cause, certificateSha256: presentedFingerprint);
      }
      throw error;
    }

    // Fase 2: autenticazione, solo dopo che il canale è cifrato e verificato.
    try {
      final token = config.accessToken;
      await abortable((token != null
              ? client.authenticateWithOAuth2(config.username, token)
              : client.login(config.username, config.password))
          .timeout(config.responseTimeout));
    } catch (e) {
      await _quietDisconnect(client);
      // Durante il LOGIN la libreria lancia ImapException solo per una
      // risposta NO/BAD del server (o per il suo timeout interno). Il rifiuto
      // resta un errore di credenziali anche se il server chiude subito dopo,
      // come fa Gmail: guardare isConnected qui, dopo la disconnessione, lo
      // faceva diventare «Connessione persa».
      if (e is em.ImapException && e.message != 'timeout') {
        final reply = '${e.message} ${e.details}'.toUpperCase();
        if (reply.contains('APPLICATION-SPECIFIC PASSWORD')) {
          throw MailTransportException(TransportErrorKind.appPasswordRequired,
              'Il server vuole una password per le app, non quella dell\'account', cause: e);
        }
        throw MailTransportException(TransportErrorKind.authFailed,
            'Nome utente o password non accettati', cause: e);
      }
      throw _translate(e, phase: 'login su $where');
    }
    _client = client;
    _connecting = null;
  }

  /// Client in fase di connessione (non ancora in [_client]).
  em.ImapClient? _connecting;

  /// STARTTLS senza possibilità di ripiego in chiaro (RFC 3501 §6.2.1,
  /// RFC 8314). Le capability ricevute prima di TLS potrebbero essere state
  /// alterate da chi sta in mezzo: dopo l'upgrade vengono richieste di nuovo.
  Future<void> _upgradeWithStartTls(em.ImapClient client) async {
    await client.capability().timeout(config.responseTimeout);
    if (!client.serverInfo.supportsStartTls) {
      throw MailTransportException(TransportErrorKind.tlsUntrusted,
          'Il server non offre STARTTLS: connessione interrotta per non '
          'inviare la password in chiaro');
    }
    await client.startTls().timeout(config.responseTimeout);
    await client.capability().timeout(config.responseTimeout);
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  @override
  Future<List<RemoteFolder>> listFolders() => _guard('elenco cartelle', () async {
        final boxes = await _requireClient.listMailboxes(recursive: true);
        return [
          for (final b in boxes)
            if (!b.isNotSelectable) RemoteFolder(b.path, _roleOf(b)),
        ];
      });

  @override
  Future<FolderStatus> selectFolder(String path) =>
      _guard('apertura cartella $path', () async {
        final box = await _requireClient.selectMailboxByPath(path,
            enableCondStore: true);
        _selected = box;
        final uidValidity = box.uidValidity;
        if (uidValidity == null) {
          throw MailTransportException(TransportErrorKind.protocol,
              'Il server non ha comunicato UIDVALIDITY per $path');
        }
        return FolderStatus(
          path: box.path,
          uidValidity: uidValidity,
          uidNext: box.uidNext ?? 1,
          exists: box.messagesExists,
          highestModseq: box.highestModSequence,
        );
      });

  @override
  Future<List<MessageRecord>> fetchHeaders({int fromUid = 1}) async {
    // Errori del chiamante: controllati fuori da _guard, che altrimenti li
    // scambierebbe per una connessione persa e chiuderebbe il socket.
    // Tutti i metodi sono async: qualunque errore, anche "connessione persa"
    // prima di cominciare, arriva dentro il Future e mai in modo sincrono.
    if (fromUid < 1) {
      throw ArgumentError.value(fromUid, 'fromUid', 'deve essere >= 1');
    }
    _requireClient;
    final selected = _selected;
    if (selected == null) throw StateError('Nessuna cartella selezionata');
    return await _guard('scaricamento intestazioni', () async {
        final client = _requireClient;
        if (selected.messagesExists == 0) return [];
        final result = await client.uidFetchMessages(
            em.MessageSequence.fromRangeToLast(fromUid, isUidSequence: true),
            '(UID FLAGS ENVELOPE)');
        return [
          for (final m in result.messages)
            // RFC 3501: "N:*" con N oltre l'ultimo UID viene letto come "*:N"
            // e restituisce comunque l'ultimo messaggio. Va scartato, altrimenti
            // ogni sync incrementale riscarica l'ultima email.
            if ((m.uid ?? 0) >= fromUid) _toRecord(m),
        ];
      });
  }

  @override
  bool get supportsCondstore {
    final info = _client?.serverInfo;
    return info != null && (info.supports('CONDSTORE') || info.supports('QRESYNC'));
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// Formato data di IMAP SEARCH (RFC 3501): "1-Oct-2026", mesi in inglese
  /// qualunque sia la lingua del sistema.
  static String imapDate(DateTime d) => '${d.day}-${_months[d.month - 1]}-${d.year}';

  @override
  Future<List<int>> searchUids({DateTime? since}) async {
    _requireClient; // prima la connessione: dopo un disconnect è 'connessione persa'
    if (_selected == null) throw StateError('Nessuna cartella selezionata');
    return await _guard('ricerca messaggi', () async {
      final result = await _requireClient.uidSearchMessages(
          searchCriteria: since == null ? 'ALL' : 'SINCE ${imapDate(since)}');
      return result.matchingSequence?.toList() ?? const [];
    });
  }

  @override
  Future<List<MessageRecord>> fetchHeadersByUids(List<int> uids) async {
    _requireClient; // prima la connessione: dopo un disconnect è 'connessione persa'
    if (_selected == null) throw StateError('Nessuna cartella selezionata');
    if (uids.isEmpty) return const [];
    return await _guard('scaricamento intestazioni', () async {
      final result = await _requireClient.uidFetchMessages(
          em.MessageSequence.fromIds(uids, isUid: true), '(UID FLAGS ENVELOPE)');
      final wanted = uids.toSet();
      return [
        for (final m in result.messages)
          if (m.uid != null && wanted.contains(m.uid)) _toRecord(m),
      ];
    });
  }

  @override
  Future<Map<int, int>> fetchFlags({List<int>? uids, int? changedSince}) async {
    _requireClient; // prima la connessione: dopo un disconnect è 'connessione persa'
    if (_selected == null) throw StateError('Nessuna cartella selezionata');
    if (changedSince == null && (uids == null || uids.isEmpty)) {
      return const {};
    }
    if (changedSince != null && !supportsCondstore) {
      throw StateError('changedSince richiede CONDSTORE');
    }
    return await _guard('scaricamento flag', () async {
      final sequence = changedSince != null
          ? em.MessageSequence.fromRangeToLast(1, isUidSequence: true)
          : em.MessageSequence.fromIds(uids!, isUid: true);
      // La libreria non conosce CHANGEDSINCE: il modificatore (RFC 7162)
      // viene aggiunto dopo l'elenco degli attributi richiesti.
      final definition =
          changedSince != null ? '(UID FLAGS) (CHANGEDSINCE $changedSince)' : '(UID FLAGS)';
      final result = await _requireClient.uidFetchMessages(sequence, definition);
      return {
        for (final m in result.messages)
          if (m.uid != null) m.uid!: _flagsOf(m.flags),
      };
    });
  }

  @override
  Future<Uint8List?> fetchRaw(int uid, {required int maxBytes}) async {
    _requireClient; // prima la connessione: dopo un disconnect è 'connessione persa'
    if (_selected == null) throw StateError('Nessuna cartella selezionata');
    return await _guard('scaricamento messaggio $uid', () async {
      final client = _requireClient;
      final sizes = await client.uidFetchMessage(uid, '(UID RFC822.SIZE)');
      final info = sizes.messages.where((m) => m.uid == uid).firstOrNull;
      if (info == null) return null;
      final size = info.size;
      if (size == null || size > maxBytes) {
        throw MailTransportException(TransportErrorKind.tooLarge,
            'Messaggio di ${size ?? '?'} byte, oltre il massimo di $maxBytes');
      }
      // BODY.PEEK e non BODY: leggere per l'anteprima o l'indice non deve
      // segnare il messaggio come letto sul server.
      final result = await client.uidFetchMessage(uid, '(UID BODY.PEEK[])');
      final m = result.messages.where((m) => m.uid == uid).firstOrNull;
      if (m == null) return null;
      return switch (m.mimeData) {
        em.BinaryMimeData(:final data) => data,
        // La libreria a volte consegna il letterale come testo: i byte
        // originali sono i codici dei caratteri (ISO-8859-1 è 1:1 sui byte).
        em.TextMimeData(:final text) => Uint8List.fromList(
            text.codeUnits.every((c) => c < 256) ? latin1.encode(text) : utf8.encode(text)),
        _ => null,
      };
    });
  }

  static List<String> _flagNames(int mask) => [
        if (mask & MessageFlags.seen != 0) r'\Seen',
        if (mask & MessageFlags.answered != 0) r'\Answered',
        if (mask & MessageFlags.flagged != 0) r'\Flagged',
        if (mask & MessageFlags.deleted != 0) r'\Deleted',
        if (mask & MessageFlags.draft != 0) r'\Draft',
      ];

  @override
  Future<void> storeFlags(List<int> uids, int flags, {required bool add}) async {
    _requireClient;
    if (_selected == null) throw StateError('Nessuna cartella selezionata');
    final names = _flagNames(flags);
    if (uids.isEmpty || names.isEmpty) return;
    await _guard('aggiornamento flag', () => _requireClient.uidStore(
        em.MessageSequence.fromIds(uids, isUid: true), names,
        action: add ? em.StoreAction.add : em.StoreAction.remove, silent: true));
  }

  @override
  Future<void> moveMessages(List<int> uids, String toPath) async {
    _requireClient;
    if (_selected == null) throw StateError('Nessuna cartella selezionata');
    if (uids.isEmpty) return;
    final sequence = em.MessageSequence.fromIds(uids, isUid: true);
    await _guard('spostamento in $toPath', () async {
      final client = _requireClient;
      if (client.serverInfo.supports('MOVE')) {
        await client.uidMove(sequence, targetMailboxPath: toPath);
        return;
      }
      // Senza MOVE: copia, poi cancella SOLO i messaggi copiati. Un EXPUNGE
      // semplice toglierebbe anche altri messaggi segnati \Deleted da un
      // altro client; senza UIDPLUS non c'è modo sicuro, e si lascia la
      // copia originale segnata come cancellata (la vedrà sparire il server).
      await client.uidCopy(sequence, targetMailboxPath: toPath);
      await client.uidStore(sequence, [r'\Deleted'], action: em.StoreAction.add, silent: true);
      if (client.serverInfo.supports('UIDPLUS')) await client.uidExpunge(sequence);
    });
  }

  @override
  Future<void> deleteMessages(List<int> uids) async {
    _requireClient;
    if (_selected == null) throw StateError('Nessuna cartella selezionata');
    if (uids.isEmpty) return;
    final sequence = em.MessageSequence.fromIds(uids, isUid: true);
    await _guard('cancellazione', () async {
      final client = _requireClient;
      await client.uidStore(sequence, [r'\Deleted'], action: em.StoreAction.add, silent: true);
      if (client.serverInfo.supports('UIDPLUS')) await client.uidExpunge(sequence);
    });
  }

  @override
  Future<void> append(String path, Uint8List raw, {int flags = 0}) async {
    _requireClient;
    await _guard('salvataggio in $path', () => _requireClient.appendMessageText(
        latin1.decode(raw), flags: _flagNames(flags), targetMailboxPath: path));
  }

  @override
  Future<List<int>> searchUidsRaw(String criteria) async {
    _requireClient;
    if (_selected == null) throw StateError('Nessuna cartella selezionata');
    return await _guard('ricerca $criteria', () async {
      final result = await _requireClient.uidSearchMessages(searchCriteria: criteria);
      return result.matchingSequence?.toList() ?? const <int>[];
    });
  }

  @override
  bool supports(String capability) => _client?.serverInfo.supports(capability) ?? false;

  @override
  Stream<TransportEvent> watch() {
    final client = _client;
    if (client == null || !client.isConnected) {
      // Connessione già persa: stesso esito di una caduta durante l'IDLE,
      // invece di un'eccezione sincrona che il chiamante non si aspetta.
      return Stream.value(const ConnectionLostEvent());
    }
    if (_selected == null) {
      // La libreria in questo caso stampa un avviso e non fa nulla: meglio
      // un errore esplicito che un IDLE che non arriva mai.
      throw StateError('watch() richiede una cartella selezionata');
    }
    if (_watching) throw StateError('watch() già attivo');
    _watching = true;

    final controller = StreamController<TransportEvent>();
    _watchController = controller;
    _eventSub = client.eventStream.listen((event) {
      if (event is em.ImapMessagesExistEvent &&
          event.newMessagesExists > event.oldMessagesExists) {
        controller.add(NewMailEvent(event.newMessagesExists));
      } else if (event is em.ImapMessagesExistEvent ||
          event is em.ImapMessagesRecentEvent ||
          event is em.ImapExpungeEvent ||
          event is em.ImapVanishedEvent ||
          event is em.ImapFetchEvent) {
        // Qualsiasi altra notifica del server può nascondere una novità:
        // dopo una cancellazione la libreria non riduce il conteggio, e una
        // nuova email arriva come EXISTS "uguale" o solo come RECENT. Meglio
        // una sync in più (con CONDSTORE costa pochissimo) che una email persa.
        controller.add(const MailboxChangedEvent());
      } else if (event is em.ImapConnectionLostEvent) {
        _endWatch(lost: true);
      }
    });
    // Se il socket muore senza che la libreria emetta l'evento (server
    // ucciso di colpo), ce ne accorgiamo al rinnovo dell'IDLE.
    _idleRefreshTimer = Timer.periodic(config.idleRefresh, (_) => _refreshIdle());

    client.idleStart(waitForContinuation: true).timeout(config.responseTimeout).catchError(
        (Object e) => _endWatch(lost: true));
    return controller.stream;
  }

  Future<void> _refreshIdle() async {
    final client = _client;
    if (client == null || !_watching) return;
    try {
      // idleDone() attende la conferma del server (tagged OK): se arriva entro
      // il timeout la connessione è viva. È anche ciò che rileva le connessioni
      // mezze aperte dopo sospensione o cambio rete (test con proxy congelato),
      // quindi un NOOP aggiuntivo sarebbe solo un giro di rete in più.
      await client.idleDone().timeout(config.responseTimeout);
      await client.idleStart(waitForContinuation: true).timeout(config.responseTimeout);
    } catch (_) {
      _endWatch(lost: true);
    }
  }

  void _endWatch({required bool lost}) {
    if (!_watching) return;
    _watching = false;
    _idleRefreshTimer?.cancel();
    _idleRefreshTimer = null;
    _eventSub?.cancel();
    _eventSub = null;
    final controller = _watchController;
    _watchController = null;
    if (controller != null) {
      if (lost) controller.add(const ConnectionLostEvent());
      controller.close();
    }
    if (lost) {
      final c = _client;
      _client = null;
      if (c != null) _quietDisconnect(c);
    }
  }

  @override
  Future<void> stopWatching() async {
    if (!_watching) return;
    final client = _client;
    _endWatch(lost: false);
    if (client != null && client.isConnected) {
      try {
        await client.idleDone().timeout(config.responseTimeout);
      } catch (_) {
        // La connessione verrà chiusa o ricreata dal chiamante.
      }
    }
  }

  @override
  Future<void> abort() async {
    _aborted = true;
    for (final a in _aborters.toList()) {
      a();
    }
    final pending = _connecting;
    _connecting = null;
    if (pending != null) unawaited(_quietDisconnect(pending));
    _endWatch(lost: false);
    final c = _client;
    _client = null;
    _selected = null;
    if (c == null) return;
    try {
      // Nessun LOGOUT e un tempo minimo: su una rete morta anche la
      // chiusura del socket TLS può restare appesa; il sistema la completa.
      await c.disconnect().timeout(const Duration(milliseconds: 200));
    } catch (_) {}
  }

  @override
  Future<void> disconnect() async {
    _endWatch(lost: false);
    final c = _client;
    _client = null;
    _selected = null;
    if (c == null) return;
    try {
      await c.logout().timeout(const Duration(seconds: 3));
    } catch (_) {
      // Logout cortese fallito: chiudiamo comunque il socket.
    }
    await _quietDisconnect(c);
  }

  Future<T> _guard<T>(String phase, Future<T> Function() action) async {
    try {
      return await _abortable(action(), phase).timeout(config.responseTimeout);
    } on MailTransportException {
      rethrow;
    } on ArgumentError {
      rethrow;
    } catch (e) {
      final error = _translate(e, phase: phase);
      if (error.kind == TransportErrorKind.connectionLost ||
          error.kind == TransportErrorKind.timeout) {
        final c = _client;
        _client = null;
        if (c != null) await _quietDisconnect(c);
      }
      throw error;
    }
  }

  /// Traduce le eccezioni di rete e della libreria nei nostri tipi.
  /// I messaggi sono costruiti qui: non contengono mai testo del server
  /// grezzo che potrebbe includere la riga di LOGIN con la password.
  MailTransportException _translate(Object e, {required String phase}) {
    if (e is MailTransportException) return e;
    if (e is TimeoutException) {
      return MailTransportException(TransportErrorKind.timeout,
          'Il server non ha risposto in tempo ($phase)', cause: e);
    }
    if (e is HandshakeException || e is TlsException) {
      return MailTransportException(TransportErrorKind.tlsUntrusted,
          'Certificato del server non valido o non fidato ($phase)', cause: e);
    }
    if (e is SocketException) {
      return MailTransportException(
          _client == null ? TransportErrorKind.unreachable : TransportErrorKind.connectionLost,
          'Server non raggiungibile ($phase)',
          cause: e);
    }
    if (e is em.ImapException) {
      // Gli errori di credenziali sono decisi solo nella fase di login di
      // connect(): qui un rifiuto del server è sempre un errore di protocollo.
      if (!(e.imapClient.isConnected)) {
        return MailTransportException(TransportErrorKind.connectionLost,
            'Connessione persa ($phase)', cause: e);
      }
      return MailTransportException(TransportErrorKind.protocol,
          'Il server ha rifiutato l\'operazione ($phase)', cause: e);
    }
    if (e is StateError || e is em.InvalidArgumentException) {
      return MailTransportException(TransportErrorKind.connectionLost,
          'Connessione persa ($phase)', cause: e);
    }
    return MailTransportException(
        TransportErrorKind.protocol, 'Errore imprevisto ($phase)', cause: e);
  }

  static Future<void> _quietDisconnect(em.ImapClient client) async {
    try {
      await client.disconnect().timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  static String _roleOf(em.Mailbox b) {
    if (b.isInbox) return 'inbox';
    if (b.isSent) return 'sent';
    if (b.isDrafts) return 'drafts';
    if (b.isJunk) return 'spam';
    if (b.isTrash) return 'trash';
    if (b.isArchive) return 'archive';
    return 'other';
  }

  static int _flagsOf(List<String>? flags) {
    var mask = 0;
    for (final f in flags ?? const <String>[]) {
      switch (f.toLowerCase()) {
        case r'\seen':
          mask |= MessageFlags.seen;
        case r'\answered':
          mask |= MessageFlags.answered;
        case r'\flagged':
          mask |= MessageFlags.flagged;
        case r'\deleted':
          mask |= MessageFlags.deleted;
        case r'\draft':
          mask |= MessageFlags.draft;
      }
    }
    return mask;
  }

  static MessageRecord _toRecord(em.MimeMessage m) {
    final env = m.envelope;
    final from = env?.from?.isNotEmpty == true ? env!.from!.first : null;
    return MessageRecord(
      uid: m.uid!,
      date: env?.date ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      messageId: env?.messageId,
      inReplyTo: env?.inReplyTo,
      fromAddress: from?.email,
      fromName: from?.personalName,
      to: [for (final a in env?.to ?? const <em.MailAddress>[]) a.email],
      cc: [for (final a in env?.cc ?? const <em.MailAddress>[]) a.email],
      subject: env?.subject ?? '',
      flags: _flagsOf(m.flags),
    );
  }
}

/// [em.ImapClient] che non va in crash per un evento tardivo.
///
/// Dopo un EXISTS o un RECENT (per esempio la risposta a un MOVE o a un
/// APPEND), la libreria notifica l'evento con 100 ms di ritardo. Se nel
/// frattempo la connessione è stata chiusa, il canale degli eventi è già
/// chiuso e la notifica lancia uno StateError in un Future che nessuno
/// aspetta: nel daemon è un'eccezione non gestita, cioè il crash del
/// processo. Trovato con il test di moveMessages (enough_mail_plus 2.2.4).
/// Un evento per una connessione chiusa non interessa più a nessuno: si scarta.
class _SafeImapClient extends em.ImapClient {
  _SafeImapClient({
    super.defaultResponseTimeout,
    super.onBadCertificate,
    super.securityContext,
  });

  @override
  void fireEvent(em.ImapEvent event) {
    try {
      super.fireEvent(event);
    } on StateError {
      // canale degli eventi già chiuso: connessione terminata
    }
  }
}
