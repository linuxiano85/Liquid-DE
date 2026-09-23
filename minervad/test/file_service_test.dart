import 'dart:io';

import 'package:minervad/services/file_service.dart';
import 'package:test/test.dart';

/// Prove sul servizio che legge e sposta i file.
///
/// Sono le operazioni che, sbagliate, fanno danni veri: un ordinamento storto
/// si vede e si corregge, una copia che sovrascrive il file sbagliato no.
/// Tutto avviene dentro una cartella temporanea che viene cancellata alla
/// fine — nessuna prova tocca niente di chi esegue le prove.
void main() {
  late Directory temp;
  late FileService files;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('minerva-file-');
    files = FileService();
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<void> touch(String relative, [String content = 'x']) async {
    final f = File('${temp.path}/$relative');
    await f.parent.create(recursive: true);
    await f.writeAsString(content);
  }

  // ── Chi è un dispositivo e chi è il computer ────────────────────────────
  //
  // È la parte di questo servizio che si è rotta più volte, e ogni volta il
  // difetto si è visto su una macchina sola: il disco di sistema in mezzo alle
  // chiavette (18 agosto 2026), i loop di waydroid fra i dischi da espellere
  // (23 agosto). Con un albero finto si prova la REGOLA, non questo computer.
  group('quali dischi sono «Dispositivi»', () {
    Map<String, dynamic> nodo(String nome, String tipo, String fs,
            List<String> punti,
            {bool rm = false, String path = ''}) =>
        {
          'name': nome,
          'type': tipo,
          'fstype': fs,
          'mountpoints': punti,
          'rm': rm,
          'path': path.isEmpty ? '/dev/$nome' : path,
        };

    test('i loop di waydroid non sono dischi da espellere', () {
      // Giacomo, 23 agosto 2026: nella colonna comparivano «/» e «vendor»,
      // che erano i due loop montati da waydroid. Premendo espelli, UDisks
      // rispondeva «Not authorized» — giustamente: non sono roba sua.
      final v = files.volumiDa([
        nodo('loop0', 'loop', 'ext4', ['/var/lib/waydroid/rootfs']),
        nodo('loop1', 'loop', 'ext4', ['/var/lib/waydroid/rootfs/vendor']),
      ], '/dev/nvme0n1p2');
      expect(v, isEmpty);
    });

    test('ma una ISO che apri tu resta un disco', () {
      // L'altra metà della regola, e serve: un filtro che toglie tutto è
      // sicuro e inutile. Quello che monti tu finisce in /run/media.
      final v = files.volumiDa([
        nodo('loop2', 'loop', 'iso9660', ['/run/media/giacomo/UBUNTU']),
      ], '/dev/nvme0n1p2');
      expect(v, hasLength(1));
      expect(v.single['mountPoint'], '/run/media/giacomo/UBUNTU');
      expect(v.single['removable'], isTrue);
    });

    test('una chiavetta USB non sparisce perché /run è di sistema', () {
      // `/run/media/...` sta dentro `/run`, che è un albero di sistema: senza
      // l'eccezione esplicita, il filtro nuovo si mangerebbe le chiavette.
      final v = files.volumiDa([
        nodo('sdb1', 'part', 'vfat', ['/run/media/giacomo/CHIAVETTA'],
            rm: true),
      ], '/dev/nvme0n1p2');
      expect(v, hasLength(1));
    });

    test('il disco di sistema non è un dispositivo', () {
      final v = files.volumiDa([
        nodo('nvme0n1p2', 'part', 'btrfs', ['/', '/var/tmp', '/home'],
            path: '/dev/nvme0n1p2'),
      ], '/dev/nvme0n1p2');
      expect(v, isEmpty);
    });

    test('gli squashfs dei pacchetti non si mostrano', () {
      final v = files.volumiDa([
        nodo('loop9', 'loop', 'squashfs', ['/var/lib/snapd/snap/core/1']),
      ], '/dev/nvme0n1p2');
      expect(v, isEmpty);
    });
  });

  // ── Le frasi che legge chi usa il programma ─────────────────────────────
  //
  // «Error unmounting /dev/loop1: GDBus.Error:org.freedesktop.UDisks2.Error.
  // NotAuthorized: Not authorized to perform operation» è comparso davvero,
  // in inglese, su una barra rossa in fondo al gestore file. Dice tre cose
  // che non servono e nasconde l'unica che serve.
  group('gli errori dei dischi si leggono', () {
    test('«non autorizzato» diventa una frase', () {
      final m = FileService.errorePulito(
          'Error unmounting /dev/loop1: GDBus.Error:'
          'org.freedesktop.UDisks2.Error.NotAuthorized: '
          'Not authorized to perform operation');
      expect(m, isNot(contains('GDBus')));
      expect(m, isNot(contains('org.freedesktop')));
      expect(m.toLowerCase(), contains('sistema'));
    });

    test('«disco occupato» dice cosa fare', () {
      final m = FileService.errorePulito(
          'Error unmounting /dev/sdb1: GDBus.Error:'
          'org.freedesktop.UDisks2.Error.DeviceBusy: target is busy');
      expect(m.toLowerCase(), contains('in uso'));
    });

    test('un errore che non conosciamo perde solo il guscio', () {
      // Meglio una frase in inglese che una frase in italiano inventata da
      // noi che dice un'altra cosa.
      final m = FileService.errorePulito(
          'Error mounting /dev/sdb1: GDBus.Error:'
          'org.freedesktop.UDisks2.Error.Failed: qualcosa di nuovo');
      expect(m, 'qualcosa di nuovo');
    });

    test('un errore vuoto non lascia una barra rossa muta', () {
      expect(FileService.errorePulito('   '), isNotEmpty);
    });
  });

  // ── I collegamenti simbolici non si seguono ────────────────────────────
  //
  // In un gestore file è la differenza fra «hai cancellato un collegamento» e
  // «hai cancellato la cartella a cui puntava». Il codice usa
  // `FileSystemEntity.type(followLinks: false)`, quindi un collegamento a una
  // cartella finisce nel ramo dei FILE e viene tolto il collegamento — ma è
  // una cosa che si legge nel codice e si crede, e qui invece si dimostra.
  group('i collegamenti simbolici', () {
    test('cancellarne uno NON cancella quello a cui punta', () async {
      await touch('prezioso/dentro.txt', 'importante');
      await Directory('${temp.path}/cartella').create();
      await Link('${temp.path}/cartella/scorciatoia')
          .create('${temp.path}/prezioso');

      final r = await files.eliminaDefinitivamente(['${temp.path}/cartella/scorciatoia']);

      expect(r['ok'], isTrue, reason: '${r['error']}');
      expect(await Link('${temp.path}/cartella/scorciatoia').exists(), isFalse);
      expect(await File('${temp.path}/prezioso/dentro.txt').exists(), isTrue,
          reason: 'il collegamento è stato SEGUITO: il difetto peggiore che '
              'un gestore file possa avere');
    });

    test('rinominarne uno rinomina il collegamento, non il bersaglio',
        () async {
      // `rename` decide col tipo RISOLTO (`isDirectory` segue i
      // collegamenti), quindi un collegamento a una cartella finisce nel ramo
      // delle cartelle. Su Linux `rename(2)` agisce comunque sul
      // collegamento — ma è una cosa che si dà per buona finché non si prova.
      await touch('prezioso/dentro.txt', 'importante');
      await Link('${temp.path}/scorciatoia').create('${temp.path}/prezioso');

      final r = await files.rename(
          '${temp.path}/scorciatoia', '${temp.path}/altro-nome');

      expect(r['ok'], isTrue, reason: '${r['error']}');
      expect(await Link('${temp.path}/altro-nome').exists(), isTrue);
      expect(await Directory('${temp.path}/prezioso').exists(), isTrue,
          reason: 'la cartella puntata è stata spostata');
      expect(await File('${temp.path}/prezioso/dentro.txt').exists(), isTrue);
    });

    test('cancellare la cartella che lo contiene non segue il collegamento',
        () async {
      await touch('prezioso/dentro.txt', 'importante');
      await Directory('${temp.path}/cartella').create();
      await Link('${temp.path}/cartella/scorciatoia')
          .create('${temp.path}/prezioso');

      await files.eliminaDefinitivamente(['${temp.path}/cartella']);

      expect(await Directory('${temp.path}/cartella').exists(), isFalse);
      expect(await File('${temp.path}/prezioso/dentro.txt').exists(), isTrue);
    });
  });

  group('elenco', () {
    test('le cartelle vengono prima dei file', () async {
      await touch('aaa.txt');
      await Directory('${temp.path}/zzz').create();

      final result = await files.list(temp.path);
      final names = [for (final e in result['entries']) e['name']];

      expect(names, ['zzz', 'aaa.txt']);
    });

    test('ordina senza distinguere maiuscole e minuscole', () async {
      // Con l'ordine grezzo dei caratteri tutte le maiuscole verrebbero prima
      // di tutte le minuscole: «Zeta» prima di «alfa». Nessuno cerca così.
      await touch('alfa.txt');
      await touch('Beta.txt');
      await touch('gamma.txt');

      final result = await files.list(temp.path);
      final names = [for (final e in result['entries']) e['name']];

      expect(names, ['alfa.txt', 'Beta.txt', 'gamma.txt']);
    });

    test('i file nascosti si vedono solo se richiesti', () async {
      await touch('visibile.txt');
      await touch('.nascosto');

      final chiuso = await files.list(temp.path);
      expect([for (final e in chiuso['entries']) e['name']], ['visibile.txt']);

      final aperto = await files.list(temp.path, showHidden: true);
      expect([for (final e in aperto['entries']) e['name']],
          containsAll(['.nascosto', 'visibile.txt']));
    });

    test('ogni voce dice tipo, dimensione e data', () async {
      await touch('dati.txt', 'dodici byte');

      final result = await files.list(temp.path);
      final e = result['entries'].single;

      expect(e['isDir'], isFalse);
      expect(e['size'], 11);
      expect(e['modified'], isA<int>());
      expect(e['mode'], isNotEmpty);
    });

    test('una cartella che non esiste risponde con un errore, non esplode',
        () async {
      final result = await files.list('${temp.path}/mai-esistita');

      expect(result['error'], isNotEmpty);
      expect(result['entries'], isEmpty);
    });
  });

  group('operazioni', () {
    test('crea una cartella', () async {
      final r = await files.makeDirectory('${temp.path}/nuova');

      expect(r['ok'], isTrue);
      expect(await Directory('${temp.path}/nuova').exists(), isTrue);
    });

    test('creare una cartella che c\'è già fallisce senza rovinarla',
        () async {
      await Directory('${temp.path}/esiste').create();
      await touch('esiste/dentro.txt');

      final r = await files.makeDirectory('${temp.path}/esiste');

      expect(r['ok'], isFalse);
      expect(await File('${temp.path}/esiste/dentro.txt').exists(), isTrue);
    });

    test('rinomina un file', () async {
      await touch('prima.txt', 'contenuto');

      final r = await files.rename(
          '${temp.path}/prima.txt', '${temp.path}/dopo.txt');

      expect(r['ok'], isTrue);
      expect(await File('${temp.path}/dopo.txt').readAsString(), 'contenuto');
      expect(await File('${temp.path}/prima.txt').exists(), isFalse);
    });

    test('misura una cartella intera', () async {
      await touch('a/uno.txt', '12345');
      await touch('a/b/due.txt', '123');

      final r = await files.measure('${temp.path}/a');

      expect(r['bytes'], 8);
    });
  });

  group('copia e spostamento', () {
    /// I trasferimenti sono asincroni e si annunciano sul flusso: si aspetta
    /// che il lavoro dica di aver finito invece di dormire un tempo a caso.
    Future<Map<String, dynamic>> waitForJob(String id) {
      return files.progress
          .firstWhere((j) =>
              j['id'] == id && (j['state'] == 'done' || j['state'] == 'error'))
          .timeout(const Duration(seconds: 20));
    }

    test('copia un file lasciando l\'originale dov\'è', () async {
      await touch('origine.txt', 'ciao');
      await Directory('${temp.path}/destinazione').create();

      final id = await files.startTransfer(
        sources: ['${temp.path}/origine.txt'],
        destination: '${temp.path}/destinazione',
        move: false,
      );
      final done = await waitForJob(id);

      expect(done['state'], 'done');
      expect(await File('${temp.path}/destinazione/origine.txt').readAsString(),
          'ciao');
      expect(await File('${temp.path}/origine.txt').exists(), isTrue);
    });

    test('lo spostamento porta via l\'originale', () async {
      await touch('viaggia.txt', 'ciao');
      await Directory('${temp.path}/destinazione').create();

      final id = await files.startTransfer(
        sources: ['${temp.path}/viaggia.txt'],
        destination: '${temp.path}/destinazione',
        move: true,
      );
      await waitForJob(id);

      expect(await File('${temp.path}/destinazione/viaggia.txt').exists(),
          isTrue);
      expect(await File('${temp.path}/viaggia.txt').exists(), isFalse);
    });

    test('copiare due volte NON sovrascrive: rinomina la seconda', () async {
      // È la prova più importante di tutto il file. Un gestore file che
      // sovrascrive in silenzio distrugge lavoro altrui, e lo fa senza che
      // nessuno se ne accorga fino a quando non serve quel file.
      await touch('doc.txt', 'primo');
      await Directory('${temp.path}/dove').create();
      await File('${temp.path}/dove/doc.txt').writeAsString('già qui');

      final id = await files.startTransfer(
        sources: ['${temp.path}/doc.txt'],
        destination: '${temp.path}/dove',
        move: false,
      );
      await waitForJob(id);

      expect(await File('${temp.path}/dove/doc.txt').readAsString(), 'già qui',
          reason: 'il file che c\'era prima non si tocca');
      expect(await File('${temp.path}/dove/doc (1).txt').readAsString(),
          'primo');
    });

    test('copia una cartella con tutto quello che ha dentro', () async {
      await touch('albero/uno.txt', 'a');
      await touch('albero/ramo/due.txt', 'b');
      await Directory('${temp.path}/dove').create();

      final id = await files.startTransfer(
        sources: ['${temp.path}/albero'],
        destination: '${temp.path}/dove',
        move: false,
      );
      await waitForJob(id);

      expect(await File('${temp.path}/dove/albero/uno.txt').readAsString(), 'a');
      expect(await File('${temp.path}/dove/albero/ramo/due.txt').readAsString(),
          'b');
    });
  });

  // ── Il cestino ─────────────────────────────────────────────────────────
  //
  // Il cestino di prova sta dentro la cartella temporanea, indicato al
  // servizio col parametro apposta: senza, queste prove scriverebbero — e
  // svuoterebbero — il cestino VERO di chi le esegue.

  group('cestino', () {
    late FileService cestinato;

    setUp(() {
      cestinato = FileService(cestinoDiProva: '${temp.path}/Cestino');
    });

    test('cestinare toglie di lì e mette nel cestino', () async {
      await touch('lettera.txt', 'ciao');

      final r = await cestinato.trash(['${temp.path}/lettera.txt']);

      expect(r['ok'], isTrue, reason: '${r['error']}');
      expect(await File('${temp.path}/lettera.txt').exists(), isFalse);
      expect(
          await File('${temp.path}/Cestino/files/lettera.txt').readAsString(),
          'ciao');
    });

    test('ripristinare lo rimette esattamente dov\'era', () async {
      await touch('sotto/lettera.txt', 'ciao');
      await cestinato.trash(['${temp.path}/sotto/lettera.txt']);

      final r = await cestinato
          .restoreFromTrash(['${temp.path}/Cestino/files/lettera.txt']);

      expect(r['ok'], isTrue, reason: '${r['error']}');
      expect(await File('${temp.path}/sotto/lettera.txt').readAsString(),
          'ciao');
      // E la scheda se ne va con lui: se restasse, il prossimo file con lo
      // stesso nome verrebbe rimesso dove stava QUESTO.
      expect(
          await File('${temp.path}/Cestino/info/lettera.txt.trashinfo')
              .exists(),
          isFalse);
    });

    test('ripristinare ricrea la cartella se non c\'è più', () async {
      await touch('sparita/lettera.txt', 'ciao');
      await cestinato.trash(['${temp.path}/sparita/lettera.txt']);
      await Directory('${temp.path}/sparita').delete(recursive: true);

      final r = await cestinato
          .restoreFromTrash(['${temp.path}/Cestino/files/lettera.txt']);

      expect(r['ok'], isTrue, reason: '${r['error']}');
      expect(await File('${temp.path}/sparita/lettera.txt').exists(), isTrue);
    });

    test('ripristinare NON sovrascrive quello che c\'è al suo posto',
        () async {
      // Un recupero che cancella è peggio del danno che doveva riparare.
      await touch('lettera.txt', 'la vecchia');
      await cestinato.trash(['${temp.path}/lettera.txt']);
      await touch('lettera.txt', 'la nuova');

      final r = await cestinato
          .restoreFromTrash(['${temp.path}/Cestino/files/lettera.txt']);

      expect(r['ok'], isTrue, reason: '${r['error']}');
      expect(await File('${temp.path}/lettera.txt').readAsString(), 'la nuova');
      expect(await File('${temp.path}/lettera.txt 2').readAsString(),
          'la vecchia');
    });

    test('senza la scheda si dice che non si sa da dove veniva', () async {
      await touch('lettera.txt');
      await cestinato.trash(['${temp.path}/lettera.txt']);
      await File('${temp.path}/Cestino/info/lettera.txt.trashinfo').delete();

      final r = await cestinato
          .restoreFromTrash(['${temp.path}/Cestino/files/lettera.txt']);

      expect(r['ok'], isFalse);
      expect(r['error'], contains('non so da dove veniva'));
      // E il file resta nel cestino: non lo si butta perché non si sa dove
      // rimetterlo.
      expect(await File('${temp.path}/Cestino/files/lettera.txt').exists(),
          isTrue);
    });

    test('un nome con caratteri strani sopravvive al giro completo', () async {
      // Il percorso nella scheda è scappato come un indirizzo web, perché è
      // lo stesso formato che leggono Dolphin e Nautilus. Se lo scrivessimo
      // crudo, un nome con un `%` tornerebbe indietro diverso.
      await touch('appunti 100% & #1.txt', 'ok');
      await cestinato.trash(['${temp.path}/appunti 100% & #1.txt']);

      final r = await cestinato.restoreFromTrash(
          ['${temp.path}/Cestino/files/appunti 100% & #1.txt']);

      expect(r['ok'], isTrue, reason: '${r['error']}');
      expect(await File('${temp.path}/appunti 100% & #1.txt').readAsString(),
          'ok');
    });

    test('svuotare cancella davvero, file e schede', () async {
      await touch('uno.txt');
      await touch('due.txt');
      await cestinato
          .trash(['${temp.path}/uno.txt', '${temp.path}/due.txt']);

      final r = await cestinato.emptyTrash();

      expect(r['ok'], isTrue, reason: '${r['error']}');
      expect(
          await Directory('${temp.path}/Cestino/files').list().isEmpty, isTrue);
      expect(
          await Directory('${temp.path}/Cestino/info').list().isEmpty, isTrue);
    });

    test('svuotare un cestino che non è mai stato usato non è un errore',
        () async {
      final r = await cestinato.emptyTrash();
      expect(r['ok'], isTrue, reason: '${r['error']}');
    });

    test('sa dire cosa è dentro il cestino e cosa no', () {
      expect(cestinato.nelCestino('${temp.path}/Cestino/files/x.txt'), isTrue);
      expect(cestinato.nelCestino('${temp.path}/altro/x.txt'), isFalse);
    });

    test('il cestino compare fra i posti della barra laterale', () async {
      final r = await cestinato.places();
      final generi = [for (final p in r['places']) p['kind']];
      expect(generi, contains('trash'));
    });

    test('la voce del cestino dice se è vuoto', () async {
      var r = await cestinato.places();
      var voce = r['places'].firstWhere((p) => p['kind'] == 'trash');
      expect(voce['vuoto'], isTrue, reason: 'cestino appena nato');

      // Dentro qualcosa non è più vuoto, e svuotandolo torna a dirlo.
      await touch('vuoto-test.txt');
      await cestinato.trash(['${temp.path}/vuoto-test.txt']);
      r = await cestinato.places();
      voce = r['places'].firstWhere((p) => p['kind'] == 'trash');
      expect(voce['vuoto'], isFalse, reason: 'cestino con dentro un file');

      await cestinato.emptyTrash();
      r = await cestinato.places();
      voce = r['places'].firstWhere((p) => p['kind'] == 'trash');
      expect(voce['vuoto'], isTrue, reason: 'cestino svuotato');
    });
  });
}
