// emulatore.dart — Un terminale VT: i byte che escono da un programma
// diventano una griglia di celle con un colore e un cursore.
//
// ── Perché è nostro ────────────────────────────────────────────────────────
//
// Giacomo, 14 settembre 2026, scegliendo: «Nostro, in Dart». Le alternative
// erano `xterm.dart` (dipende da Flutter, che il demone non ha) e `libvterm`
// (C, un'altra lingua per un'app sola). Un emulatore è un automa ben
// descritto — quello di Paul Williams, lo stesso di xterm e di tutti gli
// altri — e si prova a numeri: si danno dei byte, si guarda la griglia.
//
// ── Cosa fa e cosa non fa (tappa 1) ────────────────────────────────────────
//
// Fa: UTF-8 anche spezzato fra due pacchetti; caratteri larghi su due celle;
// SGR completo (16, 256, 24 bit, grassetto, corsivo, sottolineato, inverso,
// sbiadito, barrato); tutto il movimento del cursore; cancellazioni e
// inserimenti di righe e caratteri; la regione di scorrimento; lo schermo
// alternativo (1049); l'incolla fra parentesi (2004); i modi del mouse
// (1000, 1002, 1003, 1006); il titolo (OSC 0/2); la cartella (OSC 7); i
// marcatori firmati dei blocchi (OSC 777, vedi `blocchi_automatici.dart`);
// le risposte a DA e DSR; la grafica DEC per le cornici di `htop`.
//
// Non fa: i caratteri combinanti (saltati: l'accento non si disegna, la
// lettera sì), le sequenze DCS (lette e buttate), le tabulazioni verticali.
// Dichiarato qui, non nascosto.
//
// ── La griglia, in memoria ─────────────────────────────────────────────────
//
// Nessun oggetto per cella: ogni riga sono quattro liste tipizzate (carattere,
// primo piano, sfondo, bandiere). Un `cat` di un file da un gigabyte scrive
// milioni di celle al secondo, e un oggetto per ognuna sarebbe il garbage
// collector che lavora al posto del terminale. Il colore è un intero solo:
//
//     0                      quello del tema
//     0x01000000 | indice    uno dei 256
//     0x02000000 | rrggbb    24 bit
library;

import 'dart:convert';
import 'dart:typed_data';

import 'larghezza.dart';

// ── Le bandiere di una cella ───────────────────────────────────────────────
const int flGrassetto = 1 << 0;
const int flSbiadito = 1 << 1;
const int flCorsivo = 1 << 2;
const int flSottolineato = 1 << 3;
const int flLampeggia = 1 << 4;
const int flInverso = 1 << 5;
const int flNascosto = 1 << 6;
const int flBarrato = 1 << 7;
/// Questa cella è la metà SINISTRA di un carattere largo.
const int flLargo = 1 << 8;
/// Questa cella è la metà DESTRA: non si disegna, appartiene a quella prima.
const int flSeguito = 1 << 9;

/// I colori: come si compongono e si leggono.
const int colDefault = 0;
const int colIndice = 0x01000000;
const int colRgb = 0x02000000;
int colore256(int i) => colIndice | (i & 0xff);
int coloreRgb(int r, int g, int b) =>
    colRgb | ((r & 0xff) << 16) | ((g & 0xff) << 8) | (b & 0xff);

/// Una riga della griglia. `larghezza` celle, tutte presenti.
class Riga {
  Riga(int larghezza)
      : cp = Int32List(larghezza),
        fg = Int32List(larghezza),
        bg = Int32List(larghezza),
        fl = Uint16List(larghezza) {
    cp.fillRange(0, larghezza, 0x20);
  }

  final Int32List cp;
  final Int32List fg;
  final Int32List bg;
  final Uint16List fl;

  /// Vera se questa riga continua quella sopra (il testo è andato a capo da
  /// solo): serve a chi copia, per non mettere un a-capo dove non c'era.
  bool avvolta = false;

  int get larghezza => cp.length;

  void azzera(int da, int a, int fg0, int bg0) {
    for (var i = da; i < a && i < cp.length; i++) {
      cp[i] = 0x20;
      fg[i] = fg0;
      bg[i] = bg0;
      fl[i] = 0;
    }
  }

  /// Il testo, per la copia e per le prove: senza gli spazi in coda, e le
  /// metà destre dei caratteri larghi non si contano.
  String testo() {
    final b = StringBuffer();
    var fine = cp.length;
    while (fine > 0 && cp[fine - 1] == 0x20 && fl[fine - 1] == 0) {
      fine--;
    }
    for (var i = 0; i < fine; i++) {
      if (fl[i] & flSeguito != 0) continue;
      b.writeCharCode(cp[i]);
    }
    return b.toString();
  }

  Riga copiaLarga(int nuova) {
    final r = Riga(nuova);
    final n = nuova < cp.length ? nuova : cp.length;
    r.cp.setRange(0, n, cp);
    r.fg.setRange(0, n, fg);
    r.bg.setRange(0, n, bg);
    r.fl.setRange(0, n, fl);
    r.avvolta = avvolta;
    return r;
  }
}

/// Le righe uscite dalla cima: un anello, non una lista.
///
/// Con una `List` e `removeRange(0, 1)` a ogni riga oltre il tetto, `seq 1
/// 1000000` costava dieci miliardi di spostamenti (diecimila per riga, un
/// milione di righe) e ci metteva quarantasette secondi — misurato il 15
/// settembre 2026. Con l'anello aggiungere costa quanto una scrittura, e
/// la più vecchia si sovrascrive da sola.
class Scrollback {
  Scrollback(this.capienza) : _anello = List<Riga?>.filled(capienza, null);

  final int capienza;
  final List<Riga?> _anello;
  int _inizio = 0;
  int _quante = 0;

  int get length => _quante;
  bool get isEmpty => _quante == 0;
  bool get isNotEmpty => _quante > 0;

  Riga operator [](int i) {
    if (i < 0 || i >= _quante) throw RangeError.index(i, this);
    return _anello[(_inizio + i) % capienza]!;
  }

  Riga get first => this[0];
  Riga get last => this[_quante - 1];

  /// Aggiunge in coda. Torna la riga BUTTATA, se l'anello era pieno: chi
  /// chiama la può riusare invece di allocarne una nuova — un `cat` da un
  /// milione di righe alloca un milione di righe altrimenti, e il garbage
  /// collector lavora al posto del terminale.
  Riga? add(Riga r) {
    if (_quante < capienza) {
      _anello[(_inizio + _quante) % capienza] = r;
      _quante++;
      return null;
    }
    final via = _anello[_inizio];
    _anello[_inizio] = r;
    _inizio = (_inizio + 1) % capienza;
    return via;
  }

  Riga removeLast() {
    final r = last;
    _quante--;
    _anello[(_inizio + _quante) % capienza] = null;
    return r;
  }

  void clear() {
    for (var i = 0; i < capienza; i++) {
      _anello[i] = null;
    }
    _inizio = 0;
    _quante = 0;
  }

  Iterable<Riga> get righe sync* {
    for (var i = 0; i < _quante; i++) {
      yield this[i];
    }
  }

  Iterable<T> map<T>(T Function(Riga) f) => righe.map(f);
}

/// Dove sta il cursore, per chi lo disegna.
class Cursore {
  Cursore(this.colonna, this.riga, this.visibile, this.forma);
  final int colonna;
  final int riga;
  final bool visibile;
  /// 0 blocco · 1 sottolineatura · 2 barra (come DECSCUSR).
  final int forma;
}

class Emulatore {
  Emulatore({int colonne = 80, int righe = 24, this.scrollbackMassimo = 10000})
      : colonne = colonne < 2 ? 2 : colonne,
        righe = righe < 1 ? 1 : righe {
    _schermo = List.generate(this.righe, (_) => Riga(this.colonne));
    _alternativo = List.generate(this.righe, (_) => Riga(this.colonne));
    _margineBasso = this.righe - 1;
    _tabulazioniDiSerie();
  }

  int colonne;
  int righe;
  final int scrollbackMassimo;

  late List<Riga> _schermo;
  late List<Riga> _alternativo;
  bool _sulloAlternativo = false;
  late final Scrollback scrollback = Scrollback(scrollbackMassimo);

  /// Quante righe sono USCITE dalla cima da quando è nato, buttate comprese:
  /// insieme all'indice sullo schermo dà un numero assoluto che non torna
  /// mai indietro. È così che i marcatori dei blocchi restano validi anche
  /// dopo che la riga è finita nello scrollback o oltre.
  int righeUscite = 0;

  // ── Il cursore e gli attributi ───────────────────────────────────────
  int cx = 0;
  int cy = 0;
  bool cursoreVisibile = true;
  int formaCursore = 0;
  int _fg = colDefault;
  int _bg = colDefault;
  int _fl = 0;

  /// «In attesa di andare a capo»: il cursore è sull'ultima colonna dopo
  /// aver scritto, e il prossimo carattere lo manda alla riga dopo. È lo
  /// stato più discusso di ogni terminale, e va tenuto esplicito.
  bool _sospeso = false;

  // ── I modi ───────────────────────────────────────────────────────────
  bool aCapoAutomatico = true; // DECAWM
  bool origineRelativa = false; // DECOM
  bool inserimento = false; // IRM
  bool tastiCursoreApplicazione = false; // DECCKM
  bool incollaFraParentesi = false; // 2004
  /// 0 spento · 1000 clic · 1002 clic e trascinamento · 1003 ogni movimento.
  int modoMouse = 0;
  bool mouseSgr = false; // 1006
  bool eventiFuoco = false; // 1004
  bool aCapoConRitorno = false; // LNM

  int _margineAlto = 0;
  late int _margineBasso;
  late List<bool> _tabulazioni;

  // Cursore salvato (DECSC), uno per schermo.
  int _sx = 0, _sy = 0, _sfg = 0, _sbg = 0, _sfl = 0;
  bool _sOrigine = false, _sAvvolgi = true;
  bool _grafica = false; // G0 = DEC special graphics
  bool _sGrafica = false;
  bool _g1Grafica = false;
  bool _usaG1 = false; // SO/SI

  // ── Quello che esce ──────────────────────────────────────────────────
  /// Byte da rimandare al programma (risposte a DA, DSR…).
  final List<int> risposte = [];
  String titolo = '';
  String cartella = '';
  String? chiaveBlocchi;
  void Function(String tipo, int codice, String comando, String cartella)? bloccoMinerva;
  int campanelli = 0;
  /// Righe dello schermo cambiate dall'ultimo `pulisci()`.
  final Set<int> sporche = {};
  bool tuttoSporco = true;
  /// Vera se dall'ultimo `pulisci()` è cambiato qualcosa di non-riga:
  /// titolo, cartella, cursore, modi.
  bool statoSporco = true;

  // ── L'automa ─────────────────────────────────────────────────────────
  static const _terra = 0, _escape = 1, _escapeIntermedio = 2, _csiEntra = 3,
      _csiParam = 4, _csiIntermedio = 5, _csiIgnora = 6, _osc = 7, _dcs = 8,
      _sosPmApc = 9;
  int _stato = _terra;
  final List<int> _intermedi = [];
  final StringBuffer _paramBuf = StringBuffer();
  final StringBuffer _oscBuf = StringBuffer();
  bool _oscTroncato = false;
  bool _oscEscape = false;
  final List<int> _utf8Sospesi = [];

  List<Riga> get _griglia => _sulloAlternativo ? _alternativo : _schermo;
  bool get sulloSchermoAlternativo => _sulloAlternativo;
  int ingressiAlternativo = 0;

  Riga riga(int i) => _griglia[i];
  Cursore get cursore => Cursore(cx, cy, cursoreVisibile, formaCursore);

  /// Numero assoluto della riga `i` dello schermo.
  int rigaAssoluta(int i) => righeUscite + i;

  void pulisci() {
    sporche.clear();
    tuttoSporco = false;
    statoSporco = false;
  }

  void _tabulazioniDiSerie() {
    _tabulazioni = List<bool>.generate(colonne, (i) => i % 8 == 0);
  }

  void _sporca(int r) => sporche.add(r);
  void _sporcaTutto() => tuttoSporco = true;

  // ── Entrata: i byte ──────────────────────────────────────────────────

  /// Dà all'emulatore dei byte come arrivano dal terminale. Un carattere
  /// UTF-8 tagliato a metà resta in attesa del pacchetto dopo.
  void scrivi(List<int> byte) {
    var i = 0;
    final n = byte.length;
    while (i < n) {
      final b = byte[i];
      if (_utf8Sospesi.isNotEmpty || b >= 0x80) {
        // Sequenza multibyte: si accumula finché non è completa.
        _utf8Sospesi.add(b);
        i++;
        final cp = _decodifica();
        if (cp == -2) continue; // ancora incompleta
        if (cp >= 0) _carattere(cp);
        continue;
      }
      i++;
      _byte(b);
    }
  }

  /// Prova a chiudere la sequenza in `_utf8Sospesi`. Torna il codice, −2 se
  /// mancano byte, −1 se era spazzatura (che si butta).
  int _decodifica() {
    final s = _utf8Sospesi;
    final primo = s[0];
    int attesi;
    if (primo >= 0xf0 && primo <= 0xf4) {
      attesi = 4;
    } else if (primo >= 0xe0) {
      attesi = 3;
    } else if (primo >= 0xc2) {
      attesi = 2;
    } else {
      s.clear();
      return -1;
    }
    if (s.length < attesi) {
      // Un byte di continuazione mancante ma il successivo NON è di
      // continuazione: la sequenza era rotta, si butta quella e si
      // riparte dal nuovo.
      if (s.length > 1 && (s.last & 0xc0) != 0x80) {
        final ultimo = s.last;
        s.clear();
        if (ultimo < 0x80) {
          _byte(ultimo);
          return -1;
        }
        s.add(ultimo);
        return -2;
      }
      return -2;
    }
    try {
      final testo = utf8.decode(s, allowMalformed: false);
      s.clear();
      return testo.runes.first;
    } catch (_) {
      s.clear();
      return -1;
    }
  }

  void _byte(int b) {
    switch (_stato) {
      case _terra:
        if (b == 0x1b) {
          _stato = _escape;
          _intermedi.clear();
        } else if (b < 0x20 || b == 0x7f) {
          _controllo(b);
        } else {
          _carattere(b);
        }
      case _escape:
        _escapeByte(b);
      case _escapeIntermedio:
        if (b >= 0x20 && b <= 0x2f) {
          _intermedi.add(b);
        } else if (b >= 0x30 && b <= 0x7e) {
          _escapeFinale(b);
          _stato = _terra;
        } else if (b == 0x1b) {
          _stato = _escape;
          _intermedi.clear();
        } else if (b < 0x20) {
          _controllo(b);
        } else {
          _stato = _terra;
        }
      case _csiEntra:
      case _csiParam:
      case _csiIntermedio:
        _csiByte(b);
      case _csiIgnora:
        if (b >= 0x40 && b <= 0x7e) {
          _stato = _terra;
        } else if (b == 0x1b) {
          _stato = _escape;
          _intermedi.clear();
        } else if (b < 0x20) {
          _controllo(b);
        }
      case _osc:
        _oscByte(b);
      case _dcs:
      case _sosPmApc:
        // Si legge fino a ST (ESC \) o BEL e si butta: il contenuto non
        // ci riguarda, ma va consumato per intero o comparirebbe a schermo.
        if (b == 0x07) {
          _stato = _terra;
        } else if (b == 0x1b) {
          _oscEscape = true;
        } else if (_oscEscape && b == 0x5c) {
          _oscEscape = false;
          _stato = _terra;
        } else {
          _oscEscape = false;
        }
    }
  }

  // ── I caratteri di controllo ─────────────────────────────────────────
  void _controllo(int b) {
    switch (b) {
      case 0x07:
        campanelli++;
        statoSporco = true;
      case 0x08: // BS
        if (cx > 0) cx--;
        _sospeso = false;
        statoSporco = true;
      case 0x09: // HT
        _tabulazione();
      case 0x0a:
      case 0x0b:
      case 0x0c: // LF, VT, FF
        _aCapo();
        if (aCapoConRitorno) cx = 0;
      case 0x0d: // CR
        cx = 0;
        _sospeso = false;
        statoSporco = true;
      case 0x0e: // SO: G1
        _usaG1 = true;
      case 0x0f: // SI: G0
        _usaG1 = false;
      default:
        break;
    }
  }

  void _tabulazione() {
    _sospeso = false;
    if (cx >= colonne - 1) return;
    var c = cx + 1;
    while (c < colonne - 1 && !_tabulazioni[c]) {
      c++;
    }
    cx = c;
    statoSporco = true;
  }

  /// Avanti di una riga, scorrendo se si è sul margine basso (IND).
  void _aCapo() {
    _sospeso = false;
    if (cy == _margineBasso) {
      _scorriSu(1);
    } else if (cy < righe - 1) {
      cy++;
    }
    statoSporco = true;
  }

  /// Indietro di una riga, scorrendo in giù se si è sul margine alto (RI).
  void _rigaIndietro() {
    _sospeso = false;
    if (cy == _margineAlto) {
      _scorriGiu(1);
    } else if (cy > 0) {
      cy--;
    }
    statoSporco = true;
  }

  // ── Lo scorrimento ───────────────────────────────────────────────────

  /// Le righe della regione salgono di `n`; quelle in cima escono. Se la
  /// regione è tutto lo schermo e non siamo sull'alternativo, escono nello
  /// scrollback: è lì che vanno a finire le righe di `ls`.
  void _scorriSu(int n) {
    final g = _griglia;
    final tutto = _margineAlto == 0 && _margineBasso == righe - 1;
    for (var k = 0; k < n; k++) {
      final uscita = g[_margineAlto];
      Riga? riusabile;
      if (tutto && !_sulloAlternativo) {
        riusabile = scrollback.add(uscita);
        righeUscite++;
      } else {
        // Dentro una regione (o sull'alternativo) la riga in cima non va
        // da nessuna parte: si riusa direttamente.
        riusabile = uscita;
      }
      for (var r = _margineAlto; r < _margineBasso; r++) {
        g[r] = g[r + 1];
      }
      if (riusabile != null && riusabile.larghezza == colonne) {
        riusabile.avvolta = false;
        riusabile.azzera(0, colonne, colDefault, _bg);
        g[_margineBasso] = riusabile;
      } else {
        g[_margineBasso] = Riga(colonne)..azzera(0, colonne, colDefault, _bg);
      }
    }
    if (tutto) {
      _sporcaTutto();
    } else {
      for (var r = _margineAlto; r <= _margineBasso; r++) {
        _sporca(r);
      }
    }
  }

  void _scorriGiu(int n) {
    final g = _griglia;
    for (var k = 0; k < n; k++) {
      for (var r = _margineBasso; r > _margineAlto; r--) {
        g[r] = g[r - 1];
      }
      g[_margineAlto] = Riga(colonne)..azzera(0, colonne, colDefault, _bg);
    }
    for (var r = _margineAlto; r <= _margineBasso; r++) {
      _sporca(r);
    }
  }

  // ── Un carattere stampabile ──────────────────────────────────────────
  void _carattere(int cp) {
    // La grafica DEC: dentro `htop` e `tmux` le cornici sono lettere
    // minuscole con G0 spostato. Si traducono qui, una volta.
    final grafica = _usaG1 ? _g1Grafica : _grafica;
    if (grafica && cp >= 0x60 && cp <= 0x7e) {
      cp = _decSpeciale[cp - 0x60];
    }
    final larg = larghezzaCella(cp);
    if (larg == 0) {
      // Combinante: dichiarato in cima, si salta. Il carattere base resta.
      return;
    }
    if (_sospeso) {
      if (aCapoAutomatico) {
        _griglia[cy].avvolta = false;
        cx = 0;
        _aCapo();
        _griglia[cy].avvolta = true;
      } else {
        cx = colonne - 1;
      }
      _sospeso = false;
    }
    // Un carattere largo che non ci sta nell'ultima colonna va a capo,
    // lasciando la cella vuota: è quello che fanno tutti, e l'unico modo di
    // non spezzarlo a metà.
    if (larg == 2 && cx == colonne - 1) {
      final r = _griglia[cy];
      r.cp[cx] = 0x20;
      r.fl[cx] = 0;
      _sporca(cy);
      if (aCapoAutomatico) {
        cx = 0;
        _aCapo();
      } else {
        return;
      }
    }
    final r = _griglia[cy];
    if (inserimento) {
      _spostaDestra(r, cx, larg);
    }
    _mettiCella(r, cx, cp, larg == 2 ? _fl | flLargo : _fl);
    if (larg == 2 && cx + 1 < colonne) {
      _mettiCella(r, cx + 1, 0x20, _fl | flSeguito);
    }
    _sporca(cy);
    cx += larg;
    if (cx >= colonne) {
      cx = colonne - 1;
      _sospeso = true;
    }
    statoSporco = true;
  }

  void _mettiCella(Riga r, int x, int cp, int fl) {
    // Se si scrive sopra la metà di un carattere largo, l'altra metà
    // sparisce: non può restare mezzo ideogramma.
    if (r.fl[x] & flSeguito != 0 && x > 0) {
      r.cp[x - 1] = 0x20;
      r.fl[x - 1] &= ~flLargo;
    }
    if (r.fl[x] & flLargo != 0 && x + 1 < r.larghezza) {
      r.cp[x + 1] = 0x20;
      r.fl[x + 1] &= ~flSeguito;
    }
    r.cp[x] = cp;
    r.fg[x] = _fg;
    r.bg[x] = _bg;
    r.fl[x] = fl;
  }

  void _spostaDestra(Riga r, int da, int n) {
    for (var x = colonne - 1; x >= da + n; x--) {
      r.cp[x] = r.cp[x - n];
      r.fg[x] = r.fg[x - n];
      r.bg[x] = r.bg[x - n];
      r.fl[x] = r.fl[x - n];
    }
    r.azzera(da, da + n, colDefault, _bg);
  }

  // ── ESC ──────────────────────────────────────────────────────────────
  void _escapeByte(int b) {
    if (b >= 0x20 && b <= 0x2f) {
      _intermedi.add(b);
      _stato = _escapeIntermedio;
      return;
    }
    switch (b) {
      case 0x5b: // [
        _stato = _csiEntra;
        _paramBuf.clear();
        _intermedi.clear();
      case 0x5d: // ]
        _stato = _osc;
        _oscBuf.clear();
        _oscTroncato = false;
        _oscEscape = false;
      case 0x50: // P (DCS)
        _stato = _dcs;
        _oscEscape = false;
      case 0x58: // X (SOS)
      case 0x5e: // ^ (PM)
      case 0x5f: // _ (APC)
        _stato = _sosPmApc;
        _oscEscape = false;
      case 0x1b:
        _stato = _escape;
      default:
        if (b < 0x20) {
          _controllo(b);
          return;
        }
        _escapeFinale(b);
        _stato = _terra;
    }
  }

  void _escapeFinale(int b) {
    if (_intermedi.isNotEmpty) {
      final i = _intermedi[0];
      if (i == 0x28) {
        // ESC ( X — G0
        _grafica = b == 0x30;
      } else if (i == 0x29) {
        // ESC ) X — G1
        _g1Grafica = b == 0x30;
      } else if (i == 0x23 && b == 0x38) {
        // DECALN: schermo pieno di E, per le prove.
        for (var r = 0; r < righe; r++) {
          for (var x = 0; x < colonne; x++) {
            _griglia[r].cp[x] = 0x45;
            _griglia[r].fg[x] = 0;
            _griglia[r].bg[x] = 0;
            _griglia[r].fl[x] = 0;
          }
        }
        _sporcaTutto();
      }
      return;
    }
    switch (b) {
      case 0x37: // 7 DECSC
        _salvaCursore();
      case 0x38: // 8 DECRC
        _ripristinaCursore();
      case 0x44: // D IND
        _aCapo();
      case 0x45: // E NEL
        cx = 0;
        _aCapo();
      case 0x48: // H HTS
        _tabulazioni[cx] = true;
      case 0x4d: // M RI
        _rigaIndietro();
      case 0x63: // c RIS
        _azzeraTutto();
      case 0x3d: // = DECKPAM
      case 0x3e: // > DECKPNM
        break;
      default:
        break;
    }
  }

  void _salvaCursore() {
    _sx = cx;
    _sy = cy;
    _sfg = _fg;
    _sbg = _bg;
    _sfl = _fl;
    _sOrigine = origineRelativa;
    _sAvvolgi = aCapoAutomatico;
    _sGrafica = _grafica;
  }

  void _ripristinaCursore() {
    cx = _sx.clamp(0, colonne - 1);
    cy = _sy.clamp(0, righe - 1);
    _fg = _sfg;
    _bg = _sbg;
    _fl = _sfl;
    origineRelativa = _sOrigine;
    aCapoAutomatico = _sAvvolgi;
    _grafica = _sGrafica;
    _sospeso = false;
    statoSporco = true;
  }

  void _azzeraTutto() {
    _fg = 0;
    _bg = 0;
    _fl = 0;
    cx = 0;
    cy = 0;
    _sospeso = false;
    _margineAlto = 0;
    _margineBasso = righe - 1;
    aCapoAutomatico = true;
    origineRelativa = false;
    inserimento = false;
    tastiCursoreApplicazione = false;
    incollaFraParentesi = false;
    modoMouse = 0;
    mouseSgr = false;
    cursoreVisibile = true;
    _grafica = false;
    _g1Grafica = false;
    _usaG1 = false;
    _tabulazioniDiSerie();
    if (_sulloAlternativo) _sulloAlternativo = false;
    for (final r in _schermo) {
      r.azzera(0, colonne, 0, 0);
    }
    _sporcaTutto();
    statoSporco = true;
  }

  // ── CSI ──────────────────────────────────────────────────────────────
  void _csiByte(int b) {
    if (b >= 0x30 && b <= 0x3f) {
      // Parametri: cifre, `;`, `:`, e i prefissi `?`, `>`, `=`, `<`.
      if (_stato == _csiIntermedio) {
        _stato = _csiIgnora;
        return;
      }
      _paramBuf.writeCharCode(b);
      _stato = _csiParam;
      return;
    }
    if (b >= 0x20 && b <= 0x2f) {
      _intermedi.add(b);
      _stato = _csiIntermedio;
      return;
    }
    if (b >= 0x40 && b <= 0x7e) {
      _csiFinale(b);
      _stato = _terra;
      return;
    }
    if (b == 0x1b) {
      _stato = _escape;
      _intermedi.clear();
      return;
    }
    if (b < 0x20) {
      _controllo(b);
      return;
    }
    _stato = _csiIgnora;
  }

  /// I parametri: una lista di liste, perché `38:2:255:0:0` ha i sotto-
  /// parametri con i due punti. `\e[m` dà `[]`; `\e[;5H` dà `[[0],[5]]`.
  List<List<int>> _parametri(String s) {
    if (s.isEmpty) return const [];
    final out = <List<int>>[];
    for (final pezzo in s.split(';')) {
      final sotto = <int>[];
      for (final p in pezzo.split(':')) {
        sotto.add(p.isEmpty ? 0 : (int.tryParse(p) ?? 0));
      }
      out.add(sotto);
    }
    return out;
  }

  int _p(List<List<int>> ps, int i, int diSerie) {
    if (i >= ps.length) return diSerie;
    final v = ps[i][0];
    return v == 0 ? diSerie : v;
  }

  void _csiFinale(int finale) {
    var testo = _paramBuf.toString();
    var privato = '';
    if (testo.isNotEmpty && '?>=<'.contains(testo[0])) {
      privato = testo[0];
      testo = testo.substring(1);
    }
    final ps = _parametri(testo);
    final inter = _intermedi.isEmpty ? 0 : _intermedi[0];

    if (privato == '?') {
      if (finale == 0x68 || finale == 0x6c) {
        // DECSET / DECRST
        for (final p in ps) {
          _modoPrivato(p[0], finale == 0x68);
        }
      }
      return;
    }
    if (privato == '>') {
      if (finale == 0x63) {
        // DA2: tipo di terminale. «Sono un VT220 firmware 1»: quello che
        // dice xterm, ed è quello che i programmi si aspettano.
        risposte.addAll('\x1b[>1;10;0c'.codeUnits);
      }
      return;
    }
    if (privato.isNotEmpty) return;

    if (inter == 0x20 && finale == 0x71) {
      // DECSCUSR: la forma del cursore.
      final v = _p(ps, 0, 1);
      formaCursore = v <= 2 ? 0 : (v <= 4 ? 1 : 2);
      statoSporco = true;
      return;
    }
    if (inter != 0) return;

    switch (finale) {
      case 0x41: // A CUU
        cy = (cy - _p(ps, 0, 1)).clamp(_limiteAlto(), righe - 1);
        _sospeso = false;
      case 0x42: // B CUD
      case 0x65: // e VPR
        cy = (cy + _p(ps, 0, 1)).clamp(0, _limiteBasso());
        _sospeso = false;
      case 0x43: // C CUF
      case 0x61: // a HPR
        cx = (cx + _p(ps, 0, 1)).clamp(0, colonne - 1);
        _sospeso = false;
      case 0x44: // D CUB
        cx = (cx - _p(ps, 0, 1)).clamp(0, colonne - 1);
        _sospeso = false;
      case 0x45: // E CNL
        cy = (cy + _p(ps, 0, 1)).clamp(0, _limiteBasso());
        cx = 0;
        _sospeso = false;
      case 0x46: // F CPL
        cy = (cy - _p(ps, 0, 1)).clamp(_limiteAlto(), righe - 1);
        cx = 0;
        _sospeso = false;
      case 0x47: // G CHA
      case 0x60: // ` HPA
        cx = (_p(ps, 0, 1) - 1).clamp(0, colonne - 1);
        _sospeso = false;
      case 0x48: // H CUP
      case 0x66: // f HVP
        _vaiA(_p(ps, 1, 1) - 1, _p(ps, 0, 1) - 1);
      case 0x64: // d VPA
        _vaiA(cx, _p(ps, 0, 1) - 1 + (origineRelativa ? _margineAlto : 0),
            assoluto: true);
      case 0x49: // I CHT
        for (var i = 0; i < _p(ps, 0, 1); i++) {
          _tabulazione();
        }
      case 0x5a: // Z CBT
        for (var i = 0; i < _p(ps, 0, 1); i++) {
          _tabulazioneIndietro();
        }
      case 0x4a: // J ED
        _cancellaSchermo(ps.isEmpty ? 0 : ps[0][0]);
      case 0x4b: // K EL
        _cancellaRiga(ps.isEmpty ? 0 : ps[0][0]);
      case 0x4c: // L IL
        _inserisciRighe(_p(ps, 0, 1));
      case 0x4d: // M DL
        _cancellaRighe(_p(ps, 0, 1));
      case 0x40: // @ ICH
        _inserisciCaratteri(_p(ps, 0, 1));
      case 0x50: // P DCH
        _cancellaCaratteri(_p(ps, 0, 1));
      case 0x58: // X ECH
        _cancellaInPosto(_p(ps, 0, 1));
      case 0x53: // S SU
        _scorriSu(_p(ps, 0, 1));
      case 0x54: // T SD
        _scorriGiu(_p(ps, 0, 1));
      case 0x62: // b REP: ripete l'ultimo carattere
        final r = _griglia[cy];
        final x = cx > 0 ? cx - 1 : 0;
        final ultimo = r.cp[x];
        for (var i = 0; i < _p(ps, 0, 1); i++) {
          _carattere(ultimo);
        }
      case 0x67: // g TBC
        final v = ps.isEmpty ? 0 : ps[0][0];
        if (v == 0) {
          _tabulazioni[cx] = false;
        } else if (v == 3) {
          _tabulazioni = List<bool>.filled(colonne, false);
        }
      case 0x68: // h SM
        for (final p in ps) {
          if (p[0] == 4) inserimento = true;
          if (p[0] == 20) aCapoConRitorno = true;
        }
      case 0x6c: // l RM
        for (final p in ps) {
          if (p[0] == 4) inserimento = false;
          if (p[0] == 20) aCapoConRitorno = false;
        }
      case 0x6d: // m SGR
        _sgr(ps);
      case 0x6e: // n DSR
        final v = ps.isEmpty ? 0 : ps[0][0];
        if (v == 5) {
          risposte.addAll('\x1b[0n'.codeUnits);
        } else if (v == 6) {
          final r = cy + 1 - (origineRelativa ? _margineAlto : 0);
          risposte.addAll('\x1b[$r;${cx + 1}R'.codeUnits);
        }
      case 0x63: // c DA1
        // VT220 con colori: `\e[?62;22c`.
        risposte.addAll('\x1b[?62;22c'.codeUnits);
      case 0x72: // r DECSTBM
        final alto = _p(ps, 0, 1) - 1;
        final basso = _p(ps, 1, righe) - 1;
        if (alto < basso && basso < righe) {
          _margineAlto = alto;
          _margineBasso = basso;
        } else {
          _margineAlto = 0;
          _margineBasso = righe - 1;
        }
        _vaiA(0, 0);
      case 0x73: // s SCOSC
        _salvaCursore();
      case 0x75: // u SCORC
        _ripristinaCursore();
      case 0x74: // t: finestra (ignorato, ma alcune chiedono la misura)
        final v = ps.isEmpty ? 0 : ps[0][0];
        if (v == 18) {
          risposte.addAll('\x1b[8;$righe;${colonne}t'.codeUnits);
        }
      default:
        break;
    }
    statoSporco = true;
  }

  int _limiteAlto() => origineRelativa ? _margineAlto : 0;
  int _limiteBasso() => origineRelativa ? _margineBasso : righe - 1;

  void _vaiA(int x, int y, {bool assoluto = false}) {
    if (origineRelativa && !assoluto) {
      y += _margineAlto;
      y = y.clamp(_margineAlto, _margineBasso);
    } else {
      y = y.clamp(0, righe - 1);
    }
    cx = x.clamp(0, colonne - 1);
    cy = y;
    _sospeso = false;
    statoSporco = true;
  }

  void _tabulazioneIndietro() {
    _sospeso = false;
    if (cx <= 0) return;
    var c = cx - 1;
    while (c > 0 && !_tabulazioni[c]) {
      c--;
    }
    cx = c;
  }

  void _modoPrivato(int m, bool acceso) {
    switch (m) {
      case 1:
        tastiCursoreApplicazione = acceso;
      case 6:
        origineRelativa = acceso;
        _vaiA(0, 0);
      case 7:
        aCapoAutomatico = acceso;
      case 25:
        cursoreVisibile = acceso;
      case 1000:
      case 1002:
      case 1003:
        modoMouse = acceso ? m : 0;
      case 1004:
        eventiFuoco = acceso;
      case 1006:
        mouseSgr = acceso;
      case 2004:
        incollaFraParentesi = acceso;
      case 47:
      case 1047:
        _schermoAlternativo(acceso, salvaCursore: false);
      case 1049:
        _schermoAlternativo(acceso, salvaCursore: true);
      default:
        break;
    }
    statoSporco = true;
  }

  /// Lo schermo alternativo: `vim` e `htop` disegnano lì, e quando escono
  /// si ritrova quello di prima, intatto, col cursore dov'era.
  void _schermoAlternativo(bool acceso, {required bool salvaCursore}) {
    if (acceso == _sulloAlternativo) return;
    if (acceso) {
      ingressiAlternativo++;
      if (salvaCursore) _salvaCursore();
      _sulloAlternativo = true;
      for (final r in _alternativo) {
        r.azzera(0, colonne, 0, 0);
      }
      cx = 0;
      cy = 0;
    } else {
      _sulloAlternativo = false;
      if (salvaCursore) _ripristinaCursore();
    }
    _margineAlto = 0;
    _margineBasso = righe - 1;
    _sporcaTutto();
  }

  void _cancellaSchermo(int modo) {
    final g = _griglia;
    switch (modo) {
      case 0:
        _cancellaRiga(0);
        for (var r = cy + 1; r < righe; r++) {
          g[r].azzera(0, colonne, 0, _bg);
          _sporca(r);
        }
      case 1:
        _cancellaRiga(1);
        for (var r = 0; r < cy; r++) {
          g[r].azzera(0, colonne, 0, _bg);
          _sporca(r);
        }
      case 2:
        for (var r = 0; r < righe; r++) {
          g[r].azzera(0, colonne, 0, _bg);
        }
        _sporcaTutto();
      case 3:
        scrollback.clear();
        _sporcaTutto();
    }
    _sospeso = false;
  }

  void _cancellaRiga(int modo) {
    final r = _griglia[cy];
    switch (modo) {
      case 0:
        r.azzera(cx, colonne, 0, _bg);
      case 1:
        r.azzera(0, cx + 1, 0, _bg);
      case 2:
        r.azzera(0, colonne, 0, _bg);
    }
    _sporca(cy);
    _sospeso = false;
  }

  void _inserisciRighe(int n) {
    if (cy < _margineAlto || cy > _margineBasso) return;
    final g = _griglia;
    for (var k = 0; k < n; k++) {
      for (var r = _margineBasso; r > cy; r--) {
        g[r] = g[r - 1];
      }
      g[cy] = Riga(colonne)..azzera(0, colonne, 0, _bg);
    }
    for (var r = cy; r <= _margineBasso; r++) {
      _sporca(r);
    }
    cx = 0;
    _sospeso = false;
  }

  void _cancellaRighe(int n) {
    if (cy < _margineAlto || cy > _margineBasso) return;
    final g = _griglia;
    for (var k = 0; k < n; k++) {
      for (var r = cy; r < _margineBasso; r++) {
        g[r] = g[r + 1];
      }
      g[_margineBasso] = Riga(colonne)..azzera(0, colonne, 0, _bg);
    }
    for (var r = cy; r <= _margineBasso; r++) {
      _sporca(r);
    }
    cx = 0;
    _sospeso = false;
  }

  void _inserisciCaratteri(int n) {
    _spostaDestra(_griglia[cy], cx, n.clamp(1, colonne - cx));
    _sporca(cy);
    _sospeso = false;
  }

  void _cancellaCaratteri(int n) {
    final r = _griglia[cy];
    n = n.clamp(1, colonne - cx);
    for (var x = cx; x < colonne; x++) {
      final da = x + n;
      if (da < colonne) {
        r.cp[x] = r.cp[da];
        r.fg[x] = r.fg[da];
        r.bg[x] = r.bg[da];
        r.fl[x] = r.fl[da];
      } else {
        r.cp[x] = 0x20;
        r.fg[x] = 0;
        r.bg[x] = _bg;
        r.fl[x] = 0;
      }
    }
    _sporca(cy);
    _sospeso = false;
  }

  void _cancellaInPosto(int n) {
    _griglia[cy].azzera(cx, cx + n, 0, _bg);
    _sporca(cy);
    _sospeso = false;
  }

  // ── SGR: i colori e gli attributi ────────────────────────────────────
  void _sgr(List<List<int>> ps) {
    if (ps.isEmpty) {
      _fg = 0;
      _bg = 0;
      _fl = 0;
      return;
    }
    for (var i = 0; i < ps.length; i++) {
      final p = ps[i];
      final v = p[0];
      switch (v) {
        case 0:
          _fg = 0;
          _bg = 0;
          _fl = 0;
        case 1:
          _fl |= flGrassetto;
        case 2:
          _fl |= flSbiadito;
        case 3:
          _fl |= flCorsivo;
        case 4:
        case 21:
          _fl |= flSottolineato;
        case 5:
        case 6:
          _fl |= flLampeggia;
        case 7:
          _fl |= flInverso;
        case 8:
          _fl |= flNascosto;
        case 9:
          _fl |= flBarrato;
        case 22:
          _fl &= ~(flGrassetto | flSbiadito);
        case 23:
          _fl &= ~flCorsivo;
        case 24:
          _fl &= ~flSottolineato;
        case 25:
          _fl &= ~flLampeggia;
        case 27:
          _fl &= ~flInverso;
        case 28:
          _fl &= ~flNascosto;
        case 29:
          _fl &= ~flBarrato;
        case 39:
          _fg = 0;
        case 49:
          _bg = 0;
        case 38:
        case 48:
          // Due forme: `38;5;n` e `38;2;r;g;b` con i punti e virgola, oppure
          // `38:5:n` e `38:2::r:g:b` con i due punti (e un campo vuoto per
          // lo spazio colore). Si accettano tutte e quattro.
          int colore;
          if (p.length > 1) {
            colore = _coloreEsteso(p.sublist(1));
          } else {
            final resto = <int>[];
            var k = i + 1;
            if (k < ps.length && ps[k][0] == 5 && k + 1 < ps.length) {
              resto.addAll([5, ps[k + 1][0]]);
              k += 2;
            } else if (k < ps.length && ps[k][0] == 2 && k + 3 < ps.length) {
              resto.addAll([2, ps[k + 1][0], ps[k + 2][0], ps[k + 3][0]]);
              k += 4;
            }
            i = k - 1;
            colore = _coloreEsteso(resto);
          }
          if (v == 38) {
            _fg = colore;
          } else {
            _bg = colore;
          }
        default:
          if (v >= 30 && v <= 37) {
            _fg = colore256(v - 30);
          } else if (v >= 40 && v <= 47) {
            _bg = colore256(v - 40);
          } else if (v >= 90 && v <= 97) {
            _fg = colore256(v - 90 + 8);
          } else if (v >= 100 && v <= 107) {
            _bg = colore256(v - 100 + 8);
          }
      }
    }
  }

  int _coloreEsteso(List<int> p) {
    if (p.isEmpty) return 0;
    if (p[0] == 5 && p.length >= 2) return colore256(p[1]);
    if (p[0] == 2) {
      // `2:r:g:b` oppure `2::r:g:b` (con lo spazio colore vuoto).
      if (p.length >= 5 && p[1] == 0 && p.length == 5) {
        return coloreRgb(p[2], p[3], p[4]);
      }
      if (p.length >= 4) return coloreRgb(p[1], p[2], p[3]);
    }
    return 0;
  }

  // ── OSC: il titolo, la cartella, i blocchi ───────────────────────────
  void _oscByte(int b) {
    if (b == 0x07) {
      _oscFine();
      _stato = _terra;
      return;
    }
    if (_oscEscape) {
      _oscEscape = false;
      if (b == 0x5c) {
        _oscFine();
        _stato = _terra;
        return;
      }
      // Un ESC non seguito da `\`: si riparte dall'escape.
      _stato = _escape;
      _intermedi.clear();
      _escapeByte(b);
      return;
    }
    if (b == 0x1b) {
      _oscEscape = true;
      return;
    }
    // Un OSC senza fine è una trappola: un programma che stampa `\e]`
    // seguito da un megabyte mangerebbe tutto lo schermo. Si tronca.
    if (_oscBuf.length < 32768) { _oscBuf.writeCharCode(b); }
    else { _oscTroncato = true; }
  }

  void _oscFine() {
    if (_oscTroncato) return;
    final s = _oscBuf.toString();
    final punto = s.indexOf(';');
    final codice = int.tryParse(punto < 0 ? s : s.substring(0, punto)) ?? -1;
    final resto = punto < 0 ? '' : s.substring(punto + 1);
    switch (codice) {
      case 0:
      case 2:
        // Il titolo, da byte UTF-8 accumulati uno a uno.
        titolo = _daByte(resto);
        if (titolo.length > 200) titolo = titolo.substring(0, 200);
        statoSporco = true;
      case 7:
        cartella = _cartellaDaUrl(_daByte(resto));
        statoSporco = true;
      // OSC 133 (i marcatori «standard» dei blocchi) si ignora di proposito:
      // lo può scrivere qualunque programma, anche un file mostrato con
      // `cat`, e diventerebbe un blocco finto. I blocchi veri arrivano
      // firmati, con OSC 777 e la chiave di questa sessione.
      case 133:
        break;
      case 777:
        final campi = resto.split(';');
        if (chiaveBlocchi != null && campi.length == 6 &&
            campi[0] == 'minerva' && campi[1] == chiaveBlocchi &&
            const ['A', 'C', 'D'].contains(campi[2])) {
          try {
            bloccoMinerva?.call(campi[2], int.tryParse(campi[3]) ?? -1,
                Uri.decodeComponent(campi[4]), Uri.decodeComponent(campi[5]));
          } on FormatException { /* Metadati malformati: non diventano comandi. */ }
        }
      case 52:
        // Scrivere gli appunti da un programma: rifiutato, per principio.
        // Un `cat` di un file ostile non deve poter mettere un comando
        // negli appunti che poi si incolla in un terminale.
        break;
      default:
        break;
    }
  }

  String _daByte(String s) {
    try {
      return utf8.decode(s.codeUnits, allowMalformed: true);
    } catch (_) {
      return s;
    }
  }

  /// `file://host/percorso` → `/percorso`, con le `%20` sciolte.
  String _cartellaDaUrl(String u) {
    if (!u.startsWith('file://')) return u;
    var resto = u.substring(7);
    final barra = resto.indexOf('/');
    if (barra < 0) return '/';
    resto = resto.substring(barra);
    try {
      return Uri.decodeComponent(resto);
    } catch (_) {
      return resto;
    }
  }

  // ── La misura ────────────────────────────────────────────────────────

  /// Cambia colonne e righe. Le righe che escono dal fondo vanno nello
  /// scrollback; quelle che entrano tornano da lì. Il cursore resta sulla
  /// sua riga se può.
  void ridimensiona(int nuoveColonne, int nuoveRighe) {
    nuoveColonne = nuoveColonne < 2 ? 2 : nuoveColonne;
    nuoveRighe = nuoveRighe < 1 ? 1 : nuoveRighe;
    if (nuoveColonne == colonne && nuoveRighe == righe) return;

    List<Riga> adatta(List<Riga> g, bool conScrollback) {
      var righeNuove = g.map((r) => r.copiaLarga(nuoveColonne)).toList();
      if (nuoveRighe < righeNuove.length) {
        // Si tolgono prima le righe VUOTE in fondo, poi quelle in cima
        // (che vanno nello scrollback): è quello che uno si aspetta
        // rimpicciolendo una finestra con tre righe di testo in alto.
        while (righeNuove.length > nuoveRighe &&
            righeNuove.last.testo().isEmpty &&
            cy < righeNuove.length - 1) {
          righeNuove.removeLast();
        }
        while (righeNuove.length > nuoveRighe) {
          final via = righeNuove.removeAt(0);
          if (conScrollback) {
            scrollback.add(via);
            righeUscite++;
          }
          cy--;
        }
      } else {
        while (righeNuove.length < nuoveRighe) {
          if (conScrollback && scrollback.isNotEmpty) {
            righeNuove.insert(0, scrollback.removeLast().copiaLarga(nuoveColonne));
            righeUscite--;
            cy++;
          } else {
            righeNuove.add(Riga(nuoveColonne));
          }
        }
      }
      return righeNuove;
    }

    final cyPrima = cy;
    if (_sulloAlternativo) {
      _alternativo = adatta(_alternativo, false);
      cy = cyPrima;
      _schermo = _schermo.map((r) => r.copiaLarga(nuoveColonne)).toList();
      while (_schermo.length > nuoveRighe) {
        _schermo.removeAt(0);
      }
      while (_schermo.length < nuoveRighe) {
        _schermo.add(Riga(nuoveColonne));
      }
    } else {
      _schermo = adatta(_schermo, true);
      _alternativo = List.generate(nuoveRighe, (_) => Riga(nuoveColonne));
    }
    colonne = nuoveColonne;
    righe = nuoveRighe;
    cy = cy.clamp(0, righe - 1);
    cx = cx.clamp(0, colonne - 1);
    _margineAlto = 0;
    _margineBasso = righe - 1;
    _tabulazioniDiSerie();
    _sospeso = false;
    _sporcaTutto();
    statoSporco = true;
  }

  // ── Per le prove e per chi copia ─────────────────────────────────────

  /// Lo schermo come testo, una riga per riga.
  List<String> testoSchermo() =>
      List.generate(righe, (i) => _griglia[i].testo());

  /// Una riga qualunque della storia: gli indici negativi vanno indietro
  /// nello scrollback (−1 è l'ultima riga uscita).
  Riga? rigaStoria(int i) {
    if (i >= 0) return i < righe ? _griglia[i] : null;
    final k = scrollback.length + i;
    return k >= 0 ? scrollback[k] : null;
  }
}

/// La grafica speciale DEC (ESC ( 0): da `_` (0x60) a `~` (0x7e).
const List<int> _decSpeciale = [
  0x25c6, // ` ◆
  0x2592, // a ▒
  0x2409, // b ␉
  0x240c, // c ␌
  0x240d, // d ␍
  0x240a, // e ␊
  0x00b0, // f °
  0x00b1, // g ±
  0x2424, // h ␤
  0x240b, // i ␋
  0x2518, // j ┘
  0x2510, // k ┐
  0x250c, // l ┌
  0x2514, // m └
  0x253c, // n ┼
  0x23ba, // o ⎺
  0x23bb, // p ⎻
  0x2500, // q ─
  0x23bc, // r ⎼
  0x23bd, // s ⎽
  0x251c, // t ├
  0x2524, // u ┤
  0x2534, // v ┴
  0x252c, // w ┬
  0x2502, // x │
  0x2264, // y ≤
  0x2265, // z ≥
  0x03c0, // { π
  0x2260, // | ≠
  0x00a3, // } £
  0x00b7, // ~ ·
];
