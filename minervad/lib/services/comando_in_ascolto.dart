import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Un programma che resta acceso e scrive una riga quando qualcosa cambia:
/// `gio mount -o` (dischi e telefoni), `nmcli monitor` (rete),
/// `gdbus monitor` (Bluetooth).
///
/// È l'alternativa al rileggere ogni tanto. Fino al 20 ottobre 2026 lo stato
/// della rete e del Bluetooth si rileggeva ogni dodici secondi lanciando
/// `nmcli`, la lettura di BlueZ e `sh`+`rfkill`+`awk`: cinque processi a
/// giro per tutta la sessione, anche a computer fermo, e un cambio si vedeva
/// fino a dodici secondi dopo. Un ascoltatore costa un processo che dorme
/// (misurati: `nmcli monitor` 3,6 MB di PSS, `gdbus monitor` 0,8 MB, zero CPU
/// a riposo) e dice il cambio subito.
///
/// Le righe vicine si accorpano ([attesa]): chi ascolta rilegge lo stato
/// intero una volta per gruppo di cambi, non una per riga.
///
/// Il ciclo di vita è quello che `ArrivoDispositivi` aveva già messo a punto
/// (STA-014, 19 ottobre 2026): avvii concorrenti condivisi, poche ripartenze
/// se il programma muore, e all'arresto TERM, attesa, KILL — nessun processo
/// lasciato orfano.
class ComandoInAscolto {
  ComandoInAscolto(
    this.comando,
    this.argomenti, {
    this.attesa = const Duration(milliseconds: 300),
    this.rigaUtile,
    this.segnalaUscita = false,
  });

  final String comando;
  final List<String> argomenti;
  final Duration attesa;

  /// Quali righe contano; senza, tutte.
  final bool Function(String riga)? rigaUtile;

  /// Se vero, anche la morte del programma è un cambio: chi ascolta rilegge
  /// lo stato da sé finché l'ascoltatore non riparte (vedi [acceso]).
  final bool segnalaUscita;

  final _cambi = StreamController<void>.broadcast();

  /// Un segnale per ogni gruppo di cambiamenti.
  Stream<void> get cambi => _cambi.stream;

  /// Vero mentre il programma è acceso e i cambi arrivano da lui.
  bool get acceso => _monitor != null;

  Process? _monitor;
  Timer? _calma, _riprova;
  Future<void>? _avvio, _arresto;
  bool _fermo = false;
  int _ripartenze = 0;

  static const Map<String, String> _ambiente = {'LC_ALL': 'C', 'LANG': 'C'};

  String get _nome => [comando, ...argomenti].join(' ');

  Future<void> start() {
    if (_fermo || _monitor != null) return Future<void>.value();
    return _avvio ??= _avvia().whenComplete(() {
      _avvio = null;
    });
  }

  Future<void> _avvia() async {
    try {
      final p = await Process.start(comando, argomenti, environment: _ambiente);
      _monitor = p;
      p.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(_riga, onError: (Object _) {});
      p.stderr.drain<void>().catchError((Object _) {});
      unawaited(p.exitCode.then((_) {
        if (identical(_monitor, p)) _monitor = null;
        if (segnalaUscita) _segnala();
        // Il servizio riavviato, il bus caduto: si riprova, ma non
        // all'infinito — un programma che muore subito non deve diventare un
        // processo lanciato ogni cinque secondi per tutta la sessione.
        if (!_fermo && _ripartenze < 5) {
          _ripartenze++;
          _riprova?.cancel();
          _riprova = Timer(const Duration(seconds: 5), start);
        }
      }));
    } on ProcessException catch (e) {
      print('[MINERVA][ASCOLTO][WARN] $_nome non parte: ${e.message}');
    }
  }

  void _riga(String riga) {
    if (_fermo) return;
    final utile = rigaUtile;
    if (utile != null && !utile(riga)) return;
    _segnala();
  }

  void _segnala() {
    _calma?.cancel();
    _calma = Timer(attesa, () {
      if (!_fermo && !_cambi.isClosed) _cambi.add(null);
    });
  }

  Future<void> stop() {
    _fermo = true;
    _calma?.cancel();
    _riprova?.cancel();
    return _arresto ??= _ferma();
  }

  Future<void> _ferma() async {
    // Acquisire anche il processo che Process.start non ha ancora restituito.
    await _avvio;
    final monitor = _monitor;
    if (monitor != null) {
      monitor.kill(ProcessSignal.sigterm);
      try {
        await monitor.exitCode.timeout(const Duration(seconds: 1));
      } on TimeoutException {
        monitor.kill(ProcessSignal.sigkill);
        await monitor.exitCode.timeout(const Duration(seconds: 1));
      }
    }
    await _cambi.close();
  }
}
