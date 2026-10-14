import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Ricorda i modalias visti dalla Fucina su questo account.
///
/// Si conservano identificatori standard di compatibilità dei driver, non
/// numeri seriali né percorsi personali. Il limite impedisce una crescita
/// senza fine; il file vive nella directory di stato privata di Minerva.
class StoricoDispositivi {
  static const massimo = 2048;

  final String statoDir;
  Future<void> _coda = Future<void>.value();

  StoricoDispositivi({required this.statoDir});

  File get _file => File('$statoDir/dispositivi-visti.json');

  Future<List<String>> leggi() async {
    try {
      final contenuto = jsonDecode(await _file.readAsString());
      if (contenuto is! Map || contenuto['dispositivi'] is! List) return [];
      final visti = <String>{};
      for (final riga in contenuto['dispositivi'] as List) {
        if (riga is! Map) continue;
        final alias = riga['modalias'];
        if (alias is String && _valido(alias)) visti.add(alias.trim());
      }
      return visti.toList()..sort();
    } on FileSystemException {
      return [];
    } on FormatException {
      return [];
    }
  }

  /// Unisce il rilievo corrente. Le scritture sono serializzate perché due
  /// finestre possono chiedere il rilievo quasi nello stesso momento.
  Future<void> aggiorna(Iterable<String> modalias) {
    final correnti = modalias.map((x) => x.trim()).where(_valido).toSet();
    final prossima = _coda.then((_) => _aggiorna(correnti));
    _coda = prossima.catchError((Object _) {});
    return prossima;
  }

  /// Dimentica le periferiche precedenti. Il prossimo rilievo ricorderà di
  /// nuovo solo quelle collegate in quel momento.
  Future<void> dimentica() {
    final prossima = _coda.then((_) async {
      try {
        await _file.delete();
      } on FileSystemException {
        // Il registro può non essere mai stato creato.
      }
    });
    _coda = prossima.catchError((Object _) {});
    return prossima;
  }

  Future<void> _aggiorna(Set<String> correnti) async {
    final dati = <String, Map<String, dynamic>>{};
    try {
      final contenuto = jsonDecode(await _file.readAsString());
      final elenco = contenuto is Map ? contenuto['dispositivi'] : null;
      if (elenco is List) {
        for (final riga in elenco) {
          if (riga is! Map) continue;
          final alias = riga['modalias'];
          if (alias is String && _valido(alias)) {
            dati[alias] = Map<String, dynamic>.from(riga);
          }
        }
      }
    } on FileSystemException {
      // Primo rilievo: il registro non esiste ancora.
    } on FormatException {
      // Un file incompleto non impedisce il rilievo corrente.
    }

    final ora = DateTime.now().toUtc().toIso8601String();
    for (final alias in correnti) {
      final precedente = dati[alias];
      dati[alias] = {
        'modalias': alias,
        'primoVisto': precedente?['primoVisto'] ?? ora,
        'ultimoVisto': ora,
        'rilevamenti': ((precedente?['rilevamenti'] as num?)?.toInt() ?? 0) + 1,
      };
    }

    final elenco = dati.values.toList()
      ..sort((a, b) => '${b['ultimoVisto']}'.compareTo('${a['ultimoVisto']}'));
    final contenuto = jsonEncode({
      'versione': 1,
      'dispositivi': elenco.take(massimo).toList(),
    });
    await Directory(statoDir).create(recursive: true);
    final temporaneo = File('${_file.path}.nuovo');
    await temporaneo.writeAsString(contenuto, flush: true);
    await temporaneo.rename(_file.path);
  }

  static bool _valido(String alias) =>
      alias.length <= 1024 && alias.contains(':') && !alias.contains('\n');
}
