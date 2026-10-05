import 'dart:async';

import '../providers/compositor_provider.dart';

/// Chi sa dove sono le finestre, e lo dice a tutti.
///
/// ── Perché esiste ─────────────────────────────────────────────────────────
///
/// La shell, il gestore file e le Impostazioni sono processi distinti, e
/// tutti vogliono l'elenco delle finestre e lo spazio utile degli schermi (la
/// dock, il pannello delle ridotte, la garanzia che tiene le finestre dentro
/// lo spazio). Se ognuno lo chiedesse da sé, tre processi chiederebbero la
/// stessa cosa nello stesso istante, con tre risposte scattate in tre
/// momenti diversi. Qui la domanda si fa una volta, e chi guarda riceve.
///
/// ── Le due cose che non si vedono leggendo il codice ──────────────────────
///
///  1. **Il compositore annuncia quasi tutto.** Apertura, chiusura, fuoco,
///     titolo, schermo intero: sono eventi sul canale di minerva-wayland, e
///     reagire a un evento arriva prima che accorgersene guardando.
///
///  2. **Ma non annuncia il trascinamento col mouse.** Mentre si tiene
///     premuto e si sposta, la geometria cambia e il compositore non dice
///     niente fino a quando la si lascia. È l'unica ragione per cui qui dentro
///     c'è un timer: lento a riposo, veloce appena una lettura vede qualcosa
///     muoversi (`motoVero`).
class FinestreService {
  final CompositorProvider _compositore;

  FinestreService(this._compositore);

  /// Il JSON delle finestre, ogni volta che cambia.
  Stream<String> get finestre => _finestre.stream;
  final _finestre = StreamController<String>.broadcast();

  /// Il JSON dei monitor con le zone riservate, ogni volta che cambia.
  Stream<String> get monitor => _monitor.stream;
  final _monitor = StreamController<String>.broadcast();

  StreamSubscription? _ascolto;

  /// L'ultima risposta mandata. Serve a non ripetersi: a passo veloce si
  /// interroga sedici volte al secondo, ma una finestra ferma non produce
  /// nessun messaggio.
  String _ultimeFinestre = '';
  String _ultimiMonitor = '';

  /// L'ultima lettura senza i titoli: è questa che dice se qualcosa si è
  /// MOSSO. Vedi `senzaTitoli` più sotto.
  String _ultimaFirma = '';

  Timer? _attesa;
  Timer? _passo;
  Timer? _calma;
  bool _veloce = false;
  int _clienti = 0;
  bool _inLettura = false;
  bool _daRileggere = false;

  /// Vero quando l'ultima lettura non ha trovato nessuna finestra.
  bool _nessunaFinestra = false;

  // ── I tre tempi, e perché sono questi ──────────────────────────────────
  //
  // ATTESA (30 ms): gli eventi arrivano a grappoli. Aprire una finestra ne
  // manda tre o quattro in pochi millisecondi (`openwindow`,
  // `changefloatingmode`, `activewindow`, `windowtitle`). Interrogare a ogni
  // evento vorrebbe dire quattro letture per dire quattro volte la stessa
  // cosa. Trenta millisecondi li accorpano e restano sotto la soglia in cui
  // un occhio distingue «subito» da «dopo».
  //
  // VELOCE (60 ms): un fotogramma e mezzo a sessanta hertz. È il passo mentre
  // qualcosa si muove. Più lento si vede la barra inseguire la finestra a
  // scatti — parole di Giacomo: «le barre del titolo non seguono bene la
  // finestra se le sposti velocemente».
  //
  // RIPOSO (150 ms): la rete di sicurezza, ed è la sola cosa qui dentro che si
  // paga davvero. Vedi il conto qui sotto.
  static const _attesaMs = 30;
  static const _velocitaMs = 60;

  // ── Il passo di riposo, e perché era il difetto ────────────────────────
  //
  // Era 150 ms: sei letture e mezzo al secondo del compositore, per sempre,
  // anche con la scrivania ferma e nessuno che tocca niente. Misurato l'11
  // agosto 2026 col demone a riposo: **1,05% di un core**, cioè batteria che
  // se ne va senza che succeda niente.
  //
  // Il compositore annuncia da solo tutto quello che conta — finestre aperte,
  // chiuse, spostate col tasto, cambio di scrivania, schermo intero — e quegli
  // eventi passano da `avvia()` qui sotto. L'unica cosa che NON annuncia è il
  // trascinamento col mouse: mentre si tiene premuto e si sposta, la geometria
  // cambia sessanta volte al secondo e il compositore non dice niente.
  //
  // Quindi il passo veloce serve mentre si trascina, e il passo di riposo non
  // serve a niente. Restava come rete: adesso è una rete a maglie larghe (un
  // secondo e mezzo invece di un decimo), e il trascinamento lo si scopre
  // dalla prima lettura che vede la finestra mossa (`motoVero`), che fa
  // passare al passo veloce finché tutto non si ferma.
  static const _riposoMs = 1500;
  static const _calmaMs = 1200;

  // ── Quanto costa il passo di riposo, misurato e non stimato ────────────
  //
  // Avevo scritto «0,06% di un core: si può permettere», calcolandolo dal
  // costo di una lettura. Sbagliato di venti volte. Misurato sul demone vero,
  // con la shell collegata, su venti secondi:
  //
  //     senza il passo di riposo     0,40% di un core
  //     con il passo a 150 ms        1,70% di un core
  //                                  ────────
  //     il passo di riposo costa     1,30% di un core, per sempre
  //
  // E il conto non torna con «0,39 ms per lettura ogni 150 ms», che darebbe
  // 0,26%. Il motivo è che il costo non è nella lettura: è nello SVEGLIARSI.
  // Provato chiedendo tre cose di dimensioni molto diverse —
  //
  //     j/clients        2566 byte    0,390 ms
  //     j/activewindow    851 byte    0,344 ms
  //     j/cursorpos        33 byte    0,290 ms
  //
  // — settantasette volte meno dati per il 26% di tempo in meno. Quasi tutto
  // il costo è tirare il processo fuori dal sonno, riarmare il timer e
  // riportare la CPU da uno stato di riposo profondo. Chiedere MENO non aiuta:
  // l'unica leva è svegliarsi MENO SPESSO.
  //
  // Per questo il passo di riposo è salito a un secondo e mezzo: il
  // trascinamento si scopre dalla prima lettura che vede la finestra mossa,
  // e da lì si va al passo veloce.
  //
  // Come si fa a togliere questo costo per davvero: la barra del titolo come
  // decorazione dentro il compositore. Una decorazione si muove CON la
  // finestra, senza che nessuno guardi e senza che nessuno si svegli. Finché
  // le barre stanno su una superficie separata, questo 1,3% è il prezzo del
  // posto in cui stanno.
  //
  // Nel frattempo si paga solo quando serve: a scrivania vuota non si guarda
  // niente (vedi `_nessunaFinestra`).

  /// Comincia ad ascoltare il compositore. Non interroga niente finché non si
  /// collega qualcuno: un demone senza finestre di Minerva aperte non ha
  /// nessuno a cui raccontare dove sono le altre.
  void avvia() {
    _ascolto = _compositore.events.listen((e) {
      switch (e.type) {
        case CompositorEventType.windowOpened:
        case CompositorEventType.windowClosed:
        case CompositorEventType.windowFocused:
        case CompositorEventType.windowMoved:
        case CompositorEventType.windowTitleChanged:
        case CompositorEventType.fullscreenChanged:
        case CompositorEventType.workspaceChanged:
          _prestoMa(); // le finestre
          break;
        case CompositorEventType.monitorChanged:
          // Qui non si accorpa e non si aspetta: cambia lo spazio in cui le
          // finestre possono stare, e da quello dipende dove si ferma
          // «ingrandisci». Un ritardo qui si vede come una finestra che
          // finisce sotto la barra della scrivania.
          spingiMonitor();
          _prestoMa();
          break;
      }
    });
  }

  /// Quanti processi di Minerva sono collegati adesso.
  ///
  /// Il demone lo sa, e da qui decide se guardare o stare fermo. Non è
  /// un'ottimizzazione da poco: senza questo, un demone acceso a scrivania
  /// vuota interrogherebbe il compositore per sempre.
  void clienti(int quanti) {
    final prima = _clienti;
    _clienti = quanti;

    if (quanti > 0 && prima == 0) {
      _riprendi();
    } else if (quanti == 0) {
      _passo?.cancel();
      _passo = null;
      _calma?.cancel();
      _veloce = false;
    }
  }

  /// Manda tutto a chi guarda, adesso, anche se non è cambiato niente.
  ///
  /// Si chiama quando si collega un processo nuovo. È il pezzo che sarebbe
  /// facile dimenticare: il gestore file che si apre deve trovare l'elenco
  /// delle finestre SUBITO, non al prossimo evento del compositore — e se sta
  /// aperto da solo su una scrivania ferma, il prossimo evento non arriva.
  Future<void> spingiTutto() async {
    _ultimeFinestre = '';
    _ultimiMonitor = '';
    _nessunaFinestra = false; // da riscoprire con la lettura qui sotto
    await spingiMonitor();
    await spingiFinestre();
  }

  void _prestoMa() {
    _attesa?.cancel();
    _attesa = Timer(const Duration(milliseconds: _attesaMs), spingiFinestre);
  }

  /// Interroga il compositore e manda il risultato se è diverso da prima.
  Future<void> spingiFinestre() async {
    if (_clienti == 0) return;

    // Due letture che si accavallano direbbero la stessa cosa due volte, e
    // nell'ordine sbagliato: la seconda partita può rispondere prima.
    //
    // ── Ma chi arriva durante una lettura non si butta (30 settembre 2026) ──
    //
    // Si tornava indietro e basta. Se la lettura in corso aveva fotografato
    // la scrivania PRIMA dell'evento — l'ultima finestra chiusa e una nuova
    // aperta subito dopo — rispondeva `[]`, `_nessunaFinestra` fermava anche
    // il passo di riposo, e la finestra nuova restava senza barra fino al
    // prossimo evento. Si segna che va rifatta, e la si rifà una volta alla
    // fine: lo stesso rimedio di `SystemStateService.leggi`.
    if (_inLettura) {
      _daRileggere = true;
      return;
    }
    _inLettura = true;
    String json;
    try {
      json = await _compositore.getClientsRaw();
    } finally {
      _inLettura = false;
    }
    if (_daRileggere) {
      _daRileggere = false;
      scheduleMicrotask(spingiFinestre);
    }

    if (json.isEmpty) return;

    // ── A scrivania vuota non si guarda niente ─────────────────────────
    //
    // Senza finestre non c'è niente da trascinare, quindi la rete di
    // sicurezza non serve e il suo 1,3% di core non si paga. Ed è proprio il
    // caso in cui contava di più: un portatile lasciato sulla scrivania
    // vuota, che è dove la batteria si nota.
    //
    // Riparte da sola: `openwindow` è un evento, e arriva.
    _nessunaFinestra = json.trimLeft().startsWith('[]');
    if (_nessunaFinestra) {
      _passo?.cancel();
      _passo = null;
      _veloce = false;
      _calma?.cancel();
    }

    if (json == _ultimeFinestre) return;
    _ultimeFinestre = json;
    _finestre.add(json);

    // ── Un titolo che cambia non è una finestra che si muove ───────────
    //
    // Qui bastava «è cambiato qualcosa» per passare al passo veloce. Ma nel
    // testo che arriva dal compositore c'è anche il TITOLO di ogni finestra,
    // e ci sono programmi che lo riscrivono in continuazione: un terminale
    // con dentro un lavoro che gira ci mette una rotellina animata, un
    // browser ci mette il numero dei messaggi, un lettore il minuto della
    // canzone. Nessuno di loro si sta muovendo di un pixel.
    //
    // Il risultato era che bastava UNA finestra col titolo animato per
    // tenere il demone a sessanta millisecondi PER SEMPRE — e non solo lui:
    // ogni lettura diversa viene spedita a tutte le finestre di Minerva, che
    // rifanno i conti delle barre. Sedici volte al secondo, a scrivania
    // ferma. Trovato il 30 luglio 2026 misurando il demone a riposo: 96
    // letture al secondo dove il passo di riposo ne prevede sette.
    //
    // Si accelera solo se è cambiato qualcosa TOLTI i titoli. Il titolo si
    // manda comunque — la barra deve mostrarlo — ma al passo di riposo.
    final firma = senzaTitoli(json);
    final motoVero = firma != _ultimaFirma;
    _ultimaFirma = firma;
    if (!_nessunaFinestra && motoVero) _acceleraEAspetta();
  }

  /// Il testo delle finestre senza i titoli, per capire se si è mosso
  /// qualcosa. Si cancella il VALORE e non la chiave, così due finestre che
  /// si scambiano di posto restano distinguibili.
  ///
  /// L'espressione regolare tiene conto delle virgolette protette: un titolo
  /// che contiene `\"` non deve troncare la cancellazione a metà, o il resto
  /// della riga — dove c'è la geometria — finirebbe dentro al titolo e ogni
  /// spostamento diventerebbe invisibile.
  ///
  /// minerva-wayland scrive il titolo come `titolo`. Il difetto che questo
  /// filtro impedisce è UNA finestra col titolo animato che tiene il demone a
  /// sessanta millisecondi per sempre — e un filtro che non trova niente non
  /// dà errore: lascia solo passare tutto.
  static final RegExp _titoli =
      RegExp(r'"titolo"\s*:\s*"(?:\\.|[^"\\])*"');

  static String senzaTitoli(String json) =>
      json.replaceAll(_titoli, '"titolo": ""');

  Future<void> spingiMonitor() async {
    if (_clienti == 0) return;
    final json = await _compositore.getMonitorsRaw();
    if (json.isEmpty || json == _ultimiMonitor) return;
    _ultimiMonitor = json;
    _monitor.add(json);
  }

  void _acceleraEAspetta() {
    if (!_veloce) {
      _veloce = true;
      _riprendi();
    }
    _calma?.cancel();
    _calma = Timer(const Duration(milliseconds: _calmaMs), () {
      _veloce = false;
      _riprendi();
    });
  }

  void _riprendi() {
    _passo?.cancel();
    if (_clienti == 0 || _nessunaFinestra) return;
    _passo = Timer.periodic(
      Duration(milliseconds: _veloce ? _velocitaMs : _riposoMs),
      (_) => spingiFinestre(),
    );
  }

  Future<void> ferma() async {
    _attesa?.cancel();
    _passo?.cancel();
    _calma?.cancel();
    await _ascolto?.cancel();
    await _finestre.close();
    await _monitor.close();
  }
}
