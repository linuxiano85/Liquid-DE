import 'dart:convert';
import 'dart:io';

import '../../core/minerva_paths.dart';

/// Le cartelle che la Manutenzione non deve guardare, scelte da chi usa il
/// computer.
///
/// ── Perché non basta l'elenco scritto da noi ───────────────────────────────
///
/// Giacomo, 9 settembre 2026: «mettiamo esclusione di alcuni percorsi, ho ad
/// esempio i sorgenti di android nella cartella android/sdk, il mio progetto
/// di droidian».
///
/// `setaccio.dart` ne ha uno di serie — `Progetti`, `node_modules`, `Android`,
/// `flutter` — ed è una regola generale: si salta ciò che è **generato o
/// scaricato**. Ma nessun elenco scritto da noi può conoscere le cartelle di
/// chi usa il computer, e sbagliare per difetto qui vuol dire mostrare
/// migliaia di doppioni che non si devono toccare — cioè rendere inutile la
/// pagina.
///
/// ── Percorsi assoluti, non nomi ────────────────────────────────────────────
///
/// Una cartella si esclude perché è **quella**, non perché si chiama così.
/// `Documenti/foto` e `Scaricati/foto` sono due cose diverse, e un elenco di
/// nomi le prenderebbe tutte e due — compresa quella che volevi guardare.
class Escluse {
  Escluse({String? percorso})
      : _percorso =
            percorso ?? '${MinervaPaths.configDir}/manutenzione-escluse.json';

  final String _percorso;

  Future<List<String>> leggi() async {
    try {
      final f = File(_percorso);
      if (!await f.exists()) return const [];
      final d = jsonDecode(await f.readAsString());
      if (d is! List) return const [];
      return d.whereType<String>().where((x) => x.startsWith('/')).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Aggiunge una cartella e restituisce l'elenco nuovo.
  ///
  /// Chi c'è già non si aggiunge due volte, e una cartella **dentro** una già
  /// esclusa non si aggiunge affatto: escludere `Android/Sdk` quando c'è già
  /// `Android` non cambia niente, e lascerebbe due righe che dicono la stessa
  /// cosa. Al contrario, escludendo un genitore le figlie già escluse si
  /// tolgono: una sola riga vale per tutte.
  Future<List<String>> aggiungi(String percorso) async {
    final pulito = _pulisci(percorso);
    if (pulito == null) return leggi();
    final ora = await leggi();
    if (ora.any((e) => pulito == e || pulito.startsWith('$e/'))) return ora;
    final nuove = ora.where((e) => !e.startsWith('$pulito/')).toList()
      ..add(pulito)
      ..sort();
    await _salva(nuove);
    return nuove;
  }

  Future<List<String>> togli(String percorso) async {
    final pulito = _pulisci(percorso);
    if (pulito == null) return leggi();
    final nuove = (await leggi())..removeWhere((e) => e == pulito);
    await _salva(nuove);
    return nuove;
  }

  /// Assoluto, senza barra in fondo, senza risalite. Quello che non lo è non
  /// è una cartella: è un errore, e si lascia cadere invece di scriverlo.
  static String? _pulisci(String percorso) {
    var p = percorso.trim();
    if (!p.startsWith('/')) return null;
    if (p.contains('/../') || p.endsWith('/..')) return null;
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p == '/' ? null : p;
  }

  Future<void> _salva(List<String> quali) async {
    try {
      final f = File(_percorso);
      await f.parent.create(recursive: true);
      final accanto = File('$_percorso.nuovo');
      await accanto
          .writeAsString(const JsonEncoder.withIndent('  ').convert(quali));
      await accanto.rename(_percorso);
    } catch (e) {
      print('[MINERVA][MANUTENZIONE][ERRORE] escluse non salvate: $e');
    }
  }
}
