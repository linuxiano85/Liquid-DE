import 'dart:typed_data';

/// SHA-256, scritto a mano.
///
/// ── Perché a mano ──────────────────────────────────────────────────────────
///
/// Il demone non ha dipendenze esterne, di proposito (vedi `pubspec.yaml`), e
/// la libreria standard di Dart non ha nessun digest. Serve a parlare con gli
/// apparecchi di casa: il protocollo locale dei condizionatori Midea firma
/// ogni messaggio con uno SHA-256, e lo stesso vale per Tuya e per quasi
/// tutti gli altri.
///
/// ── Perché scriverlo non è un azzardo ─────────────────────────────────────
///
/// Perché non c'è niente da indovinare. SHA-256 è FIPS 180-4, e il NIST
/// pubblica i **vettori di prova ufficiali**: si scrive l'algoritmo e si
/// controlla che dia esattamente quei valori. È il caso raro in cui «l'ho
/// scritto io» e «è giusto» si possono affermare tutti e due, con una prova
/// che non dipende da nessun apparecchio acceso.
///
/// Quello che questo file NON è: un sostituto di una libreria crittografica
/// per proteggere dei segreti. Qui serve a **parlare un protocollo** — a
/// firmare un messaggio che dice «accendi il condizionatore» in un modo che
/// il condizionatore riconosca. Non c'è nessuna chiave nostra da difendere.
class Sha256 {
  static const List<int> _k = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  /// Il digest di `dati`: 32 byte.
  static Uint8List digest(List<int> dati) {
    // ── L'imbottitura, che è dove si sbaglia ──────────────────────────────
    //
    // Un bit a 1, poi zeri fino a lasciare otto byte in fondo, e lì la
    // lunghezza in BIT — non in byte — a 64 bit big-endian. Scriverla in byte
    // è l'errore classico: dà un digest plausibile e sbagliato, e i vettori
    // del NIST lo prendono al primo colpo.
    final lunghezzaBit = dati.length * 8;
    final quanti = ((dati.length + 9 + 63) ~/ 64) * 64;
    final m = Uint8List(quanti);
    m.setRange(0, dati.length, dati);
    m[dati.length] = 0x80;
    final vista = ByteData.view(m.buffer);
    vista.setUint64(quanti - 8, lunghezzaBit);

    var h0 = 0x6a09e667, h1 = 0xbb67ae85, h2 = 0x3c6ef372, h3 = 0xa54ff53a;
    var h4 = 0x510e527f, h5 = 0x9b05688c, h6 = 0x1f83d9ab, h7 = 0x5be0cd19;

    final w = Uint32List(64);
    for (var blocco = 0; blocco < quanti; blocco += 64) {
      for (var i = 0; i < 16; i++) {
        w[i] = vista.getUint32(blocco + i * 4);
      }
      for (var i = 16; i < 64; i++) {
        final s0 = _ruota(w[i - 15], 7) ^ _ruota(w[i - 15], 18) ^ (w[i - 15] >> 3);
        final s1 = _ruota(w[i - 2], 17) ^ _ruota(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xFFFFFFFF;
      }

      var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;
      for (var i = 0; i < 64; i++) {
        final sigma1 = _ruota(e, 6) ^ _ruota(e, 11) ^ _ruota(e, 25);
        final ch = (e & f) ^ ((~e & 0xFFFFFFFF) & g);
        final t1 = (h + sigma1 + ch + _k[i] + w[i]) & 0xFFFFFFFF;
        final sigma0 = _ruota(a, 2) ^ _ruota(a, 13) ^ _ruota(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final t2 = (sigma0 + maj) & 0xFFFFFFFF;
        h = g; g = f; f = e;
        e = (d + t1) & 0xFFFFFFFF;
        d = c; c = b; b = a;
        a = (t1 + t2) & 0xFFFFFFFF;
      }
      h0 = (h0 + a) & 0xFFFFFFFF; h1 = (h1 + b) & 0xFFFFFFFF;
      h2 = (h2 + c) & 0xFFFFFFFF; h3 = (h3 + d) & 0xFFFFFFFF;
      h4 = (h4 + e) & 0xFFFFFFFF; h5 = (h5 + f) & 0xFFFFFFFF;
      h6 = (h6 + g) & 0xFFFFFFFF; h7 = (h7 + h) & 0xFFFFFFFF;
    }

    final fuori = Uint8List(32);
    final v = ByteData.view(fuori.buffer);
    v.setUint32(0, h0); v.setUint32(4, h1); v.setUint32(8, h2);
    v.setUint32(12, h3); v.setUint32(16, h4); v.setUint32(20, h5);
    v.setUint32(24, h6); v.setUint32(28, h7);
    return fuori;
  }

  /// Rotazione a destra su 32 bit. In Dart `>>` su un `int` a 64 bit non
  /// perde i bit alti da solo: la mascheratura è obbligatoria, e dimenticarla
  /// dà un digest che sembra giusto sui messaggi corti.
  static int _ruota(int x, int n) =>
      ((x >> n) | (x << (32 - n))) & 0xFFFFFFFF;

  static String esadecimale(List<int> byte) =>
      byte.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
