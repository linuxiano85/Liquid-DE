import 'dart:convert';
import 'dart:io';
import '../minervad/lib/core/event_bus.dart';
import '../minervad/lib/core/settings_api.dart';

// Uses the production store and an isolated file, with no desktop session.
Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('liquid-windows-settings-');
  final path = '${dir.path}/settings.json';
  final bus = EventBus();
  var api = SettingsApi(bus, path: path);
  void check(bool value, String name) {
    if (!value) throw StateError(name);
    stdout.writeln('PASS $name');
  }

  try {
    await api.init();
    check(await api.setValue('stile.attuale', 'windows'), 'preset Windows attivo');
    check(await api.setValue('bar.stile', 'windows11'), 'dedicated taskbar accepted');
    check(await api.setValue('windows11.menu', 'liquid'), 'alternative Start accepted');
    check(await api.setValue('windows11.theme', 'dark'), 'dark theme accepted');
    check(await api.setValue('windows11.wallpaper', 'current'), 'custom wallpaper accepted');
    check(await api.setValue('windows11.showTilingButton', true), 'optional tiling icon accepted');
    check(await api.setValue('windows11.desktops', [1, 3, 7]), 'desktop IDs persist');
    final folders = ['settings', 'files', 'documents', 'downloads',
      'music', 'pictures', 'videos', 'home'];
    check(await api.setValue('windows11.startFolders', folders), 'collegamenti Start accettati');
    for (final invalid in [null, 'home', ['home', 'home'], ['network'], ['../tmp'], [1]]) {
      check(!await api.setValue('windows11.startFolders', invalid), 'rifiuta collegamenti invalidi: $invalid');
    }
    final liquidAccent = api.settings['shell']['accent'];
    check(api.settings['windows11']['accent'] == 'auto', 'Windows accent starts automatic');
    for (final color in ['auto', '#000000', '#ffffff', '#FFB900', '#C239B3']) {
      check(await api.setValue('windows11.accent', color), 'Windows accent accepted: $color');
    }
    check(await api.setValue('windows11.accentOnStart', true), 'Start accent option accepted');
    check(api.settings['shell']['accent'] == liquidAccent, 'Windows accent leaves Liquid accent untouched');
    for (final invalid in ['blue', '#12345', '#12345678', '#123456 ', 'transparent', '', 123, null]) {
      check(!await api.setValue('windows11.accent', invalid), 'reject malformed Windows accent: $invalid');
    }
    check(!await api.setValue('windows11.accentOnStart', 'true'), 'reject non-boolean Start accent');
    for (final entry in <String, dynamic>{
      'windows11.menu': 'unknown',
      'windows11.theme': 'unknown',
      'windows11.wallpaper': 'unknown',
      'windows11.showTilingButton': 'yes',
      'bar.stile': 'unknown',
    }.entries) {
      check(!await api.setValue(entry.key, entry.value), 'reject ${entry.key} invalid value');
    }
    for (final ids in [<int>[], [1, 1], [0], [11], ['1']]) {
      check(!await api.setValue('windows11.desktops', ids), 'reject invalid desktop list $ids');
    }
    // Le nuove scelte devono passare dallo stesso validatore della shell,
    // sopravvivere al riavvio e rifiutare valori che non si possono mostrare.
    for (final entry in <String, List<String>>{
      'windows11.startLayout': ['pinned', 'default', 'recommended'],
      'windows11.taskbarSearch': ['hidden', 'icon', 'label', 'box'],
      'windows11.taskbarAlignment': ['left', 'center'],
    }.entries) {
      for (final value in entry.value) {
        check(await api.setValue(entry.key, value), '${entry.key} accetta $value');
      }
      for (final value in ['invalid', '', 2, null]) {
        check(!await api.setValue(entry.key, value), '${entry.key} rifiuta $value');
      }
    }
    for (final key in ['taskbarTaskView', 'taskbarWidgets', 'taskbarShowDesktop']) {
      check(await api.setValue('windows11.$key', false), '$key disattivabile');
      check(!await api.setValue('windows11.$key', 'false'), '$key richiede booleano');
    }
    await api.dispose();
    api = SettingsApi(bus, path: path);
    await api.init();
    final saved = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    check(saved['windows11']['startLayout'] == 'recommended'
        && saved['windows11']['taskbarSearch'] == 'box'
        && saved['windows11']['taskbarAlignment'] == 'center'
        && saved['windows11']['taskbarWidgets'] == false, 'nuove preferenze persistenti');
    check(saved['windows11']['theme'] == 'dark' && saved['windows11']['menu'] == 'liquid', 'preferences survive reload');
    check(jsonEncode(saved['windows11']['startFolders']) == jsonEncode(folders), 'collegamenti persistenti dopo riavvio');
    check(await api.setValue('stile.attuale', 'liquid'), 'passaggio a Liquid per isolamento collegamenti');
    check(await api.setValue('windows11.startFolders', ['home']), 'collegamenti diversi nel preset Liquid');
    check(await api.setValue('stile.attuale', 'windows'), 'ritorno al preset Windows');
    check(jsonEncode(api.settings['windows11']['startFolders']) == jsonEncode(folders), 'Windows recupera i propri collegamenti');
    check(saved['windows11']['accent'] == '#C239B3' && saved['windows11']['accentOnStart'] == true, 'Windows accent preferences survive reload');
    await api.dispose();
    final original = SettingsApi.defaultSettings();
    original['stile']['attuale'] = 'windows';
    original['stile']['libero'] = '{"bar.stile":"isola"}';
    original['bar']['stile'] = 'classica';
    original['windows']['tilingMode'] = 'colonne';
    File(path).writeAsStringSync(jsonEncode(original));
    api = SettingsApi(bus, path: path);
    await api.init();
    // A subsequent ordinary preference save also persists the migration.
    await api.setValue('windows11.theme', 'dark');
    final migrated = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    check(migrated['bar']['stile'] == 'windows11', 'old Windows preset migrates');
    check(migrated['stile']['libero'] == original['stile']['libero'], 'custom snapshot preserved');
    check(migrated['windows']['tilingMode'] == 'colonne', 'tiling preference preserved');
  } finally {
    await api.dispose();
    await bus.dispose();
    await dir.delete(recursive: true);
  }
}
