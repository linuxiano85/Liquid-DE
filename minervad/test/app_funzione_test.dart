// La ricerca delle app per FUNZIONE, non solo per nome.
//
// Giacomo, 23 settembre 2026: «una ricerca intelligente delle app nella quale
// io possa sia cercare il nome che la sua funzione, come ad esempio browser o
// chrome o navigare il web». Per cercare per funzione servono le parole che i
// programmi dichiarano da soli nel loro `.desktop` — `GenericName`,
// `Comment`, `Keywords` — e il lettore del demone, fino al 24 settembre,
// leggeva solo nome e categorie.
import 'dart:io';

import 'package:minervad/services/app_scanner.dart';
import 'package:test/test.dart';

const _firefox = '''[Desktop Entry]
Name=Firefox
GenericName=Web Browser
GenericName[it]=Browser web
GenericName[de]=Webbrowser
Comment=Browse the World Wide Web
Comment[it]=Naviga nel web
Keywords=Internet;WWW;Browser;Web;
Keywords[it]=Internet;WWW;Browser;Web;Navigatore;
Keywords[de]=Internet;Netz;
Exec=firefox %u
Icon=firefox
Categories=Network;WebBrowser;

[Desktop Action new-window]
Name=Nuova finestra
Comment=Questa non è la descrizione del programma
Exec=firefox --new-window
''';

void main() {
  late Directory cartella;
  late DesktopApp app;

  setUpAll(() async {
    cartella = await Directory.systemTemp.createTemp('liquid-app-');
    final f = File('${cartella.path}/firefox.desktop');
    await f.writeAsString(_firefox);
    app = (await AppScanner().parseFromPath(f.path))!;
  });
  tearDownAll(() => cartella.delete(recursive: true));

  final lingua = (Platform.environment['LC_ALL'] ??
          Platform.environment['LC_MESSAGES'] ??
          Platform.environment['LANG'] ??
          '')
      .toLowerCase();
  final italiano = lingua.startsWith('it');

  test('le parole chiave: quelle di serie e quelle della lingua dell\'utente', () {
    expect(app.parole, containsAll(['Browser', 'Web']));
    if (italiano) expect(app.parole, contains('Navigatore'));
    expect(app.parole.where((p) => p == 'Browser'), hasLength(1));
    // Le altre lingue no: «Netz» non aiuta a trovare niente qui.
    expect(app.parole, isNot(contains('Netz')));
  });

  test('il nome generico e la descrizione nella lingua di chi usa il computer', () {
    expect(app.generico, italiano ? 'Browser web' : 'Web Browser',
        reason: 'lingua: «$lingua»');
    expect(app.descrizione, italiano ? 'Naviga nel web' : 'Browse the World Wide Web');
  });

  test('le azioni del .desktop non si mescolano col programma', () {
    // Anche le azioni hanno un `Comment`: è di loro, non del programma.
    expect(app.descrizione, isNot(contains('Questa non è')));
  });

  test('e arrivano alla shell', () {
    final j = app.toJson();
    expect(j['generico'], app.generico);
    expect(j['parole'], app.parole);
    expect(j['descrizione'], app.descrizione);
  });
}
