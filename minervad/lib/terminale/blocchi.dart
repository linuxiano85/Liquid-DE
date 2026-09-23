// blocchi.dart — Dai marcatori della shell ai blocchi: comando, uscita, esito.
//
// La shell manda quattro marcatori (OSC 133): `A` comincia il prompt, `B`
// comincia il comando, `C` comincia l'uscita, `D;n` è finito con n. Da
// quelli, senza guardare lo schermo, si sa dove sta ogni cosa:
//
//     riga A ┌ prompt ─────────────────────────┐
//     riga B │ ❯ ls -la                         │  ← il comando (fra B e C)
//     riga C │ totale 12                        │  ← l'uscita (fra C e D)
//            │ drwxr-xr-x  …                    │
//     riga D └──────────────────────────────────┘  ← esito 0, 12 ms
//
// Le righe sono ASSOLUTE (contano anche quelle uscite dallo scrollback),
// così un blocco resta lo stesso mentre lo schermo scorre.
//
// ── Il testo del comando ───────────────────────────────────────────────────
//
// Se la riga l'ha mandata la finestra (la riga NOSTRA) si sa esattamente
// cos'era. Altrimenti — chi usa la riga della shell — si legge dallo
// schermo fra B e C, cioè quello che la shell ha fatto eco. Il secondo modo
// prende anche le decorazioni del prompt a destra (l'ora di starship),
// quindi si taglia al primo blocco di tre spazi o più: non è perfetto, ed è
// il motivo per cui la riga nostra è quella di serie.
library;

class Blocco {
  Blocco(this.id, this.rigaA, this.cartella);

  final int id;
  final int rigaA;
  int rigaB = -1;
  int rigaC = -1;
  int rigaD = -1;
  String cartella;
  String comando = '';
  /// La riga l'ha mandata la finestra: il testo è certo.
  bool nostro = false;
  int codice = -1;
  int inizio = 0;
  int fine = 0;

  /// `prompt` (si aspetta un comando) · `corsa` (fra C e D) · `finito`.
  String get stato => rigaD >= 0 ? 'finito' : (rigaC >= 0 ? 'corsa' : 'prompt');
  int get durata => fine > inizio ? fine - inizio : 0;

  Map<String, dynamic> aMappa() => {
        't': 'blocco',
        'id': id,
        'stato': stato,
        'rigaA': rigaA,
        'rigaB': rigaB,
        'rigaC': rigaC,
        'rigaD': rigaD,
        'cartella': cartella,
        'comando': comando,
        'nostro': nostro,
        'codice': codice,
        'durata': durata,
      };
}

/// Il registro dei blocchi di una sessione.
class Blocchi {
  Blocchi({this.massimo = 500});

  final int massimo;
  final List<Blocco> tutti = [];
  int _prossimoId = 1;
  /// La riga che la finestra ha appena mandato: sarà il comando del blocco
  /// che sta per partire.
  String? _rigaNostra;

  Blocco? get aperto => tutti.isNotEmpty && tutti.last.rigaD < 0 ? tutti.last : null;
  Blocco? get ultimo => tutti.isNotEmpty ? tutti.last : null;

  /// La shell sta aspettando un comando? Vero fra B e C (o fra A e C).
  bool get alPrompt {
    final u = ultimo;
    return u != null && u.rigaC < 0;
  }

  /// Un comando è in corso (fra C e D)?
  bool get inCorsa {
    final u = ultimo;
    return u != null && u.rigaC >= 0 && u.rigaD < 0;
  }

  void rigaMandata(String riga) {
    _rigaNostra = riga;
  }

  /// Un marcatore. Torna i blocchi da annunciare alla finestra: quello
  /// nuovo al prompt, quello partito a C, quello finito a D.
  ///
  /// `testoFraBeC` legge dallo schermo il comando echeggiato, per chi non
  /// usa la riga nostra.
  List<Blocco> marcatore(String tipo, int riga, int codice, String comandoDetto,
      String cartella, int adesso, String Function(int da, int a) testoFraBeC) {
    final out = <Blocco>[];
    switch (tipo) {
      case 'A':
        // Un blocco ancora aperto senza C è un prompt abbandonato (Ctrl+C
        // su una riga vuota, o un Invio a vuoto): si butta. Uno con C e
        // senza D è un comando di cui la shell non ha detto l'esito
        // (una shell annidata, un `exec`): si chiude com'è.
        final a = aperto;
        if (a != null) {
          if (a.rigaC < 0) {
            tutti.removeLast();
          } else {
            a.rigaD = riga;
            a.fine = adesso;
            out.add(a);
          }
        }
        final b = Blocco(_prossimoId++, riga, cartella);
        tutti.add(b);
        if (tutti.length > massimo) tutti.removeAt(0);
        out.add(b);
      case 'B':
        final a = aperto;
        if (a != null && a.rigaC < 0) a.rigaB = riga;
      case 'C':
        var a = aperto;
        if (a == null || a.rigaC >= 0) {
          // Una C senza A davanti (una shell che manda solo C e D): si
          // apre un blocco lì.
          a = Blocco(_prossimoId++, riga, cartella);
          tutti.add(a);
        }
        a.rigaC = riga;
        a.inizio = adesso;
        final nostra = _rigaNostra;
        if (nostra != null) {
          a.comando = nostra;
          a.nostro = true;
          _rigaNostra = null;
        } else if (comandoDetto.isNotEmpty) {
          a.comando = comandoDetto;
        } else {
          final da = a.rigaB >= 0 ? a.rigaB : a.rigaA;
          a.comando = pulisciEco(testoFraBeC(da, riga));
        }
        out.add(a);
      case 'D':
        final a = aperto;
        if (a != null) {
          if (a.rigaC < 0) {
            // D senza C: un Invio a vuoto. Non è un comando.
            tutti.removeLast();
          } else {
            a.rigaD = riga;
            a.codice = codice;
            a.fine = adesso;
            out.add(a);
          }
        }
        _rigaNostra = null;
    }
    return out;
  }

  /// Il blocco che contiene questa riga assoluta, se c'è.
  Blocco? a(int rigaAssoluta) {
    for (var i = tutti.length - 1; i >= 0; i--) {
      final b = tutti[i];
      if (rigaAssoluta >= b.rigaA && (b.rigaD < 0 || rigaAssoluta < b.rigaD)) {
        return b;
      }
      if (b.rigaA < rigaAssoluta && b.rigaD >= 0 && b.rigaD <= rigaAssoluta) {
        return null;
      }
    }
    return null;
  }

  /// Dal testo echeggiato al comando: via il simbolo del prompt in testa
  /// (`❯`, `$`, `#`, `>`), via le decorazioni a destra dopo tre spazi.
  static String pulisciEco(String testo) {
    var t = testo.replaceAll('\n', ' ').trim();
    final m = RegExp(r'^(?:[^\s]*[❯›»$#>%]\s+)').firstMatch(t);
    if (m != null) t = t.substring(m.end);
    final tre = t.indexOf('   ');
    if (tre > 0) t = t.substring(0, tre);
    return t.trim();
  }
}
