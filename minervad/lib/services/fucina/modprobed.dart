import 'dart:io';

/// Read current and legacy modprobed-db layouts without executing its shell
/// configuration. Installed software and a populated database are distinct.
Future<({String percorso, Set<String> moduli})> leggiModprobed(
  Map<String, String> ambiente,
) async {
  final casa = ambiente['HOME'] ?? '';
  String xdg(String key, String fallback) {
    final value = ambiente[key] ?? '';
    return (value.startsWith('/') ? value : fallback).replaceFirst(
      RegExp(r'/+$'),
      '',
    );
  }

  final config = xdg('XDG_CONFIG_HOME', '$casa/.config');
  final data = xdg('XDG_DATA_HOME', '$casa/.local/share');
  final variables = {
    'HOME': casa,
    'HOMEDIR': casa,
    'XDG_CONFIG_HOME': config,
    'XDG_DATA_HOME': data,
  };
  String? configured;
  for (final path in [
    '$config/modprobed-db/modprobed-db.conf',
    '$config/modprobed-db.conf',
    '$config/modprobed_db.conf',
  ]) {
    final file = File(path);
    if (!await file.exists()) continue;
    try {
      for (final line in await file.readAsLines()) {
        final match = RegExp(
          r'^\s*(?:export\s+)?DBPATH\s*=\s*(.*?)\s*$',
        ).firstMatch(line);
        if (match == null) continue;
        var value = match[1]!;
        if (value.startsWith('"') || value.startsWith("'")) {
          final quote = value[0];
          final end = value.indexOf(quote, 1);
          if (end < 0 ||
              !RegExp(r'^\s*(?:#.*)?$').hasMatch(value.substring(end + 1))) {
            continue;
          }
          value = value.substring(1, end);
        } else {
          value = value.split(RegExp(r'\s+#')).first.trim();
        }
        value = value.replaceAllMapped(
          RegExp(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)'),
          (m) => variables[m[1] ?? m[2]] ?? m[0]!,
        );
        if (value == '~' || value.startsWith('~/')) {
          value = casa + value.substring(1);
        }
        if (value.startsWith('/') && !value.contains(RegExp(r'[\$`\r\n]'))) {
          configured = value.replaceFirst(RegExp(r'/+$'), '');
        }
      }
    } on FormatException {
      // Malformed text is not a usable configuration or module database.
    } on FileSystemException {
      // Continue to the standard paths; no command or migration is run.
    }
    break; // The current configuration takes precedence over old copies.
  }
  final paths = configured != null
      ? ['$configured/modprobed.db']
      : [
          '$data/modprobed-db/modprobed.db',
          '$config/modprobed.db',
          '$casa/.config/modprobed.db',
        ];
  for (final path in paths.toSet()) {
    try {
      final text = await File(path).readAsString();
      final modules = <String>{};
      for (final line in text.split('\n')) {
        final name = line.trim().split(RegExp(r'\s+')).first;
        if (RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_-]*$').hasMatch(name)) {
          modules.add(name.replaceAll('-', '_'));
        }
      }
      return (percorso: path, moduli: modules);
    } on FormatException {
      // Malformed text is not a usable configuration or module database.
    } on FileSystemException {
      // A legacy database is still useful when migration has not happened.
    }
  }
  return (percorso: paths.first, moduli: <String>{});
}
