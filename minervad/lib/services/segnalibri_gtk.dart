import 'dart:convert';
import 'dart:io';

/// Le cartelle fissate in Minerva File diventano segnalibri GTK, così si
/// trovano anche nelle finestre «Apri» e «Salva» degli altri programmi.
///
/// ── Perché esiste ────────────────────────────────────────────────────────
///
/// Chrome, GIMP, LibreOffice e quasi tutti gli altri aprono e salvano con la
/// finestra di GTK (nel nostro portale risponde `gtk`), che a sinistra mostra
/// `~/.config/gtk-3.0/bookmarks`. Le cartelle fissate nella colonna di
/// Minerva File non c'erano: per salvare un PDF nella cartella del progetto
/// bisognava ritrovarla a mano ogni volta (revisione del gestore file,
/// 6–11 ottobre 2026).
///
/// ── Si tocca solo quello che si è aggiunto ───────────────────────────────
///
/// Il file è di tutti: ci scrivono Nautilus, le impostazioni di KDE, e chi lo
/// modifica a mano. Qui si tiene a parte l'elenco delle righe aggiunte da
/// Minerva (`stato`), e si toglie SOLO quelle. Una cartella che era già fra i
/// segnalibri prima di fissarla non diventa «nostra»: togliendola dalla
/// colonna, resta dov'era.
class SegnalibriGtk {
  SegnalibriGtk({String? segnalibri, String? stato})
    : _segnalibri = File(
        segnalibri ??
            '${Platform.environment['XDG_CONFIG_HOME'] ?? '${Platform.environment['HOME']}/.config'}'
                '/gtk-3.0/bookmarks',
      ),
      _stato = File(
        stato ??
            '${Platform.environment['XDG_STATE_HOME'] ?? '${Platform.environment['HOME']}/.local/state'}'
                '/liquid-de/segnalibri-gtk.json',
      );

  final File _segnalibri;
  final File _stato;

  /// L'ultimo elenco allineato: lo stesso elenco due volte non rilegge niente.
  String _ultimo = '';
  Future<void> _coda = Future<void>.value();

  /// Porta i segnalibri a contenere le cartelle `fissate`. Ritorna vero se il
  /// file dei segnalibri è stato riscritto.
  Future<bool> allinea(List<String> fissate) {
    // Due eventi settings_changed possono arrivare prima della prima rename.
    // Li mettiamo in ordine, evitando che condividano lo stesso temporaneo
    // o che un elenco vecchio sovrascriva quello appena richiesto.
    final copia = List<String>.of(fissate);
    final turno = _coda.then((_) => _allinea(copia));
    _coda = turno.then<void>(
      (_) {},
      onError: (Object errore, StackTrace traccia) {},
    );
    return turno;
  }

  Future<bool> _allinea(List<String> fissate) async {
    final chiave = jsonEncode(fissate);
    if (chiave == _ultimo) return false;

    final volute = <String>[];
    for (final p in fissate) {
      if (!p.startsWith('/')) continue;
      final uri = Uri.directory(p).toString().replaceFirst(RegExp(r'/$'), '');
      if (!volute.contains(uri)) volute.add(uri);
    }

    final nostre = await _leggiStato();
    final righe = await _leggiRighe();

    final fuori = <String>[];
    final presenti = <String>{};
    for (final riga in righe) {
      final uri = riga.split(' ').first;
      // Una riga nostra che non è più fissata se ne va; tutte le altre restano.
      if (nostre.contains(uri) && !volute.contains(uri)) continue;
      fuori.add(riga);
      presenti.add(uri);
    }
    final nuoveNostre = nostre.where(volute.contains).toSet();
    for (final uri in volute) {
      if (presenti.contains(uri)) continue;
      fuori.add(uri);
      nuoveNostre.add(uri);
    }

    final cambiato = fuori.join('\n') != righe.join('\n');
    if (cambiato) {
      await _scriviAccanto(
        _segnalibri,
        fuori.isEmpty ? '' : '${fuori.join('\n')}\n',
      );
    }
    if (nuoveNostre.length != nostre.length ||
        !nuoveNostre.containsAll(nostre)) {
      await _scriviAccanto(
        _stato,
        '${jsonEncode({'nostre': nuoveNostre.toList()})}\n',
      );
    }
    // Solo un elenco scritto davvero può sopprimere il tentativo successivo:
    // prima un errore lasciava la cache avanzata e impediva ogni recupero.
    _ultimo = chiave;
    return cambiato;
  }

  Future<List<String>> _leggiRighe() async {
    try {
      return (await _segnalibri.readAsLines())
          .where((r) => r.trim().isNotEmpty)
          .toList();
    } on FileSystemException {
      return [];
    }
  }

  Future<Set<String>> _leggiStato() async {
    try {
      final d = jsonDecode(await _stato.readAsString());
      return ((d is Map ? d['nostre'] : null) as List? ?? const [])
          .whereType<String>()
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  /// Scritto accanto e poi rinominato: chi legge in quel momento trova il
  /// file vecchio o quello nuovo, mai metà.
  static Future<void> _scriviAccanto(File f, String testo) async {
    await f.parent.create(recursive: true);
    final provvisorio = File('${f.path}.minerva-$pid');
    await provvisorio.writeAsString(testo, flush: true);
    await provvisorio.rename(f.path);
  }
}
