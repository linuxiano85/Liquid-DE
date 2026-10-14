import 'dart:io';
import 'dart:convert';
import 'package:minervad/services/fucina/risorse_compilazione.dart';
import 'package:minervad/services/fucina/rilievo.dart';
import 'package:minervad/services/fucina_service.dart';
import 'package:test/test.dart';

void main() {
  const gib = 1024 * 1024 * 1024;
  late Directory tmp;
  void file(String path, String testo) {
    File('${tmp.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(testo);
  }

  void cgroup(String dir, String max, int current) {
    file('sys/fs/cgroup$dir/memory.max', '$max\n');
    file('sys/fs/cgroup$dir/memory.current', '$current\n');
  }

  Future<Map<String, dynamic>> leggi() =>
      RisorseCompilazione(radice: tmp.path).leggi();
  Map<String, dynamic> scelta(
    int? bytes, {
    int? richiesti,
    bool lto = false,
    int thread = 32,
  }) => scegliParallelismo(
    thread: thread,
    richiesti: richiesti,
    thinLto: lto,
    risorse: {'memoriaEffettivaBytes': bytes, 'cgroupV2Verificato': true},
  );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('fucina-risorse-');
    file('proc/meminfo', 'MemTotal: 16777216 kB\nMemAvailable: 12582912 kB\n');
    file('proc/self/cgroup', '0::/utente/app\n');
    file(
      'proc/self/mountinfo',
      '10 1 0:1 / /sys/fs/cgroup rw - cgroup2 cgroup rw\n',
    );
    cgroup('/utente', 'max', gib);
    cgroup('/utente/app', 'max', gib);
  });
  tearDown(() async => tmp.delete(recursive: true));

  test('cgroup illimitato usa MemAvailable e non la RAM totale', () async {
    final r = await leggi();
    expect(r['memoriaEffettivaBytes'], 12 * gib);
    expect(r['cgroupV2Verificato'], isTrue);
    expect(r['cgroupLimitato'], isFalse);
    expect(jsonEncode(r), isNot(contains('/utente')));
  });
  test('il limite del padre prevale su quello del processo', () async {
    cgroup('/utente', '${4 * gib}', 3 * gib);
    cgroup('/utente/app', '${8 * gib}', gib);
    final r = await leggi();
    expect(r['memoriaEffettivaBytes'], gib);
    expect(r['cgroupLimitato'], isTrue);
  });
  test('limite esaurito o zero conserva zero senza overflow', () async {
    cgroup('/utente/app', '$gib', 2 * gib);
    expect((await leggi())['memoriaEffettivaBytes'], 0);
    cgroup('/utente/app', '0', 0);
    expect((await leggi())['memoriaEffettivaBytes'], 0);
  });
  test('MemAvailable non viene sostituito con MemFree o swap', () async {
    file(
      'proc/meminfo',
      'MemTotal: 16777216 kB\nMemFree: 100 kB\nSwapFree: 99999999 kB\n',
    );
    expect((await leggi())['memoriaEffettivaBytes'], isNull);
  });
  test('dati cgroup incompleti e v1 non autorizzano Auto illimitato', () async {
    File('${tmp.path}/sys/fs/cgroup/utente/memory.current').deleteSync();
    expect((await leggi())['memoriaEffettivaBytes'], isNull);
    file('proc/self/cgroup', '3:memory:/utente/app\n');
    final r = await leggi();
    expect(r['cgroupV2Verificato'], isFalse);
    expect(r['memoriaEffettivaBytes'], isNull);
  });
  test(
    'mount di un sottoalbero verifica anche la sua radice esposta',
    () async {
      file(
        'proc/self/mountinfo',
        '10 1 0:1 /utente /sys/fs/cgroup rw - cgroup2 cgroup rw\n',
      );
      cgroup('', '${2 * gib}', gib);
      cgroup('/app', 'max', 0);
      expect((await leggi())['memoriaEffettivaBytes'], gib);
      File('${tmp.path}/sys/fs/cgroup/memory.max').deleteSync();
      expect((await leggi())['cgroupV2Verificato'], isFalse);
    },
  );
  test('mount con spazi codificati viene risolto correttamente', () async {
    file('proc/self/cgroup', '0::/\n');
    file(
      'proc/self/mountinfo',
      r'10 1 0:1 / /sys/fs/cgroup\040prova rw - cgroup2 cgroup rw'
          '\n',
    );
    file('sys/fs/cgroup prova/memory.max', '$gib');
    file('sys/fs/cgroup prova/memory.current', '0');
    expect((await leggi())['memoriaEffettivaBytes'], gib);
  });
  test(
    'percorsi relativi, traversal, mount ambigui e interi corrotti falliscono chiusi',
    () async {
      for (final p in ['/../segreto', 'relativo', '/utente/./app']) {
        file('proc/self/cgroup', '0::$p\n');
        expect((await leggi())['cgroupV2Verificato'], isFalse);
      }
      file('proc/self/cgroup', '0::/utente/app\n');
      cgroup('/utente/app', '99999999999999999999999999', 0);
      expect((await leggi())['cgroupV2Verificato'], isFalse);
      file(
        'proc/self/mountinfo',
        '10 1 0:1 / /sys/fs/cgroup rw - cgroup2 cgroup rw\n11 1 0:2 / /altro rw - cgroup2 cgroup rw\n',
      );
      expect((await leggi())['cgroupV2Verificato'], isFalse);
    },
  );
  test(
    'lettura ripetuta osserva la memoria corrente e non scrive file',
    () async {
      final prima = tmp
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path)
          .toSet();
      expect((await leggi())['memoriaEffettivaBytes'], 12 * gib);
      cgroup('/utente/app', '${4 * gib}', 3 * gib);
      expect((await leggi())['memoriaEffettivaBytes'], gib);
      expect(
        tmp
            .listSync(recursive: true)
            .whereType<File>()
            .map((f) => f.path)
            .toSet(),
        prima,
      );
    },
  );
  test(
    'alias bind mount come bpftune e sottoalberi non nascondono il padre',
    () async {
      file(
        'proc/self/mountinfo',
        '11 1 0:1 /utente/app /alias rw - cgroup2 cgroup rw\n'
            '12 1 0:1 / /run/bpftune/cgroupv2 rw - cgroup2 none rw\n'
            '10 1 0:1 / /sys/fs/cgroup rw - cgroup2 cgroup rw\n',
      );
      cgroup('/utente', '${4 * gib}', 3 * gib);
      final r = await leggi();
      expect(r['cgroupV2Verificato'], isTrue);
      expect(r['memoriaEffettivaBytes'], gib);
    },
  );
  test('Auto riduce lavori con memoria limitata e rispetta i thread', () {
    expect(scelta(2 * gib)['effettivi'], 3);
    expect(scelta(16 * gib, thread: 12)['effettivi'], 12);
    expect(scelta(128 * gib, thread: 999)['effettivi'], lessThanOrEqualTo(512));
  });
  test(
    'ThinLTO usa stima distinta e dichiara i thread indipendenti del linker',
    () {
      expect(scelta(2 * gib, lto: true)['effettivi'], 2);
      expect(
        scelta(2 * gib, lto: true)['limite'],
        contains('non limitati da make -j'),
      );
    },
  );
  test('memoria nulla, negativa o esaurita propone almeno un lavoro', () {
    for (final m in [null, -1, 0, 1]) {
      expect(scelta(m)['effettivi'], 1);
    }
    expect(scelta(null)['motivo'], contains('non verificabile'));
  });
  test(
    'manuale viene rispettato entro i thread e avvisa oltre il consiglio',
    () {
      final r = scelta(gib, richiesti: 32, thread: 12);
      expect(r['effettivi'], 12);
      expect(r['manualeOltreConsiglio'], isTrue);
      expect(r['automatico'], isFalse);
    },
  );
  test(
    'daemon rilegge le risorse anche con rilievo hardware in cache',
    () async {
      file('proc/sys/kernel/osrelease', '7.2.9-fixture');
      file('proc/modules', '');
      var chiamate = 0, root = 0;
      final s = FucinaService(
        radice: (_, _) async {
          root++;
          return {'ok': true};
        },
        lavoro: '${tmp.path}/cache',
        statoDir: '${tmp.path}/stato',
        risorseCompilazione: () async => {
          'memoriaEffettivaBytes': ++chiamate == 1 ? 16 * gib : 2 * gib,
          'cgroupV2Verificato': true,
        },
        nuovoRilevatore: (_, _) =>
            Rilevatore(radice: tmp.path, ambiente: {'PATH': ''}, nuclei: 12),
      );
      final scelte = {'versione': '7.2.9', 'nome': 'risorse'};
      final a = await s.ricetta(scelte), b = await s.ricetta(scelte);
      expect(a['ok'], isTrue);
      expect(b['ok'], isTrue);
      expect(a['parallelismo']['effettivi'], 12);
      expect(b['parallelismo']['effettivi'], 3);
      final comando = (b['passi'] as List).singleWhere(
        (p) => p['id'] == 'compila',
      )['comando'];
      expect(comando, contains('-j3'));
      expect(chiamate, 2);
      expect(root, 0);
      expect(Directory('${tmp.path}/cache').existsSync(), isFalse);
    },
  );
}
