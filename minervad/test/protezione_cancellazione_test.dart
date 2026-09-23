import 'dart:io';

import 'package:minervad/services/file_service.dart';
import 'package:test/test.dart';

/// Prove su che cosa succede quando un file **non si lascia toccare**.
///
/// ── Da dove nasce questo file ──────────────────────────────────────────────
///
/// Giacomo, 18 agosto 2026: «se clicco su sistema posso cancellare qualsiasi
/// file di sistema come se fossero nella mia home, non c'è nessuna protezione
/// dalla cancellazione».
///
/// Cancellarli non si poteva davvero — per togliere un file serve poter
/// scrivere nella cartella che lo contiene, e le cartelle di sistema sono di
/// root — ma sotto c'era un difetto peggiore di quello temuto, e silenzioso.
///
/// `trash()` provava un `rename`, e sul fallimento — **qualunque** fallimento —
/// diceva a sé stesso «filesystem diverso» e passava a copiare e cancellare.
/// Su un file protetto la copia riusciva e la cancellazione no: nel cestino
/// restava una COPIA, senza `.trashinfo`, quindi senza modo di rimetterla a
/// posto e senza che si vedesse che era un avanzo. Su una cartella di sistema
/// sarebbero stati gigabyte copiati nella home per un'operazione che non
/// poteva riuscire in nessun caso.
///
/// Lo stesso schema stava in altri due punti: il ripristino dal cestino e lo
/// spostamento vero e proprio, dove un «sposta» che non riesce a togliere
/// l'originale lasciava il file in due posti chiamandolo spostato.
///
/// ── Come si prova ─────────────────────────────────────────────────────────
///
/// Una cartella `r-x` dentro una temporanea: per chi ci sta dentro si comporta
/// **esattamente** come `/usr` o `/etc`. Non serve essere root né toccare
/// niente di vero.
void main() {
  late Directory temp;
  late Directory protetta;
  late Directory cestino;
  late FileService fs;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('minerva-protezione-');
    cestino = Directory('${temp.path}/Trash');
    protetta = Directory('${temp.path}/sistema');
    await protetta.create(recursive: true);
    await File('${protetta.path}/importante.conf')
        .writeAsString('non toccare\n');
    await Directory('${protetta.path}/sottocartella').create();
    await File('${protetta.path}/sottocartella/dentro.txt').writeAsString('x');

    fs = FileService(cestinoDiProva: cestino.path);
  });

  /// Si toglie il lucchetto prima di cancellare, o la cartella temporanea
  /// resta lì per sempre a ogni esecuzione delle prove.
  tearDown(() async {
    await Process.run('chmod', ['-R', 'u+w', temp.path]);
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<void> chiudi() async {
    await Process.run('chmod', ['555', protetta.path]);
  }

  int nelCestino() {
    final d = Directory('${cestino.path}/files');
    return d.existsSync() ? d.listSync().length : 0;
  }

  group('una cartella che non è tua', () {
    test('cestinare un file protetto non lascia una copia nel cestino',
        () async {
      // È IL DIFETTO. Prima qui restava `importante.conf` nel cestino, mentre
      // l'originale era ancora al suo posto: un duplicato invisibile.
      await chiudi();
      final r = await fs.trash(['${protetta.path}/importante.conf']);

      expect(r['ok'], isFalse, reason: 'non poteva riuscire, e deve dirlo');
      expect(nelCestino(), 0, reason: 'nel cestino non deve restare niente');
      expect(File('${protetta.path}/importante.conf').existsSync(), isTrue,
          reason: 'e l\'originale deve essere ancora al suo posto');
    });

    test('non resta nemmeno una scheda .trashinfo orfana', () async {
      await chiudi();
      await fs.trash(['${protetta.path}/importante.conf']);
      final info = Directory('${cestino.path}/info');
      expect(info.existsSync() ? info.listSync().length : 0, 0);
    });

    test('il motivo si legge, e non è un\'eccezione di Dart', () async {
      await chiudi();
      final r = await fs.trash(['${protetta.path}/importante.conf']);
      final testo = r['error'] as String;
      // Prima compariva in finestra: «PathAccessException: Cannot delete
      // file, path = '/…' (OS Error: Permission denied, errno = 13)».
      expect(testo, isNot(contains('Exception')));
      expect(testo, isNot(contains('errno')));
      expect(testo, contains('importante.conf'));
      expect(testo.toLowerCase(), contains('non è tua'));
    });

    test('una cartella protetta non si cancella e non si svuota a metà',
        () async {
      await chiudi();
      final r = await fs
          .eliminaDefinitivamente(['${protetta.path}/sottocartella']);
      expect(r['ok'], isFalse);
      expect(Directory('${protetta.path}/sottocartella').existsSync(), isTrue);
      expect(File('${protetta.path}/sottocartella/dentro.txt').existsSync(),
          isTrue);
      expect(r['error'], isNot(contains('errno')));
    });

    test('un file protetto non ferma gli altri', () async {
      // Dieci file scelti e uno solo bloccato: gli altri nove devono andare
      // nel cestino lo stesso. Prima il primo intoppo interrompeva tutto e non
      // lo diceva.
      final liberi = <String>[];
      for (var i = 0; i < 3; i++) {
        final f = File('${temp.path}/libero$i.txt');
        await f.writeAsString('$i');
        liberi.add(f.path);
      }
      await chiudi();

      final r = await fs.trash([
        liberi[0],
        '${protetta.path}/importante.conf',
        liberi[1],
        liberi[2],
      ]);

      expect(r['ok'], isFalse);
      expect(r['cestinati'], 3);
      expect(nelCestino(), 3);
      for (final l in liberi) {
        expect(File(l).existsSync(), isFalse);
      }
    });
  });

  group('quello che invece deve continuare a funzionare', () {
    test('un file tuo si cestina, e la sua scheda viene scritta', () async {
      final f = File('${temp.path}/mio.txt');
      await f.writeAsString('ciao');
      final r = await fs.trash([f.path]);

      expect(r['ok'], isTrue);
      expect(r['cestinati'], 1);
      expect(f.existsSync(), isFalse);
      expect(File('${cestino.path}/files/mio.txt').existsSync(), isTrue);
      expect(File('${cestino.path}/info/mio.txt.trashinfo').existsSync(),
          isTrue);
    });

    test('e si rimette a posto da dove veniva', () async {
      final f = File('${temp.path}/mio.txt');
      await f.writeAsString('ciao');
      await fs.trash([f.path]);
      final r =
          await fs.restoreFromTrash(['${cestino.path}/files/mio.txt']);

      expect(r['ok'], isTrue);
      expect(f.existsSync(), isTrue);
      expect(await f.readAsString(), 'ciao');
      expect(nelCestino(), 0);
    });
  });

  group('la cartella dice se si può cambiare', () {
    test('una cartella tua sì', () async {
      final r = await fs.list(temp.path);
      expect(r['scrivibile'], isTrue);
    });

    test('una cartella «di sistema» no', () async {
      // È il campo su cui l'interfaccia spegne «Nuova cartella», «Rinomina» e
      // «Sposta nel cestino»: senza, quei comandi si offrivano identici a
      // quelli di casa e il rifiuto arrivava solo dopo il clic.
      await chiudi();
      final r = await fs.list(protetta.path);
      expect(r['error'], '', reason: 'si legge benissimo: è scriverci che non si può');
      expect((r['entries'] as List).length, 2);
      expect(r['scrivibile'], isFalse);
    });

    test('e una che non si può nemmeno attraversare', () async {
      // `-w` da solo non basta: senza `x` non si arriva alle voci, quindi non
      // si toglie niente lo stesso.
      final cieca = Directory('${temp.path}/cieca');
      await cieca.create();
      await Process.run('chmod', ['666', cieca.path]);
      final r = await fs.list(cieca.path);
      expect(r['scrivibile'], isFalse);
    });
  });
}
