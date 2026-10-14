import 'dart:convert';
import 'dart:io';
import 'package:minervad/services/fucina/blocco_lavoro.dart';
import 'package:minervad/services/fucina/processi_lavoro.dart';
import 'package:test/test.dart';

class ProcFixture extends ProcessiLavoro {
  bool forza = false;
  bool? esistenza;
  ProcFixture(String path) : super(proc: path);
  @override
  Future<String> spazioPid() async => 'pid-fixture';
  @override
  Future<bool?> gruppoEsiste(int gruppo) async {
    if (forza) return esistenza;
    await for (final d in Directory(proc).list()) {
      final n = int.tryParse(d.path.split('/').last);
      if (n == null) continue;
      final p = await leggi(n);
      if (p?['gruppo'] == gruppo) return true;
    }
    return false;
  }
}

void main() {
  late Directory tmp;
  late String cache;
  late ProcFixture proc;
  late File marker;
  late Map<String, dynamic> dati;
  void scrivi(String path, String data) {
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(data);
  }

  void processo(
    int n, {
    String nome = 'sleep',
    String state = 'S',
    int? group,
    String start = '10',
  }) {
    final fields = List.filled(22, '0');
    fields[0] = state;
    fields[2] = '${group ?? n}';
    fields[3] = '${group ?? n}';
    fields[19] = start;
    scrivi('${proc.proc}/$n/stat', '$n ($nome) ${fields.join(' ')}\n');
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('fucina-recupero-');
    cache = '${tmp.path}/cache';
    Directory(cache).createSync();
    proc = ProcFixture('${tmp.path}/proc');
    scrivi('${proc.proc}/sys/kernel/random/boot_id', 'boot-attuale\n');
    marker = File('$cache/.lavoro-attivo.json');
    dati = {
      'versione': 2,
      'id': 'A',
      'boot': 'boot-attuale',
      'spazioPid': 'pid-fixture',
      'pid': 99999,
      'inizio': '9',
      'tipo': 'compilazione',
      'fase': 'nessun-processo',
      'processi': [],
    };
  });
  tearDown(() => tmp.deleteSync(recursive: true));
  void salva() => marker.writeAsStringSync(jsonEncode(dati));

  test(
    'stat gestisce spazi e parentesi nel nome, starttime e gruppo',
    () async {
      processo(40, nome: 'a (b) c)', group: 50, start: '123456');
      final p = await proc.leggi(40);
      expect(p!['nome'], 'a (b) c)');
      expect(p['gruppo'], 50);
      expect(p['inizio'], '123456');
    },
  );
  test('cache assente è libera senza crearla', () async {
    final absent = '$cache/assente';
    expect((await BloccoLavoro.verifica(absent))['stato'], 'libero');
    expect(Directory(absent).existsSync(), isFalse);
  });
  test('ispezionare un lock proprio non lo rilascia', () async {
    final lock = await BloccoLavoro.prendi(cache);
    try {
      expect((await BloccoLavoro.verifica(cache))['stato'], 'occupato');
      await expectLater(
        BloccoLavoro.recupera(cache, 'A'),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        BloccoLavoro.prendi(cache),
        throwsA(isA<FileSystemException>()),
      );
    } finally {
      await lock.chiudi();
    }
  });
  test('segnale corrotto o legacy non autorizza il recupero', () async {
    for (final text in ['{', '{"pid":99999}', '[]']) {
      marker.writeAsStringSync(text);
      expect(
        (await BloccoLavoro.verifica(cache, proc: proc))['recuperabile'],
        isFalse,
      );
      expect(marker.readAsStringSync(), text);
    }
  });
  test('un symlink non viene seguito né rimosso', () async {
    final protected = File('${tmp.path}/protetto')
      ..writeAsStringSync('non toccare');
    Link(marker.path).createSync(protected.path);
    expect(
      (await BloccoLavoro.verifica(cache, proc: proc))['recuperabile'],
      isFalse,
    );
    await expectLater(
      BloccoLavoro.recupera(cache, 'A', proc: proc),
      throwsFormatException,
    );
    expect(protected.readAsStringSync(), 'non toccare');
    expect(Link(marker.path).existsSync(), isTrue);
  });
  test('owner ancora vivo: non basta un lock libero', () async {
    processo(99999, start: '9');
    salva();
    expect(
      (await BloccoLavoro.verifica(cache, proc: proc))['stato'],
      'occupato',
    );
  });
  test('PID riusato non viene confuso con il vecchio owner', () async {
    processo(99999, start: '100');
    salva();
    expect(
      (await BloccoLavoro.verifica(cache, proc: proc))['recuperabile'],
      isTrue,
    );
  });
  test('PID di un altro namespace non autorizzano il recupero', () async {
    dati['spazioPid'] = 'altro-namespace';
    salva();
    expect(
      (await BloccoLavoro.verifica(cache, proc: proc))['recuperabile'],
      isFalse,
    );
  });
  test('figlio nel gruppo mantiene occupata la cache', () async {
    dati['fase'] = 'processo-registrato';
    dati['processi'] = [
      {'gruppo': 500, 'isolato': true},
    ];
    processo(501, group: 500);
    salva();
    final s = await BloccoLavoro.verifica(cache, proc: proc);
    expect(s['stato'], 'occupato');
    expect((s['processi'] as List).single['pid'], 501);
  });
  test('un gruppo zombie richiede comunque la conferma di scomparsa', () async {
    dati['fase'] = 'processo-registrato';
    dati['processi'] = [
      {'gruppo': 500, 'isolato': true},
    ];
    processo(501, group: 500, state: 'Z');
    salva();
    expect(
      (await BloccoLavoro.verifica(cache, proc: proc))['recuperabile'],
      isFalse,
    );
    Directory('${proc.proc}/501').deleteSync(recursive: true);
    expect(
      (await BloccoLavoro.verifica(cache, proc: proc))['recuperabile'],
      isTrue,
    );
  });
  test(
    'procfs vuoto non basta se la verifica atomica vede il gruppo o è incerta',
    () async {
      dati['fase'] = 'processo-registrato';
      dati['processi'] = [
        {'gruppo': 500, 'isolato': true},
      ];
      salva();
      proc.forza = true;
      for (final v in [true, null]) {
        proc.esistenza = v;
        expect(
          (await BloccoLavoro.verifica(cache, proc: proc))['recuperabile'],
          isFalse,
        );
      }
      proc.esistenza = false;
      expect(
        (await BloccoLavoro.verifica(cache, proc: proc))['recuperabile'],
        isTrue,
      );
    },
  );
  test(
    'spawn non registrato e installazione sono incerti nello stesso boot',
    () async {
      for (final v in [
        {'fase': 'avvio-processo', 'tipo': 'compilazione'},
        {'fase': 'nessun-processo', 'tipo': 'installazione'},
      ]) {
        dati.addAll(v);
        salva();
        expect(
          (await BloccoLavoro.verifica(cache, proc: proc))['recuperabile'],
          isFalse,
        );
      }
      scrivi('${proc.proc}/sys/kernel/random/boot_id', 'boot-successivo');
      expect(
        (await BloccoLavoro.verifica(cache, proc: proc))['recuperabile'],
        isTrue,
      );
    },
  );
  test(
    'gruppo non isolato o procfs illeggibile non autorizza la pulizia',
    () async {
      dati['fase'] = 'processo-registrato';
      dati['processi'] = [
        {'gruppo': 500, 'isolato': false},
      ];
      salva();
      expect(
        (await BloccoLavoro.verifica(cache, proc: proc))['recuperabile'],
        isFalse,
      );
      dati['processi'] = [
        {'gruppo': 500, 'isolato': true},
      ];
      salva();
      Directory(
        '${proc.proc}/999',
      ).createSync(); // PID visibile ma stat non leggibile
      expect(
        (await BloccoLavoro.verifica(cache, proc: proc))['recuperabile'],
        isFalse,
      );
    },
  );
  test('recupero atomico conserva ricevuta, sorgenti, output e log', () async {
    for (final name in ['alberi/file', 'uscita/kernel/fucina.json', 'log.txt'])
      scrivi('$cache/$name', 'sentinella $name');
    salva();
    final before = marker.readAsStringSync();
    expect(
      (await BloccoLavoro.recupera(cache, 'errato', proc: proc))['ok'],
      isFalse,
    );
    expect(marker.readAsStringSync(), before);
    expect((await BloccoLavoro.recupera(cache, 'A', proc: proc))['ok'], isTrue);
    expect(marker.existsSync(), isFalse);
    final receipt = Directory(cache)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('.lavoro-recuperato-'))
        .single;
    expect(receipt.readAsStringSync(), before);
    for (final name in ['alberi/file', 'uscita/kernel/fucina.json', 'log.txt'])
      expect(File('$cache/$name').readAsStringSync(), 'sentinella $name');
  });
  test(
    'token vecchio e nuovo figlio fra verifica e click non passano',
    () async {
      salva();
      expect(
        (await BloccoLavoro.verifica(cache, proc: proc))['recuperabile'],
        isTrue,
      );
      dati['id'] = 'B';
      salva();
      expect(
        (await BloccoLavoro.recupera(cache, 'A', proc: proc))['ok'],
        isFalse,
      );
      dati['fase'] = 'processo-registrato';
      dati['processi'] = [
        {'gruppo': 500, 'isolato': true},
      ];
      salva();
      expect(
        (await BloccoLavoro.verifica(cache, proc: proc))['recuperabile'],
        isTrue,
      );
      processo(501, group: 500);
      expect(
        (await BloccoLavoro.recupera(cache, 'B', proc: proc))['ok'],
        isFalse,
      );
      expect(marker.existsSync(), isTrue);
    },
  );
  test(
    'crash reale: leader morto, figlio vivo, poi recupero e nuovo lavoro',
    () async {
      final worker = File('${tmp.path}/worker.dart')
        ..writeAsString('''
import 'dart:io';
import 'dart:convert';
import 'package:minervad/services/fucina/blocco_lavoro.dart';
Future<void> main(List<String> a) async {
 final l=await BloccoLavoro.prendi(a[0],tipo:'compilazione');
 await l.preparaProcesso();
 final p=await Process.start('setsid',['sh','-c',r'sleep 30 & echo \$!; wait']);
 final child=int.parse(await p.stdout.transform(utf8.decoder).transform(const LineSplitter()).first);
 await l.registraProcesso(p.pid,conSetsid:true);
 p.kill(ProcessSignal.sigkill);await p.exitCode;
 print(jsonEncode({'group':p.pid,'child':child}));
 exit(0);
}
''');
      final r = await Process.run(Platform.resolvedExecutable, [
        '--packages=${File('.dart_tool/package_config.json').absolute.path}',
        worker.path,
        cache,
      ]).timeout(const Duration(seconds: 10));
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final ids = jsonDecode('${r.stdout}') as Map;
      try {
        final s = await BloccoLavoro.verifica(cache);
        expect(s['stato'], 'occupato', reason: '$s');
        expect(
          (s['processi'] as List).any((p) => p['pid'] == ids['child']),
          isTrue,
        );
        await Process.run('kill', ['-KILL', '--', '-${ids['group']}']);
        Map<String, dynamic> done = {};
        for (var i = 0; i < 40; i++) {
          done = await BloccoLavoro.verifica(cache);
          if (done['recuperabile'] == true) break;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(done['recuperabile'], isTrue, reason: '$done');
        expect(
          (await BloccoLavoro.recupera(cache, done['token']))['ok'],
          isTrue,
        );
        final next = await BloccoLavoro.prendi(cache);
        await next.chiudi();
      } finally {
        Process.killPid(ids['child'] as int, ProcessSignal.sigkill);
      }
    },
  );
}
