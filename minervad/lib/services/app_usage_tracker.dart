import 'dart:convert';
import 'dart:io';

import '../core/minerva_paths.dart';

/// Quante volte, e A CHE ORA, si apre ogni app.
///
/// La Riva: «"Frequenti" e "Cosa vuoi fare" dall'uso vero: quante volte e a
/// che ora si apre ogni app, contate dal demone». Il quante c'era; l'ora no.
/// Con l'ora il menù può dire «adesso, di solito» — la posta la mattina, il
/// lettore la sera — invece di mettere sempre le stesse sei in cima.
///
/// Il file è `app_usage.json`:
///
///     { "lanci": { "firefox.desktop": 41, … },
///       "ore":   { "firefox.desktop": [0,0,…,5,7,…], … } }   // 24 caselle
///
/// Quello di prima era solo `{ "firefox.desktop": 41 }`: si legge ancora, e
/// i conti accumulati non si perdono (le ore partono da zero).
class AppUsageTracker {
  final String _filePath;
  Map<String, int> _usage = {};
  Map<String, List<int>> _ore = {};

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
          if (data['lanci'] is Map) {
            _usage = (data['lanci'] as Map)
                .map((k, v) => MapEntry('$k', (v as num).toInt()));
            if (data['ore'] is Map) {
              _ore = (data['ore'] as Map).map((k, v) => MapEntry('$k', _ventiquattro(v)));
            }
          } else {
            // Il formato di prima: solo i conti.
            _usage = data.map((key, value) => MapEntry(key, (value as num).toInt()));
          }
        }
      } catch (e) {
        print('[MINERVA][USAGE][ERRORE] Impossibile caricare l\'utilizzo delle app: $e');
      }
    }
  }

  static List<int> _ventiquattro(dynamic v) {
    final fuori = List<int>.filled(24, 0);
    if (v is List) {
      for (var i = 0; i < v.length && i < 24; i++) {
        fuori[i] = (v[i] as num?)?.toInt() ?? 0;
      }
    }
    return fuori;
  }

  /// Incrementa il conteggio dei lanci per un dato ID app (.desktop), segna
  /// l'ora, e salva. `quando` serve alle prove; di solito è adesso.
  Future<void> recordLaunch(String id, {DateTime? quando}) async {
    _usage[id] = (_usage[id] ?? 0) + 1;
    final ora = (quando ?? DateTime.now()).hour;
    (_ore[id] ??= List<int>.filled(24, 0))[ora]++;
    await _save();
  }

  Future<void> _save() async {
    try {
      final file = File(_filePath);
      await file.parent.create(recursive: true);
      const encoder = JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert({'lanci': _usage, 'ore': _ore}));
    } catch (e) {
      print('[MINERVA][USAGE][ERRORE] Impossibile salvare l\'utilizzo delle app: $e');
    }
  }

  /// Quante volte è stata aperta un'app: serve al menù per la vista
  /// «Frequenti» e per mettere prima, a parità di risposta, quella che si usa.
  int lanci(String id) => _usage[id] ?? 0;

  /// Quante volte è stata aperta intorno a quest'ora: l'ora stessa e le due
  /// accanto (le 8:55 e le 9:05 sono la stessa abitudine).
  int adesso(String id, {DateTime? quando}) {
    final ore = _ore[id];
    if (ore == null) return 0;
    final h = (quando ?? DateTime.now()).hour;
    return ore[(h + 23) % 24] + ore[h] + ore[(h + 1) % 24];
  }

}
