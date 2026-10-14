import 'dart:convert';
import 'dart:io';

import 'package:minervad/services/fucina/regole_moduli.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporanea;
  late RegoleModuli regole;

  setUp(() {
    temporanea = Directory.systemTemp.createTempSync('fucina-regole-moduli-');
    regole = RegoleModuli(statoDir: temporanea.path);
  });

  tearDown(() => temporanea.deleteSync(recursive: true));

  test('mantieni ed escludi persistono con nomi kernel canonici', () async {
    await regole.imposta('snd-hda-intel', 'escludi');
    await regole.imposta('xpad', 'mantieni');

    expect(await regole.elenco(), {
      'mantieni': ['xpad'],
      'escludi': ['snd_hda_intel'],
    });
    expect(File('${temporanea.path}/regole-moduli.json').existsSync(), isTrue);
  });

  test(
    'una decisione sostituisce la precedente e automatico la cancella',
    () async {
      await regole.imposta('xpad', 'escludi');
      await regole.imposta('xpad', 'mantieni');
      expect((await regole.elenco())['escludi'], isEmpty);
      expect((await regole.elenco())['mantieni'], ['xpad']);

      await regole.imposta('xpad', 'automatico');
      expect(await regole.elenco(), {'mantieni': [], 'escludi': []});
    },
  );

  test('scritture concorrenti non si sovrascrivono', () async {
    await Future.wait([
      regole.imposta('xpad', 'mantieni'),
      regole.imposta('btusb', 'escludi'),
      regole.imposta('amdgpu', 'mantieni'),
    ]);

    final elenco = await regole.elenco();
    expect(elenco['mantieni'], ['amdgpu', 'xpad']);
    expect(elenco['escludi'], ['btusb']);
  });

  test('rifiuta nomi e stati non validi', () async {
    expect((await regole.imposta('../x', 'escludi'))['ok'], isFalse);
    expect((await regole.imposta('xpad', 'cancella'))['ok'], isFalse);
    expect(await regole.elenco(), {'mantieni': [], 'escludi': []});
  });

  test('indice danneggiato riparte vuoto e viene riscritto', () async {
    final file = File('${temporanea.path}/regole-moduli.json');
    file.writeAsStringSync('{rotto');
    expect(await regole.elenco(), {'mantieni': [], 'escludi': []});

    await regole.imposta('xpad', 'mantieni');
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(json['mantieni'], ['xpad']);
  });
}
