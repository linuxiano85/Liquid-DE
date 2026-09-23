import 'dart:convert';
import 'package:minervad/terminale/emulatore.dart';
import 'package:minervad/terminale/blocchi_automatici.dart';
import 'package:test/test.dart';

void main() {
  late Emulatore e;
  late List<Map<String, dynamic>> eventi;
  void scrivi(String s) => e.scrivi(utf8.encode(s));
  void marca(String tipo, {String comando = '', int codice = -1, String chiave = 'prova'}) =>
      scrivi('\x1b]777;minerva;$chiave;$tipo;$codice;${Uri.encodeComponent(comando)};%2Ftmp\x07');
  setUp(() {
    eventi = [];
    e = Emulatore(colonne: 80, righe: 8, scrollbackMassimo: 12)..chiaveBlocchi = 'prova';
    final registro = BlocchiAutomatici(e, eventi.add);
    e.bloccoMinerva = registro.marcatore;
  });
  test('comando, output senza prompt, esito e metadati Unicode', () {
    marca('A'); scrivi('PROMPT\r\n');
    marca('C', comando: "printf 'città 🌙'"); scrivi('città 🌙\r\n');
    marca('D', codice: 1); scrivi('NUOVO PROMPT');
    expect(eventi.last['comando'], "printf 'città 🌙'");
    expect(eventi.last['uscita'], 'città 🌙');
    expect(eventi.last['codice'], 1);
    expect(eventi.last['cartella'], '/tmp');
  });
  test('OSC generici, token errato e D ripetuto non chiudono un blocco', () {
    marca('A'); marca('C', comando: 'read');
    scrivi('\x1b]133;D;0\x07'); marca('D', chiave: 'falso');
    expect(eventi.length, 1);
    marca('D', codice: 0); marca('D', codice: 9);
    expect(eventi.length, 2); expect(eventi.last['codice'], 0);
  });
  test('output lungo limitato e dichiarato troncato', () {
    marca('A'); marca('C', comando: 'seq');
    for (var i = 0; i < 1000; i++) { scrivi('$i\r\n'); }
    marca('D', codice: 0);
    expect(eventi.last['troncato'], true);
    expect(eventi.last['uscita'], contains('999'));
    expect((eventi.last['uscita'] as String).length, lessThanOrEqualTo(16384));
  });
  test('schermo alternativo non archiviato, nemmeno nello stesso pacchetto', () {
    marca('A'); marca('C', comando: 'vim');
    scrivi('\x1b[?1049hprivato\x1b[?1049l'); marca('D', codice: 0);
    expect(eventi.last['interattivo'], true); expect(eventi.last['uscita'], '');
  });
}
