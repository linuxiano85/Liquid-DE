// Le prove aggiunte con le correzioni del 13 settembre 2026 (Codex): le
// sostituzioni annullate, gli errori a metà copia, il recupero del
// salvataggio delle impostazioni, il cestino che non nasconde più la perdita
// dei metadati. Vedi `riproduzioni_2026_09_12_test.dart` per il perché stanno
// qui e non in `audit/`.
import 'dart:io';
import 'package:test/test.dart';
import 'package:minervad/services/file_service.dart';
import 'package:minervad/core/linux_files.dart';
import 'package:minervad/core/settings_api.dart';
import 'package:minervad/core/event_bus.dart';

void main() {
  late Directory temp;
  setUp(() async { temp = await Directory.systemTemp.createTemp('minerva-fix-'); });
  tearDown(() => temp.delete(recursive: true));

  Future<Map<String, dynamic>> copy(FileService fs, String from, String to,
      {bool move = false, String conflict = 'sostituisci'}) async {
    final end = fs.progress.firstWhere((e) => ['done', 'failed', 'cancelled'].contains(e['state']));
    await fs.startTransfer(sources: [from], destination: to, move: move, conflitto: conflict);
    return end.timeout(const Duration(seconds: 10));
  }

  test('staging is private from creation', () {
    final dir = LinuxFiles.privateTemp(temp, '.stage-');
    expect(dir.statSync().mode & 511, 448);
  });
  test('atomic no-replace also refuses dangling symlinks', () {
    final source = File('${temp.path}/a')..writeAsStringSync('source');
    final link = Link('${temp.path}/b')..createSync('${temp.path}/missing');
    expect(() => LinuxFiles.renameNoReplace(source.path, link.path), throwsA(isA<FileSystemException>()));
    expect(source.readAsStringSync(), 'source');
    expect(link.targetSync(), '${temp.path}/missing');
  });
  test('replace publishes complete contents and removes staging', () async {
    final source = Directory('${temp.path}/a')..createSync();
    File('${source.path}/new').writeAsStringSync('new');
    final dest = Directory('${temp.path}/dest')..createSync();
    Directory('${dest.path}/a').createSync();
    File('${dest.path}/a/old').writeAsStringSync('old');
    final fs = FileService();
    addTearDown(fs.dispose);
    expect((await copy(fs, source.path, dest.path))['state'], 'done');
    expect(File('${dest.path}/a/new').readAsStringSync(), 'new');
    expect(File('${dest.path}/a/old').existsSync(), isFalse);
    expect(dest.listSync().length, 1);
  });
  test('cancelled replacement preserves both original and previous target', () async {
    final source = File('${temp.path}/a')..writeAsBytesSync(List.filled(8 * 1024 * 1024, 7));
    final dest = Directory('${temp.path}/dest')..createSync();
    final old = File('${dest.path}/a')..writeAsStringSync('old');
    final fs = FileService();
    addTearDown(fs.dispose);
    final sub = fs.progress.listen((e) {
      if ((e['bytesDone'] as int) > 0 && e['state'] == 'running') fs.cancel(e['id'] as String);
    });
    addTearDown(sub.cancel);
    expect((await copy(fs, source.path, dest.path, move: true))['state'], 'cancelled');
    expect(old.readAsStringSync(), 'old');
    expect(source.lengthSync(), 8 * 1024 * 1024);
    expect(dest.listSync().length, 1);
  });
  test('copy error leaves previous destination intact', () async {
    final source = Directory('${temp.path}/a')..createSync();
    final fifo = await Process.run('mkfifo', ['${source.path}/unsupported']);
    expect(fifo.exitCode, 0);
    final dest = Directory('${temp.path}/dest')..createSync();
    final old = File('${dest.path}/a')..writeAsStringSync('old');
    final fs = FileService();
    addTearDown(fs.dispose);
    expect((await copy(fs, source.path, dest.path))['state'], 'failed');
    expect(old.readAsStringSync(), 'old');
    expect(dest.listSync().length, 1);
  });
  test('descendant through symlink is refused before copying', () async {
    final source = Directory('${temp.path}/a')..createSync();
    final inner = Directory('${source.path}/inner')..createSync();
    final link = Link('${temp.path}/alias')..createSync(inner.path);
    final fs = FileService();
    addTearDown(fs.dispose);
    expect((await copy(fs, source.path, link.path))['state'], 'failed');
    expect(inner.listSync(), isEmpty);
  });
  test('failed settings transaction keeps memory unchanged and queue recovers', () async {
    final api = SettingsApi(EventBus(), path: '${temp.path}/settings.json');
    await api.init();
    addTearDown(api.dispose);
    final before = api.getValue('general.language');
    final obstruction = Directory('${temp.path}/settings.json.nuovo')..createSync();
    expect(await api.setValue('general.language', 'en'), isFalse);
    expect(api.getValue('general.language'), before);
    expect(await api.setValues({'general.language': 'en', 'windows.elastico': 2}),
        ['general.language', 'windows.elastico']);
    expect(api.getValue('windows.elastico'), 0);
    obstruction.deleteSync();
    expect(await api.setValue('general.language', 'en'), isTrue);
    expect(api.getValue('general.language'), 'en');
  });
}
