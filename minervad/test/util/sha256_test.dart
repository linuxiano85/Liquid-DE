import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:minervad/util/sha256.dart';
import 'package:test/test.dart';

/// Una funzione di hash sbagliata non dà errore: dà un numero diverso. Quindi
/// non le si crede sulla parola — la si confronta con i valori dello standard
/// e col `sha256sum` di questa macchina.
void main() {
  group('SHA-256 · i valori pubblicati nello standard', () {
    test('la stringa vuota', () {
      expect(Sha256.esa(const []),
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    });

    test('«abc»', () {
      expect(Sha256.esa(utf8.encode('abc')),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });

    test('il messaggio di 56 byte, quello che sta sul confine del riempimento',
        () {
      expect(
          Sha256.esa(utf8.encode(
              'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq')),
          '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1');
    });

    test('un milione di «a»', () {
      expect(Sha256.esa(List<int>.filled(1000000, 0x61)),
          'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0');
    });
  });

  test('d\'accordo con sha256sum del sistema, su dati a caso', () async {
    final caso = Random(20260825);
    for (var giro = 0; giro < 12; giro++) {
      final quanti = caso.nextInt(300);
      final dati = List<int>.generate(quanti, (_) => caso.nextInt(256));
      final f = File('${Directory.systemTemp.path}/minerva-sha-$giro.bin');
      await f.writeAsBytes(dati);
      final r = await Process.run('sha256sum', [f.path]);
      await f.delete();
      final suo = '${r.stdout}'.split(' ').first;
      expect(Sha256.esa(dati), suo, reason: 'con $quanti byte');
    }
  });

  test('base64url senza riempimento: la forma che vuole PKCE', () {
    final v = Sha256.base64url(utf8.encode('abc'));
    expect(v, isNot(contains('=')));
    expect(v, isNot(contains('+')));
    expect(v, isNot(contains('/')));
    expect(base64Url.decode('$v='), Sha256.byte(utf8.encode('abc')));
  });
}
