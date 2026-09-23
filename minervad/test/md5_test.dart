// MD5 scritto a mano, provato contro i vettori UFFICIALI.
//
// I valori qui sotto non li ho calcolati io: sono la «MD5 test suite»
// dell'appendice A.5 della RFC 1321, cioè li ha pubblicati chi ha definito
// l'algoritmo. È il caso in cui «l'ho scritto io» e «è giusto» si possono
// affermare tutti e due senza dipendere da nessun apparecchio acceso.
//
// Serve a parlare con la nube di Midea — quella dietro NetHome Plus — che
// deriva da un MD5 la chiave con cui cifra il gettone di accesso, e con la
// scoperta locale dei condizionatori, che cifra la risposta in AES con una
// chiave che è a sua volta un MD5. Non serve, e non va usato, per proteggere
// niente di nostro: per quello c'è Sha256.
import 'dart:convert';

import 'package:minervad/services/casa/md5.dart';
import 'package:test/test.dart';

void main() {
  String h(String s) => Md5.esa(utf8.encode(s));

  test('la suite dell\'appendice A.5 della RFC 1321', () {
    expect(h(''), 'd41d8cd98f00b204e9800998ecf8427e');
    expect(h('a'), '0cc175b9c0f1b6a831c399e269772661');
    expect(h('abc'), '900150983cd24fb0d6963f7d28e17f72');
    expect(h('message digest'), 'f96b697d7cb7938d525a2f31aaf161d0');
    expect(h('abcdefghijklmnopqrstuvwxyz'), 'c3fcd3d76192e4007dfb496cca67e13b');
    expect(
        h('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'),
        'd174ab98d277d9f5a5611c2c9f419d9f');
    // Ottanta caratteri: due blocchi pieni più la coda. È quello che prende
    // gli errori di imbottitura che i messaggi corti non fanno vedere.
    expect(
        h('123456789012345678901234567890123456789012345678901234567890'
            '12345678901234567890'),
        '57edf4a22be3c955ac49da2e2107b67a');
  });

  test('la lunghezza si scrive al contrario di SHA-256', () {
    // In MD5 la lunghezza finale è little endian; in SHA-256 è big endian.
    // Sbagliarla dà un digest plausibile, e si vede solo su un messaggio
    // abbastanza lungo da farla contare oltre un byte.
    expect(h('a' * 1000),
        'cabe45dcc9ae5b66ba86600cca6b8ba8'); // 8000 bit = 0x1f40
  });

  test('il confine dei 56 byte, dove il riempimento cambia idea', () {
    // 55 byte stanno nel blocco; 56 ne obbligano uno in più. È il punto in
    // cui un `<=` al posto di un `<` passa tutte le altre prove e sbaglia qui.
    expect(h('a' * 55), 'ef1772b6dff9a122358552954ad0df65');
    expect(h('a' * 56), '3b0c8ac703f828b04c6c197006d17218');
    expect(h('a' * 57), '652b906d60af96844ebd21b674f35e93');
  });

  test('il digest sono sedici byte, non una stringa', () {
    expect(Md5.digest(utf8.encode('abc')).length, 16);
    expect(Md5.digest(utf8.encode('abc')).first, 0x90);
    expect(Md5.digest(utf8.encode('abc')).last, 0x72);
  });
}
