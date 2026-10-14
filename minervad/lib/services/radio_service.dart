import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// RadioService — Le radio di tutto il mondo, per Minerva Media.
///
/// ── Da dove vengono ───────────────────────────────────────────────────────
///
/// Da radio-browser.info: un elenco libero (dati di pubblico dominio), senza
/// chiave e senza account, tenuto da volontari e controllato ogni giorno
/// (`hidebroken` toglie le stazioni che all'ultimo controllo non
/// rispondevano). Ha più server uguali: se uno non risponde si passa al
/// successivo.
///
/// ── CHE COSA ESCE DA QUESTO COMPUTER ───────────────────────────────────────
///
///   · **cercando** parte la parola scritta, e il paese scelto;
///   · **ascoltando** il lettore si collega alla stazione, come farebbe
///     qualunque radio.
///
/// Non si mandano i «clic» che radio-browser conta per la classifica: direbbe
/// a un terzo quale stazione si sta ascoltando, e la radio funziona lo
/// stesso. E non si scaricano le icone delle stazioni: ognuna sta sul sito
/// della sua radio, e un elenco di sessanta voci vorrebbe dire sessanta
/// server diversi contattati solo per guardare. La pagina mostra l'iniziale.
///
/// ── Revisione di Media, 11 ottobre 2026 ──────────────────────────────────
///
/// il manutentore: «Media lo userei per ascoltare musica, scaricare video e
/// modificare audio e video. Una radio online.» La radio non c'era.
class RadioService {
  RadioService({List<String>? server, this.agente = _agenteDiSerie})
      : server = server ?? _serverDiSerie;

  /// I server di radio-browser, nell'ordine in cui si provano.
  final List<String> server;
  final String agente;

  static const List<String> _serverDiSerie = [
    'https://de1.api.radio-browser.info',
    'https://de2.api.radio-browser.info',
    'https://fi1.api.radio-browser.info',
  ];

  /// radio-browser chiede che ogni programma si presenti col suo nome.
  static const String _agenteDiSerie = 'LiquidDE/1.0 (+https://github.com/linuxiano85/Liquid-DE)';

  /// Lo stesso elenco non cambia in pochi minuti: si tiene.
  static const Duration validita = Duration(minutes: 10);
  final Map<String, ({DateTime quando, List<Map<String, dynamic>> stazioni})> _copie = {};

  /// Il server che ha risposto l'ultima volta: si riparte da lui.
  int _buono = 0;

  /// Cerca stazioni. Senza testo dà le più ascoltate del paese.
  ///
  /// `paese` è il codice ISO a due lettere («IT»), vuoto per tutto il mondo.
  Future<Map<String, dynamic>> cerca({String testo = '', String paese = '', int limite = 60}) async {
    final t = testo.trim();
    final p = paese.trim().toUpperCase();
    if (p.isNotEmpty && !RegExp(r'^[A-Z]{2}$').hasMatch(p)) {
      return {'stazioni': [], 'error': 'Paese non valido.'};
    }
    final quante = limite.clamp(1, 200);
    final chiave = '$t|$p|$quante';
    final copia = _copie[chiave];
    if (copia != null && DateTime.now().difference(copia.quando) < validita) {
      return {'stazioni': copia.stazioni, 'error': ''};
    }

    final domanda = <String, String>{
      'hidebroken': 'true',
      'order': 'clickcount',
      'reverse': 'true',
      'limit': '$quante',
      if (t.isNotEmpty) 'name': t,
      if (p.isNotEmpty) 'countrycode': p,
    };
    try {
      final testoRisposta = await _prendi('/json/stations/search', domanda);
      final stazioni = stazioniDaJson(testoRisposta);
      _copie[chiave] = (quando: DateTime.now(), stazioni: stazioni);
      if (_copie.length > 50) _copie.remove(_copie.keys.first);
      return {'stazioni': stazioni, 'error': ''};
    } catch (e) {
      print('[MINERVA][RADIO][WARN] Ricerca non riuscita: $e');
      return {'stazioni': [], 'error': 'Il catalogo delle radio non risponde. Riprova fra poco.'};
    }
  }

  Future<String> _prendi(String percorso, Map<String, String> domanda) async {
    Object? ultimoErrore;
    for (var i = 0; i < server.length; i++) {
      final quale = (_buono + i) % server.length;
      final u = Uri.parse('${server[quale]}$percorso').replace(queryParameters: domanda);
      final c = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6)
        ..userAgent = agente;
      try {
        final req = await c.getUrl(u);
        final res = await req.close().timeout(const Duration(seconds: 12));
        if (res.statusCode != 200) {
          throw HttpException('risposta ${res.statusCode}', uri: u);
        }
        final testo = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 12));
        _buono = quale;
        return testo;
      } catch (e) {
        ultimoErrore = e;
      } finally {
        c.close(force: true);
      }
    }
    throw ultimoErrore ?? StateError('nessun server');
  }
}

/// Le stazioni, ridotte a quello che serve per sceglierne una e ascoltarla.
///
/// Si scartano quelle senza un indirizzo http o https: il lettore non
/// saprebbe cosa farne, e un `file://` o un `javascript:` in un elenco che
/// viene da fuori non deve arrivare a nessun lettore.
List<Map<String, dynamic>> stazioniDaJson(String testo) {
  final d = jsonDecode(testo);
  if (d is! List) return const [];
  final fuori = <Map<String, dynamic>>[];
  final visti = <String>{};
  for (final s in d) {
    if (s is! Map) continue;
    final id = '${s['stationuuid'] ?? ''}';
    final nome = '${s['name'] ?? ''}'.trim();
    var url = '${s['url_resolved'] ?? ''}'.trim();
    if (url.isEmpty) url = '${s['url'] ?? ''}'.trim();
    final u = Uri.tryParse(url);
    if (id.isEmpty || nome.isEmpty || u == null) continue;
    if (u.scheme != 'http' && u.scheme != 'https') continue;
    // La stessa radio compare spesso due volte (un indirizzo http e uno
    // https): se ne tiene una, la prima, che è la più ascoltata.
    final doppione = '${nome.toLowerCase()}|${s['countrycode'] ?? ''}';
    if (!visti.add(doppione)) continue;
    final tag = '${s['tags'] ?? ''}'
        .split(',')
        .map((x) => x.trim())
        .where((x) => x.isNotEmpty)
        .take(3)
        .toList();
    fuori.add({
      'id': id,
      'nome': nome.length > 80 ? nome.substring(0, 80) : nome,
      'url': url,
      'paese': '${s['countrycode'] ?? ''}',
      'tag': tag,
      'codec': '${s['codec'] ?? ''}',
      'bitrate': s['bitrate'] is num ? (s['bitrate'] as num).toInt() : 0,
    });
  }
  return fuori;
}
