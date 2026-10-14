// Prove per `RadioService`, con un radio-browser finto su questo computer:
// nessuna prova dipende dalla rete.
//
//     dart run tests/radio_service_test.dart
import 'dart:convert';
import 'dart:io';
import '../minervad/lib/services/radio_service.dart';

var prove = 0;

void check(bool value, String message) {
  if (!value) throw StateError(message);
  prove++;
}

Map<String, dynamic> stazione(String id, String nome, String url, {String paese = 'IT', String tag = ''}) => {
      'stationuuid': id,
      'name': nome,
      'url': url,
      'url_resolved': url,
      'countrycode': paese,
      'tags': tag,
      'codec': 'MP3',
      'bitrate': 128,
    };

Future<void> main() async {
  // ── Dal JSON alle stazioni ──
  final elenco = jsonEncode([
    stazione('1', 'Radio Uno', 'https://uno.example/stream', tag: 'news, talk ,italiano,quarto'),
    stazione('2', 'radio uno', 'http://uno.example/stream'),
    stazione('3', 'Radio Uno', 'https://uno.example/ch', paese: 'CH'),
    stazione('4', 'Furba', 'javascript:alert(1)'),
    stazione('5', 'Locale', 'file:///etc/passwd'),
    stazione('', 'Senza id', 'https://x.example/'),
    stazione('6', '   ', 'https://x.example/'),
    {'stationuuid': '7', 'name': 'Solo url', 'url': 'https://sette.example/', 'url_resolved': ''},
  ]);
  final s = stazioniDaJson(elenco);
  final nomi = s.map((x) => '${x['id']}').toList();
  check(nomi.join(',') == '1,3,7', 'tenute solo quelle buone, una per nome e paese: $nomi');
  check((s[0]['tag'] as List).join('|') == 'news|talk|italiano', 'tre tag, puliti: ${s[0]['tag']}');
  check(s[2]['url'] == 'https://sette.example/', 'senza url_resolved si usa url');
  check(stazioniDaJson('{"non":"lista"}').isEmpty, 'una risposta strana non rompe niente');

  // ── Un server finto: il primo è spento, il secondo risponde ──
  final finto = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final richieste = <HttpRequest>[];
  finto.listen((r) {
    richieste.add(r);
    r.response.headers.contentType = ContentType.json;
    r.response.write(jsonEncode([stazione('9', 'Radio Prova', 'https://prova.example/')]));
    r.response.close();
  });
  final spento = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final portaSpenta = spento.port;
  await spento.close();

  final radio = RadioService(server: [
    'http://127.0.0.1:$portaSpenta',
    'http://127.0.0.1:${finto.port}',
  ]);
  var r = await radio.cerca(testo: 'prova', paese: 'it');
  check(r['error'] == '' && (r['stazioni'] as List).length == 1, 'il secondo server risponde: $r');
  final q = richieste.last.uri.queryParameters;
  check(richieste.last.uri.path == '/json/stations/search', 'il percorso dell\'API');
  check(q['name'] == 'prova' && q['countrycode'] == 'IT' && q['hidebroken'] == 'true',
      'la domanda: testo, paese in maiuscolo, niente stazioni rotte: $q');
  check('${richieste.last.headers.value('user-agent')}'.startsWith('LiquidDE/'),
      'Minerva si presenta col suo nome, come chiede radio-browser');

  // La stessa domanda di nuovo: dalla copia, senza rete.
  final prima = richieste.length;
  await radio.cerca(testo: 'prova', paese: 'IT');
  check(richieste.length == prima, 'la stessa ricerca non riparte');

  // Senza testo: le più ascoltate del paese, senza `name`.
  await radio.cerca(paese: 'FR');
  check(!richieste.last.uri.queryParameters.containsKey('name') &&
          richieste.last.uri.queryParameters['countrycode'] == 'FR',
      'senza testo si chiede la classifica del paese');

  r = await radio.cerca(paese: 'ITA');
  check(r['error'] != '' && (r['stazioni'] as List).isEmpty, 'un paese non valido non parte: $r');

  // Tutti spenti: un errore detto bene, non un\'eccezione.
  await finto.close(force: true);
  final muta = RadioService(server: ['http://127.0.0.1:$portaSpenta']);
  r = await muta.cerca(testo: 'qualcosa');
  check('${r['error']}'.contains('non risponde'), 'nessun server: si dice: $r');

  print('radio_service: $prove prove superate');
}
