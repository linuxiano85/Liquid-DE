import 'dart:convert';
import 'dart:typed_data';

import 'charset.dart';

/// Limiti di sicurezza: un'email ostile non deve poter consumare memoria o
/// tempo senza limite. Superarli non è un errore: si registra un'anomalia e
/// si continua con ciò che è stato letto.
class MimeLimits {
  const MimeLimits({
    this.maxDepth = 30,
    this.maxParts = 1000,
    this.maxHeaderBytes = 256 * 1024,
    // Il limite che conta è in byte; il conteggio solo come seconda difesa.
    // Con 1000 un'email con 3000 intestazioni di disturbo nascondeva l'oggetto.
    this.maxHeaders = 20000,
  });

  final int maxDepth;
  final int maxParts;
  final int maxHeaderBytes;
  final int maxHeaders;
}

/// Una parte MIME: foglia (con [body] già decodificato dal transfer
/// encoding) o contenitore multipart (con [children]).
class MimePart {
  MimePart({
    required this.headers,
    required this.mimeType,
    required this.params,
    required this.disposition,
    required this.dispositionParams,
    required this.depth,
  });

  /// Intestazioni grezze in ordine: nome minuscolo e valore come byte
  /// (in Latin-1, cioè un carattere per byte, per non perdere nulla).
  final List<(String, String)> headers;

  /// Es. "text/plain", sempre minuscolo.
  final String mimeType;
  final Map<String, String> params;

  /// "inline", "attachment" o null.
  final String? disposition;
  final Map<String, String> dispositionParams;
  final int depth;

  Uint8List body = Uint8List(0);
  final List<MimePart> children = [];

  /// Per message/rfc822: il messaggio incapsulato.
  MimeMessageTree? encapsulated;

  String get mainType => mimeType.split('/').first;
  bool get isMultipart => mainType == 'multipart';

  String? header(String name) {
    for (final (n, v) in headers) {
      if (n == name) return v;
    }
    return null;
  }

  String? get charset => params['charset'];

  String? get contentId {
    final raw = header('content-id');
    if (raw == null) return null;
    var id = raw.trim();
    if (id.startsWith('<') && id.endsWith('>')) id = id.substring(1, id.length - 1);
    return id.isEmpty ? null : id;
  }

  /// Nome del file: disposition filename, poi content-type name.
  String? get filename {
    final n = dispositionParams['filename'] ?? params['name'];
    if (n == null) return null;
    final cleaned = sanitizeFilename(n);
    return cleaned.isEmpty ? null : cleaned;
  }

  /// Testo della parte decodificato secondo il charset (solo per text/*).
  String text() => Charsets.decode(body, charset ?? (body.every((b) => b < 0x80) ? 'us-ascii' : null));
}

/// Risultato del parsing: radice + anomalie riscontrate (per diagnostica).
class MimeMessageTree {
  MimeMessageTree(this.root, this.defects);
  final MimePart root;
  final List<String> defects;

  String? header(String name) => root.header(name);

  /// Oggetto, mittente, ecc. decodificati (RFC 2047 e 8 bit).
  String? decodedHeader(String name) {
    final v = root.header(name);
    return v == null ? null : decodeHeaderValue(v);
  }

  Iterable<MimePart> get leaves sync* {
    Iterable<MimePart> walk(MimePart p) sync* {
      if (p.isMultipart) {
        for (final c in p.children) {
          yield* walk(c);
        }
      } else {
        yield p;
      }
    }

    yield* walk(root);
  }
}

/// Toglie dal nome di un allegato tutto ciò che potrebbe farlo uscire dalla
/// cartella di destinazione o confondere l'utente: percorsi, caratteri di
/// controllo, caratteri di inversione del testo (RLO usato per "fattura<RLO>fdp.exe").
String sanitizeFilename(String name) {
  var n = name.replaceAll('\\', '/');
  n = n.split('/').where((s) => s.isNotEmpty).lastOrNull ?? '';
  n = n.replaceAll(RegExp('[\u0000-\u001f\u007f\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '');
  n = n.trim();
  if (n == '.' || n == '..') return '';
  if (n.length > 200) {
    final dot = n.lastIndexOf('.');
    final ext = dot > 0 && n.length - dot <= 10 ? n.substring(dot) : '';
    n = n.substring(0, 200 - ext.length) + ext;
  }
  return n;
}

// ---------------------------------------------------------------------------
// Intestazioni e parametri
// ---------------------------------------------------------------------------

final _encodedWord = RegExp(r'=\?([^?\s]{1,64})\?([bBqQ])\?([^?\s]*)\?=');

/// Decodifica un valore di intestazione: parole codificate RFC 2047 (anche
/// adiacenti, anche senza spazi intorno) e byte a 8 bit non codificati
/// (UTF-8 se valido, altrimenti windows-1252). Non lancia mai.
String decodeHeaderValue(String latin1Value) {
  final out = StringBuffer();
  var pos = 0;
  var lastWasEncoded = false;
  for (final m in _encodedWord.allMatches(latin1Value)) {
    final between = latin1Value.substring(pos, m.start);
    final decoded = _decodeEncodedWord(m.group(1)!, m.group(2)!, m.group(3)!);
    // RFC 2047 §6.2: lo spazio tra due parole codificate adiacenti si ignora.
    if (!(lastWasEncoded && decoded != null && between.trim().isEmpty)) {
      out.write(_decode8bit(between));
    }
    if (decoded != null) {
      out.write(decoded);
      lastWasEncoded = true;
    } else {
      out.write(_decode8bit(m.group(0)!));
      lastWasEncoded = false;
    }
    pos = m.end;
  }
  out.write(_decode8bit(latin1Value.substring(pos)));
  return out.toString().replaceAll(RegExp(r'[\r\n]+'), '');
}

String _decode8bit(String latin1Text) {
  if (latin1Text.isEmpty) return '';
  if (latin1Text.codeUnits.every((c) => c < 0x80)) return latin1Text;
  return Charsets.decodeUnknown(latin1.encode(latin1Text));
}

String? _decodeEncodedWord(String charset, String enc, String text) {
  // RFC 2231 §5: "UTF-8*it" = charset + lingua.
  final cs = charset.split('*').first;
  final List<int> bytes;
  if (enc == 'b' || enc == 'B') {
    // Dentro un'intestazione la tolleranza del corpo sarebbe dannosa: una
    // parola con caratteri non base64 non è codificata, si mostra com'è.
    if (!RegExp(r'^[A-Za-z0-9+/]*=*$').hasMatch(text)) return null;
    final b = _decodeBase64Lenient(latin1.encode(text));
    if (b == null) return null;
    bytes = b;
  } else {
    bytes = _decodeQuotedPrintable(latin1.encode(text.replaceAll('_', ' ')), header: true);
  }
  if (Charsets.canonical(cs) == null) return null;
  return Charsets.decode(bytes, cs);
}

/// Content-Type / Content-Disposition: valore principale + parametri, con
/// stringhe tra virgolette, RFC 2231 (charset, continuazioni) e parole RFC 2047
/// nei nomi file (Outlook, Gmail).
/// Con [decode] false i valori semplici restano byte grezzi (Latin-1): serve
/// per il boundary, che va confrontato byte per byte con il corpo.
(String, Map<String, String>) parseHeaderParams(String latin1Value, {bool decode = true}) {
  final parts = <String>[];
  final buf = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < latin1Value.length; i++) {
    final c = latin1Value[i];
    if (c == '"') inQuotes = !inQuotes;
    if (c == '\\' && inQuotes && i + 1 < latin1Value.length) {
      buf.write(c);
      buf.write(latin1Value[++i]);
      continue;
    }
    if (c == ';' && !inQuotes) {
      parts.add(buf.toString());
      buf.clear();
    } else {
      buf.write(c);
    }
  }
  parts.add(buf.toString());

  final value = parts.first.trim().toLowerCase();
  final simple = <String, String>{};
  final extended = <String, Map<int, (String, bool)>>{};
  for (final p in parts.skip(1)) {
    final eq = p.indexOf('=');
    if (eq <= 0) continue;
    var key = p.substring(0, eq).trim().toLowerCase();
    var val = p.substring(eq + 1).trim();
    if (val.length >= 2 && val.startsWith('"') && val.endsWith('"')) {
      val = val.substring(1, val.length - 1).replaceAllMapped(RegExp(r'\\(.)'), (m) => m.group(1)!);
    } else if (val.startsWith('"')) {
      val = val.substring(1); // virgoletta non chiusa
    }
    // RFC 2231: name*  name*0  name*0*  name*1 ...
    final m = RegExp(r'^([^*]+)\*(?:(\d{1,3})\*?)?$').firstMatch(key);
    if (m != null) {
      final base = m.group(1)!;
      final index = int.parse(m.group(2) ?? '0');
      final encoded = key.endsWith('*');
      extended.putIfAbsent(base, () => {})[index] = (val, encoded);
      continue;
    }
    simple.putIfAbsent(key, () => val);
  }

  final result = <String, String>{};
  simple.forEach((k, v) => result[k] = decode ? decodeHeaderValue(v) : v);
  extended.forEach((key, segments) {
    final ordered = segments.keys.toList()..sort();
    String? charset;
    final bytes = <int>[];
    for (final i in ordered) {
      var (text, encoded) = segments[i]!;
      if (encoded) {
        if (i == ordered.first) {
          final q1 = text.indexOf("'");
          final q2 = q1 < 0 ? -1 : text.indexOf("'", q1 + 1);
          if (q1 >= 0 && q2 > q1) {
            charset = text.substring(0, q1);
            text = text.substring(q2 + 1);
          }
        }
        bytes.addAll(_percentDecode(text));
      } else {
        bytes.addAll(latin1.encode(text));
      }
    }
    // La forma estesa vince sulla semplice (es. filename + filename*).
    result[key] = charset != null && charset.isNotEmpty
        ? Charsets.decode(bytes, charset)
        : Charsets.decodeUnknown(bytes);
  });
  return (value, result);
}

List<int> _percentDecode(String s) {
  final out = <int>[];
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c == 0x25 && i + 2 < s.length) {
      // Solo due cifre esadecimali: int.tryParse accetterebbe anche il segno
      // ("%-E" diventava -14, un "byte" negativo: crash trovato dal fuzzing).
      final h = s.substring(i + 1, i + 3);
      final v = RegExp(r'^[0-9A-Fa-f]{2}$').hasMatch(h) ? int.parse(h, radix: 16) : null;
      if (v != null) {
        out.add(v);
        i += 2;
        continue;
      }
    }
    out.add(c & 0xff);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Transfer encoding
// ---------------------------------------------------------------------------

/// Base64 tollerante: ignora i caratteri estranei (spazi, righe spezzate,
/// rumore) e il padding mancante o in eccesso, come fanno i client maturi.
Uint8List? _decodeBase64Lenient(List<int> input) {
  final clean = BytesBuilder(copy: false);
  final chunk = <int>[];
  for (final c in input) {
    if ((c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || (c >= 0x30 && c <= 0x39) ||
        c == 0x2B || c == 0x2F) {
      chunk.add(c);
    } else if (c == 0x2D || c == 0x5F) {
      chunk.add(c == 0x2D ? 0x2B : 0x2F); // varianti URL-safe
    }
  }
  var len = chunk.length;
  if (len % 4 == 1) len--; // un carattere isolato non porta informazione
  if (len == 0) return Uint8List(0);
  final padded = String.fromCharCodes(chunk.sublist(0, len)) + '=' * ((4 - len % 4) % 4);
  try {
    clean.add(base64.decode(padded));
  } on FormatException {
    return null;
  }
  return clean.takeBytes();
}

List<int> _decodeQuotedPrintable(List<int> input, {bool header = false}) {
  final out = <int>[];
  int hex(int c) {
    if (c >= 0x30 && c <= 0x39) return c - 0x30;
    if (c >= 0x41 && c <= 0x46) return c - 0x37;
    if (c >= 0x61 && c <= 0x66) return c - 0x57;
    return -1;
  }

  for (var i = 0; i < input.length; i++) {
    final c = input[i];
    if (c == 0x3D) {
      // "=" a fine riga (anche con spazi prima dell'a capo): interruzione morbida.
      var j = i + 1;
      while (j < input.length && (input[j] == 0x20 || input[j] == 0x09)) {
        j++;
      }
      if (!header && j < input.length && (input[j] == 0x0A || input[j] == 0x0D)) {
        if (input[j] == 0x0D && j + 1 < input.length && input[j + 1] == 0x0A) j++;
        i = j;
        continue;
      }
      if (!header && j == input.length) {
        i = j;
        continue;
      }
      if (i + 2 < input.length + 0 && i + 2 <= input.length - 1) {
        final h = hex(input[i + 1]), l = hex(input[i + 2]);
        if (h >= 0 && l >= 0) {
          out.add(h * 16 + l);
          i += 2;
          continue;
        }
      }
      out.add(c); // "=" non valido: lasciato com'è
    } else {
      out.add(c);
    }
  }
  return out;
}

Uint8List _decodeUuencode(Uint8List input) {
  final out = BytesBuilder(copy: false);
  final lines = const LineSplitter().convert(latin1.decode(input));
  var started = false;
  for (final line in lines) {
    if (!started) {
      if (line.startsWith('begin ')) started = true;
      continue;
    }
    if (line.trim() == 'end') break;
    if (line.isEmpty) continue;
    final n = (line.codeUnitAt(0) - 32) & 63;
    if (n == 0) continue;
    final bytes = <int>[];
    for (var i = 1; i + 3 < line.length + 1 && bytes.length < n; i += 4) {
      int v(int k) => i + k < line.length ? (line.codeUnitAt(i + k) - 32) & 63 : 0;
      final a = v(0), b = v(1), c = v(2), d = v(3);
      bytes.addAll([(a << 2 | b >> 4) & 255, (b << 4 | c >> 2) & 255, (c << 6 | d) & 255]);
    }
    out.add(bytes.take(n).toList());
  }
  return out.takeBytes();
}

Uint8List decodeTransfer(Uint8List raw, String? encoding) {
  switch (encoding?.trim().toLowerCase()) {
    case 'base64':
      return _decodeBase64Lenient(raw) ?? raw;
    case 'quoted-printable':
      return Uint8List.fromList(_decodeQuotedPrintable(raw));
    case 'x-uuencode' || 'x-uue' || 'uuencode':
      return _decodeUuencode(raw);
    default:
      return raw;
  }
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

class MimeParser {
  MimeParser({this.limits = const MimeLimits()});

  final MimeLimits limits;
  late List<String> _defects;
  late int _parts;

  MimeMessageTree parse(Uint8List data) {
    _defects = [];
    _parts = 0;
    final root = _parseEntity(data, 0, data.length, 0, defaultType: 'text/plain');
    return MimeMessageTree(root, _defects);
  }

  MimePart _parseEntity(Uint8List data, int start, int end, int depth, {required String defaultType}) {
    _parts++;
    final (headers, bodyStart) = _parseHeaders(data, start, end);

    String type = defaultType;
    var params = <String, String>{};
    final ct = _find(headers, 'content-type');
    if (ct != null) {
      final (v, p) = parseHeaderParams(ct);
      params = p;
      // Tipo malformato ("text", "", "text/") → il predefinito (RFC 2045 §5.2).
      if (RegExp(r'^[a-z0-9!#$&^_.+-]+/[a-z0-9!#$&^_.+-]+$').hasMatch(v)) {
        type = v;
      } else {
        _defects.add('Content-Type non valido: $v');
      }
    }
    String? disposition;
    var dispParams = <String, String>{};
    final cd = _find(headers, 'content-disposition');
    if (cd != null) {
      final (v, p) = parseHeaderParams(cd);
      disposition = v.isEmpty ? null : v;
      dispParams = p;
    }

    final part = MimePart(
      headers: headers,
      mimeType: type,
      params: params,
      disposition: disposition,
      dispositionParams: dispParams,
      depth: depth,
    );

    if (part.isMultipart) {
      // Boundary dai byte grezzi: decodificarlo (es. 0x89 → "‰" in
      // windows-1252) lo renderebbe impossibile da ritrovare nel corpo.
      final boundary = parseHeaderParams(ct ?? '', decode: false).$2['boundary'];
      if (depth >= limits.maxDepth) {
        _defects.add('Annidamento oltre ${limits.maxDepth} livelli: interrotto');
        return part;
      }
      if (boundary == null || boundary.isEmpty || boundary.length > 200) {
        _defects.add('Multipart senza boundary valido: trattato come testo');
        return _asText(part, data, bodyStart, end);
      }
      final ranges = _splitMultipart(data, bodyStart, end, latin1.encode(boundary));
      if (ranges == null) {
        _defects.add('Boundary non trovato nel corpo: trattato come testo');
        return _asText(part, data, bodyStart, end);
      }
      final childDefault = type == 'multipart/digest' ? 'message/rfc822' : 'text/plain';
      for (final (s, e) in ranges) {
        if (_parts >= limits.maxParts) {
          _defects.add('Oltre ${limits.maxParts} parti: le restanti sono ignorate');
          break;
        }
        part.children.add(_parseEntity(data, s, e, depth + 1, defaultType: childDefault));
      }
      return part;
    }

    final cte = _find(headers, 'content-transfer-encoding');
    part.body = decodeTransfer(Uint8List.sublistView(data, bodyStart, end), cte);

    if (type == 'message/rfc822' || type == 'message/global') {
      if (depth < limits.maxDepth && _parts < limits.maxParts) {
        final inner = _parseEntity(part.body, 0, part.body.length, depth + 1, defaultType: 'text/plain');
        part.encapsulated = MimeMessageTree(inner, const []);
      }
    }
    return part;
  }

  MimePart _asText(MimePart p, Uint8List data, int start, int end) {
    final t = MimePart(
      headers: p.headers,
      mimeType: 'text/plain',
      params: {...p.params}..remove('boundary'),
      disposition: p.disposition,
      dispositionParams: p.dispositionParams,
      depth: p.depth,
    );
    t.body = Uint8List.sublistView(data, start, end);
    return t;
  }

  static const _essentialHeaders = {
    'content-type', 'content-transfer-encoding', 'content-disposition', 'content-id',
    'subject', 'from', 'to', 'cc', 'date', 'message-id', 'in-reply-to', 'references',
    'reply-to', 'list-unsubscribe', 'mime-version',
  };

  static String? _find(List<(String, String)> headers, String name) {
    for (final (n, v) in headers) {
      if (n == name) return v;
    }
    return null;
  }

  /// Intestazioni fino alla prima riga vuota (CRLF o solo LF).
  (List<(String, String)>, int) _parseHeaders(Uint8List data, int start, int end) {
    final headers = <(String, String)>[];
    var i = start;
    final lines = <String>[];
    final limit = start + limits.maxHeaderBytes < end ? start + limits.maxHeaderBytes : end;
    var bodyStart = end;
    while (i < limit) {
      var j = i;
      while (j < end && data[j] != 0x0A) {
        j++;
      }
      var lineEnd = j;
      if (lineEnd > i && data[lineEnd - 1] == 0x0D) lineEnd--;
      final next = j < end ? j + 1 : end;
      if (lineEnd == i) {
        bodyStart = next; // riga vuota: inizio del corpo
        break;
      }
      lines.add(latin1.decode(Uint8List.sublistView(data, i, lineEnd)));
      i = next;
      if (i >= end) bodyStart = end;
    }
    if (i >= limit && limit < end) {
      _defects.add('Intestazioni oltre ${limits.maxHeaderBytes} byte: troncate');
      bodyStart = limit;
    }

    // Una prima riga che non è un'intestazione (nessun ":") significa che
    // il messaggio non ha intestazioni: è tutto corpo.
    if (lines.isNotEmpty && !lines.first.contains(':') && !lines.first.startsWith('From ')) {
      return (headers, start);
    }

    String? name;
    final value = StringBuffer();
    final essentialSeen = <String>{}; // insieme, non ricerca nella lista: costo costante
    void flush() {
      final n = name;
      if (n != null) {
        if (headers.length < limits.maxHeaders) {
          headers.add((n, value.toString().trim()));
          if (_essentialHeaders.contains(n)) essentialSeen.add(n);
        } else if (_essentialHeaders.contains(n) && essentialSeen.add(n)) {
          // Oltre il limite si accettano ancora le intestazioni che decidono
          // come si legge il messaggio, una volta sola ciascuna: la memoria
          // resta limitata e il rumore non può nascondere Content-Type.
          headers.add((n, value.toString().trim()));
        }
      }
      name = null;
      value.clear();
    }

    for (final line in lines) {
      if (line.startsWith(' ') || line.startsWith('\t')) {
        if (name != null) value.write(' ${line.trim()}');
        continue;
      }
      flush();
      final colon = line.indexOf(':');
      if (colon <= 0) continue; // riga "From " di mbox o spazzatura
      final n = line.substring(0, colon).trim().toLowerCase();
      if (n.isEmpty || n.contains(' ')) continue;
      name = n;
      value.write(line.substring(colon + 1));
    }
    flush();
    if (headers.length >= limits.maxHeaders) _defects.add('Troppe intestazioni');
    return (headers, bodyStart);
  }

  /// Intervalli [inizio, fine) delle parti, o null se il boundary non compare.
  List<(int, int)>? _splitMultipart(Uint8List data, int start, int end, List<int> boundary) {
    final delim = [0x2D, 0x2D, ...boundary];
    final ranges = <(int, int)>[];
    int? partStart;
    var i = start;
    var found = false;
    var closed = false;
    while (i < end) {
      final at = _indexOf(data, delim, i, end);
      if (at < 0) break;
      // Il delimitatore deve stare a inizio riga.
      if (at != start && data[at - 1] != 0x0A) {
        i = at + 1;
        continue;
      }
      var k = at + delim.length;
      final isClose = k + 1 < end && data[k] == 0x2D && data[k + 1] == 0x2D;
      if (isClose) k += 2;
      // Dopo il boundary solo spazi fino a fine riga (altrimenti è un boundary
      // più lungo che inizia con lo stesso testo).
      var m = k;
      while (m < end && (data[m] == 0x20 || data[m] == 0x09)) {
        m++;
      }
      if (m < end && data[m] != 0x0D && data[m] != 0x0A) {
        i = at + 1;
        continue;
      }
      found = true;
      if (partStart != null) {
        // La parte termina prima del CRLF che precede il delimitatore.
        var pe = at;
        if (pe > partStart && data[pe - 1] == 0x0A) pe--;
        if (pe > partStart && data[pe - 1] == 0x0D) pe--;
        ranges.add((partStart, pe < partStart ? partStart : pe));
      }
      if (isClose) {
        closed = true;
        break;
      }
      // Salta fino a fine riga.
      var n = m;
      if (n < end && data[n] == 0x0D) n++;
      if (n < end && data[n] == 0x0A) n++;
      partStart = n;
      i = n;
    }
    if (!found) return null;
    if (!closed) {
      _defects.add('Delimitatore finale mancante');
      if (partStart != null && partStart < end) ranges.add((partStart, end));
    }
    return ranges;
  }

  static int _indexOf(Uint8List data, List<int> pat, int from, int end) {
    final first = pat[0];
    final last = end - pat.length;
    outer:
    for (var i = from; i <= last; i++) {
      if (data[i] != first) continue;
      for (var j = 1; j < pat.length; j++) {
        if (data[i + j] != pat[j]) continue outer;
      }
      return i;
    }
    return -1;
  }
}
