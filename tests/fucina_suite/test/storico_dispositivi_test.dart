import 'dart:convert';
import 'dart:io';

import 'package:minervad/services/fucina/storico_dispositivi.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporanea;
  late StoricoDispositivi storico;

  setUp(() {
    temporanea = Directory.systemTemp.createTempSync('fucina-storico-');
    storico = StoricoDispositivi(statoDir: temporanea.path);
  });

  tearDown(() => temporanea.deleteSync(recursive: true));

  test(
    'ricorda i modalias senza perdere primo avvistamento o conteggio',
    () async {
      const alias = 'usb:v1234p5678d0001dc00dsc00dp00ic03isc00ip00in00';
      await storico.aggiorna([alias, 'non-valido']);
      final primo =
          jsonDecode(
                await File(
                  '${temporanea.path}/dispositivi-visti.json',
                ).readAsString(),
              )
              as Map<String, dynamic>;
      final primoRecord =
          (primo['dispositivi'] as List).single as Map<String, dynamic>;

      await storico.aggiorna([alias]);
      final secondo =
          jsonDecode(
                await File(
                  '${temporanea.path}/dispositivi-visti.json',
                ).readAsString(),
              )
              as Map<String, dynamic>;
      final secondoRecord =
          (secondo['dispositivi'] as List).single as Map<String, dynamic>;

      expect(await storico.leggi(), [alias]);
      expect(primoRecord['primoVisto'], secondoRecord['primoVisto']);
      expect(secondoRecord['rilevamenti'], 2);
    },
  );

  test(
    'scritture concorrenti si accodano senza cancellare periferiche',
    () async {
      const uno = 'usb:v1111p0001d0001dc00dsc00dp00ic03isc00ip00in00';
      const due = 'pci:v00001234d00005678sv0000sd0000bc03sc00i00';
      await Future.wait([
        storico.aggiorna([uno]),
        storico.aggiorna([due]),
      ]);
      expect(await storico.leggi(), containsAll([uno, due]));
    },
  );

  test('dimentica cancella il registro prima dei prossimi rilievi', () async {
    const alias = 'usb:v1234p5678d0001dc00dsc00dp00ic03isc00ip00in00';
    await storico.aggiorna([alias]);
    await storico.dimentica();
    expect(await storico.leggi(), isEmpty);
    expect(
      File('${temporanea.path}/dispositivi-visti.json').existsSync(),
      isFalse,
    );
  });
}
