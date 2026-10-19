import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'mime_parser.dart';

enum AttachmentKind {
  /// Allegato normale, mostrato nell'elenco.
  file,

  /// Immagine richiamata dall'HTML con cid: (non mostrata nell'elenco).
  inlineImage,

  /// Firma S/MIME o PGP: informazione tecnica, non un file per l'utente.
  signature,

  /// Email inoltrata come allegato (message/rfc822).
  message,
}

class AttachmentInfo {
  AttachmentInfo({
    required this.filename,
    required this.mimeType,
    required this.bytes,
    required this.kind,
    this.contentId,
  }) : sha256Hex = sha256.convert(bytes).toString();

  final String filename;
  final String mimeType;
  final Uint8List bytes;
  final AttachmentKind kind;
  final String? contentId;
  final String sha256Hex;

  int get size => bytes.length;
}

/// Ciò che il client mostra di un messaggio.
class MessageContent {
  MessageContent({
    required this.subject,
    required this.textPlain,
    required this.html,
    required this.attachments,
    required this.defects,
    required this.encrypted,
  });

  final String subject;

  /// Testo semplice: dalla parte text/plain o, in mancanza, ricavato dall'HTML.
  final String textPlain;

  /// HTML ORIGINALE, non sanificato: non va mai mostrato così com'è.
  final String? html;
  final List<AttachmentInfo> attachments;
  final List<String> defects;

  /// multipart/encrypted o application/pkcs7-mime cifrato: contenuto non
  /// leggibile senza chiave (gestito nella fase OpenPGP/S/MIME).
  final bool encrypted;

  /// Allegati visibili all'utente (esclusi immagini inline e firme).
  List<AttachmentInfo> get visibleAttachments => attachments
      .where((a) => a.kind == AttachmentKind.file || a.kind == AttachmentKind.message)
      .toList();

  /// Mappa Content-ID → allegato, per risolvere <img src="cid:...">.
  Map<String, AttachmentInfo> get cidMap => {
        for (final a in attachments)
          if (a.contentId != null) a.contentId!: a,
      };
}

/// Estrae corpo e allegati da un albero MIME, con le stesse scelte dei
/// client maturi: in multipart/alternative vince l'ultima alternativa
/// supportata; in multipart/related la radice; in multipart/mixed i testi
/// inline senza nome sono corpo, il resto allegati.
class ContentExtractor {
  MessageContent extract(MimeMessageTree tree) {
    final state = _State();
    _walk(tree.root, state, inAlternative: false);

    final referencedCids = <String>{};
    final html = state.htmlParts.isEmpty ? null : state.htmlParts.join('\n<hr>\n');
    if (html != null) {
      for (final m in RegExp(r'''cid:([^"'\s)>]+)''', caseSensitive: false).allMatches(html)) {
        final raw = m.group(1)!;
        referencedCids.add(raw);
        // Alcuni client codificano il cid in percentuale; un escape non valido
        // ("%ZZ") non deve far cadere la lettura dell'email.
        try {
          referencedCids.add(Uri.decodeComponent(raw));
        } on Object {
          // ArgumentError per "%ZZ", FormatException per UTF-8 non valido
          // dopo la decodifica ("%C3"): resta solo la forma grezza.
        }
      }
    }

    final attachments = <AttachmentInfo>[];
    for (final p in state.attachmentParts) {
      final cid = p.contentId;
      var kind = AttachmentKind.file;
      if (p.mimeType == 'application/pgp-signature' ||
          p.mimeType == 'application/pkcs7-signature' ||
          p.mimeType == 'application/x-pkcs7-signature') {
        kind = AttachmentKind.signature;
      } else if (p.mimeType == 'message/rfc822' || p.mimeType == 'message/global') {
        kind = AttachmentKind.message;
      } else if (cid != null && referencedCids.contains(cid) && p.disposition != 'attachment') {
        kind = AttachmentKind.inlineImage;
      }
      attachments.add(AttachmentInfo(
        filename: p.filename ?? _defaultName(p, attachments.length + 1),
        mimeType: p.mimeType,
        bytes: p.body,
        kind: kind,
        contentId: cid,
      ));
    }

    var plain = state.plainParts.join('\n\n');
    if (plain.trim().isEmpty && html != null) plain = htmlToText(html);

    return MessageContent(
      subject: tree.decodedHeader('subject') ?? '',
      textPlain: plain,
      html: html,
      attachments: attachments,
      defects: tree.defects,
      encrypted: state.encrypted,
    );
  }

  static String _defaultName(MimePart p, int n) {
    if (p.mimeType == 'message/rfc822') {
      final s = p.encapsulated?.decodedHeader('subject');
      final base = (s == null || s.trim().isEmpty) ? 'messaggio-$n' : sanitizeFilename(s);
      return '${base.isEmpty ? 'messaggio-$n' : base}.eml';
    }
    const ext = {
      'image/png': 'png', 'image/jpeg': 'jpg', 'image/gif': 'gif', 'image/webp': 'webp',
      'application/pdf': 'pdf', 'text/calendar': 'ics', 'text/plain': 'txt', 'text/html': 'html',
    };
    return 'allegato-$n.${ext[p.mimeType] ?? 'bin'}';
  }

  bool _isBodyText(MimePart p) =>
      (p.mimeType == 'text/plain' || p.mimeType == 'text/html') &&
      p.disposition != 'attachment' &&
      p.filename == null;

  void _walk(MimePart p, _State s, {required bool inAlternative}) {
    if (!p.isMultipart) {
      if (_isBodyText(p)) {
        if (p.mimeType == 'text/html') {
          s.htmlParts.add(p.text());
        } else {
          s.plainParts.add(_textPlainOf(p));
        }
      } else if (p.mimeType == 'application/pkcs7-mime' &&
          (p.params['smime-type'] ?? 'enveloped-data') == 'enveloped-data') {
        s.encrypted = true;
        s.attachmentParts.add(p);
      } else {
        s.attachmentParts.add(p);
      }
      return;
    }

    switch (p.mimeType) {
      case 'multipart/alternative':
        // Ultima alternativa con HTML e ultima con testo; le altre (es.
        // text/enriched, text/calendar duplicato) diventano allegati solo se
        // non sono testo.
        MimePart? htmlChoice;
        MimePart? plainChoice;
        for (final c in p.children) {
          if (_contains(c, 'text/html')) htmlChoice = c;
          if (_contains(c, 'text/plain')) plainChoice = c;
        }
        if (htmlChoice != null) {
          final sub = _State();
          _walk(htmlChoice, sub, inAlternative: true);
          s.htmlParts.addAll(sub.htmlParts);
          s.attachmentParts.addAll(sub.attachmentParts);
          s.encrypted |= sub.encrypted;
        }
        if (plainChoice != null) {
          final sub = _State();
          _walk(plainChoice, sub, inAlternative: true);
          s.plainParts.addAll(sub.plainParts);
          if (htmlChoice == null) s.attachmentParts.addAll(sub.attachmentParts);
        }
        if (htmlChoice == null && plainChoice == null) {
          // Nessuna alternativa testuale: ogni parte una volta sola, dal giro
          // normale (prima veniva aggiunta anche dal ciclo qui sotto: doppione).
          for (final c in p.children) {
            _walk(c, s, inAlternative: inAlternative);
          }
        } else {
          for (final c in p.children) {
            // Inviti (text/calendar) e altre alternative non testuali: allegati.
            if (c != htmlChoice && c != plainChoice && !c.isMultipart &&
                c.mimeType != 'text/plain' && c.mimeType != 'text/html') {
              s.attachmentParts.add(c);
            }
          }
        }
      case 'multipart/encrypted':
        s.encrypted = true;
        for (final c in p.children) {
          if (c.mimeType != 'application/pgp-encrypted') s.attachmentParts.add(c);
        }
      case 'multipart/signed':
        if (p.children.isNotEmpty) _walk(p.children.first, s, inAlternative: inAlternative);
        for (final c in p.children.skip(1)) {
          s.attachmentParts.add(c);
        }
      case 'multipart/related':
        // Radice: parametro start o prima parte.
        final start = p.params['start'];
        var root = p.children.isEmpty ? null : p.children.first;
        if (start != null) {
          final id = start.replaceAll(RegExp('[<>]'), '');
          for (final c in p.children) {
            if (c.contentId == id) root = c;
          }
        }
        if (root != null) _walk(root, s, inAlternative: inAlternative);
        for (final c in p.children) {
          if (c != root) _walk(c, s, inAlternative: true);
        }
      default:
        for (final c in p.children) {
          _walk(c, s, inAlternative: inAlternative);
        }
    }
  }

  static bool _contains(MimePart p, String type) =>
      p.isMultipart ? p.children.any((c) => _contains(c, type)) : p.mimeType == type && p.disposition != 'attachment';

  /// format=flowed (RFC 3676): righe terminate da spazio si uniscono.
  static String _textPlainOf(MimePart p) {
    final text = p.text();
    if ((p.params['format'] ?? '').toLowerCase() != 'flowed') return text;
    final delsp = (p.params['delsp'] ?? '').toLowerCase() == 'yes';
    final out = StringBuffer();
    final lines = text.split(RegExp(r'\r?\n'));
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      final isSig = line == '-- ';
      if (!isSig && line.endsWith(' ') && i < lines.length - 1) {
        if (delsp) line = line.substring(0, line.length - 1);
        out.write(line);
      } else {
        out.write(line);
        if (i < lines.length - 1) out.write('\n');
      }
    }
    return out.toString();
  }
}

class _State {
  final plainParts = <String>[];
  final htmlParts = <String>[];
  final attachmentParts = <MimePart>[];
  bool encrypted = false;
}

const _blockTags = {
  'p', 'div', 'br', 'tr', 'li', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'table', 'ul', 'ol',
  'blockquote', 'pre', 'hr', 'section', 'article', 'header', 'footer', 'dt', 'dd',
};

/// Testo leggibile da HTML, per l'anteprima e l'indice di ricerca.
String htmlToText(String html) {
  final doc = html_parser.parse(html);
  final out = StringBuffer();
  void walk(dom.Node n) {
    if (n is dom.Element) {
      final tag = n.localName ?? '';
      if (const {'script', 'style', 'head', 'title', 'template', 'noscript'}.contains(tag)) return;
      if (tag == 'br') {
        out.write('\n');
        return;
      }
      final block = _blockTags.contains(tag);
      if (block) out.write('\n');
      for (final c in n.nodes) {
        walk(c);
      }
      if (block) out.write('\n');
    } else if (n is dom.Text) {
      out.write(n.text.replaceAll(RegExp(r'[ \t\r\n\u00a0]+'), ' '));
    } else {
      for (final c in n.nodes) {
        walk(c);
      }
    }
  }

  walk(doc.body ?? doc.documentElement ?? doc);
  return out
      .toString()
      .split('\n')
      .map((l) => l.trim())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}
