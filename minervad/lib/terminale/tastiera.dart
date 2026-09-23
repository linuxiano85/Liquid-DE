// tastiera.dart — Da un tasto premuto ai byte che il terminale si aspetta.
//
// La finestra sa quale tasto è stato premuto (il nome di Qt, i modificatori,
// il testo che ne esce). Il terminale vuole byte: `\e[A` per la freccia in
// su, ma `\eOA` se il programma ha acceso i tasti-cursore applicazione
// (DECCKM, lo fa `vim`), `\x01` per Ctrl+A, `\ea` per Alt+A. La traduzione
// dipende dai MODI dell'emulatore, quindi sta dalla sua parte e non nella
// finestra — e si prova a numeri.
//
// I nomi dei tasti sono quelli di `Qt.Key_*` senza il prefisso, come li
// manda la finestra: `Up`, `Return`, `F5`, `Tab`, `Backspace`.
library;

/// I byte per un tasto. `testo` è quello che Qt dice che il tasto scrive
/// (già con Shift applicato); vuoto per i tasti speciali.
List<int> byteDelTasto({
  required String nome,
  required String testo,
  required bool ctrl,
  required bool alt,
  required bool shift,
  required bool tastiCursoreApplicazione,
}) {
  final out = <int>[];
  void esc(String s) => out.addAll(s.codeUnits);

  // ── Il modificatore xterm per le frecce e i tasti funzione ──────────
  //
  // `\e[1;5A` è Ctrl+Su: il numero è 1 + shift(1) + alt(2) + ctrl(4).
  final mod = 1 + (shift ? 1 : 0) + (alt ? 2 : 0) + (ctrl ? 4 : 0);
  String conMod(String base, String finale) =>
      mod == 1 ? '\x1b[$base$finale' : '\x1b[${base.isEmpty ? '1' : base};$mod$finale';

  switch (nome) {
    case 'Up':
    case 'Down':
    case 'Right':
    case 'Left':
      final lettera = {'Up': 'A', 'Down': 'B', 'Right': 'C', 'Left': 'D'}[nome]!;
      if (mod == 1 && tastiCursoreApplicazione) {
        esc('\x1bO$lettera');
      } else {
        esc(conMod('', lettera));
      }
      return out;
    case 'Home':
      esc(mod == 1 && tastiCursoreApplicazione ? '\x1bOH' : conMod('', 'H'));
      return out;
    case 'End':
      esc(mod == 1 && tastiCursoreApplicazione ? '\x1bOF' : conMod('', 'F'));
      return out;
    case 'Insert':
      esc(mod == 1 ? '\x1b[2~' : '\x1b[2;$mod~');
      return out;
    case 'Delete':
      esc(mod == 1 ? '\x1b[3~' : '\x1b[3;$mod~');
      return out;
    case 'PageUp':
      esc(mod == 1 ? '\x1b[5~' : '\x1b[5;$mod~');
      return out;
    case 'PageDown':
      esc(mod == 1 ? '\x1b[6~' : '\x1b[6;$mod~');
      return out;
    case 'Return':
    case 'Enter':
      if (alt) out.add(0x1b);
      out.add(0x0d);
      return out;
    case 'Tab':
      if (shift) {
        esc('\x1b[Z');
      } else {
        out.add(0x09);
      }
      return out;
    case 'Backtab':
      esc('\x1b[Z');
      return out;
    case 'Backspace':
      // DEL (0x7f), che è quello che ogni terminale moderno manda; con Ctrl
      // si manda BS (0x08), che le shell leggono come «cancella la parola».
      if (alt) out.add(0x1b);
      out.add(ctrl ? 0x08 : 0x7f);
      return out;
    case 'Escape':
      out.add(0x1b);
      return out;
    case 'Space':
      if (ctrl) {
        out.add(0x00);
      } else {
        if (alt) out.add(0x1b);
        out.add(0x20);
      }
      return out;
  }

  // ── I tasti funzione ─────────────────────────────────────────────────
  if (nome.length >= 2 && nome[0] == 'F') {
    final n = int.tryParse(nome.substring(1));
    if (n != null && n >= 1 && n <= 12) {
      const base = {
        1: 'P', 2: 'Q', 3: 'R', 4: 'S',
      };
      const tilde = {
        5: 15, 6: 17, 7: 18, 8: 19, 9: 20, 10: 21, 11: 23, 12: 24,
      };
      if (n <= 4) {
        esc(mod == 1 ? '\x1bO${base[n]}' : '\x1b[1;$mod${base[n]}');
      } else {
        esc(mod == 1 ? '\x1b[${tilde[n]}~' : '\x1b[${tilde[n]};$mod~');
      }
      return out;
    }
  }

  // ── Ctrl + lettera: i codici di controllo ────────────────────────────
  if (ctrl && testo.isNotEmpty) {
    final c = testo.toLowerCase().codeUnitAt(0);
    int? ctl;
    if (c >= 0x61 && c <= 0x7a) {
      ctl = c - 0x60; // a → 1 … z → 26
    } else {
      const speciali = {
        0x5b: 0x1b, // [
        0x5c: 0x1c, // \
        0x5d: 0x1d, // ]
        0x5e: 0x1e, // ^
        0x5f: 0x1f, // _
        0x3f: 0x7f, // ?
        0x40: 0x00, // @
        0x32: 0x00, // 2
        0x33: 0x1b, 0x34: 0x1c, 0x35: 0x1d, 0x36: 0x1e, 0x37: 0x1f,
        0x38: 0x7f,
      };
      ctl = speciali[c];
    }
    if (ctl != null) {
      if (alt) out.add(0x1b);
      out.add(ctl);
      return out;
    }
  }

  // ── Testo normale, con Alt come ESC davanti ──────────────────────────
  if (testo.isNotEmpty) {
    if (alt) out.add(0x1b);
    out.addAll(_utf8(testo));
  }
  return out;
}

List<int> _utf8(String s) {
  final out = <int>[];
  for (final r in s.runes) {
    if (r < 0x80) {
      out.add(r);
    } else if (r < 0x800) {
      out.add(0xc0 | (r >> 6));
      out.add(0x80 | (r & 0x3f));
    } else if (r < 0x10000) {
      out.add(0xe0 | (r >> 12));
      out.add(0x80 | ((r >> 6) & 0x3f));
      out.add(0x80 | (r & 0x3f));
    } else {
      out.add(0xf0 | (r >> 18));
      out.add(0x80 | ((r >> 12) & 0x3f));
      out.add(0x80 | ((r >> 6) & 0x3f));
      out.add(0x80 | (r & 0x3f));
    }
  }
  return out;
}

/// Un evento del mouse, nel formato che il programma ha chiesto.
///
/// `modoMouse` 1000 clic, 1002 anche il trascinamento, 1003 ogni movimento;
/// `sgr` è il formato 1006 (l'unico che sa contare oltre la colonna 223).
/// `pulsante`: 0 sinistro, 1 centrale, 2 destro; 64/65 la rotella su/giù.
/// Torna vuoto se il programma non vuole questo evento.
List<int> byteDelMouse({
  required int modoMouse,
  required bool sgr,
  required int colonna,
  required int riga,
  required int pulsante,
  required bool premuto,
  required bool movimento,
  required bool shift,
  required bool alt,
  required bool ctrl,
}) {
  if (modoMouse == 0) return const [];
  if (movimento) {
    if (modoMouse == 1000) return const [];
    if (modoMouse == 1002 && pulsante < 0) return const [];
  }
  var cb = pulsante < 0 ? 3 : pulsante;
  if (movimento) cb += 32;
  if (shift) cb += 4;
  if (alt) cb += 8;
  if (ctrl) cb += 16;
  if (sgr) {
    final s = '\x1b[<$cb;${colonna + 1};${riga + 1}${premuto ? 'M' : 'm'}';
    return s.codeUnits;
  }
  // X10/normale: i valori sono +32, e non si va oltre 223.
  if (!premuto && !movimento) cb = 3;
  final c = (colonna + 1 + 32).clamp(33, 255);
  final r = (riga + 1 + 32).clamp(33, 255);
  return [0x1b, 0x5b, 0x4d, cb + 32, c, r];
}
