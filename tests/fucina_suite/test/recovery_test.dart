import 'dart:io';
import 'package:test/test.dart';
import 'package:minervad/services/fucina/patch.dart';
import 'package:minervad/services/fucina/modprobed.dart';
import 'package:minervad/services/manutenzione/inventario.dart';
import 'package:minervad/services/manutenzione/pulitore.dart';

class Inventory extends Inventario {
  @override
  Future<Map<String, dynamic>> tutto() async => {
    'voci': [
      {'id': 'temporanei', 'nome': 'Temporanei', 'dove': '/tmp', 'byte': 100},
    ],
  };
}

void main() {
  late Directory temp;
  late Map<String, String> env;
  void write(String relative, String text) {
    final f = File('${temp.path}/$relative');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(text);
  }

  setUp(() {
    temp = Directory.systemTemp.createTempSync('liquid-recovery-');
    env = {'HOME': temp.path};
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('real GNU patch: fresh, already present and incompatible', () async {
    write('source', 'old\n');
    write(
      'change.patch',
      '--- a/source\n+++ b/source\n@@ -1 +1 @@\n-old\n+new\n',
    );
    Future<String?> execute(List<String> args) async {
      final r = await Process.run(
        args.first,
        args.sublist(1),
        workingDirectory: temp.path,
      );
      return r.exitCode == 0 ? null : '${r.stdout}${r.stderr}';
    }

    final file = '${temp.path}/change.patch';
    expect(await applicaPatch(file: file, esegui: execute), (
      ok: true,
      giaPresente: false,
    ));
    expect(File('${temp.path}/source').readAsStringSync(), 'new\n');
    expect(await applicaPatch(file: file, esegui: execute), (
      ok: true,
      giaPresente: true,
    ));
    expect(File('${temp.path}/source').readAsStringSync(), 'new\n');
    write('source', 'incompatible\n');
    expect(await applicaPatch(file: file, esegui: execute), (
      ok: false,
      giaPresente: false,
    ));
    expect(File('${temp.path}/source').readAsStringSync(), 'incompatible\n');
    expect(File('${temp.path}/source.rej').existsSync(), isFalse);
  });
  test('partial patches fail without mutating either file', () async {
    write('one', 'new\n');
    write('two', 'old\n');
    write(
      'partial.patch',
      '--- a/one\n+++ b/one\n@@ -1 +1 @@\n-old\n+new\n--- a/two\n+++ b/two\n@@ -1 +1 @@\n-old\n+new\n',
    );
    final r = await applicaPatch(
      file: '${temp.path}/partial.patch',
      esegui: (args) async {
        final p = await Process.run(
          args.first,
          args.sublist(1),
          workingDirectory: temp.path,
        );
        return p.exitCode == 0 ? null : '${p.stdout}';
      },
    );
    expect(r.ok, isFalse);
    expect(File('${temp.path}/one').readAsStringSync(), 'new\n');
    expect(File('${temp.path}/two').readAsStringSync(), 'old\n');
  });
  test(
    'modern database takes precedence and normalizes module names',
    () async {
      write(
        '.local/share/modprobed-db/modprobed.db',
        '# comment\nusb-storage\nnvme\nnvme\n',
      );
      write('.config/modprobed.db', 'legacy\n');
      expect((await leggiModprobed(env)).moduli, {'usb_storage', 'nvme'});
    },
  );
  test('legacy database remains supported', () async {
    write('.config/modprobed.db', 'wireguard\n');
    expect((await leggiModprobed(env)).moduli, {'wireguard'});
  });
  test('custom XDG directories and quoted DBPATH with spaces', () async {
    env['XDG_CONFIG_HOME'] = '${temp.path}/config';
    env['XDG_DATA_HOME'] = '${temp.path}/data';
    write(
      'config/modprobed-db/modprobed-db.conf',
      'DBPATH="\${XDG_DATA_HOME}/custom space" # comment\n',
    );
    write('data/custom space/modprobed.db', 'btrfs\n');
    expect((await leggiModprobed(env)).moduli, {'btrfs'});
  });
  test('empty current database does not resurrect an old database', () async {
    write('.local/share/modprobed-db/modprobed.db', '');
    write('.config/modprobed.db', 'stale\n');
    expect((await leggiModprobed(env)).moduli, isEmpty);
  });
  test('configuration never executes shell expressions', () async {
    write(
      '.config/modprobed-db/modprobed-db.conf',
      'DBPATH="\$(touch ${temp.path}/executed)"\n',
    );
    expect((await leggiModprobed(env)).moduli, isEmpty);
    expect(File('${temp.path}/executed').existsSync(), isFalse);
  });
  test(
    'invalid UTF-8 is reported as unavailable, not a daemon error',
    () async {
      write('.local/share/modprobed-db/modprobed.db', '');
      File(
        '${temp.path}/.local/share/modprobed-db/modprobed.db',
      ).writeAsBytesSync([255]);
      expect((await leggiModprobed(env)).moduli, isEmpty);
    },
  );
  test(
    'manual cleanup never enumerates or deletes system temporary files',
    () async {
      final p = Pulitore(
        inventario: Inventory(),
        togli: (_) async => fail('must not delete'),
        figliDa: (_) async {
          fail('must not enumerate /tmp');
        },
      );
      final result = await p.pulisci(['temporanei']);
      expect(result['nonRiuscite'], 1);
      expect(result['liberati'], 0);
    },
  );
}
