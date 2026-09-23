// Il servizio che presta UNA fotografia a un televisore.
//
// ── Il difetto che queste prove tengono fermo ──────────────────────────────
//
// 3 settembre 2026, provando verso il televisore della cucina (un Samsung
// Tizen, l'unico su cui è lecito provare). La fotografia non arrivava, e il
// televisore rispondeva:
//
//     «SetAVTransportURI» rifiutata dal televisore: Resource not found
//
// Che indica il posto sbagliato: sembra la rete, o il firewall. Sono servite
// tre prove per separarli — l'indirizzo era giusto e noi stessi scaricavamo il
// file con un HTTP 200; il firewall non c'entrava, perché anche su una porta
// già aperta il televisore diceva la stessa cosa.
//
// Era **il nostro servizio a dire di no**: accettava solo `GET`, e un renderer
// DLNA prima di accettare l'indirizzo manda una **HEAD** per vedere che la
// risorsa esista. Riceveva 404, e concludeva che non c'era.
//
// È la forma peggiore di difetto: il messaggio d'errore era vero e mandava a
// cercare dall'altra parte della rete.
import 'dart:io';

import 'package:minervad/services/foto/servizio_effimero.dart';
import 'package:test/test.dart';

void main() {
  late Directory tana;
  late File foto;
  late ServizioEffimero s;

  setUp(() async {
    tana = Directory.systemTemp.createTempSync('minerva-effimero-');
    foto = File('${tana.path}/foto.jpg')
      ..writeAsBytesSync(List<int>.filled(1024, 7));
    // Porta zero: una qualunque libera. Queste prove non toccano il firewall
    // e non devono litigare con una trasmissione vera in corso.
    s = ServizioEffimero(file: foto, tipo: 'image/jpeg', porta: 0);
  });

  tearDown(() async {
    await s.chiudi();
    tana.deleteSync(recursive: true);
  });

  Future<HttpClientResponse> chiedi(String url, String metodo) async {
    final c = HttpClient();
    try {
      final r = metodo == 'HEAD'
          ? await c.headUrl(Uri.parse(url))
          : await c.getUrl(Uri.parse(url));
      return await r.close();
    } finally {
      c.close();
    }
  }

  test('risponde alla HEAD che il televisore manda per prima', () async {
    final url = await s.apri(versoIl: '127.0.0.1');
    final r = await chiedi(url, 'HEAD');
    expect(r.statusCode, 200,
        reason: 'un renderer DLNA controlla con HEAD prima di accettare '
            'l\'indirizzo: un 404 qui diventa «Resource not found» sul '
            'televisore, e manda a cercare il difetto nella rete');
    expect('${r.headers.contentType}', contains('image/jpeg'));
    expect(r.headers.value('contentFeatures.dlna.org'), isNotNull);
    await r.drain<void>();
  });

  test('e la HEAD non consuma i prelievi', () async {
    // Contarla vorrebbe dire che un televisore che controlla due volte
    // esaurisce da solo il permesso di scaricare, e la fotografia non arriva
    // mai — con tutto verde da questa parte.
    final url = await s.apri(versoIl: '127.0.0.1');
    for (var i = 0; i < 6; i++) {
      final h = await chiedi(url, 'HEAD');
      expect(h.statusCode, 200, reason: 'la HEAD numero ${i + 1} è stata rifiutata');
      await h.drain<void>();
    }
    final g = await chiedi(url, 'GET');
    expect(g.statusCode, 200);
    expect((await g.fold<int>(0, (n, b) => n + b.length)), 1024);
  });

  test('un indirizzo sbagliato è un no, e non dice cosa c\'è', () async {
    final url = await s.apri(versoIl: '127.0.0.1');
    final base = url.substring(0, url.lastIndexOf('/'));
    for (final finto in ['$base/', '$base/altro', '${url}x']) {
      final r = await chiedi(finto, 'GET');
      expect(r.statusCode, 404, reason: finto);
      await r.drain<void>();
    }
  });

  test('dopo i prelievi concessi non si scarica più', () async {
    final poche = ServizioEffimero(
        file: foto, tipo: 'image/jpeg', porta: 0, prelieviMassimi: 2);
    final url = await poche.apri(versoIl: '127.0.0.1');
    for (var i = 0; i < 2; i++) {
      final r = await chiedi(url, 'GET');
      expect(r.statusCode, 200);
      await r.drain<void>();
    }
    final terzo = await chiedi(url, 'GET');
    expect(terzo.statusCode, 404);
    await terzo.drain<void>();
    await poche.chiudi();
  });

  test('chiuso, non risponde più nessuno', () async {
    final url = await s.apri(versoIl: '127.0.0.1');
    await s.chiudi();
    expect(() => chiedi(url, 'GET'), throwsA(isA<SocketException>()));
  });
}
