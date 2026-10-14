import 'dart:io';
import 'dart:convert';

import 'package:minervad/services/fucina/scaffale.dart';
import 'package:minervad/services/fucina_service.dart';
import 'package:test/test.dart';

void main() {
  late Directory tana;
  late String lavoro;
  late String stato;

  setUp(() async {
    tana = await Directory.systemTemp.createTemp('fucina-cache-');
    lavoro = '${tana.path}/cache/fucina';
    stato = '${tana.path}/stato/fucina';
    await File('${tana.path}/proc/sys/kernel/osrelease').create(recursive: true)
      ..writeAsString('6.17.2-fucina-test\n');
  });

  tearDown(() async => tana.delete(recursive: true));

  test('kernel espone archivi conservati e sorgenti riutilizzabili', () async {
    final archivio = File('$lavoro/archivi/linux-6.17.2.tar.xz');
    await archivio.create(recursive: true);
    await archivio.writeAsBytes([1, 2, 3, 4]);
    await File('${archivio.path}.firma-verificata').writeAsString('sha256\n');

    final base = Directory('$lavoro/alberi/6.17.2-vanilla');
    await File('${base.path}/.fucina-pronto').create(recursive: true);
    await File('${base.path}/linux-6.17.2/Makefile').create(recursive: true);

    final scaffale = Scaffale(
      radice: '${tana.path}/',
      lavoro: lavoro,
      statoDir: stato,
    );
    final service = FucinaService(
      radice: (_, _) async => {'ok': false},
      lavoro: lavoro,
      statoDir: stato,
      scaffale: scaffale,
    );

    final risultato = await service.kernel();
    final cache = risultato['cache'] as Map<String, dynamic>;
    final archivi = cache['archivi'] as List<dynamic>;
    final alberi = cache['alberi'] as List<dynamic>;

    expect(cache['percorso'], lavoro);
    expect(archivi, hasLength(1));
    expect(archivi.single, {
      'nome': 'linux-6.17.2.tar.xz',
      'byte': 4,
      'verificato': true,
    });
    expect(alberi, hasLength(1));
    expect(alberi.single, {
      'nome': '6.17.2-vanilla',
      'versione': 'linux-6.17.2',
      'sorgentiPresenti': true,
      'pronto': true,
    });
  });

  test(
    'recupero guidato reale del servizio non chiama root né cambia sorgenti',
    () async {
      final worker = File('${tana.path}/worker.dart')
        ..writeAsString('''
import 'dart:io';
import 'package:minervad/services/fucina/blocco_lavoro.dart';
Future<void> main(List<String> a) async {
  await BloccoLavoro.prendi(a[0],tipo:'compilazione');
  exit(0);
}
''');
      final r = await Process.run(Platform.resolvedExecutable, [
        '--packages=${File('.dart_tool/package_config.json').absolute.path}',
        worker.path,
        lavoro,
      ]).timeout(const Duration(seconds: 10));
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final source = File('$lavoro/alberi/sentinella')
        ..createSync(recursive: true)
        ..writeAsStringSync('sorgenti conservati');
      var rootCalls = 0;
      final service = FucinaService(
        radice: (_, _) async {
          rootCalls++;
          return {'ok': false};
        },
        lavoro: lavoro,
        statoDir: stato,
        scaffale: Scaffale(
          radice: '${tana.path}/',
          lavoro: lavoro,
          statoDir: stato,
        ),
      );
      final info = (await service.kernel())['cache'] as Map;
      final recovery = info['recupero'] as Map;
      expect(recovery['recuperabile'], isTrue, reason: '$recovery');
      expect((await service.recuperaCache(null))['ok'], isFalse);
      expect((await service.recuperaCache('scaduto'))['ok'], isFalse);
      final marker = File('$lavoro/.lavoro-attivo.json');
      expect(jsonDecode(marker.readAsStringSync())['tipo'], 'compilazione');
      expect((await service.recuperaCache(recovery['token']))['ok'], isTrue);
      expect(marker.existsSync(), isFalse);
      expect(rootCalls, 0);
      expect(source.readAsStringSync(), 'sorgenti conservati');
      expect(
        ((await service.kernel())['cache'] as Map)['recupero']['stato'],
        'libero',
      );
    },
  );
}
