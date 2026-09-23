// Aiutante della prova `scansione_app_test.dart`.
//
// Vive in un processo a sé perché le cartelle che lo scanner guarda le decide
// `Platform.environment`, e l'ambiente di un processo Dart non si cambia da
// dentro: l'unico modo di puntarlo a una cartella finta è avviarlo con
// l'ambiente giusto.
//
// Stampa una riga per ogni passaggio; la prova conta quante volte lo scanner
// ha davvero riaperto i file, guardando le righe `[MINERVA][MATRIX][OK]`.
import 'dart:io';

import 'package:minervad/services/app_scanner.dart';

Future<void> main(List<String> args) async {
  final cartella = args[0];
  final s = AppScanner();

  await s.scan();
  print('[PASSO] prima=${s.apps.length}');

  // Cinque richieste di fila, come le fanno cinque finestre che si aprono.
  for (var i = 0; i < 5; i++) {
    await s.scan();
  }
  print('[PASSO] dopo-cinque=${s.apps.length}');

  // Un programma installato adesso: deve comparire senza che nessuno forzi
  // niente.
  File('$cartella/applications/nuovo.desktop').writeAsStringSync(
      '[Desktop Entry]\nType=Application\nName=Nuovo\nExec=/bin/true\n');
  await s.scan();
  print('[PASSO] dopo-installazione=${s.apps.length}');

  // E una richiesta in più dopo l'installazione non ne fa un'altra.
  await s.scan();
  print('[PASSO] dopo-riposo=${s.apps.length}');

  // Due chiamate insieme, senza aspettare la prima: devono essere una sola
  // scansione, non due in parallelo sulle stesse cartelle.
  await Future.wait([s.scan(forza: true), s.scan(forza: true)]);
  print('[PASSO] insieme=${s.apps.length}');
}
