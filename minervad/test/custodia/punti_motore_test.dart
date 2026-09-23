import 'dart:io';

import 'package:minervad/services/custodia/punti_motore.dart';
import 'package:test/test.dart';

/// Prove sui punti di ritorno.
///
/// Sono la rete di tutto il resto della Custodia: se un punto di ritorno mente,
/// mente nel momento in cui qualcuno ci si è appeso. Quindi qui non si legge il
/// codice e non si controlla che una funzione sia stata chiamata — **si rompe
/// per davvero una cartella e si guarda se torna**.
void main() {
  late Directory temp;
  late PuntiMotore motore;
  late String progetto;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('minerva-punti-');
    progetto = '${temp.path}/Progetto Mio';
    await Directory('$progetto/dentro').create(recursive: true);
    await File('$progetto/uno.txt').writeAsString('primo');
    await File('$progetto/dentro/due.txt').writeAsString('secondo');
    // Un file che git non guarderebbe mai: è la ragione per cui i punti di
    // ritorno esistono accanto ai salvataggi.
    await Directory('$progetto/build').create();
    await File('$progetto/build/roba.o').writeAsString('binario');
    motore = PuntiMotore(radice: '${temp.path}/punti');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  // ── I nomi ─────────────────────────────────────────────────────────────
  //
  // Una nota la scrive una persona e diventa un nome di cartella. È un
  // ingresso come tutti gli altri, e va trattato come tale.

  group('la nota diventa un nome di cartella, e quindi si ripulisce', () {
    test('una barra non manda la copia in un\'altra cartella', () {
      expect(PuntiMotore.nomePulito('prima/dopo'), 'prima-dopo');
      expect(PuntiMotore.nomePulito('../../etc/passwd'), 'etc-passwd');
    });

    test('un trattino iniziale non diventa un\'opzione di cp', () {
      expect(PuntiMotore.nomePulito('-rf tutto'), 'rf-tutto');
      expect(PuntiMotore.nomePulito('--reflink=never'), 'reflink-never');
    });

    test('un punto iniziale non nasconde la cartella', () {
      expect(PuntiMotore.nomePulito('.nascosto'), 'nascosto');
    });

    test('gli accenti restano: è italiano, non un identificatore', () {
      expect(PuntiMotore.nomePulito('perché è così'), 'perché-è-così');
    });

    test('gli a-capo e le tabulazioni non sopravvivono', () {
      expect(PuntiMotore.nomePulito('uno\ndue'), 'uno-due');
      expect(PuntiMotore.nomePulito('uno\tdue'), 'uno-due');
    });

    test('una nota lunghissima si accorcia', () {
      expect(PuntiMotore.nomePulito('a' * 200).length, 60);
    });

    test('vuota è lecito: un punto senza nota resta un punto', () {
      expect(PuntiMotore.nomePulito('   '), '');
      expect(PuntiMotore.idPunto(DateTime(2026, 8, 24, 17, 25), ''),
          '2026-08-24_1725');
    });

    test('l\'identificativo è data, ora e cosa stavi per fare', () {
      expect(
        PuntiMotore.idPunto(DateTime(2026, 8, 24, 17, 25), 'prima del salto'),
        '2026-08-24_1725_prima-del-salto',
      );
    });

    test('e si rilegge com\'era', () {
      final p = PuntiMotore.leggiId('2026-08-24_1725_prima-del-salto', '/x');
      expect(p, isNotNull);
      expect(p!.quando, DateTime(2026, 8, 24, 17, 25));
      expect(p.nota, 'prima del salto');
    });

    test('una cartella che non è nostra non si conta e non si tocca', () {
      // Nella cartella dei punti può finirci qualsiasi cosa.
      expect(PuntiMotore.leggiId('roba', '/x'), isNull);
      expect(PuntiMotore.leggiId('.git', '/x'), isNull);
      expect(PuntiMotore.leggiId('2026-08-24', '/x'), isNull);
    });
  });

  // ── Prendere e tornare ─────────────────────────────────────────────────

  group('prendere un punto', () {
    test('copia tutto, anche quello che git non guarderebbe', () async {
      final e = await motore.crea(progetto, progetto, nota: 'il primo');
      expect(e.riuscito, isTrue, reason: e.errore);

      final dove = e.punto!.percorso;
      expect(await File('$dove/uno.txt').readAsString(), 'primo');
      expect(await File('$dove/dentro/due.txt').readAsString(), 'secondo');
      expect(await File('$dove/build/roba.o').readAsString(), 'binario');
    });

    test('due punti nello stesso minuto non si sovrascrivono', () async {
      final q = DateTime(2026, 8, 24, 17, 25);
      final a = await motore.crea(progetto, progetto, nota: 'x', quando: q);
      final b = await motore.crea(progetto, progetto, nota: 'x', quando: q);
      expect(a.riuscito && b.riuscito, isTrue);
      expect(a.punto!.percorso, isNot(b.punto!.percorso));
    });

    test('si elencano dal più recente', () async {
      await motore.crea(progetto, progetto,
          nota: 'vecchio', quando: DateTime(2026, 8, 1, 10, 0));
      await motore.crea(progetto, progetto,
          nota: 'nuovo', quando: DateTime(2026, 8, 20, 10, 0));
      final l = await motore.elenca(progetto);
      expect(l.length, 2);
      expect(l.first.nota, 'nuovo');
    });
  });

  group('tornare indietro — si rompe davvero, e si guarda se torna', () {
    test('un file cancellato per sbaglio ritorna', () async {
      final e = await motore.crea(progetto, progetto, nota: 'prima');
      expect(e.riuscito, isTrue, reason: e.errore);

      // Il disastro.
      await Directory('$progetto/dentro').delete(recursive: true);
      await File('$progetto/uno.txt').writeAsString('ROVINATO');
      await File('$progetto/intruso.txt').writeAsString('non c\'era');

      final r = await motore.ripristina(progetto, e.punto!.id, progetto);
      expect(r.riuscito, isTrue, reason: r.errore);

      expect(await File('$progetto/uno.txt').readAsString(), 'primo');
      expect(await File('$progetto/dentro/due.txt').readAsString(), 'secondo');
      // Tornare indietro vuol dire tornare indietro: anche i file *aggiunti*
      // dopo il punto se ne vanno. È la differenza fra un ripristino e una
      // fusione, e va detta all'utente prima, non scoperta dopo.
      expect(await File('$progetto/intruso.txt').exists(), isFalse);
    });

    test('anche il tornare indietro si può annullare', () async {
      final e = await motore.crea(progetto, progetto,
          nota: 'prima', quando: DateTime(2026, 8, 1, 10, 0));
      await File('$progetto/uno.txt').writeAsString('la versione nuova');

      final r = await motore.ripristina(progetto, e.punto!.id, progetto,
          quando: DateTime(2026, 8, 20, 10, 0));
      expect(r.riuscito, isTrue, reason: r.errore);
      expect(await File('$progetto/uno.txt').readAsString(), 'primo');

      // Il punto preso automaticamente prima del salto: ci si torna, e si
      // riprende la versione che si era appena buttata via.
      expect(r.punto, isNotNull);
      final indietro =
          await motore.ripristina(progetto, r.punto!.id, progetto);
      expect(indietro.riuscito, isTrue, reason: indietro.errore);
      expect(await File('$progetto/uno.txt').readAsString(),
          'la versione nuova');
    });

    test('non resta niente sparso in giro', () async {
      final e = await motore.crea(progetto, progetto, nota: 'p');
      await motore.ripristina(progetto, e.punto!.id, progetto);
      expect(await Directory('$progetto.custodia-nuova').exists(), isFalse);
      expect(await Directory('$progetto.custodia-vecchia').exists(), isFalse);
    });
  });

  // ── I rifiuti, che sono le prove che contano ───────────────────────────

  group('i rifiuti', () {
    test('non si prende un punto di una cartella che non c\'è', () async {
      final e = await motore.crea(progetto, '${temp.path}/mai-esistita');
      expect(e.riuscito, isFalse);
      expect(e.errore, contains('non esiste'));
    });

    test('non si torna a un punto che non è un punto', () async {
      final r = await motore.ripristina(progetto, '../../etc', progetto);
      expect(r.riuscito, isFalse);
      expect(r.errore, contains('non è un punto'));
    });

    test('non si elimina qualcosa che non è un punto', () async {
      final r = await motore.elimina(progetto, '..');
      expect(r.riuscito, isFalse);
      expect(r.errore, contains('non è un punto'));
    });

    test('se la rete non regge, NON si salta', () async {
      final e = await motore.crea(progetto, progetto, nota: 'p');
      expect(e.riuscito, isTrue);

      // Un motore identico, tranne che ogni copia fallisce. È il disco pieno,
      // il permesso negato, la corrente che va via a metà.
      final rotto = PuntiMotore(
        radice: motore.radice,
        esegui: (c, a) async =>
            ProcessResult(0, 1, '', 'No space left on device'),
      );
      final r = await rotto.ripristina(progetto, e.punto!.id, progetto);
      expect(r.riuscito, isFalse);
      expect(r.errore, contains('non torno indietro'));

      // E soprattutto: la cartella vera non è stata toccata.
      expect(await File('$progetto/uno.txt').readAsString(), 'primo');
      expect(await Directory('$progetto/dentro').exists(), isTrue);
    });

    test('gli errori di cp diventano frasi italiane', () async {
      final rotto = PuntiMotore(
        radice: motore.radice,
        esegui: (c, a) async => ProcessResult(
            0, 1, '', 'cp: cannot create: No space left on device'),
      );
      final e = await rotto.crea(progetto, progetto);
      expect(e.riuscito, isFalse);
      expect(
          e.errore, 'Il disco è pieno: non c\'è posto per il punto di ritorno.');
    });

    test('una copia fallita non lascia mezzo punto a fingere di essere una rete',
        () async {
      final rotto = PuntiMotore(
        radice: motore.radice,
        esegui: (c, a) async => ProcessResult(0, 1, '', 'boom'),
      );
      await rotto.crea(progetto, progetto, nota: 'mezzo');
      expect(await rotto.elenca(progetto), isEmpty);
    });
  });

  // ── La potatura ────────────────────────────────────────────────────────
  //
  // Funzione pura: cento punti finti, nessuna cartella creata. È la parte in
  // cui un errore butta via il lavoro di qualcuno, quindi è quella che voglio
  // poter provare a fondo e in un millisecondo.

  group('quali punti si buttano', () {
    Punto p(DateTime q) =>
        Punto(id: PuntiMotore.idPunto(q, ''), quando: q, nota: '', percorso: '');
    final ora = DateTime(2026, 8, 24, 12, 0);

    test('con uno solo non si butta niente', () {
      expect(PuntiMotore.daPotare([p(DateTime(2020, 1, 1))], adesso: ora),
          isEmpty);
    });

    test('gli ultimi sette giorni si tengono tutti', () {
      final l = [
        for (var h = 0; h < 40; h++) p(ora.subtract(Duration(hours: h * 4))),
      ];
      expect(PuntiMotore.daPotare(l, adesso: ora), isEmpty);
    });

    test('fra sette e trenta giorni ne resta uno al giorno', () {
      final l = [
        p(DateTime(2026, 8, 4, 9)),
        p(DateTime(2026, 8, 4, 15)),
        p(DateTime(2026, 8, 4, 21)),
        p(DateTime(2026, 8, 5, 9)),
      ];
      final via = PuntiMotore.daPotare(l, adesso: ora);
      expect(via.length, 2);
      // Resta il più recente di ogni giorno.
      expect(via.map((x) => x.quando.hour), containsAll([9, 15]));
    });

    test('oltre trenta giorni ne resta uno a settimana', () {
      final l = [
        for (var g = 0; g < 40; g++)
          p(DateTime(2026, 5, 1).add(Duration(days: g))),
      ];
      final restano = l.length - PuntiMotore.daPotare(l, adesso: ora).length;
      expect(restano, lessThanOrEqualTo(7));
      expect(restano, greaterThanOrEqualTo(5));
    });

    test('il più recente non si butta mai, per quanto sia vecchio', () {
      final l = [p(DateTime(2019, 1, 1)), p(DateTime(2019, 1, 2))];
      final via = PuntiMotore.daPotare(l, adesso: ora);
      expect(via.map((x) => x.quando), isNot(contains(DateTime(2019, 1, 2))));
      expect(via.length, lessThan(l.length));
    });
  });

  // ── Costa gratis, qui? ─────────────────────────────────────────────────

  test('«sa copiare gratis» risponde senza sporcare niente', () async {
    final prima = await Directory(temp.path).list().length;
    await motore.copiaGratuita(progetto);
    expect(await Directory(temp.path).list().length, prima,
        reason: 'la prova del reflink ha lasciato in giro dei file');
  });
}
