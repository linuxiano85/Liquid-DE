import 'dart:convert';
import 'dart:io';

import '../core/minerva_paths.dart';

/// Servizio per tracciare la frequenza di utilizzo delle app installate.
/// Salva i dati in config/app_usage.json.
class AppUsageTracker {
  final String _filePath;
  Map<String, int> _usage = {};

  AppUsageTracker({String? path})
      : _filePath = path ?? MinervaPaths.appUsageFile();

  /// Inizializza il tracker caricando i dati esistenti da file JSON.
  Future<void> init() async {
    final file = File(_filePath);
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final Map<String, dynamic> data = jsonDecode(content);
          _usage = data.map((key, value) => MapEntry(key, value as int));
        }
      } catch (e) {
        print('[MINERVA][USAGE][ERRORE] Impossibile caricare l\'utilizzo delle app: $e');
      }
    }
  }

  /// Incrementa il conteggio dei lanci per un dato ID app (.desktop) e lo salva.
  Future<void> recordLaunch(String id) async {
    _usage[id] = (_usage[id] ?? 0) + 1;
    await _save();
  }

  Future<void> _save() async {
    try {
      final file = File(_filePath);
      await file.parent.create(recursive: true);
      const encoder = JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(_usage));
    } catch (e) {
      print('[MINERVA][USAGE][ERRORE] Impossibile salvare l\'utilizzo delle app: $e');
    }
  }

  /// Restituisce gli ID delle app più frequenti ordinate in modo decrescente.
  List<String> getMostFrequent({int limit = 12}) {
    final sorted = _usage.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.map((e) => e.key).take(limit).toList();
  }
}
