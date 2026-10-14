import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// NotizieService — Le notizie della bacheca Widget, senza tracciamento.
///
/// ── Perché esiste ─────────────────────────────────────────────────────────
///
/// il manutentore, 11 ottobre 2026: nei Widget del preset Windows «si vede solo il
/// meteo e ci vorrebbero anche notizie, ma che rispettino la privacy». In
/// Windows le notizie vengono da MSN, con un account e un profilo di chi
/// legge. Qui vengono dai feed RSS delle testate, che sono pubblici.
///
/// ── CHE COSA ESCE DA QUESTO COMPUTER ───────────────────────────────────────
///
///   · una richiesta per ogni feed delle testate scelte, solo quando si apre
///     la bacheca (e non più di una ogni quindici minuti);
///   · una richiesta per ogni immagine, fatta da qui: niente cookie (questo
///     client non ne tiene), niente `Referer`, e la shell non contatta
///     nessuno. Le immagini restano in cache.
///   · quando il feed omette la foto, si legge soltanto l'HTML dell'articolo
///     sullo stesso sito del feed: niente script, cookie o richieste di
///     pubblicità. Si cerca og:image, con limiti di tempo e dimensione.
///
/// Gli interessi non escono: si sceglie qui quali notizie mostrare, dopo
/// averle scaricate tutte. Nessun account, nessun identificativo.
///
/// ── Le fonti ──────────────────────────────────────────────────────────────
///
/// Verificate l'11 ottobre 2026: rispondono e hanno notizie di oggi. Il feed
/// tecnologia di ANSA (`sito/notizie/tecnologia`) era fermo al 2023, quello
/// di Wired Italia a luglio 2026; Il Post rifiuta i programmi (403) e lo si
/// rispetta.
class NotizieService {
  NotizieService({
    String? cartellaImmagini,
    Map<String, List<Fonte>>? fonti,
    this.agente = _agenteDiSerie,
    this.soloHttps = true,
  }) : _cartellaImmagini =
           cartellaImmagini ??
           '${Platform.environment['XDG_CACHE_HOME'] ?? '${Platform.environment['HOME']}/.cache'}'
               '/liquid-de/notizie',
       fonti = fonti ?? fontiDiSerie;

  final String _cartellaImmagini;
  final Map<String, List<Fonte>> fonti;
  final String agente;

  /// Le immagini si scaricano solo in https. Le prove, con un server finto
  /// in locale, lo spengono.
  final bool soloHttps;

  static const String _agenteDiSerie =
      'LiquidDE/1.0 (+https://github.com/linuxiano85/Liquid-DE)';

  /// Gli interessi che si possono scegliere, nell'ordine in cui si mostrano.
  static const List<String> interessi = [
    'attualita',
    'tecnologia',
    'scienza',
    'economia',
    'sport',
    'cultura',
  ];

  static const Map<String, List<Fonte>> fontiDiSerie = {
    'it': [
      Fonte(
        'ANSA',
        'https://www.ansa.it/sito/notizie/topnews/topnews_rss.xml',
        'attualita',
      ),
      Fonte(
        'ANSA Tecnologia',
        'https://www.ansa.it/canale_tecnologia/notizie/tecnologia_rss.xml',
        'tecnologia',
      ),
      Fonte(
        'Punto Informatico',
        'https://www.punto-informatico.it/feed/',
        'tecnologia',
      ),
      Fonte('HDblog', 'https://www.hdblog.it/feed/', 'tecnologia'),
      Fonte(
        'la Repubblica Tecnologia',
        'https://www.repubblica.it/rss/tecnologia/rss2.0.xml',
        'tecnologia',
      ),
      Fonte(
        'ANSA Scienza',
        'https://www.ansa.it/canale_scienza_tecnica/notizie/scienzaetecnica_rss.xml',
        'scienza',
      ),
      Fonte(
        'ANSA Economia',
        'https://www.ansa.it/sito/notizie/economia/economia_rss.xml',
        'economia',
      ),
      Fonte(
        'Il Sole 24 Ore Tecnologia',
        'https://www.ilsole24ore.com/rss/tecnologia.xml',
        'economia',
      ),
      Fonte(
        'ANSA Sport',
        'https://www.ansa.it/sito/notizie/sport/sport_rss.xml',
        'sport',
      ),
      Fonte(
        'ANSA Cultura',
        'https://www.ansa.it/sito/notizie/cultura/cultura_rss.xml',
        'cultura',
      ),
    ],
    'en': [
      Fonte('BBC News', 'https://feeds.bbci.co.uk/news/rss.xml', 'attualita'),
      Fonte(
        'BBC Technology',
        'https://feeds.bbci.co.uk/news/technology/rss.xml',
        'tecnologia',
      ),
      Fonte(
        'BBC Science',
        'https://feeds.bbci.co.uk/news/science_and_environment/rss.xml',
        'scienza',
      ),
      Fonte(
        'BBC Business',
        'https://feeds.bbci.co.uk/news/business/rss.xml',
        'economia',
      ),
      Fonte('BBC Sport', 'https://feeds.bbci.co.uk/sport/rss.xml', 'sport'),
      Fonte(
        'BBC Culture',
        'https://feeds.bbci.co.uk/news/entertainment_and_arts/rss.xml',
        'cultura',
      ),
    ],
  };

  static const Duration validita = Duration(minutes: 15);
  static const int _immagineMassima = 3 * 1024 * 1024;

  final Map<String, ({DateTime quando, List<Map<String, dynamic>> articoli})>
  _copie = {};

  /// Le fonti di una lingua, con quelle spente segnate.
  List<Map<String, dynamic>> elencoFonti(String lingua, List<String> spente) {
    final elenco = fonti[lingua] ?? fonti['en'] ?? const [];
    return [
      for (final f in elenco)
        {
          'nome': f.nome,
          'url': f.url,
          'interesse': f.interesse,
          'accesa': !spente.contains(f.url),
        },
    ];
  }

  /// Le notizie per la bacheca: le più recenti degli interessi scelti, dalle
  /// fonti accese, al massimo `quante`, con l'immagine già in cache.
  Future<Map<String, dynamic>> notizie({
    String lingua = 'it',
    List<String> interessiScelti = interessi,
    List<String> spente = const [],
    int quante = 12,
    DateTime? adesso,
  }) async {
    final elenco = (fonti[lingua] ?? fonti['en'] ?? const <Fonte>[])
        .where(
          (f) =>
              !spente.contains(f.url) && interessiScelti.contains(f.interesse),
        )
        .toList();
    if (elenco.isEmpty) {
      return {
        'articoli': [],
        'error': '',
        'fonti': elencoFonti(lingua, spente),
      };
    }

    final tutti = <Map<String, dynamic>>[];
    final errori = <String>[];
    await Future.wait(
      elenco.map((f) async {
        try {
          tutti.addAll(await _feed(f));
        } catch (e) {
          errori.add(f.nome);
          print('[MINERVA][NOTIZIE][WARN] ${f.nome}: $e');
        }
      }),
    );

    // Le più recenti prima, una notizia per titolo (la stessa agenzia esce in
    // più feed), e niente notizie di più di tre giorni: un feed fermo da anni
    // non deve riempire la bacheca di cose vecchie.
    final ora = adesso ?? DateTime.now();
    final visti = <String>{};
    tutti.sort((a, b) => (b['data'] as String).compareTo(a['data'] as String));
    final validi = <Map<String, dynamic>>[];
    for (final a in tutti) {
      final data = DateTime.tryParse(a['data'] as String);
      if (data != null && ora.difference(data).inDays > 3) continue;
      if (!visti.add((a['titolo'] as String).toLowerCase())) continue;
      validi.add(a);
    }
    // A turno, una per fonte, dalla più recente: una testata che pubblica
    // di continuo (lo sport in diretta) riempiva da sola mezza bacheca
    // (controprova con le fonti vere, 11 ottobre 2026).
    final perFonte = <String, List<Map<String, dynamic>>>{};
    for (final a in validi) {
      perFonte.putIfAbsent(a['fonte'] as String, () => []).add(a);
    }
    final ordine = perFonte.keys.toList()
      ..sort(
        (x, y) => (perFonte[y]!.first['data'] as String).compareTo(
          perFonte[x]!.first['data'] as String,
        ),
      );
    final scelti = <Map<String, dynamic>>[];
    for (var giro = 0; scelti.length < quante; giro++) {
      var aggiunte = 0;
      for (final fonte in ordine) {
        final lista = perFonte[fonte]!;
        if (giro < lista.length && scelti.length < quante) {
          scelti.add(lista[giro]);
          aggiunte++;
        }
      }
      if (aggiunte == 0) break;
    }
    // Tre richieste alla volta evitano sia la coda sequenziale di dodici
    // foto sia un picco di connessioni a ogni apertura della bacheca.
    for (var offset = 0; offset < scelti.length; offset += 3) {
      final batch = scelti.skip(offset).take(3);
      await Future.wait(
        batch.map((a) async {
          var url = a['immagineUrl'] as String;
          if (url.isEmpty) {
            url = await _fotoArticolo(
              a['link'] as String,
              a['feedUrl'] as String,
            );
          }
          a['immagine'] = url.isEmpty ? '' : await _immagine(url);
          a.remove('immagineUrl');
          a.remove('feedUrl');
        }),
      );
    }
    return {
      'articoli': scelti,
      'error': scelti.isEmpty && errori.isNotEmpty
          ? 'Le fonti delle notizie non rispondono. Riprova fra poco.'
          : '',
      'fonti': elencoFonti(lingua, spente),
    };
  }

  /// Le fonti che non hanno risposto, e quando: per cinque minuti non si
  /// richiedono. Una testata giù non va tempestata a ogni apertura della
  /// bacheca.
  final Map<String, DateTime> _guaste = {};
  static const Duration _pausaGuaste = Duration(minutes: 5);

  Future<List<Map<String, dynamic>>> _feed(Fonte f) async {
    final guasta = _guaste[f.url];
    if (guasta != null && DateTime.now().difference(guasta) < _pausaGuaste) {
      throw StateError('non ha risposto da poco');
    }
    final copia = _copie[f.url];
    if (copia != null && DateTime.now().difference(copia.quando) < validita) {
      return copia.articoli.map((a) => Map<String, dynamic>.from(a)).toList();
    }
    final String testo;
    try {
      testo = await _prendiTesto(Uri.parse(f.url));
    } catch (_) {
      _guaste[f.url] = DateTime.now();
      rethrow;
    }
    _guaste.remove(f.url);
    final articoli = articoliDaFeed(testo, f);
    _copie[f.url] = (quando: DateTime.now(), articoli: articoli);
    return articoli.map((a) => Map<String, dynamic>.from(a)).toList();
  }

  HttpClient _client() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 6)
    ..userAgent = agente;

  Future<String> _prendiTesto(Uri u) async {
    final c = _client();
    try {
      final req = await c.getUrl(u);
      final res = await req.close().timeout(const Duration(seconds: 12));
      if (res.statusCode != 200)
        throw HttpException('risposta ${res.statusCode}', uri: u);
      final byte = await res
          .fold<List<int>>(<int>[], (a, b) => a..addAll(b))
          .timeout(const Duration(seconds: 12));
      return utf8.decode(byte, allowMalformed: true);
    } finally {
      c.close(force: true);
    }
  }

  final Map<String, ({DateTime quando, String url})> _fotoPagine = {};
  static const int _htmlMassimo = 384 * 1024;

  bool _webConsentito(Uri url) =>
      url.scheme == 'https' || (!soloHttps && url.scheme == 'http');

  Future<String> _fotoArticolo(String link, String feed) async {
    final original = Uri.tryParse(link);
    final source = Uri.tryParse(feed);
    if (original == null ||
        source == null ||
        !_webConsentito(original) ||
        original.origin != source.origin ||
        original.userInfo.isNotEmpty) {
      return '';
    }
    final cached = _fotoPagine[link];
    final lifetime = cached?.url.isEmpty == true ? _pausaGuaste : validita;
    if (cached != null && DateTime.now().difference(cached.quando) < lifetime) {
      return cached.url;
    }
    final client = _client();
    var photo = '';
    try {
      var uri = original;
      for (var redirects = 0; redirects <= 2; redirects++) {
        final request = await client
            .getUrl(uri)
            .timeout(const Duration(seconds: 4));
        request.followRedirects = false;
        final response = await request.close().timeout(
          const Duration(seconds: 4),
        );
        if (response.isRedirect) {
          final location = response.headers.value('location');
          final next = location == null ? null : uri.resolve(location);
          if (next == null ||
              next.origin != original.origin ||
              !_webConsentito(next)) {
            break;
          }
          uri = next;
          continue;
        }
        final type = response.headers.contentType?.mimeType;
        if (response.statusCode != 200 ||
            (type != 'text/html' && type != 'application/xhtml+xml')) {
          break;
        }
        final bytes = <int>[];
        final deadline = DateTime.now().add(const Duration(seconds: 4));
        await for (final part in response.timeout(const Duration(seconds: 4))) {
          final remaining = _htmlMassimo - bytes.length;
          bytes.addAll(part.take(remaining));
          final html = utf8.decode(bytes, allowMalformed: true);
          photo = immagineDaPagina(html, uri, ancheHttp: !soloHttps);
          if (photo.isNotEmpty ||
              html.toLowerCase().contains('</head>') ||
              bytes.length >= _htmlMassimo ||
              DateTime.now().isAfter(deadline)) {
            break;
          }
        }
        break;
      }
    } catch (_) {
      // Una pagina senza metadati non deve impedire di leggere la notizia.
    } finally {
      client.close(force: true);
    }
    if (_fotoPagine.length >= 256) {
      _fotoPagine.remove(_fotoPagine.keys.first);
    }
    _fotoPagine[link] = (quando: DateTime.now(), url: photo);
    return photo;
  }

  /// L'immagine in cache, scaricata da qui. Ritorna il percorso, o '' se non
  /// è un'immagine, è troppo grande o non risponde.
  Future<String> _immagine(String url) async {
    final u = Uri.tryParse(url);
    if (u == null || (u.scheme != 'https' && (soloHttps || u.scheme != 'http')))
      return '';
    final nome = nomeCache(url);
    final cartella = Directory(_cartellaImmagini);
    if (cartella.existsSync()) {
      for (final f in cartella.listSync(followLinks: false).whereType<File>()) {
        if (f.uri.pathSegments.last.startsWith('$nome.')) return f.path;
      }
    }
    final c = _client();
    try {
      final req = await c.getUrl(u);
      final res = await req.close().timeout(const Duration(seconds: 10));
      final tipo = res.headers.contentType;
      if (res.statusCode != 200 || tipo == null || tipo.primaryType != 'image')
        return '';
      final estensione =
          const {
            'jpeg': 'jpg',
            'png': 'png',
            'webp': 'webp',
            'gif': 'gif',
          }[tipo.subType] ??
          '';
      if (estensione.isEmpty) return '';
      final byte = <int>[];
      await for (final pezzo in res.timeout(const Duration(seconds: 10))) {
        byte.addAll(pezzo);
        if (byte.length > _immagineMassima) return '';
      }
      await Directory(_cartellaImmagini).create(recursive: true);
      final file = File('$_cartellaImmagini/$nome.$estensione');
      await file.writeAsBytes(byte, flush: true);
      return file.path;
    } catch (_) {
      return '';
    } finally {
      c.close(force: true);
    }
  }

  /// Un nome di file stabile per un indirizzo: due FNV-1a a 32 bit con semi
  /// diversi, in esadecimale. `hashCode` di Dart non promette di restare
  /// uguale da un avvio all'altro, e la cache deve ritrovare i suoi file.
  static String nomeCache(String url) {
    String fnv(int seme) {
      var h = seme;
      for (final b in utf8.encode(url)) {
        h ^= b;
        h = (h * 0x01000193) & 0xffffffff;
      }
      return h.toRadixString(16).padLeft(8, '0');
    }

    return fnv(0x811c9dc5) + fnv(0x01234567);
  }
}

/// Una testata: nome, indirizzo del feed e l'interesse a cui appartiene.
class Fonte {
  const Fonte(this.nome, this.url, this.interesse);
  final String nome;
  final String url;
  final String interesse;
}

/// Le notizie di un feed RSS 2.0 o Atom, ridotte a quello che serve:
/// titolo, fonte, collegamento (solo http/https), data ISO, indirizzo
/// dell'immagine (solo https), interesse.
///
/// Si legge con le espressioni regolari e non con un parser XML: i feed
/// veri sono spesso XML imperfetto, e qui servono cinque campi.
List<Map<String, dynamic>> articoliDaFeed(String testo, Fonte f) {
  final fuori = <Map<String, dynamic>>[];
  final voci = RegExp(
    r'<(item|entry)\b[^>]*>([\s\S]*?)</\1>',
    caseSensitive: false,
  ).allMatches(testo);
  for (final v in voci) {
    final corpo = v.group(2)!;
    final titolo = _testo(_campo(corpo, 'title'));
    var link = _campo(corpo, 'link');
    if (link.isEmpty) {
      link =
          RegExp(
            r'''<link\b[^>]*href=["']([^"']+)["']''',
            caseSensitive: false,
          ).firstMatch(corpo)?.group(1) ??
          '';
    }
    link = _testo(link);
    final u = Uri.tryParse(link);
    if (titolo.isEmpty ||
        u == null ||
        (u.scheme != 'http' && u.scheme != 'https'))
      continue;
    final dataTesto = _testo(
      _campo(corpo, 'pubDate').isNotEmpty
          ? _campo(corpo, 'pubDate')
          : (_campo(corpo, 'published').isNotEmpty
                ? _campo(corpo, 'published')
                : _campo(corpo, 'updated')),
    );
    final data = _data(dataTesto);
    fuori.add({
      'titolo': titolo.length > 200 ? '${titolo.substring(0, 200)}…' : titolo,
      'fonte': f.nome,
      'link': link,
      'data': data?.toUtc().toIso8601String() ?? '',
      'interesse': f.interesse,
      'immagineUrl': _immagineDi(corpo, f.url.startsWith('http://')),
      'feedUrl': f.url,
    });
  }
  return fuori;
}

String _campo(String corpo, String nome) {
  final m = RegExp(
    '<$nome\\b[^>]*>([\\s\\S]*?)</$nome>',
    caseSensitive: false,
  ).firstMatch(corpo);
  return m?.group(1) ?? '';
}

/// Testo semplice: senza CDATA, senza tag, con le entità più comuni.
String _testo(String s) {
  var t = s.replaceAll(RegExp(r'<!\[CDATA\[|\]\]>'), '');
  t = t.replaceAll(RegExp(r'<[^>]+>'), '');
  t = t
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&#8217;', '’')
      .replaceAll('&#8220;', '“')
      .replaceAll('&#8221;', '”');
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _immagineDi(String corpo, bool ancheHttp) {
  for (final re in [
    RegExp(
      r'''<media:content\b[^>]*url=["']([^"']+)["']''',
      caseSensitive: false,
    ),
    RegExp(
      r'''<media:thumbnail\b[^>]*url=["']([^"']+)["']''',
      caseSensitive: false,
    ),
    RegExp(
      r'''<enclosure\b[^>]*type=["']image/[^"']*["'][^>]*url=["']([^"']+)["']''',
      caseSensitive: false,
    ),
    RegExp(
      r'''<enclosure\b[^>]*url=["']([^"']+)["'][^>]*type=["']image/''',
      caseSensitive: false,
    ),
    RegExp(r'''<img\b[^>]*src=["']([^"']+)["']''', caseSensitive: false),
  ]) {
    // L'HTML della descrizione arriva anche codificato (`&lt;img …&gt;`).
    final m = re.firstMatch(
      corpo
          .replaceAll('&quot;', '"')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>'),
    );
    if (m != null) {
      final url = m.group(1)!.replaceAll('&amp;', '&');
      if (url.startsWith('https://') ||
          (ancheHttp && url.startsWith('http://')))
        return url;
    }
  }
  return '';
}

DateTime? _data(String s) {
  if (s.isEmpty) return null;
  final iso = DateTime.tryParse(s);
  if (iso != null) return iso;
  // RFC 822: «Sat, 11 Oct 2026 16:20:00 +0200» o «… GMT».
  final m = RegExp(
    r'(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|[A-Z]{1,4})?',
  ).firstMatch(s);
  if (m == null) return null;
  const mesi = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };
  final mese = mesi[m.group(2)!.toLowerCase()];
  if (mese == null) return null;
  var d = DateTime.utc(
    int.parse(m.group(3)!),
    mese,
    int.parse(m.group(1)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
    int.parse(m.group(6) ?? '0'),
  );
  final zona = m.group(7) ?? '';
  if (RegExp(r'^[+-]\d{4}$').hasMatch(zona)) {
    final segno = zona.startsWith('-') ? -1 : 1;
    final minuti =
        int.parse(zona.substring(1, 3)) * 60 + int.parse(zona.substring(3, 5));
    d = d.subtract(Duration(minutes: segno * minuti));
  }
  return d;
}

/// I metadati del sito, senza eseguire o caricare altri elementi della pagina.
String immagineDaPagina(String html, Uri page, {bool ancheHttp = false}) {
  for (final tag in RegExp(
    r'<meta\b[^>]*>',
    caseSensitive: false,
  ).allMatches(html)) {
    final attributes = <String, String>{};
    for (final field in RegExp(
      r'''([\w:-]+)\s*=\s*["']([^"']*)["']''',
    ).allMatches(tag.group(0)!)) {
      attributes[field.group(1)!.toLowerCase()] = field.group(2)!;
    }
    final kind = (attributes['property'] ?? attributes['name'] ?? '')
        .toLowerCase();
    if (kind != 'og:image' &&
        kind != 'og:image:secure_url' &&
        kind != 'twitter:image') {
      continue;
    }
    final content = attributes['content'];
    if (content == null || content.trim().isEmpty) {
      continue;
    }
    final uri = page.resolve(content.trim().replaceAll('&amp;', '&'));
    if (uri.userInfo.isEmpty &&
        (uri.scheme == 'https' || (ancheHttp && uri.scheme == 'http'))) {
      return uri.toString();
    }
  }
  return '';
}
