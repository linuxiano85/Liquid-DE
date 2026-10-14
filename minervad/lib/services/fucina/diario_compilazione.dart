import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Il diario su disco, indipendente dalla coda ridotta inviata alla finestra.
/// Ogni tentativo ha una cartella propria, anche se il rilascio è lo stesso.
class DiarioCompilazione {
  final String percorso;
  final IOSink _uscita;
  Timer? _timer;
  Future<void>? _flushInCorso;
  bool _chiuso = false;
  String errore = '';

  DiarioCompilazione(File file) : this._(file.path, file.openWrite());

  DiarioCompilazione._(this.percorso, this._uscita) {
    // Un disco pieno può far fallire il sink anche senza un flush esplicito.
    // Si osserva subito done: l'errore non deve uscire nella zona del demone.
    unawaited(_uscita.done.then<void>((_) {}, onError: _guasto));
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(flush());
    });
  }

  static Future<DiarioCompilazione> apri(
    String statoDir,
    String rilascio,
  ) async {
    final base = await Directory(
      '$statoDir/log-compilazioni',
    ).create(recursive: true);
    final cartella = await base.createTemp('$rilascio-');
    final file = await File('${cartella.path}/compilazione.log').create();
    return DiarioCompilazione(file);
  }

  void _guasto(Object e, [StackTrace? trace]) {
    if (errore.isEmpty) errore = '$e';
  }

  void riga(String testo, {bool stderr = false}) {
    if (_chiuso || errore.isNotEmpty) return;
    try {
      _uscita.writeln(stderr ? '[stderr] $testo' : testo);
    } catch (e) {
      _guasto(e);
    }
  }

  void evento(String tipo, Map<String, dynamic> dati) {
    riga('[${DateTime.now().toIso8601String()}] $tipo ${jsonEncode(dati)}');
  }

  Future<void> flush() {
    if (errore.isNotEmpty) return Future.value();
    return _flushInCorso ??= _flushUnaVolta();
  }

  Future<void> _flushUnaVolta() async {
    try {
      await _uscita.flush();
    } catch (e) {
      _guasto(e);
    } finally {
      _flushInCorso = null;
    }
  }

  Future<void> chiudi() async {
    if (_chiuso) return;
    _chiuso = true;
    _timer?.cancel();
    await flush();
    try {
      await _uscita.close();
    } catch (e) {
      _guasto(e);
    }
  }
}
