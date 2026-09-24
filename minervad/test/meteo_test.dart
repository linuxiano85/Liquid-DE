import 'dart:io';

import 'package:test/test.dart';
import 'package:minervad/services/meteo_service.dart';

/// Le risposte vere di open-meteo, copiate da questa macchina il 10 agosto
/// 2026. Provare su un JSON inventato da noi dimostrerebbe solo che sappiamo
/// leggere ciò che abbiamo scritto.
const _vereCoordinate = '''
{"results":[{"id":3172394,"name":"Napoli","latitude":40.85216,
"longitude":14.26811,"country_code":"IT","timezone":"Europe/Rome",
"country":"Italia","admin1":"Campania","admin2":"Provincia di Napoli"}]}''';

const _vereMeteo = '''
{"latitude":41.875,"longitude":12.5,"timezone":"Europe/Rome",
"current":{"time":"2026-08-10T09:30","temperature_2m":29.5,
"relative_humidity_2m":41,"apparent_temperature":30.2,"precipitation":0.0,
"weather_code":0,"wind_speed_10m":7.4,"is_day":1},
"daily":{"time":["2026-08-10","2026-08-11"],"weather_code":[0,61],
"temperature_2m_max":[33.1,29.4],"temperature_2m_min":[20.2,19.8],
"precipitation_probability_max":[0,65]}}''';

/// Con le ore e l'alba, copiata il 24 settembre 2026 (Roma, come sopra).
const _vereOre = '''
{"latitude":41.875,"longitude":12.5,"timezone":"Europe/Rome",
"current":{"time":"2026-09-24T17:45","temperature_2m":24.7,
"relative_humidity_2m":60,"apparent_temperature":25.4,"precipitation":0.0,
"weather_code":3,"wind_speed_10m":10.2,"is_day":1},
"hourly":{"time":["2026-09-24T17:00","2026-09-24T18:00","2026-09-24T19:00",
"2026-09-24T20:00"],"temperature_2m":[25.2,24.5,23.8,23.0],
"weather_code":[3,3,3,3],"precipitation_probability":[0,0,0,0],
"is_day":[1,1,1,0]},
"daily":{"time":["2026-09-24","2026-09-25"],"weather_code":[3,3],
"temperature_2m_max":[26.4,28.4],"temperature_2m_min":[13.8,19.1],
"precipitation_probability_max":[0,28],
"sunrise":["2026-09-24T06:59","2026-09-25T07:00"],
"sunset":["2026-09-24T19:04","2026-09-25T19:02"]}}''';

void main() {
  group('meteo — leggere le risposte vere', () {
    test('una località si riduce a nome, dove, e due coordinate', () {
      final l = luoghiDaJson(_vereCoordinate);
      expect(l, hasLength(1));
      expect(l.first['nome'], 'Napoli');
      // Regione e stato accanto al nome: in Italia ci sono otto
      // «Castelnuovo», e senza non si sa quale scegliere.
      expect(l.first['dove'], 'Campania, Italia');
      expect(l.first['lat'], closeTo(40.85, 0.01));
    });

    test('una risposta senza risultati non è un errore', () {
      expect(luoghiDaJson('{"generationtime_ms":0.1}'), isEmpty);
    });

    test('il tempo adesso arriva intero', () {
      final m = meteoDaJson(_vereMeteo);
      final a = m['adesso'] as Map;
      expect(a['temperatura'], 29.5);
      expect(a['umidita'], 41);
      expect(a['vento'], 7.4);
      expect(a['codice'], 0);
      expect(a['giorno'], isTrue, reason: 'è mezzogiorno: sole, non luna');
    });

    test('i giorni arrivano in fila, con massime e minime', () {
      final g = meteoDaJson(_vereMeteo)['giorni'] as List;
      expect(g, hasLength(2));
      expect(g[0]['max'], 33.1);
      expect(g[1]['codice'], 61);
      expect(g[1]['pioggia'], 65);
    });

    test('le ore della giornata, con l\'ora del posto e la notte', () {
      final o = meteoDaJson(_vereOre)['ore'] as List;
      expect(o, hasLength(4));
      expect(o.first['ora'], '17:00');
      expect(o.first['temperatura'], 25.2);
      expect(o.first['codice'], 3);
      expect(o.first['pioggia'], 0);
      // Alle venti è già buio: la luna, non il sole.
      expect(o.last['giorno'], isFalse);
    });

    test('l\'alba e il tramonto, come ore', () {
      final g = meteoDaJson(_vereOre)['giorni'] as List;
      expect(g.first['alba'], '06:59');
      expect(g.first['tramonto'], '19:04');
    });

    test('una risposta monca non fa cadere niente', () {
      // Capita: open-meteo risponde 200 con i soli campi che ha.
      final m = meteoDaJson('{"latitude":41.9}');
      expect(m['adesso'], isNull);
      expect(m['giorni'], isNull);
      expect(m['ore'], isNull);
    });

    test('una risposta che non è JSON si lamenta invece di mentire', () {
      expect(() => meteoDaJson('<html>errore</html>'), throwsA(anything));
    });
  });

  group('meteo — i codici WMO', () {
    test('sereno di giorno è un sole, di notte una luna', () {
      // Un sole disegnato alle tre del mattino è il dettaglio che fa sembrare
      // finta tutta l'interfaccia.
      expect(tempoDaCodice(0, giorno: true).icona, 'sun');
      expect(tempoDaCodice(0, giorno: false).icona, 'moon');
    });

    test('le famiglie finiscono sull\'icona giusta', () {
      expect(tempoDaCodice(3).icona, 'nuvole');
      expect(tempoDaCodice(45).icona, 'nebbia');
      expect(tempoDaCodice(63).icona, 'pioggia');
      expect(tempoDaCodice(75).icona, 'neve');
      expect(tempoDaCodice(95).icona, 'temporale');
    });

    test('un codice sconosciuto dà una nuvola, non un punto interrogativo', () {
      // Sono casi rari e specialistici. Mostrare «non so» per un rovescio è
      // peggio che mostrare una nuvola.
      expect(tempoDaCodice(4242).icona, 'nuvole');
      expect(tempoDaCodice(-1).icona, 'nuvole');
    });

    test('ogni icona del tempo esiste davvero nel set di Minerva', () {
      // Stesso vincolo delle altre icone: un nome che `Icon.qml` non conosce
      // lascia un buco nella barra, e nessuno lo dice.
      final qml = _iconQml();
      for (final c in [0, 1, 2, 3, 45, 51, 61, 65, 71, 95, 9999]) {
        for (final giorno in [true, false]) {
          final n = tempoDaCodice(c, giorno: giorno).icona;
          expect(qml, contains('"$n":'),
                 reason: 'il codice $c chiede l\'icona "$n", che non esiste');
        }
      }
    });
  });
}

String _iconQml() {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    final f = File('${dir.path}/minerva-shell/ui/Icon.qml');
    if (f.existsSync()) return f.readAsStringSync();
    dir = dir.parent;
  }
  fail('non trovo minerva-shell/ui/Icon.qml');
}
