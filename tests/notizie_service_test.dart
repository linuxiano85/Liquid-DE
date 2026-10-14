// Prove per `NotizieService`, con testate finte su questo computer: nessuna
// prova dipende dalla rete.
//
//     dart run tests/notizie_service_test.dart
import 'dart:io';
import '../minervad/lib/services/notizie_service.dart';

var prove = 0;

void check(bool value, String message) {
  if (!value) throw StateError(message);
  prove++;
}

String rss(List<String> voci) => '<?xml version="1.0"?><rss version="2.0" '
    'xmlns:media="http://search.yahoo.com/mrss/"><channel><title>Prova</title>${voci.join()}</channel></rss>';

String voce(String titolo, String link, String data, {String immagine = ''}) =>
    '<item><title><![CDATA[$titolo]]></title><link>$link</link><pubDate>$data</pubDate>'
    '${immagine.isEmpty ? '' : '<media:thumbnail width="240" url="$immagine"/>'}</item>';

Future<void> main() async {
  final base = await Directory.systemTemp.createTemp('liquid-notizie-');
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final indirizzo = 'http://127.0.0.1:${server.port}';
  final richieste = <HttpRequest>[];
  // Un PNG da un pixel.
  final png = [137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 248, 15, 4, 0, 9, 251, 3, 253, 227, 85, 242, 156, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130];
  server.listen((r) {
    richieste.add(r);
    final p = r.uri.path;
    if (p == '/tech.xml') {
      r.response.headers.contentType = ContentType('application', 'rss+xml');
      r.response.write(rss([
        voce('Nuovo processore &amp; altro', 'https://esempio.it/a', 'Sat, 11 Oct 2026 10:00:00 +0200', immagine: '$indirizzo/img.png'),
        voce('Notizia vecchia', 'https://esempio.it/vecchia', 'Tue, 30 May 2023 16:35:36 +0200'),
        voce('Link furbo', 'javascript:alert(1)', 'Sat, 11 Oct 2026 11:00:00 +0200'),
      ]));
    } else if (p == '/sport.xml') {
      r.response.headers.contentType = ContentType('application', 'atom+xml');
      r.response.write('<feed xmlns="http://www.w3.org/2005/Atom"><entry><title>Partita</title>'
          '<link href="https://esempio.it/sport"/><updated>2026-10-11T12:00:00Z</updated></entry>'
          '<entry><title>Nuovo processore &amp; altro</title><link href="https://esempio.it/doppione"/>'
          '<updated>2026-10-11T07:00:00Z</updated></entry></feed>');
    } else if (p == '/article-feed.xml') {
      r.response.headers.contentType = ContentType('application', 'rss+xml');
      r.response.write(rss([
        voce('Notizia con metadati', '$indirizzo/articolo', 'Sun, 11 Oct 2026 13:00:00 +0200'),
        voce('Notizia senza immagine', '$indirizzo/senza-foto', 'Sun, 11 Oct 2026 12:00:00 +0200'),
        voce('Notizia con redirect esterno', '$indirizzo/redirect', 'Sun, 11 Oct 2026 11:00:00 +0200'),
      ]));
    } else if (p == '/articolo') {
      r.response.headers.contentType = ContentType.html;
      r.response.write('<html><head><meta content="/img.png" property="og:image"></head>'
          '<body><script src="/tracking.js"></script><img src="/pubblicita.png"></body></html>');
    } else if (p == '/senza-foto') {
      r.response.headers.contentType = ContentType.html;
      r.response.write('<head><title>Articolo</title></head><body>Solo testo</body>');
    } else if (p == '/redirect') {
      r.response.statusCode = 302;
      r.response.headers.set('location', 'https://esempio.it/non-leggere');
    } else if (p == '/img.png') {
      r.response.headers.contentType = ContentType('image', 'png');
      r.response.add(png);
    } else {
      r.response.statusCode = 404;
    }
    r.response.close();
  });

  final fonti = {
    'it': [
      Fonte('Tech', '$indirizzo/tech.xml', 'tecnologia'),
      Fonte('Sport', '$indirizzo/sport.xml', 'sport'),
      Fonte('Rotta', '$indirizzo/manca.xml', 'cultura'),
    ],
  };
  final s = NotizieService(cartellaImmagini: '${base.path}/cache', fonti: fonti, soloHttps: false);
  final adesso = DateTime.utc(2026, 10, 11, 14);
  try {
    var r = await s.notizie(adesso: adesso);
    final a = (r['articoli'] as List).cast<Map>();
    final titoli = a.map((x) => x['titolo']).toList();
    check(titoli.join('|') == 'Partita|Nuovo processore & altro',
        'le più recenti prima, niente di vecchio, niente link non web, un titolo una volta: $titoli');
    check(a.first['link'] == 'https://esempio.it/sport' && a.first['fonte'] == 'Sport', 'Atom letto: ${a.first}');
    final img = a[1]['immagine'] as String;
    check(img.startsWith('${base.path}/cache/') && File(img).existsSync(), 'l\'immagine sta in cache, scaricata da qui: $img');
    check(!a[1].containsKey('immagineUrl'), 'alla shell arriva solo il file locale, non l\'indirizzo');
    check(r['error'] == '', 'una fonte rotta su tre non è un errore: ${r['error']}');
    check(richieste.every((q) => q.headers.value('referer') == null && q.headers.value('cookie') == null),
        'niente Referer e niente cookie');
    check(richieste.every((q) => '${q.headers.value('user-agent')}'.startsWith('LiquidDE/')), 'si presenta col suo nome');

    // Interessi: solo sport.
    r = await s.notizie(adesso: adesso, interessiScelti: ['sport']);
    check((r['articoli'] as List).every((x) => x['interesse'] == 'sport'), 'gli interessi filtrano');

    // La stessa richiesta: dalla copia, e l'immagine dalla cache.
    final prima = richieste.length;
    await s.notizie(adesso: adesso);
    check(richieste.length == prima, 'entro quindici minuti nessuna richiesta nuova');

    // Fonti spente.
    r = await s.notizie(adesso: adesso, spente: ['$indirizzo/sport.xml']);
    check(!(r['articoli'] as List).any((x) => x['fonte'] == 'Sport'), 'una fonte spenta non si legge');
    final elenco = (r['fonti'] as List).cast<Map>();
    check(elenco.firstWhere((f) => f['nome'] == 'Sport')['accesa'] == false, 'e l\'elenco la segna spenta');

    // Nessun interesse: nessuna richiesta, nessun errore.
    final ancora = richieste.length;
    r = await s.notizie(adesso: adesso, interessiScelti: []);
    check((r['articoli'] as List).isEmpty && richieste.length == ancora, 'senza interessi non parte niente');

    final metadata = NotizieService(cartellaImmagini: '${base.path}/meta', soloHttps: false,
        fonti: {'it': [Fonte('Con metadati', '$indirizzo/article-feed.xml', 'attualita')]});
    final enhanced = await metadata.notizie(adesso: adesso);
    final enhancedArticles = (enhanced['articoli'] as List).cast<Map>();
    check(File(enhancedArticles.first['immagine'] as String).existsSync(),
        'foto og:image recuperata quando manca nel feed');
    check(enhancedArticles.skip(1).every((a) => a['immagine'] == ''),
        'nessuna immagine inventata per pagine senza foto o redirect esterno');
    check(!richieste.any((r) => r.uri.path == '/tracking.js' || r.uri.path == '/pubblicita.png'),
        'nessuna richiesta a script o pubblicità della pagina');
    check(richieste.every((r) => r.headers.value('referer') == null && r.headers.value('cookie') == null),
        'anche le pagine HTML non inviano Referer o cookie');
    final countAfter = richieste.length;
    await metadata.notizie(adesso: adesso);
    check(richieste.length == countAfter, 'foto e assenza di foto entrambe in cache');
    final page = Uri.parse('https://testata.it/articolo');
    check(immagineDaPagina('<META CONTENT="/foto.jpg?a=1&amp;b=2" PROPERTY="og:image">', page)
        == 'https://testata.it/foto.jpg?a=1&b=2', 'attributi invertiti, maiuscole e URL relative');
    check(immagineDaPagina('<meta name="twitter:image" content="https://cdn.it/foto.png">', page)
        == 'https://cdn.it/foto.png', 'fallback twitter:image');
    check(immagineDaPagina('<meta property="og:image" content="data:image/png;base64,abc">', page).isEmpty,
        'metadati non web ignorati');
    check(immagineDaPagina('<meta property="og:image" content="http://cdn.it/foto.png">', page).isEmpty,
        'nessun downgrade HTTP per immagini di produzione');
    check(immagineDaPagina('<meta property="og:image" content="https://utente:segreto@cdn.it/foto.png">', page).isEmpty,
        'nessuna URL con credenziali nei metadati');
    check(NotizieService.nomeCache('https://x/y') == NotizieService.nomeCache('https://x/y') &&
        NotizieService.nomeCache('https://x/y') != NotizieService.nomeCache('https://x/z'),
        'il nome in cache è stabile e distingue');
    check(NotizieService.fontiDiSerie.values.expand((l) => l).every((f) => f.url.startsWith('https://')),
        'le fonti di serie sono tutte https');
  } finally {
    await server.close(force: true);
    await base.delete(recursive: true);
  }
  print('notizie_service: $prove prove superate');
}
