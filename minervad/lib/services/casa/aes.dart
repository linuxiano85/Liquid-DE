import 'dart:typed_data';

/// AES-128, scritto a mano: ECB e CBC.
///
/// ── Perché a mano, e perché si può dire che è giusto ──────────────────────
///
/// Il demone non ha dipendenze esterne, di proposito, e Dart non ha AES nella
/// libreria standard. Serve a parlare con gli apparecchi di casa: il
/// protocollo locale dei condizionatori Midea cifra ogni messaggio in AES-CBC
/// e la risposta della scoperta in AES-ECB; Tuya fa lo stesso.
///
/// Non c'è niente da indovinare: AES è FIPS-197 e i modi sono NIST SP 800-38A,
/// e tutti e due pubblicano i **vettori di prova ufficiali**. Si scrive, e si
/// controlla che dia esattamente quei numeri (`test/aes_test.dart`).
///
/// ── Che cosa questo file NON è ────────────────────────────────────────────
///
/// Non è una libreria crittografica per proteggere segreti. Serve a
/// **parlare un protocollo**: a comporre un messaggio che dica «che
/// temperatura hai?» in un modo che il condizionatore riconosca. Non difende
/// niente di nostro, e non va usato per farlo — per quello ci sono il
/// portachiavi e TLS, che li fa qualcun altro e meglio.
///
/// Un limite dichiarato: nessuna difesa dai «timing attack». Per un
/// condizionatore in salotto non ha senso; se un giorno questo codice servisse
/// ad altro, la prima cosa da rifare è questa riga.
class Aes128 {
  /// La tabella di sostituzione di AES. Sta scritta invece che calcolata: è
  /// nella specifica così, e un lettore che vuole controllarla la confronta
  /// con FIPS-197 riga per riga invece di dover credere a un conto.
  static const List<int> _s = [
    0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
    0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
    0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
    0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
    0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
    0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
    0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
    0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
    0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
    0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
    0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
    0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
    0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
    0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
    0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
    0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16,
  ];

  /// L'inversa, costruita una volta sola dalla tabella diretta: due tabelle
  /// scritte a mano sono due occasioni di sbagliare, e la seconda si ricava
  /// dalla prima senza ambiguità.
  static final Uint8List _si = () {
    final t = Uint8List(256);
    for (var i = 0; i < 256; i++) {
      t[_s[i]] = i;
    }
    return t;
  }();

  static const List<int> _rcon = [
    0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36
  ];

  final Uint8List _chiavi; // 11 sottochiavi da 16 byte

  Aes128(List<int> chiave) : _chiavi = _espandi(chiave) {
    if (chiave.length != 16) {
      throw ArgumentError('AES-128 vuole una chiave di 16 byte, '
          'non ${chiave.length}');
    }
  }

  static Uint8List _espandi(List<int> chiave) {
    if (chiave.length != 16) {
      throw ArgumentError('AES-128 vuole una chiave di 16 byte, '
          'non ${chiave.length}');
    }
    final w = Uint8List(176);
    w.setRange(0, 16, chiave);
    for (var i = 16; i < 176; i += 4) {
      var a = w[i - 4], b = w[i - 3], c = w[i - 2], d = w[i - 1];
      if (i % 16 == 0) {
        // Rotazione di un byte, sostituzione, e la costante del giro.
        final t = a;
        a = _s[b] ^ _rcon[i ~/ 16 - 1];
        b = _s[c];
        c = _s[d];
        d = _s[t];
      }
      w[i] = w[i - 16] ^ a;
      w[i + 1] = w[i - 15] ^ b;
      w[i + 2] = w[i - 14] ^ c;
      w[i + 3] = w[i - 13] ^ d;
    }
    return w;
  }

  /// Moltiplicazione nel campo di Galois GF(2^8), che è tutta l'aritmetica
  /// strana di AES. `0x1b` è il polinomio della specifica.
  static int _mul(int a, int b) {
    var r = 0;
    for (var i = 0; i < 8; i++) {
      if (b & 1 != 0) r ^= a;
      final alto = a & 0x80;
      a = (a << 1) & 0xFF;
      if (alto != 0) a ^= 0x1b;
      b >>= 1;
    }
    return r;
  }

  void _giroChiave(Uint8List b, int giro) {
    for (var i = 0; i < 16; i++) {
      b[i] ^= _chiavi[giro * 16 + i];
    }
  }

  void _cifraBlocco(Uint8List b) {
    _giroChiave(b, 0);
    for (var giro = 1; giro <= 10; giro++) {
      for (var i = 0; i < 16; i++) {
        b[i] = _s[b[i]];
      }
      _spostaRighe(b, false);
      if (giro != 10) _mescolaColonne(b, false);
      _giroChiave(b, giro);
    }
  }

  void _decifraBlocco(Uint8List b) {
    _giroChiave(b, 10);
    for (var giro = 9; giro >= 0; giro--) {
      _spostaRighe(b, true);
      for (var i = 0; i < 16; i++) {
        b[i] = _si[b[i]];
      }
      _giroChiave(b, giro);
      if (giro != 0) _mescolaColonne(b, true);
    }
  }

  /// Lo stato di AES è una matrice 4×4 riempita **per colonne**: il byte `i`
  /// sta in riga `i % 4`, colonna `i ~/ 4`. Confondere le due è l'errore che
  /// dà un risultato di lunghezza giusta e valore sbagliato.
  static void _spostaRighe(Uint8List b, bool indietro) {
    final t = Uint8List.fromList(b);
    for (var riga = 1; riga < 4; riga++) {
      for (var col = 0; col < 4; col++) {
        final da = indietro ? (col - riga) % 4 : (col + riga) % 4;
        b[riga + 4 * col] = t[riga + 4 * ((da + 4) % 4)];
      }
    }
  }

  static void _mescolaColonne(Uint8List b, bool indietro) {
    for (var c = 0; c < 4; c++) {
      final o = c * 4;
      final a0 = b[o], a1 = b[o + 1], a2 = b[o + 2], a3 = b[o + 3];
      if (!indietro) {
        b[o] = _mul(a0, 2) ^ _mul(a1, 3) ^ a2 ^ a3;
        b[o + 1] = a0 ^ _mul(a1, 2) ^ _mul(a2, 3) ^ a3;
        b[o + 2] = a0 ^ a1 ^ _mul(a2, 2) ^ _mul(a3, 3);
        b[o + 3] = _mul(a0, 3) ^ a1 ^ a2 ^ _mul(a3, 2);
      } else {
        b[o] = _mul(a0, 14) ^ _mul(a1, 11) ^ _mul(a2, 13) ^ _mul(a3, 9);
        b[o + 1] = _mul(a0, 9) ^ _mul(a1, 14) ^ _mul(a2, 11) ^ _mul(a3, 13);
        b[o + 2] = _mul(a0, 13) ^ _mul(a1, 9) ^ _mul(a2, 14) ^ _mul(a3, 11);
        b[o + 3] = _mul(a0, 11) ^ _mul(a1, 13) ^ _mul(a2, 9) ^ _mul(a3, 14);
      }
    }
  }

  // ── I due modi che servono ──────────────────────────────────────────────
  //
  // Nessuna imbottitura: chi chiama passa già un multiplo di 16. È una scelta,
  // non una dimenticanza — i protocolli di casa l'imbottitura la fanno a modo
  // loro (Midea ci mette byte casuali, non PKCS#7), e farla qui vorrebbe dire
  // farla due volte.

  Uint8List cifraEcb(List<int> dati) => _ecb(dati, true);
  Uint8List decifraEcb(List<int> dati) => _ecb(dati, false);

  Uint8List _ecb(List<int> dati, bool avanti) {
    _controlla(dati);
    final fuori = Uint8List.fromList(dati);
    for (var o = 0; o < fuori.length; o += 16) {
      final b = Uint8List.sublistView(fuori, o, o + 16);
      if (avanti) {
        _cifraBlocco(b);
      } else {
        _decifraBlocco(b);
      }
    }
    return fuori;
  }

  /// CBC. `iv` vuoto vuol dire sedici zeri: è quello che usa Midea, ed è
  /// scritto qui perché chi legge non debba scoprirlo altrove.
  Uint8List cifraCbc(List<int> dati, {List<int>? iv}) {
    _controlla(dati);
    final prec = Uint8List(16)..setRange(0, 16, iv ?? Uint8List(16));
    final fuori = Uint8List.fromList(dati);
    for (var o = 0; o < fuori.length; o += 16) {
      for (var i = 0; i < 16; i++) {
        fuori[o + i] ^= prec[i];
      }
      final b = Uint8List.sublistView(fuori, o, o + 16);
      _cifraBlocco(b);
      prec.setRange(0, 16, b);
    }
    return fuori;
  }

  Uint8List decifraCbc(List<int> dati, {List<int>? iv}) {
    _controlla(dati);
    var prec = Uint8List(16)..setRange(0, 16, iv ?? Uint8List(16));
    final fuori = Uint8List.fromList(dati);
    for (var o = 0; o < fuori.length; o += 16) {
      final cifrato = Uint8List.fromList(fuori.sublist(o, o + 16));
      final b = Uint8List.sublistView(fuori, o, o + 16);
      _decifraBlocco(b);
      for (var i = 0; i < 16; i++) {
        fuori[o + i] ^= prec[i];
      }
      prec = cifrato;
    }
    return fuori;
  }

  static void _controlla(List<int> dati) {
    if (dati.length % 16 != 0) {
      throw ArgumentError('AES lavora a blocchi di 16 byte: ne sono arrivati '
          '${dati.length}. L\'imbottitura la mette chi chiama, perché ogni '
          'protocollo la fa a modo suo.');
    }
  }
}
