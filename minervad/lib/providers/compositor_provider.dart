import 'dart:async';

/// Tipi di eventi sollevati dal compositor.
enum CompositorEventType {
  workspaceChanged,
  windowOpened,
  windowClosed,
  windowFocused,

  // ── Perché questi tre contano quanto i primi ──────────────────────────
  //
  // La dock, l'Alt+Tab e la garanzia sullo spazio vogliono sapere dove è
  // finita una finestra, come si chiama adesso e se è a schermo intero. Il
  // compositore li annuncia: ascoltarli costa zero e arriva prima che
  // accorgersene guardando.
  windowMoved,
  windowTitleChanged,
  fullscreenChanged,

  /// Cambia lo spazio utile: un monitor in più, uno in meno, o una zona
  /// riservata diversa. Da qui dipende dove si ferma «ingrandisci».
  monitorChanged,
}

/// Rappresenta un evento sollevato dal compositor.
class CompositorEvent {
  final CompositorEventType type;
  final dynamic payload;

  CompositorEvent({required this.type, this.payload});
}

/// Modello astratto per descrivere lo stato di un workspace.
class WorkspaceState {
  final int id;
  final String name;
  final bool isActive;
  final int windowsCount;

  WorkspaceState({
    required this.id,
    required this.name,
    required this.isActive,
    required this.windowsCount,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isActive': isActive,
        'windowsCount': windowsCount,
      };
}

/// Quello che il demone sa chiedere al compositore. Oggi l'unica
/// implementazione è `MinervaProvider`.
abstract class CompositorProvider {
  /// Stream di eventi sollevati dal compositor.
  Stream<CompositorEvent> get events;

  // ── Solo domande, nessun ordine ──────────────────────────────────────
  //
  // Qui c'erano anche `switchWorkspace`, `closeWindow`, `focusWindow` e
  // `getActiveWindow`: quattro VERBI. Sono usciti il 23 agosto 2026, e non
  // per fare pulizia — per scegliere una regola e scriverla:
  //
  //     il demone OSSERVA il compositore, la shell lo COMANDA.
  //
  // Erano diventati irraggiungibili da soli, quando la shell si è fatta la
  // sua porta (`minerva-shell/core/Compositore.qml`) e ha smesso di passare
  // di qui. Nessuno li chiamava più: restavano come una seconda strada per
  // fare la stessa cosa, e due strade per la stessa cosa divergono sempre —
  // è già successo in questo progetto, e nessuno se ne accorge finché non fa
  // male.
  //
  // Per questo `MinervaProvider` ha tre metodi invece di sette: un
  // compositore deve saper RISPONDERE, non obbedire.

  /// Recupera la lista corrente dei workspace con il loro stato.
  Future<List<WorkspaceState>> getWorkspaces();

  // ── `dispatch()` non c'è più, ed è una buona notizia ──────────────────
  //
  // Qui c'era `dispatch(dispatcher, args)` con accanto `allowedDispatchers`:
  // una lista bianca di ventidue parole di Hyprland — `togglefloating`,
  // `movetoworkspacesilent`, `cyclenext` — **dentro l'interfaccia che
  // dovrebbe essere neutra**. Un'astrazione che nomina il concreto non
  // astrae: descrive.
  //
  // Ed era codice morto. Il comando del bus che la usava (`window_action`)
  // non l'ha chiamato **mai nessuno**: verificato il 19 agosto 2026 anche
  // nella storia di git. La shell passa da `core/Compositore.qml`, che parla
  // al compositore per conto suo.
  //
  // Tolto: l'interfaccia smette di parlare Hyprland, e sparisce una via per
  // far eseguire comandi del compositore a chi arriva dal socket.
  //
  // Se un domani servisse davvero, si aggiunge un METODO per l'intenzione
  // («centra la finestra»), non un passaggio per nome.

  // ── Le due letture grezze, e perché sono grezze ───────────────────────
  //
  // Tornano il JSON del compositore così com'è, senza tradurlo in oggetti
  // Dart. È deliberato, e va contro l'istinto: un provider dovrebbe
  // nascondere il compositore dietro un modello suo.
  //
  // Solo che chi consuma questi due dati è `core/Compositore.qml`, che ha già
  // la sua lettura — matura, provata, e piena di casi che sono costati settimane
  // (la finestra ridotta a icona che vive in un workspace speciale, il titolo
  // troppo lungo che diventa la classe, `focusHistoryID` per sapere chi ha il
  // fuoco, il bordo disegnato FUORI dal rettangolo). Tradurre qui vorrebbe
  // dire riscrivere tutto quello in Dart e tenere le due versioni d'accordo
  // per sempre: due posti dove sbagliare invece di uno.
  //
  // Il giorno in cui arriva un secondo compositore, il lavoro è tradurre il
  // SUO formato in questo — che è lavoro vero, ma è lavoro in un posto solo.

  /// L'elenco delle finestre, nel formato JSON del compositore.
  /// Torna `'[]'` e non solleva mai: chi la chiama sta dentro un timer.
  Future<String> getClientsRaw();

  /// I monitor con le loro zone riservate, nel formato JSON del compositore.
  /// Torna `'[]'` e non solleva mai.
  Future<String> getMonitorsRaw();

  /// Avvia l'ascolto degli eventi dal compositor.
  Future<void> start();

  /// Ferma l'ascolto e chiude le risorse.
  Future<void> stop();
}
