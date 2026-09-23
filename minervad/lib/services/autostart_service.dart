import 'dart:io';

/// AutostartService — I programmi che partono con la sessione.
///
/// KDE ha una pagina apposta; Minerva non aveva niente, e non per svista:
/// **Hyprland non legge `~/.config/autostart`**. Chi arriva da un altro
/// ambiente si porta dietro quella cartella e quei programmi semplicemente non
/// partono più, senza che nessuno lo dica. E chi vuole aggiungerne uno oggi
/// deve modificare a mano `hyprland.conf`, cioè un file di configurazione del
/// compositore, per una cosa che non riguarda il compositore.
///
/// ── LA DECISIONE CHE VALE LA PENA SPIEGARE ─────────────────────────────────
///
/// Ci sono DUE cartelle: quella dell'utente (`~/.config/autostart`) e quella
/// di sistema (`/etc/xdg/autostart`). Su questa macchina la seconda contiene
/// **diciannove** voci messe lì dai pacchetti di KDE: `baloo_file` che indicizza
/// tutto il disco, `plasmashell`, `powerdevil`, `kglobalacceld`.
///
/// **Le voci di sistema NON partono da sole.** Solo quelle dell'utente.
///
/// Non è pigrizia: oggi quelle diciannove voci non partono — Hyprland non
/// guarda lì — e la sessione funziona benissimo. Metterle in moto tutte perché
/// «così fa un desktop completo» vorrebbe dire far comparire dal nulla un
/// indicizzatore del disco e una seconda barra delle applicazioni, il giorno
/// in cui si aggiunge una pagina nelle impostazioni. Un'aggiunta non deve
/// cambiare il comportamento di ciò che c'era.
///
/// Restano però ELENCATE, spente, con una levetta: chi vuole `gnome-keyring`
/// o `xdg-user-dirs` se lo accende, e accendendolo se ne fa una copia sua in
/// `~/.config/autostart`. È lo stesso meccanismo che usa KDE, e ha il pregio
/// che disinstallando il pacchetto la copia resta a fare rumore invece che
/// sparire in silenzio — motivo per cui si controlla sempre `TryExec`.
///
/// ── COME SI SPEGNE UNA VOCE ────────────────────────────────────────────────
///
/// Con `Hidden=true` dentro il file dell'utente, che è quello che dice la
/// specifica freedesktop. **Non** cancellandolo: cancellare la copia di una
/// voce di sistema la fa tornare accesa (riappare quella sotto), che è
/// esattamente il contrario di quello che si è chiesto.
class AutostartService {
  AutostartService({String? cartellaUtente, List<String>? cartelleSistema})
      : _utente = cartellaUtente,
        _sistema = cartelleSistema;

  final String? _utente;
  final List<String>? _sistema;

  String get cartellaUtente {
    if (_utente != null) return _utente;
    final home = Platform.environment['HOME'] ?? '';
    final config = Platform.environment['XDG_CONFIG_HOME']?.isNotEmpty == true
        ? Platform.environment['XDG_CONFIG_HOME']!
        : '$home/.config';
    return '$config/autostart';
  }

  List<String> get cartelleSistema => _sistema ?? const ['/etc/xdg/autostart'];

  /// Tutte le voci, quelle dell'utente e quelle di sistema, già fuse.
  ///
  /// Se lo stesso nome di file esiste in tutte e due, vince quello
  /// dell'utente: è la regola della specifica, ed è anche l'unica sensata —
  /// la copia personale esiste proprio per scavalcare quella di sistema.
  Future<List<Map<String, dynamic>>> elenco() async {
    final voci = <String, Map<String, dynamic>>{};

    for (final cartella in cartelleSistema) {
      for (final v in await _leggiCartella(cartella, false)) {
        voci[v['file'] as String] = v;
      }
    }
    for (final v in await _leggiCartella(cartellaUtente, true)) {
      final f = v['file'] as String;
      // Una voce dell'utente che copre una di sistema si ricorda di
      // coprirla: serve a dire «questa la puoi spegnere e tornerà quella di
      // prima», invece di «questa la cancelli e sparisce».
      v['copre'] = voci.containsKey(f);
      voci[f] = v;
    }

    final fuori = voci.values.toList();
    fuori.sort((a, b) => (a['nome'] as String)
        .toLowerCase()
        .compareTo((b['nome'] as String).toLowerCase()));
    return fuori;
  }

  Future<List<Map<String, dynamic>>> _leggiCartella(
      String cartella, bool dellUtente) async {
    final dir = Directory(cartella);
    if (!await dir.exists()) return const [];

    final fuori = <Map<String, dynamic>>[];
    await for (final e in dir.list(followLinks: false)) {
      if (!e.path.endsWith('.desktop')) continue;
      final voce = await _leggiVoce(e.path, dellUtente);
      if (voce != null) fuori.add(voce);
    }
    return fuori;
  }

  Future<Map<String, dynamic>?> _leggiVoce(
      String percorso, bool dellUtente) async {
    final campi = <String, String>{};
    try {
      var dentro = false;
      for (final raw in await File(percorso).readAsLines()) {
        final riga = raw.trim();
        if (riga.startsWith('[')) {
          // Un `.desktop` può avere più sezioni (le «azioni»): fuori da
          // `[Desktop Entry]` i campi si chiamano uguale e vogliono dire
          // altro. Senza questo controllo si legge l'`Exec` sbagliato.
          dentro = riga == '[Desktop Entry]';
          continue;
        }
        if (!dentro || riga.isEmpty || riga.startsWith('#')) continue;
        final eq = riga.indexOf('=');
        if (eq <= 0) continue;
        campi[riga.substring(0, eq).trim()] = riga.substring(eq + 1).trim();
      }
    } catch (_) {
      return null;
    }

    final exec = campi['Exec'] ?? '';
    if (exec.isEmpty) return null;

    final nomeFile = percorso.split('/').last;

    return {
      'file': nomeFile,
      'percorso': percorso,
      'nome': campi['Name']?.isNotEmpty == true
          ? campi['Name']!
          : nomeFile.replaceAll('.desktop', ''),
      'commento': campi['Comment'] ?? '',
      'exec': exec,
      'icona': campi['Icon'] ?? '',
      'utente': dellUtente,
      // ── «Acceso» vuol dire: PARTE ────────────────────────────────────
      //
      // Non «il file non è disabilitato». Per una voce di sistema le due
      // cose sono diverse: `Hidden` non c'è, quindi il file sarebbe attivo,
      // ma Minerva `/etc/xdg/autostart` non la legge — quindi non parte
      // niente.
      //
      // La prima versione mostrava quelle voci con la levetta ACCESA. È il
      // difetto peggiore che possa avere un interruttore: dice una cosa e ne
      // fa un'altra, e chi lo guarda conclude che `baloo_file` gli sta
      // indicizzando il disco mentre non sta girando affatto. Accendendola
      // se ne fa una copia fra le proprie, e da lì parte davvero.
      'acceso': dellUtente && _motivoSpenta(campi).isEmpty,
      // Perché è spenta, quando lo è. Una levetta spenta senza spiegazione
      // fa provare a riaccenderla all'infinito.
      'motivo': _motivoSpenta(campi),
    };
  }

  String _motivoSpenta(Map<String, String> campi) {
    if (campi['Hidden']?.toLowerCase() == 'true') return 'spenta';

    // La convenzione di GNOME, che quasi tutti rispettano.
    if (campi['X-GNOME-Autostart-enabled']?.toLowerCase() == 'false') {
      return 'spenta';
    }

    // `TryExec` dice: parti solo se questo programma c'è. È il campo che
    // salva dalle voci rimaste dopo una disinstallazione.
    final prova = campi['TryExec'];
    if (prova != null && prova.isNotEmpty && !_esiste(prova)) {
      return 'il programma non è installato';
    }

    // `OnlyShowIn` / `NotShowIn`: per quali ambienti vale.
    //
    // ── I nomi si CHIEDONO, non si scrivono ─────────────────────────────
    //
    // Qui c'era `{'minerva', 'hyprland'}` scritto a mano. Il 2 settembre 2026
    // la sessione ha cominciato a dichiararsi `MinervaWayland:Minerva:Hyprland`
    // — `MinervaWayland` per primo, perché è il nome con cui i portali scelgono
    // il backend giusto — e questo elenco non lo conosceva: una voce con
    // `OnlyShowIn=MinervaWayland;` risultava «di un altro ambiente» **a casa
    // sua**.
    //
    // Il difetto non è il nome mancante, è che ce ne fosse una seconda copia.
    // `XDG_CURRENT_DESKTOP` è la risposta che il resto del sistema usa e che
    // la sessione scrive in un posto solo (`start-minerva-wayland.sh`): qui si
    // legge quella. L'elenco scritto a mano resta come ripiego per quando la
    // variabile non c'è — dentro una prova, o se il demone parte da un
    // terminale.
    final dichiarati = (Platform.environment['XDG_CURRENT_DESKTOP'] ?? '')
        .split(':')
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet();
    final nostri = dichiarati.isNotEmpty
        ? dichiarati
        : {'minervawayland', 'minerva', 'hyprland'};
    final solo = campi['OnlyShowIn'];
    if (solo != null && solo.isNotEmpty) {
      final elenco = solo.split(';').map((s) => s.trim().toLowerCase());
      if (!elenco.any(nostri.contains)) return 'è di un altro ambiente';
    }
    final non = campi['NotShowIn'];
    if (non != null && non.isNotEmpty) {
      final elenco = non.split(';').map((s) => s.trim().toLowerCase());
      if (elenco.any(nostri.contains)) return 'è di un altro ambiente';
    }

    return '';
  }

  bool _esiste(String comando) {
    if (comando.startsWith('/')) {
      return File(comando).existsSync();
    }
    final path = Platform.environment['PATH'] ?? '';
    for (final d in path.split(':')) {
      if (d.isEmpty) continue;
      if (File('$d/$comando').existsSync()) return true;
    }
    return false;
  }

  // ── Modificare ───────────────────────────────────────────────────────────

  /// Accende o spegne una voce.
  ///
  /// Se la voce è di sistema se ne fa prima una copia nella cartella
  /// dell'utente: `/etc/xdg/autostart` non è scrivibile, e non deve esserlo.
  Future<Map<String, dynamic>> imposta(String file, bool acceso) async {
    final mio = File('$cartellaUtente/$file');

    if (!await mio.exists()) {
      String? sorgente;
      for (final c in cartelleSistema) {
        if (await File('$c/$file').exists()) {
          sorgente = '$c/$file';
          break;
        }
      }
      if (sorgente == null) {
        return {'ok': false, 'error': 'Non trovo «$file».'};
      }
      try {
        await Directory(cartellaUtente).create(recursive: true);
        await File(sorgente).copy(mio.path);
      } catch (e) {
        return {'ok': false, 'error': 'Non riesco a copiarla: $e'};
      }
    }

    try {
      final righe = await mio.readAsLines();
      final fuori = <String>[];
      var scritto = false;
      var dentro = false;

      for (final raw in righe) {
        final riga = raw.trim();
        if (riga.startsWith('[')) {
          // Prima di uscire da `[Desktop Entry]`, se la riga non c'era, la si
          // aggiunge: metterla dopo, in un'altra sezione, non conterebbe.
          if (dentro && !scritto) {
            fuori.add('Hidden=${acceso ? 'false' : 'true'}');
            scritto = true;
          }
          dentro = riga == '[Desktop Entry]';
          fuori.add(raw);
          continue;
        }
        if (dentro && riga.toLowerCase().startsWith('hidden=')) {
          fuori.add('Hidden=${acceso ? 'false' : 'true'}');
          scritto = true;
          continue;
        }
        // `X-GNOME-Autostart-enabled=false` spegnerebbe comunque: se c'è, va
        // riportata d'accordo con la levetta, o si accende una voce che
        // resta spenta e sembra che il comando non abbia funzionato.
        if (dentro &&
            riga.toLowerCase().startsWith('x-gnome-autostart-enabled=')) {
          fuori.add('X-GNOME-Autostart-enabled=${acceso ? 'true' : 'false'}');
          continue;
        }
        fuori.add(raw);
      }

      if (!scritto) fuori.add('Hidden=${acceso ? 'false' : 'true'}');
      await mio.writeAsString('${fuori.join('\n')}\n');
      return {'ok': true, 'error': ''};
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
  }

  /// Aggiunge un programma all'avvio.
  ///
  /// `nome` è quello che si legge nell'elenco, `comando` è quello che parte.
  Future<Map<String, dynamic>> aggiungi(String nome, String comando) async {
    final pulito = nome.trim();
    final cmd = comando.trim();
    if (pulito.isEmpty) return {'ok': false, 'error': 'Manca il nome.'};
    if (cmd.isEmpty) return {'ok': false, 'error': 'Manca il comando.'};

    // Il nome del file si ricava dal nome, ma ridotto a qualcosa che non
    // possa mai essere un percorso: senza questo, un nome con una barra
    // scriverebbe fuori dalla cartella.
    var base = pulito.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    base = base.replaceAll(RegExp(r'^-+|-+$'), '');
    if (base.isEmpty) base = 'avvio';

    try {
      await Directory(cartellaUtente).create(recursive: true);
    } catch (e) {
      return {'ok': false, 'error': 'Non riesco a creare la cartella: $e'};
    }

    var destinazione = '$cartellaUtente/minerva-$base.desktop';
    var n = 2;
    while (await File(destinazione).exists()) {
      destinazione = '$cartellaUtente/minerva-$base-$n.desktop';
      n++;
    }

    try {
      await File(destinazione).writeAsString('[Desktop Entry]\n'
          'Type=Application\n'
          'Name=$pulito\n'
          'Exec=$cmd\n'
          'X-Minerva-Autostart=true\n'
          'Hidden=false\n');
      return {'ok': true, 'error': '', 'file': destinazione.split('/').last};
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
  }

  /// Toglie del tutto una voce dell'utente.
  ///
  /// Solo dalla cartella dell'utente, e solo se il nome è un nome e non un
  /// percorso: `togli('../../.bashrc')` non deve poter cancellare niente.
  Future<Map<String, dynamic>> togli(String file) async {
    if (file.contains('/') || file.contains('..') || !file.endsWith('.desktop')) {
      return {'ok': false, 'error': 'Nome non valido.'};
    }
    final mio = File('$cartellaUtente/$file');
    if (!await mio.exists()) {
      return {'ok': false, 'error': 'Non c\'è niente da togliere.'};
    }
    try {
      await mio.delete();
      return {'ok': true, 'error': ''};
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
  }
}
