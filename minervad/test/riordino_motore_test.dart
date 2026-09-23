import 'dart:io';
import 'package:test/test.dart';
import 'package:minervad/services/foto/riordino.dart';
import 'package:minervad/services/foto/riordino_motore.dart';

// Le prove dell'esecutore del riordino.
//
// ── Qui si toccano file veri, ed è il punto ──────────────────────────────
//
// `riordino_test.dart` prova il PIANO, che è conto puro. Questo prova la parte
// che **sposta**, e una prova che finge lo spostamento prova il finto. I file
// qui sotto si scrivono davvero, in una cartella temporanea che sparisce alla
// fine.
//
// È la stessa forma della prova che Giacomo ha proposto il 26 agosto 2026 per
// la libreria vera: si riordina una COPIA, si confronta che nessun file sia
// sparito e che i conteggi tornino, e si verifica che gli originali siano
// intatti. Qui è in piccolo, e gira a ogni `prove.sh`.
//
// ── Metà di queste prove sono RIFIUTI ────────────────────────────────────
//
// Perché questo è il codice che può perdere una fotografia, e le cose che
// **non** deve fare contano più di quelle che fa.
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('minerva-riordino-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File scrivi(String nome, String testo) {
    final f = File('${tmp.path}/$nome')..createSync(recursive: true);
    f.writeAsStringSync(testo);
    return f;
  }

  group('copiare', () {
    test('la fotografia arriva a destinazione e l\'originale resta', () async {
      final a = scrivi('sorgente/uno.jpg', 'AAA');
      final dove = '${tmp.path}/ordinate/2026/03 marzo/uno.jpg';
      final r = await const RiordinoMotore(modo: 'copia')
          .esegui([Passo(da: a.path, a: dove)]);

      expect(r['ok'], isTrue);
      expect(r['fatti'], 1);
      expect(File(dove).existsSync(), isTrue);
      expect(File(dove).readAsStringSync(), 'AAA');
      expect(a.existsSync(), isTrue,
          reason: 'in modo «copia» gli originali NON si toccano');
    });

    test('le cartelle nascono da sole, tutte insieme', () async {
      final a = scrivi('x.jpg', 'X');
      final dove = '${tmp.path}/o/2026/03 marzo/07/x.jpg';
      final r = await const RiordinoMotore()
          .esegui([Passo(da: a.path, a: dove)]);
      expect(r['ok'], isTrue);
      expect(File(dove).existsSync(), isTrue);
    });

    test('niente si perde: quanti erano, tanti sono', () async {
      // La prova che Giacomo ha proposto, in piccolo: si conta prima e dopo.
      final quali = ['a.jpg', 'b.jpg', 'c.jpg', 'd.jpg'];
      final passi = <Passo>[];
      for (final q in quali) {
        final f = scrivi('sorgente/$q', q);
        passi.add(Passo(da: f.path, a: '${tmp.path}/ordinate/2026/$q'));
      }
      final r = await const RiordinoMotore().esegui(passi);

      expect(r['ok'], isTrue);
      expect(r['fatti'], quali.length);
      // Tutti arrivati, col contenuto giusto…
      for (final q in quali) {
        expect(File('${tmp.path}/ordinate/2026/$q').readAsStringSync(), q);
      }
      // …e tutti gli originali ancora lì.
      expect(Directory('${tmp.path}/sorgente').listSync().length, quali.length);
    });
  });

  group('spostare', () {
    test('la fotografia si sposta e non resta dov\'era', () async {
      final a = scrivi('sorgente/uno.jpg', 'AAA');
      final dove = '${tmp.path}/ordinate/uno.jpg';
      final r = await RiordinoMotore(
        modo: 'sposta',
        puntoDiRitorno: () async => true,
      ).esegui([Passo(da: a.path, a: dove)]);

      expect(r['ok'], isTrue);
      expect(File(dove).readAsStringSync(), 'AAA');
      expect(a.existsSync(), isFalse);
    });
  });

  group('i rifiuti — quello che NON deve succedere', () {
    test('senza punto di ritorno non si sposta niente', () async {
      // La regola della casa, scritta come rifiuto e non come consiglio.
      final a = scrivi('uno.jpg', 'AAA');
      final r = await const RiordinoMotore(modo: 'sposta')
          .esegui([Passo(da: a.path, a: '${tmp.path}/o/uno.jpg')]);

      expect(r['ok'], isFalse);
      expect(r['error'], contains('punto di ritorno'));
      expect(a.existsSync(), isTrue, reason: 'non deve aver toccato niente');
      expect(Directory('${tmp.path}/o').existsSync(), isFalse);
    });

    test('e nemmeno se il punto di ritorno fallisce', () async {
      final a = scrivi('uno.jpg', 'AAA');
      final r = await RiordinoMotore(
        modo: 'sposta',
        puntoDiRitorno: () async => false,
      ).esegui([Passo(da: a.path, a: '${tmp.path}/o/uno.jpg')]);

      expect(r['ok'], isFalse);
      expect(a.existsSync(), isTrue);
    });

    test('due fotografie nello stesso posto: non si fa NIENTE', () async {
      // Non «se ne fa una e si salta l'altra»: niente. Un piano che si
      // contraddice va guardato, non eseguito a metà.
      final a = scrivi('a.jpg', 'A');
      final b = scrivi('b.jpg', 'B');
      final stesso = '${tmp.path}/o/uguale.jpg';
      final r = await const RiordinoMotore()
          .esegui([Passo(da: a.path, a: stesso), Passo(da: b.path, a: stesso)]);

      expect(r['ok'], isFalse);
      expect(r['error'], contains('stesso posto'));
      expect(File(stesso).existsSync(), isFalse,
          reason: 'non deve aver copiato nemmeno la prima');
    });

    test('non si sovrascrive un file che c\'era già', () async {
      // Il piano non sa cosa c'è nella cartella di destinazione da ieri.
      final a = scrivi('nuova.jpg', 'NUOVA');
      final vecchia = scrivi('o/uno.jpg', 'VECCHIA');
      final r = await const RiordinoMotore()
          .esegui([Passo(da: a.path, a: vecchia.path)]);

      expect(r['ok'], isFalse);
      expect(vecchia.readAsStringSync(), 'VECCHIA',
          reason: 'il file di ieri deve essere ancora lì, intatto');
    });

    test('un piano tutto rifiutato non è un piano', () async {
      final r = await const RiordinoMotore().esegui([
        const Passo(da: '/a/x.jpg', a: '', rifiuto: 'non so quando'),
      ]);
      expect(r['ok'], isFalse);
      expect(r['error'], contains('rifiutate'));
    });

    test('un modo che non esiste non fa niente', () async {
      final a = scrivi('uno.jpg', 'A');
      final r = await const RiordinoMotore(modo: 'cancella')
          .esegui([Passo(da: a.path, a: '${tmp.path}/o/uno.jpg')]);
      expect(r['ok'], isFalse);
      expect(a.existsSync(), isTrue);
    });

    test('un file sparito lo dice, e gli altri passano lo stesso', () async {
      final buona = scrivi('buona.jpg', 'B');
      final r = await const RiordinoMotore().esegui([
        Passo(da: '${tmp.path}/non-esisto.jpg', a: '${tmp.path}/o/x.jpg'),
        Passo(da: buona.path, a: '${tmp.path}/o/buona.jpg'),
      ]);
      expect(r['ok'], isFalse, reason: 'uno è fallito, e va detto');
      expect(r['fatti'], 1);
      expect(r['falliti'], 1);
      expect(File('${tmp.path}/o/buona.jpg').existsSync(), isTrue,
          reason: 'il fallimento di uno non deve costare gli altri');
    });
  });
}
