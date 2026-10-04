import 'dart:async';
import 'dart:io';

import '../core/minerva_paths.dart';
import 'scorciatoie.dart';

/// Una singola voce del pannello «Scorciatoie».
///
/// [combos] contiene tutte le combinazioni che eseguono la stessa azione:
/// più bind con la stessa categoria e descrizione vengono fusi in un'unica
/// voce, così l'utente non vede tre righe identiche.
class KeybindEntry {
  final String category;
  final String description;
  final List<KeyCombo> combos = [];

  KeybindEntry(this.category, this.description);

  Map<String, dynamic> toJson() => {
        'category': category,
        'description': description,
        'combos': combos.map((c) => c.toJson()).toList(),
      };
}

/// Una combinazione: lista di modificatori + tasto finale.
/// I nomi restano grezzi (SUPER, Return, mouse:272): la traduzione nella
/// lingua dell'utente avviene nella shell QML, così cambiare lingua è immediato.
class KeyCombo {
  final List<String> mods;
  final String key;

  const KeyCombo(this.mods, this.key);

  String get signature => '${mods.join('+')}|$key';

  Map<String, dynamic> toJson() => {'mods': mods, 'key': key};
}

/// Legge `config/scorciatoie.minerva` e ne ricava l'elenco delle scorciatoie
/// da mostrare all'utente, tenendolo aggiornato se il file cambia.
///
/// ── Perché NON legge più il file di Hyprland ─────────────────────────────
///
/// Fino all'11 agosto 2026 questo servizio faceva il parsing di
/// `config/hypr/keybinds.conf`: `bind = $mod SHIFT, K, dispatcher, argomenti`.
/// Cioè il pannello F1 di Minerva sapeva leggere la sintassi di un
/// compositore. Cambiando compositore sarebbe stato un secondo file da
/// riscrivere, e ogni cambiamento di quella sintassi lo avrebbe rotto in
/// silenzio — un promemoria vuoto non dà nessun errore.
///
/// Adesso la sorgente è nostra e il file di Hyprland ne è il PRODOTTO
/// (`scripts/minerva-scorciatoie`, e una prova che li tiene allineati).
///
/// Formato atteso nel file:
/// ```
/// #@ Categoria | Descrizione leggibile
/// bind = $mod SHIFT, K, dispatcher, argomenti
/// ```
/// L'annotazione vale per tutti i bind consecutivi che la seguono.
///
/// ── E per NON farne comparire una: `#@-` ─────────────────────────────────
///
/// Alcune combinazioni non vanno nel promemoria: il rilascio di Alt che
/// conferma l'Alt+Tab non è una scorciatoia da imparare, è il seguito di
/// un'altra. Prima si provava a ottenerlo NON scrivendo l'annotazione — e non
/// funzionava, perché quella precedente vale finché non ne arriva un'altra:
/// il tasto compariva sotto la descrizione della riga sopra.
///
/// Visto sullo schermo l'11 agosto 2026: il pannello F1 diceva che `Alt_L`
/// serve a «tornare indietro nell'elenco delle finestre». Non è vero, ed è il
/// modo più veloce di rendere un promemoria inaffidabile.
///
/// `#@-` da solo, su una riga, spegne l'annotazione in corso.
class KeybindService {
  final String _configPath;
  List<KeybindEntry> _entries = [];
  StreamSubscription? _watcher;

  /// Notifica ricaricamenti del file, così il core può ritrasmettere l'elenco.
  final _changes = StreamController<List<KeybindEntry>>.broadcast();
  Stream<List<KeybindEntry>> get changes => _changes.stream;

  KeybindService({String? path})
      : _configPath = path ?? MinervaPaths.shippedFile('scorciatoie.minerva');

  List<KeybindEntry> get entries => _entries;

  List<Map<String, dynamic>> toJson() =>
      _entries.map((e) => e.toJson()).toList();

  /// Le stesse scorciatoie, tradotte per **minerva-wayland**.
  ///
  /// Sono una cosa diversa da `toJson()`, e non viaggiano insieme apposta:
  /// quello è il promemoria di Super+K, fatto per gli occhi di chi usa il
  /// computer, con le categorie e le descrizioni; queste sono righe per un
  /// compositore, e le legge `compositore/src/main.c`.
  ///
  /// Si rilegge il file da capo invece di riusare `_entries`: quel parser lì
  /// tiene solo quello che serve al promemoria — categoria, descrizione, tasti
  /// — e ha già buttato via i flag e la forma esatta dell'azione. Rileggere
  /// costa un millisecondo e succede quando cambia il file.
  List<String> perMinervaWayland() {
    try {
      return Scorciatoie.daFile(_configPath).perMinervaWayland(
        // La sorgente non la dichiara perché sotto Hyprland la dichiara il
        // compositore, in `~/.config/hypr/minerva-paths.conf`.
        anche: {'minerva': MinervaPaths.installRoot},
      );
    } catch (e) {
      // Una scorciatoia scritta male non deve poter spegnere il servizio: il
      // promemoria continua a funzionare, e questa lista torna vuota — cioè
      // il compositore resta senza scorciatoie, che è brutto ma visibile.
      print('[MINERVA][KEYBIND][ERRORE] Non riesco a tradurle per '
          'minerva-wayland: $e');
      return const [];
    }
  }

  Future<void> init() async {
    await reload();
    _startWatcher();
  }

  Future<void> reload() async {
    try {
      final file = File(_configPath);
      if (!await file.exists()) {
        print('[MINERVA][KEYBIND][ERRORE] File non trovato: $_configPath');
        _entries = [];
        return;
      }
      _entries = _parse(await file.readAsLines());
      print('[MINERVA][KEYBIND][OK] ${_entries.length} scorciatoie caricate.');
    } catch (e) {
      print('[MINERVA][KEYBIND][ERRORE] Lettura fallita: $e');
      _entries = [];
    }
  }

  void _startWatcher() {
    final file = File(_configPath);
    try {
      _watcher = file.parent.watch().listen((event) async {
        // ── Il salvataggio per rinomina (30 settembre 2026) ─────────────
        //
        // Molti editor (Kate e tutto ciò che usa QSaveFile, gedit) non
        // scrivono dentro il file: scrivono un file temporaneo accanto e lo
        // RINOMINANO sopra. L'evento è uno spostamento, e il nome del file
        // sta in `destination`, non in `path`: guardando solo `path` il
        // salvataggio non si vedeva, e il compositore restava con le
        // scorciatoie di prima.
        final eIlNostro = event.path == file.path ||
            (event is FileSystemMoveEvent && event.destination == file.path);
        if (!eIlNostro) return;
        if (event.type == FileSystemEvent.delete) return;
        await Future.delayed(const Duration(milliseconds: 120));
        await reload();
        _changes.add(_entries);
      });
    } catch (e) {
      print('[MINERVA][KEYBIND][ERRORE] Watcher non avviato: $e');
    }
  }

  // ── Dalla sorgente al promemoria ───────────────────────────────────────
  //
  // Niente più regexp sulla sintassi di Hyprland: `Scorciatoie` legge il
  // formato nostro e torna oggetti. Qui resta solo il raggruppamento — più
  // combinazioni che fanno la stessa cosa diventano una riga sola, o
  // l'elenco mostrerebbe tre volte «apri il promemoria».

  List<KeybindEntry> _parse(List<String> lines) {
    final sorgente = Scorciatoie.leggi(lines.join('\n'));
    final ordinati = <String, KeybindEntry>{};
    final ordine = <String>[];

    for (final s in sorgente.daMostrare) {
      final combo = _combo(s, sorgente.variabili);
      if (combo == null) continue;

      final chiave = '${s.categoria} ${s.descrizione}';
      final voce = ordinati.putIfAbsent(chiave, () {
        ordine.add(chiave);
        return KeybindEntry(s.categoria!, s.descrizione!);
      });
      if (!voce.combos.any((c) => c.signature == combo.signature)) {
        voce.combos.add(combo);
      }
    }

    return [for (final k in ordine) ordinati[k]!];
  }

  /// Da una scorciatoia della sorgente alla combinazione da mostrare.
  KeyCombo? _combo(Scorciatoia s, Map<String, String> vars) {
    final key = _expand(s.tasto, vars);
    if (key.isEmpty) return null;
    final mods = s.modificatori
        .map((m) => _expand(m, vars))
        .expand((m) => m.split(RegExp(r'[\s+]+')))
        .where((m) => m.isNotEmpty)
        .map(_canonicalMod)
        .where((m) => m != null)
        .cast<String>()
        .toList();
    return KeyCombo(mods, key);
  }

  /// Sostituisce le variabili `$nome` con il loro valore.
  String _expand(String value, Map<String, String> vars) {
    var out = value;
    for (var i = 0; i < 5 && out.contains(r'$'); i++) {
      out = out.replaceAllMapped(
        RegExp(r'\$(\w+)'),
        (m) => vars[m.group(1)] ?? m.group(0)!,
      );
    }
    return out.trim();
  }

  /// Normalizza gli alias dei modificatori accettati da Hyprland.
  String? _canonicalMod(String mod) {
    switch (mod.toUpperCase()) {
      case 'SUPER':
      case 'MOD4':
      case 'WIN':
      case 'LOGO':
        return 'SUPER';
      case 'SHIFT':
        return 'SHIFT';
      case 'CTRL':
      case 'CONTROL':
        return 'CTRL';
      case 'ALT':
      case 'MOD1':
        return 'ALT';
      case 'CAPS':
      case 'MOD2':
      case 'MOD3':
      case 'MOD5':
        return null;
      default:
        return null;
    }
  }

  Future<void> dispose() async {
    await _watcher?.cancel();
    await _changes.close();
  }
}
