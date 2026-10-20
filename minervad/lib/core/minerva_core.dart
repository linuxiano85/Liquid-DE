import 'dart:async';
import 'dart:io';
import 'event_bus.dart';
import 'cancellation.dart';
import 'state_manager.dart';
import 'minerva_paths.dart';
import 'settings_api.dart';
import '../ipc/websocket_server.dart';
import '../providers/compositor_provider.dart';
import '../providers/minerva/minerva_provider.dart';
import '../plugins/plugin_manager.dart';
import '../services/app_scanner.dart';
import '../services/process_service.dart';
import '../services/icon_resolver.dart';
import '../services/app_usage_tracker.dart';
import '../services/keybind_service.dart';
import '../services/file_service.dart';
import '../services/system_state_service.dart';
import '../services/finestre_service.dart';
import '../services/respiro_service.dart';
import 'ambiente.dart';
import '../services/segnalibri_gtk.dart';

/// Coordinatore centrale del backend di Minerva Desktop.
/// Inizializza tutti i moduli nell'ordine corretto e gestisce il ciclo di vita.
class MinervaCore {
  final EventBus eventBus = EventBus();
  late final StateManager stateManager;
  late final SettingsApi settingsApi;
  late final CompositorProvider compositorProvider;
  late final WebSocketServer webSocketServer;
  late final PluginManager pluginManager;
  late final AppScanner appScanner;
  late final IconResolver iconResolver;
  late final AppUsageTracker appUsageTracker;
  late final KeybindService keybindService;
  late final FileService fileService;
  late final SystemStateService systemState;

  /// Chi sta girando e quanto costa. Legge solo mentre il monitor è aperto.
  late final ProcessService processi;

  /// Dove sono le finestre e quanto spazio c'è, letto una volta e mandato a
  /// tutti. Vedi `services/finestre_service.dart`.
  late final FinestreService finestre;
  /// Le app che non si guardano si comprimono in zram: vedi
  /// `services/respiro_service.dart`.
  late final RespiroService respiro;

  StreamSubscription? _compositorEventSubscription;
  StreamSubscription? _keybindSubscription;
  StreamSubscription? _settingsSubscription;
  Future<void>? _startFuture;
  Future<void>? _stopFuture;
  Future<void>? _shutdownFuture;
  final _startupCancellation = CancellationToken();
  Timer? _startupProbe;

  MinervaCore() {
    stateManager = StateManager(eventBus);
    settingsApi = SettingsApi(eventBus);
    appScanner = AppScanner();
    iconResolver = IconResolver();
    appUsageTracker = AppUsageTracker();
    keybindService = KeybindService();
    fileService = FileService();
    systemState = SystemStateService(eventBus);
    processi = ProcessService(eventBus);

    // ── Il compositore è uno solo ────────────────────────────────────
    //
    // Fino al 1º settembre 2026 qui si SCEGLIEVA: `MINERVA_COMPOSITORE`,
    // poi «il socket è già aperto?», poi il ripiego su `HyprlandProvider`.
    // Tre strade perché ce n'erano due possibili, e la scelta non si chiedeva
    // a un'impostazione ma al mondo — un'impostazione che dice
    // «minerva-wayland» mentre gira Hyprland darebbe una scrivania senza
    // finestre e nessun indizio sul perché.
    //
    // Adesso di compositori ce n'è uno, ed è nostro: la cucitura sparisce
    // insieme alla scelta. `MinervaProvider` sa già dire di no da solo —
    // canale non trovato, e lo dice a voce alta invece di fingere una
    // scrivania vuota.
    compositorProvider = MinervaProvider();
    finestre = FinestreService(compositorProvider);
    respiro = RespiroService(compositorProvider, settingsApi);
    processi.respiro = respiro.perPid;

    webSocketServer = WebSocketServer(
      eventBus,
      stateManager,
      settingsApi,
      compositorProvider,
      appScanner,
      iconResolver,
      appUsageTracker,
      keybindService,
      fileService,
      systemState,
      finestre,
      processi,
    );

    pluginManager = PluginManager(eventBus);
  }

  /// Avvia tutti i servizi nell'ordine corretto.
  Future<void> start() {
    if (_stopFuture != null || _shutdownFuture != null) {
      return Future<void>.error(StateError('Core già in arresto'));
    }
    return _startFuture ??= _startWithCleanup();
  }

  Future<void> _startWithCleanup() async {
    try {
      await _startServices();
    } catch (error, stack) {
      if (error is OperationCancelled) {
        print('[MINERVA][CORE][INFO] Avvio annullato: chiudo le risorse acquisite.');
      } else {
        print('[MINERVA][CORE][WARN] Avvio incompleto: chiudo le risorse acquisite.');
      }
      try {
        await _stopResourcesOnce();
      } catch (cleanupError) {
        // Le fasi hanno già registrato gli errori; non perdere la causa
        // originale dell'avvio dietro a un eventuale errore di pulizia.
        print('[MINERVA][CORE][ERRORE] Pulizia dopo avvio fallito non completa '
            '(${cleanupError.runtimeType}).');
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> _startServices() async {
    // Opt-in: tempi del percorso reale senza loggare impostazioni, comandi
    // o credenziali. Stopwatch è monotono e locale a questo avvio del core;
    // questi valori non misurano da soli autenticazione o presentazione GPU.
    final traceStartup = Platform.environment['LIQUID_TRACE_STARTUP'] == '1';
    final startupClock = Stopwatch();
    if (traceStartup) {
      startupClock.start();
      _sorvegliaCiclo(startupClock);
    }
    final failStage = Platform.environment['MINERVA_PROVA'] == '1'
        ? Platform.environment['MINERVA_PROVA_AVVIO_FALLISCI'] : null;
    var previousStageUs = 0;
    void stage(String name) {
      // Fault injection esclusivamente nel banco privato, mai dal solo
      // flag di diagnostica usato nella sessione o nel greeter.
      if (failStage == name) throw StateError('Avvio interrotto dal banco');
      _startupCancellation.throwIfCancelled();
      if (!traceStartup) return;
      final now = startupClock.elapsedMicroseconds;
      print('[LIQUID][STARTUP] pid=$pid stage=$name elapsed_us=$now '
          'delta_us=${now - previousStageUs}');
      previousStageUs = now;
    }
    stage('core.begin');
    print('[MINERVA][CORE][INFO] Inizializzazione di Minerva Core...');
    print('[MINERVA][CORE][INFO] Installazione: ${MinervaPaths.installRoot}');
    print('[MINERVA][CORE][INFO] Preferenze: ${MinervaPaths.configDir}');

    // 0. Al primo avvio si parte dalle impostazioni di Minerva, se ci sono:
    // copiate, non spostate. Dal secondo avvio questa riga non fa nulla.
    await MinervaPaths.importaDaMinerva('settings.json');
    _startupCancellation.throwIfCancelled();
    await MinervaPaths.importaDaMinerva('app_usage.json');
    stage('preferences.imported');

    // 1. Carica Impostazioni e Tracker
    await settingsApi.init(cancellation: _startupCancellation);
    stage('settings.loaded');
    await appUsageTracker.init();
    stage('usage.loaded');
    await keybindService.init();
    stage('keybindings.loaded');

    // Le scorciatoie spente nelle Impostazioni, applicate da subito: il
    // compositore riceve solo quelle accese.
    _applicaScorciatoieSpente();

    // Inizializza il tema icone e avvia la scansione delle app installate.
    //
    // Il tema delle icone non si cerca nella schermata di accesso: l'utente
    // `greeter` non ha una casa dove tenerne uno, e infatti la riga che
    // lasciava era un avviso — «Tema icone non rilevato. Fallback su:
    // hicolor». Un avviso per una cosa che non è un guasto insegna a non
    // leggere gli avvisi. Vedi `core/ambiente.dart`.
    if (!Ambiente.eGreeter) {
      await iconResolver.init();
    }
    stage(Ambiente.eGreeter ? 'icons.skipped-greeter' : 'icons.initialized');
    await appScanner.scan();
    stage('applications.scanned');

    // Lo stato dell'apparecchio: batteria, luminosità, rete, Bluetooth.
    // Letto qui una volta per tutte e tre le finestre di Minerva — prima
    // ognuna se lo leggeva da sé, e non si parlavano. Vedi
    // `services/system_state_service.dart`.
    await systemState.init();
    stage('system.initialized');
    await processi.init();
    stage('processes.initialized');

    // 2. Avvia il Provider del Compositor
    await compositorProvider.start();
    stage('compositor.start-returned');

    // Subito dopo, chi racconta lo stato delle finestre. Prima del server
    // WebSocket, perché deve già essere in ascolto quando il primo processo di
    // Minerva si collega: chi si collega riceve lo stato all'istante.
    finestre.avvia();
    stage('windows.observer-started');
    // Nella schermata di accesso non ci sono app nostre da far respirare.
    if (!Ambiente.eGreeter) respiro.avvia();

    // ── Quale scrivania è attiva, e nient'altro ──────────────────────────
    //
    // Qui c'era anche una rilettura completa delle scrivanie a ogni finestra
    // aperta o chiusa: un giro di IPC al compositore, l'elenco di tutte le
    // finestre in JSON, e la spedizione a ogni processo di Minerva collegato.
    // Nessuno lo apriva — le finestre la shell le riceve da `finestre`, che è
    // un'altra strada. Vedi `core/state_manager.dart`.
    //
    // Quel che resta costa zero: il numero della scrivania arriva già dentro
    // l'evento, non c'è niente da chiedere a nessuno.
    _compositorEventSubscription = compositorProvider.events.listen((event) {
      if (event.type == CompositorEventType.workspaceChanged) {
        final payload = event.payload;
        if (payload is int) stateManager.setActiveWorkspace(payload);
      }
    });

    // Ritrasmette l'elenco scorciatoie quando keybinds.conf viene modificato
    _keybindSubscription = keybindService.changes.listen((_) {
      eventBus.publish(MinervaEvent(
        type: 'keybindings_changed',
        payload: keybindService.toJson(),
      ));
      // E le stesse, tradotte per minerva-wayland: senza questa riga, chi
      // cambia una scorciatoia la vede comparire nel promemoria di Super+K e
      // il tasto continua a fare quello di prima — finché non riavvia la
      // sessione. Il compositore le rimpiazza tutte, `scorciatoie azzera`
      // compreso.
      eventBus.publish(MinervaEvent(
        type: 'scorciatoie_compositore',
        payload: {'righe': keybindService.perMinervaWayland()},
      ));
    });

    // Quando cambiano le Impostazioni, rileggi quali scorciatoie sono spente:
    // spegnerne una deve liberare il tasto senza riavviare la sessione.
    _settingsSubscription = eventBus.ascolta((evento) {
      if (evento.type == 'settings_changed') {
        _applicaScorciatoieSpente();
        _allineaSegnalibri();
      }
    }, chi: 'core-scorciatoie');
    // Le cartelle fissate anche nelle finestre «Apri/Salva» degli altri
    // programmi: vedi `SegnalibriGtk`. Una volta all'avvio, poi a ogni cambio.
    _allineaSegnalibri();

    // 4. Avvia il server WebSocket IPC
    await webSocketServer.start(traceStartup: traceStartup ? stage : null,
        cancellation: _startupCancellation);
    // The listener is registered earlier inside start; this marks its return,
    // including service initialization and work interleaved during awaits.
    stage('ipc.start.returned');

    // 5. Avvia i plugin esterni
    await pluginManager.init();
    stage('plugins.init-returned');

    stage('core.complete');
    print('[MINERVA][CORE][OK] Minerva Core inizializzato completamente.');
  }

  /// Solo con `LIQUID_TRACE_STARTUP=1`, solo per i primi dieci secondi: dice
  /// quando il ciclo degli eventi resta fermo più di 150 ms. Al login fisico
  /// v23 (18 ottobre 2026) la richiesta di accesso è partita 3,3 s dopo che la
  /// schermata l'aveva spedita, con greetd che rispondeva in 30 ms: qualcosa
  /// teneva fermo il demone, e da fuori non si vede che cosa.
  void _sorvegliaCiclo(Stopwatch orologio) {
    var ultimo = orologio.elapsedMilliseconds;
    _startupProbe?.cancel();
    _startupProbe = Timer.periodic(const Duration(milliseconds: 50), (t) {
      final ora = orologio.elapsedMilliseconds;
      final buco = ora - ultimo;
      ultimo = ora;
      if (buco > 150) {
        print('[LIQUID][STARTUP] pid=$pid stage=loop.stall gap_ms=$buco '
            'elapsed_ms=$ora realtime_ms=${DateTime.now().millisecondsSinceEpoch}');
      }
      if (ora > 10000) t.cancel();
    });
  }

  final SegnalibriGtk _segnalibriGtk = SegnalibriGtk();

  /// Le cartelle fissate in Minerva File (`files.pinned`) nei segnalibri GTK.
  /// `SegnalibriGtk` non fa niente se l'elenco non è cambiato. Un errore di
  /// scrittura si dice nel registro e basta: non è una ragione per fermare
  /// il demone.
  void _allineaSegnalibri() {
    final files = settingsApi.settings['files'];
    final fissate = (files is Map && files['pinned'] is List)
        ? (files['pinned'] as List).whereType<String>().toList()
        : <String>[];
    _segnalibriGtk.allinea(fissate).catchError((Object e) {
      print('[MINERVA][SEGNALIBRI][WARN] Segnalibri GTK non aggiornati: $e');
      return false;
    });
  }

  /// Legge `shortcuts.disabled` dalle Impostazioni e la passa al traduttore:
  /// le scorciatoie spente non vengono registrate nel compositore, e il tasto
  /// resta libero. Se la lista è cambiata, si ripubblicano le righe.
  void _applicaScorciatoieSpente() {
    final raw = settingsApi.settings['shortcuts'];
    final lista = (raw is Map && raw['disabled'] is List)
        ? raw['disabled'].cast<String>().toSet()
        : <String>{};
    final gia = keybindService.disattivate;
    final uguali = gia.length == lista.length && gia.containsAll(lista);
    if (uguali) return;
    keybindService.disattivate = lista;
    eventBus.publish(MinervaEvent(
      type: 'scorciatoie_compositore',
      payload: {'righe': keybindService.perMinervaWayland()},
    ));
  }

  /// Arresta in modo pulito tutte le risorse e i servizi.
  ///
  /// ── L'ordine non è casuale ─────────────────────────────────────────────
  ///
  /// Prima si zittisce **chi pubblica** (i servizi con un timer proprio), poi
  /// chi ascolta, e solo alla fine il bus. Al contrario, un timer già in coda
  /// pubblica su un bus chiuso — che prima faceva morire il processo a metà
  /// arresto, e adesso viene contato e detto (vedi `EventBus`).
  ///
  /// `systemState` e `processi` **non venivano fermati affatto**: due timer
  /// periodici (uno ogni 12 secondi, l'altro ogni 2 mentre il monitor è
  /// aperto) restavano vivi dopo un arresto che si dichiarava «pulito». In
  /// `--test-start` era abbastanza a tenere in piedi il processo.
  Future<void> stop() {
    _blockAdmissions();
    return _shutdownFuture ??= _stopAfterStartup();
  }

  void _blockAdmissions() {
    _startupCancellation.cancel();
    webSocketServer.blockAdmission();
    pluginManager.quiesce();
    _startupProbe?.cancel();
  }

  Future<void> _stopAfterStartup() async {
    try { await _startFuture; } catch (_) {
      // start conserva la propria eccezione. La pulizia usa un Future
      // distinto per evitare un ciclo start -> stop -> start.
    }
    await _stopResourcesOnce();
  }

  Future<void> _stopResourcesOnce() {
    _blockAdmissions();
    return _stopFuture ??= _stopServices();
  }

  Future<void> _stopServices() async {
    print('[MINERVA][CORE][INFO] Arresto in corso...');
    final sw = Stopwatch()..start();

    // Nessuna nuova richiesta deve entrare mentre i suoi servizi vengono
    // distrutti. Le connessioni perdono anche le sottoscrizioni qui.
    await _fase('ipc.quiesce', webSocketServer.quiesce);

    await _fase('systemState', systemState.dispose);
    await _fase('processi', () async => processi.dispose());
    await _fase('finestre', finestre.ferma);
    await _fase('respiro', respiro.ferma);
    await _fase('keybind', keybindService.dispose);
    // Copie in corso: staging privato, ma diamo tempo di chiudere bene.
    await _fase('fileService', fileService.dispose,
        limite: const Duration(seconds: 8));

    await _fase('sottoscrizioni', () async {
      await _compositorEventSubscription?.cancel();
      await _keybindSubscription?.cancel();
      await _settingsSubscription?.cancel();
    });

    await _fase('plugin', pluginManager.dispose);
    await _fase('ipc.stop', webSocketServer.stop);
    await _fase('compositore', compositorProvider.stop);
    // Le impostazioni si scrivono qui: il limite più largo di tutti.
    await _fase('impostazioni', settingsApi.dispose,
        limite: const Duration(seconds: 10));

    await _fase('eventBus', eventBus.dispose);
    if (_fasiSforate.isNotEmpty || _fasiFallite.isNotEmpty) {
      // Tutte le fasi sono state tentate; l'arresto resta «non pulito» come
      // prima, e chi chiama (`bin/minervad.dart`) esce con 1.
      throw StateError('arresto in ${sw.elapsedMilliseconds} ms; '
          'oltre il limite: ${_fasiSforate.join(', ')}; '
          'fallite: ${_fasiFallite.join(', ')}');
    }
    print('[MINERVA][CORE][OK] Minerva Core arrestato in '
        '${sw.elapsedMilliseconds} ms.');
  }

  // ── Un limite per fase ─────────────────────────────────────────────────
  //
  // Un arresto è durato minuti, fermo prima di `_controller.close()` (18
  // ottobre), e nessuno sapeva in quale fase. Ora ogni fase ha un tempo
  // massimo: se lo sfora si scrive QUALE, e si va avanti. Continuare con una
  // fase ancora viva è meno grave di un demone che non esce mai: la sessione
  // dopo aspetterebbe il suo posto per sempre.

  final List<String> _fasiSforate = [];
  final List<String> _fasiFallite = [];

  Future<void> _fase(String nome, Future<void> Function() lavoro,
      {Duration limite = const Duration(seconds: 3)}) async {
    final sw = Stopwatch()..start();
    try {
      await _provaBlocca(nome, lavoro).timeout(limite);
    } on TimeoutException {
      _fasiSforate.add(nome);
      print('[MINERVA][CORE][WARN] Arresto: la fase «$nome» supera '
          '${limite.inSeconds} s, si prosegue senza aspettarla.');
      return;
    } catch (e) {
      _fasiFallite.add(nome);
      print('[MINERVA][CORE][WARN] Arresto: la fase «$nome» è fallita: $e');
      return;
    }
    if (sw.elapsedMilliseconds > 500) {
      print('[MINERVA][CORE][INFO] Arresto: «$nome» ${sw.elapsedMilliseconds} ms.');
    }
  }

  /// Solo nelle prove (`MINERVA_PROVA=1`): `MINERVA_PROVA_ARRESTO_BLOCCA=<fase>`
  /// fa restare quella fase appesa per sempre, per verificare il limite.
  static Future<void> _provaBlocca(String nome, Future<void> Function() lavoro) {
    final env = Platform.environment;
    if (env['MINERVA_PROVA'] == '1' && env['MINERVA_PROVA_ARRESTO_BLOCCA'] == nome) {
      return Completer<void>().future;
    }
    return lavoro();
  }
}
