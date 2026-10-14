import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Profili locali di configurazione Fucina, uno per macchina o scenario.
///
/// Conserva le preferenze e una piccola impronta hardware, non seriali,
/// percorsi o l'inventario grezzo. Le scelte vengono validate dal servizio
/// prima di arrivare qui.
class ProfiliKernel {
  static const massimo = 20;

  final String statoDir;
  Future<void> _coda = Future<void>.value();

  ProfiliKernel({required this.statoDir});

  File get _file => File('$statoDir/profili-kernel.json');

  Future<List<Map<String, dynamic>>> elenco() async {
    try {
      final raw = jsonDecode(await _file.readAsString());
      if (raw is! Map || raw['profili'] is! List) return [];
      final validi = <Map<String, dynamic>>[];
      for (final voce in raw['profili'] as List) {
        if (voce is! Map) continue;
        final profilo = Map<String, dynamic>.from(voce);
        if (_valido(profilo)) validi.add(profilo);
      }
      validi.sort(
        (a, b) =>
            b['aggiornato'].toString().compareTo(a['aggiornato'].toString()),
      );
      return validi;
    } on FileSystemException {
      return [];
    } on FormatException {
      return [];
    }
  }

  Future<Map<String, dynamic>> salva({
    required String nome,
    required Map<String, dynamic> scelte,
    required Map<String, dynamic> hardware,
    required Map<String, dynamic> evidenze,
  }) async {
    return _inCoda(() async {
      final pulito = nome.trim();
      if (!_nomeValido(pulito)) {
        throw const FormatException(
          'Il nome del profilo deve contenere da 1 a 48 caratteri, senza righe nuove.',
        );
      }
      final risultato = <Map<String, dynamic>>[];
      try {
        final raw = jsonDecode(await _file.readAsString());
        if (raw is Map && raw['profili'] is List) {
          for (final voce in raw['profili'] as List) {
            if (voce is Map) {
              final profilo = Map<String, dynamic>.from(voce);
              if (_valido(profilo)) risultato.add(profilo);
            }
          }
        }
      } on FileSystemException {
        // Primo profilo.
      } on FormatException {
        // Un indice corrotto non impedisce di ricrearlo.
      }

      final esistente = risultato.indexWhere(
        (p) => p['nome'].toString().toLowerCase() == pulito.toLowerCase(),
      );
      if (esistente < 0 && risultato.length >= massimo) {
        throw const FileSystemException(
          'Hai raggiunto il limite di 20 profili. Elimina un profilo e riprova.',
        );
      }
      final ora = DateTime.now().toUtc().toIso8601String();
      final precedente = esistente < 0 ? null : risultato.removeAt(esistente);
      final profilo = <String, dynamic>{
        'id': precedente?['id'] ?? _nuovoId(risultato),
        'nome': pulito,
        'creato': precedente?['creato'] ?? ora,
        'aggiornato': ora,
        'schema': 1,
        'scelte': scelte,
        'hardware': _hardware(hardware),
        'evidenze': _evidenze(evidenze),
      };
      risultato.insert(0, profilo);
      await _scrivi(risultato.take(massimo).toList());
      return profilo;
    });
  }

  Future<Map<String, dynamic>?> carica(Object? id) async {
    if (id is! String || !RegExp(r'^[0-9]{1,20}$').hasMatch(id)) return null;
    for (final profilo in await elenco()) {
      if (profilo['id'] == id) return profilo;
    }
    return null;
  }

  Future<bool> elimina(Object? id) async {
    if (id is! String || !RegExp(r'^[0-9]{1,20}$').hasMatch(id)) return false;
    return _inCoda(() async {
      final profili = await elenco();
      final prima = profili.length;
      profili.removeWhere((p) => p['id'] == id);
      if (profili.length == prima) return false;
      await _scrivi(profili);
      return true;
    });
  }

  Future<T> _inCoda<T>(Future<T> Function() operazione) {
    final risultato = Completer<T>();
    _coda = _coda.then((_) async {
      try {
        risultato.complete(await operazione());
      } catch (errore, traccia) {
        risultato.completeError(errore, traccia);
      }
    });
    return risultato.future;
  }

  Future<void> _scrivi(List<Map<String, dynamic>> profili) async {
    await Directory(statoDir).create(recursive: true);
    final temporaneo = File('${_file.path}.nuovo');
    await temporaneo.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert({'versione': 1, 'profili': profili}),
      flush: true,
    );
    await temporaneo.rename(_file.path);
  }

  String _nuovoId(List<Map<String, dynamic>> profili) {
    final usati = profili.map((p) => p['id']).whereType<String>().toSet();
    var micros = DateTime.now().microsecondsSinceEpoch;
    while (usati.contains('$micros')) {
      micros++;
    }
    return '$micros';
  }

  Map<String, dynamic> _hardware(Map<String, dynamic> origine) => {
    for (final chiave in const ['cpu', 'fornitore', 'livelloX86'])
      if (origine[chiave] is String && origine[chiave].toString().length <= 160)
        chiave: origine[chiave],
  };

  Map<String, dynamic> _evidenze(Map<String, dynamic> origine) {
    final risultato = <String, dynamic>{};
    for (final chiave in const [
      'dispositivi',
      'moduli',
      'dispositiviStorici',
    ]) {
      final valore = origine[chiave];
      if (valore is int && valore >= 0 && valore <= 1000000) {
        risultato[chiave] = valore;
      }
    }
    for (final chiave in const ['filesystemMontati', 'lsmAttivi']) {
      final valore = origine[chiave];
      if (valore is! List) continue;
      risultato[chiave] = valore
          .whereType<String>()
          .where(
            (voce) =>
                voce.length <= 64 && !voce.contains(RegExp(r'[\x00-\x1f\x7f]')),
          )
          .take(128)
          .toList();
    }
    return risultato;
  }

  bool _valido(Map<String, dynamic> p) =>
      p['schema'] == 1 &&
      p['id'] is String &&
      RegExp(r'^[0-9]{1,20}$').hasMatch(p['id'] as String) &&
      p['nome'] is String &&
      _nomeValido(p['nome'] as String) &&
      p['scelte'] is Map;

  bool _nomeValido(String nome) =>
      nome.isNotEmpty &&
      nome.length <= 48 &&
      !nome.contains('\n') &&
      !nome.contains('\r') &&
      !nome.contains(RegExp(r'[\x00-\x1f\x7f]'));
}
