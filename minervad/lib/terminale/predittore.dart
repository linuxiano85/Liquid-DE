// predittore.dart — Cosa stai per scrivere, e perché lo proponiamo.
//
// Quello che Giacomo vede in Alacritty è l'autosuggerimento di fish: il
// testo grigio dalla storia, accettato con →. Questo fa quello E dice il
// perché — ogni proposta ha una spiegazione in italiano accanto — perché
// pesca da cinque sorgenti, in quest'ordine di peso:
//
//     1. la storia di QUESTA cartella      (×3)
//     2. la storia di tutte le cartelle    (×1)
//     3. gli esempi del dizionario         (con la loro spiegazione)
//     4. i comandi del dizionario e del PATH  (solo per la prima parola)
//     5. i percorsi                         (per le parole dopo la prima)
//
// La storia pesa per recenza (dimezza ogni sette giorni) e per esito (un
// comando fallito vale un terzo): quello che hai scritto ieri e che ha
// funzionato viene prima di quello di un mese fa che ha dato errore.
//
// Una cartella nuova NON eredita i comandi sbagliati: la storia di un'altra
// cartella pesa un terzo di quella di questa, e un comando fallito un terzo
// ancora — quindi un `rm` fallito altrove finisce in fondo, non in cima.
//
// Nessuna rete, nessun modello: è deterministico e si prova a numeri. L'IA
// locale, quando ci sarà, sarà una sesta sorgente dietro un interruttore.
library;

import 'dart:io';

import 'dizionario.dart';
import 'storia.dart';
import 'completamento.dart';

class Proposta {
  Proposta(this.testo, this.tipo, this.spiegazione, this.peso);
  /// La riga intera che si otterrebbe accettando.
  final String testo;
  /// `storia` · `esempio` · `comando` · `programma` · `cartella` · `file`.
  final String tipo;
  final String spiegazione;
  double peso;

  Map<String, dynamic> aMappa() => {
        'testo': testo,
        'tipo': tipo,
        'spiegazione': spiegazione,
        'peso': double.parse(peso.toStringAsFixed(3)),
      };
}

class Risposta {
  Risposta(this.testo, this.fantasma, this.proposte);
  final String testo;
  /// La riga fino alla fine del token corrente, o vuoto. Mai una catena.
  final String fantasma;
  final List<Proposta> proposte;

  Map<String, dynamic> aMappa() => {
        'testo': testo,
        'fantasma': fantasma,
        'proposte': [for (final p in proposte)
          {...p.aMappa(), 'inserimento': prossimaParola(testo, p.testo)}],
      };
}

class Predittore {
  Predittore({
    required this.storia,
    required this.dizionario,
    List<String>? programmi,
    this.leggiCartelle = true,
  }) : _programmi = programmi; // ignore: prefer_initializing_formals

  final Storia storia;
  final Dizionario dizionario;
  final bool leggiCartelle;
  List<String>? _programmi;

  /// I nomi nel PATH, letti una volta sola alla prima richiesta.
  List<String> get programmi {
    final p = _programmi;
    if (p != null) return p;
    final out = <String>{};
    final path = Platform.environment['PATH'] ?? '';
    for (final dir in path.split(':')) {
      if (dir.isEmpty) continue;
      try {
        for (final e in Directory(dir).listSync(followLinks: true)) {
          final st = e.statSync();
          if (st.type == FileSystemEntityType.file && (st.mode & 0x49) != 0) {
            out.add(e.uri.pathSegments.last);
          }
        }
      } catch (_) {
        continue;
      }
    }
    final lista = out.toList()..sort();
    _programmi = lista;
    return lista;
  }

  static const _giornoMs = 86400000;

  Risposta proponi(String testo, String cartella, {int quante = 12, int? adessoMs}) {
    if (testo.length > 4096 || contieneControlli(testo)) {
      return Risposta(testo, '', []);
    }
    quante = quante.clamp(0, 30);
    final adesso = adessoMs ?? DateTime.now().millisecondsSinceEpoch;
    final perTesto = <String, Proposta>{};
    void aggiungi(Proposta p) {
      if (p.testo == testo) return;
      final c = perTesto[p.testo];
      if (c == null) {
        perTesto[p.testo] = p;
      } else {
        c.peso += p.peso;
        if (c.spiegazione.isEmpty && p.spiegazione.isNotEmpty) {
          perTesto[p.testo] = Proposta(p.testo, c.tipo, p.spiegazione, c.peso);
        }
      }
    }

    // ── 1 e 2: la storia ─────────────────────────────────────────────────
    final conteggi = <String, int>{};
    for (final v in storia.voci) {
      if (!v.comando.startsWith(testo)) continue;
      final eta = (adesso - v.quando).clamp(0, 365 * _giornoMs) / _giornoMs;
      var peso = 1.0;
      peso *= v.cartella == cartella ? 3.0 : 1.0;
      peso *= _mezzaVita(eta, 7) + 0.05;
      peso *= v.codice == 0 ? 1.0 : (v.codice < 0 ? 0.8 : 0.33);
      conteggi[v.comando] = (conteggi[v.comando] ?? 0) + 1;
      aggiungi(Proposta(v.comando, 'storia', '', peso));
    }
    for (final p in perTesto.values) {
      if (p.tipo != 'storia') continue;
      final n = conteggi[p.testo] ?? 1;
      final voce = dizionario.trova(_primaParola(p.testo));
      final quante = n == 1 ? 'usato una volta' : 'usato $n volte';
      perTesto[p.testo] = Proposta(p.testo, 'storia',
          voce != null ? '${voce.descrizione} · $quante' : quante, p.peso);
    }

    // ── 3: gli esempi del dizionario ─────────────────────────────────────
    if (testo.isNotEmpty) {
      for (final (v, e) in dizionario.esempi) {
        if (!e.comando.startsWith(testo)) continue;
        aggiungi(Proposta(e.comando, 'esempio', e.spiegazione,
            0.6 + (v.livello <= 2 ? 0.2 : 0.0)));
      }
    }

    // ── 4: i comandi, se si sta scrivendo la prima parola ────────────────
    final primaParola = !testo.contains(' ');
    if (primaParola && testo.isNotEmpty) {
      for (final v in dizionario.voci) {
        if (v.comando.startsWith(testo) && !v.comando.startsWith('-') &&
            RegExp(r'^[a-z0-9._+-]+$').hasMatch(v.comando)) {
          aggiungi(Proposta(v.comando, 'comando', v.descrizione, 0.5));
        }
      }
      var n = 0;
      for (final p in programmi) {
        if (!RegExp(r'^[a-zA-Z0-9._+-]+$').hasMatch(p)) continue;
        if (!p.startsWith(testo)) continue;
        if (perTesto.containsKey(p)) continue;
        final voce = dizionario.trova(p);
        aggiungi(Proposta(p, 'programma', voce?.descrizione ?? '', 0.2));
        if (++n >= 40) break;
      }
    }

    // ── 5: i percorsi, per le parole dopo la prima ───────────────────────
    if (!primaParola && leggiCartelle) {
      for (final p in _percorsi(testo, cartella)) {
        aggiungi(p);
      }
    }

    final proposte = perTesto.values.toList()
      ..sort((a, b) {
        final c = b.peso.compareTo(a.peso);
        return c != 0 ? c : a.testo.compareTo(b.testo);
      });

    // Il fantasma completa una sola parola della storia o degli esempi.
    // Le proposte conservano il contesto completo per la spiegazione,
    // ma il protocollo espone un inserimento separato limitato al token.
    var fantasma = '';
    if (testo.isNotEmpty) {
      for (final p in proposte) {
        if (p.tipo == 'storia' || p.tipo == 'esempio') {
          fantasma = prossimaParola(testo, p.testo);
          if (fantasma.isNotEmpty) break;
        }
      }
    }
    return Risposta(testo, fantasma, proposte.take(quante).toList());
  }

  static double _mezzaVita(double giorni, double meta) {
    var x = 1.0;
    var g = giorni;
    while (g >= meta) {
      x /= 2;
      g -= meta;
      if (x < 0.001) return 0.0;
    }
    return x * (1 - (g / meta) * 0.5);
  }

  static String _primaParola(String riga) {
    final parole = spezzaParole(riga);
    for (final p in parole) {
      if (p == 'sudo' || p.contains('=')) continue;
      return p.split('/').last;
    }
    return '';
  }

  /// Completa l'ultima parola come percorso: `cd Doc` → `cd Documenti/`.
  List<Proposta> _percorsi(String testo, String cartella) {
    final out = <Proposta>[];
    final token = ultimoPercorso(testo);
    if (token == null) return out;
    final prima = testo.substring(0, token.inizio);
    final parola = token.valore;
    if (parola.startsWith('-')) return out;
    final senzaProtezione = parola;
    var base = senzaProtezione;
    var prefisso = '';
    final barra = senzaProtezione.lastIndexOf('/');
    if (barra >= 0) {
      base = senzaProtezione.substring(0, barra + 1);
      prefisso = senzaProtezione.substring(barra + 1);
    } else {
      base = '';
      prefisso = senzaProtezione;
    }
    var dir = base;
    if (dir.startsWith('~') && !dir.startsWith('~/')) return out;
    if (dir.startsWith('~/')) {
      dir = (Platform.environment['HOME'] ?? '') + dir.substring(1);
    }
    if (!dir.startsWith('/')) dir = '$cartella/$dir';
    if (dir.isEmpty) dir = cartella;
    List<FileSystemEntity> voci;
    try {
      voci = Directory(dir).listSync(followLinks: false);
    } catch (_) {
      return out;
    }
    var n = 0;
    voci.sort((a, b) => a.path.compareTo(b.path));
    for (final e in voci) {
      final nome = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (!nome.startsWith(prefisso)) continue;
      if (prefisso.isEmpty && nome.startsWith('.')) continue;
      final cartellaVera = FileSystemEntity.isDirectorySync(e.path);
      if (contieneControlli(nome)) continue;
      final percorso = base.isEmpty && nome.startsWith('-') ? './$nome' : base + nome;
      final protetto = (percorso.startsWith('~/')
          ? '~/${proteggiPercorso(percorso.substring(2))}'
          : proteggiPercorso(percorso)) + (cartellaVera ? '/' : '');
      out.add(Proposta(prima + protetto, cartellaVera ? 'cartella' : 'file',
          cartellaVera ? 'una cartella' : 'un file', 0.4));
      if (++n >= 30) break;
    }
    return out;
  }
}
