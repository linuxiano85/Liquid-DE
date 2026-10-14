import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Preferenze esplicite per i moduli, applicate alle ricette di ogni kernel.
/// Non modifica mai i sorgenti: decide solo quali moduli chiedere a Kconfig.
class RegoleModuli {
  static const massimo = 2048;
  static final RegExp _nome = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  final String statoDir;
  Future<void> _coda = Future<void>.value();

  RegoleModuli({required this.statoDir});

  File get _file => File('$statoDir/regole-moduli.json');

  Future<Map<String, List<String>>> elenco() async {
    final dati = await _leggi();
    return {
      'mantieni': (dati['mantieni'] as Set<String>).toList()..sort(),
      'escludi': (dati['escludi'] as Set<String>).toList()..sort(),
    };
  }

  Future<Map<String, dynamic>> imposta(Object? nome, Object? scelta) {
    if (nome is! String || !_nome.hasMatch(nome)) {
      return Future.value({'ok': false, 'errore': 'Nome modulo non valido.'});
    }
    if (scelta is! String ||
        !const {'automatico', 'mantieni', 'escludi'}.contains(scelta)) {
      return Future.value({
        'ok': false,
        'errore': 'Scelta del modulo non valida.',
      });
    }
    final canonico = nome.replaceAll('-', '_');
    final risultato = Completer<Map<String, dynamic>>();
    _coda = _coda.then((_) async {
      try {
        final dati = await _leggi();
        final mantieni = dati['mantieni'] as Set<String>;
        final escludi = dati['escludi'] as Set<String>;
        mantieni.remove(canonico);
        escludi.remove(canonico);
        if (scelta == 'mantieni') mantieni.add(canonico);
        if (scelta == 'escludi') escludi.add(canonico);
        if (mantieni.length + escludi.length > massimo) {
          throw const FileSystemException(
            'Archivio pieno: elimina alcune regole prima di aggiungerne altre.',
          );
        }
        await _scrivi(mantieni, escludi);
        risultato.complete({'ok': true, 'regole': await elenco()});
      } catch (errore, traccia) {
        risultato.completeError(errore, traccia);
      }
    });
    return risultato.future;
  }

  Future<Map<String, Set<String>>> _leggi() async {
    try {
      final raw = jsonDecode(await _file.readAsString());
      if (raw is! Map || raw['versione'] != 1) {
        return {'mantieni': <String>{}, 'escludi': <String>{}};
      }
      Set<String> leggi(String chiave) => {
        if (raw[chiave] is List)
          for (final voce in raw[chiave] as List)
            if (voce is String && _nome.hasMatch(voce))
              voce.replaceAll('-', '_'),
      };
      final mantieni = leggi('mantieni');
      final escludi = leggi('escludi')..removeAll(mantieni);
      if (mantieni.length + escludi.length > massimo) {
        return {'mantieni': <String>{}, 'escludi': <String>{}};
      }
      return {'mantieni': mantieni, 'escludi': escludi};
    } on FileSystemException {
      return {'mantieni': <String>{}, 'escludi': <String>{}};
    } on FormatException {
      return {'mantieni': <String>{}, 'escludi': <String>{}};
    }
  }

  Future<void> _scrivi(Set<String> mantieni, Set<String> escludi) async {
    await Directory(statoDir).create(recursive: true);
    final temporaneo = File('${_file.path}.nuovo');
    await temporaneo.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'versione': 1,
        'mantieni': mantieni.toList()..sort(),
        'escludi': escludi.toList()..sort(),
      }),
      flush: true,
    );
    await temporaneo.rename(_file.path);
  }
}
