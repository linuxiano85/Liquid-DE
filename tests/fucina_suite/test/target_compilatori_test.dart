import 'dart:io';
import 'package:minervad/services/fucina/target_compilatori.dart';
import 'package:minervad/services/fucina/rilievo.dart';
import 'package:minervad/services/fucina_service.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  Future<void> stub(String nome, String body) async {
    final f = File('${tmp.path}/$nome')
      ..writeAsStringSync('#!/usr/bin/python3\n$body\n');
    expect((await Process.run('chmod', ['755', f.path])).exitCode, 0);
  }

  TargetCompilatori sonda({Duration limite = const Duration(seconds: 1)}) =>
      TargetCompilatori(ambiente: {'PATH': tmp.path}, limite: limite);
  void scrivi(String path, String testo) {
    final f = File('${tmp.path}/$path')..createSync(recursive: true);
    f.writeAsStringSync(testo);
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('fucina-target-');
  });
  tearDown(() async => tmp.delete(recursive: true));

  test('interpreta target e tuning GCC senza esportare il testo grezzo', () {
    final r = TargetCompilatori.interpreta(
      'gcc',
      ' -march=  haswell\n -mtune=  generic\n/home/privata\n',
    );
    expect(r['rilevato'], isTrue);
    expect(r['cpu'], 'haswell');
    expect(r['tuning'], 'generic');
    expect('$r', isNot(contains('/home/privata')));
  });
  test('interpreta Clang e rifiuta token non validi o native non risolto', () {
    expect(
      TargetCompilatori.interpreta(
        'clang',
        '"/home/privata/clang" "-target-cpu" "znver4"',
      )['cpu'],
      'znver4',
    );
    for (final s in [
      '"-target-cpu" "/home/privata"',
      '"-target-cpu" "native"',
      '"-target-cpu" "bad name"',
      '',
    ]) {
      expect(TargetCompilatori.interpreta('clang', s)['rilevato'], isFalse);
    }
    expect(
      TargetCompilatori.interpreta('gcc', '-march= native\n')['rilevato'],
      isFalse,
    );
  });
  test('sonde con argomenti fissi, stdout e stderr, senza compilazione', () async {
    await stub(
      'gcc',
      "import sys\nassert sys.argv[1:] == ['-Q','--help=target','-march=native','-mtune=native']\nprint(' -march= haswell\\n -mtune= haswell')",
    );
    await stub(
      'clang',
      "import sys\nassert sys.argv[1:] == ['-###','-march=native','-x','c','-c','/dev/null','-o','/dev/null']\nsys.stderr.write('\"-target-cpu\" \"haswell\"')",
    );
    final r = await sonda().leggi({'livelloX86': 'v3'});
    expect(r.map((m) => m['cpu']), ['haswell', 'haswell']);
    expect(tmp.listSync().whereType<File>().length, 2);
  });
  test(
    'compilatore assente e uscita non riuscita restano non verificati',
    () async {
      await stub('gcc', "import sys\nprint(' -march= haswell')\nsys.exit(1)");
      final r = await sonda().leggi({'livelloX86': 'v3'});
      expect(r.every((m) => m['rilevato'] == false), isTrue);
    },
  );
  test(
    'diagnostica eccessiva non cresce senza limite né diventa un successo',
    () async {
      await stub(
        'gcc',
        "import sys\nsys.stdout.write(' -march= haswell\\n'+'X'*(4*1024*1024))",
      );
      final r = await sonda().leggi({'livelloX86': 'v3'});
      expect(r.first['rilevato'], isFalse);
      expect(r.first['messaggio'], contains('limite'));
    },
  );
  test(
    'timeout termina il processo della sonda senza bloccare la risposta',
    () async {
      await stub(
        'gcc',
        "import os,time\nopen('${tmp.path}/pid','w').write(str(os.getpid()))\ntime.sleep(30)",
      );
      final timer = Stopwatch()..start();
      final r = await sonda(
        limite: const Duration(milliseconds: 200),
      ).leggi({'livelloX86': 'v3'});
      expect(r.first['rilevato'], isFalse);
      expect(r.first['messaggio'], contains('tempo limite'));
      expect(timer.elapsed, lessThan(const Duration(seconds: 3)));
      final pid = int.parse(File('${tmp.path}/pid').readAsStringSync());
      expect(Directory('/proc/$pid').existsSync(), isFalse);
    },
  );
  test('piattaforma non x86 non esegue le sonde x86', () async {
    await stub('gcc', "open('${tmp.path}/avviato','w').write('errore')");
    expect(await sonda().leggi({'livelloX86': ''}), isEmpty);
    expect(File('${tmp.path}/avviato').existsSync(), isFalse);
  });

  test(
    'richieste simultanee condividono le due sonde senza moltiplicare processi',
    () async {
      await stub(
        'gcc',
        "import time\nopen('${tmp.path}/conta-gcc','a').write('1')\ntime.sleep(.1)\nprint(' -march= haswell')",
      );
      await stub(
        'clang',
        "import time\nopen('${tmp.path}/conta-clang','a').write('1')\ntime.sleep(.1)\nprint('\"-target-cpu\" \"haswell\"')",
      );
      final t = sonda();
      final risultati = await Future.wait([
        for (var i = 0; i < 5; i++) t.leggi({'livelloX86': 'v3'}),
      ]);
      expect(
        risultati.every((r) => r.every((v) => v['rilevato'] == true)),
        isTrue,
      );
      expect(File('${tmp.path}/conta-gcc').readAsStringSync(), '1');
      expect(File('${tmp.path}/conta-clang').readAsStringSync(), '1');
    },
  );

  test(
    'backend rifiuta native con flag non uniformi senza chiedere root',
    () async {
      const flags =
          'lm cmov cx8 fpu fxsr mmx syscall sse sse2 cx16 lahf_lm popcnt sse4_1 sse4_2 ssse3';
      scrivi(
        'proc/cpuinfo',
        'processor: 0\nflags: $flags avx\n\nprocessor: 1\nflags: $flags\n',
      );
      scrivi('proc/sys/kernel/osrelease', '7.2.9-distro\n');
      scrivi('proc/modules', '');
      var rootCalls = 0;
      final s = FucinaService(
        radice: (_, _) async {
          rootCalls++;
          return {'ok': true};
        },
        lavoro: '${tmp.path}/cache',
        statoDir: '${tmp.path}/stato',
        nuovoRilevatore: (racconta, alias) =>
            Rilevatore(radice: tmp.path, ambiente: {'PATH': ''}, nuclei: 2),
      );
      final r = await s.ricetta({
        'versione': '7.2.9',
        'nome': 'test',
        'nativo': true,
      });
      expect(r['ok'], isFalse);
      expect(r['errore'], contains('non sono uniformi'));
      expect(rootCalls, 0);
      expect(Directory('${tmp.path}/cache').existsSync(), isFalse);
    },
  );
}
