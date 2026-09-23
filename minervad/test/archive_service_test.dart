import 'dart:io';

import 'package:minervad/services/archive_service.dart';
import 'package:test/test.dart';

/// Prove su comprimi ed estrai.
///
/// Girano contro `bsdtar` vero, non contro una sua imitazione: metà di ciò che
/// può andare storto qui sta nel comportamento dello strumento — quali nomi
/// rifiuta, cosa scrive su stderr, cosa mette dentro l'archivio — e una
/// finzione riprodurrebbe quello che credo, non quello che fa.
///
/// Tutto succede in una cartella temporanea che viene cancellata alla fine.
void main() {
  late Directory temp;
  late ArchiveService archivi;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('minerva-arch-');
    archivi = ArchiveService();
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<void> scrivi(String relativo, [String contenuto = 'ciao']) async {
    final f = File('${temp.path}/$relativo');
    await f.parent.create(recursive: true);
    await f.writeAsString(contenuto);
  }

  // ── Riconoscere un archivio ────────────────────────────────────────────

  group('riconoscere', () {
    test('riconosce le estensioni che sa aprire', () {
      expect(ArchiveService.eArchivio('/casa/foto.zip'), isTrue);
      expect(ArchiveService.eArchivio('/casa/roba.tar.zst'), isTrue);
      expect(ArchiveService.eArchivio('/casa/vecchio.rar'), isTrue);
      expect(ArchiveService.eArchivio('/casa/lettera.odt'), isFalse);
    });

    test('non si fa fermare dalle maiuscole', () {
      // I file che arrivano da Windows si chiamano spesso «ROBA.ZIP», e chi
      // confronta con `endsWith('.zip')` e basta non li riconosce.
      expect(ArchiveService.eArchivio('/casa/ROBA.ZIP'), isTrue);
    });

    test('le doppie estensioni vincono sulle semplici', () {
      // Se `.gz` venisse provato prima di `.tar.gz`, la cartella estratta si
      // chiamerebbe «foto.tar» — che è il nome di un file, non di una
      // cartella, e si porta dietro un'estensione che non vuol dire niente.
      expect(ArchiveService.nomeSenzaEstensione('foto.tar.gz'), 'foto');
      expect(ArchiveService.nomeSenzaEstensione('foto.tgz'), 'foto');
      expect(ArchiveService.nomeSenzaEstensione('foto.zip'), 'foto');
      expect(ArchiveService.nomeSenzaEstensione('senza-estensione'),
          'senza-estensione');
    });
  });

  // ── Comprimere ─────────────────────────────────────────────────────────

  group('comprimere', () {
    test('un file solo diventa un archivio col suo nome', () async {
      await scrivi('lettera.txt', 'buongiorno');

      final r = await archivi.comprimi(['${temp.path}/lettera.txt']);

      expect(r['ok'], isTrue, reason: '${r['error']}');
      expect(r['percorso'], '${temp.path}/lettera.zip');
      expect(await File('${temp.path}/lettera.zip').exists(), isTrue);
    });

    test('dentro ci sono i nomi semplici, non i percorsi completi', () async {
      // È il difetto che rende un archivio sgradevole da ricevere: aperto da
      // qualcun altro crea `home/giacomo/Documenti/…` invece del file.
      await scrivi('lettera.txt');

      final r = await archivi.comprimi(['${temp.path}/lettera.txt']);
      final elenco = await Process.run('bsdtar', ['-tf', r['percorso']]);

      expect('${elenco.stdout}'.trim(), 'lettera.txt');
    });

    test('più file prendono il nome della cartella che li contiene', () async {
      await scrivi('uno.txt');
      await scrivi('due.txt');

      final r = await archivi.comprimi(
          ['${temp.path}/uno.txt', '${temp.path}/due.txt']);

      expect(r['ok'], isTrue, reason: '${r['error']}');
      final nome = ArchiveService.nomeSenzaEstensione(
          (r['percorso'] as String).split('/').last);
      expect(nome, temp.path.split('/').last);
    });

    test('non sovrascrive un archivio che c\'è già', () async {
      await scrivi('lettera.txt');
      final primo = await archivi.comprimi(['${temp.path}/lettera.txt']);
      final secondo = await archivi.comprimi(['${temp.path}/lettera.txt']);

      expect(secondo['ok'], isTrue, reason: '${secondo['error']}');
      expect(secondo['percorso'], isNot(primo['percorso']));
      expect(secondo['percorso'], '${temp.path}/lettera 2.zip');
      expect(await File(primo['percorso']).exists(), isTrue);
    });

    test('rifiuta elementi sparsi in cartelle diverse', () async {
      // Non è un capriccio: i nomi dentro l'archivio si scrivono relativi a
      // UNA cartella, e con elementi di due cartelle diverse
      // `bsdtar -C` prenderebbe il file sbagliato o nessuno.
      await scrivi('qui/uno.txt');
      await scrivi('la/due.txt');

      final r = await archivi.comprimi(
          ['${temp.path}/qui/uno.txt', '${temp.path}/la/due.txt']);

      expect(r['ok'], isFalse);
      expect(r['error'], contains('stessa cartella'));
    });

    test('una cartella intera finisce dentro con quel che contiene', () async {
      await scrivi('foto/mare.jpg');
      await scrivi('foto/monte.jpg');

      final r = await archivi.comprimi(['${temp.path}/foto']);
      final elenco = await Process.run('bsdtar', ['-tf', r['percorso']]);

      expect('${elenco.stdout}', contains('foto/mare.jpg'));
      expect('${elenco.stdout}', contains('foto/monte.jpg'));
    });

    test('il formato decide l\'estensione', () async {
      await scrivi('roba.txt');

      final r = await archivi.comprimi(['${temp.path}/roba.txt'],
          formato: 'tarzst');

      expect(r['ok'], isTrue, reason: '${r['error']}');
      expect(r['percorso'], endsWith('.tar.zst'));
    });

    test('un formato che non conosciamo ripiega su zip invece di fallire',
        () async {
      await scrivi('roba.txt');

      final r =
          await archivi.comprimi(['${temp.path}/roba.txt'], formato: 'boh');

      expect(r['ok'], isTrue, reason: '${r['error']}');
      expect(r['percorso'], endsWith('.zip'));
    });

    test('niente da comprimere non fa partire nessun comando', () async {
      final r = await archivi.comprimi([]);
      expect(r['ok'], isFalse);
    });
  });

  // ── Estrarre ───────────────────────────────────────────────────────────

  group('estrarre', () {
    test('un archivio con una cartella sola non ne aggiunge un\'altra',
        () async {
      await scrivi('foto/mare.jpg');
      final fatto = await archivi.comprimi(['${temp.path}/foto']);
      await Directory('${temp.path}/foto').delete(recursive: true);

      final r = await archivi.estrai(fatto['percorso']);

      expect(r['ok'], isTrue, reason: '${r['error']}');
      expect(r['cartella'], temp.path);
      expect(await File('${temp.path}/foto/mare.jpg').exists(), isTrue);
      // Non `foto/foto/mare.jpg`.
      expect(await Directory('${temp.path}/foto/foto').exists(), isFalse);
    });

    test('un archivio sciolto viene raccolto in una cartella nuova', () async {
      // La «bomba»: trenta file in cima che, estratti dove capita, si mescolano
      // a quello su cui si stava lavorando e non si distinguono più.
      await scrivi('uno.txt');
      await scrivi('due.txt');
      final fatto = await archivi
          .comprimi(['${temp.path}/uno.txt', '${temp.path}/due.txt']);
      final nomeArchivio = (fatto['percorso'] as String).split('/').last;
      final atteso =
          '${temp.path}/${ArchiveService.nomeSenzaEstensione(nomeArchivio)}';

      final r = await archivi.estrai(fatto['percorso']);

      expect(r['ok'], isTrue, reason: '${r['error']}');
      expect(r['cartella'], atteso);
      expect(await File('$atteso/uno.txt').exists(), isTrue);
      expect(await File('$atteso/due.txt').exists(), isTrue);
    });

    test('se la cartella esiste già se ne fa una nuova, non si sovrascrive',
        () async {
      await scrivi('foto/mare.jpg', 'la foto vera');
      final fatto = await archivi.comprimi(['${temp.path}/foto']);
      // `foto/` è ancora lì, con dentro il lavoro di qualcuno.

      final r = await archivi.estrai(fatto['percorso']);

      expect(r['ok'], isTrue, reason: '${r['error']}');
      expect(r['cartella'], isNot(temp.path));
      expect(await File('${temp.path}/foto/mare.jpg').readAsString(),
          'la foto vera');
    });

    test('dice dov\'è finita la roba', () async {
      // Il gestore file ci porta dentro chi ha estratto: senza questo campo
      // dovrebbe indovinarlo, e indovinerebbe sbagliato nei casi qui sopra.
      await scrivi('foto/mare.jpg');
      final fatto = await archivi.comprimi(['${temp.path}/foto']);
      await Directory('${temp.path}/foto').delete(recursive: true);

      final r = await archivi.estrai(fatto['percorso']);

      expect(r['nuovo'], '${temp.path}/foto');
    });

    test('un archivio che non esiste dà un messaggio, non un\'eccezione',
        () async {
      final r = await archivi.estrai('${temp.path}/mai-esistito.zip');
      expect(r['ok'], isFalse);
      expect(r['error'], contains('non esiste'));
    });

    test('un file che non è un archivio non fa danni', () async {
      await scrivi('finto.zip', 'questo non è uno zip');

      final r = await archivi.estrai('${temp.path}/finto.zip');

      expect(r['ok'], isFalse);
      expect(r['error'], isNotEmpty);
      // E soprattutto: non ha lasciato in giro cartelle vuote.
      expect(await Directory('${temp.path}/finto').exists(), isFalse);
    });

    // ── La prova che conta ───────────────────────────────────────────────

    test('un archivio che vuole scrivere FUORI viene rifiutato', () async {
      // «Zip slip»: un membro chiamato `../../scappato.txt`. Chi lo estrae
      // senza controlli si ritrova un file scritto due cartelle più su —
      // cioè, con un archivio costruito apposta, in `~/.config` o in
      // `~/.bashrc`.
      //
      // La garanzia la dà libarchive, non noi. Questa prova esiste perché la
      // garanzia sparirebbe in silenzio se un domani qualcuno sostituisse
      // `bsdtar` con una libreria che spacchetta a mano.
      await scrivi('base/innocuo.txt');
      final cattivo = '${temp.path}/cattivo.tar';
      final fatto = await Process.run('tar', [
        '-cf', cattivo,
        '-C', temp.path,
        'base/innocuo.txt',
        '--transform', 's|base/innocuo.txt|../../scappato.txt|',
      ]);
      expect(fatto.exitCode, 0, reason: 'non sono riuscito a costruire '
          'l\'archivio cattivo: ${fatto.stderr}');

      final r = await archivi.estrai(cattivo);

      expect(r['ok'], isFalse);
      expect(await File('${temp.parent.path}/scappato.txt').exists(), isFalse,
          reason: 'IL FILE È USCITO DALLA CARTELLA');
    });
  });
}
