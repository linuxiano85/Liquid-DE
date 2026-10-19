import 'dart:convert';

/// The active settings remain the public projection used by existing clients.
/// Saved profiles contain only desktop preferences, never hardware or secrets.
class DesktopProfiles {
  static const names = ['libero', 'liquid', 'minerva', 'mac', 'windows'];
  static const groups = {
    'shell',
    'cheatsheet',
    'shortcuts',
    'riva',
    'isola',
    'centro',
    'launcher',
    'bar',
    'windows',
    'icons',
    'desktop',
    'dock',
    'windowControls',
    'windows11',
    'clock',
  };
  static const excluded = {
    'shell.hotReload',
    'launcher.defaultTerminal',
    'desktop.menuUsed',
  };
  static const individual = {
    'general.beginnerMode',
    'accessibility.textScale',
    'accessibility.cursorSize',
    'power.risparmioEffetti',
    'power.risparmioSoglia',
    'media.disegno',
    'files.view',
    'files.disposizione',
    'files.caselleSelezione',
    'files.pannelloLaterale',
    'files.zoom',
    'files.sort',
    'files.sortDesc',
    'files.desktopPositions',
    'files.sfondiAutomatici',
    'files.clicSingolo',
    'files.anteprime',
    'files.showHidden',
    'viewer.filmstrip',
    'terminale.carattere',
    'terminale.corpo',
    'terminale.tavolozza',
    'terminale.cursore',
    'editor.font',
    'editor.size',
    'editor.bold',
    'editor.italic',
    'editor.colore',
    'editor.fondoScuro',
  };
  final Map<String, dynamic> factory;
  final bool Function(String path, dynamic value) valid;
  DesktopProfiles(this.factory, this.valid);

  static dynamic copy(dynamic value) => jsonDecode(jsonEncode(value));

  bool scoped(String path) =>
      !excluded.contains(path) &&
      (groups.contains(path.split('.').first) || individual.contains(path));

  Map<String, dynamic> snapshot(Map<String, dynamic> settings) {
    final result = <String, dynamic>{};
    void walk(Map values, Map defaults, String prefix) {
      for (final e in defaults.entries) {
        final path = prefix.isEmpty ? e.key as String : '$prefix.${e.key}';
        if (!values.containsKey(e.key)) continue;
        final value = values[e.key];
        if (e.value is Map && (e.value as Map).isNotEmpty && value is Map) {
          walk(value, e.value as Map, path);
        } else if (scoped(path) && valid(path, value)) {
          result[path] = copy(value);
        }
      }
    }

    walk(settings, factory, '');
    return result;
  }

  /// Uno snapshot completo scritto dal demone include già la proiezione
  /// del profilo attivo. Non interpretarlo come un semplice cambio manuale
  /// del selettore: si perderebbero i profili aggiornati da un'altra sessione.
  bool hasCurrentProjection(Map<String, dynamic> settings) {
    final style = settings['stile'];
    if (style is! Map || style['profili'] is! Map) return false;
    final saved = (style['profili'] as Map)[style['attuale']];
    bool same(dynamic a, dynamic b) {
      if (a is Map && b is Map) {
        return a.length == b.length && a.keys.every((k) => b.containsKey(k) && same(a[k], b[k]));
      }
      if (a is List && b is List) {
        return a.length == b.length && List.generate(a.length, (i) => i).every((i) => same(a[i], b[i]));
      }
      return a == b;
    }
    return same(saved, snapshot(settings));
  }

  Map<String, dynamic> defaults(String name) {
    final p = snapshot(factory);
    p.addAll({
      'bar.position': name == 'windows' ? 'basso' : 'alto',
      'bar.stile': name == 'windows'
          ? 'windows11'
          : (name == 'liquid' || name == 'libero' ? 'isola' : 'classica'),
      'bar.listaFinestre': name == 'windows',
      'dock.enabled': name != 'windows',
      'dock.position': name == 'windows' ? 'alto' : 'basso',
      'dock.modo': name == 'mac' ? 'elude' : 'sempre',
      'dock.iconSize': name == 'mac' ? 52 : 48,
      'dock.magnification': name == 'mac'
          ? 1.9
          : (name == 'windows' ? 1.0 : 1.5),
      'windows.buttonsSide': name == 'mac' ? 'sinistra' : 'destra',
    });
    if (name == 'windows') {
      p['windows.effetto'] = 'nessuno';
      p['windows.mercurio'] = false;
      p['riva.angoli.altoSx'] = 'niente';
      p['riva.angoli.altoDx'] = 'niente';
      p['riva.angoli.bassoSx'] = 'niente';
      p['riva.angoli.bassoDx'] = 'niente';
    }
    return p;
  }

  Map<String, dynamic> _safe(dynamic saved) {
    final result = <String, dynamic>{};
    if (saved is! Map) return result;
    final allowed = snapshot(factory).keys.toSet();
    for (final e in saved.entries) {
      if (e.key is String && allowed.contains(e.key) && valid(e.key, e.value)) {
        result[e.key] = copy(e.value);
      }
    }
    return result;
  }

  /// Migration keeps the active desktop and the old Free snapshot. The old
  /// shared visual preferences also seed Liquid when upgrading from Windows.
  /// Invalid inactive values are repaired individually, never all-or-nothing.
  void normalize(Map<String, dynamic> settings) {
    final style = settings['stile'] as Map<String, dynamic>;
    final active = names.contains(style['attuale'])
        ? style['attuale'] as String
        : 'libero';
    style['attuale'] = active;
    final old = style['profili'];
    final migrating = old is! Map || old.isEmpty;
    final profiles = <String, dynamic>{};
    for (final name in names) {
      profiles[name] = defaults(name)
        ..addAll(_safe(old is Map ? old[name] : null));
    }
    if (migrating) {
      // Historical presets changed only these layout keys, not the effects.
      const layout = {
        'bar.position',
        'bar.stile',
        'bar.listaFinestre',
        'dock.enabled',
        'dock.position',
        'dock.modo',
        'dock.iconSize',
        'dock.magnification',
        'windows.buttonsSide',
      };
      final legacy = snapshot(settings)
        ..removeWhere((k, _) => layout.contains(k));
      if (active != 'liquid') {
        (profiles['liquid'] as Map).addAll(copy(legacy) as Map);
      }
      if (active != 'libero') {
        (profiles['libero'] as Map).addAll(copy(legacy) as Map);
        try {
          (profiles['libero'] as Map).addAll(
            _safe(jsonDecode(style['libero'] as String)),
          );
        } catch (_) {
          /* An unreadable old snapshot cannot block switching. */
        }
      }
    }
    profiles[active] = snapshot(settings);
    style['profili'] = profiles;
  }

  void capture(Map<String, dynamic> settings) {
    final style = settings['stile'] as Map<String, dynamic>;
    (style['profili'] as Map)[style['attuale']] = snapshot(settings);
  }

  void activate(Map<String, dynamic> settings, String name) {
    final style = settings['stile'] as Map<String, dynamic>;
    if (style['attuale'] == name) return;
    capture(settings);
    final target = defaults(name)
      ..addAll(_safe((style['profili'] as Map)[name]));
    project(settings, target);
    style['attuale'] = name;
  }

  void project(Map<String, dynamic> settings, Map<String, dynamic> target) {
    for (final e in target.entries) {
      final segments = e.key.split('.');
      Map node = settings;
      for (final segment in segments.take(segments.length - 1)) {
        if (node[segment] is! Map) node[segment] = <String, dynamic>{};
        node = node[segment] as Map;
      }
      node[segments.last] = copy(e.value);
    }
  }
}
