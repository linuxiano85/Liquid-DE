import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Risposta SMTP completa (anche su più righe: "250-…" … "250 …").
class SmtpReply {
  SmtpReply(this.code, this.lines);
  final int code;
  final List<String> lines;
  bool get ok => code >= 200 && code < 400;
  @override
  String toString() => '$code ${lines.join(' / ')}';
}

class SmtpProtocolException implements Exception {
  SmtpProtocolException(this.message, [this.reply]);
  final String message;
  final SmtpReply? reply;
  @override
  String toString() => 'SmtpProtocolException: $message${reply == null ? '' : ' ($reply)'}';
}

/// Client SMTP minimo, scritto qui invece di usare quello di enough_mail:
/// quello considera finita la risposta a EHLO solo se un singolo pacchetto
/// TCP contiene più righe, e con una risposta spezzata resta appeso fino al
/// timeout (trovato con il server finto, che spezza apposta).
///
/// Lavora su un RawSocket per poter passare a TLS a metà (STARTTLS) senza
/// perdere byte: i Socket normali di Dart non lo permettono.
class SmtpConnection {
  SmtpConnection._(this._socket, this.timeout) {
    _listen();
  }

  RawSocket _socket;
  final Duration timeout;
  late StreamSubscription<RawSocketEvent> _sub;
  final _buffer = <int>[];
  final _lines = <String>[];
  Completer<void>? _wait;
  bool _closed = false;
  Set<String> capabilities = {};

  static Future<SmtpConnection> connect(
    String host,
    int port, {
    required bool implicitTls,
    SecurityContext? context,
    bool Function(X509Certificate)? onBadCertificate,
    Duration connectTimeout = const Duration(seconds: 20),
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final RawSocket socket = implicitTls
        ? await RawSecureSocket.connect(host, port,
            context: context, onBadCertificate: onBadCertificate, timeout: connectTimeout)
        : await RawSocket.connect(host, port, timeout: connectTimeout);
    final c = SmtpConnection._(socket, timeout);
    final greeting = await c.read().timeout(connectTimeout);
    if (greeting.code != 220) {
      await c.close();
      throw SmtpProtocolException('Saluto del server inatteso', greeting);
    }
    return c;
  }

  void _listen() {
    _sub = _socket.listen((e) {
      if (e == RawSocketEvent.read) {
        final data = _socket.read();
        if (data != null) _buffer.addAll(data);
        _split();
      } else if (e == RawSocketEvent.readClosed || e == RawSocketEvent.closed) {
        _closed = true;
        _wake();
      }
    }, onError: (Object _) {
      _closed = true;
      _wake();
    }, onDone: () {
      _closed = true;
      _wake();
    });
  }

  void _split() {
    var start = 0;
    for (var i = 0; i + 1 < _buffer.length; i++) {
      if (_buffer[i] == 13 && _buffer[i + 1] == 10) {
        _lines.add(latin1.decode(_buffer.sublist(start, i)));
        start = i + 2;
        i++;
      }
    }
    if (start > 0) _buffer.removeRange(0, start);
    // Una riga di risposta lunghissima è un server rotto o ostile.
    if (_buffer.length > 64 * 1024) {
      _closed = true;
      _socket.close();
    }
    _wake();
  }

  void _wake() {
    final w = _wait;
    _wait = null;
    w?.complete();
  }

  Future<String> _line() async {
    while (_lines.isEmpty) {
      if (_closed) throw const SocketException('Connessione chiusa dal server');
      _wait = Completer<void>();
      await _wait!.future;
    }
    return _lines.removeAt(0);
  }

  /// Legge una risposta intera: righe "NNN-…" finché arriva "NNN …".
  Future<SmtpReply> read() async {
    final lines = <String>[];
    while (true) {
      final line = await _line().timeout(timeout);
      if (line.length < 3 || int.tryParse(line.substring(0, 3)) == null) {
        throw SmtpProtocolException('Risposta SMTP non valida: $line');
      }
      lines.add(line.length > 4 ? line.substring(4) : '');
      if (line.length == 3 || line[3] == ' ') {
        return SmtpReply(int.parse(line.substring(0, 3)), lines);
      }
      if (lines.length > 200) throw SmtpProtocolException('Risposta troppo lunga');
    }
  }

  void _write(List<int> bytes) {
    if (_closed) throw const SocketException('Connessione chiusa');
    var off = 0;
    while (off < bytes.length) {
      off += _socket.write(bytes, off);
    }
  }

  Future<SmtpReply> command(String line) async {
    _write(latin1.encode('$line\r\n'));
    return read();
  }

  Future<void> ehlo(String name) async {
    final r = await command('EHLO $name');
    if (r.code != 250) throw SmtpProtocolException('EHLO rifiutato', r);
    capabilities = {for (final l in r.lines.skip(1)) l.toUpperCase()};
  }

  bool get supportsStartTls => capabilities.contains('STARTTLS');

  bool supportsAuth(String mechanism) => capabilities.any(
      (c) => (c.startsWith('AUTH ') || c.startsWith('AUTH=')) && c.substring(5).split(' ').contains(mechanism));

  /// Passa a TLS sulla stessa connessione e dimentica le capability: quelle
  /// ricevute in chiaro potrebbero essere state alterate (si rifà EHLO).
  Future<void> startTls(String host,
      {SecurityContext? context, bool Function(X509Certificate)? onBadCertificate}) async {
    final r = await command('STARTTLS');
    if (r.code != 220) throw SmtpProtocolException('STARTTLS rifiutato', r);
    // Dopo il 220 il server deve tacere fino all'handshake. Byte già
    // arrivati sono risposte iniettate in chiaro da chi sta in mezzo
    // (CVE-2011-0411 e famiglia): verrebbero letti come se fossero cifrati.
    if (_buffer.isNotEmpty || _lines.isNotEmpty) {
      await close();
      throw SmtpProtocolException('Dati inattesi prima di TLS: connessione interrotta');
    }
    capabilities = {};
    _socket = await RawSecureSocket.secure(_socket,
        subscription: _sub, host: host, context: context, onBadCertificate: onBadCertificate);
    _listen();
  }

  Future<SmtpReply> authPlain(String user, String password) => command(
      'AUTH PLAIN ${base64.encode(utf8.encode('\u0000$user\u0000$password'))}');

  Future<SmtpReply> authLogin(String user, String password) async {
    final r = await command('AUTH LOGIN');
    if (r.code != 334) return r;
    final r2 = await command(base64.encode(utf8.encode(user)));
    if (r2.code != 334) return r2;
    return command(base64.encode(utf8.encode(password)));
  }

  /// XOAUTH2 (Google): il token al posto della password. Se il token non va
  /// il server risponde 334 con un JSON d'errore e aspetta una riga vuota,
  /// dopo la quale manda il codice finale (535).
  Future<SmtpReply> authXoauth2(String user, String accessToken) async {
    final r = await command(
        'AUTH XOAUTH2 ${base64.encode(utf8.encode('user=$user\u0001auth=Bearer $accessToken\u0001\u0001'))}');
    if (r.code != 334) return r;
    return command('');
  }

  /// MAIL, RCPT e DATA. Restituisce i destinatari rifiutati (vuoto = tutti
  /// accettati); se li rifiuta tutti, non manda il messaggio.
  Future<List<String>> sendMail(String from, List<String> recipients, Uint8List message) async {
    final m = await command('MAIL FROM:<$from>');
    if (!m.ok) throw SmtpProtocolException('Mittente rifiutato', m);
    final refused = <String>[];
    for (final r in recipients) {
      final reply = await command('RCPT TO:<$r>');
      if (!reply.ok) refused.add(r);
    }
    if (refused.length == recipients.length) {
      await command('RSET');
      throw SmtpProtocolException('Tutti i destinatari rifiutati: ${refused.join(', ')}');
    }
    final d = await command('DATA');
    if (d.code != 354) throw SmtpProtocolException('DATA rifiutato', d);
    _write(dotStuff(message));
    final done = await read();
    if (!done.ok) throw SmtpProtocolException('Messaggio rifiutato', done);
    return refused;
  }

  /// Corpo per DATA (RFC 5321 §4.5.2): punto raddoppiato a inizio riga,
  /// CRLF finale garantito, poi la riga "." che chiude.
  static Uint8List dotStuff(Uint8List message) {
    final out = BytesBuilder(copy: false);
    var lineStart = true;
    for (final b in message) {
      if (lineStart && b == 0x2E) out.addByte(0x2E);
      out.addByte(b);
      lineStart = b == 0x0A;
    }
    if (!lineStart) out.add(const [13, 10]);
    out.add(const [0x2E, 13, 10]);
    return out.takeBytes();
  }

  Future<void> quit() async {
    try {
      await command('QUIT').timeout(const Duration(seconds: 5));
    } on Object {
      // il messaggio è già stato accettato
    }
  }

  Future<void> close() async {
    _closed = true;
    try {
      await _sub.cancel();
      await _socket.close();
    } on Object {
      // già chiuso
    }
  }
}
