import 'dart:io';

import 'package:minervad/services/fucina/rilievo.dart';
import 'package:minervad/services/fucina_service.dart';
import 'package:test/test.dart';

void main() {
  late Directory tana;

  void preparaMacchina(String radice, String cpu) {
    File('$radice/proc/sys/kernel/osrelease')
      ..createSync(recursive: true)
      ..writeAsStringSync('6.17.2-test\n');
    File('$radice/proc/cpuinfo')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
model name : $cpu
vendor_id : GenuineIntel
flags : fpu sse sse2 avx avx2
''');
    File('$radice/proc/meminfo')
      ..createSync(recursive: true)
      ..writeAsStringSync('MemTotal: 16000000 kB\n');
  }

  FucinaService servizio({required String radice, required String stato}) =>
      FucinaService(
        lavoro: '${tana.path}/cache',
        statoDir: stato,
        radice: (verbo, argomenti) async => {'ok': true},
        nuovoRilevatore: (racconta, alias) => Rilevatore(
          radice: radice,
          ambiente: {'HOME': radice, 'PATH': ''},
          modaliasStorici: alias,
          nuclei: 4,
        ),
      );

  setUp(
    () =>
        tana = Directory.systemTemp.createTempSync('fucina-profili-servizio-'),
  );
  tearDown(() => tana.deleteSync(recursive: true));

  final scelte = <String, dynamic>{
    'tolti': <String>[],
    'aggiunti': ['xpad'],
    'scorte': ['filesystem', 'chiavette'],
    'preset': <String>[],
    'sorgente': 'vanilla',
    'versione': '6.17.2',
    'base': 'in-uso',
    'compilatore': 'clang',
    'lto': true,
    'provaVeloce': false,
    'nativo': true,
    'nome': 'anteprima',
    'autofdo': true,
    'profilo': '',
    'misura': true,
    'provaAvvio': true,
  };

  test('salva preferenze, le ricarica e segnala CPU non verificata', () async {
    final prima = '${tana.path}/pc-uno';
    final seconda = '${tana.path}/pc-due';
    final stato = '${tana.path}/stato';
    preparaMacchina(prima, 'CPU uno');
    preparaMacchina(seconda, 'CPU due');

    final servizioUno = servizio(radice: prima, stato: stato);
    final esitoSalva = await servizioUno.salvaProfilo('Clang gioco', scelte);
    expect(esitoSalva['ok'], isTrue, reason: '$esitoSalva');
    final profilo = esitoSalva['profilo'] as Map<String, dynamic>;
    expect(profilo['scelte']['versione'], isNull);
    expect(profilo['scelte']['lto'], isTrue);
    expect(profilo['scelte']['provaAvvio'], isTrue);

    final esitoStessoPc = await servizioUno.caricaProfilo(profilo['id']);
    expect(esitoStessoPc['nativoCompatibile'], isTrue);

    final servizioDue = servizio(radice: seconda, stato: stato);
    final esitoCarica = await servizioDue.caricaProfilo(profilo['id']);
    expect(esitoCarica['ok'], isTrue, reason: '$esitoCarica');
    expect(esitoCarica['nativoCompatibile'], isFalse);
    expect(esitoCarica['scelte']['nativo'], isTrue);
    expect('${esitoCarica['avvisoHardware']}', contains('CPU'));
  });

  test('rifiuta preferenze non valide senza creare un profilo', () async {
    final macchina = '${tana.path}/pc';
    final stato = '${tana.path}/stato';
    preparaMacchina(macchina, 'CPU test');
    final servizioTest = servizio(radice: macchina, stato: stato);

    final esito = await servizioTest.salvaProfilo('Test', {
      ...scelte,
      'compilatore': 'gcc',
      'lto': true,
    });
    expect(esito['ok'], isFalse);
    expect('${esito['errore']}', contains('Clang'));
    expect(await servizioTest.profili().then((r) => r['profili']), isEmpty);
  });

  test('il daemon blocca la compilazione se mancano prerequisiti', () async {
    final macchina = '${tana.path}/pc-senza-toolchain';
    final stato = '${tana.path}/stato-senza-toolchain';
    preparaMacchina(macchina, 'CPU test');
    final service = servizio(radice: macchina, stato: stato);

    final esito = await service.avvia({
      ...scelte,
      'compilatore': 'gcc',
      'lto': false,
      'autofdo': false,
    });

    expect(esito['ok'], isFalse);
    expect(esito['requisitiMancanti'], contains('make'));
    expect('${esito['errore']}', contains('pacman -S --needed'));
    expect(Directory('${tana.path}/cache/alberi').existsSync(), isFalse);
  });

  test(
    'le regole persistenti prevalgono sulle scelte temporanee della ricetta',
    () async {
      final macchina = '${tana.path}/pc-regole';
      final stato = '${tana.path}/stato-regole';
      preparaMacchina(macchina, 'CPU regole');
      File('$macchina/proc/modules')
        ..createSync(recursive: true)
        ..writeAsStringSync('snd_hda_intel 123 0 - Live 0x0\n');
      final servizioRegole = servizio(radice: macchina, stato: stato);

      expect(
        (await servizioRegole.impostaRegolaModulo('xpad', 'escludi'))['ok'],
        isTrue,
      );
      final escluso = await servizioRegole.ricetta({
        ...scelte,
        'scorte': ['controller'],
        'aggiunti': ['xpad'],
      });
      expect(escluso['ok'], isTrue, reason: '$escluso');
      expect(escluso['moduli'], isNot(contains('xpad')));

      expect(
        (await servizioRegole.impostaRegolaModulo('xpad', 'mantieni'))['ok'],
        isTrue,
      );
      final mantenuto = await servizioRegole.ricetta({
        ...scelte,
        'tolti': ['xpad'],
      });
      expect(mantenuto['ok'], isTrue, reason: '$mantenuto');
      expect(mantenuto['moduli'], contains('xpad'));
    },
  );

  test(
    'non permette di salvare l’esclusione di un modulo essenziale',
    () async {
      final macchina = '${tana.path}/pc-avvio';
      final stato = '${tana.path}/stato-avvio';
      preparaMacchina(macchina, 'CPU avvio');
      final servizioAvvio = servizio(radice: macchina, stato: stato);

      final esito = await servizioAvvio.impostaRegolaModulo(
        'usbhid',
        'escludi',
      );
      expect(esito['ok'], isFalse);
      expect('${esito['errore']}', contains('avviare'));
    },
  );
}
