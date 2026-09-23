import 'package:test/test.dart';
import 'package:minervad/services/foto/riordino.dart';

// Le prove del riordino.
//
// ── Qui non si sposta niente, e non per pigrizia ─────────────────────────
//
// `Riordino` fa il PIANO: dice dove finirebbe ogni file, e quali non tocca.
// Non legge il disco e non ne ha bisogno — quindi si prova con dei numeri, in
// un decimo di secondo, e si può provare **tutto**, compresi i casi che su
// una libreria vera capitano una volta l'anno.
//
// Lo spostamento vero è un'altra cosa e avrà le sue prove: si riordina una
// COPIA in una cartella temporanea, si confronta che nessun file sia sparito,
// e si verifica che gli originali siano intatti. È l'idea di Giacomo del 26
// agosto, e la ragione per cui questa parte sarà provabile invece che
// sperabile.
//
// ── Le prove che contano di più sono i RIFIUTI ───────────────────────────
//
// Una fotografia messa nel mese sbagliato è peggio di una lasciata dov'era:
// nella seconda si sa ancora dove cercarla.

DaRiordinare _f(String p, DateTime? d,
        {String fiducia = 'certa', bool contesa = false}) =>
    DaRiordinare(
        percorso: p, data: d, fiducia: fiducia, daControllare: contesa);

void main() {
  const dove = '/home/tizio/Immagini/Riordinate';

  group('dove finisce un file', () {
    test('anno e mese, col mese scritto in italiano', () {
      final r = Riordino(destinazione: dove);
      final p = r.piano([_f('/a/IMG_1.jpg', DateTime(2026, 3, 17, 11, 27))]);
      expect(p.single.a, '$dove/2026/03 marzo/IMG_1.jpg');
    });

    test('il numero del mese davanti al nome, o si ordinano male', () {
      // Senza il numero, una cartella ordinata alfabeticamente mette aprile
      // prima di gennaio. Il numero c'è per il computer, il nome per te.
      final r = Riordino(destinazione: dove);
      final mesi = [
        for (var m = 1; m <= 12; m++)
          r.piano([_f('/a/x$m.jpg', DateTime(2026, m, 1))]).single.a
      ];
      final ordinate = [...mesi]..sort();
      expect(mesi, ordinate, reason: 'in ordine alfabetico devono restare in '
          'ordine di calendario');
    });

    test('solo l\'anno, quando si vuole così', () {
      final r = Riordino(destinazione: dove, struttura: 'anno');
      expect(r.piano([_f('/a/x.jpg', DateTime(2019, 8, 3))]).single.a,
          '$dove/2019/x.jpg');
    });

    test('fino al giorno', () {
      final r = Riordino(destinazione: dove, struttura: 'anno-mese-giorno');
      expect(r.piano([_f('/a/x.jpg', DateTime(2026, 3, 7))]).single.a,
          '$dove/2026/03 marzo/07/x.jpg');
    });

    test('e separati per tipo, se si chiede', () {
      final r = Riordino(destinazione: dove, perTipo: true);
      final p = r.piano([
        _f('/a/foto.jpg', DateTime(2026, 3, 1)),
        _f('/a/clip.mp4', DateTime(2026, 3, 1)),
        _f('/a/shot.png', DateTime(2026, 3, 1)),
      ], tipi: {
        '/a/clip.mp4': 'video',
        '/a/shot.png': 'schermata',
      });
      expect(p[0].a, contains('/Foto/'));
      expect(p[1].a, contains('/Video/'));
      expect(p[2].a, contains('/Schermate/'));
    });
  });

  group('il nome', () {
    test('di serie NON si rinomina', () {
      // Il nome che un file ha addosso è, per alcuni, l'unica prova della data
      // che abbiamo. Cambiarlo deve essere una scelta esplicita.
      final r = Riordino(destinazione: dove);
      expect(r.piano([_f('/a/Snapchat-760231133.jpg', DateTime(2026, 3, 17))])
          .single.a, endsWith('/Snapchat-760231133.jpg'));
    });

    test('chiedendolo, diventa la data — e senza i due punti', () {
      // I due punti su alcuni dischi non si scrivono: un nome che funziona sul
      // portatile e non sulla chiavetta è un nome sbagliato.
      final r = Riordino(destinazione: dove, rinomina: true);
      final a = r.piano([_f('/a/x.jpg', DateTime(2026, 3, 17, 11, 27, 27))])
          .single.a;
      expect(a, endsWith('/2026-03-17 11.27.27.jpg'));
      expect(a.split('/').last, isNot(contains(':')));
    });

    test('due scatti nello stesso secondo non si sovrascrivono', () {
      // Una raffica ne fa dieci. Senza il «-2», il secondo cancellerebbe il
      // primo — e sarebbe una fotografia persa nel silenzio.
      final r = Riordino(destinazione: dove, rinomina: true);
      final quando = DateTime(2026, 3, 17, 11, 27, 27);
      final p = r.piano([
        _f('/a/uno.jpg', quando),
        _f('/a/due.jpg', quando),
        _f('/a/tre.jpg', quando),
      ]);
      expect(p.map((x) => x.a).toSet().length, 3,
          reason: 'tre file, tre destinazioni diverse');
      expect(p[1].a, endsWith('-2.jpg'));
      expect(p[2].a, endsWith('-3.jpg'));
    });

    test('e nemmeno senza rinomina, se due si chiamano uguale', () {
      // `Video/IMG_123.jpg` e `Immagini/IMG_123.jpg` finirebbero nello stesso
      // posto: è esattamente il caso della libreria di Giacomo.
      final r = Riordino(destinazione: dove);
      final quando = DateTime(2026, 7, 4, 15, 38);
      final p = r.piano([
        _f('/home/g/Video/IMG_20260704_153845.jpg', quando),
        _f('/home/g/Immagini/IMG_20260704_153845.jpg', quando),
      ]);
      expect(p[0].a, isNot(p[1].a));
    });
  });

  group('i rifiuti — le fotografie che NON si toccano', () {
    test('senza data non si sposta', () {
      final r = Riordino(destinazione: dove);
      final p = r.piano([_f('/a/x.jpg', null)]).single;
      expect(p.siFa, isFalse);
      expect(p.a, isEmpty, reason: 'non deve nemmeno avere una destinazione');
      expect(p.rifiuto, contains('non so quando'));
    });

    test('su una data CONTESA non si tocca niente', () {
      // «Contesa» vuol dire che l'EXIF e il nome dicono cose diverse di più di
      // un giorno. Rinominare lì sopra cancella l'unica altra prova che
      // avevamo — il nome — e la cancella per sempre.
      final r = Riordino(destinazione: dove, rinomina: true);
      final p = r.piano([
        _f('/a/x.jpg', DateTime(2026, 3, 17), contesa: true)
      ]).single;
      expect(p.siFa, isFalse);
      expect(p.rifiuto, contains('non vanno d\'accordo'));
    });

    test('e nemmeno con la sola data del file', () {
      // È il caso delle 826 fotografie di Giacomo: hanno TUTTE lo stesso
      // mtime — l'istante della copia dal telefono. Riordinare su quella vuol
      // dire un giorno solo con dentro tutto.
      final r = Riordino(destinazione: dove);
      final p = r.piano([
        _f('/a/x.jpg', DateTime(2026, 7, 8, 21, 29), fiducia: 'ultima-spiaggia')
      ]).single;
      expect(p.siFa, isFalse);
    });

    test('i rifiuti restano nell\'elenco, non spariscono', () {
      // Un elenco che mostra solo quello che si farà nasconde proprio le cose
      // su cui serve una decisione.
      final r = Riordino(destinazione: dove);
      final p = r.piano([
        _f('/a/buona.jpg', DateTime(2026, 3, 1)),
        _f('/a/senza.jpg', null),
        _f('/a/contesa.jpg', DateTime(2026, 3, 1), contesa: true),
      ]);
      expect(p.length, 3);
      expect(p.where((x) => x.siFa).length, 1);
    });

    test('il conto si può dire a parole prima di toccare un byte', () {
      final r = Riordino(destinazione: dove);
      final c = Riordino.conto(r.piano([
        _f('/a/1.jpg', DateTime(2026, 3, 1)),
        _f('/a/2.jpg', DateTime(2026, 3, 1)),
        _f('/a/3.jpg', null),
      ]));
      expect(c['quanti'], 3);
      expect(c['siFanno'], 2);
      expect(c['rifiutati'], 1);
      expect((c['perche'] as Map).values.first, 1);
    });

    test('una fiducia bassa ma NON ultima spiaggia si sposta', () {
      // «probabile» è la data letta dal nome del file, ed è una data vera:
      // rifiutarla vorrebbe dire non riordinare quasi niente.
      final r = Riordino(destinazione: dove);
      final p = r.piano([
        _f('/a/IMG_20260317_112727.jpg', DateTime(2026, 3, 17),
            fiducia: 'probabile')
      ]).single;
      expect(p.siFa, isTrue);
    });
  });
}
