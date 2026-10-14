import 'dart:ffi' show IntPtr, sizeOf;
import 'dart:io';
import 'package:minervad/services/controller_service.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

String bitmap(int button) {
  final bits = sizeOf<IntPtr>() * 8;
  final words = List<String>.filled(button ~/ bits + 1, '0');
  words[button ~/ bits] = (BigInt.one << (button % bits)).toRadixString(16);
  return words.reversed.join(' ');
}

void main() {
  late Directory tmp;
  late ControllerService service;
  var count = 0;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('liquid-controller-');
    count = 0;
    Directory('${tmp.path}/class/input').createSync(recursive: true);
    service = ControllerService(
      automatico: () => false,
      tipo: () => 'xbox-series',
      perPad: () => {},
      radiceSys: '${tmp.path}/class/input',
      programma: '/inesistente/inputplumber',
    );
  });
  tearDown(() async {
    await service.close();
    tmp.deleteSync(recursive: true);
  });

  void pad(
    String topology, {
    String bus = '0005',
    String vendor = '054c',
    String product = '09cc',
    String name = 'Wireless Controller',
    String keys = '',
    String axes = '0',
    String serial = 'fixture-ps4',
  }) {
    final n = count++;
    final d = Directory('${tmp.path}/devices/$topology/input/input$n');
    d.createSync(recursive: true);
    Directory('${d.path}/id').createSync();
    Directory('${d.path}/capabilities').createSync();
    Directory('${d.path}/event${20 + n}').createSync();
    for (final e in {
      'id/bustype': bus,
      'id/vendor': vendor,
      'id/product': product,
      'name': name,
      'uniq': serial,
      'capabilities/key': keys,
      'capabilities/abs': axes,
    }.entries) {
      File('${d.path}/${e.key}').writeAsStringSync(e.value);
    }
    final js = Directory('${tmp.path}/class/input/js$n')..createSync();
    Link('${js.path}/device').createSync(d.path);
  }

  test(
    'sei joydev: due fisici, due target DS5 e due sensori = due pad',
    () async {
      pad('virtual/misc/uhid/0005:054C:09CC.000E', keys: bitmap(0x130));
      pad(
        'virtual/misc/uhid/0005:057E:2009.000D',
        vendor: '057e',
        product: '2009',
        name: 'Pro Controller',
        keys: bitmap(0x130),
        serial: 'fixture-switch',
      );
      for (var n = 0; n < 2; n++) {
        pad(
          'virtual/misc/uhid/0003:054C:0CE6.00$n',
          bus: '0003',
          product: '0ce6',
          name: 'Sony Interactive Entertainment DualSense Wireless Controller',
          keys: bitmap(0x130),
          serial: 'fixture-target-$n',
        );
        pad(
          'virtual/misc/uhid/0003:054C:0CE6.00$n',
          bus: '0003',
          product: '0ce6',
          name: 'DualSense Motion Sensors',
          keys: '0',
          serial: 'fixture-imu-$n',
        );
      }
      final found = await service.inventario();
      expect(found.map((p) => p['nome']), [
        'Wireless Controller',
        'Pro Controller',
      ]);
      expect(found.map((p) => p['famiglia']), ['playstation', 'nintendo']);
      expect(found.map((p) => p['chiave']).toSet().length, 2);
    },
  );

  test(
    'un DualSense USB reale non viene confuso con il target virtuale',
    () async {
      pad(
        'pci0000:00/usb1/1-2/0003:054C:0CE6.0001',
        bus: '0003',
        product: '0ce6',
        name: 'Sony Interactive Entertainment DualSense Wireless Controller',
        keys: bitmap(0x130),
      );
      expect((await service.inventario()).single['collegamento'], 'usb');
    },
  );
  test('un DualSense Bluetooth reale UHID rimane visibile', () async {
    pad(
      'virtual/misc/uhid/0005:054C:0CE6.0001',
      product: '0ce6',
      keys: bitmap(0x130),
    );
    expect((await service.inventario()).length, 1);
  });
  test(
    'sensori Bluetooth con joydev e senza tasti non sono controller',
    () async {
      pad('virtual/misc/uhid/0005:054C:0CE6.0001', keys: '0');
      expect(await service.inventario(), isEmpty);
    },
  );
  test('target uinput di Xbox o Steam non diventa un pad aggiuntivo', () async {
    pad('virtual/input', bus: '0003', keys: bitmap(0x130));
    expect(await service.inventario(), isEmpty);
  });
  test('un joystick con BTN_TRIGGER è valido', () async {
    pad('pci0000:00/usb1/1-3/hid', bus: '0003', keys: bitmap(0x120));
    expect((await service.inventario()).length, 1);
  });
  test(
    'bitmap con parole zero non riempite: BTN_GAMEPAD non va perso',
    () async {
      pad('virtual/misc/uhid/0005:057E:2009', keys: bitmap(0x130));
      expect((await service.inventario()).length, 1);
    },
  );
  test('tasti tastiera non bastano a identificare un controller', () async {
    pad('pci0000:00/usb1/1-3/hid', keys: bitmap(30));
    expect(await service.inventario(), isEmpty);
  });
  test('capabilities corrotte non interrompono il censimento', () async {
    pad('virtual/misc/uhid/0005:057E:2009', keys: 'non-esadecimale');
    pad('virtual/misc/uhid/0005:054C:09CC', keys: bitmap(0x130));
    expect((await service.inventario()).length, 1);
  });
  test(
    'disconnessione durante la scansione non cancella gli altri pad',
    () async {
      pad('virtual/misc/uhid/0005:054C:09CC', keys: bitmap(0x130));
      Directory('${tmp.path}/class/input/js9').createSync();
      Link(
        '${tmp.path}/class/input/js9/device',
      ).createSync('${tmp.path}/sparito');
      expect((await service.inventario()).length, 1);
    },
  );

  Map<String, String> mappings(Map<String, dynamic> conf) {
    final yaml = ControllerService.profilo('Fixture', {
      'preset': 'xbox',
      'mappa': {},
      ...conf,
    });
    final names = RegExp(
      r'^  - name: (\w+)$',
      multiLine: true,
    ).allMatches(yaml).map((m) => m[1]!).toList();
    final targets = RegExp(
      r'^          button: (\w+)$',
      multiLine: true,
    ).allMatches(yaml).map((m) => m[1]!).toList();
    return {for (var n = 0; n < names.length; n++) names[n]: targets[n]};
  }

  test('posizioni Xbox: identità, nessuno scambio implicito', () {
    expect(mappings({'scambiaXO': false, 'scambiaXY': false}), isEmpty);
  });
  test(
    'lettere Nintendo: entrambe le coppie, senza toccare dorsali e menu',
    () {
      expect(mappings({'scambiaXO': true, 'scambiaXY': true}), {
        'South': 'East',
        'East': 'South',
        'West': 'North',
        'North': 'West',
      });
    },
  );
  test('vecchio scambiaXO mantiene il comportamento, non scambia X/Y', () {
    expect(mappings({'scambiaXO': true}), {'South': 'East', 'East': 'South'});
  });
  test('scambio superiore indipendente dalla coppia inferiore', () {
    expect(mappings({'scambiaXY': true}), {'West': 'North', 'North': 'West'});
  });
  test('profili PS4 e Switch indipendenti', () {
    final ps4 = mappings({'preset': 'playstation'});
    final sw = mappings({'scambiaXO': true, 'scambiaXY': true});
    expect(ps4, isEmpty);
    expect(sw.length, 4);
    expect(mappings({'preset': 'playstation'}), ps4);
  });
  test('swap si compone con rimappatura personalizzata esistente', () {
    expect(
      mappings({
        'preset': 'personalizzato',
        'mappa': {'East': 'Start'},
        'scambiaXO': true,
      }),
      {'South': 'Start', 'East': 'South'},
    );
  });
  test('tutte le combinazioni di scambio preservano i 15 tasti', () {
    for (final lower in [false, true]) {
      for (final upper in [false, true]) {
        final changed = mappings({'scambiaXO': lower, 'scambiaXY': upper});
        final targets = ControllerService.tasti
            .map((t) => changed[t] ?? t)
            .toSet();
        expect(targets, ControllerService.tasti.toSet());
      }
    }
  });
  Map<String, dynamic> profile(
    Map<String, dynamic> conf, {
    String family = 'xbox',
    List<String> digital = const [],
  }) {
    final y = loadYaml(
      ControllerService.profilo(
        'Fixture',
        {'preset': 'xbox', 'mappa': {}, ...conf},
        famiglia: family,
        grillettiDigitali: digital,
      ),
    );
    return Map<String, dynamic>.from(y as Map);
  }

  // Native events verified against hid-nintendo and hid-playstation;
  // target positions verified against InputPlumber and Chromium mappings.
  const nativeTarget = {
    'South': 0,
    'East': 1,
    'North': 2,
    'West': 3,
    'LeftBumper': 4,
    'RightBumper': 5,
    'Select': 8,
    'Start': 9,
    'LeftStick': 10,
    'RightStick': 11,
    'DPadUp': 12,
    'DPadDown': 13,
    'DPadLeft': 14,
    'DPadRight': 15,
    'Guide': 16,
  };
  for (final family in ['nintendo', 'playstation', 'xbox']) {
    for (final lower in [false, true]) {
      for (final upper in [false, true]) {
        test(
          '$family: tutti i 15 pulsanti, basso/destra=$lower sinistra/alto=$upper',
          () {
            final p = profile({
              'scambiaXO': lower,
              'scambiaXY': upper,
            }, family: family);
            final changed = <String, String>{};
            for (final row in p['mapping']) {
              changed[row['source_event']['gamepad']['button']] =
                  row['target_events'][0]['gamepad']['button'];
            }
            for (final logical in ControllerService.tasti) {
              // Physical left/top are encoded differently by Nintendo.
              final raw = family == 'nintendo'
                  ? logical
                  : switch (logical) {
                      'West' => 'North',
                      'North' => 'West',
                      _ => logical,
                    };
              var expected = switch (logical) {
                'West' => 2,
                'North' => 3,
                _ => nativeTarget[logical]!,
              };
              if (lower && expected < 2) expected = 1 - expected;
              if (upper && (expected == 2 || expected == 3))
                expected = 5 - expected;
              expect(
                nativeTarget[changed[raw] ?? raw],
                expected,
                reason: 'physical $logical',
              );
            }
          },
        );
      }
    }
  }
  test(
    'Nintendo ZL/ZR digitali diventano assi senza perdere pressione/rilascio',
    () {
      final p = profile(
        {},
        family: 'nintendo',
        digital: ['LeftTrigger', 'RightTrigger'],
      );
      for (final side in ['LeftTrigger', 'RightTrigger']) {
        final rows = (p['mapping'] as List).where(
          (r) => r['source_event']['gamepad']['button'] == side,
        );
        expect(rows.length, 1);
        expect(rows.single['target_events'], [
          {
            'gamepad': {'button': side},
          },
          {
            'gamepad': {
              'trigger': {'name': side},
            },
          },
        ]);
      }
    },
  );
  test(
    'grilletti analogici PS4 non vengono sovrascritti da eventi digitali',
    () {
      expect(profile({}, family: 'playstation')['mapping'], isEmpty);
    },
  );
  test('la mappa personalizzata usa la posizione sinistra su PS4 e Switch', () {
    for (final family in ['playstation', 'nintendo']) {
      final p = profile({
        'preset': 'personalizzato',
        'mappa': {'West': 'Start'},
      }, family: family);
      final raw = family == 'nintendo' ? 'West' : 'North';
      final row = (p['mapping'] as List).singleWhere(
        (r) => r['source_event']['gamepad']['button'] == raw,
      );
      expect(row['target_events'], [
        {
          'gamepad': {'button': 'Start'},
        },
      ]);
    }
  });
  test('nomi dei dispositivi con virgolette e newline restano dati YAML', () {
    final y = loadYaml(
      ControllerService.profilo('Pad "Test"\nnext', {
        'preset': 'xbox',
        'mappa': {},
      }),
    );
    expect(y['name'], 'Liquid DE — Pad "Test"\nnext');
    expect(y['mapping'], isEmpty);
  });
  test('inventario distingue grilletti digitali e assi analogici', () async {
    pad(
      'virtual/misc/uhid/0005:057E:2009',
      vendor: '057e',
      keys: bitmap(0x138),
      serial: 'digital',
    );
    pad(
      'virtual/misc/uhid/0005:054C:09CC',
      keys: bitmap(0x138),
      axes: bitmap(2),
      serial: 'analog',
    );
    final found = await service.inventario();
    expect(found.first['grillettiDigitali'], ['LeftTrigger']);
    expect(found.last['grillettiDigitali'], isEmpty);
  });
}
