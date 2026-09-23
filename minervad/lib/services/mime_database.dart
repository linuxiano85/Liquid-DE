import 'dart:io';

/// MimeDatabase — Il database dei tipi di file, letto direttamente.
///
/// Nasce da un difetto che Giacomo ha trovato facendo doppio clic sul
/// lanciatore di un suo progetto, `joca.sh`: si apriva la finestra delle
/// PROPRIETÀ. E lì la strada finiva, perché anche l'elenco «Si apre con» era
/// vuoto.
///
/// ── Perché non bastava `file` ──────────────────────────────────────────────
///
/// `MimeService.detect()` chiedeva il tipo a `file --mime-type`, che è un
/// programma per indovinare il CONTENUTO di uno stream. Guarda dentro e ignora
/// il nome — cioè fa il contrario di quello che prescrive la specifica
/// freedesktop, che dal nome parte. Le conseguenze, misurate su questa
/// macchina il 17 agosto 2026:
///
///   · uno script `.sh` risulta `text/x-shellscript`, mentre `mimeapps.list` e
///     la tabella dei gruppi dicevano `application/x-shellscript`. Sono LO
///     STESSO TIPO con due nomi — `aliases` lo dichiara — ma le due stringhe
///     non si incontravano mai;
///   · un `.py` risulta `text/x-script.python`, un nome che `file` si inventa e
///     che nel database non esiste: lì un `.py` è `text/x-python`, che nella
///     nostra tabella c'era già;
///   · un file `.desktop` risulta `text/plain`, cioè un lanciatore si apriva
///     nell'editor;
///   · certi `.js` risultano `text/x-c++`.
///
/// L'intestazione di `mime_service.dart` prometteva già questa classe — «qui la
/// specifica freedesktop è applicata direttamente» — e la metà che riguarda
/// come si RICONOSCE un tipo non era stata fatta.
///
/// ── Cosa si legge ──────────────────────────────────────────────────────────
///
/// Tre file dentro `<cartella dati>/mime/`, quarantotto kilobyte in tutto su
/// una installazione normale:
///
///   · `globs2`     `peso:tipo:modello[:cs]`   — 1549 righe
///   · `aliases`    `alias canonico`           —  357 righe
///   · `subclasses` `figlio genitore`          —  616 righe
///
/// Si leggono alla prima domanda e si tengono in memoria. Se non ci sono —
/// una macchina senza `shared-mime-info` — non si rompe niente: le tabelle
/// restano vuote, `perNome` non risponde, e `MimeService` torna esattamente
/// alla strada di prima.
class MimeDatabase {
  MimeDatabase({List<String>? cartelle}) : _cartelle = cartelle ?? cartelleXdg();

  /// Le cartelle dove cercare `mime/`. Si possono imporre dalle prove, che è
  /// l'unico modo di provare questa classe senza dipendere da quali pacchetti
  /// sono installati sulla macchina che esegue le prove.
  final List<String> _cartelle;

  static List<String> cartelleXdg() {
    final home = Platform.environment['HOME'] ?? '';
    final dataHome = Platform.environment['XDG_DATA_HOME'];
    final casa = (dataHome != null && dataHome.isNotEmpty)
        ? dataHome
        : (home.isEmpty ? '' : '$home/.local/share');
    final v = Platform.environment['XDG_DATA_DIRS'];
    final raw = (v != null && v.isNotEmpty) ? v : '/usr/local/share:/usr/share';
    return [
      if (casa.isNotEmpty) casa,
      ...raw.split(':').where((d) => d.trim().isNotEmpty),
    ];
  }

  final List<_Modello> _modelli = [];
  final Map<String, String> _alias = {};
  final Map<String, List<String>> _genitori = {};

  bool _caricato = false;
  DateTime? _dataGlobs;
  DateTime _ultimoControllo = DateTime.fromMillisecondsSinceEpoch(0);

  /// Vero se qualcosa è stato letto davvero. Serve a chi deve decidere se
  /// fidarsi o ripiegare.
  bool get pronto => _caricato && _modelli.isNotEmpty;

  /// Legge, una volta sola — e si riaccorge di un `update-mime-database`.
  ///
  /// Installare un pacchetto rigenera quei file, e il demone vive per giorni:
  /// senza questo controllo, un programma installato stamattina avrebbe i suoi
  /// tipi riconosciuti solo dopo il riavvio della sessione. Il controllo è uno
  /// `stat` e si fa al massimo una volta al minuto.
  Future<void> _assicura() async {
    final adesso = DateTime.now();
    if (_caricato) {
      if (adesso.difference(_ultimoControllo).inSeconds < 60) return;
      _ultimoControllo = adesso;
      final quando = await _dataDiGlobs();
      if (quando == null || quando == _dataGlobs) return;
    }
    _ultimoControllo = adesso;
    await _leggi();
  }

  Future<DateTime?> _dataDiGlobs() async {
    for (final d in _cartelle) {
      final f = File('$d/mime/globs2');
      try {
        if (await f.exists()) return (await f.stat()).modified;
      } catch (_) {}
    }
    return null;
  }

  Future<void> _leggi() async {
    _modelli.clear();
    _alias.clear();
    _genitori.clear();
    _caricato = true;
    _dataGlobs = await _dataDiGlobs();

    // In ordine di precedenza: la cartella dell'utente per prima. Un modello
    // aggiunto da chi usa la macchina deve poter battere quello di sistema, e
    // a parità di tutto il resto vince chi è stato letto prima.
    for (final d in _cartelle) {
      await _leggiGlobs('$d/mime/globs2');
      await _leggiCoppie('$d/mime/aliases', (a, b) {
        _alias.putIfAbsent(a, () => b);
      });
      await _leggiCoppie('$d/mime/subclasses', (figlio, genitore) {
        _genitori.putIfAbsent(figlio, () => []).add(genitore);
      });
    }
  }

  Future<void> _leggiGlobs(String percorso) async {
    final f = File(percorso);
    try {
      if (!await f.exists()) return;
      for (final riga in await f.readAsLines()) {
        if (riga.isEmpty || riga.startsWith('#')) continue;
        final p = riga.split(':');
        if (p.length < 3) continue;
        final peso = int.tryParse(p[0]);
        if (peso == null) continue;
        // Il modello può contenere `:` (raro ma legale): si ricuce tutto
        // quello che viene dopo il tipo, meno l'eventuale bandierina finale.
        var resto = p.sublist(2);
        var maiuscole = false;
        if (resto.length > 1 && resto.last == 'cs') {
          maiuscole = true;
          resto = resto.sublist(0, resto.length - 1);
        }
        final modello = resto.join(':');
        if (modello.isEmpty) continue;
        _modelli.add(_Modello(peso, p[1], modello, maiuscole));
      }
    } catch (_) {
      // Un file illeggibile vale come un file che non c'è.
    }
  }

  Future<void> _leggiCoppie(
      String percorso, void Function(String, String) aggiungi) async {
    final f = File(percorso);
    try {
      if (!await f.exists()) return;
      for (final riga in await f.readAsLines()) {
        if (riga.isEmpty || riga.startsWith('#')) continue;
        final spazio = riga.indexOf(' ');
        if (spazio <= 0) continue;
        final a = riga.substring(0, spazio).trim();
        final b = riga.substring(spazio + 1).trim();
        if (a.isEmpty || b.isEmpty) continue;
        aggiungi(a, b);
      }
    } catch (_) {}
  }

  // ── Dal nome al tipo ─────────────────────────────────────────────────────

  /// Il tipo che spetta a un NOME di file, o stringa vuota.
  ///
  /// ── L'ordine, che è quello della specifica ─────────────────────────────
  ///
  /// 1. un modello LETTERALE (`Makefile`, `core`) batte tutto: chi ha scritto
  ///    quel modello sta nominando un file preciso, non una famiglia;
  /// 2. poi il modello col peso più alto — è il numero che il database usa
  ///    proprio per dirimere `*.iso` fra sette candidati;
  /// 3. a parità di peso, il modello PIÙ LUNGO: `*.tar.gz` deve battere
  ///    `*.gz`, altrimenti un archivio compresso diventa un file compresso e
  ///    basta.
  ///
  /// Le maiuscole si ignorano, tranne per i cinque modelli che il database
  /// marca `cs` — fra cui `*.c` e `*.C`, che sono due linguaggi diversi.
  Future<String> perNome(String nome) async {
    await _assicura();
    if (_modelli.isEmpty) return '';
    final base = nome.split('/').last;
    if (base.isEmpty) return '';
    final basso = base.toLowerCase();

    _Modello? migliore;
    for (final m in _modelli) {
      if (!m.combacia(base, basso)) continue;
      if (migliore == null || m.meglioDi(migliore)) migliore = m;
    }
    return migliore?.tipo ?? '';
  }

  // ── Alias ────────────────────────────────────────────────────────────────

  /// Il nome vero di un tipo. `application/x-shellscript` →
  /// `text/x-shellscript`.
  Future<String> canonico(String tipo) async {
    if (tipo.isEmpty) return tipo;
    await _assicura();
    return _alias[tipo] ?? tipo;
  }

  /// Tutti i nomi con cui quel tipo può essere scritto: il canonico e i suoi
  /// alias.
  ///
  /// Serve a LEGGERE, non a scrivere: i `mimeapps.list` che stanno già sul
  /// disco — compreso quello di Giacomo — sono scritti con gli alias, e una
  /// ricerca che prova solo il nome canonico non li trova.
  Future<List<String>> nomiDi(String tipo) async {
    await _assicura();
    final vero = _alias[tipo] ?? tipo;
    final fuori = <String>[vero];
    _alias.forEach((a, c) {
      if (c == vero && a != vero) fuori.add(a);
    });
    return fuori;
  }

  // ── Genitori ─────────────────────────────────────────────────────────────

  /// Il tipo e i suoi antenati, dal più vicino al più lontano.
  ///
  /// ── Le due regole che nel file non ci sono ─────────────────────────────
  ///
  /// La specifica le dà per scontate e `subclasses` non le scrive:
  ///
  ///   · ogni `text/*` è figlio di `text/plain`;
  ///   · tutto ciò che non è `inode/*` è figlio di
  ///     `application/octet-stream` (solo se si chiede `conRadice`).
  ///
  /// È la prima che ripara il caso di Giacomo anche su una macchina dove
  /// `mimeapps.list` non nomini gli script: nessun programma installato
  /// dichiara `text/x-shellscript`, ma cinque dichiarano `text/plain`, e uno
  /// script È testo semplice con qualcosa in più.
  Future<List<String>> catena(String tipo, {bool conRadice = true}) async {
    if (tipo.isEmpty) return [];
    await _assicura();
    final vero = _alias[tipo] ?? tipo;

    // `x-scheme-handler/https` non è un tipo di FILE: non è «un
    // octet-stream un po' più preciso», e dargli antenati vorrebbe dire
    // proporre un editor di testo per aprire un indirizzo web.
    if (vero.startsWith('x-scheme-handler/')) return [vero];

    final fuori = <String>[vero];
    final visti = <String>{vero};
    final coda = <String>[vero];
    while (coda.isNotEmpty) {
      final ora = coda.removeAt(0);
      for (final g in _genitori[ora] ?? const <String>[]) {
        final gv = _alias[g] ?? g;
        if (!visti.add(gv)) continue;
        fuori.add(gv);
        coda.add(gv);
      }
    }

    if (vero.startsWith('text/') && visti.add('text/plain')) {
      fuori.add('text/plain');
    }
    // La radice si dà solo a chi la chiede. Per l'elenco dei candidati va
    // bene — chi sceglie a mano sa quello che fa — ma come PREDEFINITO
    // silenzioso no: un programma che dichiara la radice di tutto
    // diventerebbe quello che apre ogni file sconosciuto della macchina, e
    // «non lo so» è una risposta migliore di una bugia.
    if (conRadice &&
        !vero.startsWith('inode/') &&
        vero != 'application/octet-stream' &&
        visti.add('application/octet-stream')) {
      fuori.add('application/octet-stream');
    }
    return fuori;
  }
}

/// Una riga di `globs2`.
class _Modello {
  _Modello(this.peso, this.tipo, this.modello, this.maiuscoleContano)
      : letterale = !modello.contains(RegExp(r'[*?\[]')),
        _suffisso = modello.startsWith('*.') &&
                !modello.substring(2).contains(RegExp(r'[*?\[]'))
            ? modello.substring(1) // «.tar.gz»
            : null;

  final int peso;
  final String tipo;
  final String modello;
  final bool maiuscoleContano;
  final bool letterale;
  final String? _suffisso;

  RegExp? _rex;

  bool combacia(String nome, String basso) {
    final n = maiuscoleContano ? nome : basso;
    final m = maiuscoleContano ? modello : modello.toLowerCase();
    if (letterale) return n == m;
    final s = _suffisso;
    if (s != null) {
      final t = maiuscoleContano ? s : s.toLowerCase();
      return n.length > t.length && n.endsWith(t);
    }
    _rex ??= RegExp('^${_traduci(modello)}\$',
        caseSensitive: maiuscoleContano);
    return _rex!.hasMatch(nome);
  }

  /// Da modello di shell a espressione regolare. Sono ottantadue righe su
  /// millecinquecento, quindi la parte scomoda della specifica si paga su un
  /// ventesimo dei casi.
  static String _traduci(String g) {
    final b = StringBuffer();
    for (var i = 0; i < g.length; i++) {
      final c = g[i];
      switch (c) {
        case '*':
          b.write('.*');
          break;
        case '?':
          b.write('.');
          break;
        case '[':
          b.write('[');
          break;
        case ']':
          b.write(']');
          break;
        default:
          b.write(RegExp.escape(c));
      }
    }
    return b.toString();
  }

  /// L'ordine di preferenza: letterale, poi peso, poi lunghezza.
  bool meglioDi(_Modello altro) {
    if (letterale != altro.letterale) return letterale;
    if (peso != altro.peso) return peso > altro.peso;
    return modello.length > altro.modello.length;
  }
}
