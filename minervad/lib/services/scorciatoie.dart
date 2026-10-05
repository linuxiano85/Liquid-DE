import 'dart:io';

/// Le scorciatoie di Minerva, nel vocabolario di Minerva.
///
/// `config/scorciatoie.minerva` è la sorgente unica, in lingua nostra: quali
/// tasti aprono cosa, con le ragioni scritte accanto. Da qui escono due
/// cose: le righe `scorciatoia …` che la shell manda a minerva-wayland
/// (`perMinervaWayland`), e il promemoria di Super+K (`daMostrare`).
///
/// Fino al 2 settembre 2026 ne usciva anche `config/hypr/keybinds.conf`, la
/// stessa sorgente tradotta per Hyprland: se n'è andato con quella sessione,
/// e cambiare compositore ha voluto dire togliere un traduttore, non
/// riscrivere le novantacinque scorciatoie.
class Scorciatoia {
  /// I tasti come li scrive un umano: `$mod K`, `F1`, `$mod CTRL down`.
  /// L'ULTIMO è il tasto, quelli prima sono modificatori.
  final String tasti;

  /// `anche-bloccato` · `ripete` · `mouse` · `al-rilascio` · `tocco` · `tieni`
  ///
  /// `tocco` vuol dire «premuto e lasciato **da solo**»: il gesto con cui
  /// Super apre il menù delle applicazioni. Tira dentro `al-rilascio` — un
  /// tocco si riconosce quando il tasto si rialza — ma non è la stessa cosa:
  /// l'Alt che conferma l'Alt+Tab è `al-rilascio` e **non** `tocco`, perché
  /// deve scattare proprio quando in mezzo è stato premuto Tab.
  ///
  /// Il compositore lo distingue da sé (vedi `perMinervaWayland`).
  final Set<String> flag;

  /// Nel vocabolario di Minerva: `minerva: cheatsheet`, `scrivania: 3`,
  /// `avvia: alacritty`, `chiudi-finestra`.
  final String azione;

  /// Per il promemoria di Super+K. `null` quando la scorciatoia non ci va (è il
  /// seguito di un'altra: il rilascio di Alt che conferma l'Alt+Tab).
  final String? categoria;
  final String? descrizione;

  /// Riga nella sorgente, per poter dire DOVE quando qualcosa non torna.
  final int riga;

  const Scorciatoia({
    required this.tasti,
    required this.flag,
    required this.azione,
    required this.riga,
    this.categoria,
    this.descrizione,
  });

  /// I modificatori, cioè tutto tranne l'ultima parola.
  List<String> get modificatori {
    final p = tasti.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    return p.length <= 1 ? const [] : p.sublist(0, p.length - 1);
  }

  /// Il tasto vero, cioè l'ultima parola.
  String get tasto {
    final p = tasti.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    return p.isEmpty ? '' : p.last;
  }

  Map<String, dynamic> toJson() => {
        'tasti': tasti,
        'flag': flag.toList()..sort(),
        'azione': azione,
        if (categoria != null) 'categoria': categoria,
        if (descrizione != null) 'descrizione': descrizione,
      };
}

class Scorciatoie {
  final List<Scorciatoia> tutte;
  final Map<String, String> variabili;

  const Scorciatoie(this.tutte, this.variabili);

  /// Quelle che vanno nel promemoria di Super+K.
  List<Scorciatoia> get daMostrare =>
      tutte.where((s) => s.categoria != null && s.descrizione != null).toList();

  // ── Leggere la sorgente ────────────────────────────────────────────────

  static final _annotazione = RegExp(r'^@\s*(.+?)\s*\|\s*(.+?)\s*$');
  static final _spegni = RegExp(r'^@\s*-\s*$');
  static final _variabile = RegExp(r'^\$(\w+)\s*=\s*(.+?)\s*$');
  static final _regola = RegExp(r'^(.+?)\s*->\s*(.*)$');
  static final _marchi = RegExp(r'\[([^\]]*)\]\s*$');

  static Scorciatoie leggi(String testo) {
    final righe = <Scorciatoia>[];
    final variabili = <String, String>{};
    String? categoria;
    String? descrizione;

    final linee = testo.split('\n');
    for (var i = 0; i < linee.length; i++) {
      final l = linee[i];
      final s = l.trim();

      if (s.isEmpty || s.startsWith('#')) continue;
      if (_spegni.hasMatch(s)) {
        categoria = null;
        descrizione = null;
        continue;
      }
      final a = _annotazione.firstMatch(s);
      if (a != null) {
        categoria = a.group(1);
        descrizione = a.group(2);
        continue;
      }
      final v = _variabile.firstMatch(s);
      if (v != null) {
        variabili[v.group(1)!] = v.group(2)!;
        continue;
      }
      final r = _regola.firstMatch(s);
      if (r == null) {
        // Non si tira dritto in silenzio: una riga che nessuno capisce è una
        // scorciatoia che non esisterà, e il modo peggiore di scoprirlo è
        // premendo il tasto.
        throw FormatException(
            'riga ${i + 1} di scorciatoie.minerva: non è né un commento né una '
            'regola «tasti -> azione»:\n  $s');
      }

      var sinistra = r.group(1)!.trim();
      final flag = <String>{};
      final m = _marchi.firstMatch(sinistra);
      if (m != null) {
        for (final f in m.group(1)!.split(RegExp(r'\s+'))) {
          if (f.trim().isNotEmpty) flag.add(f.trim());
        }
        sinistra = sinistra.substring(0, m.start).trim();
      }

      righe.add(Scorciatoia(
        tasti: sinistra,
        flag: flag,
        azione: r.group(2)!.trim(),
        riga: i + 1,
        categoria: categoria,
        descrizione: descrizione,
      ));
    }
    return Scorciatoie(righe, variabili);
  }

  static Scorciatoie daFile(String percorso) =>
      leggi(File(percorso).readAsStringSync());

  // ── Le righe per minerva-wayland ─────────────────────────────────────
  //
  // Il formato è quello che legge `compositore/src/main.c`:
  //
  //     scorciatoia SUPER K - minerva:cheatsheet
  //     scorciatoia - XF86AudioRaiseVolume bloccato minerva:volume-su
  //
  // ── Quello che NON si manda, e perché contarlo ──────────────────────────
  //
  // Le azioni che il compositore non conosce si saltano: mandarle vorrebbe
  // dire un tasto che il compositore si mangia e poi non usa — peggio che non
  // registrarlo, perché il programma sotto non lo riceve nemmeno.

  /// Le azioni che minerva-wayland sa fare da sé.
  ///
  /// ── Le tre delle frecce, tolte da questo elenco il 31 agosto 2026 ───────
  ///
  /// `fuoco`, `sposta-finestra` e `ridimensiona` erano saltate con un
  /// ragionamento giusto e una conclusione sbagliata: «vogliono dire qualcosa
  /// solo dove c'è una griglia». Vero per «allarga nella griglia», falso per
  /// il resto:
  ///
  ///   * il fuoco alla finestra a sinistra ha senso ovunque ci siano due
  ///     finestre — griglia o no, l'occhio sa quale è «quella a sinistra»;
  ///   * «sposta la finestra a sinistra» senza griglia ha una lettura ovvia
  ///     che Minerva ha già: **l'aggancio a metà schermo**, lo stesso del
  ///     trascinamento contro il bordo;
  ///   * `ridimensiona` il canale lo conosceva già come verbo: mancavano solo
  ///     le righe che glielo mandavano.
  ///
  /// Il conto era 67 registrate su 95 scritte, con dodici tasti che nel
  /// promemoria di Super+K comparivano e non facevano niente.
  static const Set<String> _sueDavvero = {
    'minerva',
    'avvia',
    'scrivania',
    'porta-a-scrivania',
    'chiudi-finestra',
    'schermo-intero',
    'esci-dalla-sessione',
    'fuoco',
    'sposta-finestra',
    'ridimensiona',
  };

  static String _verboDi(String azione) {
    final i = azione.indexOf(':');
    return (i < 0 ? azione : azione.substring(0, i)).trim();
  }

  static bool _perLuiVale(Scorciatoia s) {
    // Col mouse no: quelle le tratta già la barra del titolo dentro il
    // compositore, e registrarle qui vorrebbe dire due posti che rispondono
    // allo stesso gesto.
    if (s.flag.contains('mouse')) return false;
    // E nemmeno la rotellina: `mouse_down` non è un tasto della tastiera, non
    // ha un nome XKB — verificato, `xkb_keysym_from_name` risponde NoSymbol —
    // e il compositore direbbe «il tasto non esiste».
    //
    // **Ma il gesto c'è**, e dal 30 agosto 2026 lo fa il compositore stesso,
    // dentro `cursore_rotella`: Super + rotellina cambia scrivania, con
    // l'accumulo che impedisce a una rotellina ad alta risoluzione di saltarne
    // otto in un colpo. Queste due righe restano nella sorgente perché sono la
    // documentazione del gesto e finiscono nel promemoria di Super+K — non perché
    // qualcuno le debba registrare.
    if (s.tasto.startsWith('mouse')) return false;
    if (!_sueDavvero.contains(_verboDi(s.azione))) return false;
    // «Portala sulla scrivania speciale» non vuol dire niente qui: le
    // scrivanie sono dieci e si chiamano coi numeri. Il compositore
    // risponderebbe «le scrivanie vanno da 1 a 10», ma si sarebbe già
    // mangiato il tasto — e un tasto mangiato e non usato è peggio di un
    // tasto libero.
    if (_verboDi(s.azione) == 'porta-a-scrivania') {
      final arg = s.azione.substring(s.azione.indexOf(':') + 1).trim();
      // La stanza accanto, portando la finestra: il compositore sa contare.
      if (int.tryParse(arg) == null && arg != 'prossima' && arg != 'precedente') {
        return false;
      }
    }
    return true;
  }

  /// Le variabili della sorgente, sciolte.
  ///
  /// `$mod`, `$terminal`, `$browser`. minerva-wayland riceve righe già
  /// pronte, e un `$mod` che gli arrivasse così sarebbe un modificatore che
  /// non esiste, cioè una scorciatoia che non scatta mai.
  ///
  /// `anche` sono le variabili che la sorgente NON dichiara perché le dichiara
  /// chi la usa: `$minerva`, la cartella installata. Senza, «blocca lo schermo»
  /// diventerebbe il comando `"$minerva/scripts/minerva-blocca"` — che una
  /// shell esegue senza lamentarsi, e non fa niente.
  String _sciogli(String t, [Map<String, String> anche = const {}]) {
    var fuori = t;
    anche.forEach((nome, valore) {
      fuori = fuori.replaceAll('\$$nome', valore);
    });
    variabili.forEach((nome, valore) {
      fuori = fuori.replaceAll('\$$nome', valore);
    });
    return fuori;
  }

  /// Le righe da mandare a minerva-wayland sul suo canale.
  List<String> perMinervaWayland({Map<String, String> anche = const {}}) {
    final fuori = <String>['scorciatoie azzera'];
    for (final s in tutte) {
      if (!_perLuiVale(s)) continue;
      final mods = s.modificatori
          .map((m) => _sciogli(m, anche).toUpperCase())
          .where((m) => m.isNotEmpty)
          .join('+');
      final i = s.azione.indexOf(':');
      final verbo = _verboDi(s.azione);
      final arg =
          i < 0 ? '' : _sciogli(s.azione.substring(i + 1).trim(), anche);
      // ── I flag, attaccati col `+` come i modificatori ─────────────────
      //
      // `al-rilascio` non c'era, e la sua mancanza rompeva un gesto intero:
      // `ALT Tab` apriva il selettore delle finestre e **nessuno lo
      // chiudeva**, perché a chiuderlo è il momento in cui si molla Alt. Il
      // riquadro restava aperto sullo schermo e la finestra scelta non
      // prendeva il fuoco.
      final flag = <String>[
        if (s.flag.contains('anche-bloccato')) 'bloccato',
        if (s.flag.contains('al-rilascio')) 'rilascio',
        // Il compositore lo tratta come «rilascio + nessun altro tasto in
        // mezzo», e accende `rilascio` da sé se trova questo: due parole per
        // un gesto solo sarebbero due posti da tenere d'accordo.
        if (s.flag.contains('tocco')) 'tocco',
        // Premuto e TENUTO da solo: il compositore annuncia l'azione dopo
        // 400 ms e, al rilascio, la stessa col suffisso `-via`.
        if (s.flag.contains('tieni')) 'tieni',
      ];
      final riga = 'scorciatoia ${mods.isEmpty ? '-' : mods} '
          '${_sciogli(s.tasto, anche)} '
          '${flag.isEmpty ? '-' : flag.join('+')} '
          '$verbo${arg.isEmpty ? '' : ':$arg'}';
      // ── Una variabile rimasta intera non esce di qui ──────────────────
      //
      // Se dopo lo scioglimento c'è ancora un `\$`, vuol dire che quella
      // variabile non la conosce nessuno: `\$mod` diventerebbe un
      // modificatore che non esiste, e `"\$minerva/scripts/minerva-blocca"`
      // un comando che la shell esegue senza lamentarsi e che non fa niente.
      // Tutte e due sono scorciatoie che si registrano, si mangiano il tasto,
      // e non fanno la cosa. Meglio non registrarle: il tasto resta libero, e
      // chi guarda il conto vede che qualcosa manca.
      if (riga.contains(r'$')) continue;
      fuori.add(riga);
    }
    return fuori;
  }
}
