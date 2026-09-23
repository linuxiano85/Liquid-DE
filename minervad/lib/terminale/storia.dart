// storia.dart — La storia dei comandi, con l'esito e la cartella.
//
// La shell ha già la sua storia (`.zsh_history`, `fish_history`), ma sa solo
// COSA hai scritto. Qui si tiene anche DOVE (la cartella), COM'È ANDATA (il
// codice d'uscita) e QUANTO CI HA MESSO: è quello che permette alla
// predizione di proporre prima i comandi di questa cartella, e di pesare
// meno quelli che sono falliti.
//
// Un file JSONL, una riga per comando, solo in aggiunta:
//
//     {"quando":1757900000000,"cartella":"/home/g","comando":"ls -la","codice":0,"durata":12}
//
// Sta in `~/.local/share/minerva/terminale/storia.jsonl`. Si legge una volta
// all'avvio (le ultime `massimo` righe), si aggiunge una riga per comando.
//
// ── Cosa NON si salva ──────────────────────────────────────────────────────
//
// Un comando che comincia con uno spazio (la convenzione di `HISTCONTROL=
// ignorespace`, che tutti conoscono). Un comando vuoto. La password di
// `sudo` non passa mai di qui per costruzione: si scrive DENTRO il comando,
// in modo grezzo, e la storia registra solo la riga che l'ha lanciato.
library;

import 'dart:convert';
import 'dart:io';

class VoceStoria {
  VoceStoria({
    required this.quando,
    required this.cartella,
    required this.comando,
    required this.codice,
    required this.durata,
  });

  /// Millisecondi dal 1970.
  final int quando;
  final String cartella;
  final String comando;
  /// −1 se non si sa (la shell non ha detto D).
  final int codice;
  /// Millisecondi.
  final int durata;

  Map<String, dynamic> aMappa() => {
        'quando': quando,
        'cartella': cartella,
        'comando': comando,
        'codice': codice,
        'durata': durata,
      };

  static VoceStoria? daMappa(Map<String, dynamic> m) {
    final comando = m['comando'];
    if (comando is! String || comando.isEmpty) return null;
    return VoceStoria(
      quando: (m['quando'] as num?)?.toInt() ?? 0,
      cartella: '${m['cartella'] ?? ''}',
      comando: comando,
      codice: (m['codice'] as num?)?.toInt() ?? -1,
      durata: (m['durata'] as num?)?.toInt() ?? 0,
    );
  }
}

class Storia {
  Storia({this.percorso, this.massimo = 5000});

  /// Null: solo in memoria (le prove, e la Palestra).
  final String? percorso;
  final int massimo;
  final List<VoceStoria> voci = [];

  static String percorsoDiSerie() {
    final casa = Platform.environment['HOME'] ?? '/tmp';
    final dati = Platform.environment['XDG_DATA_HOME'] ?? '$casa/.local/share';
    return '$dati/minerva/terminale/storia.jsonl';
  }

  /// Legge il file, se c'è. Le righe rotte si saltano: un file di storia
  /// con una riga guasta non deve togliere il terminale a nessuno.
  void carica() {
    final p = percorso;
    if (p == null) return;
    final f = File(p);
    if (!f.existsSync()) return;
    List<String> righe;
    try {
      righe = f.readAsLinesSync();
    } catch (_) {
      return;
    }
    final da = righe.length > massimo ? righe.length - massimo : 0;
    for (final r in righe.skip(da)) {
      if (r.trim().isEmpty) continue;
      try {
        final v = VoceStoria.daMappa(jsonDecode(r) as Map<String, dynamic>);
        if (v != null) voci.add(v);
      } catch (_) {
        continue;
      }
    }
  }

  /// Aggiunge e scrive. Torna falso se non si salva (spazio, comando vuoto).
  bool aggiungi(VoceStoria v) {
    if (v.comando.isEmpty || v.comando.startsWith(' ')) return false;
    if (v.comando.trim().isEmpty) return false;
    voci.add(v);
    if (voci.length > massimo * 2) {
      voci.removeRange(0, voci.length - massimo);
    }
    final p = percorso;
    if (p != null) {
      try {
        final f = File(p);
        f.parent.createSync(recursive: true);
        f.writeAsStringSync('${jsonEncode(v.aMappa())}\n', mode: FileMode.append, flush: true);
      } catch (e) {
        stderr.writeln('minerva-terminale: storia non scritta: $e');
      }
    }
    return true;
  }

  /// Le voci che cominciano così, dalla più recente, senza doppioni: per
  /// ↑/↓ e per Ctrl+R (`contiene` invece di `comincia`).
  List<VoceStoria> cerca(String testo, {bool contiene = false, int quanti = 50}) {
    final out = <VoceStoria>[];
    final visti = <String>{};
    for (var i = voci.length - 1; i >= 0 && out.length < quanti; i--) {
      final v = voci[i];
      final ok = contiene ? v.comando.contains(testo) : v.comando.startsWith(testo);
      if (!ok) continue;
      if (!visti.add(v.comando)) continue;
      out.add(v);
    }
    return out;
  }
}
