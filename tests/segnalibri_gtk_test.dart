// Prove per `SegnalibriGtk`: le cartelle fissate in Minerva File diventano
// segnalibri GTK, e Minerva toglie solo le righe che ha aggiunto lei.
//
//     dart run tests/segnalibri_gtk_test.dart
import 'dart:io';

import '../minervad/lib/services/segnalibri_gtk.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  var prove = 0;
  final base = await Directory.systemTemp.createTemp('liquid-segnalibri-');
  final file = File('${base.path}/gtk-3.0/bookmarks');
  final stato = '${base.path}/stato.json';
  SegnalibriGtk nuovo() => SegnalibriGtk(segnalibri: file.path, stato: stato);
  List<String> righe() => file.existsSync() ? file.readAsLinesSync() : [];

  // I segnalibri che c'erano già, uno con un'etichetta.
  await file.parent.create(recursive: true);
  await file.writeAsString(
    'file:///home/tizio/Musica\nfile:///home/tizio/Lavoro Ufficio\n',
  );

  // Una cartella fissata compare in fondo, una volta sola.
  var s = nuovo();
  check(
    await s.allinea(['/home/tizio/Progetti/Liquid DE']),
    'la prima volta il file cambia',
  );
  check(
    righe().length == 3 &&
        righe().last == 'file:///home/tizio/Progetti/Liquid%20DE',
    'la cartella fissata si aggiunge in fondo, con gli spazi codificati: ${righe()}',
  );
  prove++;

  // Lo stesso elenco di nuovo non riscrive niente.
  check(
    !await s.allinea(['/home/tizio/Progetti/Liquid DE']),
    'stesso elenco, nessuna scrittura',
  );
  prove++;

  // Fissare una cartella che era già fra i segnalibri non la duplica, e
  // la riga dell'utente (con l'etichetta) resta com'era.
  s = nuovo();
  await s.allinea(['/home/tizio/Progetti/Liquid DE', '/home/tizio/Lavoro']);
  check(
    righe().where((r) => r.startsWith('file:///home/tizio/Lavoro')).length == 1,
    'una cartella già presente non si duplica: ${righe()}',
  );
  check(
    righe().contains('file:///home/tizio/Lavoro Ufficio'),
    'l\'etichetta dell\'utente resta',
  );
  prove++;

  // Tolte dalla colonna: se ne va solo quella aggiunta da Minerva.
  s = nuovo();
  await s.allinea([]);
  check(
    !righe().any((r) => r.contains('Liquid%20DE')),
    'la riga nostra se ne va: ${righe()}',
  );
  check(
    righe().contains('file:///home/tizio/Lavoro Ufficio'),
    'la riga dell\'utente resta anche se era fissata: ${righe()}',
  );
  check(
    righe().contains('file:///home/tizio/Musica'),
    'le altre righe dell\'utente restano',
  );
  prove++;

  // Senza file di partenza si crea, e un percorso non assoluto si ignora.
  await file.delete();
  s = nuovo();
  await s.allinea(['/srv/condivisa', 'relativo/no']);
  check(
    righe().length == 1 && righe().first == 'file:///srv/condivisa',
    'file creato da capo, percorsi relativi scartati: ${righe()}',
  );
  prove++;

  // Un errore di scrittura non deve far credere che l'elenco sia salvato.
  await file.delete();
  final ostacolo = Directory(file.path);
  await ostacolo.create();
  s = nuovo();
  var fallita = false;
  try {
    await s.allinea(['/srv/ritenta']);
  } on FileSystemException {
    fallita = true;
  }
  check(fallita, 'la cartella al posto del file impedisce la scrittura');
  await ostacolo.delete();
  check(
    await s.allinea(['/srv/ritenta']),
    'lo stesso elenco si ritenta dopo un errore',
  );
  check(
    righe().contains('file:///srv/ritenta'),
    'il tentativo riuscito salva il segnalibro',
  );
  prove++;

  // Due eventi delle impostazioni arrivati insieme devono restare in ordine.
  s = nuovo();
  await Future.wait([
    s.allinea(['/srv/prima']),
    s.allinea(['/srv/seconda']),
  ]);
  check(
    righe().contains('file:///srv/seconda'),
    'resta l\'ultimo elenco richiesto',
  );
  check(
    !righe().contains('file:///srv/prima'),
    'nessuna riga residua dal primo evento',
  );
  prove++;

  await base.delete(recursive: true);
  print('segnalibri_gtk: $prove prove superate');
}
