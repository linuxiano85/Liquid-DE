import 'dart:io';

import '../ipc/websocket_server.dart' show WebSocketServer;
import 'app_scanner.dart';
import 'mime_database.dart';

/// MimeService — Chi apre che cosa.
///
/// Nasce da un difetto preciso: Minerva apriva le immagini con Google Chrome.
/// Non perché qualcuno l'avesse deciso, ma perché nessuno l'aveva deciso —
/// senza una riga in `mimeapps.list` la scelta cade sul primo programma che
/// dichiara di saper leggere quel tipo, e un browser dichiara di saper leggere
/// quasi tutto. Il visualizzatore di immagini installato apposta perdeva
/// contro un programma che l'immagine la mostra per caso.
///
/// ── PERCHÉ NON `xdg-mime` E `xdg-open` ───────────────────────────────────
///
/// Sono script di shell del pacchetto `xdg-utils` che, prima di fare
/// qualunque cosa, guardano `XDG_CURRENT_DESKTOP` e delegano all'ambiente:
/// `kreadconfig5` su KDE, `gio` su GNOME, e solo se non riconoscono niente
/// leggono i file loro. Su una sessione Minerva finiscono sempre nel ramo
/// «generico», cioè nel ramo meno curato — e comunque significa affidare a un
/// altro progetto la risposta alla domanda più elementare che un ambiente
/// grafico si senta fare: «con che cosa apro questo?».
///
/// Qui la specifica freedesktop è applicata direttamente. È corta, è pubblica,
/// e implementarla vuol dire che la risposta non dipende da quali altri
/// ambienti sono installati sulla macchina.
class MimeService {
  MimeService(this._apps, {MimeDatabase? database, String? cartellaConfig})
      : _db = database ?? MimeDatabase(),
        _configFinta = cartellaConfig;

  /// Dove sta `mimeapps.list`, quando non lo si vuole prendere dall'ambiente.
  /// Le prove non devono riscrivere quello di chi le esegue.
  final String? _configFinta;

  final AppScanner _apps;

  /// Il database dei tipi di `shared-mime-info`. Si può imporre dalle prove.
  final MimeDatabase _db;

  String get _home => Platform.environment['HOME'] ?? '';

  String get _configHome {
    if (_configFinta != null) return _configFinta;
    final v = Platform.environment['XDG_CONFIG_HOME'];
    if (v != null && v.isNotEmpty) return v;
    return _home.isEmpty ? '' : '$_home/.config';
  }

  List<String> get _configDirs {
    final v = Platform.environment['XDG_CONFIG_DIRS'];
    final raw = (v != null && v.isNotEmpty) ? v : '/etc/xdg';
    return raw.split(':').where((d) => d.trim().isNotEmpty).toList();
  }

  List<String> get _dataDirs {
    final home = Platform.environment['XDG_DATA_HOME'];
    final dataHome = (home != null && home.isNotEmpty)
        ? home
        : (_home.isEmpty ? '' : '$_home/.local/share');
    final v = Platform.environment['XDG_DATA_DIRS'];
    final raw = (v != null && v.isNotEmpty) ? v : '/usr/local/share:/usr/share';
    return [
      if (dataHome.isNotEmpty) dataHome,
      ...raw.split(':').where((d) => d.trim().isNotEmpty),
    ];
  }

  /// Il file che scriviamo noi. Gli altri della catena si leggono soltanto:
  /// sono di sistema o di altri ambienti, e riscriverli sarebbe presunzione.
  String get userMimeApps => '$_configHome/mimeapps.list';

  /// Tutti i `mimeapps.list` che contano, in ordine di precedenza. Il primo
  /// che risponde vince: è la regola della specifica, ed è anche l'unica che
  /// permetta a una scelta dell'utente di battere una scelta della
  /// distribuzione.
  List<String> get _mimeAppsChain => [
        userMimeApps,
        for (final d in _configDirs) '$d/mimeapps.list',
        for (final d in _dataDirs) '$d/applications/mimeapps.list',
      ];

  // ── Che cos'è questo file ──────────────────────────────────────────────

  /// Il tipo di un percorso.
  ///
  /// ── Prima il NOME, poi il contenuto ────────────────────────────────────
  ///
  /// Qui c'era solo `file --mime-type`, e il commento diceva che guardare
  /// dentro è meglio che guardare l'estensione. Sembra ragionevole e non lo
  /// era: `file` è un programma per indovinare il contenuto di uno stream, non
  /// il database dei tipi di un desktop, e i nomi che restituisce non sono
  /// sempre quelli che il resto del sistema usa. Il difetto per cui è venuto
  /// fuori: uno script `.sh` risultava `text/x-shellscript` mentre
  /// `mimeapps.list` diceva `application/x-shellscript` — lo stesso tipo con
  /// due nomi — e non si apriva più niente. Vedi `mime_database.dart`.
  ///
  /// La specifica dice di partire dal nome, e da lì si parte. Chi non ha
  /// estensione (`README`, `gradlew`) passa a `file`, che per quel caso è
  /// proprio lo strumento giusto.
  ///
  /// ── L'eccezione: fra immagini, suoni e video decide il contenuto ───────
  ///
  /// Il commento di prima non era campato in aria, e su questa macchina il suo
  /// caso esiste davvero: `~/Immagini/IMG_20260704_153943.mp4` **è un JPEG**, e
  /// una suoneria `.mp3` è un WAV. Un nome sbagliato dentro le famiglie
  /// immagine/suono/video è l'unico caso in cui aprire col programma
  /// sbagliato non mostra niente — un lettore video davanti a una fotografia
  /// resta nero.
  ///
  /// Quindi: il nome decide sempre, tranne quando dice «immagine, suono o
  /// video». Lì si chiede anche a `file`, e se anche lui dice una di quelle tre
  /// famiglie si dà retta a lui. Costo: un processo in più per le fotografie e
  /// **zero** per tutto il resto — prima era uno per ogni file di ogni tipo.
  Future<String> detect(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: true);
    if (type == FileSystemEntityType.directory) return 'inode/directory';
    if (type == FileSystemEntityType.notFound) return '';

    final dalNome = await _db.perNome(path);
    if (dalNome.isNotEmpty && !_daAnnusare(dalNome)) return dalNome;

    final dalContenuto = await _dalContenuto(path);
    if (dalNome.isNotEmpty) {
      // Il contenuto vince solo se parla della stessa famiglia: se dice
      // `text/plain` di un `.svg` sta solo dicendo che dentro c'è del testo,
      // che è vero e inutile.
      return _daAnnusare(dalContenuto) ? dalContenuto : dalNome;
    }
    if (dalContenuto.isNotEmpty) return dalContenuto;
    return _byExtension(path);
  }

  /// Le tre famiglie in cui un nome sbagliato fa danno.
  static bool _daAnnusare(String mime) =>
      const {'image', 'audio', 'video'}.contains(mime.split('/').first);

  /// Il tipo secondo `file`, tradotto nei nomi che usa il resto del sistema.
  Future<String> _dalContenuto(String path) async {
    try {
      final r = await Process.run('file', ['--mime-type', '-b', '--', path]);
      final out = (r.stdout as String).trim();
      if (out.isEmpty || !out.contains('/')) return '';
      return await _db.canonico(_nomiDiLibmagic[out] ?? out);
    } catch (_) {
      // `file` non installato: si ripiega sull'estensione, che è meglio di
      // niente ma non merita di essere la strada principale.
      return '';
    }
  }

  /// I nomi che `file` si inventa e che freedesktop non conosce.
  ///
  /// Non stanno in `aliases` perché non sono alias di niente: sono nomi di un
  /// altro vocabolario. `text/x-script.python` non compare in nessun
  /// `.desktop` installato, quindi un `.py` riconosciuto così non aveva
  /// nessuno che lo aprisse.
  static const Map<String, String> _nomiDiLibmagic = {
    'text/x-script.python': 'text/x-python',
    'text/x-c++': 'text/x-c++src',
    'text/x-c': 'text/x-csrc',
  };

  static const Map<String, String> _extensions = {
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'webp': 'image/webp',
    'gif': 'image/gif',
    'svg': 'image/svg+xml',
    'pdf': 'application/pdf',
    'txt': 'text/plain',
    'md': 'text/markdown',
    'mp3': 'audio/mpeg',
    'flac': 'audio/flac',
    'mp4': 'video/mp4',
    'mkv': 'video/matroska',
    'zip': 'application/zip',
  };

  String _byExtension(String path) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot < 0) return 'application/octet-stream';
    return _extensions[name.substring(dot + 1).toLowerCase()] ??
        'application/octet-stream';
  }

  // ── Chi lo apre ────────────────────────────────────────────────────────

  /// Quel che si è già letto, con la data del file a fare da scadenza.
  ///
  /// Non è un lusso: un `mime_categories` chiede il predefinito di una
  /// sessantina di tipi, e ognuno rileggeva i quattro `mimeapps.list` della
  /// catena — duecentoquaranta letture di file per disegnare una pagina delle
  /// impostazioni. Con la data si rilegge solo ciò che è cambiato davvero, e
  /// chi scrive (`_riscrivi`) svuota la cache da sé.
  final Map<String, ({DateTime quando, Map<String, String> voci})> _letto = {};

  void _dimentica() => _letto.clear();

  /// Legge una sezione di un file in stile INI.
  Future<Map<String, String>> _section(String file, String section) async {
    final f = File(file);
    if (!await f.exists()) return {};
    final chiave = '$file\u0000$section';
    try {
      final quando = (await f.stat()).modified;
      final gia = _letto[chiave];
      if (gia != null && gia.quando == quando) return gia.voci;
      final voci = await _leggiSezione(f, section);
      _letto[chiave] = (quando: quando, voci: voci);
      return voci;
    } catch (_) {
      return _leggiSezione(f, section);
    }
  }

  Future<Map<String, String>> _leggiSezione(File f, String section) async {
    final out = <String, String>{};
    var inside = false;
    try {
      for (final raw in await f.readAsLines()) {
        final line = raw.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        if (line.startsWith('[') && line.endsWith(']')) {
          inside = (line == '[$section]');
          continue;
        }
        if (!inside) continue;
        final eq = line.indexOf('=');
        if (eq <= 0) continue;
        out[line.substring(0, eq).trim()] = line.substring(eq + 1).trim();
      }
    } catch (_) {
      return out;
    }
    return out;
  }

  /// Il programma predefinito per un tipo, o stringa vuota.
  ///
  /// Una voce che nomina un `.desktop` che non esiste più si SALTA invece di
  /// far fallire tutto: succede a ogni programma disinstallato, e un ambiente
  /// che smette di aprire le immagini perché è stato tolto un visualizzatore
  /// che nessuno usava sarebbe assurdo.
  ///
  /// ── Si cerca lungo la PARENTELA, non su un nome solo ───────────────────
  ///
  /// Due allargamenti, e vengono dallo stesso difetto (vedi
  /// `mime_database.dart`):
  ///
  ///  · a ogni anello si provano tutti i NOMI di quel tipo, canonico e alias.
  ///    I `mimeapps.list` che stanno già sul disco sono scritti con gli alias
  ///    — quello di Giacomo dice `application/x-shellscript` — e cercare solo
  ///    il nome canonico non li trovava;
  ///  · si risale ai tipi GENITORI. Uno script è testo semplice con qualcosa
  ///    in più: se nessuno ha scelto un programma per gli script, quello del
  ///    testo semplice è la risposta giusta, non il vuoto.
  ///
  /// L'ordine conta: l'anello più vicino vince su tutti i file, quindi una
  /// scelta fatta per gli script batte quella fatta per il testo semplice
  /// anche se la seconda sta in un file più importante.
  ///
  /// `eredita: false` serve ai GRUPPI delle impostazioni: là la domanda è «per
  /// questo tipo qualcuno ha scelto?», e rispondere «sì, quello del testo
  /// semplice» farebbe apparire deciso un gruppo dove non si è deciso niente —
  /// e spegnerebbe per sempre l'avviso «non per tutti».
  Future<String> defaultFor(String mime, {bool eredita = true}) async {
    if (mime.isEmpty) return '';
    // Le sezioni si leggono UNA volta e non a ogni anello: la catena può
    // essere lunga quattro e i file sono quattro, e sedici letture di file
    // per un doppio clic sono sedici letture di troppo.
    final sezioni = <Map<String, String>>[];
    for (final file in _mimeAppsChain) {
      sezioni.add(await _section(file, 'Default Applications'));
    }

    // Senza la radice: un programma che dichiarasse
    // `application/octet-stream` diventerebbe quello che apre ogni file
    // sconosciuto della macchina, e «non lo so» è meglio di una bugia.
    final catena = eredita
        ? await _db.catena(mime, conRadice: false)
        : <String>[await _db.canonico(mime)];

    for (final anello in catena) {
      final nomi = await _db.nomiDi(anello);
      for (final defaults in sezioni) {
        for (final nome in nomi) {
          final value = defaults[nome];
          if (value == null || value.isEmpty) continue;
          for (final id in value.split(';')) {
            final trimmed = id.trim();
            if (trimmed.isEmpty) continue;
            if (_apps.getAppById(trimmed) != null) return trimmed;
          }
        }
      }
    }
    return '';
  }

  /// Tutti i programmi che sanno aprire quel tipo, il più adatto per primo.
  ///
  /// ── PERCHÉ SERVE UN PUNTEGGIO E NON L'ORDINE ALFABETICO ────────────────
  ///
  /// Firefox, Chrome e Gwenview dichiarano tutti e tre `image/png`, e in
  /// ordine alfabetico vince Firefox. Ma un browser apre un'immagine come
  /// effetto collaterale del fatto che apre pagine web: non ha lo zoom, non
  /// ha la freccia per la foto successiva, non ruota niente. Il
  /// visualizzatore di immagini fa una cosa sola e la fa apposta.
  ///
  /// Contare quanti tipi dichiara ciascuno non basta a distinguerli — sono
  /// venticinque contro ventiquattro. Quello che li distingue è la
  /// CATEGORIA che si sono dati: `WebBrowser` contro `Graphics;Viewer`. È
  /// una dichiarazione d'intenti scritta dall'autore del programma, ed è
  /// l'informazione giusta a cui dare retta.
  Future<List<Map<String, dynamic>>> candidatesFor(String mime) async {
    final scored = await scoredFor(mime);
    scored.sort((a, b) {
      if (a.value != b.value) return b.value.compareTo(a.value);
      return a.key.name.toLowerCase().compareTo(b.key.name.toLowerCase());
    });
    // Si manda il minimo indispensabile e non `toJson()`: la lista completa
    // dei tipi dichiarati è lunga venticinque righe per applicazione, non
    // serve a chi disegna il menu, e per un elenco di dieci candidati sono
    // duecentocinquanta stringhe che attraversano il socket per niente.
    return scored
        .map((e) => {
              'id': e.key.id,
              'name': e.key.name,
              'icon': e.key.icon,
              'iconPath': e.key.iconPath ?? '',
            })
        .toList();
  }

  /// Gli stessi candidati col punteggio in chiaro, non ordinati.
  ///
  /// Serve ai gruppi. Mettere insieme i candidati di nove tipi guardando solo
  /// la POSIZIONE nelle nove classifiche premia chi è l'unico a dichiarare il
  /// tipo più oscuro del mucchio: Firefox finiva primo fra gli editor di
  /// testo perché era il solo a dichiarare `application/json`, e arrivava
  /// primo in una classifica di uno.
  /// ── E l'EREDITARIETÀ, che è ciò che riempie l'elenco ───────────────────
  ///
  /// Un programma entra in classifica anche se dichiara non questo tipo ma un
  /// suo GENITORE. Senza, l'elenco dei candidati per uno script era **vuoto**
  /// — nessun `.desktop` installato dichiara `text/x-shellscript` — e la
  /// finestra delle proprietà nascondeva del tutto la colonna «Si apre con»:
  /// un file che non si poteva né aprire, né assegnare, né eseguire.
  ///
  /// ── Perché uno SCALINO da cento e non un malus da dieci ────────────────
  ///
  /// Perché `_fitness` oscilla di sessantacinque punti (+25 al browser sul
  /// web, −40 altrove, −12 al terminale, +15 al mestiere giusto), e un malus
  /// di dieci si fa scavalcare. Provato sul caso vero: con dieci punti Vim,
  /// che `application/x-shellscript` lo dichiara per nome ma vuole un
  /// terminale, finiva DIETRO a un editor che arriva per eredità. Chi dichiara
  /// il tipo deve stare davanti, per quanto sia meno comodo — è l'unico che
  /// abbia detto di saperlo aprire.
  ///
  /// I numeri di prima (100 e 50) diventano 1000 e 150. Nessuno li legge come
  /// valori assoluti: servono solo ai due ordinamenti e all'unione per gruppo.
  Future<List<MapEntry<DesktopApp, int>>> scoredFor(String mime) async {
    if (mime.isEmpty) return [];
    final family = mime.split('/').first;
    final catena = await _db.catena(mime);
    final nomi = <List<String>>[
      for (final anello in catena) await _db.nomiDi(anello)
    ];
    final scored = <MapEntry<DesktopApp, int>>[];

    for (final app in _apps.apps) {
      if (app.mimeTypes.isEmpty) continue;
      var score = -1;
      var distanza = 0;
      // Si scende la parentela e ci si ferma al PRIMO anello che risponde:
      // un programma vale per quanto è vicino al tipo vero, non per quanti
      // dei suoi antenati dichiara.
      for (var i = 0; i < catena.length && score < 0; i++) {
        final famigliaAnello = catena[i].split('/').first;
        for (final declared in app.mimeTypes) {
          if (nomi[i].contains(declared)) {
            score = 1000;
            break;
          }
          // Il jolly `text/*` è una dichiarazione più debole di un'eredità
          // vera: dice «apro un po' di tutto», non «apro questa cosa».
          if (declared == '$famigliaAnello/*') score = score < 150 ? 150 : score;
        }
        if (score >= 0) distanza = i;
      }
      if (score < 0) continue;
      score += _fitness(app, mime, family) - distanza * 100;
      scored.add(MapEntry(app, score));
    }
    return scored;
  }

  /// Quanto un programma è FATTO per quel tipo, al di là del fatto che lo
  /// sappia aprire.
  int _fitness(DesktopApp app, String mime, String family) {
    final cats = app.categories.map((c) => c.toLowerCase()).toSet();
    var bonus = 0;

    // Un browser che apre un'immagine è un ripiego, e come tale va in fondo.
    // Non quando il tipo è roba da browser: lì è la scelta giusta.
    final isWeb = cats.contains('webbrowser');
    final webIsRight = mime == 'text/html' ||
        mime == 'application/xhtml+xml' ||
        mime.startsWith('x-scheme-handler/');
    if (isWeb && !webIsRight) bonus -= 40;
    // E quando il tipo è roba da browser, il browser è la risposta giusta e
    // non solo la meno sbagliata.
    if (isWeb && webIsRight) bonus += 25;

    // Chi si è dichiarato del mestiere sale — ma non quando il mestiere è un
    // altro. `text/html` sta nella famiglia `text`, e senza questa guardia un
    // editor di testo prende il premio da editor e passa davanti al browser:
    // Micro apriva le pagine web, che tecnicamente sa fare e mostra il
    // sorgente HTML. È la risposta giusta a un'altra domanda.
    if (webIsRight) return bonus - (app.mimeTypes.length ~/ 20);

    switch (family) {
      case 'image':
        if (cats.contains('graphics') || cats.contains('viewer')) bonus += 15;
        if (cats.contains('photography') || cats.contains('rastergraphics')) {
          bonus += 5;
        }
        break;
      case 'audio':
      case 'video':
        if (cats.contains('audiovideo') || cats.contains('player')) bonus += 15;
        break;
      case 'text':
        if (cats.contains('texteditor') || cats.contains('development')) {
          bonus += 15;
        }
        break;
      case 'inode':
        if (cats.contains('filemanager')) bonus += 20;
        break;
    }

    // Un programma che ha bisogno di un terminale resta una scelta legittima
    // — c'è chi legge i file di testo con Vim e ha ragione — ma non è la
    // scelta da proporre per prima a chi ha appena fatto doppio clic con il
    // mouse. Per un indirizzo web non è nemmeno una scelta: `micro
    // https://…` apre un file vuoto con quel nome.
    if (app.needsTerminal) {
      bonus -= mime.startsWith('x-scheme-handler/') ? 60 : 12;
    }

    // A parità di tutto, chi dichiara meno tipi ha scelto meglio di chi
    // dichiara tutto. Vale poco, e serve solo a rompere i pareggi.
    bonus -= (app.mimeTypes.length ~/ 20);

    // E a parità ancora, i programmi di Minerva vengono prima. Non è
    // favoritismo: questa è la sessione di Minerva, e il suo gestore file
    // perdeva contro Dolphin per ordine alfabetico — «Dolphin» viene prima di
    // «File». Sono tre punti, quindi non basta a superare un programma
    // davvero più adatto: sposta solo i pareggi.
    if (app.id.startsWith('minerva-')) bonus += 3;
    return bonus;
  }

  // ── Categorie ──────────────────────────────────────────────────────────

  /// I gruppi che si offrono nelle impostazioni.
  ///
  /// ── PERCHÉ NON UN TIPO ALLA VOLTA ──────────────────────────────────────
  ///
  /// Un pannello che chiede «chi apre image/png?» e poi «chi apre image/jpeg?»
  /// e poi altre cinque volte non è un pannello: è il file `mimeapps.list`
  /// ridisegnato. E soprattutto non risolve il problema, perché chi sceglie il
  /// visualizzatore per i PNG si aspetta di aver scelto per LE IMMAGINI — e
  /// invece il primo JPEG torna nel browser, con la sensazione che
  /// l'impostazione non abbia funzionato.
  ///
  /// Qui si sceglie una volta per gruppo e si scrivono tutti i tipi del
  /// gruppo. I tipi elencati sono quelli che capitano davvero: l'elenco
  /// completo di IANA sarebbe più corretto sulla carta e inutile in pratica,
  /// perché scrivere una riga per `image/x-portable-graymap` non cambia la
  /// vita a nessuno e allunga il file di tutti gli altri ambienti.
  /// Le FAMIGLIE, cioè come i gruppi si presentano in Impostazioni.
  ///
  /// Giacomo, 17 agosto 2026: «riorganizza questa sezione per tipi affini,
  /// mettiamo delle tendine espandibili dove poi aprire e scegliere i
  /// programmi… così la sezione sarà più compatta e semplice sapendo che tipo
  /// di app cerchi».
  ///
  /// Quindici gruppi in fila sono un elenco da scorrere; cinque tendine sono
  /// un posto dove si sa già dove guardare. La divisione sta QUI e non nella
  /// pagina perché è la stessa informazione dei gruppi: chi aggiunge un
  /// gruppo deve dire dove va, e se lo decidesse la pagina se ne dimenticherebbe.
  static const List<Map<String, dynamic>> famiglie = [
    {'id': 'internet', 'it': 'Internet', 'en': 'Internet', 'icon': 'globe'},
    {'id': 'documenti', 'it': 'Documenti', 'en': 'Documents', 'icon': 'document'},
    {'id': 'media', 'it': 'Immagini, musica e video',
     'en': 'Images, music and video', 'icon': 'image'},
    {'id': 'codice', 'it': 'Testo e codice', 'en': 'Text and code',
     'icon': 'code'},
    {'id': 'sistema', 'it': 'Sistema', 'en': 'System', 'icon': 'sliders'},
  ];

  /// ── I NOMI DEI TIPI SI VERIFICANO, NON SI RICORDANO ──────────────────
  ///
  /// Ogni stringa qui sotto è stata cercata in `/usr/share/mime/globs2` prima
  /// di scriverla. Non è pedanteria: su trentatré nomi scritti a memoria ne
  /// erano sbagliati NOVE, e uno di quegli sbagli — `application/x-shellscript`
  /// al posto di `text/x-shellscript` — è il difetto per cui `joca.sh` non si
  /// apriva più (vedi `mime_database.dart`). I casi che ingannano di più:
  ///
  ///   `application/x-cd-image`  →  `application/vnd.efi.iso`
  ///   `audio/x-m4a`             →  `audio/mp4`
  ///   `text/x-c`                →  `text/x-csrc`
  ///   `text/x-ruby`             →  `application/x-ruby`
  ///   `text/xml`                →  `application/xml`
  ///
  /// E quattro erano sbagliati **da prima**, cioè stavano già in questa
  /// tabella: `audio/x-wav` (è `audio/vnd.wave`), `video/x-matroska` (è
  /// `video/matroska`), `video/x-msvideo` (è `video/vnd.avi`) e `audio/opus`,
  /// che non è nemmeno un alias — un `.opus` è `audio/x-opus+ogg`. Erano lì da
  /// mesi, e nessuno se n'era accorto perché senza gli alias NIENTE di questa
  /// tabella combaciava mai davvero.
  ///
  /// I primi quattro sono alias veri, quindi adesso funzionerebbero lo stesso;
  /// si scrive comunque il nome canonico, perché è quello che finisce nel
  /// `mimeapps.list` di tutti gli altri ambienti.
  static const List<Map<String, dynamic>> categories = [
    {
      'id': 'web',
      'famiglia': 'internet',
      'it': 'Pagine web',
      'en': 'Web pages',
      'icon': 'globe',
      'mimes': [
        'text/html',
        'application/xhtml+xml',
        'x-scheme-handler/http',
        'x-scheme-handler/https',
      ],
    },
    {
      'id': 'mail',
      'famiglia': 'internet',
      'it': 'Posta',
      'en': 'Mail',
      'icon': 'mail',
      'mimes': ['x-scheme-handler/mailto', 'message/rfc822'],
    },
    {
      'id': 'torrent',
      'famiglia': 'internet',
      'it': 'Torrent',
      'en': 'Torrents',
      'icon': 'globe',
      'mimes': ['application/x-bittorrent', 'x-scheme-handler/magnet'],
    },
    {
      'id': 'document',
      'famiglia': 'documenti',
      'it': 'Documenti PDF',
      'en': 'PDF documents',
      'icon': 'pdf',
      'mimes': ['application/pdf'],
    },
    {
      'id': 'ufficio',
      'famiglia': 'documenti',
      'it': 'Documenti di testo',
      'en': 'Text documents',
      'icon': 'document',
      'mimes': [
        'application/vnd.oasis.opendocument.text',
        'application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/rtf',
      ],
    },
    {
      'id': 'foglio',
      'famiglia': 'documenti',
      'it': 'Fogli di calcolo',
      'en': 'Spreadsheets',
      'icon': 'table',
      'mimes': [
        'application/vnd.oasis.opendocument.spreadsheet',
        'application/vnd.ms-excel',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'text/csv',
      ],
    },
    {
      'id': 'presentazione',
      'famiglia': 'documenti',
      'it': 'Presentazioni',
      'en': 'Presentations',
      'icon': 'slides',
      'mimes': [
        'application/vnd.oasis.opendocument.presentation',
        'application/vnd.ms-powerpoint',
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      ],
    },
    {
      'id': 'libro',
      'famiglia': 'documenti',
      'it': 'Libri e fumetti',
      'en': 'Books and comics',
      'icon': 'list',
      'mimes': [
        'application/epub+zip',
        'application/x-mobipocket-ebook',
        'application/x-fictionbook+xml',
        'image/vnd.djvu',
        'application/vnd.comicbook+zip',
        'application/vnd.comicbook-rar',
      ],
    },
    {
      'id': 'image',
      'famiglia': 'media',
      'it': 'Immagini',
      'en': 'Images',
      'icon': 'image',
      'mimes': [
        'image/png',
        'image/jpeg',
        'image/gif',
        'image/webp',
        'image/bmp',
        'image/tiff',
        'image/svg+xml',
        'image/avif',
        'image/heif',
        'image/jxl',
        'image/vnd.microsoft.icon',
        'image/x-xcf',
        'image/vnd.adobe.photoshop',
      ],
    },
    {
      'id': 'video',
      'famiglia': 'media',
      'it': 'Video',
      'en': 'Video',
      'icon': 'video',
      'mimes': [
        'video/mp4',
        'video/matroska',
        'video/webm',
        'video/quicktime',
        'video/vnd.avi',
        'video/mpeg',
        'video/x-ms-wmv',
        'video/3gpp',
        'video/ogg',
        'video/x-flv',
      ],
    },
    {
      'id': 'audio',
      'famiglia': 'media',
      'it': 'Musica',
      'en': 'Music',
      'icon': 'music',
      'mimes': [
        'audio/mpeg',
        'audio/flac',
        'audio/ogg',
        'audio/vnd.wave',
        'audio/mp4',
        'audio/x-vorbis+ogg',
        'audio/x-opus+ogg',
        'audio/aac',
        'audio/midi',
        'audio/x-ms-wma',
      ],
    },
    {
      'id': 'text',
      'famiglia': 'codice',
      'it': 'Testo e codice',
      'en': 'Text and code',
      'icon': 'code',
      'mimes': [
        'text/plain',
        'text/markdown',
        'application/json',
        'application/xml',
        'text/x-shellscript',
        'text/x-python',
        'text/javascript',
        'text/x-csrc',
        'text/x-c++src',
        'text/x-java',
        'text/x-lua',
        'application/x-ruby',
        'text/x-go',
        'application/vnd.dart',
        'application/yaml',
        'application/toml',
      ],
    },
    {
      'id': 'folder',
      'famiglia': 'sistema',
      'it': 'Cartelle',
      'en': 'Folders',
      'icon': 'folder',
      'mimes': ['inode/directory'],
    },
    {
      'id': 'archive',
      'famiglia': 'sistema',
      'it': 'Archivi',
      'en': 'Archives',
      'icon': 'archive',
      'mimes': [
        'application/zip',
        'application/x-tar',
        'application/gzip',
        'application/x-xz',
        'application/x-7z-compressed',
        'application/vnd.rar',
        'application/zstd',
        'application/x-bzip2',
        'application/x-lzma',
      ],
    },
    {
      'id': 'disco',
      'famiglia': 'sistema',
      'it': 'Immagini disco',
      'en': 'Disk images',
      'icon': 'disco',
      'mimes': ['application/vnd.efi.iso', 'application/vnd.efi.img'],
    },
    {
      'id': 'font',
      'famiglia': 'sistema',
      'it': 'Caratteri',
      'en': 'Fonts',
      'icon': 'font',
      'mimes': [
        'font/ttf',
        'font/otf',
        'font/woff',
        'font/woff2',
        'font/collection',
      ],
    },
  ];

  /// Stato di ogni gruppo: chi lo apre adesso e chi potrebbe.
  ///
  /// `mixed` è la cosa che rende onesto il pannello. Un sistema vissuto ha
  /// quasi sempre i tipi sparpagliati fra programmi diversi — le immagini a
  /// Gwenview tranne i SVG che sono finiti a Inkscape. Mostrare solo il
  /// programma del primo tipo direbbe una cosa falsa; dirlo apertamente
  /// permette di sistemare la faccenda con un clic.
  Future<List<Map<String, dynamic>>> categoryState() async {
    final out = <Map<String, dynamic>>[];
    for (final cat in categories) {
      final mimes = (cat['mimes'] as List).cast<String>();

      final chosen = <String>[];
      for (final m in mimes) {
        // Senza eredità: vedi `defaultFor`. Un gruppo dove non si è
        // scelto niente deve continuare a dire «da scegliere».
        chosen.add(await defaultFor(m, eredita: false));
      }
      final present = chosen.where((c) => c.isNotEmpty).toList();
      final first = present.isEmpty ? '' : present.first;
      // «Non per tutti» ha senso solo se QUALCOSA è stato scelto. Un gruppo
      // dove non è stato deciso niente è già segnalato da «da scegliere»:
      // aggiungerci anche l'avviso vorrebbe dire mettere un cartello di
      // avvertimento su una situazione normale, e nove cartelli su un
      // pannello appena aperto insegnano solo a non leggerli.
      final mixed = present.isNotEmpty &&
          (present.length != mimes.length || present.any((c) => c != first));

      // I candidati sono l'unione su tutti i tipi del gruppo, ciascuno col
      // punteggio migliore che ottiene: un programma che apre i MKV ma non i
      // MP4 deve comunque comparire fra i lettori video.
      final best = <String, int>{};
      final byId = <String, DesktopApp>{};
      for (final m in mimes) {
        for (final e in await scoredFor(m)) {
          final id = e.key.id;
          if (!best.containsKey(id) || e.value > best[id]!) {
            best[id] = e.value;
            byId[id] = e.key;
          }
        }
      }
      final ids = best.keys.toList()
        ..sort((a, b) {
          if (best[a] != best[b]) return best[b]!.compareTo(best[a]!);
          return byId[a]!.name.toLowerCase().compareTo(byId[b]!.name.toLowerCase());
        });

      out.add({
        'id': cat['id'],
        'famiglia': cat['famiglia'],
        'it': cat['it'],
        'en': cat['en'],
        'icon': cat['icon'],
        'mimes': mimes,
        'defaultApp': first,
        'mixed': mixed,
        'candidates': ids
            .map((i) => {
                  'id': byId[i]!.id,
                  'name': byId[i]!.name,
                  'icon': byId[i]!.icon,
                  'iconPath': byId[i]!.iconPath ?? '',
                })
            .toList(),
      });
    }
    return out;
  }

  /// Assegna un programma a tutti i tipi di un gruppo.
  Future<Map<String, dynamic>> setCategory(String id, String appId) async {
    final cat = categories.where((c) => c['id'] == id);
    if (cat.isEmpty) return {'ok': false, 'error': 'Gruppo sconosciuto'};
    final mimes = (cat.first['mimes'] as List).cast<String>();
    return setDefaults(mimes, appId);
  }

  /// Tutto ciò che serve al pannello e al menu «Apri con…».
  Future<Map<String, dynamic>> describe(String path) async {
    final mime = await detect(path);
    return {
      'path': path,
      'mime': mime,
      'defaultApp': await defaultFor(mime),
      'candidates': await candidatesFor(mime),
    };
  }

  // ── Scegliere ──────────────────────────────────────────────────────────

  /// Scrive la scelta in `~/.config/mimeapps.list`.
  ///
  /// Il file si riscrive intero conservando tutto ciò che non riguarda questo
  /// tipo: è di tutti gli ambienti, non nostro, e cancellare le righe di
  /// qualcun altro perché non le capiamo è il modo migliore per rompere il
  /// sistema di chi ci prova.
  Future<Map<String, dynamic>> setDefault(String mime, String appId) =>
      setDefaults([mime], appId);

  /// Come sopra, ma per più tipi in una sola riscrittura.
  ///
  /// Chiamare `setDefault` nove volte di fila darebbe lo stesso file e nove
  /// letture, nove riscritture e otto occasioni di lasciarlo a metà se
  /// qualcosa va storto nel mezzo. Un gruppo si scrive tutto o niente.
  Future<Map<String, dynamic>> setDefaults(
      List<String> mimes, String appId) async {
    final wanted = mimes.where((m) => m.trim().isNotEmpty).toSet();
    if (wanted.isEmpty || appId.isEmpty) {
      return {'ok': false, 'error': 'Tipo o applicazione mancante'};
    }
    return _riscrivi(
      tocca: wanted,
      cambia: (sezione, mime, righe) {
        if (sezione == 'Default Applications') return '$mime=$appId';
        if (sezione == 'Added Associations') {
          // AGGIUNGE, non sostituisce. Questa sezione è un elenco separato da
          // `;` di tutti i programmi che devono comparire fra le scelte anche
          // se non dichiarano il tipo nel proprio `.desktop`; riscriverla con
          // un valore solo cancellava le aggiunte di prima. È anche il motivo
          // per cui `application/x-shellscript` compariva DUE volte nel file
          // di Giacomo.
          final gia = righe
              .where((v) => v.trim().isNotEmpty && v.trim() != appId)
              .toList();
          return '$mime=${[appId, ...gia].join(';')}';
        }
        return null;
      },
      risposta: {'mimes': wanted.toList(), 'appId': appId},
    );
  }

  /// Toglie il programma predefinito di un tipo: da lì in poi decide di nuovo
  /// il sistema.
  ///
  /// Non si scrive niente in `[Removed Associations]`, che vorrebbe dire
  /// un'altra cosa — «quel programma non deve nemmeno comparire fra le
  /// scelte» — e non è quello che chiede chi preme «Non ricordare più».
  Future<Map<String, dynamic>> forgetDefault(String mime) async {
    if (mime.trim().isEmpty) {
      return {'ok': false, 'error': 'Tipo mancante'};
    }
    return _riscrivi(
      tocca: {mime.trim()},
      // Vuoto vuol dire «togli»; `null` vuol dire «lascia com'era». Le altre
      // sezioni non si toccano: è esattamente il difetto che c'era prima.
      cambia: (sezione, m, righe) =>
          sezione == 'Default Applications' ? '' : null,
      risposta: {'mimes': [mime.trim()], 'appId': ''},
    );
  }

  /// Riscrive `~/.config/mimeapps.list` toccando SOLO i tipi indicati.
  ///
  /// ── Tre difetti riparati tutti insieme ─────────────────────────────────
  ///
  /// La versione di prima:
  ///
  ///  1. cancellava la riga del tipo da OGNI sezione, compresa `[Removed
  ///     Associations]` — cioè, per assegnare un programma, toglieva di mezzo
  ///     la riga che dice il contrario di quello che si sta facendo;
  ///  2. buttava via i commenti e tutto ciò che stava prima della prima
  ///     sezione, a ogni scrittura;
  ///  3. scriveva con un `writeAsString` diretto, mentre `fs_write` in questo
  ///     stesso progetto usa `tmp`+`rename`. Un file di configurazione
  ///     troncato a metà da un calo di corrente è un ambiente che al riavvio
  ///     non sa più aprire niente.
  ///
  /// `cambia` riceve la sezione, il tipo e i valori che quella riga aveva, e
  /// risponde:
  ///
  ///   · **una riga** → si scrive quella;
  ///   · **`null`** → la riga di prima resta com'era (o non se ne aggiunge
  ///     nessuna, se non c'era);
  ///   · **stringa vuota** → la riga si toglie.
  ///
  /// La distinzione fra le ultime due è tutta la differenza fra riparare il
  /// difetto e rifarlo: «non ho niente da dire su questa sezione» non è
  /// «cancella».
  Future<Map<String, dynamic>> _riscrivi({
    required Set<String> tocca,
    required String? Function(String sezione, String mime, List<String> valori)
        cambia,
    required Map<String, dynamic> risposta,
  }) async {
    final file = File(userMimeApps);
    try {
      await file.parent.create(recursive: true);

      // Si conserva TUTTO: intestazione, commenti, righe vuote, ordine.
      final testa = <String>[];
      final ordine = <String>[];
      final sezioni = <String, List<String>>{};
      final valori = <String, Map<String, List<String>>>{};
      var corrente = '';

      if (await file.exists()) {
        for (final grezza in await file.readAsLines()) {
          final riga = grezza.trim();
          if (riga.startsWith('[') && riga.endsWith(']')) {
            corrente = riga.substring(1, riga.length - 1);
            if (!ordine.contains(corrente)) {
              ordine.add(corrente);
              sezioni[corrente] = [];
              valori[corrente] = {};
            }
            continue;
          }
          if (corrente.isEmpty) {
            testa.add(grezza);
            continue;
          }
          final uguale = riga.indexOf('=');
          if (uguale > 0 && !riga.startsWith('#')) {
            final chiave = riga.substring(0, uguale).trim();
            if (tocca.contains(chiave)) {
              // Si mette da parte e non si riscrive qui: la riga nuova la
              // decide `cambia`, e va al posto della vecchia.
              valori[corrente]![chiave] =
                  riga.substring(uguale + 1).split(';');
              continue;
            }
          }
          sezioni[corrente]!.add(grezza);
        }
      }

      for (final s in ['Default Applications', 'Added Associations']) {
        if (!ordine.contains(s)) {
          ordine.add(s);
          sezioni[s] = [];
          valori[s] = {};
        }
      }

      for (final s in ordine) {
        for (final mime in tocca) {
          final vecchi = valori[s]?[mime];
          final nuova = cambia(s, mime, vecchi ?? const <String>[]);
          if (nuova == null) {
            // Lasciata com'era. Torna in fondo alla sua sezione invece che
            // al suo posto esatto: si muove solo la riga dei tipi toccati, e
            // in un file di coppie `chiave=valore` l'ordine non significa
            // niente.
            if (vecchi != null) sezioni[s]!.add('$mime=${vecchi.join(';')}');
          } else if (nuova.isNotEmpty) {
            sezioni[s]!.add(nuova);
          }
        }
      }

      final buffer = StringBuffer();
      for (final riga in testa) {
        buffer.writeln(riga);
      }
      for (final s in ordine) {
        buffer.writeln('[$s]');
        for (final riga in sezioni[s]!) {
          if (riga.trim().isEmpty) continue;
          buffer.writeln(riga);
        }
        buffer.writeln();
      }

      // Scrittura in due tempi: chi legge il file trova o quello di prima o
      // quello nuovo, mai mezzo.
      final tmp = File('$userMimeApps.nuovo');
      await tmp.writeAsString(buffer.toString(), flush: true);
      await tmp.rename(userMimeApps);
      _dimentica();

      return {'ok': true, 'error': '', ...risposta};
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
  }

  // ── Aprire ─────────────────────────────────────────────────────────────

  /// Apre dei percorsi con un programma preciso.
  ///
  /// La riga `Exec=` si rilegge dal .desktop invece di usare quella già
  /// ripulita dallo scanner, perché i codici di campo contano: `%f` vuole UN
  /// percorso (e allora il programma va lanciato una volta per file), `%F` li
  /// vuole tutti insieme, `%u`/`%U` li vogliono come indirizzi. Passare
  /// sempre tutto insieme funziona finché non capita il programma che apre
  /// solo il primo file e ignora gli altri in silenzio.
  Future<Map<String, dynamic>> openWith(String appId, List<String> paths) async {
    final app = _apps.getAppById(appId);
    if (app == null) return {'ok': false, 'error': 'Applicazione sconosciuta'};

    final execLine = await _rawExec(appId);
    if (execLine.isEmpty) return {'ok': false, 'error': 'Riga Exec mancante'};

    final singular = execLine.contains('%f') || execLine.contains('%u');
    final batches = singular ? paths.map((p) => [p]).toList() : [paths];

    try {
      for (final batch in batches) {
        final argv = _expand(execLine, batch);
        if (argv.isEmpty) continue;
        if (app.needsTerminal) {
          // ── Non sempre c'è Alacritty (30 settembre 2026) ──────────────
          //
          // Qui il terminale era scritto a mano: `alacritty -e`. Su un
          // computer senza Alacritty «Apri con → Vim» rispondeva «fatto»
          // (il `sh` staccato parte sempre) e non si apriva niente. Il
          // demone sa già scegliere un terminale che c'è —
          // `dentroUnTerminale` — e si usa quello. Gli argomenti diventano
          // una riga di shell uno a uno, ciascuno fra virgolette singole: un
          // nome di file con spazi o apostrofi resta un argomento solo.
          await Process.start(
            'sh',
            ['-c', WebSocketServer.dentroUnTerminale(rigaDiShell(argv))],
            mode: ProcessStartMode.detached,
          );
        } else {
          await Process.start(argv.first, argv.sublist(1),
              mode: ProcessStartMode.detached);
        }
      }
      return {'ok': true, 'error': ''};
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
  }

  /// Gli argomenti come riga di shell, ognuno fra virgolette singole.
  /// Pubblica per provarla: è il punto in cui un nome di file diventa testo
  /// che una shell interpreta.
  static String rigaDiShell(List<String> argv) => argv
      .map((a) => "'${WebSocketServer.protettaPerShell(a)}'")
      .join(' ');

  /// La riga `Exec=` originale, codici di campo compresi.
  Future<String> _rawExec(String appId) async {
    for (final dir in _dataDirs) {
      final f = File('$dir/applications/$appId');
      if (!await f.exists()) continue;
      var inside = false;
      for (final raw in await f.readAsLines()) {
        final line = raw.trim();
        if (line.startsWith('[') && line.endsWith(']')) {
          inside = (line == '[Desktop Entry]');
          continue;
        }
        if (inside && line.startsWith('Exec=')) return line.substring(5).trim();
      }
    }
    // Nelle cartelle Flatpak e nei percorsi non standard: si ripiega su ciò
    // che lo scanner aveva già letto, senza codici di campo.
    return _apps.getAppById(appId)?.exec ?? '';
  }

  /// Spezza la riga in argomenti rispettando le virgolette, e sostituisce i
  /// codici di campo con i percorsi. Gli altri codici (`%i`, `%c`, `%k`) si
  /// tolgono: valgono icona, nome e percorso del .desktop, e nessuno di essi
  /// serve per aprire un file.
  List<String> _expand(String execLine, List<String> paths) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    String? quote;
    for (var i = 0; i < execLine.length; i++) {
      final c = execLine[i];
      if (quote != null) {
        if (c == quote) {
          quote = null;
        } else if (c == '\\' && i + 1 < execLine.length) {
          buffer.write(execLine[++i]);
        } else {
          buffer.write(c);
        }
        continue;
      }
      if (c == '"' || c == "'") {
        quote = c;
        continue;
      }
      if (c == ' ') {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
        continue;
      }
      buffer.write(c);
    }
    if (buffer.isNotEmpty) tokens.add(buffer.toString());

    final argv = <String>[];
    for (final t in tokens) {
      switch (t) {
        case '%f':
        case '%u':
          if (paths.isNotEmpty) argv.add(paths.first);
          break;
        case '%F':
        case '%U':
          argv.addAll(paths);
          break;
        case '%i':
        case '%c':
        case '%k':
        case '%d':
        case '%D':
        case '%n':
        case '%N':
        case '%v':
        case '%m':
          break;
        default:
          argv.add(t);
      }
    }

    // Un .desktop senza codici di campo non dice dove vanno i file: si
    // accodano. È il comportamento di qualunque programma da riga di comando.
    final hadField = tokens.any((t) => t.length == 2 && t.startsWith('%'));
    if (!hadField) argv.addAll(paths);
    return argv;
  }
}
