import 'dart:io';

/// Una cartella di icone dichiarata in `index.theme`.
class _IconDir {
  final String path; // relativo alla radice del tema: "apps/48" oppure "48x48/apps"
  final int size;
  final String type; // Fixed | Scalable | Threshold
  final int minSize;
  final int maxSize;

  const _IconDir(this.path, this.size, this.type, this.minSize, this.maxSize);

  /// Quanto questa cartella si discosta dalla dimensione desiderata.
  /// Più basso è meglio; le cartelle scalabili coprono un intervallo.
  int distanceTo(int wanted) {
    if (type == 'Scalable') {
      if (wanted < minSize) return minSize - wanted;
      if (wanted > maxSize) return wanted - maxSize;
      return 0;
    }
    return (size - wanted).abs();
  }
}

/// Un tema di icone caricato dal suo `index.theme`.
class _IconTheme {
  final String name;

  /// TUTTE le cartelle in cui questo tema esiste, in ordine di precedenza.
  ///
  /// Sono più d'una, e non è un caso raro: la specifica Freedesktop dice
  /// espressamente che un tema può stare sparso fra le cartelle base, e
  /// `hicolor` lo è sempre — l'`index.theme` sta in `/usr/share/icons/hicolor`
  /// e le icone dei programmi installati dall'utente in
  /// `~/.local/share/icons/hicolor`. Qui si teneva solo la cartella dove si
  /// era trovato `index.theme`, e il risultato era che le icone di Minerva —
  /// installate esattamente dove dice la specifica — non si trovavano mai:
  /// il gestore file, le Impostazioni e Attività mostravano tutti e tre
  /// l'ingranaggio grigio di «programma senza icona».
  final List<String> roots;

  final List<_IconDir> dirs;
  final List<String> inherits;

  const _IconTheme(this.name, this.roots, this.dirs, this.inherits);
}

/// Risolve il nome di un'icona (es. "firefox") nel percorso del file su disco.
///
/// Segue la specifica Freedesktop leggendo `index.theme`, invece di indovinare
/// la struttura delle cartelle. È la differenza fra funzionare e non funzionare:
/// Papirus organizza le icone come `48x48/apps/`, Breeze come `apps/48/`.
/// Un resolver che conosce un solo schema trova le icone di alcuni temi e
/// mostra riquadri vuoti per tutti gli altri.
class IconResolver {
  final Map<String, String> _cache = {};
  final Map<String, _IconTheme?> _themes = {};

  /// Il tema rilevato dalle impostazioni di sistema — quello che si usa
  /// quando nessuno ne ha scelto uno.
  String _detectedTheme = 'hicolor';

  /// Il tema scelto in Impostazioni. Vuoto = si segue il sistema.
  String _chosenTheme = '';

  List<String>? _chain;

  /// Le icone del menu applicazioni sono circa 48px.
  static const int _preferredSize = 48;

  late final List<String> _iconRoots;
  late final String _home;

  // ── Famiglie e varianti ────────────────────────────────────────────────
  //
  // Quasi ogni tema di icone è installato tre volte: «Colloid»,
  // «Colloid-Dark», «Colloid-Light». Non sono tre temi diversi — sono lo
  // stesso disegno colorato per due sfondi diversi, e la desinenza dice per
  // QUALE sfondo. «-Dark» vuol dire «per un'interfaccia scura», e le sue
  // icone monocromatiche sono chiare.
  //
  // Finché l'elenco delle Impostazioni mostrava i nomi delle cartelle, si
  // poteva scegliere quella sbagliata senza saperlo, e non c'era nessun modo
  // di accorgersene prima: Giacomo aveva scelto «Colloid-Light», e nel
  // pannello di controllo l'ingranaggio di «Animazioni» era un grigio scuro
  // su fondo scuro — c'era e non si vedeva.
  //
  // Adesso si sceglie la FAMIGLIA e la variante la decide Minerva, che è
  // l'unica a sapere di che colore è il proprio sfondo. È anche ciò che serve
  // ai temi chiari (bianco, rosa, verde): cambiando lo sfondo cambiano le
  // icone, senza che nessuno debba tornare nelle impostazioni.

  static const List<String> _desinenzeScure = ['-Dark', '-dark', '-Black'];
  static const List<String> _desinenzeChiare = ['-Light', '-light'];

  /// Vero quando l'interfaccia di Minerva è scura, e quindi vanno usate le
  /// varianti «-Dark» — quelle disegnate per starci sopra.
  bool _interfacciaScura = true;

  bool get interfacciaScura => _interfacciaScura;

  /// Cambia lo sfondo di riferimento. Restituisce vero se è cambiato davvero,
  /// perché allora la mappa delle icone va rifatta.
  bool setInterfacciaScura(bool scura) {
    if (scura == _interfacciaScura) return false;
    _interfacciaScura = scura;
    // Il giudizio su cosa si vede dipende dal fondo: cambiando fondo va
    // rifatto da capo, o si continuerebbe a servire le icone dell'altro.
    _visibilita.clear();
    _cache.clear();
    _chain = null;
    return true;
  }

  /// Il nome di famiglia di un tema: «Colloid-Light» → «Colloid».
  static String famiglia(String nome) {
    for (final d in [..._desinenzeScure, ..._desinenzeChiare]) {
      if (nome.length > d.length && nome.endsWith(d)) {
        return nome.substring(0, nome.length - d.length);
      }
    }
    return nome;
  }

  /// Vero se il tema esiste ed è un tema di icone (non di puntatori).
  bool _utilizzabile(String nome) {
    final t = _loadTheme(nome);
    return t != null && t.dirs.isNotEmpty;
  }

  /// La variante di questa famiglia adatta allo sfondo dell'interfaccia.
  ///
  /// Se non ce n'è una si prende la famiglia nuda, e in ultima istanza la
  /// variante dell'altro colore: un'icona un po' fuori tono si vede comunque,
  /// un riquadro vuoto no.
  String variantePer(String nome) {
    final fam = famiglia(nome);
    final volute = _interfacciaScura ? _desinenzeScure : _desinenzeChiare;
    final altre = _interfacciaScura ? _desinenzeChiare : _desinenzeScure;
    for (final d in volute) {
      if (_utilizzabile('$fam$d')) return '$fam$d';
    }
    if (_utilizzabile(fam)) return fam;
    for (final d in altre) {
      if (_utilizzabile('$fam$d')) return '$fam$d';
    }
    return nome;
  }

  /// Il tema effettivamente in uso: la variante giusta di quello scelto se
  /// c'è, altrimenti di quello del sistema.
  String get activeTheme => variantePer(
      _chosenTheme.isNotEmpty ? _chosenTheme : _detectedTheme);

  /// La famiglia scelta in Impostazioni, o vuota se si segue il sistema. È
  /// questa che l'elenco delle Impostazioni deve evidenziare, non
  /// `activeTheme`: chi ha scelto «Colloid» non deve vedersi acceso
  /// «Colloid-Dark», che nell'elenco non c'è nemmeno.
  String get chosenTheme => _chosenTheme;

  String get detectedTheme => famiglia(_detectedTheme);

  IconResolver() {
    final env = Platform.environment;
    _home = env['HOME'] ?? '';
    _iconRoots = _radiciBase(env, _home);
    _iconRoots.addAll(_radiciAnnidate());
  }

  /// Le cartelle base delle icone, in ordine di precedenza.
  ///
  /// Erano quattro scritte a mano, e mancava proprio quella di Liquid DE:
  /// l'installatore mette le icone delle nostre app in
  /// `~/.local/opt/liquid-de/share/icons/hicolor`, la sessione aggiunge quel
  /// `share` in testa a `XDG_DATA_DIRS`, e qui non lo guardava nessuno. I
  /// `.desktop` si trovavano (lo scanner legge `XDG_DATA_DIRS`), le icone no:
  /// sul computer di prova del 29 settembre 2026 la dock mostrava File,
  /// Impostazioni e Custodia senza icona.
  ///
  /// Adesso si segue la specifica — `XDG_DATA_HOME` e ogni `XDG_DATA_DIRS`,
  /// ciascuno con `/icons` — e il prefisso di Liquid DE si aggiunge anche per
  /// nome (stessa regola di `scripts/minerva-cartelle.sh`), perché un demone
  /// avviato con un ambiente povero non perda di nuovo le icone.
  static List<String> _radiciBase(Map<String, String> env, String home) {
    String base(String variabile, String ripiego) {
      final v = env[variabile] ?? '';
      return v.startsWith('/') ? v : ripiego;
    }

    final dataHome = base('XDG_DATA_HOME', '$home/.local/share');
    final dataDirs = (env['XDG_DATA_DIRS']?.isNotEmpty == true
            ? env['XDG_DATA_DIRS']!
            : '/usr/local/share:/usr/share')
        .split(':')
        .where((d) => d.startsWith('/'));
    final prefisso = base('LIQUID_PREFISSO', '$home/.local/opt/liquid-de');

    String senzaBarra(String d) =>
        d.length > 1 && d.endsWith('/') ? d.substring(0, d.length - 1) : d;

    return <String>{
      '$home/.local/share/icons',
      '$home/.icons',
      '${senzaBarra(dataHome)}/icons',
      for (final d in dataDirs) '${senzaBarra(d)}/icons',
      '${senzaBarra(prefisso)}/share/icons',
      '/usr/local/share/icons',
      '/usr/share/icons',
    }.toList();
  }

  /// Le cartelle scompattate UNA DI TROPPO.
  ///
  /// ── Perché esiste ──────────────────────────────────────────────────────
  ///
  /// Giacomo, 6 settembre 2026: «in .local/share/icons ho messo vari temi
  /// icone ma non compaiono nei set icone in impostazioni».
  ///
  /// Tre su cinque non comparivano, e non era un difetto della ricerca: erano
  /// scompattati un livello troppo in fondo —
  /// `~/.local/share/icons/Fluent-purple/Fluent-purple/index.theme` invece di
  /// `~/.local/share/icons/Fluent-purple/index.theme`. È quello che succede
  /// estraendo un archivio dentro una cartella che ha già il suo nome, ed è
  /// l'errore più comune che ci sia con i temi.
  ///
  /// Si potrebbe rispondere «rimettili a posto». Ma un tema installato che non
  /// compare, senza che niente lo dica, è esattamente il difetto che questo
  /// progetto si è messo per iscritto di non commettere. E riconoscerlo costa
  /// una cartella in più da guardare.
  ///
  /// La regola è stretta apposta: si scende di UN livello, e solo dentro una
  /// cartella che **non è già un tema** (non ha un `index.theme` suo) ma che
  /// contiene almeno un tema. Così non si va a pescare in giro, e una cartella
  /// di icone normale non cambia comportamento.
  List<String> _radiciAnnidate() {
    final fuori = <String>[];
    for (final root in _iconRoots) {
      final dir = Directory(root);
      if (!dir.existsSync()) continue;
      for (final entry in dir.listSync()) {
        if (entry is! Directory) continue;
        if (File('${entry.path}/index.theme').existsSync()) continue;
        var contieneUnTema = false;
        try {
          for (final dentro in entry.listSync()) {
            if (dentro is Directory &&
                File('${dentro.path}/index.theme').existsSync()) {
              contieneUnTema = true;
              break;
            }
          }
        } catch (_) {
          continue;
        }
        if (contieneUnTema) fuori.add(entry.path);
      }
    }
    return fuori;
  }

  /// Rileva il tema icone attivo dalle impostazioni di sistema.
  Future<void> init() async {
    final detected = await _detectTheme();
    if (detected != null && detected.isNotEmpty) {
      _detectedTheme = detected;
      print('[MINERVA][MATRIX][INFO] Tema icone di sistema: $_detectedTheme');
    } else {
      print('[MINERVA][MATRIX][WARN] Tema icone non rilevato. Fallback su: $_detectedTheme');
    }

    // Precarica la catena, così la prima risoluzione non paga la lettura
    // dei file index.theme.
    final chain = _themeChain();
    print('[MINERVA][MATRIX][INFO] Catena temi icone: ${chain.join(" → ")}');
  }

  /// Cambia il tema di icone. Stringa vuota = torna a seguire il sistema.
  ///
  /// Butta via la cache: contiene percorsi del tema precedente, e senza
  /// svuotarla il cambio si vedrebbe solo sulle icone mai chieste prima —
  /// cioè, dopo qualche minuto d'uso, su nessuna.
  /// Si accetta anche il nome di una variante («Colloid-Light»): si tiene la
  /// famiglia. Serve a chi ha nelle impostazioni un nome salvato quando la
  /// scelta era ancora fra le varianti.
  bool setTheme(String name) {
    final wanted = famiglia(name.trim());
    if (wanted == _chosenTheme) return false;
    _chosenTheme = wanted;
    _cache.clear();
    _chain = null;
    print('[MINERVA][MATRIX][INFO] Tema icone in uso: $activeTheme');
    return true;
  }

  /// Le FAMIGLIE di icone installate, in ordine alfabetico.
  ///
  /// Si escludono due cose. I temi di soli puntatori del mouse: dichiarano
  /// `index.theme` come tutti gli altri ma non hanno nessuna cartella di
  /// icone, e nell'elenco delle Impostazioni sarebbero voci che non cambiano
  /// niente. E le varianti chiara e scura, che sono lo stesso tema: mostrarle
  /// vuol dire chiedere di scegliere per quale sfondo va bene un'icona, che è
  /// una cosa che Minerva sa e chi guarda no.
  List<String> listThemes() {
    final famiglie = <String>{};
    for (final root in _iconRoots) {
      final dir = Directory(root);
      if (!dir.existsSync()) continue;
      for (final entry in dir.listSync()) {
        if (entry is! Directory) continue;
        final name = entry.path.split('/').last;
        if (!File('${entry.path}/index.theme').existsSync()) continue;
        final theme = _loadTheme(name);
        if (theme == null || theme.dirs.isEmpty) continue;
        famiglie.add(famiglia(name));
      }
    }
    final sorted = famiglie.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
  }

  Future<String?> _detectTheme() async {
    // 1. KDE — la sorgente più attendibile su un sistema con Plasma installato
    final kdeglobals = File('$_home/.config/kdeglobals');
    if (await kdeglobals.exists()) {
      try {
        var inIconsSection = false;
        for (final raw in await kdeglobals.readAsLines()) {
          final line = raw.trim();
          if (line.startsWith('[')) {
            inIconsSection = line == '[Icons]';
            continue;
          }
          if (inIconsSection && line.startsWith('Theme=')) {
            return line.substring('Theme='.length).trim();
          }
        }
      } catch (_) {}
    }

    // 2. GTK
    for (final path in [
      '$_home/.config/gtk-4.0/settings.ini',
      '$_home/.config/gtk-3.0/settings.ini',
    ]) {
      final file = File(path);
      if (!await file.exists()) continue;
      try {
        for (final raw in await file.readAsLines()) {
          final line = raw.trim();
          if (line.startsWith('gtk-icon-theme-name=')) {
            return line.split('=').last.trim().replaceAll('"', '');
          }
        }
      } catch (_) {}
    }

    return null;
  }

  /// Catena di ricerca: tema attivo, i suoi antenati, infine hicolor.
  List<String> _themeChain() {
    if (_chain != null) return _chain!;

    final chain = <String>[];
    final seen = <String>{};

    void walk(String name, int depth) {
      // Un tema che eredita da sé stesso, direttamente o in cerchio,
      // bloccherebbe l'avvio: la profondità massima è una rete di sicurezza.
      if (depth > 8 || !seen.add(name)) return;
      chain.add(name);
      final theme = _loadTheme(name);
      if (theme == null) return;
      for (final parent in theme.inherits) {
        walk(parent, depth + 1);
      }
    }

    walk(activeTheme, 0);
    if (seen.add('hicolor')) chain.add('hicolor');

    _chain = chain;
    return chain;
  }

  /// Legge e memorizza `index.theme`. Restituisce null se il tema non esiste.
  _IconTheme? _loadTheme(String name) {
    if (_themes.containsKey(name)) return _themes[name];

    // Le cartelle dove questo tema esiste davvero, in ordine di precedenza:
    // quelle dell'utente prima di quelle di sistema. Si calcolano una volta
    // sola perché il costo va pagato a ogni icona cercata e non trovata.
    final roots = <String>[];
    for (final root in _iconRoots) {
      if (Directory('$root/$name').existsSync()) roots.add('$root/$name');
    }
    if (roots.isEmpty) {
      _themes[name] = null;
      return null;
    }

    // L'`index.theme` invece è uno solo, e vale per tutte: descrive la forma
    // del tema (quali cartelle, di che misura), non dove sta.
    for (final root in roots) {
      final indexFile = File('$root/index.theme');
      if (!indexFile.existsSync()) continue;

      try {
        final theme = _parseIndex(name, roots, indexFile.readAsLinesSync());
        _themes[name] = theme;
        return theme;
      } catch (e) {
        print('[MINERVA][MATRIX][WARN] index.theme illeggibile per "$name": $e');
      }
    }

    _themes[name] = null;
    return null;
  }

  _IconTheme _parseIndex(String name, List<String> roots, List<String> lines) {
    var section = '';
    final sectionValues = <String, Map<String, String>>{};
    var inherits = <String>[];
    final directories = <String>[];

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      if (line.startsWith('[') && line.endsWith(']')) {
        section = line.substring(1, line.length - 1);
        continue;
      }

      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final key = line.substring(0, eq).trim();
      final value = line.substring(eq + 1).trim();

      if (section == 'Icon Theme') {
        if (key == 'Inherits') {
          inherits = value
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
        } else if (key == 'Directories' || key == 'ScaledDirectories') {
          directories.addAll(
              value.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty));
        }
      } else {
        sectionValues.putIfAbsent(section, () => {})[key] = value;
      }
    }

    final dirs = <_IconDir>[];
    for (final dir in directories) {
      final values = sectionValues[dir];
      if (values == null) continue;
      final size = int.tryParse(values['Size'] ?? '') ?? 0;
      if (size == 0) continue;
      final type = values['Type'] ?? 'Threshold';
      final minSize = int.tryParse(values['MinSize'] ?? '') ?? size;
      final maxSize = int.tryParse(values['MaxSize'] ?? '') ?? size;
      dirs.add(_IconDir(dir, size, type, minSize, maxSize));
    }

    return _IconTheme(name, roots, dirs, inherits);
  }

  /// Risolve il nome dell'icona in un percorso assoluto, con cache.
  ///
  /// `size` è la dimensione a cui l'icona verrà disegnata. Non è un dettaglio:
  /// i temi curati disegnano la stessa icona più volte per dimensioni diverse
  /// — a 16 pixel con meno dettagli e i tratti allineati alla griglia — e
  /// prendere sempre quella da 48 per poi rimpicciolirla dà un'immagine molle,
  /// che è esattamente il difetto che si nota su una barra.
  ///
  /// `generic` a false serve a chi vuole sapere se l'icona c'è davvero:
  /// il ripiego su `application-x-executable` è giusto per un programma senza
  /// icona, ed è un ingranaggio a caso al posto di «ordina».
  String resolve(String iconName, {int size = _preferredSize, bool generic = true}) {
    if (iconName.isEmpty) return '';

    // Un percorso assoluto va usato così com'è
    if (iconName.startsWith('/')) {
      return File(iconName).existsSync() ? iconName : '';
    }

    // Alcuni file .desktop scrivono "firefox.png" invece di "firefox"
    var name = iconName;
    for (final ext in ['.png', '.svg', '.xpm']) {
      if (name.toLowerCase().endsWith(ext)) {
        name = name.substring(0, name.length - ext.length);
        break;
      }
    }

    final key = '$size/${generic ? 'g' : 'x'}/$name';
    final cached = _cache[key];
    if (cached != null) return cached;

    final resolved = _search(name, size, generic);
    _cache[key] = resolved;
    return resolved;
  }

  /// I file già giudicati: leggere e misurare un SVG costa, e le stesse icone
  /// si chiedono decine di volte.
  final Map<String, bool> _visibilita = {};

  /// Vero se quell'icona si vedrebbe sul fondo dell'interfaccia.
  ///
  /// ── Perché non basta scegliere la variante giusta del tema ──────────────
  ///
  /// Perché le varianti coprono le icone di sistema e non tutte le altre. In
  /// Colloid, `places/22/folder.svg` esiste in due versioni — scura per il
  /// fondo chiaro, chiara per quello scuro — ma
  /// `mimetypes/scalable/text-x-generic.svg` è UNA sola, `#f4f4f4`, cioè
  /// quasi bianca. Su Minerva chiaro il documento sparisce, e con lui ogni
  /// file di testo del gestore file.
  ///
  /// Non è un difetto di Colloid: è che un tema di icone non promette di
  /// funzionare su tutti e due i fondi. Ed è esattamente lo scenario che
  /// conta — Giacomo, 11 agosto 2026: «se un utente installa una app non
  /// minerva avrà sempre problemi, quindi devi puntare alla perfezione».
  ///
  /// Quindi non ci si fida del nome del tema: si GUARDA il file. Se tutti i
  /// suoi colori stanno dalla stessa parte del nostro fondo, quell'icona non
  /// si userà.
  ///
  /// Solo per gli SVG: un PNG andrebbe decodificato, e decodificare
  /// ventitremila PNG per rispondere a una domanda che riguarda le icone
  /// monocromatiche — che sono quasi tutte SVG — sarebbe pagare molto per
  /// poco.
  bool siVedrebbe(File file) {
    if (!file.path.endsWith('.svg')) return true;
    final noto = _visibilita[file.path];
    if (noto != null) return noto;

    var esito = true;
    try {
      final testo = file.readAsStringSync();
      // `currentColor` vuol dire «il colore me lo dai tu»: quelle si adattano
      // sempre, e non c'è niente da giudicare.
      if (!testo.contains('currentColor')) {
        final colori = RegExp(r'#([0-9a-fA-F]{6})\b')
            .allMatches(testo)
            .map((m) => m.group(1)!)
            .toSet();
        if (colori.isNotEmpty) {
          var somma = 0.0;
          for (final c in colori) {
            final r = int.parse(c.substring(0, 2), radix: 16) / 255;
            final g = int.parse(c.substring(2, 4), radix: 16) / 255;
            final b = int.parse(c.substring(4, 6), radix: 16) / 255;
            somma += 0.2126 * r + 0.7152 * g + 0.0722 * b;
          }
          final media = somma / colori.length;
          // Le soglie sono larghe apposta: si scarta solo quello che è
          // DAVVERO tutto dalla stessa parte. Un'icona a più colori — Firefox,
          // una cartella con un accento — sta in mezzo e passa sempre.
          esito = _interfacciaScura ? media > 0.16 : media < 0.86;
        }
      }
    } catch (_) {
      // File illeggibile: si lascia passare. Meglio un'icona che forse non si
      // vede di un buco sicuro.
    }
    _visibilita[file.path] = esito;
    return esito;
  }

  String _search(String name, int size, bool generic) {
    // 1. Nei temi, dal più specifico al più generico
    for (final themeName in _themeChain()) {
      final theme = _loadTheme(themeName);
      if (theme == null) continue;

      // Le cartelle più vicine alla dimensione voluta si provano per prime
      final dirs = theme.dirs.toList()
        ..sort((a, b) => a.distanceTo(size).compareTo(b.distanceTo(size)));

      for (final dir in dirs) {
        for (final root in theme.roots) {
          for (final ext in ['.png', '.svg', '.xpm']) {
            final file = File('$root/${dir.path}/$name$ext');
            if (!file.existsSync()) continue;
            // Un'icona che sul nostro fondo non si vedrebbe non è un'icona:
            // vedi `siVedrebbe`. Si continua a cercare — in un'altra cartella
            // o in un altro tema — e se non si trova niente si torna a mani
            // vuote, così la shell disegna la sua.
            if (!siVedrebbe(file)) continue;
            return file.path;
          }
        }
      }
    }

    // 2. Cartelle legacy, fuori da qualunque tema
    for (final dir in ['/usr/share/pixmaps', '/usr/local/share/pixmaps']) {
      for (final ext in ['.png', '.svg', '.xpm']) {
        final file = File('$dir/$name$ext');
        if (file.existsSync()) return file.path;
      }
    }

    // 3. Ripiego su un'icona generica, così il riquadro non resta vuoto.
    //    Il confronto evita la ricorsione infinita se manca anche quella.
    if (generic && name != 'application-x-executable') {
      return resolve('application-x-executable', size: size);
    }

    return '';
  }
}
