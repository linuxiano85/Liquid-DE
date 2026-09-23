import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// MeteoService — Che tempo fa, e che tempo farà.
///
/// ── CHE COSA ESCE DA QUESTO COMPUTER ───────────────────────────────────────
///
/// Due chiamate a `open-meteo.com`, e niente altro:
///
///   · **cercando una località** parte la parola scritta nel campo di ricerca;
///   · **per le previsioni** partono le coordinate scelte, arrotondate al
///     centesimo di grado — circa un chilometro, cioè il quartiere e non la
///     casa.
///
/// Non c'è chiave, non c'è account, non parte nessun identificativo del
/// computer o dell'utente. Non si usa la posizione automatica: la località la
/// sceglie chi usa il computer, e finché non ne sceglie una **non parte
/// niente**. È il motivo per cui questo servizio non ha un valore di fabbrica.
///
/// ── PERCHÉ NON SI CHIEDE PIÙ SPESSO ────────────────────────────────────────
///
/// Il tempo non cambia in un minuto, e open-meteo aggiorna i suoi dati ogni
/// quarto d'ora. Chiedere più spesso non darebbe un numero diverso: darebbe
/// solo traffico, e su un portatile anche una radio che si sveglia per niente.
class MeteoService {
  MeteoService({this.base = 'https://api.open-meteo.com/v1/forecast',
                this.geocoding = 'https://geocoding-api.open-meteo.com/v1/search'});

  final String base;
  final String geocoding;

  static const Duration validita = Duration(minutes: 15);

  Map<String, dynamic>? _ultimo;
  DateTime _quando = DateTime.fromMillisecondsSinceEpoch(0);
  String _perDove = '';

  /// Cerca una località per nome.
  Future<List<Map<String, dynamic>>> cerca(String nome, {String lingua = 'it'}) async {
    final pulito = nome.trim();
    if (pulito.length < 2) return const [];
    final u = Uri.parse('$geocoding?name=${Uri.encodeQueryComponent(pulito)}'
        '&count=8&language=$lingua&format=json');
    try {
      final testo = await _prendi(u);
      return luoghiDaJson(testo);
    } catch (e) {
      print('[MINERVA][METEO][WARN] Ricerca della località fallita: $e');
      return const [];
    }
  }

  /// Il tempo adesso e i prossimi sette giorni.
  ///
  /// `forza` salta la validità della copia in memoria: serve al pannello
  /// quando l'utente cambia località, dove aspettare un quarto d'ora
  /// vorrebbe dire mostrare il tempo del posto di prima.
  Future<Map<String, dynamic>> previsioni(double lat, double lon,
      {bool forza = false}) async {
    final dove = '${lat.toStringAsFixed(2)},${lon.toStringAsFixed(2)}';
    final fresco = DateTime.now().difference(_quando) < validita;
    if (!forza && fresco && _perDove == dove && _ultimo != null) return _ultimo!;

    final u = Uri.parse('$base?latitude=${lat.toStringAsFixed(2)}'
        '&longitude=${lon.toStringAsFixed(2)}'
        '&current=temperature_2m,relative_humidity_2m,apparent_temperature,'
        'precipitation,weather_code,wind_speed_10m,is_day'
        '&daily=weather_code,temperature_2m_max,temperature_2m_min,'
        'precipitation_probability_max'
        '&forecast_days=7&timezone=auto');
    try {
      final dati = meteoDaJson(await _prendi(u));
      _ultimo = dati;
      _quando = DateTime.now();
      _perDove = dove;
      return dati;
    } catch (e) {
      print('[MINERVA][METEO][WARN] Previsioni non riuscite: $e');
      // Si restituisce l'ultima copia buona, se c'è, con il segno che è
      // vecchia: una temperatura di un'ora fa è più utile di un trattino, ma
      // va detto che è di un'ora fa.
      if (_ultimo != null) return {..._ultimo!, 'vecchio': true};
      return {'errore': '$e'};
    }
  }

  Future<String> _prendi(Uri u) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await c.getUrl(u);
      final res = await req.close().timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        throw HttpException('risposta ${res.statusCode}', uri: u);
      }
      return await res.transform(utf8.decoder).join();
    } finally {
      c.close(force: true);
    }
  }
}

/// Le località trovate, ridotte a ciò che serve per sceglierne una.
List<Map<String, dynamic>> luoghiDaJson(String testo) {
  final d = jsonDecode(testo);
  if (d is! Map || d['results'] is! List) return const [];
  final fuori = <Map<String, dynamic>>[];
  for (final r in d['results'] as List) {
    if (r is! Map) continue;
    // Regione e stato accanto al nome, e non è decorazione: in Italia ci sono
    // otto «Castelnuovo», e senza la provincia non si sa quale scegliere.
    final pezzi = [r['admin1'], r['country']]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toList();
    fuori.add({
      'nome': '${r['name'] ?? ''}',
      'dove': pezzi.join(', '),
      'lat': (r['latitude'] as num?)?.toDouble() ?? 0,
      'lon': (r['longitude'] as num?)?.toDouble() ?? 0,
    });
  }
  return fuori;
}

/// L'uscita di open-meteo, ridotta a quello che il pannello disegna.
Map<String, dynamic> meteoDaJson(String testo) {
  final d = jsonDecode(testo);
  if (d is! Map) throw const FormatException('risposta non riconosciuta');

  final ora = d['current'];
  final giorni = d['daily'];
  final fuori = <String, dynamic>{};

  if (ora is Map) {
    fuori['adesso'] = {
      'temperatura': (ora['temperature_2m'] as num?)?.toDouble(),
      'percepita': (ora['apparent_temperature'] as num?)?.toDouble(),
      'umidita': (ora['relative_humidity_2m'] as num?)?.toDouble(),
      'pioggia': (ora['precipitation'] as num?)?.toDouble(),
      'vento': (ora['wind_speed_10m'] as num?)?.toDouble(),
      'codice': (ora['weather_code'] as num?)?.toInt() ?? -1,
      // `is_day` decide fra sole e luna: lo stesso codice «sereno» di notte
      // non è un sole, e un sole disegnato alle tre del mattino è il genere di
      // dettaglio che fa sembrare finta tutta l'interfaccia.
      'giorno': (ora['is_day'] as num?)?.toInt() != 0,
    };
  }

  if (giorni is Map && giorni['time'] is List) {
    final t = giorni['time'] as List;
    final cod = (giorni['weather_code'] as List?) ?? const [];
    final max = (giorni['temperature_2m_max'] as List?) ?? const [];
    final min = (giorni['temperature_2m_min'] as List?) ?? const [];
    final pio = (giorni['precipitation_probability_max'] as List?) ?? const [];
    final elenco = <Map<String, dynamic>>[];
    for (var i = 0; i < t.length; i++) {
      elenco.add({
        'data': '${t[i]}',
        'codice': i < cod.length ? (cod[i] as num?)?.toInt() ?? -1 : -1,
        'max': i < max.length ? (max[i] as num?)?.toDouble() : null,
        'min': i < min.length ? (min[i] as num?)?.toDouble() : null,
        'pioggia': i < pio.length ? (pio[i] as num?)?.toDouble() : null,
      });
    }
    fuori['giorni'] = elenco;
  }

  return fuori;
}

/// Che cosa vuol dire un codice WMO, e con che icona si disegna.
///
/// La tabella è quella dell'Organizzazione meteorologica mondiale, che
/// open-meteo usa senza cambiarla. I codici non coperti finiscono su «nuvoloso»
/// e non su un punto interrogativo: sono casi rari e specialistici (grandine
/// leggera, granuli di neve), e mostrare «non so» per un rovescio è peggio che
/// mostrare una nuvola.
({String icona, String it, String en}) tempoDaCodice(int c, {bool giorno = true}) {
  switch (c) {
    case 0:
      return (icona: giorno ? 'sun' : 'moon', it: 'Sereno', en: 'Clear');
    case 1:
      return (icona: giorno ? 'sun' : 'moon',
              it: 'Quasi sereno', en: 'Mainly clear');
    case 2:
      return (icona: 'nuvole-sole', it: 'Poco nuvoloso', en: 'Partly cloudy');
    case 3:
      return (icona: 'nuvole', it: 'Nuvoloso', en: 'Overcast');
    case 45:
    case 48:
      return (icona: 'nebbia', it: 'Nebbia', en: 'Fog');
    case 51:
    case 53:
    case 55:
    case 56:
    case 57:
      return (icona: 'pioggia', it: 'Pioviggine', en: 'Drizzle');
    case 61:
    case 63:
    case 80:
    case 81:
      return (icona: 'pioggia', it: 'Pioggia', en: 'Rain');
    case 65:
    case 82:
      return (icona: 'pioggia', it: 'Pioggia forte', en: 'Heavy rain');
    case 66:
    case 67:
      return (icona: 'pioggia', it: 'Pioggia gelata', en: 'Freezing rain');
    case 71:
    case 73:
    case 75:
    case 77:
    case 85:
    case 86:
      return (icona: 'neve', it: 'Neve', en: 'Snow');
    case 95:
    case 96:
    case 99:
      return (icona: 'temporale', it: 'Temporale', en: 'Thunderstorm');
    default:
      return (icona: 'nuvole', it: 'Nuvoloso', en: 'Cloudy');
  }
}
