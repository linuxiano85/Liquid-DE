import 'dart:convert';
import 'dart:io';
import '../minervad/lib/core/event_bus.dart';
import '../minervad/lib/core/settings_api.dart';
import '../minervad/lib/core/desktop_profiles.dart';

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('liquid-profile-test-');
  final path = '${dir.path}/settings.json';
  final bus = EventBus();
  var api = SettingsApi(bus, path: path);
  var count = 0;
  void check(bool ok, String label) {
    if (!ok) throw StateError(label);
    count++;
    print('PASS $label');
  }
  Future<void> restart() async {
    await api.dispose();
    api = SettingsApi(bus, path: path);
    await api.init();
  }
  final choices = <String, Map<String, dynamic>>{};
  try {
    await api.init();
    await api.setValues({'input.controllerPad': {'switch': {'layout': 'europeo'}},
      'general.language': 'it', 'media.volume': 27, 'power.lockAfter': 7,
      'greeter.autologin': false, 'launcher.defaultTerminal': 'my-terminal',
      'shell.hotReload': true, 'weather.name': 'Test city'});
    final common = ['input', 'general.language', 'media.volume', 'power.lockAfter',
      'greeter', 'launcher.defaultTerminal', 'shell.hotReload', 'weather'];
    final shared = {for (final k in common) k: jsonEncode(api.getValue(k))};
    for (var i = 0; i < DesktopProfiles.names.length; i++) {
      final name = DesktopProfiles.names[i];
      check(await api.setValue('stile.attuale', name), 'activate $name');
      if (name == 'windows') {
        check(api.getValue('windows.effetto') == 'nessuno', 'fresh Windows has no inherited watercolor');
        check((api.getValue('riva.angoli') as Map).values.every((v) => v == 'niente'), 'fresh Windows has no inherited hot corners');
      }
      final edits = <String, dynamic>{
        'windows.effetto': i.isEven ? 'acquerello' : 'nessuno',
        'riva.angoli': {'altoSx': i.isEven ? 'menu' : 'niente', 'altoDx':'niente', 'bassoSx':'niente', 'bassoDx':'niente'},
        'windows.tilingMode': i.isEven ? 'colonne' : 'classico',
        'windows.tilingGap': i + 1,
        'windows.workspaceLayouts': List.filled(10, i.isEven ? 'griglia' : 'maestro'),
        'windows.tilingRules': [{'app':'test-$i', 'enabled':true, 'width':40+i, 'position':-1, 'workspace':i+1}],
        'bar.position': i.isEven ? 'basso' : 'alto',
        'dock.enabled': i.isEven, 'dock.pinned': ['app-$i.desktop'],
        'launcher.fixedApps': ['menu-$i.desktop'], 'icons.theme': 'theme-$i',
        'desktop.wallpaper': '/tmp/wall-$i.png', 'desktop.animationSpeed': 0.5 + i/10,
        'shell.accent': '#11223$i', 'shell.scavalca': {'base':'#12345$i'},
        'files.desktopPositions': {'file.with.dots': {'x':i/10, 'y':0.4}},
        'files.disposizione': i.isEven ? 'schede' : 'affiancata',
        'files.caselleSelezione': i.isEven,
        'shortcuts.disabled': i.isEven ? [r'$mod W'] : [],
        'windows11.accent': '#55667$i', 'windows11.accentOnStart': i.isEven,
      };
      check((await api.setValues(edits)).isEmpty, 'customize $name');
      choices[name] = edits;
      final events = bus.conteggio['settings_changed'];
      check(await api.setValue('stile.attuale', name), 'same preset accepted');
      check(bus.conteggio['settings_changed'] == events, 'same preset preserves preferences without a notification');
    }
    await restart();
    // Every source/destination pair, including switches after a process restart.
    for (final source in DesktopProfiles.names) {
      await api.setValue('stile.attuale', source);
      for (final target in DesktopProfiles.names.reversed) {
        await api.setValue('stile.attuale', target);
        for (final e in choices[target]!.entries) {
          check(jsonEncode(api.getValue(e.key)) == jsonEncode(e.value), '$source → $target restores ${e.key}');
        }
        for (final e in shared.entries) {
          check(jsonEncode(api.getValue(e.key)) == e.value, '$target keeps shared ${e.key}');
        }
        await api.setValue('stile.attuale', source);
      }
    }
    // Color maps, lists and positions must have no references into inactive data.
    await api.setValue('stile.attuale', 'liquid');
    final windowsBefore = jsonEncode(api.getValue('stile.profili.windows'));
    await api.setValue('shell.scavalca', {});
    await api.setValue('dock.pinned', []);
    check(jsonEncode(api.getValue('stile.profili.windows')) == windowsBefore, 'editing maps and lists cannot mutate another profile');
    var events = bus.conteggio['settings_changed'] ?? 0;
    check((await api.setValues({'windows.tilingGap':22, 'stile.attuale':'windows'})).isEmpty, 'batch switches before applying destination preferences');
    check(api.getValue('windows.tilingGap') == 22, 'batch edits destination');
    check(bus.conteggio['settings_changed'] == events+1, 'switch batch publishes one complete snapshot');
    await api.setValue('stile.attuale', 'liquid');
    check(api.getValue('windows.tilingGap') == choices['liquid']!['windows.tilingGap'], 'batch leaves outgoing profile intact');
    for (final invalid in ['unknown', '', null, 7]) {
      check(!await api.setValue('stile.attuale', invalid), 'reject invalid preset $invalid');
    }
    check(!await api.setValue('stile.profili', {}), 'IPC cannot erase profiles');
    check(!await api.setValue('stile.profili.windows.media.volume', 99), 'IPC cannot inject shared state into profiles');
    check(!await api.setValue('stile', {'attuale':'windows', 'profili':{}}), 'invalid group update is rejected before activation');
    check(api.getValue('stile.attuale') == 'liquid', 'rejected group keeps current preset');
    check(await api.setValue('stile', {'attuale':'windows'}), 'group activation works');
    await restart();
    await api.setValue('stile.attuale', 'windows');
    check(api.getValue('windows.tilingGap') == 22, 'destination changes survive restart');
    check(api.sorveglianzeAperte == 1, 'only one watcher after many switches');

    // Partial damage to an inactive profile is repaired, preserving good values.
    await api.dispose();
    final saved = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    saved['stile']['profili']['liquid']['windows.tilingGap'] = -1;
    saved['stile']['profili']['liquid']['media.volume'] = 100;
    saved['stile']['profili']['liquid']['shell'] = {'hotReload':false};
    saved['stile']['profili']['liquid']['invented.key'] = 'bad';
    saved['stile']['profili']['invented'] = {};
    File(path).writeAsStringSync(jsonEncode(saved));
    api = SettingsApi(bus, path:path); await api.init();
    await api.setValue('stile.attuale', 'liquid');
    check(api.getValue('windows.tilingGap') == 8, 'damaged inactive value resets individually');
    check(api.getValue('desktop.wallpaper') == choices['liquid']!['desktop.wallpaper'], 'good inactive value survives repair');
    check(api.getValue('media.volume') == 27 && api.getValue('shell.hotReload') == true, 'profile cannot override system or entire groups');
    check(!(api.getValue('stile.profili') as Map).containsKey('invented'), 'unknown profiles removed');
    await api.resetToDefaults();
    check((api.getValue('stile.profili') as Map).length == 5, 'global reset initializes all profiles');
    await api.setValue('stile.attuale', 'windows');
    check(api.getValue('windows.effetto') == 'nessuno', 'Windows defaults after reset');

    // A legacy Windows install retains its active customization and Free layout.
    await api.dispose();
    final legacy = SettingsApi.defaultSettings();
    (legacy['stile'] as Map).remove('profili');
    legacy['stile']['attuale'] = 'windows';
    legacy['stile']['libero'] = '{"dock.iconSize":61,"bar.stile":"isola"}';
    legacy['bar']['stile'] = 'classica';
    legacy['desktop']['wallpaper'] = '/tmp/legacy.png';
    legacy['windows']['effetto'] = 'acquerello';
    File(path).writeAsStringSync(jsonEncode(legacy));
    api = SettingsApi(bus, path:path); await api.init();
    check(api.getValue('bar.stile') == 'windows11' && api.getValue('desktop.wallpaper') == '/tmp/legacy.png', 'legacy active customization migrates');
    await api.setValue('windows.effetto', 'nessuno');
    await api.setValue('stile.attuale', 'liquid');
    check(api.getValue('windows.effetto') == 'acquerello', 'old shared watercolor retained in Liquid');
    await api.setValue('stile.attuale', 'libero');
    check(api.getValue('dock.iconSize') == 61 && api.getValue('bar.stile') == 'isola', 'old Free snapshot restored');
    await api.setValue('stile.attuale', 'windows');
    check(api.getValue('windows.effetto') == 'nessuno', 'new Windows preferences separated after migration');
    await restart();
    check(api.getValue('windows.effetto') == 'nessuno', 'migration persists');
    await api.setValue('bar.stile', 'classica');
    await restart();
    check(api.getValue('bar.stile') == 'classica', 'custom Windows bar is not mistaken for a legacy preset');
    await api.setValue('stile.attuale', 'liquid');
    await api.setValue('windows.tilingGap', 19);
    // File edits and rapid IPC writes share the same transaction queue.
    final external = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    external['stile']['attuale'] = 'windows';
    external['windows']['tilingGap'] = 24;
    File(path).writeAsStringSync(jsonEncode(external));
    await api.setValue('media.volume', 31);
    check(api.getValue('stile.attuale') == 'windows' && api.getValue('windows.tilingGap') == 24, 'external switch applies explicit edits to destination');
    await api.setValue('stile.attuale', 'liquid');
    check(api.getValue('windows.tilingGap') == 19, 'external switch preserves outgoing profile');
    final queued = [api.setValue('stile.attuale','windows'), api.setValue('windows.tilingGap', 23),
      api.setValue('stile.attuale','liquid'), api.setValue('windows.tilingGap', 18)];
    check((await Future.wait(queued)).every((v) => v), 'concurrent switches and edits are serialized');
    check(api.getValue('windows.tilingGap') == 18, 'last queued edit stays in Liquid');
    await api.setValue('stile.attuale','windows');
    check(api.getValue('windows.tilingGap') == 23, 'earlier queued edit stays in Windows');
    final beforeFailure = jsonEncode(api.settings);
    final eventCount = bus.conteggio['settings_changed'];
    await File('$path.nuovo').delete().catchError((_) => File('$path.nuovo'));
    await Directory('$path.nuovo').create();
    check(!await api.setValue('stile.attuale','liquid'), 'failed disk write rejects switch');
    check(jsonEncode(api.settings) == beforeFailure && bus.conteggio['settings_changed'] == eventCount, 'failed switch preserves both active state and profiles without an event');
    await Directory('$path.nuovo').delete();
    check(await api.setValue('stile.attuale','liquid'), 'queue recovers after failed save');
    check(await api.setValue('riva', {'cassetto':'sinistra'}), 'partial preference groups remain supported');
    check(await api.setValue('stile.attuale','windows'), 'switch rebuilds missing intermediate groups');
    check(api.getValue('riva.angoli') is Map, 'destination corners restored after partial group update');
    print('RESULT $count checks passed');
  } finally {
    await api.dispose(); await bus.dispose(); await dir.delete(recursive:true);
  }
}
