// SHA-256 scritto a mano, provato contro i vettori UFFICIALI.
//
// I valori qui sotto non li ho calcolati io: vengono da FIPS 180-4 e dalle
// «NIST Cryptographic Algorithm Validation Program» byte-oriented test
// vectors. È il caso raro in cui «l'ho scritto io» e «è giusto» si possono
// affermare tutti e due, senza dipendere da nessun apparecchio acceso.
//
// Serve a parlare coi condizionatori (il protocollo locale Midea firma ogni
// messaggio con uno SHA-256) e servirà a Tuya e a chiunque altro.
import 'dart:convert';

import 'package:minervad/services/casa/sha256.dart';
import 'package:test/test.dart';

void main() {
  String h(List<int> d) => Sha256.esadecimale(Sha256.digest(d));

  test('i vettori di FIPS 180-4', () {
    expect(h(utf8.encode('abc')),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    expect(h(utf8.encode('')),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    expect(
        h(utf8.encode('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq')),
        '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1');
    // Quello lungo due blocchi e mezzo: prende gli errori di imbottitura che
    // i messaggi corti non fanno vedere.
    expect(
        h(utf8.encode('abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmn'
            'hijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu')),
        'cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1');
  });

  test('il milione di «a», che è il vettore che prende i conti a 64 bit', () {
    // La lunghezza va scritta in BIT e a 64 bit: scriverla in byte, o a 32
    // bit, dà un digest plausibile e sbagliato — e si vede solo qui.
    expect(h(List<int>.filled(1000000, 0x61)),
        'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0');
  });

  test('un byte in più cambia tutto', () {
    final a = h(utf8.encode('Minerva'));
    final b = h(utf8.encode('Minervb'));
    expect(a, isNot(b));
    expect(a.length, 64);
  });

  test('le lunghezze attorno al confine di blocco', () {
    // 55, 56, 63, 64, 65 byte: è dove l'imbottitura decide se serve un blocco
    // in più, ed è l'unico punto dove un'implementazione sbagliata può ancora
    // sembrare giusta.
    const atteso = {
      55: '9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318',
      56: 'b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a',
      63: '7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34',
      64: 'ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb',
      65: '635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0',
    };
    atteso.forEach((quanti, valore) {
      expect(h(List<int>.filled(quanti, 0x61)), valore, reason: '$quanti byte');
    });
  });
}
