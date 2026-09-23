import 'dart:io';

import 'package:test/test.dart';
import 'package:minervad/services/manutenzione/escluse.dart';

// Le cartelle che la Manutenzione non deve guardare.
//
// Sbagliare per difetto qui vuol dire mostrare migliaia di doppioni che non si
// devono toccare — cioè rendere inutile la pagina. Sbagliare per eccesso vuol
// dire nascondere i doppioni veri. Nessuna delle due dà errore: si vede solo
// usando, e per questo va provato.
void main() {
  late Directory casa;
  late Escluse escluse;

  setUp(() async {
    casa = await Directory.systemTemp.createTemp('minerva-escl-');
    escluse = Escluse(percorso: '${casa.path}/escluse.json');
  });
  tearDown(() async => casa.delete(recursive: true));

  test('si aggiungono, si tolgono, e restano scritte', () async {
    expect(await escluse.leggi(), isEmpty);
    await escluse.aggiungi('/casa/Android');
    await escluse.aggiungi('/casa/flutter');
    expect(await escluse.leggi(), ['/casa/Android', '/casa/flutter']);

    // Un'altra istanza legge lo stesso file: è una preferenza, e deve valere
    // anche domani.
    final altra = Escluse(percorso: '${casa.path}/escluse.json');
    expect(await altra.leggi(), hasLength(2));

    await escluse.togli('/casa/Android');
    expect(await escluse.leggi(), ['/casa/flutter']);
  });

  test('la stessa due volte resta una', () async {
    await escluse.aggiungi('/casa/Android');
    await escluse.aggiungi('/casa/Android/');
    expect(await escluse.leggi(), ['/casa/Android']);
  });

  test('una cartella dentro una già esclusa non si aggiunge', () async {
    // Escludere `Android/Sdk` quando c'è già `Android` non cambia niente, e
    // lascerebbe due righe che dicono la stessa cosa.
    await escluse.aggiungi('/casa/Android');
    await escluse.aggiungi('/casa/Android/Sdk');
    expect(await escluse.leggi(), ['/casa/Android']);
  });

  test('e escludendo il genitore, le figlie si tolgono', () async {
    // Una riga sola vale per tutte: lasciarne tre che dicono la stessa cosa è
    // un elenco che si smette di leggere.
    await escluse.aggiungi('/casa/Android/Sdk');
    await escluse.aggiungi('/casa/Android/Studio');
    await escluse.aggiungi('/casa/Android');
    expect(await escluse.leggi(), ['/casa/Android']);
  });

  test('quello che non è un percorso non si scrive', () async {
    for (final storto in ['', 'Android', '../etc', '/', '/casa/../etc']) {
      await escluse.aggiungi(storto);
    }
    expect(await escluse.leggi(), isEmpty);
  });

  test('un file illeggibile non impedisce di guardare', () async {
    await File('${casa.path}/escluse.json').writeAsString('{rotto');
    expect(await escluse.leggi(), isEmpty);
    await escluse.aggiungi('/casa/x');
    expect(await escluse.leggi(), ['/casa/x']);
  });
}
