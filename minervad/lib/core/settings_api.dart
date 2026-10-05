import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'event_bus.dart';
import 'minerva_paths.dart';

/// Gestore delle impostazioni di Minerva.
/// Carica il file settings.json, lo fonde con i valori predefiniti e ne
/// ascolta i cambiamenti in tempo reale.
class SettingsApi {
  final EventBus _eventBus;
  final String _configPath;
  Map<String, dynamic> _settings = {};
  StreamSubscription? _watcherSubscription;

  SettingsApi(this._eventBus, {String? path})
      : _configPath = path ?? MinervaPaths.settingsFile();

  Map<String, dynamic> get settings => _settings;

  /// Inizializza le impostazioni caricando il file e avviando il watcher.
  Future<void> init() async {
    final file = File(_configPath);
    if (!await file.exists()) {
      await file.parent.create(recursive: true);
      _settings = defaultSettings();
      await _write();
      print('[MINERVA][CORE][INFO] Creato file impostazioni di default in: $_configPath');
    } else {
      await _loadSettings();
      // Un file scritto da una versione precedente può non avere le chiavi
      // nuove: le aggiungiamo senza toccare le scelte già fatte dall'utente.
      // Prima si pota, poi si riempie: al contrario, una chiave sconosciuta
      // annidata dentro un gruppo appena creato verrebbe guardata due volte.
      final potate = _potaSconosciute();
      if (_fillMissingDefaults() || potate) {
        await _write();
        print('[MINERVA][CORE][INFO] Impostazioni aggiornate con le nuove opzioni.');
      }
    }

    _startWatcher();
  }

  Future<void> _loadSettings() async {
    try {
      final content = await File(_configPath).readAsString();
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        _settings = decoded;
        _testoNoto = content;
        // Il blur è stato tolto il 28 settembre 2026 («a questo punto il blur
        // lo eliminerei»): chi l'aveva scelto passa al filtro che c'è. In
        // memoria: il file si riscrive alla prossima impostazione cambiata.
        final finestre = _settings['windows'];
        if (finestre is Map && finestre['effetto'] == 'blur') {
          finestre['effetto'] = 'acquerello';
        }
        print('[MINERVA][CORE][OK] Impostazioni caricate correttamente.');
      } else {
        throw const FormatException('La radice di settings.json non è un oggetto');
      }
    } catch (e) {
      print('[MINERVA][CORE][ERRORE] Errore nel caricamento delle impostazioni: $e');
      if (_settings.isEmpty) _settings = defaultSettings();
    }
  }

  /// Quante sorveglianze del file sono aperte in questo momento. Deve essere
  /// 0 o 1, mai di più: è l'unico modo di provare che non se ne perdono per
  /// strada, perché una sorveglianza persa continua a funzionare e non si
  /// vede da nessun'altra parte.
  int get sorveglianzeAperte => _sorveglianzeAperte;
  int _sorveglianzeAperte = 0;

  /// Ferma la sorveglianza, se c'è. Azzera **prima** di aspettare: chi arriva
  /// nel frattempo non deve trovare una sottoscrizione che sta morendo.
  Future<void> _stopWatcher() async {
    final s = _watcherSubscription;
    _watcherSubscription = null;
    if (s != null) {
      _sorveglianzeAperte--;
      await s.cancel();
    }
  }

  void _startWatcher() {
    // ── Una sorveglianza sola, sempre ──────────────────────────────────────
    //
    // Senza questa riga se ne accumulavano. `_saveAndNotify` la ferma, scrive,
    // e la riavvia nel `finally`; con due salvataggi sovrapposti i due `finally`
    // ne aprivano due, e il riferimento al primo veniva sovrascritto — cioè
    // perso, ma vivo. Da lì in poi ogni modifica al file veniva letta e
    // annunciata due volte: due `settings_changed`, due ricostruzioni della
    // mappa delle icone, e il numero raddoppiava a ogni coppia successiva.
    if (_watcherSubscription != null) return;

    final file = File(_configPath);
    try {
      _watcherSubscription = file.parent.watch().listen((event) async {
        // Non basta guardare `modify`: chi scrive bene un file di
        // configurazione scrive di fianco e poi sposta (lo facciamo anche noi,
        // vedi `_write`), e allora l'evento è un `move` o un `create`. Con il
        // solo `modify` una modifica fatta da un editor di testo passava
        // inosservata, e il demone restava con le impostazioni di prima.
        final suo = event.path == file.path ||
            (event is FileSystemMoveEvent && event.destination == file.path);
        if (!suo) return;
        if (event.type != FileSystemEvent.modify &&
            event.type != FileSystemEvent.create &&
            event.type != FileSystemEvent.move) {
          return;
        }
        // Breve delay per evitare letture parziali durante il salvataggio
        await Future.delayed(const Duration(milliseconds: 100));
        // ── In fila con i salvataggi ─────────────────────────────────────
        //
        // `_stopWatcher` ferma gli eventi NUOVI, non un callback già dentro
        // questa attesa di cento millesimi: fino al 30 settembre 2026 quel
        // callback poteva ricaricare `_settings` nel mezzo di un salvataggio,
        // che poi lo sovrascriveva. Nella fila arriva dopo, e legge il file
        // com'è davvero. E si ripara come all'avvio: chi scrive il file a
        // mano può sbagliare un tipo quanto chiunque altro.
        await _inCoda(() async {
          print('[MINERVA][CORE][INFO] Rilevata modifica a settings.json. Ricaricamento...');
          await _ricarica();
          _notifyChanged();
        });
      });
      _sorveglianzeAperte++;
    } catch (e) {
      print('[MINERVA][CORE][ERRORE] Watcher impostazioni non avviato: $e');
    }
  }

  /// Il testo del file come l'abbiamo letto o scritto l'ultima volta. Se sul
  /// disco c'è altro, qualcuno l'ha cambiato da fuori.
  String? _testoNoto;

  /// Rilegge il file e lo rimette in forma: le chiavi sconosciute via, quelle
  /// mancanti e quelle col tipo sbagliato ai valori di fabbrica. In memoria:
  /// il file si riscrive al prossimo salvataggio.
  Future<void> _ricarica() async {
    await _loadSettings();
    _potaSconosciute();
    _fillMissingDefaults();
  }

  void _notifyChanged() {
    _eventBus.publish(MinervaEvent(type: 'settings_changed', payload: _settings));
  }

  // ── Lettura tipizzata ────────────────────────────────────────────────────

  /// Legge un valore con percorso a punti: `getValue('desktop.animations')`.
  dynamic getValue(String path, [dynamic fallback]) {
    dynamic node = _settings;
    for (final segment in path.split('.')) {
      if (node is Map && node.containsKey(segment)) {
        node = node[segment];
      } else {
        return fallback;
      }
    }
    return node ?? fallback;
  }

  String getString(String path, String fallback) {
    final v = getValue(path);
    return v is String ? v : fallback;
  }

  // ── Scrittura ────────────────────────────────────────────────────────────

  /// Imposta un valore con percorso a punti e salva su disco.
  /// I livelli intermedi mancanti vengono creati.
  /// Scrive un'impostazione. Restituisce `false` se il percorso non esiste.
  ///
  /// ── Perché restituisce qualcosa ────────────────────────────────────────
  ///
  /// Fino al 7 settembre 2026 non restituiva niente: il rifiuto finiva nella
  /// riga qui sotto e basta. Il registro del demone lo legge chi lo cerca; chi
  /// ha scritto l'impostazione no, e restava convinto di aver scritto. Una
  /// manopola delle Impostazioni legata a una chiave sbagliata resterebbe dove
  /// l'hai messa per sempre, senza che niente lo dica.
  ///
  /// È lo stesso difetto che il commento di `_applyValue` condanna qui sotto —
  /// «un verbo che si può scrivere e non fa niente» — arrivato un piano più su.
  Future<bool> setValue(String path, dynamic value) async {
    try {
      return await _transazione(() => _applyValue(path, value), 'Impostazione "$path" aggiornata');
    } catch (e) {
      print('[MINERVA][CORE][ERRORE] Impostazione non salvata: $e');
      return false;
    }
  }

  /// Applica più impostazioni in un colpo solo (un solo salvataggio su disco).
  ///
  /// Restituisce i percorsi RIFIUTATI, in ordine di arrivo. Vuoto vuol dire
  /// che sono passate tutte.
  ///
  /// Un gruppo non è tutto-o-niente di proposito: se un preset di venti chiavi
  /// ne contiene una scritta male, le altre diciannove devono comunque
  /// applicarsi — rifiutare tutto per una lascerebbe l'aspetto a metà fra due
  /// stili, che è peggio di tutti e due.
  Future<List<String>> setValues(Map<String, dynamic> updates) async {
    try {
      return await _transazione(() {
        final rifiutate = <String>[];
        for (final entry in updates.entries) {
          if (!_applyValue(entry.key, entry.value)) rifiutate.add(entry.key);
        }
        return rifiutate;
      }, 'Impostazioni aggiornate');
    } catch (e) {
      print('[MINERVA][CORE][ERRORE] Impostazioni non salvate: $e');
      return updates.keys.toList();
    }
  }

  /// Scrive un valore in memoria. Restituisce false se il percorso non esiste.
  ///
  /// ── Una chiave inventata non si scrive ────────────────────────────────
  ///
  /// Fino al 5 settembre 2026 questa funzione creava i rami che non
  /// trovava: qualunque percorso era buono, e scrivere `shell.fontFamily`
  /// — che non esiste — riusciva. Il risultato è una chiave che vive nel
  /// file dell'utente, non la legge nessuno, e non dà nessun errore: è
  /// esattamente il difetto che questo progetto si è messo per iscritto di
  /// non commettere («un verbo che si può scrivere e non fa niente»), e che
  /// ha già lasciato in giro quattro chiavi morte.
  ///
  /// Scoperto sbagliando: durante una prova ho scritto io stesso
  /// `shell.fontFamily`, e il demone l'ha accettata senza fiatare.
  ///
  /// Adesso il percorso deve esistere nei VALORI DI FABBRICA, che sono
  /// l'elenco di ciò che Minerva sa fare. L'unica eccezione sono le mappe
  /// dichiarate vuote (`shell.scavalca`, `desktop.desktopPositions`): una
  /// mappa vuota di fabbrica vuol dire «qui le chiavi le mette l'utente»,
  /// e sotto di esse si scrive quel che si vuole.
  bool _applyValue(String path, dynamic value) {
    final segments = path.split('.');
    if (segments.isEmpty || segments.any((s) => s.isEmpty)) return false;
    if (!_esisteDiFabbrica(segments)) {
      print('[MINERVA][CORE][ERRORE] Impostazione inesistente: "$path" '
          '— non è nei valori di fabbrica, e non si inventa');
      return false;
    }
    // ── E deve avere la FORMA di quella di fabbrica ─────────────────────
    //
    // Fino al 30 settembre 2026 il percorso si controllava e il valore no.
    // Provato sul demone: `set_setting shell 7` sostituiva il gruppo intero
    // con un numero, e al riavvio restava lì — `_fillMissingDefaults` vedeva
    // «c'è» e passava oltre; `launcher.fixedApps = [1, 2]` faceva rispondere
    // `azione_fallita` a ogni apertura del menù, per sempre. Un gruppo si
    // può ancora scrivere intero (la shell lo fa con `riva.angoli` e
    // `isola.mostra`), ma con una mappa che ha le sue chiavi e i suoi tipi.
    if (!_conforme(path, _fabbricaA(segments), value)) {
      print('[MINERVA][CORE][ERRORE] Impostazione "$path": il valore non ha '
          'il tipo di quello di fabbrica — rifiutato');
      return false;
    }

    Map<String, dynamic> node = _settings;
    for (var i = 0; i < segments.length - 1; i++) {
      final next = node[segments[i]];
      if (next is Map<String, dynamic>) {
        node = next;
      } else {
        final created = <String, dynamic>{};
        node[segments[i]] = created;
        node = created;
      }
    }
    node[segments.last] = value;
    return true;
  }

  /// Il percorso è previsto dai valori di fabbrica?
  ///
  /// Si cammina nell'albero di fabbrica insieme al percorso. Se lungo la
  /// strada si incontra una mappa VUOTA, da lì in poi è terreno libero.
  /// L'albero di fabbrica, costruito una volta sola: `defaultSettings()` lo
  /// ricrea da zero ogni volta, e qui si guarda a ogni scrittura.
  static final Map<String, dynamic> _fabbrica = defaultSettings();

  /// Il valore ha la forma di quello di fabbrica?
  ///
  /// [fabbrica] è `null` sotto una mappa libera (lì comanda l'utente) e per le
  /// poche chiavi che di fabbrica valgono `null`: niente con cui confrontare.
  /// I numeri sono numeri, interi o no: un cursore manda 960.5 dove la
  /// fabbrica dice 960. Una lista di fabbrica fatta di nomi vuole nomi; una
  /// lista vuota di fabbrica non dice cosa conterrà, e si accetta.
  static bool _conforme(String percorso, dynamic fabbrica, dynamic valore) {
    final intervallo = _intervalli[percorso];
    if (intervallo != null) {
      return valore is num &&
          valore.isFinite &&
          valore >= intervallo[0] &&
          valore <= intervallo[1];
    }
    if (fabbrica == null) return true;
    if (fabbrica is Map) {
      if (valore is! Map) return false;
      if (fabbrica.isEmpty) return true; // mappa libera
      for (final e in valore.entries) {
        final chiave = e.key;
        if (chiave is! String || !fabbrica.containsKey(chiave)) return false;
        if (!_conforme('$percorso.$chiave', fabbrica[chiave], e.value)) {
          return false;
        }
      }
      return true;
    }
    if (fabbrica is num) return valore is num && valore.isFinite;
    if (fabbrica is bool) return valore is bool;
    if (fabbrica is String) return valore is String;
    if (fabbrica is List) {
      if (valore is! List) return false;
      if (fabbrica.isNotEmpty && fabbrica.every((x) => x is String)) {
        return valore.every((x) => x is String);
      }
      return true;
    }
    return true;
  }

  /// Le manopole degli effetti che hanno un intervallo, oltre al tipo.
  static const _intervalli = <String, List<double>>{
    'windows.rigidita': [0.5, 2],
    'windows.smorzamento': [0.15, 0.95], 'windows.elastico': [0, 3],
    'windows.elasticoUltimo': [0.1, 3], 'windows.effettoOpacita': [0.5, 1],
  };

  static bool _esisteDiFabbrica(List<String> segments) {
    dynamic nodo = _fabbrica;
    for (var i = 0; i < segments.length; i++) {
      if (nodo is! Map) return false;
      if (nodo.isEmpty) return true; // mappa libera: sotto ci va di tutto
      if (!nodo.containsKey(segments[i])) return false;
      nodo = nodo[segments[i]];
    }
    return true;
  }

  /// Ripristina tutte le impostazioni ai valori di fabbrica.
  Future<void> resetToDefaults() async {
    await _transazione(() { _settings = defaultSettings(); }, 'Impostazioni ripristinate ai valori predefiniti');
  }

  /// I salvataggi si mettono in fila, uno alla volta.
  ///
  /// ── Perché serve una fila ──────────────────────────────────────────────
  ///
  /// Il server IPC non aspetta la fine di un messaggio prima di consegnare il
  /// successivo: `socket.listen` chiama un gestore `async` e tira dritto.
  /// Trascinare un cursore nelle Impostazioni manda quindi diversi
  /// `set_setting` che si accavallano, e ognuno faceva un
  /// `writeAsString` sullo STESSO file: due scritture aperte insieme, ognuna
  /// delle quali tronca il file prima di riempirlo. Il risultato possibile è
  /// un `settings.json` mezzo scritto — cioè illeggibile, cioè tutte le tue
  /// scelte perse al riavvio successivo, con la sola traccia di una riga di
  /// registro che nessuno legge in tempo.
  ///
  /// Non è un caso di laboratorio: è quello che succede muovendo un cursore.
  Future<void> _coda = Future.value();

  Future<T> _transazione<T>(T Function() modifica, String logMessage) {
    return _inCoda(() async {
      await _stopWatcher();
      // ── Chi ha cambiato il file da fuori, prima di noi ───────────────
      //
      // Un editor di testo salva `settings.json`, e un istante dopo — prima
      // che la sorveglianza se ne accorga — un cursore delle Impostazioni
      // manda `set_setting`. Fino al 30 settembre 2026 questo salvataggio
      // partiva dalle impostazioni in memoria, quelle di PRIMA, e scriveva
      // sopra la modifica appena fatta: persa, senza traccia. Il file è di
      // pochi chilobyte: rileggerlo costa meno di perdere una scelta.
      try {
        final suDisco = await File(_configPath).readAsString();
        if (_testoNoto != null && suDisco != _testoNoto) await _ricarica();
      } catch (_) {
        // Illeggibile o sparito: si parte da quello che c'è in memoria, e il
        // salvataggio lo rimette a posto.
      }
      final prima = _settings;
      try {
        _settings = jsonDecode(jsonEncode(prima)) as Map<String, dynamic>;
        final risultato = modifica();
        final candidata = _settings;
        _settings = prima;
        if (jsonEncode(candidata) == jsonEncode(prima)) return risultato;
        await _write(candidata);
        _settings = candidata;
        print('[MINERVA][CORE][INFO] $logMessage.');
        _notifyChanged();
        return risultato;
      } catch (_) {
        _settings = prima;
        rethrow;
      } finally {
        _startWatcher();
      }
    });
  }

  /// Mette un lavoro in fila dopo gli altri: i salvataggi e i ricaricamenti
  /// dal disco toccano tutti `_settings`, e uno alla volta.
  Future<T> _inCoda<T>(Future<T> Function() lavoro) {
    final mia = _coda.then((_) => lavoro());
    // La coda non deve interrompersi se un salvataggio va male: chi viene dopo
    // ha comunque diritto a provarci.
    _coda = mia.then<void>((_) {}, onError: (Object e, StackTrace s) {});
    return mia;
  }

  /// Scrive di fianco e poi sposta.
  ///
  /// `writeAsString` tronca il file e poi lo riempie: fra le due cose il file
  /// esiste ed è vuoto. Se il computer si spegne lì — o se il processo muore,
  /// o se il disco è pieno a metà — al riavvio successivo non ci sono più le
  /// impostazioni, e Minerva riparte coi valori di fabbrica fingendo siano i
  /// tuoi. Uno spostamento sullo stesso filesystem invece è atomico: o c'è il
  /// file di prima, o c'è quello nuovo, mai un terzo caso.
  Future<void> _write([Map<String, dynamic>? valori]) async {
    const encoder = JsonEncoder.withIndent('  ');
    final finale = File(_configPath);
    final provvisorio = File('$_configPath.nuovo');
    final testo = '${encoder.convert(valori ?? _settings)}\n';
    await provvisorio.writeAsString(testo, flush: true);
    await provvisorio.rename(finale.path);
    _testoNoto = testo;
  }


  /// Toglie dalle impostazioni le chiavi che i valori di fabbrica non conoscono.
  /// Restituisce true se ha tolto qualcosa.
  ///
  /// ── Perché serve, visto che ormai si rifiutano ─────────────────────────
  ///
  /// Perché il rifiuto vale da oggi in avanti. Le chiavi scritte PRIMA — da
  /// una versione precedente, da uno script di prova, da me durante una prova —
  /// restano lì per sempre: `_fillMissingDefaults` sa solo aggiungere.
  ///
  /// Nel `settings.json` di Giacomo, l'8 settembre 2026, ce n'erano sette:
  /// `animations.enabled`, `bar.opacity`, `launcher.defaultView`,
  /// `launcher.maxShown`, `plugins.enabled`, `windows.blur`,
  /// `windows.compositorBars` — resti dell'era di Hyprland e degli
  /// script di prova di allora, che le scrivevano quando il demone accettava
  /// qualunque cosa. Nessuna letta da nessuno.
  ///
  /// Non facevano danni, ed è proprio per questo che restavano. Ma un file di
  /// impostazioni che elenca manopole che non comandano niente dice il falso su
  /// cosa fa Minerva, a chi lo legge e a chi ci scrive sopra un domani.
  ///
  /// ── E le mappe libere, che NON si toccano ──────────────────────────────
  ///
  /// Una mappa dichiarata vuota di fabbrica vuol dire «qui le chiavi le mette
  /// l'utente»: le posizioni delle icone sulla scrivania, i colori scavalcati.
  /// Potare quelle vorrebbe dire cancellare la disposizione della scrivania a
  /// ogni avvio — la cura peggiore del male. `_esisteDiFabbrica` lo sa già, e
  /// si passa da lì invece di rifare il ragionamento.
  bool _potaSconosciute() {
    final tolte = <String>[];

    void gira(Map<String, dynamic> nodo, List<String> dove) {
      for (final chiave in nodo.keys.toList()) {
        final percorso = [...dove, chiave];
        if (!_esisteDiFabbrica(percorso)) {
          nodo.remove(chiave);
          tolte.add(percorso.join('.'));
          continue;
        }
        final valore = nodo[chiave];
        // Sotto una mappa libera non si scende: là dentro comanda l'utente.
        final diFabbrica = _fabbricaA(percorso);
        if (valore is Map<String, dynamic> &&
            !(diFabbrica is Map && diFabbrica.isEmpty)) {
          gira(valore, percorso);
        }
      }
    }

    gira(_settings, const []);
    if (tolte.isNotEmpty) {
      print('[MINERVA][CORE][INFO] Tolte ${tolte.length} impostazioni che non '
          'esistono più: ${tolte.join(", ")}');
    }
    return tolte.isNotEmpty;
  }

  /// Il nodo dei valori di fabbrica a quel percorso, o `null` se non c'è.
  static dynamic _fabbricaA(List<String> segments) {
    dynamic nodo = _fabbrica;
    for (final s in segments) {
      if (nodo is! Map || !nodo.containsKey(s)) return null;
      nodo = nodo[s];
    }
    return nodo;
  }

  /// Aggiunge ricorsivamente le chiavi predefinite assenti.
  /// Restituisce true se qualcosa è stato aggiunto.
  bool _fillMissingDefaults() {
    var changed = false;

    // ── E ripara i tipi sbagliati ────────────────────────────────────────
    //
    // «C'è» non bastava: un `shell` che vale 7 c'è, e restava 7 a ogni avvio
    // (30 settembre 2026). Un valore che non ha la forma di quello di
    // fabbrica torna di fabbrica, e lo si dice: una scelta persa si vede nel
    // registro, un menù che non si apre più no.
    void merge(Map<String, dynamic> target, Map<String, dynamic> defaults,
        String dove) {
      for (final entry in defaults.entries) {
        final percorso = dove.isEmpty ? entry.key : '$dove.${entry.key}';
        final existing = target[entry.key];
        final diFabbrica = entry.value;
        if (!target.containsKey(entry.key)) {
          target[entry.key] = diFabbrica;
          changed = true;
        } else if (existing is Map<String, dynamic> &&
            diFabbrica is Map<String, dynamic> &&
            diFabbrica.isNotEmpty) {
          merge(existing, diFabbrica, percorso);
        } else if (!_conforme(percorso, diFabbrica, existing)) {
          print('[MINERVA][CORE][WARN] Impostazione "$percorso" col tipo '
              'sbagliato (${jsonEncode(existing)}): torna quella di fabbrica.');
          target[entry.key] = diFabbrica;
          changed = true;
        }
      }
    }

    merge(_settings, defaultSettings(), '');
    return changed;
  }

  /// Valori di fabbrica. Ogni opzione esposta nel pannello Impostazioni
  /// deve avere qui il suo default.
  static Map<String, dynamic> defaultSettings() => {
        // ── L'aspetto di tutta Minerva ────────────────────────────────
        //
        // Un tema è una TINTA e un VERSO (chiaro o scuro). La tavolozza vera
        // sta in `minerva-shell/theme/Colors.qml`, che è l'unico posto in cui
        // si sceglie un colore; qui sta solo il nome di quello in uso.
        //
        // `schemiChiari` non è un'impostazione: è ciò che il demone deve
        // sapere per scegliere la variante giusta del tema di icone (le icone
        // «-Dark» sono chiare, fatte per stare su fondo scuro). Se qualcuno
        // aggiunge un tema in Colors.qml e si dimentica di questo elenco, se
        // ne accorge una prova — `test/schemi_test.dart`.
        'shell': {
          // ── Qui c'era `clock24`, e non la scriveva nessuno ────────────
          //
          // La leggeva la sola schermata di blocco. Nelle Impostazioni → Data
          // e ora la scelta fra dodici e ventiquattro ore scrive
          // `clock.format24` (la barra) e `greeter.clock24` (l'accesso): si
          // metteva l'orologio a dodici ore e la schermata di blocco restava a
          // ventiquattro, per sempre, senza che nulla lo dicesse.
          //
          // Tolta il 9 settembre 2026: adesso il blocco legge `clock.format24`
          // come la barra. Una terza chiave per la stessa domanda non è una
          // scelta in più — è un posto in cui la risposta può divergere.
          //
          // `greeter.clock24` invece resta e ha ragione di restare: la
          // schermata di ACCESSO gira prima che ci sia un utente, e le
          // preferenze di chi non ha ancora fatto l'accesso non si possono
          // leggere.
          // Ricarica a caldo dei QML: solo per chi sviluppa Minerva.
          'hotReload': false,
          'scheme': 'notte',
          'accent': '#22D3EE',
          // ── Il settimo tema ────────────────────────────────────────────
          //
          // Con `scheme` a 'personale' la tinta e il verso li scegli tu, e
          // tutto il resto continua a derivare da quei due come per gli altri
          // sei. Il verso non si indovina dalla tinta: un grigio medio può
          // stare bene in tutti e due i modi, e chi sceglie sa quale vuole.
          'tintaPersonale': '#101018',
          'versoPersonale': true,
          // ── E i colori messi a mano, uno per uno ───────────────────────
          //
          // Nomi ammessi: base, testo, membrana, bordo, positivo, avviso,
          // pericolo — l'elenco vero sta in `theme/Colors.qml`
          // (`scavalcabili`), che è l'unico posto in cui si sceglie un colore.
          //
          // Vuoto vuol dire «lascia derivare», ed è il ripiego: un colore
          // scritto qui vince sul conto che lo avrebbe calcolato, e quel conto
          // era MISURATO. Le Impostazioni mostrano il contrasto mentre si
          // sceglie, e avvisano sotto 4,5 senza impedire niente.
          'scavalca': <String, dynamic>{},
          'membraneOpacity': 0.93,
          // ── E la stessa cosa col filtro vero, che è un mestiere diverso ──
          //
          // (Le chiavi si chiamano ancora `…Blur`: sono nate col blur, e
          // rinominarle farebbe perdere a chi le ha già regolate il suo
          // numero. Oggi valgono con l'acquerello, l'unico filtro rimasto.)
          //
          // Due numeri e non uno, perché la domanda «quanto è coprente la
          // barra» ha due risposte giuste secondo cosa c'è dietro.
          //
          // Senza blur dietro c'è una fotografia NITIDA, e sotto 0,75 il testo
          // ci si perde: è la soglia misurata, ed è dove si ferma il cursore.
          // Col blur del compositore dietro c'è una macchia morbida e un po'
          // scurita, che non ruba leggibilità a niente — e lì 0,93 vuol dire
          // non vedere la sfocatura per cui si è pagato un passaggio di
          // disegno. Misurato il 9 settembre 2026: fra `vetro` e `blur`, nella
          // fascia della barra non cambiava NEMMENO UN PIXEL.
          //
          // Un numero solo obbligherebbe a scegliere quale delle due
          // situazioni servire, e a rigirare il cursore ogni volta che si
          // cambia effetto. Due numeri sono due memorie: ognuno si ricorda
          // com'era.
          'membraneOpacityBlur': 0.68,
          'windowOpacity': 0.88,
          // ── Il tasto che riavvia la scrivania ──────────────────────────
          //
          // Giacomo, 2 settembre 2026: «mettiamo un tasto disattivabile
          // accanto al meteo dove posso riavviare la shell».
          //
          // Acceso di suo: chi sta costruendo Minerva la ricarica dieci volte
          // al giorno, e la scorciatoia da sola si dimentica. Chi non lo vuole
          // lo spegne in Impostazioni → Aspetto, e la barra torna com'era.
          //
          // Ricarica, non riavvia: la shell si rilegge restando viva, quindi
          // barra e pannelli non spariscono. È la stessa cosa che fa
          // `minerva-reload.sh` senza argomenti.
          'tastoRiavvio': true,
        },
        'general': {
          // Lingua dell'interfaccia: 'auto' segue la lingua di sistema.
          'language': 'auto',
          // Modalità principiante: suggerimenti visibili e conferme in più.
          'beginnerMode': true,
        },
        'cheatsheet': {
          // Il pannello «Scorciatoie» è attivabile da qui.
          'enabled': true,
          // Opacità dello sfondo semitrasparente (0 = invisibile, 1 = pieno).
          'backgroundOpacity': 0.55,
          // Mostra il pannello automaticamente al primo avvio della sessione.
          'showOnFirstRun': true,
        },
        // ── La finestra delle Impostazioni ────────────────────────────
        //
        // `lastSection`: dove si era rimasti. `scripts/minerva-settings` lo
        // prometteva nella sua riga d'aiuto molto prima che esistesse, e la
        // finestra si riapriva sempre su «Aspetto».
        'settings': {
          'lastSection': 'appearance',
        },
        // ── La riva: che cosa esce da quale bordo ─────────────────────────
        //
        // «I bordi vivi: banchina in basso, stanze a sinistra, Cassetto a
        // destra; si scambiano posto trascinandoli». `cassetto` dice da che
        // parte esce il Cassetto (gli appunti); le Stanze escono dall'altra.
        // Lo cambia il trascinamento di uno dei due verso l'altro bordo.
        'riva': {
          'cassetto': 'destra',
          // Il carattere della molla di tutta la riva: 'calma', 'liquida',
          // 'viva' (vedi `minerva-shell/theme/Motion.qml`).
          'molla': 'liquida',
          // Con una finestra che riempie lo schermo, angoli e bordi solo con
          // Super giù (e Super tenuto fa salire la riva). Falso: sempre.
          'consenso': true,
          // Che cosa fa ogni angolo: 'menu', 'centro', 'scrivania',
          // 'stanze', 'isola', 'appunti', 'niente' (`core/Riva.qml`).
          'angoli': {
            'altoSx': 'niente',
            'altoDx': 'centro',
            'bassoSx': 'menu',
            'bassoDx': 'scrivania',
          },
        },
        // Che cosa mostra l'Isola, pezzo per pezzo.
        'isola': {
          'mostra': {
            'data': true,
            'meteo': true,
            'musica': true,
            'vassoio': true,
            'stato': true,
          },
        },
        // Il Centro di controllo (in alto a destra): quali riquadri e in che
        // ordine. Si cambia dal Centro stesso, con «Personalizza». I nomi
        // sono quelli del catalogo in `minerva-shell/menu/Centro.qml`; uno
        // che non conosce si salta.
        'centro': {
          'voci': [
            'wifi',
            'bluetooth',
            'notte',
            'nondisturbare',
            'risparmio',
            'gioco',
            'trasmetti',
            'impostazioni',
          ],
        },
        'launcher': {
          // Qui c'era `'maxShown': 7` — quante voci mostrare nel menu — e
          // non la leggeva nessuno: zero occorrenze in tutto il progetto. Il
          // pannello delle applicazioni le mostra tutte, e scorre. Tolta il
          // 5 settembre 2026: una manopola che non fa niente insegna a non
          // fidarsi delle altre.
          // ── Il menu delle applicazioni ────────────────────────────────
          //
          // `wheelCategories`: la rotellina passa da una categoria all'altra.
          // `hiddenCategories`: quelle che non si vogliono vedere (Preferiti e
          //   Tutte non si possono togliere: sono le vie d'uscita).
          // `startCategory`: con quale si apre.
          'wheelCategories': true,
          'hoverCategories': true,
          // Il Sottomarino (`menu/Sottomarino.qml`): la vista con cui si apre
          // («categorie», «attivita», «frequenti», «az») e il verso.
          'vista': 'categorie',
          'verticale': false,
          // Le misure che si scelgono trascinando i bordi del menù: una per
          // verso, perché un menù largo e basso e uno stretto e alto sono due
          // scelte diverse.
          'orizzontaleLarghezza': 960,
          'orizzontaleAltezza': 430,
          'verticaleLarghezza': 420,
          'hiddenCategories': <String>[],
          'startCategory': 'favorites',
          // Il nostro, dal 15 settembre 2026. Chi ne vuole un altro lo sceglie
          // in Impostazioni → Applicazioni predefinite; Alacritty resta
          // installato finché il Terminale di Minerva non ha passato la prova
          // approfondita (tappa 5 del piano).
          'defaultTerminal': 'minerva-terminale',
          // Le app in cima al menu appena installato.
          //
          // C'erano `org.kde.dolphin`, `org.kde.kate` e `systemsettings`: i
          // programmi di KDE, su un ambiente che di KDE non vuole dipendere.
          // Su un computer senza KDE quelle voci sono tre riquadri vuoti che
          // non aprono niente — e il gestore file e le Impostazioni Minerva ce
          // li ha suoi.
          'fixedApps': [
            'firefox.desktop',
            'minerva-files.desktop',
            'minerva-terminale.desktop',
            'minerva-settings.desktop',
          ],
          // Qui c'era `'defaultView': 'menu'`, con scritto accanto che
          // `'matrix'` avrebbe dato «cerchi concentrici». Quei cerchi non
          // esistono, e la chiave non la leggeva nessuno: era la descrizione
          // di una funzione mai scritta, in un file che si legge come se
          // dicesse la verità. Tolta il 5 settembre 2026.
        },
        'bar': {
          // ── Da che parte sta la barra ──────────────────────────────────
          //
          // 'alto' o 'basso'. Era dichiarata qui dal primo giorno e non la
          // leggeva nessuno: una impostazione che esiste, si può scrivere, e
          // non fa niente — il tipo di bugia che nessun errore segnala.
          //
          // I lati non ci sono, e non per dimenticanza: barra e dock sono
          // costruite in orizzontale — la lingua scende, le icone crescono
          // verso l'interno — e metterle di fianco non è un ancoraggio
          // diverso, è un'altra geometria. Quando si farà, sarà una voce in
          // più qui e un lavoro a sé.
          //
          // `top` e `bottom` continuano a valere: chi ha un file scritto
          // prima non deve accorgersi di niente.
          //
          // ⚠ Questa e `dock.position` non sono indipendenti: dal 5 settembre
          // 2026 barra e dock **non possono stare dallo stesso bordo**. Se qui
          // dentro finiscono uguali — scrivendo il file a mano, per esempio —
          // vince la dock e la barra va dall'altra parte. La regola sta in
          // `minerva-shell/core/Posizioni.qml`, che è il solo posto da cui
          // passano tutti quelli che hanno un verso.
          'position': 'alto',
          // 'isola' o 'classica'. L'Isola è la barra della Riva: una capsula
          // che galleggia in mezzo (`minerva-shell/menu/IsolaBarra.qml`). La
          // classica è la barra di Minerva, a tutta larghezza, che resta
          // come scelta.
          'stile': 'isola',
          // Come sta l'Isola: 'sempre' (riserva la fascia), 'elude' (c'è
          // finché nessuna finestra le arriva sotto) o 'nascondi' (oltre il
          // bordo, torna con una sosta del puntatore lassù). Giacomo, 30
          // settembre 2026: «servirebbe avere l'isola dove si trova l'ora in
          // modalità eludi finestre perché quando sono sul desktop per vedere
          // l'ora devo sempre salire su e farla comparire». Gli stessi tre
          // modi della dock (`dock.modo`).
          'modoIsola': 'elude',
          // Il valore di prima (25 settembre, «così recuperiamo spazio»): si
          // legge ancora solo per chi l'aveva SPENTO, che ritrova l'Isola
          // sempre su. Vedi `modoIsola` in `minerva-shell/shell.qml`.
          'aScomparsa': true,
          // Qui c'era `'opacity': 0.10`. Tolta il 5 settembre 2026: non la
          // leggeva NESSUNO — zero occorrenze in tutto il progetto — e la
          // trasparenza della barra ce l'ha già `shell.membraneOpacity`, che
          // funziona ed è esposta nelle Impostazioni. Due manopole per lo
          // stesso valore sono peggio di una: una delle due mente sempre.
          'showAppMenuButton': true,
          // Le finestre aperte in fila nella barra, una voce per finestra.
          // Spenta di suo: con la dock accesa sarebbe la stessa cosa detta
          // due volte. La accende lo stile «Windows», dove la dock non c'è.
          'listaFinestre': false,
          // ── I valori di sistema nella barra ──────────────────────────
          //
          // Giacomo, 9 settembre 2026: «dei widget sia sulla barra». Gli
          // stessi tipi della scrivania (`desktop.widgets`), ma qui basta il
          // nome: sulla barra non c'è niente da posizionare né da
          // ridimensionare, c'è solo l'ordine.
          //
          //     ['processore', 'memoria']
          //
          // Vuota di serie, e non è prudenza: la barra c'è sempre, quindi un
          // widget qui tiene acceso il campionamento del demone per tutta la
          // sessione — cinque secondi, quattro file. Chi lo vuole lo accende
          // sapendolo; a chi non lo vuole non costa niente.
          'widgets': <String>[],
        },
        'windows': {
          // ── Qui c'era `gap`, e non arrivava da nessuna parte ──────────
          //
          // I margini valevano solo per le finestre AFFIANCATE. Hyprland non
          // c'è più dal 2 settembre 2026, il nostro compositore risponde
          // «margini non ha una strada» e lo scrive nel registro a ogni
          // avvio: restava una manopola che si poteva scrivere e che non
          // cambiava un pixel.
          //
          // Trovata dal banco delle manopole il 9 settembre 2026:
          // «windows.gap 1 → 3, non muove, 0,000 %». Tolta.
          //
          // Lo spazio sopra una finestra libera lo mette `abbassa()` in
          // `spine/TitleBars.qml`, che è dove è sempre stato per davvero.
          // ── L'effetto sulle finestre: nessuno, vetro, acquerello ───────
          //
          // Qui c'era `'blur': 2`, un numero da 0 a 3 che sceglieva quanta
          // sfocatura chiedere a Hyprland. Sotto minerva-wayland **non faceva
          // niente**: `Compositore.sfocatura()` era un buco che scriveva una
          // riga e basta. Un'impostazione che si vede, si cambia, e non cambia
          // nulla è il difetto che questo progetto si è messo per iscritto di
          // non commettere — e stava nel nostro pannello.
          //
          // Giacomo, 2 settembre 2026: «ci vorrebbero delle impostazioni per
          // mettere nessun effetto o blur o vetro e queste impostazioni si
          // dovrebbero applicare alle finestre e in blur o vetro dovrebbero
          // far vedere un solo corpo trasparente [...] la barra e la finestra
          // senza stacchi».
          //
          //   'nessuno'  finestre opache, come nascono
          //   'vetro'    una sola trasparenza su tutta la finestra, barra
          //              compresa: il compositore la applica all'albero intero
          //              e la barra si disegna opaca per non moltiplicarla
          //   'acquerello' come il vetro, e dietro il COLORE di quello che
          //              c'è, cella per cella, steso morbido: niente forme
          //              dietro il testo
          //
          // C'era anche 'blur' (dietro sfocato): tolto il 28 settembre 2026,
          // visto l'acquerello — «a questo punto il blur lo eliminerei». Chi
          // l'aveva nel file passa all'acquerello al caricamento.
          //
          // Nasceva 'nessuno' («una scrivania che parte con le finestre
          // trasparenti prima che qualcuno l'abbia chiesto sembra rotta»).
          // Dal 27 settembre 2026 nasce 'acquerello': è il materiale di
          // Liquid, e Giacomo, vedendolo: «Lo adotterei per tutto». Non è una
          // trasparenza qualunque — dietro il testo non passano forme, solo
          // colore — e costa zero a scrivania ferma.
          'effetto': 'acquerello',
          // Quanto è opaca una finestra col vetro acceso. Stesso numero che le
          // finestre di Minerva usavano già per conto loro
          // (`shell.windowOpacity`): partire da un valore diverso vorrebbe
          // dire che accendendo il vetro le nostre cambiano e le altre no.
          'effettoOpacita': 0.88,
          // Mercurio: le finestre vicine si fondono come gocce, e si staccano
          // allontanandole. Acceso di serie: è il secondo materiale di Liquid,
          // e a scrivania ferma non costa niente (lo disegna il compositore
          // solo fra finestre a meno di 48 pixel, e solo quando si muovono).
          'mercurio': true,
          // ── La cornice attorno alla finestra attiva ────────────────────
          //
          // 'spento', 'fisso' o 'gira'. Non è una decorazione in più: c'era
          // già, ed era trasparente — è l'anello di sei pixel con cui si
          // prende una finestra per ridimensionarla.
          //
          // 'gira' è la striscia LED che Giacomo ha chiesto il 3 settembre
          // 2026. La anima il compositore, dodici passi al secondo, e SOLO
          // sulla finestra attiva: un arcobaleno attorno a otto finestre
          // insieme non è un effetto, è una fiera.
          //
          // Nasce spenta. Un effetto che si muove tutto il giorno è una cosa
          // che si sceglie, non che si subisce — e su un portatile è anche
          // batteria.
          'cornice': 'spento',
          // ── Il bordo colorato: spessore, colori, finestre spente ───────
          //
          // Giacomo, 9 settembre 2026: «voglio poter regolare lo spessore del
          // colore intorno alla finestra attiva [...] e vorrei anche
          // l'effetto rgb come una strip led e possibilità di scegliere i
          // colori che si alterneranno».
          //
          // Sei pixel è la misura con cui la cornice è nata, ed era legata a
          // quella della presa per ridimensionare: adesso sono due numeri.
          'corniceSpessore': 6,
          // Vuoto vuol dire lo SPETTRO intero, che è l'arcobaleno di sempre.
          // Da un colore in su, il giro passa per quelli e per nessun altro.
          'corniceTinte': <String>[],
          // Zero: la cornice si accende solo sulla finestra attiva, che è la
          // ragione per cui esiste — dire quale risponde alla tastiera. Da
          // zero in su diventa il contorno di tutte, ed è un'altra cosa.
          'corniceSpente': 0.0,
          // Millisecondi per un giro intero dello spettro. Il compositore
          // rifiuta sotto i 2000: più veloce non è un colore che gira, è un
          // lampeggio davanti agli occhi.
          'cornicePeriodo': 8000,
          // ── Quanto tremano le finestre ──────────────────────────────
          //
          // Giacomo, 10 settembre 2026: «voglio le finestre tremolanti».
          //
          // Zero spento, uno normale, tre il massimo. Trascinando, la
          // finestra resta un po' indietro rispetto al dito; al rilascio
          // raggiunge la posizione, la supera di poco e si posa.
          //
          // Spento di serie, come l'effetto vetro e per la stessa ragione:
          // una scrivania che parte con le finestre che rimbalzano prima che
          // qualcuno l'abbia chiesto ha deciso al posto tuo.
          //
          // La deformazione è disegnata dal compositore in wobbly.c.
          // L'ultima elasticità si conserva anche spegnendo l'effetto.
          'elastico': 0.0,
          'elasticoUltimo': 1.0,
          'rigidita': 1.0,
          'smorzamento': 0.42,
          // Che fa la barra a schermo intero: 'hover' compare avvicinandosi.
          'fullscreenBar': 'hover',
          'titleHeight': 34,
          // ── Chi disegna la barra del titolo ─────────────────────────────
          //
          // `false` (come nasce): la disegna la shell, su una superficie
          // appoggiata sopra le finestre. `true`: la disegna il compositore,
          // col plugin `plugins/minerva-bars` — una decorazione vera, che si
          // muove con la finestra e non copre chi le sta davanti.
          //
          // Da che parte stanno riduci/ingrandisci/schermo intero/chiudi:
          // 'destra' come su Windows, 'sinistra' come su macOS.
          'buttonsSide': 'destra',
          // ── I programmi che la barra se la disegnano da soli ─────────────
          //
          // Il compositore disegna la barra del titolo a ogni finestra. I
          // browser e parecchie applicazioni GNOME però se la disegnano da
          // soli: su quelle la nostra sarebbe la seconda — due titoli, due
          // file di pulsanti, e trenta pixel di spazio buttati. L'elenco lo
          // manda la shell al compositore (`Compositore.appConBarraPropria`).
          //
          // Qui stanno le classi da lasciar stare. Si confronta la classe
          // della finestra in minuscolo: basta che la contenga.
          //
          // Chi preferisce la barra di Minerva anche su Firefox può dire a
          // Firefox di usare quella di sistema (Personalizza → «Barra del
          // titolo») e togliere la voce da questo elenco.
          'csdApps': [
            'firefox',
            'chromium',
            'google-chrome',
            'brave-browser',
            'microsoft-edge',
            'thunderbird',
            // Gli editor derivati da VS Code (Antigravity, Code, Cursor,
            // Windsurf) accendono di serie la loro barra del titolo: su Linux
            // `window.titleBarStyle` vale «custom». Nessuno di questi lo
            // dichiara al compositore, e non c'è modo di chiederglielo: si
            // vede soltanto, ed è il motivo per cui questo elenco è a mano.
            'antigravity',
            'org.gnome.',
            'nautilus',
            'gnome-',
          ],
        },
        // ── Il gestore file ────────────────────────────────────────────
        //
        // Poche, e tutte cose che cambiano come ci si comporta, non come si
        // vede: le scelte di aspetto stanno nella finestra dove si vedono
        // (vista, ordine, zoom), qui stanno quelle che valgono per tutte le
        // cartelle e per tutte le finestre.
        'files': {
          'view': 'list',
          'zoom': 1,
          'sort': 'name',
          'sortDesc': false,
          'pinned': <String>[],
          // Dove sta ogni icona sulla scrivania, per nome.
          'desktopPositions': <String, dynamic>{},
          // Le cartelle che il sistema conosce — Musica, Documenti, Immagini —
          // prendono da sole uno sfondo a motivo: note sparse su Musica, fogli
          // su Documenti. Si riconoscono prima di leggerne il nome.
          'sfondiAutomatici': true,
          // Un clic solo apre, invece di due. Chi viene da GNOME lo cerca
          // subito; chi viene da Windows lo trova insopportabile. Spento.
          'clicSingolo': false,
          // Le miniature delle immagini. Si spengono su cartelle enormi di
          // foto su un disco lento, dove ogni miniatura è una lettura.
          'anteprime': true,
          // La domanda prima di cestinare. Si può togliere perché il cestino
          // È la rete: chiedere due volte per un'azione già reversibile è
          // il tipo di attrito che fa smettere di leggere le domande.
          'confermaCestino': true,
          // I file nascosti (il punto in testa al nome). Da ricordare fra
          // una sessione e l'altra: chi li accende una volta non li rivuole
          // nascosti al prossimo avvio.
          'showHidden': false,
          // ── Tenerlo pronto ────────────────────────────────────────────
          //
          // Il gestore file si avvia all'accesso e resta acceso senza
          // finestra, così la prima cartella che si apre compare subito
          // invece che dopo circa 800 ms.
          //
          // Non è gratis e il numero va detto. Rimisurato il 18 agosto
          // 2026 sulla macchina vera, dopo il passaggio al disegno col
          // processore: 84 MB di memoria privata da dormiente. Con la
          // scheda video erano 116.
          // Acceso di serie perché l'attesa la paga ogni volta chi usa il
          // computer, mentre la memoria la paga solo chi ne ha poca — e
          // quello la spegne qui.
          //
          // Chiudendo la finestra con questo spento il programma esce
          // davvero: vedi `onRequestClose` in `minerva-shell/filemanager.qml`.
          'tieniAcceso': true,
        },
        // ── L'editor di testi ──────────────────────────────────────────
        //
        // Come si scrive, non cosa: il carattere, il peso, i colori. Ogni
        // documento aperto nasce con queste scelte, e chi le cambia le
        // ritrova alla prossima finestra.
        // ── Il Terminale ──────────────────────────────────────────────
        //
        // 15 settembre 2026. Le manopole stanno nell'app, come per l'editor;
        // qui i valori di fabbrica. Il carattere vuoto vuol dire «quello
        // monospazio del tema».
        'terminale': {
          'carattere': '',
          'corpo': 14,
          // «minerva» segue il tema; «classica» e «solarizzata» sono fisse.
          'tavolozza': 'minerva',
          // 0 blocco · 1 sottolineatura · 2 barra. Il programma può
          // cambiarla (DECSCUSR); questa è quella di partenza.
          'cursore': 0,
          'scrollback': 10000,
          // Il campanello: un suono, o niente.
          'campanello': true,
        },
        'editor': {
          // La famiglia del carattere. Vuota vuol dire «il monospazio del
          // tema»: per scrivere si parte da lì.
          'font': '',
          'size': 14,
          'bold': false,
          'italic': false,
          // Il colore del testo. L'accento di Minerva come partenza, che è
          // il colore di tutto il resto.
          'colore': '',
          // Fondo scuro o chiaro: sul chiaro il colore del testo scuro si
          // regge meglio, e viceversa.
          'fondoScuro': true,
          // L'a-capo automatico. Spento: con l'a-capo acceso i numeri di riga
          // non corrispondono più a niente, ed erano proprio quelli a mancare.
          'piega': false,
        },
        'icons': {
          // Come sono disegnate le icone dell'interfaccia.
          //
          //  'minerva'  — i tracciati disegnati da noi (Icon.qml)
          //  'classiche'— le icone del tema installato, con i loro colori
          //  'tinta'    — le icone del tema, ricolorate nella nostra tinta
          //
          // Le nostre restano il valore di serie perché sono le uniche che
          // non possono mancare: un tema di icone incompleto lascia buchi,
          // un tracciato no.
          'style': 'minerva',
          // Quale tema usare. Vuoto = quello scelto nelle impostazioni del
          // sistema, che è già quello che usano i menu delle applicazioni.
          'theme': '',
        },
        'desktop': {
          // Vero dopo il primo uso del menu del tasto destro: serve a non
          // ripetere il suggerimento a chi l'ha già trovato.
          'menuUsed': false,
          // Menu contestuale con il tasto destro sulla scrivania.
          'rightClickMenu': true,
          // Le icone dei file sulla scrivania, come su ogni ambiente
          // classico: si aprono con un doppio clic, si spostano
          // trascinandole e ricordano il loro posto.
          'icons': true,
          // ── Come stanno disposte ────────────────────────────────────
          //
          // Due interruttori e non tre scelte in fila, perché è così che li
          // conosce chi arriva da Windows, da KDE o da GNOME 2: la
          // disposizione automatica vince sull'allineamento, e insieme danno
          // i tre modi che esistono davvero.
          //
          // Automatica SPENTA di fabbrica: decide lei dove va ogni cosa, e
          // una scrivania che rimette le icone dove vuole lei appena ne
          // arriva una nuova è la ragione per cui in tanti la spengono.
          'iconAutoArrange': false,
          // Allineamento ACCESO: è quello che toglie il disordine senza
          // togliere la libertà di mettere le cose dove si vuole.
          'iconSnap': true,
          // Gli stessi nomi del gestore file, e la stessa funzione che
          // ordina: 'name', 'type', 'size', 'modified'.
          // ── I widget della scrivania ──────────────────────────────────
          //
          // Giacomo, 9 settembre 2026: «vorrei avere dei widget sul desktop
          // per vedere i valori di sistema [...] ridimensionabili
          // direttamente da desktop e possono anche essere bloccati e
          // diventare parte dello sfondo».
          //
          // L'elenco è STATO, non una manopola: sono le posizioni in cui li
          // hai trascinati, come `files.desktopPositions`. Le coordinate sono
          // FRAZIONI dello schermo e non pixel — vedi `widget/Telaio.qml`.
          'widgets': <Map<String, dynamic>>[],
          // Bloccati di serie: chi non li ha mai spostati non deve poterseli
          // portare via con un clic per sbaglio. Si sbloccano dal tasto
          // destro sulla barra o dalle Impostazioni.
          'widgetBloccati': true,
          'widgetAccesi': true,
          // La modalità «pulita»: niente icone, niente widget. Per una
          // schermata, o per mostrare la scrivania a qualcuno.
          'puliti': false,
          'iconSort': 'name',
          'iconSortDesc': false,
          // Il lato del disegno dell'icona. La cella della griglia si ricava
          // da qui: un numero solo da regolare, e niente che possa divergere.
          'iconSize': 46,
          // ── Il movimento ────────────────────────────────────────────
          //
          // `animations` vale per TUTTE e due le metà, ed è la correzione del
          // 19 agosto 2026: prima toccava solo il compositore (finestre che si
          // aprono, cambio scrivania) e lasciava correre le animazioni della
          // shell — pannelli, dock, menu — che sono quelle che si notano.
          // Giacomo: «non porta a nessun cambiamento». Vedi
          // `minerva-shell/theme/Motion.qml`.
          'animations': true,
          // Quanto dura il movimento, rispetto al normale: 0,5 = doppio della
          // velocità, 2 = metà. Separata dall'interruttore apposta, così chi
          // spegne e riaccende ritrova la sua e non quella di fabbrica.
          'animationSpeed': 1.0,
          // Qui c'era la scia dietro le finestre (`motionBlur`): era di
          // Hyprland, e sotto il nostro compositore non la applicava nessuno.
          // Tolta il 27 settembre 2026 con la sua levetta.
          // ── Lo sfondo ───────────────────────────────────────────────
          //
          // Erano lette da `sections/Appearance.qml` e da `core/Wallpaper.qml`
          // e non stavano qui: cinque impostazioni che esistevano solo come
          // valore di ripiego scritto nella shell. È la regola che questo
          // file dichiara in cima a sé stesso, e che nessuno faceva
          // rispettare.
          //
          //  'minerva' — i sei sfondi che viaggiano con la shell
          //  'image'   — una immagine scelta
          //  'folder'  — una cartella che gira
          'wallpaperMode': 'minerva',
          // Vuoto vuol dire «quello di Minerva», non «nessuno»: la scrivania
          // non deve mai restare nera per una impostazione mancante.
          'wallpaper': '',
          'wallpaperFolder': '',
          // Ogni quanti minuti cambia. 0 = mai.
          'rotateMinutes': 0,
          'rotateRandom': false,
        },
        // ── Lo schermo, non i monitor ─────────────────────────────────
        //
        // La disposizione dei monitor sta in `schermi.conf`, che legge il
        // compositore: qui sta solo quello che Minerva aggiunge sopra, cioè
        // per ora la luce notturna.
        'display': {
          // Il filtro luce blu. Spento di fabbrica: cambia il colore di TUTTO
          // lo schermo, e una cosa che cambia i colori senza che nessuno
          // l'abbia chiesta sembra un guasto del monitor.
          'nightLight': false,
          // Gradi Kelvin. 6500 è la luce del giorno e non tocca niente; 3800
          // è una sera tranquilla; sotto i 3000 si comincia a non distinguere
          // bene i colori, e chi guarda foto se ne accorge.
          'nightLightTemp': 3800,
          // Accendersi e spegnersi da sola all'ora scelta.
          'nightLightAuto': false,
          'nightLightFrom': 21,
          'nightLightTo': 7,
        },
        // ── Come si DISEGNA l'ora, non che ora è ──────────────────────
        //
        // Il fuso e la sincronizzazione appartengono al sistema e li tiene
        // `timedatectl`: metterne una copia qui vorrebbe dire avere due
        // verità che prima o poi divergono. Qui sta solo la forma.
        'clock': {
          // 24 ore. Il default segue l'Europa, che è dove sta chi usa questo
          // computer; si cambia da Impostazioni → Data e ora.
          'format24': true,
        },
        // ── Accessibilità ─────────────────────────────────────────────
        //
        // Tutte e tre sono cose che il compositore o la tipografia DIMENTICANO a
        // ogni avvio: il posto dove ricordarle è qui, e la shell le riapplica
        // appena il demone risponde.
        'accessibility': {
          // Moltiplicatore del testo di tutta Minerva. Il tetto vero è 1.3, e
          // il perché sta scritto in `theme/Typography.qml`.
          'textScale': 1.0,
          // Ingrandimento dello schermo attorno al puntatore. 1 = spento.
          'zoom': 1.0,
          // Dimensione del puntatore. 24 è quella di serie dei temi di
          // puntatori più diffusi.
          'cursorSize': 24,
        },
        // ── Il tempo che fa ───────────────────────────────────────────
        //
        // Spento finché non c'è una località: senza coordinate il demone non
        // chiede niente a nessuno. La località la si cerca per nome dalle
        // Impostazioni, e da lì restano scritte solo le coordinate — al
        // centesimo di grado, cioè il quartiere e non la casa.
        'weather': {
          'enabled': false,
          'name': '',
          'lat': 0.0,
          'lon': 0.0,
        },
        'greeter': {
          'user': '',
          'session': 'minerva',
          'autologin': false,
          'background': 'aurora',
          'wallpaper': '',
          'auroraStrength': 0.55,
          'blur': 48,
          'scrim': 0.42,
          'showClock': true,
          // La schermata di accesso ha una chiave sua perché gira in un
          // ALTRO processo, con un altro demone e un'altra configurazione
          // (vedi `scripts/minerva-greetd`): non può leggere quella sopra.
          // Il pannello «Data e ora» le scrive tutte e due insieme, così non
          // capita di trovare l'ora scritta in due modi diversi passando
          // dalla schermata di accesso alla scrivania.
          'clock24': true,
          // Le cose in più della schermata di accesso (23 settembre 2026):
          // il meteo sotto la data (solo se la sessione ne ha uno acceso),
          // «Buonasera, Giacomo» al posto del nome secco, e batteria e
          // tastiera nell'angolo. Il meteo mostra la città: si spegne qui.
          'meteo': true,
          'saluto': true,
          'stato': true,
          // Da che parte stanno l'ora e l'accesso: «sinistra», «destra» o
          // «centro» (com'era prima). L'altra metà resta libera: nella
          // schermata di blocco lì vanno le notifiche. Vale per tutte e due
          // le schermate, che devono somigliarsi.
          'lato': 'sinistra',
        },
        // ── Il lettore multimediale ───────────────────────────────────
        //
        // Il volume stava SOLO nel cursore, che partiva da 70 mentre
        // l'uscita audio era all'unità: all'avvio il numero sullo schermo e
        // il suono nelle casse dicevano due cose diverse, e spostandolo non
        // se ne ricordava niente al riavvio.
        //
        // `ripeti` ha tre valori perché due non bastano: «tutto» era il
        // comportamento di prima ed era implicito — la scaletta ripartiva da
        // capo alla fine e non c'era modo di dirle di smettere.
        'media': {
          'volume': 70,
          'muto': false,
          // 'no' · 'tutto' · 'uno'
          'ripeti': 'tutto',
          'casuale': false,
          // Quale dei quattro disegni dell'audio: 0 barre, 1 onda,
          // 2 radiale, 3 neon. Si sceglieva a ogni avvio da capo.
          'disegno': 0,
        },
        // ── Lo stile della scrivania ──────────────────────────────────
        //
        // Uno stile non aggiunge manopole: scrive insieme quelle che ci sono
        // già, sparse fra tre pagine. `libero` è la fotografia di com'era
        // prima di sceglierne uno, e viaggia come **testo JSON** perché le
        // chiavi hanno il punto dentro (`bar.position`) e qui il punto vuol
        // dire «scendi di un livello».
        'stile': {
          'attuale': 'libero',
          'libero': '',
        },
        'viewer': {
          // Anteprima: la striscia delle miniature in fondo alla finestra.
          // Accesa di suo — è quella che dice a che punto si è dentro una
          // cartella, e chi guarda una fotografia sola la spegne una volta.
          'filmstrip': true,
        },
        // Qui c'era `'plugins': {'enabled': ['weather', 'system_stats']}`.
        // Due nomi di moduli che non esistono, in una chiave che NESSUNO
        // legge: `PluginManager` decide se avviare un modulo dal campo
        // `enabled` del suo `plugin.json`, non da qui. Chi apriva il file
        // trovava scritto che due moduli erano attivi, e non lo erano — una
        // riga di configurazione che dice il falso è peggio di una che manca.
        // ── La dock ───────────────────────────────────────────────────
        //
        // Otto manopole che `dock/Dock.qml` dichiara e la shell legge da
        // sempre, e che fino al 18 agosto 2026 esistevano SOLO come valore di
        // ripiego scritto dentro il QML. Erano 46 chiavi su 108 in quello
        // stato: vedi `test/impostazioni_ripiego_test.dart`.
        'dock': {
          'enabled': true,
          'iconSize': 48,
          'magnification': 1.6,
          'reach': 2.2,
          // ── Come sta la dock sullo schermo ─────────────────────────────
          //
          // Tre modi, e non più una levetta:
          //
          //   'sempre'   riserva il suo spazio: le finestre si fermano sopra
          //              di lei e non ci passano mai sotto;
          //   'nascondi' sparisce, e torna avvicinando il puntatore al bordo
          //              basso dello schermo;
          //   'elude'    resta visibile finché nessuna finestra la
          //              coprirebbe, e si ritira quando una ci arriva sopra.
          //
          // Il terzo è quello che Giacomo ha chiesto il 2 settembre 2026 e
          // che non esisteva: «non hai ancora reso la dock a scomparsa o che
          // elude le finestre o sempre presente».
          //
          // `autoHide` resta scritto qui sotto per una ragione sola: chi
          // aveva già Minerva installata ha quel valore nel proprio file, e
          // `dock.modo` lo legge per non far cambiare comportamento a nessuno
          // di soppiatto. Vedi `Dock.qml`.
          'modo': 'sempre',
          'autoHide': false,
          // ── E da che parte sta la dock ────────────────────────────────
          //
          // 'basso' o 'alto'. Sopra o sotto la barra non è una scelta: chi
          // le mette dalla stessa parte se le trova una sull'altra, e la
          // shell non glielo impedisce — impedirlo vorrebbe dire decidere
          // per chi ha due schermi e una barra sola. Le Impostazioni lo
          // dicono a parole, che è il posto giusto per un avviso.
          'position': 'basso',
          'opacity': 0.90,
          // Col blur vero del compositore dietro. Vedi
          // `shell.membraneOpacityBlur`, che è lo stesso ragionamento per la
          // barra: sono due situazioni diverse, quindi due memorie.
          'opacityBlur': 0.68,
          'showLabels': true,
          // ⚠ `spine/panels/AppsPanel.qml` legge questa stessa chiave con un
          // ripiego DIVERSO (elenco vuoto). Qui vince quello della shell, che
          // è chi la dock la costruisce davvero.
          'pinned': ['firefox.desktop', 'minerva-terminale.desktop'],
        },
        'audio': {
          'feedbackSounds': true,
          'feedbackVolume': 0.4,
          // Volume oltre il 100%: distorce, e va chiesto.
          'allowOverdrive': false,
        },
        'input': {
          'layout': 'it',
          'repeatDelay': 600,
          'repeatRate': 25,
          'naturalScroll': true,
          'tapToClick': true,
          'disableWhileTyping': true,
          'sensitivity': 0,
          'touchpadOn': true,
          // I pad di gioco passano da InputPlumber, che li presenta a ogni
          // gioco come un pad del tipo scelto (`ControllerService`).
          'controllerAutomatico': true,
          'controllerTipo': 'xbox-series',
          // Per ogni pad, con chiave il suo indirizzo: preset, mappa dei
          // tasti, «scambia ✕ e ○» e i colori della barra luminosa. Mappa
          // libera: i pad sono quelli che uno collega.
          'controllerPad': <String, dynamic>{},
        },
        'power': {
          // Minuti. 0 = mai.
          'dimAfter': 5,
          'lockAfter': 10,
          'suspendAfter': 30,
          'lidAction': 'suspend',
          // Il modo risparmio del compositore: «auto» abbassa gli effetti a
          // batteria sotto la soglia (o col profilo «risparmio energetico»),
          // «sempre» sempre, «mai» mai. Vedi `compositore/src/energia.h`.
          'risparmioEffetti': 'auto',
          'risparmioSoglia': 20,
        },
        // La memoria che respira: le nostre app fuori vista da un minuto si
        // comprimono in zram («delicata»), o niente («spenta»). Vedi
        // `services/respiro_service.dart`.
        'memoria': {
          'respiro': 'delicata',
        },
        'notifications': {
          'doNotDisturb': false,
          // Cosa si vede sulla schermata di blocco: «numero» (per programma,
          // «Thunderbird · 3 email», come sul telefono), «tutto» (anche il
          // testo), «niente». Il filtro lo fa la shell PRIMA di passarle al
          // blocco: vedi `Core.Notifications._perIlBlocco`.
          'bloccoMostra': 'numero',
        },
        'windowControls': {
          'enabled': true,
        },
        // ── Le app tenute pronte ───────────────────────────────────────
        //
        // Un'app di Minerva chiusa se ne va, e riaprirla costa fra 317 e
        // 645 ms — misurati il 18 agosto 2026 sulla macchina vera, dal
        // lancio del processo alla finestra mappata dal compositore. Quasi
        // tutto quel tempo è la costruzione dell'albero degli oggetti QML,
        // e le due strade per accorciarla sono già state percorse e sono
        // chiuse (la cache di compilazione di Qt non si può accendere con
        // Quickshell 0.3; ridurre il sorgente non sposta niente).
        //
        // Resta una strada sola: non ricostruire. Un'app già costruita si
        // rimostra in 17–50 ms invece che in 317–645 — da dieci a venti volte
        // più veloce, e anche questo è misurato.
        //
        // Il prezzo si paga in memoria e non è piccolo: fra 49 e 98 MB
        // privati per app, sempre occupati, più uno 0,20% di CPU costante.
        // Tutte e sei insieme fanno 418 MB.
        // E non è un prezzo che si può togliere: la memoria che si paga È
        // la velocità che si compra, perché ciò che resta in memoria è
        // esattamente l'albero che non va ricostruito.
        //
        // Per questo sono tutte spente di fabbrica tranne il gestore file,
        // che era già acceso per scelta di Giacomo il 16 agosto e ha la sua
        // chiave storica in `files.tieniAcceso`. Si accendono una alla
        // volta, guardando il prezzo scritto accanto.
        'preload': {
          'calcolatrice': false,
          'editor': false,
          'impostazioni': false,
          'anteprima': false,
          'attivita': false,
          // Il Terminale tenuto pronto ha già una shell viva: l'apertura è
          // istantanea, e il prezzo è quella shell in memoria.
          'terminale': false,
          // Dopo quanti minuti da ferma un'app tenuta pronta esce da sola.
          // Zero la lascia lì per sempre: chi apre la calcolatrice una
          // volta stamattina non deve ritrovarsela in memoria stasera.
          'minuti': 30,
        },
      };

  Future<void> dispose() async {
    // Prima si aspetta che la fila si svuoti: fermarsi con una scrittura a
    // metà è esattamente il modo in cui si perde il file.
    await _coda;
    await _stopWatcher();
  }
}
