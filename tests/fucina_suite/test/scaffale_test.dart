import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:minervad/services/fucina/rilievo.dart';
import 'package:minervad/services/fucina/scaffale.dart';
import 'package:minervad/services/fucina_service.dart';
import 'package:test/test.dart';

// Lo scaffale della Fucina e le due porte verso root.
//
// Quello che conta qui è un confine solo: **il kernel della distribuzione
// non si raggiunge**. Non compare nell'elenco, non si installa sopra, non si
// toglie. Le prove sotto «si rifiuta» sono quelle che valgono.
void main() {
  late Directory tana;
  late String r;
  late String lavoro;
  late String statoDir;

  void file(String rel, String testo) {
    final f = File('$r/$rel');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(testo);
  }

  setUp(() {
    tana = Directory.systemTemp.createTempSync('fucina-scaffale-');
    r = tana.path;
    lavoro = '$r/lavoro';
    statoDir = '$r/stato';
    file('proc/sys/kernel/osrelease', '6.17.2-arch1-1\n');
    // Due kernel installati: quello della distribuzione e uno nostro.
    Directory('$r/usr/lib/modules/6.17.2-arch1-1').createSync(recursive: true);
    Directory('$r/usr/lib/modules/6.17.2-fucina-vecchio')
        .createSync(recursive: true);
    file('boot/vmlinuz-6.17.2-fucina-vecchio', 'x');
    // Uno pronto in uscita, e una cartella che non è un kernel nostro.
    file('lavoro/uscita/6.17.2-fucina-nuovo/fucina.json',
        jsonEncode({'quando': '2026-09-30T08:00:00', 'moduli': 120}));
    file('lavoro/uscita/linux/fucina.json', '{}');
  });

  tearDown(() => tana.deleteSync(recursive: true));

  Scaffale scaffale() => Scaffale(radice: '$r/', lavoro: lavoro, statoDir: statoDir);

  group('il nome di un kernel nostro', () {
    test('si riconosce', () {
      expect(Scaffale.nostro('6.17.2-fucina-prova'), isTrue);
      expect(Scaffale.nostro('6.17-fucina-a'), isTrue);
      expect(Scaffale.nostro('7.0.1-fucina-gioco-2026'), isTrue);
    });

    test('e tutto il resto no', () {
      for (final n in [
        '6.17.2-arch1-1', '6.17.2-cachyos', 'linux', '', '6.17.2-fucina-',
        '6.17.2-fucina-../../etc', '6.17.2-fucina-a/b', '../6.17-fucina-a',
        '6.17.2-fucina-A', '6.17.2-fucina-a\n', 'x6.17.2-fucina-a',
      ]) {
        expect(Scaffale.nostro(n), isFalse, reason: '«$n»');
      }
    });
  });

  test('l\'elenco ha solo i nostri, pronti e installati', () async {
    final e = await scaffale().elenco();
    expect(e['inUso'], '6.17.2-arch1-1');
    final k = {for (final x in e['kernel'] as List) x['rilascio']: x};
    expect(k.keys, unorderedEquals(['6.17.2-fucina-nuovo', '6.17.2-fucina-vecchio']));
    expect(k['6.17.2-fucina-nuovo']['pronto'], isTrue);
    expect(k['6.17.2-fucina-nuovo']['moduli'], 120);
    expect(k['6.17.2-fucina-vecchio']['installato'], isTrue);
    expect(k['6.17.2-fucina-vecchio']['immagine'], isTrue);
  });

  group('la verifica al primo avvio', () {
    test('sul kernel della distribuzione non si applica, e lo dice', () async {
      final v = await scaffale().verifica();
      expect(v['applicabile'], isFalse);
      expect(v['spiega'], contains('6.17.2-arch1-1'));
    });

    test('trova i dispositivi rimasti senza driver', () async {
      file('proc/sys/kernel/osrelease', '6.17.2-fucina-nuovo\n');
      file('stato/attesi-6.17.2-fucina-nuovo.json', jsonEncode([
        {'percorso': '/pci0000:00/audio', 'modalias': 'pci:a',
         'driver': 'snd_hda_intel', 'modulo': 'snd_hda_intel'},
        {'percorso': '/pci0000:00/rete', 'modalias': 'pci:b',
         'driver': 'r8169', 'modulo': 'r8169'},
        {'percorso': '/usb1/chiavetta', 'modalias': 'usb:c',
         'driver': 'usb-storage', 'modulo': 'usb_storage'},
      ]));
      // L'audio ha ancora il driver; la rete c'è ma senza; la chiavetta non
      // c'è proprio.
      Directory('$r/sys/devices/pci0000:00/audio').createSync(recursive: true);
      Directory('$r/sys/bus/pci/drivers/snd_hda_intel').createSync(recursive: true);
      Link('$r/sys/devices/pci0000:00/audio/driver')
          .createSync('../../../bus/pci/drivers/snd_hda_intel');
      Directory('$r/sys/devices/pci0000:00/rete').createSync(recursive: true);

      final v = await scaffale().verifica();
      expect(v['applicabile'], isTrue);
      expect(v['aPosto'], 1);
      expect((v['orfani'] as List).single['modulo'], 'r8169');
      expect((v['assenti'] as List).single['modulo'], 'usb_storage');
    });
  });

  group('AutoFDO: lo scaffale sa chi è pronto al profilo', () {
    test('dal vmlinux messo da parte e dal profilo accanto', () async {
      file('lavoro/profili/6.17.2-fucina-nuovo/vmlinux', 'V');
      file('lavoro/uscita/6.17.2-fucina-nuovo-afdo/fucina.json', jsonEncode({
        'scelte': {'profilo': '6.17.2-fucina-nuovo'},
      }));
      var k = {
        for (final x in (await scaffale().elenco())['kernel'] as List)
          x['rilascio']: x,
      };
      expect(k['6.17.2-fucina-nuovo']['prontoAlProfilo'], isTrue);
      expect(k['6.17.2-fucina-nuovo']['profilo'], isFalse);
      expect(k['6.17.2-fucina-vecchio']['prontoAlProfilo'], isFalse);
      expect(k['6.17.2-fucina-nuovo-afdo']['colProfiloDi'], '6.17.2-fucina-nuovo');
      file('lavoro/profili/6.17.2-fucina-nuovo/autofdo.prof', 'P');
      k = {
        for (final x in (await scaffale().elenco())['kernel'] as List)
          x['rilascio']: x,
      };
      expect(k['6.17.2-fucina-nuovo']['profilo'], isTrue);
    });
  });

  group('AutoFDO: registrare il profilo', () {
    const nostro = '6.17.2-fucina-nuovo';
    late List<List<Object>> chiesti;
    late List<List<String>> lanciati;

    FucinaService servizio({bool lbr = true}) {
      chiesti = [];
      lanciati = [];
      file('proc/cpuinfo', 'vendor_id\t: GenuineIntel\nflags\t\t: fpu lm\n');
      if (lbr) file('sys/bus/event_source/devices/cpu/caps/branches', '32\n');
      return FucinaService(
        lavoro: lavoro,
        statoDir: statoDir,
        scaffale: scaffale(),
        nuovoRilevatore: (racconta) =>
            Rilevatore(radice: r, ambiente: {'HOME': '$r/casa'}, nuclei: 4),
        radice: (verbo, argomenti) async {
          chiesti.add([verbo, argomenti]);
          return {
            'ok': true,
            'uscita': utf8.encode(
                'fatto ${FucinaService.cartellaRegistrazioni}/$nostro.data\n'),
          };
        },
        esegui: (e, a) async {
          lanciati.add([e, ...a]);
          final o = a.indexOf('-o');
          if (o >= 0) File(a[o + 1]).writeAsStringSync('$e\n');
          return ProcessResult(0, 0, '', '');
        },
      );
    }

    setUp(() {
      file('proc/sys/kernel/osrelease', '$nostro\n');
      file('lavoro/profili/$nostro/vmlinux', 'VMLINUX');
    });

    test('registra da root col tipo di processore, poi converte come te',
        () async {
      final s = servizio();
      final e = await s.profila(nostro, 10);
      expect(e['ok'], isTrue, reason: '$e');
      expect(chiesti.single, ['fucina-profila', ['600', 'intel']]);
      expect(lanciati.single, [
        'llvm-profgen', '--kernel', '--binary=$lavoro/profili/$nostro/vmlinux',
        '--perfdata=${FucinaService.cartellaRegistrazioni}/$nostro.data',
        '-o', '$lavoro/profili/$nostro/autofdo.prof.nuovo',
      ]);
      expect(File('$lavoro/profili/$nostro/autofdo.prof').readAsStringSync(),
          'llvm-profgen\n');
      expect(e['sommato'], isFalse);
    });

    test('la seconda volta il profilo nuovo si somma a quello di prima',
        () async {
      file('lavoro/profili/$nostro/autofdo.prof', 'VECCHIO');
      final s = servizio();
      final e = await s.profila(nostro, 5);
      expect(e['ok'], isTrue, reason: '$e');
      expect(e['sommato'], isTrue);
      expect(lanciati.last.take(4),
          ['llvm-profdata', 'merge', '--sample', '--extbinary']);
      expect(File('$lavoro/profili/$nostro/autofdo.prof').readAsStringSync(),
          'llvm-profdata\n');
      expect(File('$lavoro/profili/$nostro/autofdo.prof.nuovo').existsSync(),
          isFalse);
    });

    test('i minuti restano fra 1 e 60', () async {
      final s = servizio();
      await s.profila(nostro, 999);
      expect((chiesti.single[1] as List).first, '3600');
    });

    test('solo avviati su quel kernel', () async {
      file('proc/sys/kernel/osrelease', '6.17.2-arch1-1\n');
      final e = await servizio().profila(nostro, 10);
      expect(e['ok'], isFalse);
      expect(e['errore'], contains('Riavvia'));
      expect(chiesti, isEmpty);
    });

    test('solo su un kernel pronto al profilo', () async {
      File('$lavoro/profili/$nostro/vmlinux').deleteSync();
      final e = await servizio().profila(nostro, 10);
      expect(e['ok'], isFalse);
      expect(e['errore'], contains('non è pronto al profilo'));
      expect(chiesti, isEmpty);
    });

    test('se il processore non ha un registro dei salti, non si chiede la '
        'password per niente', () async {
      final e = await servizio(lbr: false).profila(nostro, 10);
      expect(e['ok'], isFalse);
      expect(e['errore'], contains('non si può registrare'));
      expect(chiesti, isEmpty);
    });

    test('un nome che non è nostro non arriva a root', () async {
      final s = servizio();
      for (final n in ['6.17.2-arch1-1', '../x', null]) {
        expect((await s.profila(n, 10))['ok'], isFalse);
      }
      expect(chiesti, isEmpty);
    });
  });

  group('le due porte verso root', () {
    late List<List<Object>> chiesti;

    FucinaService servizio() {
      chiesti = [];
      return FucinaService(
        lavoro: lavoro,
        statoDir: statoDir,
        scaffale: scaffale(),
        radice: (verbo, argomenti) async {
          chiesti.add([verbo, argomenti]);
          return {'ok': true, 'uscita': utf8.encode('nota: fatto\n')};
        },
      );
    }

    test('installa un kernel pronto passando il nome e la SUA cartella',
        () async {
      final s = servizio();
      final e = await s.installa('6.17.2-fucina-nuovo');
      expect(e['ok'], isTrue);
      expect(e['note'], ['nota: fatto']);
      expect(chiesti.single[0], 'fucina-installa');
      expect(chiesti.single[1],
          ['$lavoro/uscita/6.17.2-fucina-nuovo', '6.17.2-fucina-nuovo']);
    });

    test('non installa un nome che non è nostro, né uno non pronto', () async {
      final s = servizio();
      for (final n in ['6.17.2-arch1-1', '../../etc', '6.17.2-fucina-vecchio',
                       null, 42]) {
        final e = await s.installa(n);
        expect(e['ok'], isFalse, reason: '$n');
      }
      expect(chiesti, isEmpty, reason: 'root non deve nemmeno sentirne parlare');
    });

    test('non toglie il kernel in uso, né quello della distribuzione',
        () async {
      final s = servizio();
      expect((await s.togli('6.17.2-arch1-1'))['ok'], isFalse);
      file('proc/sys/kernel/osrelease', '6.17.2-fucina-vecchio\n');
      final e = await s.togli('6.17.2-fucina-vecchio');
      expect(e['ok'], isFalse);
      expect(e['errore'], contains('stai usando'));
      expect(chiesti, isEmpty);
    });

    test('toglie uno dei nostri, per nome', () async {
      final s = servizio();
      expect((await s.togli('6.17.2-fucina-vecchio'))['ok'], isTrue);
      expect(chiesti.single, ['fucina-togli', ['6.17.2-fucina-vecchio']]);
    });

    test('mentre si installa non si può compilare: riscriverebbe i file',
        () async {
      final radiceLenta = Completer<Map<String, dynamic>>();
      final s = FucinaService(
        lavoro: lavoro,
        statoDir: statoDir,
        scaffale: scaffale(),
        radice: (_, _) => radiceLenta.future,
      );
      final installa = s.installa('6.17.2-fucina-nuovo');
      final avvia = await s.avvia({'nome': 'nuovo', 'versione': '6.17.2'});
      expect(avvia['ok'], isFalse);
      expect(avvia['errore'], contains('installazione'));
      final seconda = await s.installa('6.17.2-fucina-nuovo');
      expect(seconda['ok'], isFalse);
      radiceLenta.complete({'ok': true, 'uscita': <int>[]});
      expect((await installa)['ok'], isTrue);
    });

    test('un kernel che in QEMU non è partito non si installa', () async {
      file('lavoro/uscita/6.17.2-fucina-nuovo/fucina.json', jsonEncode({
        'quando': '2026-10-01T08:00:00',
        'provaAvvio': {'ok': false, 'perche': 'panico'},
      }));
      final s = servizio();
      final e = await s.installa('6.17.2-fucina-nuovo');
      expect(e['ok'], isFalse);
      expect(e['errore'], contains('QEMU'));
      expect(chiesti, isEmpty);
    });

    test('la password annullata non è un guasto', () async {
      final s = FucinaService(
        lavoro: lavoro,
        statoDir: statoDir,
        scaffale: scaffale(),
        radice: (_, _) async =>
            {'ok': false, 'annullato': true, 'error': 'Annullato.'},
      );
      final e = await s.togli('6.17.2-fucina-vecchio');
      expect(e['ok'], isFalse);
      expect(e['annullato'], isTrue);
    });
  });
}

