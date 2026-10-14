// Prove per `FileService.anteprima`: il riquadro dei dettagli e
// dell'anteprima del gestore file (11 ottobre 2026).
//
//     dart run tests/anteprima_file_test.dart
//
// Una domanda sola per file: i dettagli, e per un testo le prime righe, mai
// più di `anteprimaMassimo` byte.
import 'dart:convert';
import 'dart:io';

import '../minervad/lib/services/file_service.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  var prove = 0;
  final base = await Directory.systemTemp.createTemp('liquid-anteprima-');
  final files = FileService(cestinoDiProva: '${base.path}/cestino');
  try {
    // Un testo breve arriva intero, con dimensione e data.
    final nota = File('${base.path}/nota.txt');
    await nota.writeAsString('Prima riga\nàèìòù — seconda riga\n');
    var r = await files.anteprima(nota.path);
    check(r['ok'] == true && r['isDir'] == false, 'un file si legge: $r');
    check(r['testo'] == 'Prima riga\nàèìòù — seconda riga\n',
        'il testo arriva intero e in UTF-8: ${r['testo']}');
    check(r['troncato'] == false && r['binario'] == false,
        'un testo breve non è troncato né binario: $r');
    check(r['size'] == await nota.length(), 'la dimensione è quella vera');
    check((r['modified'] as int) > 0, 'c\'è la data di modifica');
    prove++;

    // Un testo lungo si ferma al tetto, e lo dice.
    final lungo = File('${base.path}/lungo.log');
    await lungo.writeAsString('riga di registro\n' * 5000);
    r = await files.anteprima(lungo.path);
    check(utf8.encode(r['testo'] as String).length <= FileService.anteprimaMassimo,
        'mai più del tetto: ${(r['testo'] as String).length}');
    check(r['troncato'] == true, 'un testo più lungo del tetto è troncato');
    prove++;

    // Un carattere tagliato a metà dal tetto non rende binario il file.
    final accenti = File('${base.path}/accenti.txt');
    await accenti.writeAsString('è' * 20000);
    r = await files.anteprima(accenti.path);
    check(r['binario'] == false && r['troncato'] == true,
        'un carattere a metà sul tetto resta testo: $r');
    prove++;

    // Un file con byte zero è binario: nessun testo.
    final binario = File('${base.path}/programma.bin');
    await binario.writeAsBytes([0x7f, 0x45, 0x4c, 0x46, 0, 0, 1, 2, 3]);
    r = await files.anteprima(binario.path);
    check(r['binario'] == true && r['testo'] == '', 'un binario non manda testo: $r');
    prove++;

    // Byte che non sono UTF-8, senza zeri: binario anche loro.
    final latino = File('${base.path}/strano.dat');
    await latino.writeAsBytes(List.generate(400, (i) => 0x80 + (i % 64)));
    r = await files.anteprima(latino.path);
    check(r['binario'] == true, 'troppi byte non UTF-8 sono binario: $r');
    prove++;

    // Un'immagine porta le misure, non il testo.
    final png = File('${base.path}/punto.png');
    await png.writeAsBytes(base64.decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAIAAAASFvFNAAAAFElEQVR4nGN06XjHAAZMEIqBgQEAHqYBvpG5uYAAAAAASUVORK5CYII='));
    r = await files.anteprima(png.path);
    check(r['imageWidth'] == 3 && r['imageHeight'] == 2,
        'le misure dell\'immagine dall\'intestazione: $r');
    check(r['testo'] == '', 'un\'immagine non manda testo');
    prove++;

    // Una cartella: niente lettura.
    r = await files.anteprima(base.path);
    check(r['ok'] == true && r['isDir'] == true && r['testo'] == '',
        'una cartella ha solo i dettagli: $r');
    prove++;

    // Un file sparito risponde con un errore, non con un'eccezione.
    r = await files.anteprima('${base.path}/non-esiste.txt');
    check(r['ok'] == false && (r['error'] as String).isNotEmpty,
        'un file sparito è un errore detto bene: $r');
    prove++;
  } finally {
    await base.delete(recursive: true);
  }
  print('anteprima_file: $prove prove superate');
}
