import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Un allegato da spedire.
class OutgoingAttachment {
  OutgoingAttachment(this.filename, this.mimeType, this.bytes);
  final String filename;
  final String mimeType;
  final Uint8List bytes;
}

/// Un messaggio da spedire, già validato.
class OutgoingMessage {
  OutgoingMessage({
    required this.fromAddress,
    this.fromName,
    required this.to,
    this.cc = const [],
    this.bcc = const [],
    required this.subject,
    required this.text,
    this.inReplyTo,
    this.references = const [],
    this.attachments = const [],
  });

  final String fromAddress;
  final String? fromName;
  final List<String> to;
  final List<String> cc;

  /// Destinatari nascosti: ricevono il messaggio ma non compaiono MAI nelle
  /// intestazioni, nemmeno nella copia salvata in Inviata.
  final List<String> bcc;
  final String subject;
  final String text;

  /// Message-ID a cui si risponde (con le parentesi angolari).
  final String? inReplyTo;
  final List<String> references;
  final List<OutgoingAttachment> attachments;

  /// Tutti gli indirizzi a cui il server SMTP deve consegnare.
  List<String> get recipients => {...to, ...cc, ...bcc}.toList();
}

/// Il messaggio pronto: byte da spedire e Message-ID assegnato.
class ComposedMessage {
  ComposedMessage(this.raw, this.messageId);
  final Uint8List raw;
  final String messageId;
}

/// Compone un messaggio RFC 5322 / MIME interamente a 7 bit: passa
/// ovunque, anche dai server che non accettano 8BITMIME.
///
/// - intestazioni con caratteri non ASCII in RFC 2047 (base64 UTF-8);
/// - testo in quoted-printable, righe di al massimo 76 caratteri;
/// - allegati in base64 con nome in RFC 2231 (e una versione ASCII per i
///   client vecchi);
/// - CR e LF tolti da ogni valore che finisce in un'intestazione: nessun
///   testo dell'utente può aggiungere intestazioni (header injection).
class MessageComposer {
  MessageComposer({Random? random, DateTime Function()? clock})
      : _random = random ?? Random.secure(),
        _clock = clock ?? DateTime.now;

  final Random _random;
  final DateTime Function() _clock;

  ComposedMessage compose(OutgoingMessage m) {
    final domain = m.fromAddress.split('@').last;
    final messageId = '<${_token(24)}@$domain>';
    final out = StringBuffer();
    void header(String name, String value) => out.write('$name: $value\r\n');

    header('From', _address(m.fromAddress, m.fromName));
    if (m.to.isNotEmpty) header('To', m.to.map(_clean).join(', '));
    if (m.cc.isNotEmpty) header('Cc', m.cc.map(_clean).join(', '));
    header('Subject', encodeHeaderWord(_clean(m.subject)));
    header('Date', formatDate(_clock()));
    header('Message-ID', messageId);
    final reply = m.inReplyTo == null ? null : _clean(m.inReplyTo!);
    if (reply != null && reply.isNotEmpty) header('In-Reply-To', reply);
    final refs = [...m.references.map(_clean), ?reply].where((r) => r.isNotEmpty).toSet();
    if (refs.isNotEmpty) header('References', refs.join(' '));
    header('MIME-Version', '1.0');
    header('User-Agent', 'Liquid Mail');

    if (m.attachments.isEmpty) {
      _textPart(out);
      out.write('\r\n');
      out.write(quotedPrintable(m.text));
    } else {
      final boundary = '=_liquid_${_token(16)}';
      header('Content-Type', 'multipart/mixed; boundary="$boundary"');
      // Preambolo: lo vedono solo i client che non capiscono MIME.
      out.write('\r\nMessaggio MIME in piu\' parti.\r\n');
      out.write('--$boundary\r\n');
      _textPart(out);
      out.write('\r\n');
      out.write(quotedPrintable(m.text));
      for (final a in m.attachments) {
        out.write('\r\n--$boundary\r\n');
        final name = _clean(a.filename);
        final ascii = name.replaceAll(RegExp(r'[^\x20-\x7E]'), '_').replaceAll('"', "'");
        final type = RegExp(r'^[\w.+-]+/[\w.+-]+$').hasMatch(a.mimeType)
            ? a.mimeType
            : 'application/octet-stream';
        if (ascii == name) {
          out.write('Content-Type: $type; name="$name"\r\n');
          out.write('Content-Disposition: attachment; filename="$name"\r\n');
        } else {
          // Come Thunderbird: nella disposizione solo la forma RFC 2231 (se ci
          // fosse anche quella ASCII, alcuni client sceglierebbero quella), e
          // nel Content-Type il nome in RFC 2047 per i client più vecchi.
          out.write('Content-Type: $type;\r\n name="${encodeHeaderWord(name)}"\r\n');
          out.write("Content-Disposition: attachment;\r\n filename*=utf-8''${_rfc2231(name)}\r\n");
        }
        out.write('Content-Transfer-Encoding: base64\r\n\r\n');
        final b64 = base64.encode(a.bytes);
        for (var i = 0; i < b64.length; i += 76) {
          out.write(b64.substring(i, min(i + 76, b64.length)));
          out.write('\r\n');
        }
      }
      out.write('\r\n--$boundary--\r\n');
    }
    return ComposedMessage(Uint8List.fromList(ascii.encode(out.toString())), messageId);
  }

  void _textPart(StringBuffer out) {
    out.write('Content-Type: text/plain; charset=utf-8\r\n');
    out.write('Content-Transfer-Encoding: quoted-printable\r\n');
  }

  String _token(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return String.fromCharCodes(
        List.generate(length, (_) => chars.codeUnitAt(_random.nextInt(chars.length))));
  }

  static String _clean(String s) => s.replaceAll(RegExp(r'[\r\n\u0000]'), ' ').trim();

  static String _address(String address, String? name) {
    final a = _clean(address);
    final n = name == null ? '' : _clean(name);
    if (n.isEmpty) return a;
    if (RegExp(r'^[\x20-\x7E]*$').hasMatch(n)) {
      return '"${n.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}" <$a>';
    }
    return '${encodeHeaderWord(n)} <$a>';
  }

  /// RFC 2047: testo ASCII com'è, altrimenti `=?utf-8?B?…?=` a pezzi che non
  /// spezzano mai un carattere UTF-8 e restano entro i 75 caratteri.
  static String encodeHeaderWord(String text) {
    if (RegExp(r'^[\x20-\x7E]*$').hasMatch(text)) return text;
    final words = <String>[];
    final chunk = <int>[];
    for (final rune in text.runes) {
      final bytes = utf8.encode(String.fromCharCode(rune));
      if (chunk.length + bytes.length > 45) {
        words.add('=?utf-8?B?${base64.encode(chunk)}?=');
        chunk.clear();
      }
      chunk.addAll(bytes);
    }
    if (chunk.isNotEmpty) words.add('=?utf-8?B?${base64.encode(chunk)}?=');
    return words.join('\r\n ');
  }

  static String _rfc2231(String s) => [
        for (final b in utf8.encode(s))
          RegExp(r'[A-Za-z0-9._-]').hasMatch(String.fromCharCode(b))
              ? String.fromCharCode(b)
              : '%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}',
      ].join();

  /// Quoted-printable (RFC 2045) di testo UTF-8, con fine riga CRLF.
  static String quotedPrintable(String text) {
    final out = StringBuffer();
    final lines = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    for (var l = 0; l < lines.length; l++) {
      final bytes = utf8.encode(lines[l]);
      var lineLength = 0;
      for (var i = 0; i < bytes.length; i++) {
        final b = bytes[i];
        final last = i == bytes.length - 1;
        // Spazi e tab a fine riga vanno codificati: i server li tolgono.
        final plain = (b >= 33 && b <= 126 && b != 61) || ((b == 32 || b == 9) && !last);
        final piece = plain ? String.fromCharCode(b) : '=${b.toRadixString(16).toUpperCase().padLeft(2, '0')}';
        if (lineLength + piece.length > 75) {
          out.write('=\r\n');
          lineLength = 0;
        }
        out.write(piece);
        lineLength += piece.length;
      }
      if (l < lines.length - 1) out.write('\r\n');
    }
    out.write('\r\n');
    return out.toString();
  }

  /// Data RFC 5322 con il fuso orario locale ("Tue, 13 Oct 2026 18:40:00 +0200").
  static String formatDate(DateTime d) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    String two(int n) => n.toString().padLeft(2, '0');
    final offset = d.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final abs = offset.abs();
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year} '
        '${two(d.hour)}:${two(d.minute)}:${two(d.second)} '
        '$sign${two(abs.inHours)}${two(abs.inMinutes % 60)}';
  }
}
