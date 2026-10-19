import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Lo spettro di quello che esce dalle casse, per l'equalizzatore della
/// barra Liquid.
///
/// Richiesta del manutentore, 18 ottobre 2026: «in liquid vorrei poter vedere
/// l'effetto onde o effetto equalizzatore nella barra dove sta il calendario
/// con il titolo di quello che sta riproducendo». Le barrette di prima erano
/// un'animazione: si muovevano uguali con la musica e col silenzio. Queste
/// seguono il suono vero, di qualunque lettore (Media, il browser, Spotify).
///
/// ── Cosa succede all'audio ───────────────────────────────────────────────
///
/// `parec` legge il «monitor» dell'uscita predefinita: la copia di ciò che
/// va alle casse, non il microfono. Il suono resta in questo processo, non
/// si salva e non si manda a nessuno: alla barra arrivano solo [bande]
/// numeri da 0 a 100, una trentina di volte al secondo.
///
/// Si legge solo mentre qualcuno guarda (`iscrivi`/`disiscrivi`), come il
/// monitor di sistema: con la barra nascosta o la musica ferma `parec` non
/// gira.
class SpettroService {
  SpettroService({
    this.bande = 16,
    List<String>? comando,
    this.frequenza = 44100,
  }) : comando = comando ??
            [
              'parec',
              '--device=@DEFAULT_MONITOR@',
              '--format=float32le',
              '--rate=$frequenza',
              '--channels=1',
              '--raw',
              '--latency-msec=30',
              '--client-name=Minerva',
              '--stream-name=Equalizzatore della barra',
            ];

  final int bande;
  final List<String> comando;
  final int frequenza;

  final _uscita = StreamController<List<int>>.broadcast();

  /// Le bande, da 0 a 100, dai bassi agli acuti.
  Stream<List<int>> get livelli => _uscita.stream;

  /// Falso se `parec` non c'è o non parte: la barra torna all'animazione.
  bool get disponibile => _disponibile;
  bool _disponibile = true;

  int _iscritti = 0;
  Process? _processo;
  Timer? _riprova;
  bool _chiuso = false;

  void iscrivi() {
    if (_chiuso) return;
    if (_iscritti++ == 0) unawaited(_avvia());
  }

  void disiscrivi() {
    if (_iscritti == 0) return;
    if (--_iscritti == 0) _ferma();
  }

  Future<void> chiudi() async {
    _chiuso = true;
    _iscritti = 0;
    _ferma();
    await _uscita.close();
  }

  Future<void> _avvia() async {
    if (_chiuso || _iscritti == 0 || _processo != null) return;
    final analizzatore = Analizzatore(bande: bande, frequenza: frequenza);
    final Process p;
    try {
      p = await Process.start(comando.first, comando.skip(1).toList());
    } on ProcessException {
      _disponibile = false;
      return;
    }
    if (_chiuso || _iscritti == 0) {
      p.kill();
      return;
    }
    _disponibile = true;
    _processo = p;
    p.stderr.drain<void>().ignore();
    var resto = Uint8List(0);
    var silenzio = 0;
    p.stdout.listen((pezzo) {
      // I campioni sono float a 4 byte: un pezzo può tagliarne uno a metà.
      final tutto = Uint8List(resto.length + pezzo.length)
        ..setAll(0, resto)
        ..setAll(resto.length, pezzo);
      final interi = tutto.length ~/ 4 * 4;
      final campioni = Float32List.view(
          Uint8List.fromList(tutto.sublist(0, interi)).buffer);
      resto = tutto.sublist(interi);
      for (final livelli in analizzatore.aggiungi(campioni)) {
        // Nel silenzio si manda un fotogramma di zeri e poi si tace: la barra
        // non deve ricevere trenta messaggi al secondo per non disegnare niente.
        final muto = livelli.every((v) => v == 0);
        silenzio = muto ? silenzio + 1 : 0;
        if (silenzio <= 1 && !_uscita.isClosed) _uscita.add(livelli);
      }
    }, onDone: () {
      if (identical(_processo, p)) _processo = null;
      // Un `parec` caduto (il server audio riavviato) si rilancia, con calma.
      if (!_chiuso && _iscritti > 0) {
        _riprova?.cancel();
        _riprova = Timer(const Duration(seconds: 3), () => unawaited(_avvia()));
      }
    });
  }

  void _ferma() {
    _riprova?.cancel();
    _riprova = null;
    final p = _processo;
    _processo = null;
    p?.kill();
    if (!_uscita.isClosed) _uscita.add(List<int>.filled(bande, 0));
  }
}

/// Da campioni a bande: FFT su 2048 campioni ogni 1/30 di secondo, bande
/// distribuite come le sente l'orecchio (logaritmiche, 50 Hz – 14 kHz),
/// livello in decibel con un guadagno che si adatta al volume, salita svelta
/// e discesa morbida. Pura: le prove la nutrono con un seno.
class Analizzatore {
  Analizzatore({required this.bande, required this.frequenza})
      : _passo = frequenza ~/ 30 {
    for (var i = 0; i < _n; i++) {
      _finestra[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (_n - 1));
    }
    final basso = math.log(50), alto = math.log(14000);
    for (var b = 0; b <= bande; b++) {
      final f = math.exp(basso + (alto - basso) * b / bande);
      _bordi.add(math.max(1, (f / frequenza * _n).round()));
    }
    _valori = List<double>.filled(bande, 0);
  }

  static const _n = 2048;
  final int bande;
  final int frequenza;
  final int _passo;
  final _finestra = Float64List(_n);
  final _bordi = <int>[];
  final _anello = Float64List(_n);
  int _scritti = 0, _daUltimo = 0;
  late List<double> _valori;
  double _massimo = -60;

  /// Aggiunge campioni; per ogni fotogramma completato, le bande (0–100).
  List<List<int>> aggiungi(List<double> campioni) {
    final fuori = <List<int>>[];
    for (final c in campioni) {
      _anello[_scritti % _n] = c.isFinite ? c : 0;
      _scritti++;
      if (++_daUltimo >= _passo && _scritti >= _n) {
        _daUltimo = 0;
        fuori.add(_fotogramma());
      }
    }
    return fuori;
  }

  List<int> _fotogramma() {
    final re = Float64List(_n), im = Float64List(_n);
    final inizio = _scritti % _n;
    for (var i = 0; i < _n; i++) {
      re[i] = _anello[(inizio + i) % _n] * _finestra[i];
    }
    fft(re, im);
    final db = List<double>.filled(bande, -120);
    for (var b = 0; b < bande; b++) {
      final da = _bordi[b], a = math.max(_bordi[b + 1], da + 1);
      var somma = 0.0;
      for (var k = da; k < a && k < _n ~/ 2; k++) {
        somma += re[k] * re[k] + im[k] * im[k];
      }
      final potenza = somma / (a - da) / (_n * _n / 16);
      // +3 dB per ottava attorno a 1 kHz, come gli analizzatori da studio: la
      // musica ha poca energia negli acuti, e senza la parte rosa della barra
      // resterebbe quasi sempre spenta.
      final centro = (da + a) / 2 * frequenza / _n;
      db[b] = 10 * math.log(potenza + 1e-12) / math.ln10 +
          3 * math.log(centro / 1000) / math.ln2;
    }
    // Il guadagno insegue il punto più forte: un brano piano e uno forte
    // riempiono la barra allo stesso modo. Scende piano (un secondo e mezzo
    // per 10 dB), così un attacco dopo una pausa non sembra un'esplosione.
    final picco = db.reduce(math.max);
    _massimo = picco > _massimo ? picco : _massimo - 0.22;
    final soglia = math.max(_massimo, -50.0);
    final livelli = List<int>.filled(bande, 0);
    for (var b = 0; b < bande; b++) {
      var v = ((db[b] - (soglia - 42)) / 42).clamp(0.0, 1.0);
      // Sotto -75 dB è silenzio, qualunque sia il guadagno.
      if (db[b] < -75) v = 0;
      final prima = _valori[b];
      _valori[b] = v > prima ? prima + (v - prima) * 0.65 : prima + (v - prima) * 0.18;
      livelli[b] = (_valori[b] * 100).round().clamp(0, 100);
    }
    return livelli;
  }

  /// FFT iterativa radix-2, sul posto. `re.length` è una potenza di 2.
  static void fft(Float64List re, Float64List im) {
    final n = re.length;
    for (var i = 1, j = 0; i < n; i++) {
      var bit = n >> 1;
      for (; j & bit != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        var t = re[i];
        re[i] = re[j];
        re[j] = t;
        t = im[i];
        im[i] = im[j];
        im[j] = t;
      }
    }
    for (var len = 2; len <= n; len <<= 1) {
      final angolo = -2 * math.pi / len;
      final wr = math.cos(angolo), wi = math.sin(angolo);
      for (var i = 0; i < n; i += len) {
        var cr = 1.0, ci = 0.0;
        for (var k = 0; k < len ~/ 2; k++) {
          final a = i + k, b = a + len ~/ 2;
          final tr = re[b] * cr - im[b] * ci, ti = re[b] * ci + im[b] * cr;
          re[b] = re[a] - tr;
          im[b] = im[a] - ti;
          re[a] += tr;
          im[a] += ti;
          final ncr = cr * wr - ci * wi;
          ci = cr * wi + ci * wr;
          cr = ncr;
        }
      }
    }
  }
}
