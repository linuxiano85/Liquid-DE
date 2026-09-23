import 'dart:io';

import 'package:minervad/services/custodia/cartella_motore.dart';
import 'package:test/test.dart';

/// Prove sull'invio a una cartella o a un disco.
///
/// ── Perché queste prove pesano più delle altre ─────────────────────────────
///
/// Perché qui c'è `rsync --delete`, che è l'unico comando di tutta la Custodia
/// che **cancella roba di qualcun altro**. Puntato sulla cartella sbagliata,
/// svuota quella cartella.
///
/// La difesa non è la prudenza di chi scrive: è che non si scrive **mai** nella
/// cartella scelta dall'utente, ma sempre dentro una sottocartella nostra col
/// nome del progetto. Il `--delete` non può arrivare oltre quella. Le prove qui
/// sotto verificano proprio quello — che se uno indica la home per sbaglio, si
/// ritrova una cartella in più e non una home vuota.
void main() {
  late Directory temp;
  late String progetto;
  late String disco;
  late CartellaMotore m;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('minerva-invio-');
    progetto = '${temp.path}/Il Progetto';
    disco = '${temp.path}/DiscoEsterno';
    await Directory('$progetto/dentro').create(recursive: true);
    await Directory(disco).create(recursive: true);
    await File('$progetto/uno.txt').writeAsString('primo');
    await File('$progetto/dentro/due.txt').writeAsString('secondo');
    m = CartellaMotore();
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  // ── I rifiuti, che qui vengono per primi ───────────────────────────────

  group('dove NON si manda niente', () {
    test('un percorso relativo', () {
      expect(CartellaMotore.percheNo(progetto, 'copie/qui'), isNotNull);
    });

    test('il progetto stesso', () {
      expect(CartellaMotore.percheNo(progetto, progetto), isNotNull);
      expect(CartellaMotore.percheNo(progetto, '$progetto/'), isNotNull);
    });

    test('una cartella DENTRO il progetto', () {
      // La copia finirebbe dentro sé stessa, e il giro dopo copierebbe anche
      // quella: cresce finché il disco non finisce.
      final e = CartellaMotore.percheNo(progetto, '$progetto/copie');
      expect(e, contains('dentro sé stessa'));
    });

    test('una cartella che CONTIENE il progetto', () {
      final e = CartellaMotore.percheNo(progetto, temp.path);
      expect(e, contains('scegline una fuori'));
    });

    test('le cartelle di sistema', () {
      for (final d in ['/', '/etc', '/usr', '/home', '/boot', '/var']) {
        expect(CartellaMotore.percheNo(progetto, d), isNotNull,
            reason: 'ha accettato $d');
      }
    });

    test('la home nuda', () {
      final casa = Platform.environment['HOME'];
      if (casa == null) return;
      expect(CartellaMotore.percheNo('/x/y', casa), isNotNull);
      // Ma una cartella dentro la home va benissimo.
      expect(CartellaMotore.percheNo('/x/y', '$casa/Copie'), isNull);
    });

    test('due nomi con lo stesso inizio non sono annidati', () {
      // `/x/Copie` e `/x/CopieVecchie`: la seconda comincia per la prima ma non
      // ci sta dentro.
      expect(CartellaMotore.percheNo('/x/Copie', '/x/CopieVecchie'), isNull);
    });

    test('una cartella che non c\'è lo dice, e nomina il disco', () async {
      final e = await m.manda(progetto, '${temp.path}/staccato', chiave: 'k');
      expect(e.riuscito, isFalse);
      expect(e.errore, contains('disco esterno'));
    });

    test('un progetto sparito non si manda', () async {
      await Directory(progetto).delete(recursive: true);
      final e = await m.manda(progetto, disco, chiave: 'k');
      expect(e.riuscito, isFalse);
    });
  });

  // ── Lo specchio ────────────────────────────────────────────────────────

  group('lo specchio', () {
    test('la prima copia porta tutto', () async {
      final e = await m.manda(progetto, disco, chiave: 'prog-abc123');
      expect(e.riuscito, isTrue, reason: e.errore);

      final base = '$disco/prog-abc123/adesso';
      expect(await File('$base/uno.txt').readAsString(), 'primo');
      expect(await File('$base/dentro/due.txt').readAsString(), 'secondo');
    });

    test('non crea un livello in più a ogni invio', () async {
      // La barra finale sulla sorgente vuol dire «il contenuto di». Senza,
      // dopo tre invii si trova `adesso/Il Progetto/Il Progetto/…`.
      await m.manda(progetto, disco, chiave: 'k');
      await m.manda(progetto, disco, chiave: 'k');
      await m.manda(progetto, disco, chiave: 'k');
      expect(await Directory('$disco/k/adesso/Il Progetto').exists(), isFalse);
      expect(await File('$disco/k/adesso/uno.txt').exists(), isTrue);
    });

    test('quello che cancelli sparisce anche dalla copia', () async {
      await m.manda(progetto, disco, chiave: 'k');
      await File('$progetto/uno.txt').delete();
      await m.manda(progetto, disco, chiave: 'k');
      expect(await File('$disco/k/adesso/uno.txt').exists(), isFalse);
    });

    test('ma NON tocca niente fuori dalla cartella del progetto', () async {
      // La proprietà che rende `--delete` sicuro. Si mette della roba
      // dell'utente accanto, e deve essere ancora lì dopo.
      await File('$disco/roba mia.txt').writeAsString('non toccarmi');
      await Directory('$disco/altre copie').create();
      await m.manda(progetto, disco, chiave: 'k');
      expect(await File('$disco/roba mia.txt').readAsString(), 'non toccarmi');
      expect(await Directory('$disco/altre copie').exists(), isTrue);
    });

    test('una modifica della STESSA lunghezza, nello stesso secondo, arriva',
        () async {
      // Il difetto peggiore che un programma di backup possa avere: non perde
      // i dati, **dice di averli salvati quando non è vero**.
      //
      // rsync di suo confronta gli orari al secondo intero. Cinque byte che
      // diventano altri cinque byte nello stesso secondo vengono saltati in
      // silenzio, e rsync esce con successo. Si chiude con
      // `--modify-window=-1`, che confronta al nanosecondo e non costa niente.
      await m.manda(progetto, disco, chiave: 'k');
      await File('$progetto/uno.txt').writeAsString('nuova');
      expect((await File('$progetto/uno.txt').length()), 5,
          reason: 'la prova non prova niente se la lunghezza cambia');

      final e = await m.manda(progetto, disco, chiave: 'k');
      expect(e.riuscito, isTrue, reason: e.errore);
      expect(await File('$disco/k/adesso/uno.txt').readAsString(), 'nuova');
    });

    test('ma un albero immutato non si ricopia', () async {
      // L'altra metà: se il confronto esatto rendesse ogni giro una ricopia
      // completa, 286 GB diventerebbero inutilizzabili.
      for (var i = 0; i < 40; i++) {
        await File('$progetto/f$i.txt').writeAsString('contenuto $i');
      }
      await m.manda(progetto, disco, chiave: 'k');
      final prima = File('$disco/k/adesso/f7.txt').statSync().modified;
      await m.manda(progetto, disco, chiave: 'k');
      expect(File('$disco/k/adesso/f7.txt').statSync().modified, prima,
          reason: 'ha ricopiato un file che non era cambiato');
    });

    test('si può escludere quello che non serve', () async {
      await Directory('$progetto/build').create();
      await File('$progetto/build/roba.o').writeAsString('x');
      await m.manda(progetto, disco, chiave: 'k', escludi: ['build/']);
      expect(await Directory('$disco/k/adesso/build').exists(), isFalse);
      expect(await File('$disco/k/adesso/uno.txt').exists(), isTrue);
    });

    test('anche i nomi con spazi e virgolette arrivano interi', () async {
      await File('$progetto/nome"strano con spazio.txt').writeAsString('x');
      final e = await m.manda(progetto, disco, chiave: 'k');
      expect(e.riuscito, isTrue, reason: e.errore);
      expect(
          await File('$disco/k/adesso/nome"strano con spazio.txt').exists(),
          isTrue);
    });
  });

  // ── I giri datati ──────────────────────────────────────────────────────

  group('i giri datati', () {
    test('il primo invio non lascia un giro: non c\'era niente da fotografare',
        () async {
      final e = await m.manda(progetto, disco,
          chiave: 'k', dataGiro: '2026-08-24_1000');
      expect(e.riuscito, isTrue, reason: e.errore);
      expect(e.giro, isNull);
      expect(await m.giri(disco, 'k'), isEmpty);
    });

    test('il secondo sì, e fotografa com\'era PRIMA', () async {
      await m.manda(progetto, disco, chiave: 'k');
      await File('$progetto/uno.txt').writeAsString('la versione nuova');

      final e = await m.manda(progetto, disco,
          chiave: 'k', dataGiro: '2026-08-24_1100');
      expect(e.riuscito, isTrue, reason: e.errore);
      expect(e.giro, isNotNull);

      // Lo specchio ha la nuova, il giro ha la vecchia.
      expect(await File('$disco/k/adesso/uno.txt').readAsString(),
          'la versione nuova');
      expect(
          await File('$disco/k/2026-08-24_1100/uno.txt').readAsString(),
          'primo');
    });

    test('un giro costa i nomi, non i file', () async {
      // `cp -al`: quello che non cambia è lo STESSO dato sul disco. È il
      // motivo per cui si possono tenere tanti giri anche su un disco esterno
      // che non sa fare il reflink di btrfs.
      await File('$progetto/grosso.bin').writeAsString('x' * 200000);
      await m.manda(progetto, disco, chiave: 'k');
      await m.manda(progetto, disco,
          chiave: 'k', dataGiro: '2026-08-24_1200');

      final a = File('$disco/k/adesso/grosso.bin').statSync();
      final b = File('$disco/k/2026-08-24_1200/grosso.bin').statSync();
      // Stesso inode = un dato solo sul disco, due nomi.
      expect(await _inode('$disco/k/adesso/grosso.bin'),
          await _inode('$disco/k/2026-08-24_1200/grosso.bin'),
          reason: 'il giro ha COPIATO invece di collegare: '
              '${a.size} e ${b.size}');
    });

    test('si elencano dal più recente, e solo i nostri', () async {
      await m.manda(progetto, disco, chiave: 'k');
      await m.manda(progetto, disco, chiave: 'k', dataGiro: '2026-08-01_0900');
      await m.manda(progetto, disco, chiave: 'k', dataGiro: '2026-08-20_0900');
      // Roba che l'utente ha messo lì: non è un giro e non si conta.
      await Directory('$disco/k/appunti').create();

      expect(await m.giri(disco, 'k'), ['2026-08-20_0900', '2026-08-01_0900']);
    });

    test('un giro che non riesce non impedisce di aggiornare lo specchio',
        () async {
      // La copia più importante è l'ultima: se il collegamento fallisce si va
      // avanti lo stesso, e lo si dice tornando `giro: null`.
      await m.manda(progetto, disco, chiave: 'k');
      final zoppo = CartellaMotore(esegui: (c, a) async {
        if (c == 'cp') return ProcessResult(0, 1, '', 'boom');
        return Process.run(c, a);
      });
      await File('$progetto/uno.txt').writeAsString('nuova');
      final e = await zoppo.manda(progetto, disco,
          chiave: 'k', dataGiro: '2026-08-24_1300');
      expect(e.riuscito, isTrue, reason: e.errore);
      expect(e.giro, isNull);
      expect(await File('$disco/k/adesso/uno.txt').readAsString(), 'nuova');
    });
  });

  // ── Gli errori ─────────────────────────────────────────────────────────

  group('gli errori si leggono', () {
    test('disco pieno', () {
      expect(CartellaMotore.erroreLeggibile('rsync: No space left on device'),
          contains('pieno'));
    });
    test('disco staccato a metà', () {
      expect(
          CartellaMotore.erroreLeggibile('No such file or directory (2)'),
          contains('staccato'));
    });
    test('un disco che si sta rompendo lo si dice', () {
      expect(CartellaMotore.erroreLeggibile('Input/output error (5)'),
          contains('rompendo'));
    });
    test('quello che non riconosce lo riporta, non lo inventa', () {
      expect(CartellaMotore.erroreLeggibile('qualcosa di mai visto'),
          'qualcosa di mai visto');
    });
  });
}

Future<int> _inode(String percorso) async {
  final r = await Process.run('stat', ['-c', '%i', percorso]);
  return int.parse('${r.stdout}'.trim());
}
