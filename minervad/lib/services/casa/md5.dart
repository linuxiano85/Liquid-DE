import 'dart:typed_data';

/// MD5, scritto a mano.
///
/// ── Perché ce n'è bisogno, e perché proprio MD5 ───────────────────────────
///
/// Non lo scegliamo noi: lo sceglie chi ha scritto il protocollo. La nube di
/// Midea — quella dietro l'applicazione **NetHome Plus**, che è quella che usa
/// Giacomo — deriva la chiave con cui cifra il gettone di accesso da un MD5
/// della chiave dell'applicazione, e la scoperta locale dei condizionatori
/// cifra la risposta in AES con una chiave che è a sua volta un MD5.
///
/// MD5 è **rotto** per quello a cui serviva (firmare, distinguere), e questo
/// file non va usato per quello: non è un modo per verificare che un file sia
/// integro né per proteggere una password. Serve a **parlare un protocollo**
/// già esistente, dove è l'altro capo a pretenderlo. Se un giorno qualcuno
/// cercasse un digest in questo progetto, quello giusto è [Sha256].
///
/// ── Perché scriverlo non è un azzardo ─────────────────────────────────────
///
/// Perché non c'è niente da indovinare. MD5 è RFC 1321, e la RFC pubblica
/// nell'appendice A.5 i **vettori di prova ufficiali**: si scrive
/// l'algoritmo e si controlla che dia esattamente quei valori
/// (`test/md5_test.dart`). È il caso in cui «l'ho scritto io» e «è giusto»
/// stanno insieme, con una prova che non dipende da nessun apparecchio acceso.
class Md5 {
  /// Le rotazioni, quattro giri da sedici. Stanno scritte invece che
  /// calcolate: nella RFC sono una tabella, e chi controlla le confronta riga
  /// per riga invece di dover credere a un conto.
  static const List<int> _s = [
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, //
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, //
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, //
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
  ];

  /// `_k[i] = floor(2^32 * abs(sin(i + 1)))`, con l'angolo in radianti.
  /// Scritte, per lo stesso motivo di [_s]: la RFC le dà così.
  static const List<int> _k = [
    0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, //
    0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
    0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
    0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
    0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
    0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
    0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
    0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
    0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
    0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
    0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
    0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
    0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
    0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
    0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
    0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
  ];

  static int _ruota(int x, int n) =>
      ((x << n) | (x >>> (32 - n))) & 0xffffffff;

  /// Il digest di [dati]: sedici byte.
  static Uint8List digest(List<int> dati) {
    // Riempimento: un bit a 1, poi zeri fino a 56 byte su 64, poi la
    // lunghezza in BIT su otto byte **little endian**. È l'unico posto dove
    // MD5 si comporta al contrario di SHA-256, ed è l'errore classico.
    final lunghezzaInBit = dati.length * 8;
    final resto = (dati.length + 1) % 64;
    final zeri = resto <= 56 ? 56 - resto : 120 - resto;
    final m = Uint8List(dati.length + 1 + zeri + 8);
    m.setRange(0, dati.length, dati);
    m[dati.length] = 0x80;
    final coda = ByteData.sublistView(m, m.length - 8);
    coda.setUint32(0, lunghezzaInBit & 0xffffffff, Endian.little);
    coda.setUint32(4, (lunghezzaInBit >>> 32) & 0xffffffff, Endian.little);

    var a0 = 0x67452301, b0 = 0xefcdab89, c0 = 0x98badcfe, d0 = 0x10325476;
    final blocco = ByteData.sublistView(m);
    final w = Int32List(16);

    for (var off = 0; off < m.length; off += 64) {
      for (var i = 0; i < 16; i++) {
        w[i] = blocco.getUint32(off + i * 4, Endian.little);
      }
      var a = a0, b = b0, c = c0, d = d0;
      for (var i = 0; i < 64; i++) {
        int f, g;
        if (i < 16) {
          f = (b & c) | (~b & d);
          g = i;
        } else if (i < 32) {
          f = (d & b) | (~d & c);
          g = (5 * i + 1) % 16;
        } else if (i < 48) {
          f = b ^ c ^ d;
          g = (3 * i + 5) % 16;
        } else {
          f = c ^ (b | (~d & 0xffffffff));
          g = (7 * i) % 16;
        }
        f = (f + a + _k[i] + (w[g] & 0xffffffff)) & 0xffffffff;
        a = d;
        d = c;
        c = b;
        b = (b + _ruota(f, _s[i])) & 0xffffffff;
      }
      a0 = (a0 + a) & 0xffffffff;
      b0 = (b0 + b) & 0xffffffff;
      c0 = (c0 + c) & 0xffffffff;
      d0 = (d0 + d) & 0xffffffff;
    }

    final fuori = Uint8List(16);
    final v = ByteData.sublistView(fuori);
    v.setUint32(0, a0, Endian.little);
    v.setUint32(4, b0, Endian.little);
    v.setUint32(8, c0, Endian.little);
    v.setUint32(12, d0, Endian.little);
    return fuori;
  }

  /// Lo stesso digest, in cifre esadecimali minuscole: è il modo in cui i
  /// protocolli che ci interessano lo scrivono e lo confrontano.
  static String esa(List<int> dati) {
    final b = StringBuffer();
    for (final x in digest(dati)) {
      b.write(x.toRadixString(16).padLeft(2, '0'));
    }
    return b.toString();
  }
}
