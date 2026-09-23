import 'dart:async';

/// Rappresenta un evento generico nel bus degli eventi di Minerva.
class MinervaEvent {
  final String type;
  final dynamic payload;
  final DateTime timestamp;

  MinervaEvent({required this.type, this.payload}) : timestamp = DateTime.now();

  Map<String, dynamic> toJson() => {
        'type': type,
        'payload': payload,
        'timestamp': timestamp.toIso8601String(),
      };

  @override
  String toString() => '[MINERVA][EVENT][$type] $payload';
}

/// Il bus degli eventi: chi ha qualcosa da dire lo pubblica qui, chi vuole
/// saperlo si iscrive. È il punto da cui passa tutto, e per questo le cose che
/// fa in più rispetto a un `StreamController` nudo sono tutte difese.
///
/// ── 1. Pubblicare dopo la chiusura non fa cadere il demone ────────────────
///
/// Un `StreamController` chiuso a cui si aggiunge un evento lancia
/// `StateError`. Alla chiusura del demone i servizi non si fermano tutti nello
/// stesso istante: un timer già in coda che pubblica mezzo secondo dopo
/// `dispose()` fa morire il processo **durante l'arresto**, con un'eccezione
/// che nessuno legge perché il computer si sta spegnendo. In modalità
/// `--test-start` lo stesso difetto trasforma un'autodiagnosi in un
/// fallimento che non c'entra niente con ciò che si stava provando.
///
/// Si ignora e si CONTA, invece: chiudere vuol dire «non m'interessa più», ma
/// se il conto non è zero l'ordine di arresto è sbagliato e va detto.
///
/// ── 2. Un ascoltatore che si rompe non zittisce il bus ────────────────────
///
/// Su uno stream broadcast, un'eccezione lanciata dentro un `listen` non torna
/// a chi ha pubblicato: finisce alla zona, cioè in pratica da nessuna parte.
/// Gli altri iscritti continuano a ricevere, quindi il guasto è **parziale e
/// silenzioso** — il tipo che si scopre settimane dopo. Con `ascolta()` si
/// stampa almeno una riga con il nome dell'iscritto e il tipo dell'evento.
///
/// ── 3. Il conto degli eventi ──────────────────────────────────────────────
///
/// Non è statistica: è la prima cosa da guardare quando il demone consuma a
/// riposo. Un evento che passa mille volte al minuto è un difetto, e senza
/// questo conto non si vede. Vedi la lezione già imparata sul risvegliarsi.
class EventBus {
  final _streamController = StreamController<MinervaEvent>.broadcast();

  bool _chiuso = false;
  final Map<String, int> _conteggio = {};
  int _dopoLaChiusura = 0;

  /// Consente di ascoltare gli eventi pubblicati.
  Stream<MinervaEvent> get stream => _streamController.stream;

  bool get chiuso => _chiuso;

  /// Quanti eventi sono passati, per tipo. Sola lettura.
  Map<String, int> get conteggio => Map.unmodifiable(_conteggio);

  /// Quanti sono stati pubblicati DOPO la chiusura, cioè buttati.
  int get pubblicatiDopoLaChiusura => _dopoLaChiusura;

  /// Consente di filtrare gli eventi per tipo.
  ///
  /// Ogni chiamata crea uno stream derivato: serve a iscriversi una volta, non
  /// va chiamata dentro un ciclo o a ogni richiesta.
  Stream<MinervaEvent> filter(String type) {
    return _streamController.stream.where((event) => event.type == type);
  }

  /// Pubblica un nuovo evento nel bus.
  ///
  /// Restituisce `false` se il bus è chiuso e l'evento è stato buttato: chi
  /// vuole può accorgersene, invece di scoprirlo da un'eccezione a metà
  /// arresto.
  bool publish(MinervaEvent event) {
    if (_chiuso || _streamController.isClosed) {
      _dopoLaChiusura++;
      return false;
    }
    _conteggio[event.type] = (_conteggio[event.type] ?? 0) + 1;
    _streamController.add(event);
    return true;
  }

  /// Iscrizione con la rete sotto: se il gestore lancia, lo si dice per nome e
  /// gli altri iscritti non ne risentono.
  ///
  /// `stream.listen` resta per chi la rete non la vuole (o deve trasformare lo
  /// stream), ma dentro il demone è questa la forma da preferire.
  StreamSubscription<MinervaEvent> ascolta(
    void Function(MinervaEvent) gestore, {
    String chi = '?',
  }) {
    return _streamController.stream.listen((evento) {
      try {
        gestore(evento);
      } catch (e, dove) {
        print('[MINERVA][BUS][ERRORE] «$chi» è caduto su ${evento.type}: $e');
        print(dove);
      }
    });
  }

  /// Chiude il canale di comunicazione.
  Future<void> dispose() async {
    if (_chiuso) return;
    _chiuso = true;
    await _streamController.close();
    if (_dopoLaChiusura > 0) {
      print('[MINERVA][BUS][WARN] $_dopoLaChiusura eventi pubblicati dopo la '
          'chiusura: qualcosa si ferma nell\'ordine sbagliato.');
    }
  }
}
