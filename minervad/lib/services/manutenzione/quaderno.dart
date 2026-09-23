import 'dart:convert';
import 'dart:io';

import '../../core/minerva_paths.dart';

/// Quanto spazio Minerva Manutenzione ha recuperato in tutto, da sempre.
///
/// ── Perché tenerne il conto ────────────────────────────────────────────────
///
/// Giacomo, 9 settembre 2026: «possiamo mettere un riepilogo di tutto lo spazio
/// che è stato recuperato con la app? Giga totali ad esempio? Una cosa tipo
/// CleanMyMac».
///
/// È il numero che dà senso a tutto il resto. Ogni singola pulizia si dimentica
/// il giorno dopo — «ho tolto 384 MB» non se lo ricorda nessuno — mentre «da
/// quando c'è, questa app ti ha restituito dieci giga» è la ragione per cui
/// vale la pena riaprirla.
///
/// ── E perché è l'unico numero di questo programma che si RICORDA ───────────
///
/// L'inventario, di proposito, non si ricorda niente: `du` deve percorrere le
/// cartelle vere ogni volta, perché un conto vecchio di mezz'ora direbbe il
/// falso proprio su quello che hai appena pulito. Questo invece è una storia,
/// e una storia si scrive.
///
/// ── Cosa ci si scrive, e cosa NO ───────────────────────────────────────────
///
/// Solo i byte **usciti davvero**: quelli che il pulitore ha tolto e per cui
/// ha risposto di sì. Niente di quello che è stato promesso, niente di quello
/// che è stato spuntato e poi rifiutato. Un totale gonfiato è la bugia più
/// facile da dire qui dentro — nessuno può controllarla — ed è per questo che
/// va detto in chiaro che non si fa.
class Quaderno {
  Quaderno({String? percorso})
      : _percorso = percorso ?? '${MinervaPaths.configDir}/manutenzione.json';

  final String _percorso;

  /// Quanto è stato recuperato in tutto, quante volte, e da quando.
  Future<Map<String, dynamic>> leggi() async {
    try {
      final f = File(_percorso);
      if (!await f.exists()) return _vuoto;
      final testo = await f.readAsString();
      if (testo.trim().isEmpty) return _vuoto;
      final d = jsonDecode(testo);
      if (d is! Map) return _vuoto;
      return {
        'byte': (d['byte'] as num?)?.toInt() ?? 0,
        'volte': (d['volte'] as num?)?.toInt() ?? 0,
        'dal': d['dal'] as String? ?? '',
        'ultima': d['ultima'] as String? ?? '',
      };
    } catch (_) {
      // Un quaderno illeggibile non deve impedire una pulizia: il conto
      // riparte, e ricominciare da zero è meglio che non funzionare.
      return _vuoto;
    }
  }

  static const Map<String, dynamic> _vuoto = {
    'byte': 0,
    'volte': 0,
    'dal': '',
    'ultima': '',
  };

  /// Aggiunge quello che è stato tolto adesso, e restituisce il totale nuovo.
  ///
  /// Zero byte non è una pulizia: se non è uscito niente — perché era già
  /// pulito, o perché hai annullato la password — non si segna niente. Un
  /// contatore di «volte» che cresce senza che sia successo nulla rende
  /// inutile anche il numero accanto.
  Future<Map<String, dynamic>> segna(int byte) async {
    final ora = await leggi();
    if (byte <= 0) return ora;
    final adesso = DateTime.now().toIso8601String();
    final nuovo = {
      'byte': (ora['byte'] as int) + byte,
      'volte': (ora['volte'] as int) + 1,
      'dal': (ora['dal'] as String).isEmpty ? adesso : ora['dal'],
      'ultima': adesso,
    };
    try {
      final f = File(_percorso);
      await f.parent.create(recursive: true);
      // Di fianco e poi al suo posto: se manca la corrente a metà scrittura,
      // il quaderno è quello di prima e intero, non mezzo. È la stessa regola
      // con cui si salvano le impostazioni.
      final accanto = File('$_percorso.nuovo');
      await accanto.writeAsString(const JsonEncoder.withIndent('  ')
          .convert(nuovo));
      await accanto.rename(_percorso);
    } catch (e) {
      // Non aver potuto scrivere la storia non annulla la pulizia, che è
      // già successa. Si dice e si va avanti.
      print('[MINERVA][MANUTENZIONE][ERRORE] quaderno non salvato: $e');
    }
    return nuovo;
  }
}
