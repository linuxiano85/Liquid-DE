// motore.dart — Il motore del Terminale: uno per finestra, fra lo
// pseudo-terminale e la finestra che disegna.
//
// ── Il posto che occupa ────────────────────────────────────────────────────
//
//     finestra QML  ⇄  (stdin/stdout, un JSON per riga)  ⇄  Motore
//     Motore        ⇄  (cornici / byte grezzi)             ⇄  minerva-pty ⇄ shell
//
// Un processo per finestra, e NON dentro il demone: la visura del 7 settembre
// 2026 ha misurato che il demone si ferma 22 ms quando legge `/proc`, e un
// `cat` da un gigabyte non deve poter fermare la scrivania. Qui dentro
// l'emulatore lavora quanto vuole; la finestra riceve solo quello che deve
// disegnare, al massimo sessanta volte al secondo.
//
// ── Il protocollo con la finestra ──────────────────────────────────────────
//
// Dalla finestra (uno per riga, JSON):
//
//     {"t":"tasto","k":"Up","testo":"","ctrl":false,"alt":false,"shift":false}
//     {"t":"misura","c":120,"r":40}
//     {"t":"incolla","testo":"…"}
//     {"t":"comando","riga":"ls -la"}        scrive la riga più Invio
//     {"t":"mouse","x":3,"y":4,"b":0,"tipo":"premi"|"lascia"|"muovi"|"rotella","dy":-1,…}
//     {"t":"scorri","di":-10}                lo scrollback, in righe (0 = torna vivo)
//     {"t":"fuoco","dentro":true}
//     {"t":"chiudi"}
//
// Alla finestra:
//
//     {"t":"pronto","colonne":..,"righe":..}
//     {"t":"righe","tutte":true|false,"scarto":N,"righe":[[i,[[testo,fg,bg,fl],…]],…]}
//     {"t":"cursore","c":..,"r":..,"v":true,"f":0}
//     {"t":"stato","alt":false,"titolo":"…","cartella":"…","mouse":0,"scrollback":N}
//     {"t":"blocco","tipo":"A"|"B"|"C"|"D","riga":N,"codice":0,"comando":"…"}
//     {"t":"campanello"}
//     {"t":"fine","codice":0}
//
// Le righe: solo quelle cambiate, e ogni riga è una lista di TRATTI — celle
// vicine con lo stesso colore e le stesse bandiere, fuse. Un carattere largo
// è un tratto da solo con `flLargo` addosso: chi disegna sa che occupa due
// celle. Le metà destre non si mandano.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'emulatore.dart';
import 'tastiera.dart';
import 'completamento.dart';
import 'dizionario.dart';
import 'guardia.dart';
import 'predittore.dart';
import 'storia.dart';
import 'blocchi_automatici.dart';

Future<Map<String, dynamic>> _calcolaPredizione(
    String testo, String cartella, String? percorso, List<VoceStoria> voci) {
  return Isolate.run(() {
    final storia = Storia()..voci.addAll(voci);
    return Predittore(storia: storia, dizionario: percorso == null
        ? Dizionario.vuoto() : Dizionario.daFile(percorso))
        .proponi(testo, cartella).aMappa();
  });
}

class Motore {
  Motore({
    required this.percorsoPty,
    required this.fuori,
    int colonne = 80,
    int righe = 24,
    this.cartella,
    this.esegui,
    this.shell,
    this.integrazione,
    this.percorsoDizionario,
    int scrollback = 10000,
  }) : emulatore = Emulatore(
            colonne: colonne, righe: righe, scrollbackMassimo: scrollback);

  final String percorsoPty;
  final IOSink fuori;
  final String? cartella;
  final String? esegui;
  final String? shell;
  /// La cartella `config/terminale` con i ganci per zsh e bash, o null per
  /// una shell lasciata com'è (niente blocchi: dichiarato, non nascosto).
  final String? integrazione;
  final String? percorsoDizionario;
  bool _predizioneAttiva = false;
  Map<String, dynamic>? _richiestaPredizione;
  String? _incollaDaConfermare;
  final _storiaSuggerimenti = Storia(); // Solo sessione, mai password dal PTY.

  // Un solo lavoro alla volta; durante la scansione resta solo l'ultima
  // richiesta. Il filesystem non deve fermare l'emulazione del PTY.
  Future<void> _predici(Map<String, dynamic> richiesta) async {
    _richiestaPredizione = richiesta;
    if (_predizioneAttiva) return;
    _predizioneAttiva = true;
    try {
      while (_richiestaPredizione != null) {
        final m = _richiestaPredizione!;
        _richiestaPredizione = null;
        final testo = m['testo'] is String ? m['testo'] as String : '';
        final dir = emulatore.cartella.isNotEmpty
            ? emulatore.cartella : (cartella ?? Directory.current.path);
        final percorso = percorsoDizionario;
        final risultato = await _calcolaPredizione(testo, dir, percorso,
            List<VoceStoria>.of(_storiaSuggerimenti.voci));
        if (_richiestaPredizione == null) {
          _manda({'t': 'predizione', ...risultato});
        }
      }
    } catch (_) {
      _manda({'t': 'predizione', 'testo': '', 'fantasma': '', 'proposte': []});
    } finally {
      _predizioneAttiva = false;
    }
  }
  final Emulatore emulatore;
  late final _blocchiAutomatici = BlocchiAutomatici(emulatore, (b) {
    _blocchiDaMandare[b['id'] as int] = b;
    if (_blocchiDaMandare.length > 100) {
      _blocchiDaMandare.remove(_blocchiDaMandare.keys.first);
    }
  });
  final _blocchiDaMandare = <int, Map<String, dynamic>>{};
  String _shellBlocchi = '';

  Process? _pty;
  Timer? _battito;
  bool _daDisegnare = false;
  bool _tuttoDaMandare = true;
  bool _fuocoDentro = true;
  int _campanelliMandati = 0;

  /// Quante righe di scrollback si stanno guardando: 0 è il vivo.
  int scarto = 0;

  /// Ogni quanto si manda un fotogramma, al massimo. Sedici millisecondi:
  /// sessanta al secondo. Un `cat` produce migliaia di righe al secondo, e
  /// mandarle tutte sarebbe disegnare cose che nessuno vede.
  static const battitoMs = 16;

  Future<void> avvia() async {
    final argomenti = <String>[
      '--colonne', '${emulatore.colonne}',
      '--righe', '${emulatore.righe}',
    ];
    if (cartella != null && cartella!.isNotEmpty) {
      argomenti.addAll(['--cartella', cartella!]);
    }
    if (esegui != null && esegui!.isNotEmpty) {
      argomenti.addAll(['--esegui', esegui!]);
    }
    if (shell != null && shell!.isNotEmpty) {
      argomenti.addAll(['--shell', shell!]);
    }
    // ── L'integrazione con la shell ──────────────────────────────────────
    //
    // zsh prende i marcatori firmati da un `.zshenv` nostro (via `ZDOTDIR`,
    // che il file rimette a posto subito), bash da un `--rcfile` che legge
    // prima il `.bashrc` vero. Le altre shell — fish compreso, che i suoi
    // marcatori OSC 133 li manda da solo ma senza firma — restano un
    // terminale classico.
    final ambiente = <String, String>{};
    final quale = shell != null && shell!.isNotEmpty
        ? shell!
        : (Platform.environment['SHELL'] ?? '/bin/sh');
    final base = quale.split('/').last;
    if (integrazione != null && (base == 'bash' || base == 'zsh') &&
        (esegui == null || esegui!.isEmpty)) {
      _shellBlocchi = base;
      final random = Random.secure();
      final chiave = List.generate(24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      ambiente['MINERVA_BLOCCHI_CHIAVE'] = chiave;
      emulatore.chiaveBlocchi = chiave;
      emulatore.bloccoMinerva = _blocchiAutomatici.marcatore;
      if (base == 'zsh') {
        final orig = Platform.environment['ZDOTDIR'];
        if (orig != null && orig.isNotEmpty) {
          ambiente['MINERVA_ZDOTDIR_ORIG'] = orig;
        }
        ambiente['ZDOTDIR'] = '$integrazione/zsh';
        ambiente['MINERVA_TERMINALE_INTEGRAZIONE'] = integrazione!;
      } else if (base == 'bash') {
        // Non di accesso: da shell di accesso bash ignora `--rcfile`. Il
        // file nostro legge lui `/etc/bash.bashrc` e `~/.bashrc`, come
        // farebbe bash da solo.
        argomenti.addAll(['--non-accesso', '--arg', '--rcfile',
                          '--arg', '$integrazione/bash/integrazione.bash']);
      }
    }
    final p = await Process.start(percorsoPty, argomenti,
        environment: ambiente.isEmpty ? null : ambiente);
    _pty = p;
    // ── Tre cose devono finire prima di dire «fine» ──────────────────────
    //
    // L'uscita del terminale (per disegnare l'ultimo fotogramma), lo
    // stderr di `minerva-pty` (che porta il codice d'uscita, e arriva DOPO
    // la chiusura dello stdout) e il processo stesso. La prima versione
    // mandava `fine` alla chiusura dello stdout, e il codice era sempre −1:
    // la riga `uscita 127` non era ancora stata letta.
    final uscitaFinita = Completer<void>();
    final erroreFinito = Completer<void>();
    p.stdout.listen(_daiTerminale, onDone: () {
      _disegna();
      uscitaFinita.complete();
    });
    p.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((r) {
      // `uscita N` o `segnale N` alla fine; il resto sono avvisi.
      if (r.startsWith('uscita ') || r.startsWith('segnale ')) {
        _codiceUscita = int.tryParse(r.split(' ').last) ?? -1;
        if (r.startsWith('segnale')) _codiceUscita = 128 + _codiceUscita;
      } else {
        stderr.writeln('minerva-terminale: $r');
      }
    }, onDone: erroreFinito.complete);
    Future.wait([uscitaFinita.future, erroreFinito.future, p.exitCode])
        .then((_) => _terminaleChiuso());
    _manda({'t': 'pronto', 'colonne': emulatore.colonne, 'righe': emulatore.righe});
    _mandaStato();
    _segnaDaDisegnare();
  }

  int _codiceUscita = -1;

  /// Byte dal terminale: all'emulatore, poi un fotogramma quando è ora.
  void _daiTerminale(List<int> byte) {
    emulatore.scrivi(byte);
    if (emulatore.risposte.isNotEmpty) {
      _alTerminale(Uint8List.fromList(emulatore.risposte));
      emulatore.risposte.clear();
    }
    _segnaDaDisegnare();
  }

  void _terminaleChiuso() {
    _blocchiAutomatici.termina(-1);
    _disegna();
    _manda({'t': 'fine', 'codice': _codiceUscita});
    fuori.flush().then((_) => exit(0));
  }

  void _segnaDaDisegnare() {
    _daDisegnare = true;
    // Il primo fotogramma parte subito; i seguenti aspettano il battito. È
    // il compromesso di tutti i terminali: reattivo al primo carattere, e
    // mai più di sessanta volte al secondo sotto una raffica.
    _battito ??= Timer(const Duration(milliseconds: battitoMs), () {
      _battito = null;
      if (_daDisegnare) _disegna();
    });
  }

  // ── Il fotogramma ────────────────────────────────────────────────────
  void _disegna() {
    _daDisegnare = false;
    final e = emulatore;
    final tutte = _tuttoDaMandare || e.tuttoSporco || scarto > 0;
    final righe = <List<dynamic>>[];
    if (tutte) {
      for (var i = 0; i < e.righe; i++) {
        righe.add([i, _tratti(_rigaVisibile(i))]);
      }
    } else {
      final ordinate = e.sporche.toList()..sort();
      for (final i in ordinate) {
        if (i >= 0 && i < e.righe) righe.add([i, _tratti(e.riga(i))]);
      }
    }
    _tuttoDaMandare = false;
    if (righe.isNotEmpty) {
      _manda({'t': 'righe', 'tutte': tutte, 'scarto': scarto, 'righe': righe});
    }
    if (e.statoSporco || tutte) {
      final c = e.cursore;
      _manda({
        't': 'cursore',
        'c': c.colonna,
        'r': c.riga,
        'v': c.visibile && scarto == 0,
        'f': c.forma,
      });
      _mandaStato();
    }
    for (final b in _blocchiDaMandare.values) {
      _manda({...b, 'comandoParziale': _shellBlocchi == 'bash'});
    }
    _blocchiDaMandare.clear();
    while (_campanelliMandati < e.campanelli) {
      _campanelliMandati++;
      _manda({'t': 'campanello'});
    }
    e.pulisci();
  }

  void _mandaStato() {
    final e = emulatore;
    _manda({
      't': 'stato',
      'alt': e.sulloSchermoAlternativo,
      'titolo': e.titolo,
      'cartella': e.cartella,
      'mouse': e.modoMouse,
      'incolla': e.incollaFraParentesi,
      'scrollback': e.scrollback.length,
      'scarto': scarto,
    });
  }

  /// La riga `i` di quello che si vede, tenendo conto dello scarto: con
  /// scarto 3 la riga 0 dello schermo è la terzultima dello scrollback.
  Riga _rigaVisibile(int i) {
    if (scarto == 0) return emulatore.riga(i);
    final k = i - scarto;
    if (k >= 0) return emulatore.riga(k);
    final s = emulatore.scrollback;
    final idx = s.length + k;
    return idx >= 0 ? s[idx] : _vuota;
  }

  late final Riga _vuota = Riga(emulatore.colonne);

  /// I tratti di una riga: celle vicine con gli stessi attributi, fuse.
  List<List<dynamic>> _tratti(Riga r) {
    final out = <List<dynamic>>[];
    final n = r.larghezza;
    var x = 0;
    // Le celle vuote in coda non si mandano: a schermo sono il colore di
    // fondo comunque, e su una riga da 200 colonne sono quasi tutte.
    var fine = n;
    while (fine > 0 && r.cp[fine - 1] == 0x20 && r.fl[fine - 1] == 0 &&
        r.bg[fine - 1] == 0) {
      fine--;
    }
    while (x < fine) {
      if (r.fl[x] & flSeguito != 0) {
        x++;
        continue;
      }
      final fg = r.fg[x], bg = r.bg[x], fl = r.fl[x];
      if (fl & flLargo != 0) {
        out.add([String.fromCharCode(r.cp[x]), fg, bg, fl, x]);
        x++;
        continue;
      }
      final b = StringBuffer();
      final inizio = x;
      while (x < fine && r.fg[x] == fg && r.bg[x] == bg && r.fl[x] == fl &&
          r.fl[x] & flLargo == 0) {
        b.writeCharCode(r.cp[x]);
        x++;
      }
      out.add([b.toString(), fg, bg, fl, inizio]);
    }
    return out;
  }

  // ── Dalla finestra ───────────────────────────────────────────────────
  void dallaFinestra(String riga) {
    if (riga.length > 2 * 1024 * 1024) return;
    Map<String, dynamic> m;
    try {
      m = jsonDecode(riga) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    for (final k in ['c', 'r', 'x', 'y', 'b', 'dy', 'di']) {
      final v = m[k];
      if (v != null && (v is! num || !v.isFinite || v.abs() > 1000000000)) return;
    }
    switch (m['t']) {
      case 'predici':
        unawaited(_predici(m));
      case 'prepara':
        final testo = m['testo'];
        if (testo is! String || testo.length > 4096 || contieneControlli(testo)) {
          _manda({'t': 'erroreIncolla', 'motivo': 'Il compositore accetta una sola riga senza caratteri di controllo.'});
          return;
        }
        _storiaSuggerimenti.aggiungi(VoceStoria(
            quando: DateTime.now().millisecondsSinceEpoch,
            cartella: emulatore.cartella, comando: testo, codice: -1, durata: 0));
        _incolla(testo);
      case 'annullaIncolla':
        _incollaDaConfermare = null;
      case 'confermaIncolla':
        final testo = _incollaDaConfermare;
        _incollaDaConfermare = null;
        if (testo != null) _incolla(testo, confermato: true);
      case 'tasto':
        final byte = byteDelTasto(
          nome: '${m['k'] ?? ''}',
          testo: '${m['testo'] ?? ''}',
          ctrl: m['ctrl'] == true,
          alt: m['alt'] == true,
          shift: m['shift'] == true,
          tastiCursoreApplicazione: emulatore.tastiCursoreApplicazione,
        );
        if (byte.isNotEmpty) {
          _tornaVivo();
          _alTerminale(Uint8List.fromList(byte));
        }
      case 'misura':
        final c = (m['c'] as num?)?.toInt() ?? emulatore.colonne;
        final r = (m['r'] as num?)?.toInt() ?? emulatore.righe;
        emulatore.ridimensiona(c, r);
        _pty?.stdin.add(_cornice(1, utf8.encode('${emulatore.colonne} ${emulatore.righe}')));
        _tuttoDaMandare = true;
        _segnaDaDisegnare();
      case 'incolla':
        _incolla('${m['testo'] ?? ''}');
      case 'comando':
        _tornaVivo();
        _alTerminale(Uint8List.fromList(utf8.encode('${m['riga'] ?? ''}\r')));
      case 'mouse':
        _mouse(m);
      case 'scorri':
        final di = (m['di'] as num?)?.toInt() ?? 0;
        final nuovo = di == 0
            ? 0
            : (scarto + di).clamp(0, emulatore.scrollback.length);
        if (nuovo != scarto) {
          scarto = nuovo;
          _tuttoDaMandare = true;
          _segnaDaDisegnare();
        }
      case 'fuoco':
        _fuocoDentro = m['dentro'] == true;
        if (emulatore.eventiFuoco) {
          _alTerminale(Uint8List.fromList((_fuocoDentro ? '\x1b[I' : '\x1b[O').codeUnits));
        }
      case 'chiudi':
        _pty?.kill(ProcessSignal.sighup);
      default:
        break;
    }
  }

  void _tornaVivo() {
    if (scarto != 0) {
      scarto = 0;
      _tuttoDaMandare = true;
      _segnaDaDisegnare();
    }
  }

  /// Un incolla: fra parentesi se il programma le ha chieste (allora sa che
  /// è un incolla e non lo esegue riga per riga), e con i ritorni a capo
  /// normalizzati — un `\n` incollato in una shell è un Invio.
  void _incolla(String testo, {bool confermato = false}) {
    if (testo.length > 65536) {
      _manda({'t': 'erroreIncolla', 'motivo': 'Incolla troppo grande (massimo 65536 caratteri).'});
      return;
    }
    final sicuro = pulisciIncolla(testo);
    if (!confermato) {
      _incollaDaConfermare = null;
      final giudizio = Guardia(casa: Platform.environment['HOME'])
          .giudica(sicuro, cartella: emulatore.cartella);
      if (sicuro.contains('\n') || sicuro != testo || giudizio != null) {
        _incollaDaConfermare = sicuro;
        _manda({'t': 'confermaIncolla', 'testo': sicuro,
          'motivo': giudizio?.motivo ?? 'Testo con più righe o controlli rimossi: verifica prima di incollare.'});
        return;
      }
    }
    _tornaVivo();
    final pulito = sicuro.replaceAll('\n', '\r');
    final b = <int>[];
    if (emulatore.incollaFraParentesi) b.addAll('\x1b[200~'.codeUnits);
    b.addAll(utf8.encode(pulito));
    if (emulatore.incollaFraParentesi) b.addAll('\x1b[201~'.codeUnits);
    _alTerminale(Uint8List.fromList(b));
    _manda({'t': 'incollato'});
  }

  void _mouse(Map<String, dynamic> m) {
    final x = (m['x'] as num?)?.toInt() ?? 0;
    final y = (m['y'] as num?)?.toInt() ?? 0;
    final tipo = '${m['tipo'] ?? ''}';
    final b = (m['b'] as num?)?.toInt() ?? 0;
    final dy = (m['dy'] as num?)?.toInt() ?? 0;

    if (tipo == 'rotella') {
      if (emulatore.modoMouse != 0) {
        final byte = byteDelMouse(
          modoMouse: emulatore.modoMouse, sgr: emulatore.mouseSgr,
          colonna: x, riga: y, pulsante: dy < 0 ? 64 : 65, premuto: true,
          movimento: false,
          shift: m['shift'] == true, alt: m['alt'] == true, ctrl: m['ctrl'] == true,
        );
        _alTerminale(Uint8List.fromList(byte));
      } else if (emulatore.sulloSchermoAlternativo) {
        // `less` e `vim` senza mouse: la rotella diventa le frecce, che è
        // quello che uno si aspetta girandola.
        final freccia = dy < 0 ? 'Up' : 'Down';
        final byte = byteDelTasto(nome: freccia, testo: '', ctrl: false,
            alt: false, shift: false,
            tastiCursoreApplicazione: emulatore.tastiCursoreApplicazione);
        for (var i = 0; i < 3; i++) {
          _alTerminale(Uint8List.fromList(byte));
        }
      } else {
        final nuovo = (scarto - dy * 3).clamp(0, emulatore.scrollback.length);
        if (nuovo != scarto) {
          scarto = nuovo;
          _tuttoDaMandare = true;
          _segnaDaDisegnare();
        }
      }
      return;
    }
    if (emulatore.modoMouse == 0) return;
    final byte = byteDelMouse(
      modoMouse: emulatore.modoMouse, sgr: emulatore.mouseSgr,
      colonna: x, riga: y,
      pulsante: tipo == 'muovi' && m['b'] == null ? -1 : b,
      premuto: tipo != 'lascia', movimento: tipo == 'muovi',
      shift: m['shift'] == true, alt: m['alt'] == true, ctrl: m['ctrl'] == true,
    );
    if (byte.isNotEmpty) _alTerminale(Uint8List.fromList(byte));
  }

  // ── Verso il terminale ───────────────────────────────────────────────
  void _alTerminale(Uint8List byte) {
    final p = _pty;
    if (p == null) return;
    // Le cornici portano al massimo 65535 byte: un incolla grosso si spezza.
    var i = 0;
    while (i < byte.length) {
      final fine = (i + 65000).clamp(0, byte.length);
      p.stdin.add(_cornice(0, byte.sublist(i, fine)));
      i = fine;
    }
  }

  List<int> _cornice(int tipo, List<int> dati) {
    final n = dati.length;
    return [tipo, (n >> 8) & 0xff, n & 0xff, ...dati];
  }

  void _manda(Map<String, dynamic> m) {
    fuori.writeln(jsonEncode(m));
  }
}
