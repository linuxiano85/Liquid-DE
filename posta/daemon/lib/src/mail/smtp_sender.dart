import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../transport/mail_transport.dart';
import 'smtp_client.dart';

/// Perché un invio non è riuscito.
enum SendFailure {
  /// Credenziali rifiutate dal server SMTP.
  authFailed,

  /// Certificato non valido o STARTTLS assente: la password non è partita.
  tls,

  /// Rete o server non raggiungibili: si può riprovare.
  offline,

  /// Il server ha rifiutato mittente, destinatari o messaggio.
  rejected,
}

class SendException implements Exception {
  SendException(this.failure, this.message);
  final SendFailure failure;
  final String message;
  @override
  String toString() => 'SendException(${failure.name}): $message';
}

/// Invio via SMTP con le stesse regole di sicurezza della lettura: TLS
/// diretto o STARTTLS obbligatorio, mai la password in chiaro; certificati
/// non firmati accettati solo se l'utente ne ha approvato l'impronta.
class SmtpSender {
  SmtpSender({this.timeout = const Duration(seconds: 60)});

  final Duration timeout;

  /// Spedisce [raw] a [recipients]. Restituisce i destinatari che il server
  /// ha rifiutato mentre accettava gli altri (vuoto = consegnato a tutti).
  Future<List<String>> send(
      TransportConfig c, String from, List<String> recipients, Uint8List raw) async {
    if (recipients.isEmpty) throw SendException(SendFailure.rejected, 'Nessun destinatario');
    final trusted = c.trustedCertSha256?.toLowerCase();
    bool badCert(X509Certificate cert) =>
        trusted != null && sha256.convert(cert.der).toString() == trusted;
    SmtpConnection? conn;
    var phase = 'connessione';
    try {
      conn = await SmtpConnection.connect(c.host, c.port,
          implicitTls: c.security == ConnectionSecurity.tls,
          context: c.securityContext,
          onBadCertificate: badCert,
          connectTimeout: c.connectTimeout,
          timeout: timeout);
      await conn.ehlo('liquid.local');
      if (c.security == ConnectionSecurity.starttls) {
        if (!conn.supportsStartTls) {
          throw SendException(SendFailure.tls,
              'Il server di invio non offre STARTTLS: la password non viene spedita in chiaro');
        }
        phase = 'STARTTLS';
        await conn.startTls(c.host, context: c.securityContext, onBadCertificate: badCert);
        await conn.ehlo('liquid.local');
      }
      phase = 'accesso';
      final token = c.accessToken;
      final auth = token != null
          ? await conn.authXoauth2(c.username, token)
          : conn.supportsAuth('PLAIN') || !conn.supportsAuth('LOGIN')
              ? await conn.authPlain(c.username, c.password)
              : await conn.authLogin(c.username, c.password);
      if (auth.code != 235) {
        throw SendException(SendFailure.authFailed, 'Nome utente o password non accettati per l\'invio');
      }
      phase = 'invio';
      final refused = await conn.sendMail(from, recipients, raw);
      await conn.quit();
      return refused;
    } on SendException {
      rethrow;
    } on SmtpProtocolException catch (e) {
      throw SendException(SendFailure.rejected, 'Il server ha rifiutato l\'invio ($phase): ${e.message}');
    } on HandshakeException {
      throw SendException(SendFailure.tls, 'Certificato del server di invio non valido o non fidato');
    } on TlsException {
      throw SendException(SendFailure.tls, 'Connessione sicura non riuscita ($phase)');
    } on SocketException {
      throw SendException(SendFailure.offline, 'Server di invio non raggiungibile ($phase)');
    } on TimeoutException {
      throw SendException(SendFailure.offline, 'Il server di invio non ha risposto in tempo ($phase)');
    } finally {
      await conn?.close();
    }
  }
}
