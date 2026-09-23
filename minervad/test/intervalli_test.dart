// `Range`: prestare un PEZZO di file, che è come si guarda un film.
//
// ── Perché queste prove esistono ──────────────────────────────────────────
//
// Fino al 4 settembre 2026 il servizio che presta un file dichiarava
// `DLNA.ORG_OP=01` — «so consegnare a partire da un byte qualunque» — e non
// era vero: mandava sempre tutto dal principio. Su una fotografia da 3 MB non
// si notava. Su un film vuol dire non potersi spostare, e su certi lettori
// vuol dire non partire affatto.
//
// La lettura dell'intestazione ha due errori classici, e li prova tutti e due
// questo file: `bytes=-500` che vuol dire «gli ULTIMI 500» e si legge al
// contrario, e l'ultimo byte che in HTTP è compreso mentre in `openRead` è
// escluso — un byte per pezzo, e il film si ferma senza dire perché.
import 'dart:io';

import 'package:minervad/services/foto/servizio_effimero.dart';
import 'package:test/test.dart';

void main() {
  group('leggere l\'intestazione, senza aprire niente', () {
    test('la forma normale: da qui a lì, estremi compresi', () {
      final i = Intervallo.leggi('bytes=100-199', 1000)!;
      expect(i.da, 100);
      expect(i.a, 199);
      expect(i.quanti, 100); // 199 - 100 + 1
    });

    test('«da qui alla fine»', () {
      final i = Intervallo.leggi('bytes=900-', 1000)!;
      expect(i.da, 900);
      expect(i.a, 999);
      expect(i.quanti, 100);
    });

    test('«gli ULTIMI tanti», che si legge al contrario', () {
      // `bytes=-500` NON è «dal byte 0 al 500». Chi lo legge così serve
      // l'inizio del film a chi voleva la fine.
      final i = Intervallo.leggi('bytes=-500', 1000)!;
      expect(i.da, 500);
      expect(i.a, 999);
      expect(i.quanti, 500);
    });

    test('e se ne chiede più di quanti ce ne sono, si dà tutto', () {
      final i = Intervallo.leggi('bytes=-5000', 1000)!;
      expect(i.da, 0);
      expect(i.a, 999);
    });

    test('chiedere oltre la fine non è un errore: si dà quello che c\'è', () {
      final i = Intervallo.leggi('bytes=900-99999', 1000)!;
      expect(i.a, 999);
    });

    test('cominciare oltre la fine SÌ, ed è un errore suo', () {
      // Ha una risposta sua nella specifica (416) e va distinta da «non ho
      // capito»: il televisore deve sapere quanto è lungo per richiedere bene.
      expect(() => Intervallo.leggi('bytes=1000-', 1000), throwsRangeError);
      expect(() => Intervallo.leggi('bytes=5000-6000', 1000), throwsRangeError);
    });

    test('quello che non capiamo vale come «non chiesto»', () {
      // E allora si manda tutto, che è la risposta giusta e non un errore.
      for (final storto in [
        null, '', 'roba', 'items=0-10', 'bytes=', 'bytes=abc-def',
        'bytes=10', 'bytes=-0', 'bytes=200-100',
      ]) {
        expect(Intervallo.leggi(storto, 1000), isNull, reason: '$storto');
      }
    });

    test('maiuscole e spazi non cambiano la risposta', () {
      final i = Intervallo.leggi('  BYTES= 10 - 20 ', 1000)!;
      expect(i.da, 10);
      expect(i.a, 20);
    });

    test('più intervalli insieme: si serve il primo', () {
      // È legale e nessun televisore lo fa. Servire il primo è quello che
      // fanno anche i server veri.
      final i = Intervallo.leggi('bytes=0-99,200-299', 1000)!;
      expect(i.da, 0);
      expect(i.a, 99);
    });
  });

  group('e adesso davvero, su un socket', () {
    late Directory tana;
    late File film;
    late ServizioEffimero s;
    late String url;

    // 4096 byte con dentro il proprio numero d'ordine: così un pezzo servito
    // storto non è «lungo giusto ma sbagliato», si vede subito.
    final contenuto = List<int>.generate(4096, (i) => i % 251);

    setUp(() async {
      tana = await Directory.systemTemp.createTemp('minerva-intervalli');
      film = File('${tana.path}/film.mp4')..writeAsBytesSync(contenuto);
      s = ServizioEffimero(file: film, tipo: 'video/mp4', porta: 0);
      url = await s.apri(versoIl: '127.0.0.1');
    });

    tearDown(() async {
      await s.chiudi();
      tana.deleteSync(recursive: true);
    });

    Future<HttpClientResponse> chiedi(String? range,
        {String metodo = 'GET'}) async {
      final c = HttpClient();
      final r = await c.openUrl(metodo, Uri.parse(url));
      if (range != null) r.headers.set(HttpHeaders.rangeHeader, range);
      return r.close();
    }

    test('senza Range si manda tutto, e si dice che si saprebbe fare a pezzi',
        () async {
      final r = await chiedi(null);
      expect(r.statusCode, 200);
      expect(r.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
      expect(await _byte(r), contenuto);
    });

    test('con Range si risponde 206 e si manda ESATTAMENTE quel pezzo',
        () async {
      final r = await chiedi('bytes=1000-1099');
      expect(r.statusCode, 206);
      expect(r.headers.value(HttpHeaders.contentRangeHeader),
          'bytes 1000-1099/4096');
      final b = await _byte(r);
      // Cento byte, non novantanove: in HTTP l'ultimo è COMPRESO.
      expect(b.length, 100);
      expect(b, contenuto.sublist(1000, 1100));
    });

    test('l\'ultimo byte del file arriva davvero', () async {
      // È il caso che prende il `+ 1` dimenticato: senza, questo pezzo è
      // vuoto e il film si ferma un fotogramma prima della fine.
      final r = await chiedi('bytes=4095-');
      expect(r.statusCode, 206);
      final b = await _byte(r);
      expect(b.length, 1);
      expect(b.first, contenuto.last);
    });

    test('gli ultimi byte, chiesti al contrario', () async {
      final r = await chiedi('bytes=-10');
      expect(r.statusCode, 206);
      expect(r.headers.value(HttpHeaders.contentRangeHeader),
          'bytes 4086-4095/4096');
      expect(await _byte(r), contenuto.sublist(4086));
    });

    test('un intervallo fuori dal file riceve 416, non un 404', () async {
      final r = await chiedi('bytes=9000-9100');
      expect(r.statusCode, 416);
      // Con la lunghezza, perché il televisore possa richiedere bene.
      expect(r.headers.value(HttpHeaders.contentRangeHeader), 'bytes */4096');
      await r.drain<void>();
    });

    test('rimettendo insieme i pezzi si riottiene il film intero', () async {
      // La prova che conta: tre richieste come le fa un lettore, e quello che
      // ne esce deve essere identico al file. Prende in un colpo solo tutti
      // gli errori di un byte, da qualunque parte stiano.
      final pezzi = <int>[];
      for (final r in ['bytes=0-999', 'bytes=1000-2999', 'bytes=3000-']) {
        final risposta = await chiedi(r);
        expect(risposta.statusCode, 206);
        pezzi.addAll(await _byte(risposta));
      }
      expect(pezzi, contenuto);
    });

    test('saltare avanti NON consuma i prelievi', () async {
      // Un film in cui ci si sposta fa molte richieste. Contarle vorrebbe dire
      // che spostarsi qualche volta chiude il servizio a metà visione.
      final poco = ServizioEffimero(
          file: film, tipo: 'video/mp4', porta: 0, prelieviMassimi: 1);
      final u = await poco.apri(versoIl: '127.0.0.1');
      final c = HttpClient();
      Future<int> pezzo(String range) async {
        final q = await c.getUrl(Uri.parse(u));
        q.headers.set(HttpHeaders.rangeHeader, range);
        final r = await q.close();
        await r.drain<void>();
        return r.statusCode;
      }

      expect(await pezzo('bytes=0-9'), 206);      // l'unico «da capo»
      expect(await pezzo('bytes=100-199'), 206);  // un salto: gratis
      expect(await pezzo('bytes=200-299'), 206);
      expect(await pezzo('bytes=3000-3099'), 206);
      // Ma ricominciare da zero sì, ed è il prelievo in più.
      expect(await pezzo('bytes=0-9'), 404);
      c.close(force: true);
      await poco.chiudi();
    });

    test('le intestazioni DLNA di un VIDEO non sono quelle di una foto',
        () async {
      final r = await chiedi(null, metodo: 'HEAD');
      expect(r.headers.value('transferMode.dlna.org'), 'Streaming');
      expect(r.headers.value('contentFeatures.dlna.org'),
          contains('DLNA.ORG_FLAGS=01700000'));
      await r.drain<void>();

      final foto = ServizioEffimero(file: film, tipo: 'image/jpeg', porta: 0);
      final u = await foto.apri(versoIl: '127.0.0.1');
      final c = HttpClient();
      final q = await (await c.openUrl('HEAD', Uri.parse(u))).close();
      expect(q.headers.value('transferMode.dlna.org'), 'Interactive');
      expect(q.headers.value('contentFeatures.dlna.org'),
          contains('DLNA.ORG_FLAGS=00900000'));
      await q.drain<void>();
      c.close(force: true);
      await foto.chiudi();
    });

    test('la HEAD dice la lunghezza del pezzo senza mandarlo', () async {
      final r = await chiedi('bytes=10-19', metodo: 'HEAD');
      expect(r.statusCode, 206);
      expect(r.headers.contentLength, 10);
      expect(await _byte(r), isEmpty);
    });
  });

  test('un film non si spegne a metà: la sveglia si rimanda a ogni pezzo',
      () async {
    // Era un difetto vero: la scadenza era secca dall'apertura, dieci minuti,
    // e suonava nel mezzo del film. Adesso conta il SILENZIO.
    final tana = await Directory.systemTemp.createTemp('minerva-sveglia');
    final f = File('${tana.path}/f.mp4')..writeAsBytesSync(List.filled(64, 3));
    final s = ServizioEffimero(
        file: f,
        tipo: 'video/mp4',
        porta: 0,
        durata: const Duration(milliseconds: 700));
    final u = await s.apri(versoIl: '127.0.0.1');
    final c = HttpClient();

    // Si continua a guardare: quattro richieste a 300 ms, cioè ben oltre i
    // 700 ms della scadenza secca di una volta.
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final q = await c.getUrl(Uri.parse(u));
      q.headers.set(HttpHeaders.rangeHeader, 'bytes=10-20');
      final r = await q.close();
      expect(r.statusCode, 206, reason: 'spento dopo ${i + 1} richieste');
      await r.drain<void>();
    }
    expect(s.aperto, isTrue);

    // E quando si smette di guardare, si spegne da solo.
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(s.aperto, isFalse);

    c.close(force: true);
    await s.chiudi();
    tana.deleteSync(recursive: true);
  });
}

Future<List<int>> _byte(HttpClientResponse r) async {
  final b = <int>[];
  await for (final pezzo in r) {
    b.addAll(pezzo);
  }
  return b;
}
