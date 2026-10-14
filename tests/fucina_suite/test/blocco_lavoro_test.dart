import 'dart:convert';
import 'dart:io';
import 'package:minervad/services/fucina/blocco_lavoro.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('fucina-lock-'));
  tearDown(() => tmp.deleteSync(recursive: true));
  test('due istanze nello stesso processo non condividono la cache', () async {
    final a = await BloccoLavoro.prendi(tmp.path);
    try {
      await expectLater(
        BloccoLavoro.prendi(tmp.path),
        throwsA(isA<FileSystemException>()),
      );
    } finally {
      await a.chiudi();
    }
    final b = await BloccoLavoro.prendi(tmp.path);
    await b.chiudi();
  });
  test('un alias della cartella non aggira il blocco', () async {
    final cache = Directory('${tmp.path}/cache')..createSync();
    Link('${tmp.path}/alias').createSync(cache.path);
    final a = await BloccoLavoro.prendi(cache.path);
    try {
      await expectLater(
        BloccoLavoro.prendi('${tmp.path}/alias'),
        throwsA(isA<FileSystemException>()),
      );
    } finally {
      await a.chiudi();
    }
  });
  test(
    'daemon morto con figlio vivo: cache bloccata dal segnale persistente',
    () async {
      final script = File('${tmp.path}/worker.dart')
        ..writeAsString('''
import 'dart:io';
import 'package:minervad/services/fucina/blocco_lavoro.dart';
Future<void> main(List<String> a) async {
  await BloccoLavoro.prendi(a[0]);
  final child = await Process.start('/usr/bin/sleep', ['20'], mode: ProcessStartMode.detached);
  print(child.pid);
  exit(0); // morte senza chiusura, come un crash del daemon
}
''');
      final cache = '${tmp.path}/cache';
      final r = await Process.run(Platform.resolvedExecutable, [
        '--packages=${File('.dart_tool/package_config.json').absolute.path}',
        script.path,
        cache,
      ]).timeout(const Duration(seconds: 10));
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final child = int.parse('${r.stdout}'.trim());
      try {
        expect((await Process.run('kill', ['-0', '$child'])).exitCode, 0);
        await expectLater(
          BloccoLavoro.prendi(cache),
          throwsA(
            isA<FileSystemException>().having(
              (e) => e.message,
              'recupero',
              contains('non è stato chiuso'),
            ),
          ),
        );
        expect(File('$cache/.lavoro-attivo.json').existsSync(), isTrue);
      } finally {
        Process.killPid(child, ProcessSignal.sigkill);
      }
      // L'uscita del figlio non autorizza la rimozione automatica del segnale.
      await expectLater(
        BloccoLavoro.prendi(cache),
        throwsA(isA<FileSystemException>()),
      );
    },
  );
  test(
    'un processo indipendente contende il lock POSIX e lo rilascia morendo',
    () async {
      final p = await Process.start('python3', [
        '-c',
        'import fcntl,sys; f=open(sys.argv[1],"a"); fcntl.lockf(f,fcntl.LOCK_EX|fcntl.LOCK_NB); print("ready",flush=True); sys.stdin.readline()',
        '${tmp.path}/.lavoro.lock',
      ]);
      expect(
        await p.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first,
        'ready',
      );
      try {
        await expectLater(
          BloccoLavoro.prendi(tmp.path),
          throwsA(isA<FileSystemException>()),
        );
      } finally {
        p.kill();
        await p.exitCode;
      }
      final b = await BloccoLavoro.prendi(tmp.path);
      await b.chiudi();
    },
  );
}
