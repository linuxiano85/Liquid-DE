import 'dart:io';

import 'package:minervad/services/fucina/diario_compilazione.dart';
import 'package:test/test.dart';

void main() {
  test(
    'il diario è leggibile durante il processo, prima di chiuderlo',
    () async {
      final dir = await Directory.systemTemp.createTemp('fucina-diario-');
      final diario = await DiarioCompilazione.apri(
        dir.path,
        '6.17.2-fucina-prova',
      );
      try {
        diario.evento('inizio', {'prova': true});
        diario.riga('riga visibile a processo ancora vivo');
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        expect(
          File(diario.percorso).readAsStringSync(),
          contains('riga visibile a processo ancora vivo'),
        );
        diario.riga('ultima riga');
        await diario.chiudi();
        expect(
          File(diario.percorso).readAsStringSync(),
          endsWith('ultima riga\n'),
        );
        expect(diario.errore, isEmpty);
      } finally {
        await diario.chiudi();
        await dir.delete(recursive: true);
      }
    },
  );

  test('ENOSPC resta un errore del log senza eccezioni non gestite', () async {
    final diario = DiarioCompilazione(File('/dev/full'));
    diario.riga('questo disco rifiuta tutte le scritture');
    await diario.flush();
    expect(diario.errore, isNotEmpty);
    diario.riga('anche continuare non deve far cadere il demone');
    await diario.chiudi();
  }, skip: !File('/dev/full').existsSync());
}
