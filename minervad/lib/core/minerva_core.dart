import 'dart:async';
import 'event_bus.dart';
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
import 'ambiente.dart';

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

  StreamSubscription? _compositorEventSubscription;
  StreamSubscription? _keybindSubscription;

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
  Future<void> start() async {
    print('[MINERVA][CORE][INFO] Inizializzazione di Minerva Core...');
    print('[MINERVA][CORE][INFO] Installazione: ${MinervaPaths.installRoot}');
    print('[MINERVA][CORE][INFO] Preferenze: ${MinervaPaths.configDir}');

    // 0. Il trasloco.
    //
    // Impostazioni, tema e conteggio degli avvii stavano dentro la cartella
    // del progetto. Adesso stanno in ~/.config/minerva, dove stanno le cose
    // di chi usa un programma e non quelle del programma. Chi aveva già
    // Minerva se le porta dietro senza accorgersene; chi la installa oggi non
    // trova niente da traslocare e questa riga non fa nulla.
    await MinervaPaths.migrateIfNeeded('settings.json');
    await MinervaPaths.migrateIfNeeded('app_usage.json');

    // 1. Carica Impostazioni e Tracker
    await settingsApi.init();
    await appUsageTracker.init();
    await keybindService.init();

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
    await appScanner.scan();

    // Lo stato dell'apparecchio: batteria, luminosità, rete, Bluetooth.
    // Letto qui una volta per tutte e tre le finestre di Minerva — prima
    // ognuna se lo leggeva da sé, e non si parlavano. Vedi
    // `services/system_state_service.dart`.
    await systemState.init();
    await processi.init();

    // 2. Avvia il Provider del Compositor
    await compositorProvider.start();

    // Subito dopo, chi racconta lo stato delle finestre. Prima del server
    // WebSocket, perché deve già essere in ascolto quando il primo processo di
    // Minerva si collega: chi si collega riceve lo stato all'istante.
    finestre.avvia();

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

    // 4. Avvia il server WebSocket IPC
    await webSocketServer.start();

    // 5. Avvia i plugin esterni
    await pluginManager.init();

    print('[MINERVA][CORE][OK] Minerva Core inizializzato completamente.');
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
  Future<void> stop() async {
    print('[MINERVA][CORE][INFO] Arresto in corso...');

    // 1. Chi si sveglia da solo, per primo.
    await systemState.dispose();
    processi.dispose();
    await finestre.ferma();
    await keybindService.dispose();
    fileService.dispose();

    // 2. Chi ascolta.
    await _compositorEventSubscription?.cancel();
    await _keybindSubscription?.cancel();

    // 3. Chi parla con l'esterno.
    await pluginManager.dispose();
    await webSocketServer.stop();
    await compositorProvider.stop();
    await settingsApi.dispose();

    // 4. E per ultimo il bus, quando non ha più nessuno che ci scriva.
    await eventBus.dispose();
    print('[MINERVA][CORE][OK] Minerva Core arrestato.');
  }
}
