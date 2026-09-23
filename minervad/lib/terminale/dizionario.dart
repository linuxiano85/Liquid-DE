// dizionario.dart — I comandi spiegati in italiano: una tabella sola.
//
// `config/dizionario-comandi.json` serve a tre cose, e per questo è UNA
// tabella e non tre: la predizione (gli esempi che cominciano come quello
// che stai scrivendo, con la spiegazione accanto), «spiega» su un blocco
// (cosa fa questo comando, opzione per opzione), e la Palestra (le lezioni
// rimandano qui). Tre copie sarebbero tre verità diverse nel giro di un mese.
//
// Ogni voce: `comando`, `descrizione`, `categoria`, `livello` (1–5, quello
// della Palestra), `pericolo` (0 niente, 1 tocca dei file, 2 tocca il
// sistema, 3 cancella e non torna), `opzioni` [{flag, spiegazione}],
// `esempi` [{comando, spiegazione}], `vedi` [nomi].
library;

import 'dart:convert';
import 'dart:io';

class Opzione {
  const Opzione(this.flag, this.spiegazione);
  final String flag;
  final String spiegazione;

  /// Le forme che questa opzione accetta: `-A N / -B N / -C N` ne dà tre,
  /// `-l` una, `+x` una. Si confronta il primo pezzo prima dello spazio.
  List<String> get forme => flag
      .split('/')
      .map((f) => f.trim().split(' ').first)
      .where((f) => f.isNotEmpty)
      .toList();
}

class Esempio {
  const Esempio(this.comando, this.spiegazione);
  final String comando;
  final String spiegazione;
}

class Voce {
  Voce({
    required this.comando,
    required this.descrizione,
    required this.categoria,
    required this.livello,
    required this.pericolo,
    required this.opzioni,
    required this.esempi,
    required this.vedi,
  });

  final String comando;
  final String descrizione;
  final String categoria;
  final int livello;
  final int pericolo;
  final List<Opzione> opzioni;
  final List<Esempio> esempi;
  final List<String> vedi;

  /// L'opzione che spiega questo pezzo, se c'è: `-la` si spiega come `-l`
  /// più `-a`, `--color=auto` come `--color=auto` o come `--color`.
  Opzione? opzione(String pezzo) {
    for (final o in opzioni) {
      for (final f in o.forme) {
        if (f == pezzo) return o;
        if (pezzo.contains('=') && f == pezzo.split('=').first) return o;
        if (f.contains('=') && f.split('=').first == pezzo.split('=').first) {
          return o;
        }
      }
    }
    return null;
  }

  Map<String, dynamic> aMappa() => {
        'comando': comando,
        'descrizione': descrizione,
        'categoria': categoria,
        'livello': livello,
        'pericolo': pericolo,
        'opzioni': [
          for (final o in opzioni) {'flag': o.flag, 'spiegazione': o.spiegazione}
        ],
        'esempi': [
          for (final e in esempi) {'comando': e.comando, 'spiegazione': e.spiegazione}
        ],
        'vedi': vedi,
      };
}

/// Una parte di una riga spiegata: un comando della pipeline con le sue
/// opzioni riconosciute e quelle no.
class Spiegazione {
  Spiegazione({
    required this.comando,
    required this.descrizione,
    required this.conosciuto,
    required this.pericolo,
    required this.opzioni,
    required this.sconosciute,
    required this.argomenti,
  });
  final String comando;
  final String descrizione;
  final bool conosciuto;
  final int pericolo;
  final List<List<String>> opzioni;
  final List<String> sconosciute;
  final List<String> argomenti;

  Map<String, dynamic> aMappa() => {
        'comando': comando,
        'descrizione': descrizione,
        'conosciuto': conosciuto,
        'pericolo': pericolo,
        'opzioni': opzioni,
        'sconosciute': sconosciute,
        'argomenti': argomenti,
      };
}

class Dizionario {
  Dizionario(this.voci) {
    for (final v in voci) {
      _perNome[v.comando] = v;
    }
  }

  factory Dizionario.vuoto() => Dizionario(const []);

  /// Legge il JSON. Un file mancante o rotto dà un dizionario vuoto e un
  /// avviso: il terminale deve aprirsi lo stesso.
  factory Dizionario.daFile(String percorso) {
    try {
      final testo = File(percorso).readAsStringSync();
      return Dizionario.daJson(testo);
    } catch (e) {
      stderr.writeln('minerva-terminale: dizionario non letto ($percorso): $e');
      return Dizionario.vuoto();
    }
  }

  factory Dizionario.daJson(String testo) {
    final m = jsonDecode(testo) as Map<String, dynamic>;
    final out = <Voce>[];
    for (final c in (m['comandi'] as List)) {
      final v = c as Map<String, dynamic>;
      out.add(Voce(
        comando: '${v['comando']}',
        descrizione: '${v['descrizione'] ?? ''}',
        categoria: '${v['categoria'] ?? ''}',
        livello: (v['livello'] as num?)?.toInt() ?? 1,
        pericolo: (v['pericolo'] as num?)?.toInt() ?? 0,
        opzioni: [
          for (final o in (v['opzioni'] as List? ?? const []))
            Opzione('${o['flag']}', '${o['spiegazione'] ?? ''}')
        ],
        esempi: [
          for (final e in (v['esempi'] as List? ?? const []))
            Esempio('${e['comando']}', '${e['spiegazione'] ?? ''}')
        ],
        vedi: [for (final s in (v['vedi'] as List? ?? const [])) '$s'],
      ));
    }
    return Dizionario(out);
  }

  final List<Voce> voci;
  final Map<String, Voce> _perNome = {};

  Voce? trova(String comando) => _perNome[comando];
  bool get vuoto => voci.isEmpty;

  /// Tutti gli esempi, con la voce di provenienza: per la predizione.
  Iterable<(Voce, Esempio)> get esempi sync* {
    for (final v in voci) {
      for (final e in v.esempi) {
        yield (v, e);
      }
    }
  }

  // ── Spiegare una riga ────────────────────────────────────────────────

  /// Spezza una riga nelle sue parti: `ls -la | grep x && echo y` dà tre
  /// segmenti. Le virgolette tengono insieme; `sudo`, `env`, `time`,
  /// `nohup` e le assegnazioni `A=b` davanti si scavalcano per arrivare al
  /// comando vero, che è quello che spiega qualcosa.
  List<Spiegazione> spiega(String riga) {
    final out = <Spiegazione>[];
    for (final segmento in spezzaPipeline(riga)) {
      final parole = spezzaParole(segmento);
      if (parole.isEmpty) continue;
      var i = 0;
      const trasparenti = {'sudo', 'doas', 'env', 'time', 'nohup', 'exec', 'command', 'builtin'};
      while (i < parole.length &&
          (trasparenti.contains(parole[i]) ||
              RegExp(r'^[A-Za-z_][A-Za-z0-9_]*=').hasMatch(parole[i]) ||
              (i > 0 && trasparenti.contains(parole[i - 1]) && parole[i].startsWith('-')) ||
              (i > 1 && trasparenti.contains(parole[i - 2]) && const {'-u', '-g'}.contains(parole[i - 1])))) {
        i++;
      }
      if (i >= parole.length) i = 0;
      final nome = parole[i].split('/').last;
      final voce = trova(nome);
      final opzioni = <List<String>>[];
      final sconosciute = <String>[];
      final argomenti = <String>[];
      var fineOpzioni = false;
      for (final p in parole.skip(i + 1)) {
        if (fineOpzioni) {
          argomenti.add(p);
          continue;
        }
        if (p == '--') {
          fineOpzioni = true;
          continue;
        }
        if (p.startsWith('--')) {
          final o = voce?.opzione(p);
          if (o != null) {
            opzioni.add([p, o.spiegazione]);
          } else {
            sconosciute.add(p);
          }
        } else if (p.startsWith('-') && p.length > 1 && !RegExp(r'^-\d').hasMatch(p)) {
          // `-la` è `-l` e `-a`: ognuna cercata da sola, salvo che l'insieme
          // esista come opzione (`-rf` no, ma `aux` di ps non ha il trattino).
          final intera = voce?.opzione(p);
          if (intera != null) {
            opzioni.add([p, intera.spiegazione]);
            continue;
          }
          for (var k = 1; k < p.length; k++) {
            final singola = '-${p[k]}';
            final o = voce?.opzione(singola);
            if (o != null) {
              opzioni.add([singola, o.spiegazione]);
            } else {
              sconosciute.add(singola);
            }
          }
        } else {
          // Le sotto-parole (`git status`, `systemctl restart`, `ps aux`)
          // stanno fra le opzioni del dizionario senza trattino.
          final o = voce?.opzione(p);
          if (o != null && argomenti.isEmpty && opzioni.every((x) => x[0].startsWith('-'))) {
            opzioni.add([p, o.spiegazione]);
          } else {
            argomenti.add(p);
          }
        }
      }
      out.add(Spiegazione(
        comando: nome,
        descrizione: voce?.descrizione ?? '',
        conosciuto: voce != null,
        pericolo: voce?.pericolo ?? 0,
        opzioni: opzioni,
        sconosciute: sconosciute,
        argomenti: argomenti,
      ));
    }
    return out;
  }
}

/// Spezza sui separatori di pipeline fuori dalle virgolette: `|`, `||`,
/// `&&`, `;`. Il testo fra virgolette resta intero.
List<String> spezzaPipeline(String riga) {
  final out = <String>[];
  final b = StringBuffer();
  String? virgolette;
  for (var i = 0; i < riga.length; i++) {
    final c = riga[i];
    if (virgolette != null) {
      b.write(c);
      if (c == virgolette) virgolette = null;
      if (c == r'\' && virgolette == '"' && i + 1 < riga.length) {
        b.write(riga[++i]);
      }
      continue;
    }
    if (c == '"' || c == "'") {
      virgolette = c;
      b.write(c);
      continue;
    }
    if (c == r'\' && i + 1 < riga.length) {
      b.write(c);
      b.write(riga[++i]);
      continue;
    }
    if (c == '|' || c == ';' || c == '&' || c == '\n') {
      if (c == '&' && ((i > 0 && '<>'.contains(riga[i - 1])) ||
          (i + 1 < riga.length && riga[i + 1] == '>'))) {
        // 2>&1, <&0 e &>file sono reindirizzamenti. Un & isolato
        // invece termina un comando: la guardia deve vedere il successivo.
        b.write(c);
        continue;
      }
      if (i + 1 < riga.length && riga[i + 1] == c) i++;
      final s = b.toString().trim();
      if (s.isNotEmpty) out.add(s);
      b.clear();
      continue;
    }
    b.write(c);
  }
  final s = b.toString().trim();
  if (s.isNotEmpty) out.add(s);
  return out;
}

/// Spezza in parole rispettando le virgolette (che si tolgono) e le barre
/// rovesciate.
List<String> spezzaParole(String segmento) {
  final out = <String>[];
  final b = StringBuffer();
  var dentro = false;
  String? virgolette;
  for (var i = 0; i < segmento.length; i++) {
    final c = segmento[i];
    if (virgolette != null) {
      if (c == virgolette) {
        virgolette = null;
      } else if (c == r'\' && virgolette == '"' && i + 1 < segmento.length) {
        b.write(segmento[++i]);
      } else {
        b.write(c);
      }
      continue;
    }
    if (c == '"' || c == "'") {
      virgolette = c;
      dentro = true;
      continue;
    }
    if (c == r'\' && i + 1 < segmento.length) {
      b.write(segmento[++i]);
      dentro = true;
      continue;
    }
    if (c == ' ' || c == '\t') {
      if (dentro) {
        out.add(b.toString());
        b.clear();
        dentro = false;
      }
      continue;
    }
    b.write(c);
    dentro = true;
  }
  if (dentro) out.add(b.toString());
  return out;
}
