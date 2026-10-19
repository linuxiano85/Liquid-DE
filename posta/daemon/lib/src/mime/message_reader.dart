import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'html_sanitizer.dart';
import 'message_content.dart';
import 'mime_parser.dart';

/// L'email non è stata letta entro il tempo concesso: l'isolate che la
/// leggeva è stato ucciso. Il messaggio va mostrato come "non leggibile",
/// con la possibilità di scaricare il sorgente, mai riprovato in un ciclo.
class MessageReadTimeout implements Exception {
  MessageReadTimeout(this.timeout);
  final Duration timeout;
  @override
  String toString() => 'MessageReadTimeout: lettura oltre ${timeout.inMilliseconds} ms';
}

/// L'email supera la dimensione massima accettata.
class MessageTooLarge implements Exception {
  MessageTooLarge(this.size, this.maxBytes);
  final int size;
  final int maxBytes;
  @override
  String toString() => 'MessageTooLarge: $size byte, massimo $maxBytes';
}

/// Ciò che il daemon salva e la UI mostra di un'email. A differenza di
/// [MessageContent] non contiene MAI l'HTML originale: solo quello sanificato.
class ReadMessage {
  ReadMessage({
    required this.subject,
    required this.textPlain,
    required this.html,
    required this.attachments,
    required this.defects,
    required this.encrypted,
    this.headers = const {},
  });

  final String subject;

  /// Intestazioni utili al filtro e alle risposte (nome in minuscolo,
  /// valore decodificato e accorciato): List-Unsubscribe, Precedence,
  /// In-Reply-To, References, X-Mailer e le altre `x-…`.
  final Map<String, String> headers;
  final String textPlain;

  /// HTML già passato dal sanificatore, o null se l'email è solo testo.
  final SanitizedHtml? html;
  final List<AttachmentInfo> attachments;
  final List<String> defects;
  final bool encrypted;
}

/// Lettura completa (parser, estrazione, sanificazione) di un'email.
///
/// Gira in un isolate a parte, ucciso allo scadere di [timeout]. Un timeout
/// nello stesso isolate non scatterebbe mai: il parsing è sincrono, e
/// un'email costruita apposta lo terrebbe occupato bloccando sync, RPC e
/// tutto il resto (verificato con un mutante quadratico, vedi
/// docs/stato-sviluppo.md). Con `Isolate.run` il Future scadrebbe, ma il
/// calcolo continuerebbe in sottofondo per sempre: per questo l'isolate si
/// crea a mano e si uccide.
Future<ReadMessage> readMessage(
  Uint8List raw, {
  Duration timeout = const Duration(seconds: 10),
  int maxBytes = 64 * 1024 * 1024,
  bool allowRemoteImages = false,
  void Function(Uint8List raw)? testHook,
}) async {
  if (raw.length > maxBytes) throw MessageTooLarge(raw.length, maxBytes);
  final results = ReceivePort();
  final exits = ReceivePort();
  final isolate = await Isolate.spawn(
    _readInIsolate,
    _Request(results.sendPort, TransferableTypedData.fromList([raw]), allowRemoteImages, testHook),
    onExit: exits.sendPort,
    onError: results.sendPort,
    errorsAreFatal: true,
  );
  try {
    final reply = await results.first.timeout(timeout, onTimeout: () {
      isolate.kill(priority: Isolate.immediate);
      throw MessageReadTimeout(timeout);
    });
    if (reply is ReadMessage) return reply;
    // onError manda [messaggio, stack]: il parser non dovrebbe mai lanciare,
    // ma se succede l'errore resta un errore normale, non un crash.
    throw StateError('Lettura dell\'email fallita: $reply');
  } finally {
    results.close();
    // Si aspetta la fine dell'isolate (al massimo un attimo dopo il kill):
    // chi chiama sa che nulla gira più quando il Future si completa.
    await exits.first.timeout(const Duration(seconds: 2), onTimeout: () => null);
    exits.close();
  }
}

class _Request {
  _Request(this.reply, this.raw, this.allowRemoteImages, this.testHook);
  final SendPort reply;
  final TransferableTypedData raw;
  final bool allowRemoteImages;
  final void Function(Uint8List raw)? testHook;
}

void _readInIsolate(_Request request) {
  final raw = request.raw.materialize().asUint8List();
  request.testHook?.call(raw);
  final tree = MimeParser().parse(raw);
  final content = ContentExtractor().extract(tree);
  final html = content.html;
  request.reply.send(ReadMessage(
    subject: content.subject,
    textPlain: content.textPlain,
    html: html == null
        ? null
        : HtmlSanitizer(allowRemoteImages: request.allowRemoteImages).sanitize(html),
    attachments: content.attachments,
    defects: content.defects,
    encrypted: content.encrypted,
    headers: _usefulHeaders(tree),
  ));
}

const _wanted = {
  'list-unsubscribe', 'list-id', 'precedence', 'in-reply-to', 'references', 'feedback-id',
  'reply-to', 'auto-submitted',
};

Map<String, String> _usefulHeaders(MimeMessageTree tree) {
  final out = <String, String>{};
  for (final (name, _) in tree.root.headers) {
    final n = name.toLowerCase();
    if (out.containsKey(n) || out.length >= 60) continue;
    if (!_wanted.contains(n) && !n.startsWith('x-')) continue;
    final v = tree.decodedHeader(n) ?? '';
    out[n] = v.length > 1000 ? v.substring(0, 1000) : v;
  }
  return out;
}
