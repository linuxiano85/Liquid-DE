import 'dart:io';

import 'package:test/test.dart';
import 'package:minervad/services/manutenzione/setaccio.dart';

// Il setaccio: i file che ci sono due volte nella cartella di casa.
//
// Le prove girano su una casa finta costruita a mano, con file veri: qui
// contano i BYTE, e un file finto non ha byte. Sono piccoli — poche decine di
// kilobyte — e la soglia si abbassa per la prova.
void main() {
  late Directory casa;

  Future<File> scrivi(String dove, String contenuto) async {
    final f = File('${casa.path}/$dove');
    await f.parent.create(recursive: true);
    await f.writeAsString(contenuto);
    return f;
  }

  setUp(() async => casa = await Directory.systemTemp.createTemp('minerva-set-'));
  tearDown(() async => casa.delete(recursive: true));

  Setaccio setaccio() => Setaccio(casa: casa.path, soglia: 10);

  group('trova quello che c\'è due volte', () {
    test('e conta lo spazio in più, non lo spazio in tutto', () async {
      // Tre copie da 1000 byte sprecano 2000, non 3000: una serve.
      final testo = 'x' * 1000;
      await scrivi('Immagini/mare.jpg', testo);
      await scrivi('Scaricati/mare.jpg', testo);
      await scrivi('Documenti/mare.jpg', testo);
      final r = await setaccio().doppioni();
      final g = (r['gruppi'] as List).cast<Map<String, dynamic>>();
      expect(g.length, 1);
      expect(g.single['byteInPiu'], 2000);
      expect(r['sprecato'], 2000);
    });

    test('due file diversi della stessa misura non sono doppioni', () async {
      await scrivi('a.bin', 'x' * 1000);
      await scrivi('b.bin', 'y' * 1000);
      expect((await setaccio().doppioni())['gruppi'], isEmpty);
    });

    test('le briciole non si mostrano', () async {
      // Due copie di un'icona non sono un problema di nessuno, e sarebbero
      // migliaia di righe davanti alle poche che contano.
      await scrivi('uno.txt', 'ciao');
      await scrivi('due.txt', 'ciao');
      final r = await Setaccio(casa: casa.path).doppioni(); // soglia vera
      expect(r['gruppi'], isEmpty);
    });
  });

  group('quale copia si propone di tenere', () {
    test('mai quella in una cartella di passaggio', () async {
      // Il difetto visto sul disco vero: proponeva di buttare le due copie
      // messe da qualche parte e di tenere quella in Scaricati, che è il
      // posto da cui la roba dovrebbe USCIRE.
      // Stessa profondità e «Scaricati» viene prima in ordine alfabetico:
      // così è la regola del passaggio a decidere, e non un'altra. La prima
      // versione di questa prova metteva la copia buona più in alto
      // nell'albero, e passava anche togliendo la regola.
      final testo = 'x' * 2000;
      await scrivi('Scaricati/video.mp4', testo);
      await scrivi('Video/video.mp4', testo);
      final g = ((await setaccio().doppioni())['gruppi'] as List).first
          as Map<String, dynamic>;
      expect(g['tieni'], '${casa.path}/Video/video.mp4');
      expect('${g['perche']}', contains('passaggio'));
    });

    test('a parità, la meno profonda', () async {
      final testo = 'x' * 2000;
      await scrivi('Immagini/mare.jpg', testo);
      await scrivi('Immagini/2026/estate/mare.jpg', testo);
      final g = ((await setaccio().doppioni())['gruppi'] as List).first
          as Map<String, dynamic>;
      expect(g['tieni'], '${casa.path}/Immagini/mare.jpg');
    });

    test('e il primo dell\'elenco È quello che si tiene', () async {
      // Prima l'elenco restava nell'ordine del motore e la proposta stava in
      // un campo a parte: chi leggeva «il primo si tiene, gli altri via» si
      // ritrovava lo stesso file in tutte e due le colonne.
      final testo = 'x' * 2000;
      await scrivi('Scaricati/a.bin', testo);
      await scrivi('Documenti/a.bin', testo);
      final g = ((await setaccio().doppioni())['gruppi'] as List).first
          as Map<String, dynamic>;
      expect((g['percorsi'] as List).first, g['tieni']);
      expect((g['percorsi'] as List).skip(1), isNot(contains(g['tieni'])));
    });
  });

  group('il codice non si guarda', () {
    test('Progetti, node_modules, .git e le cartelle nascoste restano fuori',
        () async {
      // Dentro un progetto i doppioni sono NORMALI: node_modules ripete le
      // stesse librerie, una compilazione ripete i suoi prodotti, `.git`
      // tiene apposta più copie. Mostrarli vorrebbe dire annegare le tre
      // copie del telefono in decine di migliaia di righe da non toccare.
      final testo = 'x' * 2000;
      for (final d in ['Progetti', 'roba/node_modules', 'roba/.git',
                       '.cache', 'roba/build']) {
        await scrivi('$d/copia.bin', testo);
      }
      await scrivi('Documenti/copia.bin', testo);
      expect((await setaccio().doppioni())['gruppi'], isEmpty,
          reason: 'una copia sola fuori dal codice non è un doppione');
    });
  });

  group('non si resta mai senza', () {
    test('chiedendo di buttarle TUTTE, una resta in piedi', () async {
      // È la prova che un programma di doppioni deve avere e che quasi
      // nessuno scrive.
      final testo = 'x' * 2000;
      final a = await scrivi('Documenti/a.bin', testo);
      final b = await scrivi('Scaricati/a.bin', testo);
      final r = await setaccio().daButtare([a.path, b.path]);
      final via = (r['via'] as List).cast<String>();
      final rifiutati =
          (r['rifiutati'] as List).cast<Map<String, dynamic>>();
      expect(via.length, 1);
      expect(rifiutati.length, 1);
      expect('${rifiutati.single['perche']}', contains('ultima copia'));
      expect(via.single, b.path, reason: 'si salva quella proposta');
    });

    test('un file che non ha più un gemello si rifiuta', () async {
      // Basta aprire due volte la finestra: un elenco vecchio chiede di
      // buttare un file che nel frattempo è rimasto solo.
      final solo = await scrivi('Documenti/solo.bin', 'x' * 2000);
      final r = await setaccio().daButtare([solo.path]);
      expect(r['via'], isEmpty);
      expect('${(r['rifiutati'] as List).single['perche']}',
          contains('non è un doppione'));
    });

    test('senza scelta non si fa niente e lo si dice', () async {
      final r = await setaccio().daButtare([]);
      expect(r['ok'], isFalse);
    });
  });

  group('il confronto vero: byte per byte', () {
    test('se uno dei due è cambiato dopo la scansione, non si butta',
        () async {
      // È il caso più probabile di tutti, e con le sole impronte non si
      // vedrebbe: l'elenco che hai sotto gli occhi è di mezz'ora fa, e nel
      // frattempo ci hai scritto dentro.
      //
      // Qui si simula al contrario — si cambia il file DOPO che il setaccio
      // ha deciso — ed è la stessa cosa: quello che conta è che il confronto
      // avvenga al momento di toccare, non al momento di guardare.
      final testo = 'x' * 2000;
      final a = await scrivi('Documenti/a.bin', testo);
      final b = await scrivi('Scaricati/a.bin', testo);
      final s = setaccio();
      // Il setaccio li vede uguali...
      expect((await s.doppioni())['gruppi'], hasLength(1));
      // ...poi uno cambia, restando della stessa lunghezza.
      await b.writeAsString('y' * 2000);
      final r = await s.daButtare([b.path]);
      expect(r['via'], isEmpty);
      // Il rifiuto arriva prima ancora del confronto: rifacendo il giro non
      // sono più gemelli, e un file senza gemello non è un doppione. Va bene
      // così — quello che conta è che NON si tocchi. Il confronto byte per
      // byte è provato da solo qui sotto, perché una garanzia che si può
      // provare solo di riflesso non è una garanzia.
      expect('${(r['rifiutati'] as List).single['perche']}', isNotEmpty);
      expect(await a.exists(), isTrue);
      expect(await b.exists(), isTrue);
    });


    test('due file della stessa lunghezza ma diversi non sono identici',
        () async {
      final a = await scrivi('Documenti/a.bin', 'x' * 5000);
      final b = await scrivi('Documenti/b.bin', 'x' * 4999 + 'y');
      expect(await setaccio().identici(a.path, b.path), isFalse,
          reason: 'cambia UN byte in fondo: l\'assaggio delle estremità lo '
              'prende, ma il confronto deve prenderlo comunque');
      expect(await setaccio().identici(a.path, a.path), isTrue);
    });

    test('e se uno non si legge, il dubbio vale come un no', () async {
      final a = await scrivi('Documenti/a.bin', 'x' * 100);
      expect(await setaccio().identici(a.path, '${casa.path}/non-esiste.bin'),
          isFalse);
    });

    test('e se sono davvero identici, si butta', () async {
      // La controprova: senza, la prova qui sopra sarebbe verde anche con un
      // confronto che dice sempre di no.
      final testo = 'x' * 2000;
      await scrivi('Documenti/a.bin', testo);
      final b = await scrivi('Scaricati/a.bin', testo);
      final r = await setaccio().daButtare([b.path]);
      expect(r['via'], [b.path]);
      expect(r['rifiutati'], isEmpty);
    });
  });

  group('la cartella di riferimento', () {
    // ── Perché esiste ────────────────────────────────────────────────────
    //
    // Giacomo: «metti caso che metto un nuovo backup nel PC e quelli che già
    // avevo sono sparpagliati: seleziono la cartella come riferimento e tutto
    // il resto viene considerato doppione».
    //
    // Il demone non applica la scelta — quella è della finestra — ma prepara
    // la domanda: per ogni cartella dove vive almeno una copia dice **quanto
    // libererebbe** se fosse lei la buona. Senza quel numero la scelta
    // sarebbe alla cieca: due cartelle plausibili possono valere tre giga e
    // trecento mega.
    test('dice quanto libererebbe ognuna, e la migliore è la prima', () async {
      // Il caso vero: un backup nuovo (Backup/DCIM) e due copie sparse.
      final testo = 'x' * 3000;
      await scrivi('Backup/DCIM/uno.mp4', testo);
      await scrivi('Scaricati/uno.mp4', testo);
      await scrivi('Documenti/vecchi/uno.mp4', testo);

      final altro = 'y' * 3000;
      await scrivi('Backup/DCIM/due.mp4', altro);
      await scrivi('Scaricati/due.mp4', altro);

      // Un terzo gruppo che `Scaricati` NON tocca: senza questo, le due
      // cartelle liberano esattamente lo stesso e il confronto sotto non
      // proverebbe niente. (La prima versione di questa prova lo faceva, ed
      // è caduta.)
      final terzo = 'z' * 4000;
      await scrivi('Backup/DCIM/tre.mp4', terzo);
      await scrivi('Documenti/vecchi/tre.mp4', terzo);

      final c = ((await setaccio().doppioni())['cartelle'] as List)
          .cast<Map<String, dynamic>>();
      expect(c, isNotEmpty);
      // `Backup` è in tutti e due i gruppi e ha fuori tre copie in tutto.
      expect(c.first['percorso'], '${casa.path}/Backup');
      expect(c.first['gruppi'], 3);
      expect(c.first['liberabili'], 3000 * 3 + 4000);

      // E `Scaricati`, che è in tutti e due ma con una copia fuori per
      // gruppo, vale meno.
      final scaricati =
          c.firstWhere((x) => x['percorso'] == '${casa.path}/Scaricati');
      expect(scaricati['liberabili'], lessThan(c.first['liberabili'] as int));
    });

    test('una cartella che non contiene doppioni non si propone', () async {
      // Proporre una cartella che non libera niente vorrebbe dire allungare
      // l'elenco proprio con le risposte inutili.
      final testo = 'x' * 3000;
      await scrivi('Backup/uno.bin', testo);
      await scrivi('Scaricati/uno.bin', testo);
      await scrivi('Musica/solo.mp3', 'z' * 3000);

      final c = ((await setaccio().doppioni())['cartelle'] as List)
          .cast<Map<String, dynamic>>();
      expect(c.map((x) => x['percorso']),
          isNot(contains('${casa.path}/Musica')));
    });
  });

  group('le cartelle escluse', () {
    test('quello che è dentro non si guarda', () async {
      // `~/Android` sono 3,1 GB e 45.403 file, `~/flutter` 1,6 GB e 17.427:
      // dentro una SDK i doppioni sono normali quanto dentro node_modules, e
      // non si toccano mai.
      final testo = 'x' * 2000;
      await scrivi('roba/Sdk/uno.jar', testo);
      await scrivi('roba/Sdk/copia/uno.jar', testo);
      expect(((await setaccio().doppioni())['gruppi'] as List), hasLength(1));

      final senza = Setaccio(
          casa: casa.path, soglia: 10, escluse: ['${casa.path}/roba/Sdk']);
      expect((await senza.doppioni())['gruppi'], isEmpty);
    });

    test('e si esclude QUELLA cartella, non tutte quelle che si chiamano così',
        () async {
      // `Documenti/foto` e `Scaricati/foto` sono due cose diverse: un elenco
      // di NOMI le prenderebbe tutte e due, compresa quella da guardare.
      final testo = 'x' * 2000;
      await scrivi('Documenti/foto/uno.jpg', testo);
      await scrivi('Scaricati/foto/uno.jpg', testo);
      final s = Setaccio(
          casa: casa.path, soglia: 10, escluse: ['${casa.path}/Documenti/foto']);
      // Resta una copia sola: non è più un doppione, e infatti non compare.
      expect((await s.doppioni())['gruppi'], isEmpty);

      final tutte = Setaccio(casa: casa.path, soglia: 10);
      expect((await tutte.doppioni())['gruppi'], hasLength(1));
    });
  });

  group('le copie arrivate da WhatsApp', () {
    test('valgono meno, a parità di byte', () async {
      // Non per il peso — sono identiche — ma per il NOME:
      // `IMG-20250730-WA0013.jpg` dice il giorno in cui è ARRIVATA sul
      // telefono, `IMG_20260426_102932.jpg` dice lo scatto. Il giorno che si
      // riordina per data, è l'unica cosa su cui contare.
      final testo = 'x' * 2000;
      await scrivi('Immagini/IMG-20250730-WA0013.jpg', testo);
      await scrivi('Immagini/IMG_20260426_102932.jpg', testo);
      final g = ((await setaccio().doppioni())['gruppi'] as List).first
          as Map<String, dynamic>;
      expect(g['tieni'], '${casa.path}/Immagini/IMG_20260426_102932.jpg');
    });

    test('e vale anche la cartella, non solo il nome', () async {
      // La copia WhatsApp è la MENO profonda e viene prima in ordine
      // alfabetico: così è la regola nuova a decidere, e non un'altra. (La
      // prima versione la metteva più in fondo all'albero, e passava anche
      // togliendo la regola.)
      final testo = 'y' * 2000;
      await scrivi('Documenti/WhatsApp Images/foto.jpg', testo);
      await scrivi('Immagini/2026/foto.jpg', testo);
      final g = ((await setaccio().doppioni())['gruppi'] as List).first
          as Map<String, dynamic>;
      expect(g['tieni'], '${casa.path}/Immagini/2026/foto.jpg');
    });

    test('fra due copie WhatsApp vincono le altre regole', () async {
      // La regola nuova non deve spazzare via quelle di prima: se vengono
      // tutte e due da WhatsApp, decide il posto (fuori dalle cartelle di
      // passaggio).
      final testo = 'z' * 2000;
      await scrivi('Scaricati/IMG-20250730-WA0013.jpg', testo);
      await scrivi('Immagini/IMG-20250730-WA0013.jpg', testo);
      final g = ((await setaccio().doppioni())['gruppi'] as List).first
          as Map<String, dynamic>;
      expect(g['tieni'], '${casa.path}/Immagini/IMG-20250730-WA0013.jpg');
    });
  });
}
