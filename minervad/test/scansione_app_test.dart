// Il demone rilegge i `.desktop` solo quando è cambiato qualcosa.
//
// ── Perché esiste questa prova ─────────────────────────────────────────────
//
// Nel registro di una sessione vera del 2 settembre 2026 la scansione delle
// applicazioni compariva **ottantanove volte**. Non è un difetto della
// scansione: la chiede ogni finestra di Minerva che si collega al demone —
// la shell, il gestore file, le Impostazioni, ogni app — perché la shell si
// riavvia molte volte mentre il demone parte una volta sola, e un programma
// installato nel frattempo non comparirebbe mai.
//
// Il costo non era il tempo (111 ms a freddo, 40 a caldo su 166 file) ma la
// memoria: ogni giro costruiva settantun oggetti e li buttava, e il mucchio di
// Dart cresce fino al massimo che ha visto e non lo restituisce. Il demone era
// passato da 44 a 74 MB.
//
// Le due garanzie che questa prova tiene ferme sono in tensione fra loro, ed è
// il motivo per cui vanno provate insieme:
//   1. chiedere la scansione dieci volte di fila non ne fa dieci;
//   2. ma un programma installato un istante fa si vede lo stesso.
//
// Se un giorno qualcuno «ottimizza» tenendo l'elenco in memoria a vita, la
// seconda diventa rossa — che è esattamente quello che deve succedere.
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('la scansione non si ripete se non è cambiato niente, ma vede il nuovo',
      () async {
    final tmp = Directory.systemTemp.createTempSync('minerva-scan-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final apps = Directory('${tmp.path}/applications')..createSync();
    final vuota = Directory('${tmp.path}/vuota')..createSync();

    for (var i = 0; i < 3; i++) {
      File('${apps.path}/prog$i.desktop').writeAsStringSync(
          '[Desktop Entry]\nType=Application\nName=Prog $i\nExec=/bin/true\n');
    }

    final r = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'test/aiuti/conta_scansioni.dart', tmp.path],
      environment: {
        'HOME': tmp.path,
        'XDG_DATA_HOME': tmp.path,
        'XDG_DATA_DIRS': vuota.path,
      },
      workingDirectory: Directory.current.path,
    );
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    final out = '${r.stdout}';

    // Quante volte ha DAVVERO riletto i file dal disco.
    final vere = RegExp(r'\[MINERVA\]\[MATRIX\]\[OK\]').allMatches(out).length;

    // Otto chiamate a `scan()`: la prima, cinque di seguito, una dopo
    // l'installazione, una di riposo — più le due insieme forzate, che valgono
    // per una sola. Le scansioni vere devono essere tre: la prima, quella dopo
    // l'installazione, e quella forzata.
    expect(vere, 3, reason: 'scansioni vere sbagliate:\n$out');

    expect(out, contains('[PASSO] prima=3'));
    expect(out, contains('[PASSO] dopo-cinque=3'));
    // La garanzia che conta di più: il programma installato un istante fa c'è.
    expect(out, contains('[PASSO] dopo-installazione=4'));
    expect(out, contains('[PASSO] dopo-riposo=4'));
    expect(out, contains('[PASSO] insieme=4'));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
