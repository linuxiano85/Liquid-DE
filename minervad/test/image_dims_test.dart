import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:minervad/services/image_dims.dart';

// Le misure si leggono dall'intestazione, e l'intestazione si può costruire a
// mano: queste prove non hanno bisogno di nessun file vero, e girano ovunque.
//
// Quello che c'è da provare non è il caso facile — un PNG ha larghezza e
// altezza a due posizioni fisse e non può sbagliarsi — ma il JPEG, che
// costringe a camminare fra i segmenti, e il caso in cui la risposta giusta è
// «non lo so».

Uint8List _png(int w, int h) {
  final b = Uint8List(24);
  b.setAll(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  b.setAll(8, [0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]);
  b[16] = (w >> 24) & 0xFF;
  b[17] = (w >> 16) & 0xFF;
  b[18] = (w >> 8) & 0xFF;
  b[19] = w & 0xFF;
  b[20] = (h >> 24) & 0xFF;
  b[21] = (h >> 16) & 0xFF;
  b[22] = (h >> 8) & 0xFF;
  b[23] = h & 0xFF;
  return b;
}

Uint8List _gif(int w, int h) {
  final b = Uint8List(16);
  b.setAll(0, 'GIF89a'.codeUnits);
  b[6] = w & 0xFF;
  b[7] = (w >> 8) & 0xFF;
  b[8] = h & 0xFF;
  b[9] = (h >> 8) & 0xFF;
  return b;
}

/// Un JPEG con, prima della cornice, due segmenti da saltare — uno dei quali
/// è una tabella di Huffman (0xC4), che sta nella serie 0xC0…0xCF e cornice
/// NON è. È il caso che rompe le implementazioni scritte in fretta.
Uint8List _jpeg(int w, int h, {bool conTrappola = true}) {
  final out = <int>[0xFF, 0xD8];
  if (conTrappola) {
    // APP0, lungo 16
    out.addAll([0xFF, 0xE0, 0x00, 0x10]);
    out.addAll(List.filled(14, 0));
    // DHT (0xC4), lungo 6: da saltare, non da leggere
    out.addAll([0xFF, 0xC4, 0x00, 0x06, 1, 2, 3, 4]);
  }
  // SOF0: lunghezza, precisione, altezza, larghezza
  out.addAll([0xFF, 0xC0, 0x00, 0x11, 0x08]);
  out.addAll([(h >> 8) & 0xFF, h & 0xFF]);
  out.addAll([(w >> 8) & 0xFF, w & 0xFF]);
  out.addAll(List.filled(12, 0));
  return Uint8List.fromList(out);
}

void main() {
  group('ImageDims.fromBytes', () {
    test('PNG', () {
      final d = ImageDims.fromBytes(_png(1840, 4080));
      expect(d, isNotNull);
      expect(d!.width, 1840);
      expect(d.height, 4080);
    });

    test('GIF', () {
      final d = ImageDims.fromBytes(_gif(320, 240));
      expect(d!.width, 320);
      expect(d.height, 240);
    });

    test('JPEG, saltando i segmenti prima della cornice', () {
      final d = ImageDims.fromBytes(_jpeg(4032, 3024));
      expect(d, isNotNull);
      expect(d!.width, 4032);
      expect(d.height, 3024);
    });

    test('JPEG senza segmenti da saltare', () {
      final d = ImageDims.fromBytes(_jpeg(100, 200, conTrappola: false));
      expect(d!.width, 100);
      expect(d.height, 200);
    });

    test('BMP con altezza negativa: il segno è il verso, non la misura', () {
      final b = Uint8List(30);
      b[0] = 0x42;
      b[1] = 0x4D;
      // larghezza 40
      b[18] = 40;
      // altezza -30, in complemento a due
      b.setAll(22, [0xE2, 0xFF, 0xFF, 0xFF]);
      final d = ImageDims.fromBytes(b);
      expect(d!.width, 40);
      expect(d.height, 30);
    });

    test('un formato che non conosciamo dice di non saperlo', () {
      final b = Uint8List(64);
      b.setAll(0, 'non sono un immagine'.codeUnits);
      expect(ImageDims.fromBytes(b), isNull);
    });

    test('un file troncato non fa saltare niente', () {
      expect(ImageDims.fromBytes(Uint8List(4)), isNull);
      expect(ImageDims.fromBytes(_png(10, 10).sublist(0, 20)), isNull);
    });
  });

  group('ImageDims.read', () {
    test('un file che non esiste dice di non saperlo', () {
      expect(ImageDims.read('/tmp/questo-file-non-esiste-mai.png'), isNull);
    });
  });
}
