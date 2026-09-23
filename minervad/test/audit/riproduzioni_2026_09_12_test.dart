// Le riproduzioni dell'audit del 12 settembre 2026 (Codex).
//
// Sono nate ROSSE, apposta: ognuna descrive una garanzia che il gestore file
// o le impostazioni non davano — annullare uno spostamento fra due dischi
// cancellava i file già spostati, rinominare sovrascriveva senza chiedere,
// «sostituisci» distruggeva la destinazione prima di avere la copia, un link
// rotto veniva seguito fuori dalla cartella, un salvataggio fallito veniva
// dichiarato riuscito. Sono diventate verdi il 13 settembre con le correzioni
// vere, non cambiando le aspettative.
//
// Stavano in `audit/`, fuori da `dart test`. Da qui girano con tutte le altre:
// una prova che ha già trovato una perdita di dati una volta è esattamente
// quella che deve girare sempre.
import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:minervad/services/file_service.dart';
import 'package:minervad/services/archive_service.dart';
import 'package:minervad/ipc/canale_segreto.dart';
import 'package:minervad/core/settings_api.dart';
import 'package:minervad/core/event_bus.dart';

void main() {
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('minerva-audit-data-');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });
  Future<Map<String, dynamic>> transfer(
    FileService fs,
    List<String> src,
    String dst, {
    bool move = false,
    String conflict = 'entrambi',
  }) async {
    final done = fs.progress.firstWhere(
      (e) => ['done', 'failed', 'cancelled'].contains(e['state']),
    );
    await fs.startTransfer(
      sources: src,
      destination: dst,
      move: move,
      conflitto: conflict,
    );
    return done.timeout(const Duration(seconds: 10));
  }

  test('rename must not silently overwrite another file', () async {
    final a = File('${temp.path}/a')..writeAsStringSync('source');
    final b = File('${temp.path}/b')..writeAsStringSync('valuable-original');
    final result = await FileService().rename(a.path, b.path);
    print('rename result=$result, destination=${b.readAsStringSync()}');
    expect(b.readAsStringSync(), 'valuable-original');
  });
  test('trash must report failure when restore metadata cannot be saved', () async {
    final root = '${temp.path}/trash';
    final source = File('${temp.path}/documento')
      ..writeAsStringSync('valuable');
    // Simula metadati non scrivibili senza dipendere dall'UID del test.
    Directory('$root/info/documento.trashinfo').createSync(recursive: true);
    final fs = FileService(cestinoDiProva: root);
    final result = await fs.trash([source.path]);
    final trashed = File('$root/files/documento');
    final restored = await fs.restoreFromTrash([trashed.path]);
    print(
      'trash=$result, restore=$restored, '
      'sourceExists=${source.existsSync()}, dataRetained=${trashed.existsSync()}',
    );
    expect(
      result['ok'],
      isFalse,
      reason: 'A successful trash operation must retain restore metadata',
    );
  });
  test('same-file replace must not delete the source', () async {
    final a = File('${temp.path}/a')..writeAsStringSync('valuable-original');
    final result = await transfer(
      FileService(),
      [a.path],
      temp.path,
      conflict: 'sostituisci',
    );
    print(
      'self-replace state=${result['state']}, sourceExists=${a.existsSync()}',
    );
    expect(a.existsSync(), isTrue);
  });
  test('copy into a descendant must be rejected', () async {
    final src = Directory('${temp.path}/src')..createSync();
    final dst = Directory('${src.path}/dst')..createSync();
    final fs = FileService();
    final done = fs.progress.firstWhere(
      (e) => ['done', 'failed', 'cancelled'].contains(e['state']),
    );
    final id = await fs.startTransfer(
      sources: [src.path],
      destination: dst.path,
      move: false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final recursive = Directory('${dst.path}/src/dst/src').existsSync();
    fs.cancel(id);
    final result = await done.timeout(const Duration(seconds: 10));
    print('descendant recursive=$recursive, state=${result['state']}');
    expect(recursive, isFalse);
  });
  test('copy must not write through dangling destination symlinks', () async {
    final src = Directory('${temp.path}/src')..createSync();
    final dst = Directory('${temp.path}/dst')..createSync();
    final input = File('${src.path}/a')..writeAsStringSync('source');
    final outside = File('${temp.path}/outside');
    Link('${dst.path}/a').createSync(outside.path);
    final result = await transfer(FileService(), [input.path], dst.path);
    print(
      'symlink copy state=${result['state']}, outsideExists=${outside.existsSync()}',
    );
    expect(outside.existsSync(), isFalse);
  });
  test('compression must handle a leading-dash filename', () async {
    final input = File('${temp.path}/--version')
      ..writeAsStringSync('important');
    final result = await ArchiveService().comprimi([
      input.path,
    ], nome: 'bundle');
    print('archive result=$result');
    expect(result['ok'], isTrue);
    expect(File(result['percorso'] as String).existsSync(), isTrue);
  });
  test('IPC secret creation must reject a preexisting symlink', () async {
    final victim = File('${temp.path}/victim')..writeAsStringSync('original');
    final path = '${temp.path}/canale';
    Link(path).createSync(victim.path);
    try {
      await CanaleSegreto.scriviNuovo(
        percorsoFile: path,
        socket: '${temp.path}/x.sock',
      );
    } catch (_) {}
    final changed = victim.readAsStringSync() != 'original';
    print('secret followed symlink=$changed');
    expect(changed, isFalse);
  });
  test('copy must preserve private directory permissions', () async {
    final src = Directory('${temp.path}/private')..createSync();
    await Process.run('chmod', ['700', src.path]);
    final dst = Directory('${temp.path}/dest')..createSync();
    final result = await transfer(FileService(), [src.path], dst.path);
    final mode = Directory('${dst.path}/private').statSync().mode & 511;
    print(
      'directory copy state=${result['state']}, permissions=${mode.toRadixString(8)}',
    );
    expect(mode, 448);
  });
  test('settings write failure must not return success', () async {
    final path = '${temp.path}/settings.json';
    final bus = EventBus();
    final settings = SettingsApi(bus, path: path);
    await settings.init();
    final before = File(path).readAsStringSync();
    Directory('$path.nuovo').createSync();
    final result = await settings.setValue('general.language', 'en');
    print(
      'settings success=$result, diskUnchanged=${File(path).readAsStringSync() == before}',
    );
    await settings.dispose();
    expect(result, isFalse);
  });
  test(
    'cancelling cross-device move must preserve already moved files',
    () async {
      final dst = await Directory('/dev/shm')
          .createTemp('minerva-audit-destination-');
      addTearDown(() => dst.delete(recursive: true));
      final a = File('${temp.path}/a')..writeAsStringSync('irreplaceable');
      final b = File('${temp.path}/b')
        ..writeAsBytesSync(List.filled(4 * 1024 * 1024, 7));
      final fs = FileService();
      final sub = fs.progress.listen((event) {
        if (event['currentFile'] == 'b' && event['state'] == 'running') {
          fs.cancel(event['id'] as String);
        }
      });
      final result = await transfer(fs, [a.path, b.path], dst.path, move: true);
      await sub.cancel();
      final preserved = a.existsSync() || File('${dst.path}/a').existsSync();
      print(
        'cross-device state=${result['state']}, firstFilePreserved=$preserved',
      );
      expect(preserved, isTrue);
    },
  );
}
