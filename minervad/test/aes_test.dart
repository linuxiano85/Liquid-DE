// AES-128 scritto a mano, provato contro i vettori UFFICIALI.
//
// I valori non li ho calcolati io: vengono da FIPS-197 (appendice B e C.1) e
// da NIST SP 800-38A (i modi ECB e CBC). Un'implementazione di AES o dà
// esattamente quei byte o è sbagliata: non esistono vie di mezzo, e non serve
// nessun apparecchio acceso per saperlo.
//
// Serve a parlare coi condizionatori di casa (il protocollo locale Midea cifra
// in AES-CBC e la scoperta in AES-ECB) e servirà a Tuya.
import 'dart:typed_data';

import 'package:minervad/services/casa/aes.dart';
import 'package:test/test.dart';

Uint8List da(String esa) {
  final b = Uint8List(esa.length ~/ 2);
  for (var i = 0; i < b.length; i++) {
    b[i] = int.parse(esa.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return b;
}

String a(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('FIPS-197 C.1: il blocco della specifica', () {
    final k = da('000102030405060708090a0b0c0d0e0f');
    final chiaro = da('00112233445566778899aabbccddeeff');
    final atteso = '69c4e0d86a7b0430d8cdb78070b4c55a';
    final aes = Aes128(k);
    expect(a(aes.cifraEcb(chiaro)), atteso);
    expect(a(aes.decifraEcb(da(atteso))), a(chiaro));
  });

  test('FIPS-197 B: l\'esempio svolto passo per passo', () {
    final aes = Aes128(da('2b7e151628aed2a6abf7158809cf4f3c'));
    expect(a(aes.cifraEcb(da('3243f6a8885a308d313198a2e0370734'))),
        '3925841d02dc09fbdc118597196a0b32');
  });

  group('NIST SP 800-38A — ECB', () {
    final aes = Aes128(da('2b7e151628aed2a6abf7158809cf4f3c'));
    const coppie = {
      '6bc1bee22e409f96e93d7e117393172a': '3ad77bb40d7a3660a89ecaf32466ef97',
      'ae2d8a571e03ac9c9eb76fac45af8e51': 'f5d3d58503b9699de785895a96fdbaaf',
      '30c81c46a35ce411e5fbc1191a0a52ef': '43b1cd7f598ece23881b00e3ed030688',
      'f69f2445df4f9b17ad2b417be66c3710': '7b0c785e27e8ad3f8223207104725dd4',
    };
    test('cifra e decifra tutti e quattro i blocchi', () {
      coppie.forEach((chiaro, cifrato) {
        expect(a(aes.cifraEcb(da(chiaro))), cifrato, reason: chiaro);
        expect(a(aes.decifraEcb(da(cifrato))), chiaro, reason: cifrato);
      });
    });
  });

  group('NIST SP 800-38A — CBC', () {
    final k = da('2b7e151628aed2a6abf7158809cf4f3c');
    final iv = da('000102030405060708090a0b0c0d0e0f');
    final chiaro = da('6bc1bee22e409f96e93d7e117393172a'
        'ae2d8a571e03ac9c9eb76fac45af8e51'
        '30c81c46a35ce411e5fbc1191a0a52ef'
        'f69f2445df4f9b17ad2b417be66c3710');
    const cifrato = '7649abac8119b246cee98e9b12e9197d'
        '5086cb9b507219ee95db113a917678b2'
        '73bed6b8e3c1743b7116e69e22229516'
        '3ff1caa1681fac09120eca307586e1a7';

    test('i quattro blocchi incatenati', () {
      final aes = Aes128(k);
      expect(a(aes.cifraCbc(chiaro, iv: iv)), cifrato);
      expect(a(aes.decifraCbc(da(cifrato), iv: iv)), a(chiaro));
    });

    test('e con IV di zeri, che è quello che usa Midea', () {
      final aes = Aes128(k);
      final c = aes.cifraCbc(chiaro);
      expect(a(aes.decifraCbc(c)), a(chiaro));
      // Con IV diverso il risultato DEVE cambiare: se non cambiasse, l'IV non
      // starebbe entrando nel conto e il primo blocco sarebbe ECB travestito.
      expect(a(c), isNot(cifrato));
    });
  });

  group('i rifiuti', () {
    test('una chiave che non è di 16 byte', () {
      expect(() => Aes128(da('00112233')), throwsArgumentError);
      expect(() => Aes128(List<int>.filled(32, 0)), throwsArgumentError);
    });

    test('dati che non sono un multiplo di 16', () {
      final aes = Aes128(da('000102030405060708090a0b0c0d0e0f'));
      // Il messaggio deve dire ANCHE di chi è la colpa: ogni protocollo di
      // casa fa l'imbottitura a modo suo, e farla qui vorrebbe dire farla due
      // volte.
      expect(() => aes.cifraEcb(List<int>.filled(17, 0)), throwsArgumentError);
      expect(() => aes.cifraCbc(List<int>.filled(1, 0)), throwsArgumentError);
    });
  });

  test('cifrare e decifrare torna sempre indietro, su dati a caso', () {
    // Non sostituisce i vettori ufficiali: prende il caso in cui una tabella
    // inversa sbagliata funziona per i quattro blocchi del NIST e non per gli
    // altri.
    final aes = Aes128(da('603deb1015ca71be2b73aef0857d7781'));
    var seme = 12345;
    for (var giro = 0; giro < 40; giro++) {
      final n = (1 + giro % 5) * 16;
      final d = Uint8List(n);
      for (var i = 0; i < n; i++) {
        seme = (seme * 1103515245 + 12345) & 0x7FFFFFFF;
        d[i] = seme & 0xFF;
      }
      expect(a(aes.decifraEcb(aes.cifraEcb(d))), a(d), reason: 'ECB giro $giro');
      expect(a(aes.decifraCbc(aes.cifraCbc(d))), a(d), reason: 'CBC giro $giro');
    }
  });
}
