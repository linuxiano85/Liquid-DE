import 'dart:io';

import 'package:minervad/services/app_scanner.dart';
import 'package:minervad/services/mime_database.dart';
import 'package:minervad/services/mime_service.dart';
import 'package:test/test.dart';

/// Prove su come si riscrive `~/.config/mimeapps.list`.
///
/// ── Perché ci vogliono delle prove per scrivere un file INI ────────────────
///
/// Perché quel file non è nostro: lo leggono e lo scrivono tutti gli ambienti
/// grafici installati sulla macchina, e la versione di prima ci passava sopra
/// con la ruspa. Faceva quattro danni, e tre erano invisibili:
///
///  1. cancellava la riga del tipo da OGNI sezione, compresa
///     `[Removed Associations]` — cioè, per assegnare un programma, cancellava
///     la riga che dice il contrario;
///  2. in `[Added Associations]` sostituiva invece di aggiungere, buttando via
///     le scelte di chi era passato prima. È il motivo per cui nel file di
///     Giacomo `application/x-shellscript` compariva DUE volte;
///  3. buttava via commenti e tutto ciò che stava prima della prima
///     intestazione, a ogni scrittura;
///  4. scriveva senza `tmp`+`rename`, quindi un'interruzione a metà lasciava
///     un file troncato — cioè un computer che domani non apre più niente con
///     niente.
///
/// Qui si scrive in una `HOME` finta: provare contro quella vera vorrebbe dire
/// riscrivere il `mimeapps.list` di chi esegue le prove.
void main() {
  late Directory temp;
  late MimeService mime;

  String percorso() => '${temp.path}/config/mimeapps.list';

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('minerva-mimeapps-');
    await Directory('${temp.path}/config').create();
    await Directory('${temp.path}/mime').create();
    // Una base minima: serve solo a far riconoscere l'alias.
    await File('${temp.path}/mime/aliases')
        .writeAsString('application/x-shellscript text/x-shellscript\n');

    mime = MimeService(
      // I programmi «installati» sono questi e basta: `defaultFor` scarta le
      // righe che nominano un `.desktop` che non c'è, e senza questo l'esito
      // dipenderebbe da cosa è installato sulla macchina delle prove.
      AppScanner.finto([
        DesktopApp(
          id: 'editor.desktop',
          name: 'Editor',
          exec: 'editor %F',
          icon: '',
          categories: ['TextEditor'],
          mimeTypes: ['text/plain'],
        ),
        DesktopApp(
          id: 'gwenview.desktop',
          name: 'Gwenview',
          exec: 'gwenview %F',
          icon: '',
          categories: ['Graphics'],
          mimeTypes: ['image/png'],
        ),
        DesktopApp(
          id: 'vim.desktop',
          name: 'Vim',
          exec: 'vim %F',
          icon: '',
          categories: ['TextEditor'],
          mimeTypes: ['text/plain'],
          needsTerminal: true,
        ),
      ]),
      database: MimeDatabase(cartelle: [temp.path]),
      cartellaConfig: '${temp.path}/config',
    );
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<void> scrivi(String contenuto) async =>
      File(percorso()).writeAsString(contenuto);

  Future<String> leggi() async => File(percorso()).readAsString();

  test('un file che non c\'era si crea con le sue sezioni', () async {
    final r = await mime.setDefaults(['image/png'], 'editor.desktop');
    expect(r['ok'], isTrue);
    final testo = await leggi();
    expect(testo, contains('[Default Applications]'));
    expect(testo, contains('image/png=editor.desktop'));
  });

  test('le righe degli altri tipi restano dove sono', () async {
    await scrivi('''
[Default Applications]
image/png=gwenview.desktop
video/mp4=mpv.desktop
''');
    await mime.setDefaults(['text/plain'], 'editor.desktop');
    final testo = await leggi();
    expect(testo, contains('image/png=gwenview.desktop'));
    expect(testo, contains('video/mp4=mpv.desktop'));
    expect(testo, contains('text/plain=editor.desktop'));
  });

  test('i commenti e l\'intestazione non si perdono', () async {
    await scrivi('''
# scritto a mano, non toccare
[Default Applications]
# le immagini
image/png=gwenview.desktop
''');
    await mime.setDefaults(['text/plain'], 'editor.desktop');
    final testo = await leggi();
    expect(testo, contains('# scritto a mano, non toccare'));
    expect(testo, contains('# le immagini'));
  });

  test('una sezione che non conosciamo resta intatta', () async {
    await scrivi('''
[Default Applications]
image/png=gwenview.desktop

[Removed Associations]
text/plain=vim.desktop
''');
    await mime.setDefaults(['text/plain'], 'editor.desktop');
    final testo = await leggi();
    // LA PROVA DEL DIFETTO: la versione di prima cancellava questa riga,
    // cioè cambiava di nascosto una scelta che non le era stata chiesta.
    expect(testo, contains('[Removed Associations]'));
    expect(testo, contains('text/plain=vim.desktop'));
  });

  test('in Added Associations si aggiunge, non si sostituisce', () async {
    await scrivi('''
[Default Applications]
text/plain=vecchio.desktop

[Added Associations]
text/plain=gwenview.desktop;kate.desktop
''');
    await mime.setDefaults(['text/plain'], 'editor.desktop');
    final testo = await leggi();
    expect(testo, contains('text/plain=editor.desktop;gwenview.desktop;kate.desktop'));
  });

  test('la stessa scelta due volte non lascia due righe', () async {
    await mime.setDefaults(['text/plain'], 'editor.desktop');
    await mime.setDefaults(['text/plain'], 'editor.desktop');
    final testo = await leggi();
    expect('text/plain=editor.desktop'.allMatches(testo).length,
        2, // una in `[Default Applications]`, una in `[Added Associations]`
        reason: 'nel file di Giacomo la stessa riga compariva raddoppiata');
  });

  test('togliere la scelta la toglie solo da dove è nostra', () async {
    await scrivi('''
[Default Applications]
text/plain=editor.desktop
image/png=gwenview.desktop

[Removed Associations]
text/plain=vim.desktop
''');
    final r = await mime.forgetDefault('text/plain');
    expect(r['ok'], isTrue);
    final testo = await leggi();
    expect(testo, isNot(contains('text/plain=editor.desktop')));
    // Non si mette nessuno in lista nera, e quella di prima non si tocca.
    expect(testo, contains('text/plain=vim.desktop'));
    expect(testo, contains('image/png=gwenview.desktop'));
  });

  test('togliere una scelta che non c\'era non è un errore', () async {
    await scrivi('[Default Applications]\nimage/png=gwenview.desktop\n');
    final r = await mime.forgetDefault('audio/mpeg');
    expect(r['ok'], isTrue);
    expect(await leggi(), contains('image/png=gwenview.desktop'));
  });

  test('dopo la scrittura non resta nessun file di appoggio', () async {
    await mime.setDefaults(['text/plain'], 'editor.desktop');
    expect(await File('${percorso()}.nuovo').exists(), isFalse);
  });

  test('una scelta scritta con un vecchio alias vale lo stesso', () async {
    // È IL DIFETTO DI GIACOMO. Il suo file dice
    // `application/x-shellscript`; il tipo vero di uno script è
    // `text/x-shellscript`, e prima le due stringhe non si incontravano mai.
    await scrivi('''
[Default Applications]
application/x-shellscript=editor.desktop
''');
    expect(await mime.defaultFor('text/x-shellscript'), 'editor.desktop');
  });

  test('senza una scelta sua si eredita quella del testo semplice', () async {
    await scrivi('[Default Applications]\ntext/plain=editor.desktop\n');
    expect(await mime.defaultFor('text/x-shellscript'), 'editor.desktop');
    // Ma i GRUPPI non ereditano: un gruppo dove non si è scelto niente deve
    // continuare a dire «da scegliere».
    expect(await mime.defaultFor('text/x-shellscript', eredita: false), '');
  });
}
