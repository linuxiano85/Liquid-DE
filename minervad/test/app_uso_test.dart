// Quante volte e a che ora si apre ogni app: il menù ne fa «adesso, di
// solito». Il file di prima (solo i conti) si legge ancora.
import 'dart:convert';
import 'dart:io';

import 'package:minervad/services/app_usage_tracker.dart';
import 'package:test/test.dart';

void main() {
  late Directory cartella;
  setUp(() async => cartella = await Directory.systemTemp.createTemp('liquid-uso-'));
  tearDown(() => cartella.delete(recursive: true));

  test('il file di prima si legge ancora, e i conti non si perdono', () async {
    final f = File('${cartella.path}/app_usage.json');
    await f.writeAsString(jsonEncode({'firefox.desktop': 41}));
    final u = AppUsageTracker(path: f.path);
    await u.init();
    expect(u.lanci('firefox.desktop'), 41);
    expect(u.adesso('firefox.desktop'), 0);
  });

  test('l\'ora conta, e le ore accanto anche', () async {
    final f = File('${cartella.path}/app_usage.json');
    final u = AppUsageTracker(path: f.path);
    await u.init();
    final mattina = DateTime(2026, 9, 24, 8, 30);
    for (var i = 0; i < 3; i++) {
      await u.recordLaunch('posta.desktop', quando: mattina);
    }
    await u.recordLaunch('posta.desktop', quando: DateTime(2026, 9, 24, 9, 5));
    await u.recordLaunch('lettore.desktop', quando: DateTime(2026, 9, 24, 21, 0));
    expect(u.lanci('posta.desktop'), 4);
    expect(u.adesso('posta.desktop', quando: DateTime(2026, 9, 25, 8, 55)), 4);
    expect(u.adesso('posta.desktop', quando: DateTime(2026, 9, 25, 21, 0)), 0);
    expect(u.adesso('lettore.desktop', quando: DateTime(2026, 9, 25, 22, 10)), 1);
  });

  test('mezzanotte è accanto alle 23', () async {
    final u = AppUsageTracker(path: '${cartella.path}/app_usage.json');
    await u.init();
    await u.recordLaunch('film.desktop', quando: DateTime(2026, 9, 24, 23, 40));
    expect(u.adesso('film.desktop', quando: DateTime(2026, 9, 25, 0, 10)), 1);
  });

  test('si salva e si rilegge, con le ore', () async {
    final percorso = '${cartella.path}/app_usage.json';
    final u = AppUsageTracker(path: percorso);
    await u.init();
    await u.recordLaunch('posta.desktop', quando: DateTime(2026, 9, 24, 8, 0));
    final di = AppUsageTracker(path: percorso);
    await di.init();
    expect(di.lanci('posta.desktop'), 1);
    expect(di.adesso('posta.desktop', quando: DateTime(2026, 9, 24, 8, 0)), 1);
  });
}
