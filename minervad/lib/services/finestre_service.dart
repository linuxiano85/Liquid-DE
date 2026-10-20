import 'dart:async';

import '../providers/compositor_provider.dart';
import '../providers/minerva/minerva_provider.dart';

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
///  2. **Annuncia anche il trascinamento col mouse.** Fino al 20 ottobre
///     2026 no: mentre si teneva premuto la geometria cambiava senza eventi,
///     e qui c'era un timer — lento a riposo (1,5 s, l'1,3 % di un core per
///     sempre), veloce a 60 ms appena una lettura vedeva una finestra mossa.
///     Ora minerva-wayland manda «mossa» anche durante la presa, a ogni
///     spostamento, e qui non c'è più nessun timer: si legge solo dopo un
///     evento, e a riposo il demone non si sveglia per le finestre.
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

  /// L'ultima risposta mandata. Serve a non ripetersi: un evento che non
  /// cambia niente (il fuoco sulla finestra che lo aveva già) non produce
  /// nessun messaggio.
  String _ultimeFinestre = '';
  String _ultimiMonitor = '';

  Timer? _attesa;
  int _clienti = 0;
  bool _inLettura = false;
  bool _daRileggere = false;
  bool _fermo = false;
  Future<void>? _arresto;

  // ATTESA (30 ms): gli eventi arrivano a grappoli. Aprire una finestra ne
  // manda tre o quattro in pochi millisecondi (`openwindow`,
  // `changefloatingmode`, `activewindow`, `windowtitle`). Interrogare a ogni
  // evento vorrebbe dire quattro letture per dire quattro volte la stessa
  // cosa. Trenta millisecondi li accorpano e restano sotto la soglia in cui
  // un occhio distingue «subito» da «dopo». Durante un trascinamento le
  // «mossa» arrivano a ogni fotogramma: l'attesa le accorpa allo stesso modo,
  // una lettura ogni 30 ms finché la mano si muove.
  static const _attesaMs = 30;

  /// Comincia ad ascoltare il compositore. Non interroga niente finché non si
  /// collega qualcuno: un demone senza finestre di Minerva aperte non ha
  /// nessuno a cui raccontare dove sono le altre.
  void avvia() {
    if (_fermo || _ascolto != null) return;
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
  /// Il demone lo sa, e da qui decide se leggere o stare fermo: senza
  /// nessuno collegato gli eventi del compositore si lasciano passare, e chi
  /// si collega dopo riceve tutto da `spingiTutto`.
  void clienti(int quanti) {
    if (_fermo) return;
    _clienti = quanti;
    if (quanti == 0) {
      _daRileggere = false;
      _attesa?.cancel();
    }
  }

  /// Manda tutto a chi guarda, adesso, anche se non è cambiato niente.
  ///
  /// Si chiama quando si collega un processo nuovo. È il pezzo che sarebbe
  /// facile dimenticare: il gestore file che si apre deve trovare l'elenco
  /// delle finestre SUBITO, non al prossimo evento del compositore — e se sta
  /// aperto da solo su una scrivania ferma, il prossimo evento non arriva.
  Future<void> spingiTutto() async {
    if (_fermo || _clienti == 0) return;
    _ultimeFinestre = '';
    _ultimiMonitor = '';
    await spingiMonitor();
    await spingiFinestre();
  }

  void _prestoMa() {
    if (_fermo || _clienti == 0) return;
    _attesa?.cancel();
    _attesa = Timer(const Duration(milliseconds: _attesaMs), spingiFinestre);
  }

  /// Interroga il compositore e manda il risultato se è diverso da prima.
  Future<void> spingiFinestre() async {
    if (_fermo || _clienti == 0) return;

    // Due letture che si accavallano direbbero la stessa cosa due volte, e
    // nell'ordine sbagliato: la seconda partita può rispondere prima.
    //
    // ── Ma chi arriva durante una lettura non si butta (30 settembre 2026) ──
    //
    // Si tornava indietro e basta. Se la lettura in corso aveva fotografato
    // la scrivania PRIMA dell'evento — l'ultima finestra chiusa e una nuova
    // aperta subito dopo — rispondeva `[]`, e la finestra nuova restava
    // senza barra fino al prossimo evento. Si segna che va rifatta, e la si
    // rifà una volta alla fine: lo stesso rimedio di `SystemStateService.leggi`.
    if (_inLettura) {
      _daRileggere = true;
      return;
    }
    _inLettura = true;
    String json;
    try {
      final provider = _compositore;
      json = provider is MinervaProvider
          ? (await provider.finestreSeRisponde() ?? '')
          : await provider.getClientsRaw();
    } finally {
      _inLettura = false;
    }
    // Il compositore può rispondere dopo l'uscita dell'ultimo client o dopo
    // ferma(): non pubblicare su stream chiusi né rileggere.
    if (_fermo || _clienti == 0) return;
    if (_daRileggere) {
      _daRileggere = false;
      scheduleMicrotask(spingiFinestre);
    }

    if (json.isEmpty || json == _ultimeFinestre) return;
    _ultimeFinestre = json;
    _finestre.add(json);
  }

  Future<void> spingiMonitor() async {
    if (_fermo || _clienti == 0) return;
    final json = await _compositore.getMonitorsRaw();
    if (_fermo || _clienti == 0) return;
    if (json.isEmpty || json == _ultimiMonitor) return;
    _ultimiMonitor = json;
    _monitor.add(json);
  }

  Future<void> ferma() {
    // Chiusura terminale e sincrona delle ammissioni. Le letture già partite
    // possono terminare, ma al ritorno scartano la risposta. Per riavviare il
    // servizio serve una nuova istanza, come per i suoi stream.
    if (_arresto != null) return _arresto!;
    _fermo = true;
    _clienti = 0;
    _daRileggere = false;
    _attesa?.cancel();
    return _arresto = _chiudiFlussi();
  }

  Future<void> _chiudiFlussi() async {
    await _ascolto?.cancel();
    await _finestre.close();
    await _monitor.close();
  }
}
