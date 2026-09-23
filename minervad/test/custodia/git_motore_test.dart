import 'dart:io';

import 'package:minervad/services/custodia/git_motore.dart';
import 'package:test/test.dart';

/// Prove sul motore dei salvataggi.
///
/// Due metà, e servono a cose diverse.
///
/// La prima è la **lettura di `--porcelain=v2 -z`**, e si prova con testi
/// finti: è una funzione pura, e i casi che contano sono quelli che su questa
/// macchina non capitano mai — un nome di file con dentro una virgoletta, una
/// tabulazione, un a-capo. Sono nomi legali. Esistono. E sono esattamente il
/// punto in cui un parser scritto a occhio sbaglia in silenzio: `minerva-radice`
/// ci era già passato una volta.
///
/// La seconda è **git per davvero**, dentro una cartella temporanea. Perché una
/// prova che finge git prova come credo che funzioni git, non come funziona.
void main() {
  const nul = '\u0000';

  // ── La lettura dello stato ─────────────────────────────────────────────

  group('leggere cosa è cambiato', () {
    test('un file modificato e uno nuovo', () {
      final s = GitMotore.leggiStato(
        '1 .M N... 100644 100644 100644 aaa bbb lib/uno.dart$nul'
        '? nuovo.txt$nul',
      );
      expect(s.modifiche.length, 2);
      expect(s.modifiche[0].percorso, 'lib/uno.dart');
      expect(s.modifiche[0].verso, Verso.modificato);
      expect(s.modifiche[1].percorso, 'nuovo.txt');
      expect(s.modifiche[1].verso, Verso.aggiunto);
    });

    test('un nome con lo spazio non si spezza', () {
      final s = GitMotore.leggiStato(
        '1 .M N... 100644 100644 100644 aaa bbb Minerva Shell/app.qml$nul',
      );
      expect(s.modifiche.single.percorso, 'Minerva Shell/app.qml');
    });

    test('un nome con virgolette e tabulazioni arriva intero', () {
      // Con `-z` git NON mette le virgolette e NON scappa niente: i byte del
      // nome arrivano crudi. Verificato a mano su git vero.
      final s = GitMotore.leggiStato(
        '? nome"strano.txt$nul'
        '? con\ttab.txt$nul'
        '? con\na-capo.txt$nul',
      );
      // In ordine di byte: la tabulazione (0x09) viene prima dell'a-capo
      // (0x0A). Sono nomi legali, e ordinarli è un dettaglio; **non perderli**
      // non lo è.
      expect(s.modifiche.map((m) => m.percorso), [
        'con\ttab.txt',
        'con\na-capo.txt',
        'nome"strano.txt',
      ]);
    });

    test('un rinomino porta il nome vecchio nel campo DOPO', () {
      // È la trappola: chi legge un record per volta si ritrova «a.txt» come
      // se fosse un file a sé, e conta una modifica in più che non esiste.
      final s = GitMotore.leggiStato(
        '2 R. N... 100644 100644 100644 aaa bbb R100 b con spazio.txt$nul'
        'a.txt$nul',
      );
      expect(s.modifiche.length, 1, reason: 'ha contato il nome vecchio');
      expect(s.modifiche.single.percorso, 'b con spazio.txt');
      expect(s.modifiche.single.percorsoPrima, 'a.txt');
      expect(s.modifiche.single.verso, Verso.rinominato);
    });

    test('e un rinomino seguito da altro non si mangia il record dopo', () {
      final s = GitMotore.leggiStato(
        '2 R. N... 100644 100644 100644 aaa bbb R100 nuovo.txt${nul}vecchio.txt$nul'
        '? terzo.txt$nul',
      );
      expect(s.modifiche.map((m) => m.percorso), ['nuovo.txt', 'terzo.txt']);
    });

    test('cancellato, aggiunto, in conflitto', () {
      final s = GitMotore.leggiStato(
        '1 D. N... 100644 000000 000000 aaa bbb via.txt$nul'
        '1 A. N... 000000 100644 100644 aaa bbb qui.txt$nul'
        'u UU N... 100644 100644 100644 100644 a b c litigio.txt$nul',
      );
      final per = {for (final m in s.modifiche) m.percorso: m.verso};
      expect(per['via.txt'], Verso.tolto);
      expect(per['qui.txt'], Verso.aggiunto);
      expect(per['litigio.txt'], Verso.inConflitto);
    });

    test('le righe di intestazione dicono il ramo e quanto manca fuori', () {
      final s = GitMotore.leggiStato(
        '# branch.oid aaaa$nul'
        '# branch.head principale$nul'
        '# branch.upstream origin/principale$nul'
        '# branch.ab +3 -1$nul'
        '? uno.txt$nul',
      );
      expect(s.ramo, 'principale');
      expect(s.haDestinazione, isTrue);
      expect(s.daMandare, 3);
      expect(s.daPrendere, 1);
      expect(s.modifiche.length, 1);
    });

    test('senza destinazione, non si finge che ce ne sia una', () {
      final s = GitMotore.leggiStato(
        '# branch.head principale$nul'
        '# branch.ab +0 -0$nul',
      );
      expect(s.haDestinazione, isFalse);
      expect(s.pulito, isTrue);
    });

    test('i file ignorati non sono modifiche', () {
      final s = GitMotore.leggiStato('! build/roba.o$nul? vero.txt$nul');
      expect(s.modifiche.single.percorso, 'vero.txt');
    });

    test('un\'uscita vuota è una cartella pulita, non un errore', () {
      expect(GitMotore.leggiStato('').pulito, isTrue);
      expect(GitMotore.leggiStato(nul).pulito, isTrue);
    });
  });

  // ── Il raggruppamento ──────────────────────────────────────────────────

  group('raggruppare per significato', () {
    test('le cartelle di Minerva prendono il loro nome vero', () {
      final g = GitMotore.raggruppa([
        const Modifica(percorso: 'minerva-shell/app.qml', verso: Verso.modificato),
        const Modifica(percorso: 'minerva-shell/core/Ipc.qml', verso: Verso.modificato),
        const Modifica(percorso: 'minervad/lib/x.dart', verso: Verso.modificato),
        const Modifica(percorso: 'compositore/src/main.c', verso: Verso.modificato),
      ]);
      expect(g.first.nome, 'la scrivania');
      expect(g.first.modifiche.length, 2);
      expect(g.map((x) => x.nome), containsAll(['il demone', 'il compositore']));
    });

    test('prima chi è cambiato di più: è come si racconta la giornata', () {
      final g = GitMotore.raggruppa([
        const Modifica(percorso: 'minervad/a', verso: Verso.modificato),
        const Modifica(percorso: 'minerva-shell/a', verso: Verso.modificato),
        const Modifica(percorso: 'minerva-shell/b', verso: Verso.modificato),
        const Modifica(percorso: 'minerva-shell/c', verso: Verso.modificato),
      ]);
      expect(g.first.nome, 'la scrivania');
      expect(g.last.nome, 'il demone');
    });

    test('quello che non conosce prende il nome della sua cartella', () {
      final g = GitMotore.raggruppa([
        const Modifica(percorso: 'roba-mia/x.txt', verso: Verso.modificato),
      ]);
      expect(g.single.nome, 'roba-mia');
    });

    test('un documento in cima è «i documenti», il resto è la cartella', () {
      final g = GitMotore.raggruppa([
        const Modifica(percorso: 'README.md', verso: Verso.modificato),
        const Modifica(percorso: 'MODULI.md', verso: Verso.modificato),
        const Modifica(percorso: 'meson.build', verso: Verso.modificato),
      ]);
      final per = {for (final x in g) x.nome: x.modifiche.length};
      expect(per['i documenti'], 2);
      expect(per['la cartella principale'], 1);
    });
  });

  // ── git per davvero ────────────────────────────────────────────────────

  group('git vero, dentro una cartella temporanea', () {
    late Directory temp;
    late String p;
    late GitMotore g;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('minerva-git-');
      p = temp.path;
      g = GitMotore();
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    Future<void> firma() async {
      await Process.run('git', ['-C', p, 'config', 'user.name', 'Prova']);
      await Process.run('git', ['-C', p, 'config', 'user.email', 'p@prova']);
    }

    test('una cartella qualsiasi non tiene una storia', () async {
      expect(await g.eRepo(p), isFalse);
      expect((await g.stato(p)).tieneStoria, isFalse);
    });

    test('«comincia a tenere la storia» la comincia, e scrive cosa ignorare',
        () async {
      await Directory('$p/node_modules').create();
      await Directory('$p/__pycache__').create();
      final e = await g.inizia(p);
      expect(e.riuscito, isTrue, reason: e.errore);
      expect(await g.eRepo(p), isTrue);

      final ign = await File('$p/.gitignore').readAsString();
      expect(ign, contains('node_modules/'));
      expect(ign, contains('__pycache__/'));
      // In italiano, come tutto il resto che una persona può leggere.
      expect(ign, contains('Custodia'));
    });

    test('il ramo si chiama «principale», non «master»', () async {
      await g.inizia(p);
      await firma();
      await File('$p/x.txt').writeAsString('x');
      await g.salva(p, 'il primo');
      expect((await g.stato(p)).ramo, 'principale');
    });

    test('non si comincia due volte', () async {
      await g.inizia(p);
      final e = await g.inizia(p);
      expect(e.riuscito, isFalse);
      expect(e.errore, contains('già'));
    });

    test('salvare prende tutto: anche i file mai visti prima', () async {
      await g.inizia(p);
      await firma();
      await Directory('$p/dentro').create();
      await File('$p/uno.txt').writeAsString('uno');
      await File('$p/dentro/due.txt').writeAsString('due');

      final e = await g.salva(p, 'la prima volta');
      expect(e.riuscito, isTrue, reason: e.errore);
      expect((await g.stato(p)).pulito, isTrue);

      final storia = await g.storia(p);
      expect(storia.single.cosa, 'la prima volta');
    });

    test('anche un file col nome cattivo si salva', () async {
      await g.inizia(p);
      await firma();
      await File('$p/nome"strano con spazio.txt').writeAsString('x');
      final s1 = await g.stato(p);
      expect(s1.modifiche.map((m) => m.percorso),
          contains('nome"strano con spazio.txt'));

      final e = await g.salva(p, 'nomi difficili');
      expect(e.riuscito, isTrue, reason: e.errore);
      expect((await g.stato(p)).pulito, isTrue);
    });

    test('una cartella mai vista non conta per uno', () async {
      // `git status` collassa una cartella intera mai tracciata in `? nome/`.
      // Chi legge «1 il compositore» crede che sia un file; là dentro ce ne
      // sono sedici. Il numero deve essere quello vero.
      await g.inizia(p);
      await firma();
      await File('$p/x.txt').writeAsString('x');
      await g.salva(p, 'primo');

      await Directory('$p/nuova/dentro').create(recursive: true);
      for (var i = 0; i < 5; i++) {
        await File('$p/nuova/file$i.txt').writeAsString('$i');
      }
      await File('$p/nuova/dentro/sesto.txt').writeAsString('6');

      final s = await g.stato(p);
      expect(s.modifiche.length, 6, reason: s.modifiche.map((m) => m.percorso).join(', '));
      expect(s.modifiche.map((m) => m.percorso),
          contains('nuova/dentro/sesto.txt'));
      // E nessuna riga finisce per barra: quelle non sono file.
      expect(s.modifiche.where((m) => m.percorso.endsWith('/')), isEmpty);
    });

    test('e quello che il .gitignore esclude non si conta lo stesso', () async {
      await g.inizia(p);
      await firma();
      await File('$p/.gitignore').writeAsString('nuova/scarti/\n');
      await g.salva(p, 'primo');

      await Directory('$p/nuova/scarti').create(recursive: true);
      await File('$p/nuova/buono.txt').writeAsString('x');
      await File('$p/nuova/scarti/roba.o').writeAsString('x');

      final s = await g.stato(p);
      expect(s.modifiche.map((m) => m.percorso), ['nuova/buono.txt']);
    });

    test('un rinomino si vede come un rinomino', () async {
      await g.inizia(p);
      await firma();
      await File('$p/prima.txt').writeAsString('contenuto abbastanza lungo\n' * 20);
      await g.salva(p, 'primo');
      await File('$p/prima.txt').rename('$p/dopo.txt');

      final s = await g.stato(p);
      final r = s.modifiche.where((m) => m.verso == Verso.rinominato);
      // git riconosce il rinomino solo dopo `add`; se non ci riesce lo vede
      // come «tolto + aggiunto», e va bene lo stesso: non deve mai contare
      // tre file dove ce ne sono due.
      expect(s.modifiche.length, lessThanOrEqualTo(2));
      if (r.isNotEmpty) expect(r.single.percorsoPrima, 'prima.txt');
    });
  });

  // ── I rifiuti ──────────────────────────────────────────────────────────

  group('i rifiuti', () {
    late Directory temp;
    late String p;
    late GitMotore g;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('minerva-git-no-');
      p = temp.path;
      g = GitMotore();
      await g.inizia(p);
      await Process.run('git', ['-C', p, 'config', 'user.name', 'Prova']);
      await Process.run('git', ['-C', p, 'config', 'user.email', 'p@prova']);
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('non si salva senza dire cosa hai fatto', () async {
      await File('$p/x.txt').writeAsString('x');
      final e = await g.salva(p, '   ');
      expect(e.riuscito, isFalse);
      expect(e.errore, contains('cosa hai fatto'));
    });

    test('non si salva se non è cambiato niente', () async {
      // `inizia()` lascia il `.gitignore` da salvare: si comincia da lì, e
      // solo dopo la cartella è davvero pulita.
      expect((await g.salva(p, 'comincio')).riuscito, isTrue);
      final e = await g.salva(p, 'niente');
      expect(e.riuscito, isFalse);
      expect(e.errore, contains('Non è cambiato niente'));
    });

    test('un file oltre i 100 MB si ferma PRIMA di entrare nella storia',
        () async {
      // Dopo il salvataggio sarebbe troppo tardi: resterebbe dentro per
      // sempre, e per toglierlo bisognerebbe riscrivere ogni salvataggio.
      final f = File('$p/enorme.bin');
      final w = f.openSync(mode: FileMode.write);
      w.setPositionSync(101 * 1024 * 1024);
      w.writeByteSync(0);
      await w.close();

      final e = await g.salva(p, 'ci provo');
      expect(e.riuscito, isFalse);
      expect(e.errore, contains('100 MB'));
      expect(e.grossi, contains('enorme.bin'));
      // E la storia è rimasta vuota.
      expect(await g.haStoria(p), isFalse);
    });

    test('…ma si può insistere, se uno sa cosa fa', () async {
      final f = File('$p/enorme.bin');
      final w = f.openSync(mode: FileMode.write);
      w.setPositionSync(101 * 1024 * 1024);
      w.writeByteSync(0);
      await w.close();

      final e = await g.salva(p, 'lo voglio lo stesso', forza: true);
      expect(e.riuscito, isTrue, reason: e.errore);
    });

    test('non si torna a un salvataggio inventato', () async {
      expect((await g.tornaA(p, 'non-esadecimale')).riuscito, isFalse);
      expect((await g.tornaA(p, '../../etc')).riuscito, isFalse);
      expect((await g.tornaA(p, 'deadbeef')).riuscito, isFalse);
    });

    test('senza firma, il messaggio è italiano e dice cosa manca', () async {
      await Process.run('git', ['-C', p, 'config', '--unset', 'user.email']);
      await File('$p/x.txt').writeAsString('x');
      final e = await g.salva(p, 'ci provo');
      // O git usa una firma dedotta e riesce, o rifiuta: in questo secondo
      // caso il messaggio non deve essere in inglese.
      if (!e.riuscito) {
        expect(e.errore, contains('firmare'));
      }
    });
  });

  // ── Chi firma ──────────────────────────────────────────────────────────

  group('la firma', () {
    late Directory temp;
    late String p;
    late GitMotore g;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('minerva-firma-');
      p = temp.path;
      g = GitMotore();
      await g.inizia(p);
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('un indirizzo finto si riconosce prima dell\'invio, non dopo',
        () async {
      // `giacomo@example.com` funziona benissimo finché resta sul computer.
      // Al primo invio GitHub non riconosce l'autore, e i salvataggi
      // risultano di nessuno — che è irreparabile senza riscrivere la storia.
      await Process.run('git', ['-C', p, 'config', 'user.name', 'Giacomo']);
      await Process.run(
          'git', ['-C', p, 'config', 'user.email', 'giacomo@example.com']);
      final f = await g.firma(p);
      expect(f.completa, isTrue);
      expect(f.credibile, isFalse);
    });

    test('un indirizzo vero è credibile', () async {
      await Process.run('git', ['-C', p, 'config', 'user.name', 'Giacomo']);
      await Process.run(
          'git', ['-C', p, 'config', 'user.email', 'tizio@gmail.com']);
      final f = await g.firma(p);
      expect(f.completa && f.credibile, isTrue);
    });
  });
}
