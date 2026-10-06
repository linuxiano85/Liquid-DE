// Prove per `OsservatoreCartelle`: le cartelle aperte nel gestore file si
// aggiornano da sole quando cambiano da fuori.
//
//     dart run tests/osservatore_cartelle_test.dart
import 'dart:async';
import 'dart:io';
import '../minervad/lib/services/osservatore_cartelle.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  var tests = 0;
  final base = await Directory.systemTemp.createTemp('liquid-osservatore-');
  final cartella = await Directory('${base.path}/a').create();
  final altra = await Directory('${base.path}/b').create();
  final arrivati = <String>[];
  final finestra = Object();
  final altroClient = Object();
  final oss = OsservatoreCartelle((client, m) {
    final p = m['payload'] as Map;
    arrivati.add('${identical(client, finestra) ? "F" : "A"}:${p['pane']}:${p['path']}');
  });

  Future<void> aspetta([int ms = 600]) => Future.delayed(Duration(milliseconds: ms));

  // Un file creato da fuori arriva come UN avviso al riquadro che guarda.
  oss.guarda(finestra, 'p1', cartella.path);
  await File('${cartella.path}/nuovo.txt').writeAsString('x');
  await aspetta();
  check(arrivati.length == 1 && arrivati.first == 'F:p1:${cartella.path}',
      'un file nuovo deve dare un avviso: $arrivati');
  tests++;

  // Una raffica (una copia di cento file) non diventa cento avvisi.
  arrivati.clear();
  for (var i = 0; i < 100; i++) {
    File('${cartella.path}/f$i').writeAsStringSync('$i');
  }
  await aspetta();
  check(arrivati.isNotEmpty && arrivati.length <= 2,
      'una raffica deve dare uno o due avvisi, non ${arrivati.length}');
  tests++;

  // Due riquadri sulla stessa cartella: un solo osservatore, due avvisi.
  arrivati.clear();
  oss.guarda(altroClient, 'q1', cartella.path);
  check(oss.quante == 1, 'la stessa cartella si guarda una volta sola');
  await File('${cartella.path}/nuovo.txt').delete();
  await aspetta();
  check(arrivati.length == 2, 'tutti e due i riquadri vanno avvisati: $arrivati');
  tests++;

  // Il riquadro cambia cartella: la vecchia non lo avvisa più.
  arrivati.clear();
  oss.guarda(finestra, 'p1', altra.path);
  await File('${cartella.path}/f1').delete();
  await aspetta();
  check(arrivati.length == 1 && arrivati.first.startsWith('A:q1:'),
      'cambiata cartella, p1 non deve più sentire la vecchia: $arrivati');
  tests++;

  // Il client se ne va: nessuno guarda più, e l'osservatore si chiude.
  arrivati.clear();
  oss.smetti(altroClient);
  check(oss.quante == 1, 'resta solo la cartella di p1, non ${oss.quante}');
  await File('${cartella.path}/f2').delete();
  await aspetta();
  check(arrivati.isEmpty, 'chi se n\'è andato non va avvisato: $arrivati');
  tests++;

  // La cartella guardata sparisce: un ultimo avviso, poi niente osservatore.
  arrivati.clear();
  await altra.delete(recursive: true);
  await aspetta();
  check(arrivati.isNotEmpty, 'la cartella sparita va detta al riquadro');
  check(oss.quante == 0, 'un osservatore morto va dimenticato, ne restano ${oss.quante}');
  tests++;

  // Una cartella che non esiste non si guarda e non rompe niente.
  oss.guarda(finestra, 'p2', '${base.path}/non-esiste');
  check(oss.quante == 0, 'una cartella inesistente non si guarda');
  tests++;

  oss.chiudi();
  await base.delete(recursive: true);
  print('osservatore_cartelle: $tests prove superate');
}
