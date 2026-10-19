import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../db/mail_store.dart';

/// Categoria di un errore di trasporto: è ciò che la UI mostra all'utente
/// e ciò che decide se riprovare.
enum TransportErrorKind {
  /// Credenziali rifiutate. Riprovare non serve: va chiesto all'utente.
  authFailed(retryable: false),

  /// Il provider rifiuta la password dell'account e vuole quella dedicata
  /// alla posta (Gmail con la verifica in due passaggi).
  appPasswordRequired(retryable: false),

  /// Certificato non valido o non fidato. Mai riprovare in automatico.
  tlsUntrusted(retryable: false),

  /// Server spento, DNS errato, rete assente.
  unreachable(retryable: true),

  /// Il server non risponde entro il tempo previsto.
  timeout(retryable: true),

  /// Connessione caduta durante l'uso.
  connectionLost(retryable: true),

  /// Risposta inattesa o comando rifiutato dal server.
  protocol(retryable: false),

  /// Il messaggio supera la dimensione massima accettata: non lo si scarica.
  tooLarge(retryable: false);

  const TransportErrorKind({required this.retryable});
  final bool retryable;
}

class MailTransportException implements Exception {
  MailTransportException(this.kind, this.message,
      {this.cause, this.certificateSha256});

  final TransportErrorKind kind;
  final String message;
  final Object? cause;

  /// Solo per [TransportErrorKind.tlsUntrusted]: impronta SHA-256 del
  /// certificato presentato, da mostrare all'utente perché decida se fidarsi
  /// (server personale, Proton Mail Bridge).
  final String? certificateSha256;

  @override
  String toString() => 'MailTransportException(${kind.name}): $message';
}

/// Come viene cifrata la connessione. Non esiste un'opzione "in chiaro":
/// la password non viaggia mai senza TLS.
enum ConnectionSecurity {
  /// TLS dal primo byte (porta 993 per IMAP, 465 per SMTP).
  tls,

  /// Connessione in chiaro che passa a TLS prima del login (143, 587).
  /// Se il server non offre STARTTLS la connessione viene rifiutata.
  starttls,
}

/// Parametri di connessione. La password arriva da libsecret al momento
/// della connessione e non viene salvata altrove.
class TransportConfig {
  const TransportConfig({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    this.accessToken,
    this.security = ConnectionSecurity.tls,
    this.trustedCertSha256,
    this.securityContext,
    this.connectTimeout = const Duration(seconds: 20),
    this.responseTimeout = const Duration(seconds: 60),
    this.idleRefresh = const Duration(minutes: 25),
  });

  final String host;
  final int port;
  final String username;
  final String password;

  /// Token OAuth 2.0 (Gmail con «Accedi con Google»). Se c'è, l'accesso usa
  /// XOAUTH2 e [password] è vuota.
  final String? accessToken;
  final ConnectionSecurity security;

  /// Impronta SHA-256 (esadecimale) di un certificato che l'utente ha deciso
  /// esplicitamente di accettare anche se non firmato da una CA riconosciuta.
  /// Si aggiunge alle CA di sistema, non le sostituisce.
  final String? trustedCertSha256;

  /// null = CA di sistema. Nei test: solo la CA di prova.
  final SecurityContext? securityContext;

  /// Tempo massimo per TCP + TLS + saluto del server.
  final Duration connectTimeout;

  /// Tempo massimo di risposta a un singolo comando.
  final Duration responseTimeout;

  /// RFC 2177: i server chiudono un IDLE dopo 30 minuti; lo rinnoviamo prima.
  final Duration idleRefresh;
}

class RemoteFolder {
  const RemoteFolder(this.path, this.role);
  final String path;

  /// 'inbox', 'sent', 'drafts', 'spam', 'trash', 'archive' o 'other'.
  final String role;
}

class FolderStatus {
  const FolderStatus({
    required this.path,
    required this.uidValidity,
    required this.uidNext,
    required this.exists,
    this.highestModseq,
  });

  final String path;
  final int uidValidity;
  final int uidNext;
  final int exists;
  final int? highestModseq;
}

sealed class TransportEvent {
  const TransportEvent();
}

/// Il numero di messaggi nella cartella osservata è cambiato in aumento.
class NewMailEvent extends TransportEvent {
  const NewMailEvent(this.exists);
  final int exists;
}

/// La cartella osservata è cambiata in un modo che richiede una sync:
/// messaggi cancellati, flag modificati da un altro dispositivo, oppure un
/// EXISTS che non mostra un aumento (es. 4 → 3 → 4 dopo una cancellazione).
class MailboxChangedEvent extends TransportEvent {
  const MailboxChangedEvent();
}

/// La connessione usata per l'IDLE si è interrotta.
class ConnectionLostEvent extends TransportEvent {
  const ConnectionLostEvent();
}

/// Contratto che il resto del daemon usa per parlare con un server di posta.
/// Nessun altro file importa direttamente la libreria IMAP: sostituirla
/// significa scrivere una nuova implementazione di questa interfaccia.
abstract interface class MailTransport {
  bool get isConnected;

  /// Connessione e login. Lancia [MailTransportException].
  Future<void> connect();

  Future<List<RemoteFolder>> listFolders();

  Future<FolderStatus> selectFolder(String path);

  /// Intestazioni dei messaggi con UID da [fromUid] in su nella cartella
  /// selezionata.
  Future<List<MessageRecord>> fetchHeaders({int fromUid = 1});

  /// UID presenti nella cartella selezionata; con [since] solo quelli
  /// consegnati da quella data (INTERNALDATE, non l'intestazione Date che il
  /// mittente può falsificare).
  Future<List<int>> searchUids({DateTime? since});

  /// Intestazioni di UID precisi. UID inesistenti vengono ignorati.
  Future<List<MessageRecord>> fetchHeadersByUids(List<int> uids);

  /// Flag (bitmask di [MessageFlags]) per UID.
  /// Con [changedSince] (CONDSTORE) solo i messaggi modificati da quel
  /// MODSEQ; altrimenti per gli [uids] indicati.
  Future<Map<int, int>> fetchFlags({List<int>? uids, int? changedSince});

  /// Il server supporta CONDSTORE (RFC 7162): permette di chiedere solo i
  /// flag cambiati invece di tutti. Valido dopo [connect].
  bool get supportsCondstore;

  /// Byte originali del messaggio [uid] della cartella selezionata, o null
  /// se non esiste più. Prima si chiede la dimensione (RFC822.SIZE): oltre
  /// [maxBytes] lancia [TransportErrorKind.tooLarge] senza scaricare niente.
  /// Usa BODY.PEEK: leggere non segna il messaggio come letto sul server.
  Future<Uint8List?> fetchRaw(int uid, {required int maxBytes});

  /// Aggiunge ([add] vero) o toglie i flag [flags] (maschera di
  /// [MessageFlags]) ai messaggi [uids] della cartella selezionata.
  Future<void> storeFlags(List<int> uids, int flags, {required bool add});

  /// Sposta i messaggi [uids] della cartella selezionata in [toPath]. Con
  /// MOVE (RFC 6851) in un passo; altrimenti COPY, \Deleted e UID EXPUNGE
  /// dei soli messaggi spostati.
  Future<void> moveMessages(List<int> uids, String toPath);

  /// Cancella per sempre i messaggi [uids] della cartella selezionata:
  /// \Deleted e UID EXPUNGE dei soli messaggi indicati. Senza UIDPLUS
  /// restano segnati come cancellati (un EXPUNGE semplice toglierebbe anche
  /// quelli segnati da altri client).
  Future<void> deleteMessages(List<int> uids);

  /// Aggiunge un messaggio completo alla cartella [path] (Inviata, Bozze).
  Future<void> append(String path, Uint8List raw, {int flags = 0});

  /// UID della cartella selezionata che soddisfano un criterio IMAP SEARCH
  /// scritto per intero. Serve alle estensioni dei provider, per esempio
  /// `X-GM-RAW "category:promotions"` di Gmail.
  Future<List<int>> searchUidsRaw(String criteria);

  /// Capability annunciata dal server (es. `X-GM-EXT-1`, `MOVE`).
  bool supports(String capability);

  /// Avvia l'IDLE sulla cartella selezionata. Lo stream si chiude con
  /// [stopWatching] o dopo un [ConnectionLostEvent].
  Stream<TransportEvent> watch();

  Future<void> stopWatching();

  /// Chiusura cortese (LOGOUT): può richiedere un giro di rete.
  Future<void> disconnect();

  /// Chiusura immediata, senza LOGOUT: tutti i comandi in corso falliscono
  /// subito con [TransportErrorKind.connectionLost]. Per lo spegnimento,
  /// quando la rete può essere morta e nulla deve restare appeso.
  Future<void> abort();
}
