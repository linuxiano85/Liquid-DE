import 'dart:io';
import 'dart:typed_data';

/// Le misure di un'immagine, lette dall'INTESTAZIONE del file.
///
/// ── Perché esiste ──────────────────────────────────────────────────────────
///
/// Anteprima deve decidere quanto in grande decodificare un'immagine PRIMA di
/// decodificarla. Sembra un paradosso e non lo è: la larghezza e l'altezza
/// stanno nei primi byte del file, mentre i pixel — che sono il costo — stanno
/// dopo. Una fotografia da 1840×4080 occupa trenta megabyte decodificata, e per
/// mostrarla dentro una finestra da 1180×662 ne servono tre.
///
/// Senza questo, l'unico modo di sapere quanto è grande un'immagine è aprirla
/// tutta, cioè pagare esattamente il prezzo che si voleva evitare.
///
/// ── Perché nel demone ──────────────────────────────────────────────────────
///
/// Perché è lettura di file, e il confine è quello: la shell disegna, il demone
/// sa. Costa una `open` e sedici byte letti — meno di quanto costi decidere di
/// non farlo.
///
/// Si leggono i formati che coprono tutto quello che si incontra davvero. Per
/// gli altri si risponde `null`, e chi chiama torna a fare come prima: è un
/// suggerimento, non un contratto.
class ImageDims {
  final int width;
  final int height;
  const ImageDims(this.width, this.height);

  Map<String, int> toJson() => {'width': width, 'height': height};

  /// Legge le misure dall'intestazione del file. `null` se il formato non si
  /// riconosce o il file è troppo corto.
  static ImageDims? read(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      final raf = file.openSync();
      try {
        // Sessantaquattro byte bastano per PNG, GIF, BMP e WEBP: lì le misure
        // stanno a una posizione fissa.
        final testa = raf.readSync(64);
        if (testa.length < 12) return null;
        if (!(testa[0] == 0xFF && testa[1] == 0xD8)) return fromBytes(testa);
        // Il JPEG no: bisogna CAMMINARE fra i segmenti, e in una fotografia di
        // telefono la cornice arriva dopo un EXIF che può essere lungo
        // sessanta kilobyte perché ci sta dentro una miniatura. Leggerne un
        // blocco fisso e sperare è esattamente il primo tentativo che ho fatto,
        // e su tutte le foto vere rispondeva «non lo so».
        return _jpegDaFile(raf, raf.lengthSync());
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      return null;
    }
  }

  /// La camminata sul file: due byte di marcatore, due di lunghezza, e un
  /// salto. Nessun buffer grande, una decina di letture da quattro byte.
  static ImageDims? _jpegDaFile(RandomAccessFile raf, int lunghezzaFile) {
    var i = 2;
    // Un tetto ai segmenti: un file rotto non deve poterci tenere qui dentro.
    for (var giri = 0; giri < 256; giri++) {
      if (i + 4 > lunghezzaFile) return null;
      raf.setPositionSync(i);
      final t = raf.readSync(4);
      if (t.length < 4) return null;
      if (t[0] != 0xFF) {
        i++; // byte di riempimento fra un segmento e l'altro
        continue;
      }
      final marker = t[1];
      if (marker == 0xD8 || marker == 0x01 ||
          (marker >= 0xD0 && marker <= 0xD7)) {
        i += 2;
        continue;
      }
      if (marker == 0xD9 || marker == 0xDA) return null; // fine, o dati
      final lunghezza = (t[2] << 8) | t[3];
      if (lunghezza < 2) return null;
      // SOF0…SOF15 sono le cornici. Si escludono 0xC4 (tabelle di Huffman),
      // 0xC8 (estensione) e 0xCC (aritmetica): stanno in mezzo alla serie e
      // NON sono cornici — leggerli darebbe due numeri qualunque.
      final eCornice = marker >= 0xC0 && marker <= 0xCF &&
          marker != 0xC4 && marker != 0xC8 && marker != 0xCC;
      if (eCornice) {
        raf.setPositionSync(i + 5);
        final m = raf.readSync(4);
        if (m.length < 4) return null;
        return ImageDims((m[2] << 8) | m[3], (m[0] << 8) | m[1]);
      }
      i += 2 + lunghezza;
    }
    return null;
  }

  /// La parte pura, che si può provare senza toccare il disco.
  static ImageDims? fromBytes(Uint8List b) {
    if (b.length < 12) return null;

    // ── PNG ──────────────────────────────────────────────────────────────
    // Firma di otto byte, poi il chunk IHDR: larghezza e altezza a 16 e 20.
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
      if (b.length < 24) return null;
      return ImageDims(_be32(b, 16), _be32(b, 20));
    }

    // ── GIF ──────────────────────────────────────────────────────────────
    // «GIF87a» o «GIF89a», poi due interi a 16 bit little-endian.
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) {
      return ImageDims(_le16(b, 6), _le16(b, 8));
    }

    // ── BMP ──────────────────────────────────────────────────────────────
    if (b[0] == 0x42 && b[1] == 0x4D) {
      if (b.length < 26) return null;
      // L'altezza può essere negativa: vuol dire che le righe sono scritte
      // dall'alto in basso invece che dal basso in alto. La misura è la
      // stessa, il segno riguarda l'ordine.
      final h = _le32(b, 22);
      return ImageDims(_le32(b, 18), h < 0 ? -h : h);
    }

    // ── WEBP ─────────────────────────────────────────────────────────────
    // «RIFF» … «WEBP», e poi tre varianti che scrivono le misure in tre
    // posti diversi. Sono tre formati con un cappello in comune.
    if (b.length >= 30 &&
        b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
        b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
      final tipo = String.fromCharCodes(b.sublist(12, 16));
      if (tipo == 'VP8 ') {
        // I due byte a 26 e 28 hanno due bit di scala in cima.
        return ImageDims(_le16(b, 26) & 0x3FFF, _le16(b, 28) & 0x3FFF);
      }
      if (tipo == 'VP8L') {
        // Quattordici bit per larghezza e altezza, impacchettati in 32 bit,
        // e valgono meno uno.
        final bits = _le32(b, 21);
        return ImageDims((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1);
      }
      if (tipo == 'VP8X') {
        // Ventiquattro bit ciascuna, meno uno, a partire da 24.
        final w = b[24] | (b[25] << 8) | (b[26] << 16);
        final h = b[27] | (b[28] << 8) | (b[29] << 16);
        return ImageDims(w + 1, h + 1);
      }
      return null;
    }

    // ── JPEG ─────────────────────────────────────────────────────────────
    //
    // Qui non c'è una posizione fissa: bisogna CAMMINARE fra i segmenti
    // finché non si trova quello che dichiara la cornice (SOF). È il motivo
    // per cui questo formato sta per ultimo e non per primo.
    if (b[0] == 0xFF && b[1] == 0xD8) {
      var i = 2;
      while (i + 9 < b.length) {
        if (b[i] != 0xFF) {
          // Byte di riempimento fra un segmento e l'altro: si scorre.
          i++;
          continue;
        }
        final marker = b[i + 1];
        // I marcatori senza corpo: si saltano di due byte e basta.
        if (marker == 0xD8 || marker == 0x01 ||
            (marker >= 0xD0 && marker <= 0xD7)) {
          i += 2;
          continue;
        }
        if (marker == 0xD9 || marker == 0xDA) return null; // fine, o dati
        final lunghezza = _be16(b, i + 2);
        if (lunghezza < 2) return null;
        // SOF0…SOF15 sono le cornici. Si escludono 0xC4 (tabelle di Huffman),
        // 0xC8 (estensione) e 0xCC (aritmetica): stanno in mezzo alla serie e
        // NON sono cornici — leggerli darebbe due numeri qualunque.
        final eCornice = marker >= 0xC0 && marker <= 0xCF &&
            marker != 0xC4 && marker != 0xC8 && marker != 0xCC;
        if (eCornice) {
          if (i + 9 >= b.length) return null;
          // Dentro al segmento: precisione (1 byte), altezza, larghezza.
          return ImageDims(_be16(b, i + 7), _be16(b, i + 5));
        }
        i += 2 + lunghezza;
      }
      return null;
    }

    return null;
  }

  static int _be16(Uint8List b, int i) => (b[i] << 8) | b[i + 1];
  static int _be32(Uint8List b, int i) =>
      (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
  static int _le16(Uint8List b, int i) => b[i] | (b[i + 1] << 8);
  static int _le32(Uint8List b, int i) {
    final v = b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24);
    // Dart non ha interi a 32 bit: il bit alto va riportato a mano, o
    // un'altezza negativa di un BMP diventa due miliardi.
    return v >= 0x80000000 ? v - 0x100000000 : v;
  }
}
