import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../compositor_provider.dart';

/// Implementazione di [CompositorProvider] per **minerva-wayland**, il
/// compositore di Minerva.
///
/// ── Perché esiste, e cosa NON fa ─────────────────────────────────────────
///
/// L'audit del 23 agosto 2026 contava, fra le cose mancanti: «`MinervaProvider`
/// nel demone: non esiste, c'è solo `hyprland_provider.dart`». Senza, dentro
/// minerva-wayland la dock è vuota, l'Alt+Tab non ha niente da scorrere e le
/// barre del titolo non sanno dove sta niente — perché tutto lo stato delle
/// finestre della shell arriva dal demone, non da un protocollo Wayland.
///
/// È la stessa forma di HyprlandProvider, e deliberatamente: **due letture
/// grezze e uno stream di eventi.** Nessun verbo. La shell comanda il
/// compositore da sé, per il suo canale — vedi `core/Compositore.qml` — e il
/// demone si limita a osservare. Tre metodi invece di sette, esattamente come
/// era stato scritto in `compositor_provider.dart` quando i verbi sono usciti.
///
/// ── E perché il JSON esce da qui COME ARRIVA ─────────────────────────────
///
/// `getClientsRaw()` torna il formato di minerva-wayland senza tradurlo in
/// quello di Hyprland. La tentazione era forte — così la shell non si accorge
/// di niente — ed è la strada sbagliata: vorrebbe dire tradurre il nostro
/// formato NEL PIÙ STRANO dei due (dove «schermo intero» è un numero fra zero
/// e due, dove «ridotto a icona» è una scrivania di servizio) per poi
/// ritradurlo in lingua nostra dentro il QML.
///
/// Il posto dove le parole di un compositore diventano parole di Minerva è
/// uno solo, e c'è già: `core/Compositore.qml`. Lì `_due()` fa la stessa cosa
/// per i verbi. Qui si passa avanti, e basta.
class MinervaProvider implements CompositorProvider {
  final _eventi = StreamController<CompositorEvent>.broadcast();

  /// Il percorso del socket. Vuoto = non l'abbiamo trovato.
  String _canale = '';
  Socket? _ascolto;
  StreamSubscription? _iscrizione;
  bool _acceso = false;
  bool _riconnessioneInCorso = false;

  /// `canale` si passa solo dalle prove: in sessione lo trova [trovaCanale].
  ///
  // L'analizzatore vorrebbe `{this._canale = ''}`, che Dart non accetta: un
  // parametro con nome non può essere privato. L'avviso è giusto in generale e
  // sbagliato qui.
  // ignore: prefer_initializing_formals
  MinervaProvider({String canale = ''}) : _canale = canale;

  @override
  Stream<CompositorEvent> get events => _eventi.stream;

  /// Dove parla minerva-wayland, o stringa vuota se non sta girando.
  ///
  /// Prima si guarda `MINERVA_CANALE`, che il compositore mette nell'ambiente
  /// dei propri figli — e la sessione di Minerva è un suo figlio. È la strada
  /// giusta: dice il socket di QUESTO compositore, non di uno qualsiasi.
  ///
  /// Il ripiego è cercare in `$XDG_RUNTIME_DIR`, e serve a un caso vero: il
  /// demone riavviato a mano da un terminale che il compositore non ha
  /// generato. Se ne trova più d'uno non si sceglie a caso — si rinuncia:
  /// due compositori vivi vogliono dire che qualcosa è rimasto in piedi, e
  /// attaccarsi a quello sbagliato darebbe una scrivania che risponde a metà,
  /// che è più difficile da capire di una che non risponde.
  static String trovaCanale() {
    final detto = Platform.environment['MINERVA_CANALE'] ?? '';
    if (detto.isNotEmpty) return detto;

    final run = Platform.environment['XDG_RUNTIME_DIR'] ?? '';
    if (run.isEmpty) return '';
    try {
      final trovati = Directory(run)
          .listSync(followLinks: false)
          .whereType<FileSystemEntity>()
          .map((e) => e.path)
          .where((p) {
            final nome = p.split('/').last;
            return nome.startsWith('minerva-wayland-') && nome.endsWith('.sock');
          })
          // I socket avanzati da un compositore morto si scartano qui: senza,
          // due prove interrotte lascerebbero due file e la ricerca
          // rinuncerebbe, pur essendocene uno solo vivo (o nessuno).
          .where(inAscolto)
          .toList()
        ..sort();
      if (trovati.length == 1) return trovati.first;
    } catch (_) {}
    return '';
  }

  /// Vero se minerva-wayland sta girando **adesso**: è così che il demone
  /// sceglie fra i due provider, senza chiedere niente a nessuno.
  ///
  /// ── Il file c'è e non risponde nessuno ─────────────────────────────────
  ///
  /// Un socket Unix è un file, e il file **resta sul disco quando il
  /// programma muore male**: `canale_chiudi()` lo toglie all'uscita pulita, ma
  /// un SIGKILL, una macchina che si spegne o una prova interrotta lo lasciano
  /// lì per sempre.
  ///
  /// Costato il 24 agosto 2026, e vale la pena raccontarlo perché il sintomo
  /// non somigliava alla causa: finita una prova annidata, il demone della
  /// sessione VERA ha visto quel file, ha concluso «gira minerva-wayland», e
  /// da lì in poi ha chiesto le finestre a un compositore morto. Hyprland
  /// aveva un terminale aperto; la shell diceva `finestre=0`. Nessun errore,
  /// da nessuna parte: la scrivania semplicemente non aveva più finestre.
  ///
  /// Non basta guardare se il file esiste: bisogna guardare se qualcuno
  /// ASCOLTA. `/proc/net/unix` elenca i socket legati con il loro percorso, e
  /// un file avanzato lì dentro non c'è. È una lettura sincrona, e deve
  /// esserlo: la scelta del provider si fa nel costruttore del nucleo, prima
  /// che esista un ciclo di eventi in cui aspettare una connessione.
  static bool inUso() {
    final c = trovaCanale();
    return c.isNotEmpty && inAscolto(c);
  }

  /// Vero se qualcuno è in ascolto su quel percorso.
  ///
  /// `proc` si passa solo dalle prove: il contenuto di `/proc/net/unix` non si
  /// può fabbricare, e una riga di quel file è esattamente ciò che va provato.
  static bool inAscolto(String percorso, {String? proc}) {
    if (percorso.isEmpty) return false;
    try {
      final testo = proc ?? File('/proc/net/unix').readAsStringSync();
      for (final riga in const LineSplitter().convert(testo)) {
        // Il percorso è l'ULTIMO campo, e si confronta per intero: cercarlo
        // con `contains` farebbe passare per vivo `…-0.sock.vecchio`, e
        // soprattutto qualunque socket il cui percorso contenga il nostro.
        final i = riga.lastIndexOf(' ');
        if (i < 0) continue;
        if (riga.substring(i + 1) == percorso) return true;
      }
    } catch (_) {
      // Senza `/proc` non si può sapere, e allora si crede al file: è il
      // comportamento di prima, ed è quello giusto quando manca l'informazione
      // migliore — non si spegne una funzione perché non si è potuto
      // verificarla.
      return true;
    }
    return false;
  }

  // ── Chiedere ────────────────────────────────────────────────────────────
  //
  // Un collegamento per domanda, come fa HyprlandProvider con `.socket.sock`,
  // e non il collegamento degli eventi. Non è spreco: è ciò che evita di dover
  // distinguere una risposta da un annuncio arrivato nel frattempo — cioè un
  // pezzo di codice che sbaglia una volta ogni mille e non si trova più.
  Future<String> _chiedi(String comando) async {
    if (_canale.isEmpty) _canale = trovaCanale();
    if (_canale.isEmpty) return '';

    for (var tentativo = 0; tentativo < 2; tentativo++) {
      Socket? s;
      try {
        s = await Socket.connect(
          InternetAddress(_canale, type: InternetAddressType.unix),
          0,
        ).timeout(const Duration(seconds: 2));
        s.add(utf8.encode('$comando\n'));
        await s.flush();

        // Si legge UNA riga e si chiude. Il protocollo è a righe, e la
        // risposta è una riga: aspettare la fine dello stream vorrebbe dire
        // aspettare che il compositore chiuda, e lui non chiude.
        final riga = await s
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first
            .timeout(const Duration(seconds: 2));
        s.destroy();
        return riga;
      } catch (e) {
        s?.destroy();
        if (tentativo == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          continue;
        }
        print('[MINERVA][CORE][ERRORE] minerva-wayland non risponde '
            'a "$comando": $e');
      }
    }
    return '';
  }

  /// Il carico di una risposta `ok …`, o stringa vuota.
  ///
  /// Un `no …` NON diventa stringa vuota per caso: ci si passa apposta, perché
  /// chi chiama legge la stringa vuota come «nessuna finestra» e per un giro la
  /// dock si svuota. Meglio niente aggiornamento che un aggiornamento falso.
  static String caricoOk(String risposta) {
    if (risposta.startsWith('ok ')) return risposta.substring(3).trim();
    if (risposta.trim() == 'ok') return '';
    return '';
  }

  static bool _sembraJson(String s) {
    final t = s.trimLeft();
    return t.startsWith('[') || t.startsWith('{');
  }

  @override
  Future<String> getClientsRaw() async {
    final r = caricoOk(await _chiedi('finestre'));
    return _sembraJson(r) ? r : '[]';
  }

  @override
  Future<String> getMonitorsRaw() async {
    final r = caricoOk(await _chiedi('schermi'));
    return _sembraJson(r) ? r : '[]';
  }

  /// Le scrivanie, chieste al compositore.
  ///
  /// Fino al 25 agosto 2026 qui si tornava una scrivania sola e finta, perché
  /// in minerva-wayland le scrivanie non c'erano: la shell mandava
  /// `workspace 3` e quella riga se ne andava nel vuoto — lo stesso modo in
  /// cui era sparito il «riduci». Adesso c'è un elenco vero.
  ///
  /// Se la domanda non riesce si torna **una scrivania sola** e non un elenco
  /// vuoto: chi legge — la striscia dei pallini nella barra — con l'elenco
  /// vuoto non disegna niente, e «niente» somiglia troppo a «il demone è
  /// caduto».
  @override
  Future<List<WorkspaceState>> getWorkspaces() async {
    final r = caricoOk(await _chiedi('scrivanie'));
    try {
      final l = jsonDecode(r);
      if (l is List && l.isNotEmpty) {
        return [
          for (final w in l.whereType<Map>())
            WorkspaceState(
              id: (w['id'] as num?)?.toInt() ?? 0,
              name: '${w['nome'] ?? w['id'] ?? ''}',
              isActive: w['attiva'] == true,
              windowsCount: (w['finestre'] as num?)?.toInt() ?? 0,
            ),
        ];
      }
    } catch (_) {}
    return [
      WorkspaceState(id: 1, name: '1', isActive: true, windowsCount: 0),
    ];
  }

  // ── Ascoltare ───────────────────────────────────────────────────────────

  @override
  Future<void> start() async {
    if (_acceso) return;
    _acceso = true;

    if (_canale.isEmpty) _canale = trovaCanale();
    if (_canale.isEmpty) {
      print('[MINERVA][CORE][WARN] minerva-wayland: canale non trovato. '
          'Il demone non saprà quando le finestre cambiano.');
      return;
    }

    try {
      _ascolto = await Socket.connect(
        InternetAddress(_canale, type: InternetAddressType.unix),
        0,
      );
      // `ascolta` è ciò che trasforma questo collegamento in un abbonamento:
      // senza, il compositore risponde alle domande e non dice mai niente di
      // sua iniziativa.
      _ascolto!.add(utf8.encode('ascolta\n'));
      await _ascolto!.flush();

      _iscrizione = _ascolto!
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            leggiRiga,
            onError: (Object e) {
              print('[MINERVA][CORE][ERRORE] canale di minerva-wayland: $e');
              _riprendi();
            },
            onDone: () {
              print('[MINERVA][CORE][INFO] canale di minerva-wayland chiuso.');
              _riprendi();
            },
          );
      print('[MINERVA][CORE][OK] In ascolto su minerva-wayland: $_canale');
    } catch (e) {
      print('[MINERVA][CORE][ERRORE] minerva-wayland non raggiungibile: $e');
      _riprendi();
    }
  }

  /// La stessa forma della riconnessione di HyprlandProvider, e per la stessa
  /// ragione: là il difetto era che `start()` cominciava con
  /// `if (_running) return;` e la riconnessione lo chiamava senza spegnere il
  /// flag — cioè non riconnetteva mai. Un socket degli eventi caduto e non
  /// ripreso vuol dire una dock ferma per il resto della sessione.
  void _riprendi() {
    if (!_acceso || _riconnessioneInCorso) return;
    _riconnessioneInCorso = true;
    Future<void>.delayed(const Duration(seconds: 2), () async {
      _riconnessioneInCorso = false;
      if (!_acceso) return;
      await _iscrizione?.cancel();
      _iscrizione = null;
      _ascolto?.destroy();
      _ascolto = null;
      // Il compositore può essere ripartito su un altro display: il socket va
      // ritrovato, non riusato.
      _canale = '';
      _acceso = false;
      await start();
    });
  }

  /// Una riga del canale. Pubblica perché è tutta la logica che vale la pena
  /// provare, e provarla non deve richiedere un compositore acceso.
  ///
  ///     evento aperta {"id":"0x55f1c0","pid":4211,…}
  ///
  /// Le righe che non cominciano con `evento` si buttano senza dire niente:
  /// sono le risposte `ok`/`no` a un comando che qualcun altro ha mandato su
  /// questo stesso collegamento, e un giorno potrebbero esserci.
  void leggiRiga(String riga) {
    final e = daRiga(riga);
    if (e != null) _eventi.add(e);
  }

  /// Da una riga del canale a un evento, o `null`.
  ///
  /// ── Il carico è JSON, e non è un dettaglio ─────────────────────────────
  ///
  /// Hyprland manda `attributo>>valore1,valore2`, e questo progetto ci ha già
  /// perso mezza giornata: `activewindow` manda `CLASSE,TITOLO` e
  /// `activewindowv2` manda `INDIRIZZO`, il demone leggeva il secondo come il
  /// primo, e il ramo «due campi» non scattava mai perché un indirizzo non ha
  /// virgole — mentre un titolo di finestra ce le ha quasi sempre. Con un
  /// oggetto JSON quella classe di difetti non esiste.
  static CompositorEvent? daRiga(String riga) {
    final r = riga.trim();
    if (!r.startsWith('evento ')) return null;

    final resto = r.substring(7).trim();
    final spazio = resto.indexOf(' ');
    if (spazio <= 0) return null;

    final che = resto.substring(0, spazio);
    dynamic carico;
    try {
      carico = jsonDecode(resto.substring(spazio + 1));
    } catch (_) {
      return null;
    }

    switch (che) {
      case 'aperta':
        return CompositorEvent(
            type: CompositorEventType.windowOpened, payload: carico);
      case 'chiusa':
        return CompositorEvent(
            type: CompositorEventType.windowClosed, payload: carico);
      case 'fuoco':
        return CompositorEvent(
            type: CompositorEventType.windowFocused, payload: carico);
      case 'titolo':
        return CompositorEvent(
            type: CompositorEventType.windowTitleChanged, payload: carico);
      case 'mossa':
        return CompositorEvent(
            type: CompositorEventType.windowMoved, payload: carico);
      // «stato» copre ingrandita, ridotta e schermo intero: sono tre bit dello
      // stesso oggetto e arrivano insieme. Si alza `fullscreenChanged` perché
      // è quello a cui la shell reagisce ridisegnando la barra del titolo, ed
      // è l'unico dei tre che le cambia la forma.
      case 'stato':
        return CompositorEvent(
            type: CompositorEventType.fullscreenChanged, payload: carico);
      case 'schermi':
        return CompositorEvent(
            type: CompositorEventType.monitorChanged, payload: carico);
      // Il carico esce **come intero**, e non come l'oggetto arrivato: è
      // l'unico posto di tutto il provider dove si cambia forma a un dato, e
      // ha una ragione precisa. `minerva_core.dart` fa
      // `if (payload is int) stateManager.setActiveWorkspace(payload)`, che è
      // la forma che manda Hyprland; consegnargli una mappa vorrebbe dire un
      // `if` che non scatta mai — un cambio di scrivania che non risulta a
      // nessuno, e nessun errore da nessuna parte. Tradurre è il mestiere di
      // questo file.
      case 'scrivania':
        final attiva = carico is Map ? carico['attiva'] : null;
        if (attiva is! int) return null;
        return CompositorEvent(
            type: CompositorEventType.workspaceChanged, payload: attiva);
      default:
        return null;
    }
  }

  @override
  Future<void> stop() async {
    _acceso = false;
    await _iscrizione?.cancel();
    _iscrizione = null;
    _ascolto?.destroy();
    _ascolto = null;
    await _eventi.close();
  }
}
