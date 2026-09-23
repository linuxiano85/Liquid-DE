import 'dart:io';

import 'package:minervad/services/custodia/registro.dart';
import 'package:test/test.dart';

/// Prove sul registro dei progetti.
///
/// Il registro decide **su cosa** la Custodia ha il permesso di agire, e quindi
/// decide anche quanto può fare danno. Le prove che contano qui sono i rifiuti:
/// registrare la home intera o due progetti uno dentro l'altro non dà nessun
/// errore visibile — dà una catastrofe il giorno che qualcuno preme «torna
/// indietro».
void main() {
  late Directory temp;
  late Registro reg;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('minerva-registro-');
    reg = Registro(percorso: '${temp.path}/progetti.json');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<String> cartella(String nome) async {
    final d = Directory('${temp.path}/$nome');
    await d.create(recursive: true);
    return d.path;
  }

  // ── Aggiungere ─────────────────────────────────────────────────────────

  group('aggiungere un progetto', () {
    test('una cartella normale entra, e prende il nome della cartella',
        () async {
      final p = await cartella('Minerva Shell');
      final e = reg.aggiungi(p);
      expect(e.riuscito, isTrue, reason: e.errore);
      expect(e.progetto!.nome, 'Minerva Shell');
      expect(reg.progetti.length, 1);
    });

    test('la barra finale non crea un secondo progetto', () async {
      final p = await cartella('Uno');
      expect(reg.aggiungi(p).riuscito, isTrue);
      final due = reg.aggiungi('$p/');
      expect(due.riuscito, isFalse);
      expect(due.errore, contains('già nell\'elenco'));
    });

    test('togliere non tocca i punti di ritorno', () async {
      final p = await cartella('Uno');
      reg.aggiungi(p);
      expect(reg.togli(p).riuscito, isTrue);
      expect(reg.progetti, isEmpty);
      // La cartella vera è ancora lì: togliere dall'elenco non cancella niente.
      expect(await Directory(p).exists(), isTrue);
    });
  });

  // ── I rifiuti ──────────────────────────────────────────────────────────

  group('i rifiuti', () {
    test('un percorso relativo non si registra', () {
      final e = reg.aggiungi('Documenti/Progetti');
      expect(e.riuscito, isFalse);
      expect(e.errore, contains('percorso completo'));
    });

    test('una cartella che non c\'è non si registra', () {
      final e = reg.aggiungi('${temp.path}/mai-esistita');
      expect(e.riuscito, isFalse);
      expect(e.errore, contains('non esiste'));
    });

    test('un file non è un progetto', () async {
      final f = File('${temp.path}/roba.txt');
      await f.writeAsString('x');
      final e = reg.aggiungi(f.path);
      expect(e.riuscito, isFalse);
    });

    test('la radice e le cartelle di sistema, mai', () {
      for (final p in ['/', '/etc', '/usr', '/home', '/var', '/boot']) {
        final e = reg.aggiungi(p);
        expect(e.riuscito, isFalse, reason: 'ha accettato $p');
      }
    });

    test('la home dell\'utente, mai', () {
      final casa = Platform.environment['HOME'];
      if (casa == null) return;
      expect(reg.aggiungi(casa).riuscito, isFalse);
      expect(reg.aggiungi('$casa/').riuscito, isFalse);
      // «torna a ieri» su Documenti riporterebbe indietro 310 GB, posta e
      // chiavi comprese.
      expect(reg.aggiungi('$casa/Documenti').riuscito, isFalse);
      expect(reg.aggiungi('$casa/.ssh').riuscito, isFalse);
      expect(reg.aggiungi('$casa/.config').riuscito, isFalse);
    });

    test('un progetto dentro un altro progetto, mai', () async {
      final padre = await cartella('Padre');
      await cartella('Padre/Figlio');
      expect(reg.aggiungi(padre).riuscito, isTrue);

      final e = reg.aggiungi('$padre/Figlio');
      expect(e.riuscito, isFalse);
      expect(e.errore, contains('senza dirlo'));
    });

    test('e nemmeno al contrario: prima il figlio, poi il padre', () async {
      final padre = await cartella('Padre2');
      final figlio = await cartella('Padre2/Figlio');
      expect(reg.aggiungi(figlio).riuscito, isTrue);

      final e = reg.aggiungi(padre);
      expect(e.riuscito, isFalse);
      expect(e.errore, contains('senza dirlo'));
    });

    test('due cartelle col prefisso in comune NON sono annidate', () async {
      // `/x/Minerva` e `/x/Minerva Shell`: la seconda comincia per la prima,
      // ma non ci sta dentro. Un confronto senza la barra le rifiuterebbe.
      final a = await cartella('Minerva');
      final b = await cartella('Minerva Shell');
      expect(reg.aggiungi(a).riuscito, isTrue);
      final e = reg.aggiungi(b);
      expect(e.riuscito, isTrue, reason: e.errore);
    });

    test('togliere qualcosa che non c\'è lo dice', () {
      expect(reg.togli('/x/y').riuscito, isFalse);
    });
  });

  // ── Il file ────────────────────────────────────────────────────────────

  group('il file su disco', () {
    test('si scrive e si rilegge identico', () async {
      final p = await cartella('Uno');
      reg.aggiungi(p, nome: 'Il Mio Uno');
      reg.progetti.first.destinazioni.add(Destinazione(
        tipo: 'github',
        nome: 'GitHub',
        dove: 'git@github.com:tizio/uno.git',
      ));
      await reg.salva();

      final due = Registro(percorso: reg.percorso);
      await due.carica();
      expect(due.progetti.length, 1);
      expect(due.progetti.first.nome, 'Il Mio Uno');
      expect(due.progetti.first.destinazioni.first.dove,
          'git@github.com:tizio/uno.git');
    });

    test('non contiene nessuna parola d\'ordine', () async {
      final p = await cartella('Uno');
      reg.aggiungi(p);
      reg.progetti.first.destinazioni.add(Destinazione(
        tipo: 'github',
        nome: 'GitHub',
        dove: 'git@github.com:tizio/uno.git',
      ));
      await reg.salva();
      final testo = await File(reg.percorso).readAsString();
      // Il gettone sta nel portachiavi. Qui c'è solo dove andare.
      expect(testo.toLowerCase(), isNot(contains('token')));
      expect(testo.toLowerCase(), isNot(contains('password')));
      expect(testo, isNot(contains('ghp_')));
    });

    test('un registro illeggibile non impedisce di partire', () async {
      await File(reg.percorso).parent.create(recursive: true);
      await File(reg.percorso).writeAsString('{ questo non è json');
      await reg.carica();
      expect(reg.progetti, isEmpty);
      // E il file resta lì: è l'unica copia di quello che l'utente aveva
      // scelto, e cancellarlo sarebbe peggio del difetto.
      expect(await File(reg.percorso).exists(), isTrue);
    });

    test('una voce rotta non porta giù le altre', () async {
      await File(reg.percorso).parent.create(recursive: true);
      await File(reg.percorso).writeAsString('''
{ "versione": 1, "progetti": [
    { "percorso": "non-assoluto", "nome": "Rotto" },
    { "nome": "Senza percorso" },
    { "percorso": "/x/Buono", "nome": "Buono" }
] }
''');
      await reg.carica();
      expect(reg.progetti.length, 1);
      expect(reg.progetti.first.nome, 'Buono');
    });

    test('scrivere non lascia mai un file a metà', () async {
      final p = await cartella('Uno');
      reg.aggiungi(p);
      await reg.salva();
      await reg.salva();
      // Il file di lavoro non deve sopravvivere alla scrittura.
      expect(await File('${reg.percorso}.nuovo').exists(), isFalse);
    });
  });

  // ── Il motore suggerito ────────────────────────────────────────────────

  group('come tiene la storia, questa cartella?', () {
    test('con un .git dentro è git, senza discutere', () async {
      final p = await cartella('ConGit');
      await Directory('$p/.git').create();
      expect(Registro.suggerisciMotore(p), 'git');
    });

    test('una cartella di codice è git', () async {
      final p = await cartella('Codice');
      await File('$p/main.dart').writeAsString('void main() {}');
      await File('$p/README.md').writeAsString('# ciao');
      expect(Registro.suggerisciMotore(p), 'git');
    });

    test('una cartella con dentro immagini disco è copia', () async {
      // È il caso di `Ruby`: 286 GB di ROM Android. Su GitHub non entrerà mai,
      // e non è un limite da aggirare.
      final p = await cartella('Ruby');
      await File('$p/boot.img').writeAsString('finta');
      expect(Registro.suggerisciMotore(p), 'copia');
    });

    test('e li trova anche un piano più sotto', () async {
      final p = await cartella('Roba');
      await Directory('$p/dentro').create();
      await File('$p/dentro/immagine.iso').writeAsString('finta');
      expect(Registro.suggerisciMotore(p), 'copia');
    });

    test('un file oltre i cento megabyte è copia, comunque si chiami',
        () async {
      final p = await cartella('Grosso');
      final f = File('$p/senza-estensione');
      final r = f.openSync(mode: FileMode.write);
      r.setPositionSync(101 * 1024 * 1024);
      r.writeByteSync(0);
      await r.close();
      expect(Registro.suggerisciMotore(p), 'copia');
    });
  });

  // ── Trovare i progetti che ci sono già ─────────────────────────────────

  group('scoprire', () {
    test('elenca le cartelle, ignora i file e i nascosti', () async {
      final base = await cartella('Progetti');
      await Directory('$base/Uno').create();
      await Directory('$base/Due').create();
      await Directory('$base/.nascosto').create();
      await File('$base/appunti.txt').writeAsString('x');

      final trovati = Registro.scopri(base);
      expect(trovati.map((p) => p.nome), ['Due', 'Uno']);
    });

    test('propone il motore giusto per ognuno', () async {
      final base = await cartella('Progetti2');
      await Directory('$base/Codice/.git').create(recursive: true);
      await Directory('$base/Rom').create();
      await File('$base/Rom/super.img').writeAsString('x');

      final trovati = {for (final p in Registro.scopri(base)) p.nome: p.motore};
      expect(trovati['Codice'], 'git');
      expect(trovati['Rom'], 'copia');
    });

    test('una cartella che non c\'è dà una lista vuota, non un errore', () {
      expect(Registro.scopri('${temp.path}/mai-esistita'), isEmpty);
    });
  });
}
