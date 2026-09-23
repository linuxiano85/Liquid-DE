// Le prove dell'emulatore: si danno byte, si guarda la griglia.
//
// Un terminale si rompe in silenzio: `vim` mostra le righe scalate di uno,
// `htop` ha le cornici fatte di lettere, il cursore sta una colonna più in
// là. Nessuna di queste cose dà un errore. L'unico modo di prenderle è
// scrivere la sequenza e guardare dove finiscono i caratteri.
//
// Ogni gruppo prende una famiglia di sequenze; in fondo ci sono i casi che
// rompono davvero — l'UTF-8 spezzato fra due pacchetti, il carattere largo
// in ultima colonna, lo schermo alternativo col cursore salvato.
import 'dart:convert';

import 'package:minervad/terminale/emulatore.dart';
import 'package:minervad/terminale/larghezza.dart';
import 'package:test/test.dart';

Emulatore nuovo({int c = 20, int r = 5}) => Emulatore(colonne: c, righe: r);

void scrivi(Emulatore e, String s) => e.scrivi(utf8.encode(s));

void main() {
  group('testo semplice', () {
    test('le lettere finiscono nelle celle, il cursore avanza', () {
      final e = nuovo();
      scrivi(e, 'ciao');
      expect(e.riga(0).testo(), 'ciao');
      expect(e.cx, 4);
      expect(e.cy, 0);
    });

    test('CR LF va a capo e torna a sinistra', () {
      final e = nuovo();
      scrivi(e, 'uno\r\ndue');
      expect(e.testoSchermo().take(2), ['uno', 'due']);
      expect(e.cx, 3);
      expect(e.cy, 1);
    });

    test('LF da solo va giù senza tornare a sinistra', () {
      final e = nuovo();
      scrivi(e, 'ab\ncd');
      expect(e.riga(1).testo(), '  cd');
    });

    test('a capo automatico sull\'ultima colonna, con la riga segnata', () {
      final e = nuovo(c: 5);
      scrivi(e, 'abcdefg');
      expect(e.riga(0).testo(), 'abcde');
      expect(e.riga(1).testo(), 'fg');
      expect(e.riga(1).avvolta, isTrue);
    });

    test('lo scorrimento manda la prima riga nello scrollback', () {
      final e = nuovo(r: 2);
      scrivi(e, '1\r\n2\r\n3');
      expect(e.testoSchermo(), ['2', '3']);
      expect(e.scrollback.length, 1);
      expect(e.scrollback.first.testo(), '1');
      expect(e.righeUscite, 1);
    });

    test('la tabulazione salta di otto', () {
      final e = nuovo(c: 30);
      scrivi(e, 'a\tb\tc');
      expect(e.riga(0).testo(), 'a       b       c');
    });

    test('backspace torna indietro senza cancellare', () {
      final e = nuovo();
      scrivi(e, 'abc\b\bX');
      expect(e.riga(0).testo(), 'aXc');
    });

    test('il campanello si conta', () {
      final e = nuovo();
      scrivi(e, 'a\x07b\x07');
      expect(e.campanelli, 2);
      expect(e.riga(0).testo(), 'ab');
    });
  });

  group('il cursore', () {
    test('CUP va dove dice (1-based)', () {
      final e = nuovo();
      scrivi(e, '\x1b[3;5HX');
      expect(e.riga(2).cp[4], 'X'.codeUnitAt(0));
    });

    test('CUP senza parametri va in cima a sinistra', () {
      final e = nuovo();
      scrivi(e, 'abc\x1b[HZ');
      expect(e.riga(0).testo(), 'Zbc');
    });

    test('CUU CUD CUF CUB si fermano ai bordi', () {
      final e = nuovo(c: 10, r: 3);
      scrivi(e, '\x1b[5;5H'); // già ritagliato a (3,5)
      expect(e.cy, 2);
      scrivi(e, '\x1b[9A\x1b[9D');
      expect(e.cx, 0);
      expect(e.cy, 0);
      scrivi(e, '\x1b[99C\x1b[99B');
      expect(e.cx, 9);
      expect(e.cy, 2);
    });

    test('CHA e VPA', () {
      final e = nuovo();
      scrivi(e, '\x1b[7G\x1b[3dX');
      expect(e.cx, 7);
      expect(e.cy, 2);
    });

    test('DECSC/DECRC ricordano posizione e colore', () {
      final e = nuovo();
      scrivi(e, '\x1b[2;3H\x1b[31m\x1b7\x1b[H\x1b[0m\x1b8X');
      expect(e.cy, 1);
      expect(e.riga(1).cp[2], 'X'.codeUnitAt(0));
      expect(e.riga(1).fg[2], colore256(1));
    });

    test('DSR 6 risponde con la posizione', () {
      final e = nuovo();
      scrivi(e, '\x1b[4;7H\x1b[6n');
      expect(utf8.decode(e.risposte), '\x1b[4;7R');
    });

    test('DA1 risponde da VT220', () {
      final e = nuovo();
      scrivi(e, '\x1b[c');
      expect(utf8.decode(e.risposte), startsWith('\x1b[?62'));
    });

    test('DECTCEM nasconde e mostra il cursore', () {
      final e = nuovo();
      scrivi(e, '\x1b[?25l');
      expect(e.cursoreVisibile, isFalse);
      scrivi(e, '\x1b[?25h');
      expect(e.cursoreVisibile, isTrue);
    });

    test('DECSCUSR cambia la forma', () {
      final e = nuovo();
      scrivi(e, '\x1b[5 q');
      expect(e.formaCursore, 2);
      scrivi(e, '\x1b[3 q');
      expect(e.formaCursore, 1);
    });
  });

  group('cancellare e inserire', () {
    test('EL 0/1/2', () {
      final e = nuovo(c: 6);
      scrivi(e, 'abcdef\x1b[3G\x1b[K');
      expect(e.riga(0).testo(), 'ab');
      scrivi(e, '\x1b[Hxyzuvw\x1b[3G\x1b[1K');
      expect(e.riga(0).testo(), '   uvw');
      scrivi(e, '\x1b[2K');
      expect(e.riga(0).testo(), '');
    });

    test('ED 0 pulisce dal cursore in giù, ED 2 tutto', () {
      final e = nuovo(r: 3);
      scrivi(e, 'a\r\nb\r\nc\x1b[2;1H\x1b[J');
      expect(e.testoSchermo(), ['a', '', '']);
      scrivi(e, '\x1b[2J');
      expect(e.testoSchermo(), ['', '', '']);
    });

    test('ED 3 svuota lo scrollback', () {
      final e = nuovo(r: 2);
      scrivi(e, '1\r\n2\r\n3\x1b[3J');
      expect(e.scrollback, isEmpty);
    });

    test('ICH sposta a destra, DCH toglie', () {
      final e = nuovo(c: 8);
      scrivi(e, 'abcd\x1b[2G\x1b[2@');
      expect(e.riga(0).testo(), 'a  bcd');
      scrivi(e, '\x1b[3P');
      expect(e.riga(0).testo(), 'acd');
    });

    test('ECH cancella sul posto', () {
      final e = nuovo();
      scrivi(e, 'abcdef\x1b[2G\x1b[3X');
      expect(e.riga(0).testo(), 'a   ef');
    });

    test('IL e DL dentro la regione', () {
      final e = nuovo(r: 4);
      scrivi(e, '1\r\n2\r\n3\r\n4\x1b[2;1H\x1b[L');
      expect(e.testoSchermo(), ['1', '', '2', '3']);
      scrivi(e, '\x1b[2M');
      expect(e.testoSchermo(), ['1', '3', '', '']);
    });
  });

  group('la regione di scorrimento', () {
    test('DECSTBM: si scorre solo dentro', () {
      final e = nuovo(r: 5);
      scrivi(e, 'a\r\nb\r\nc\r\nd\r\ne');
      scrivi(e, '\x1b[2;4r'); // righe 2-4
      scrivi(e, '\x1b[4;1H\nX'); // dal margine basso: scorre la regione
      expect(e.testoSchermo(), ['a', 'c', 'd', 'X', 'e']);
      expect(e.scrollback, isEmpty, reason: 'la regione non è tutto lo schermo');
    });

    test('RI sul margine alto scorre in giù', () {
      final e = nuovo(r: 3);
      scrivi(e, 'a\r\nb\r\nc\x1b[H\x1bMX');
      expect(e.testoSchermo(), ['X', 'a', 'b']);
    });

    test('SU e SD', () {
      final e = nuovo(r: 3);
      scrivi(e, 'a\r\nb\r\nc\x1b[1S');
      expect(e.testoSchermo(), ['b', 'c', '']);
      scrivi(e, '\x1b[1T');
      expect(e.testoSchermo(), ['', 'b', 'c']);
    });

    test('DECOM: le posizioni sono relative al margine', () {
      final e = nuovo(r: 5);
      scrivi(e, '\x1b[2;4r\x1b[?6h\x1b[1;1HX');
      expect(e.riga(1).testo(), 'X');
    });
  });

  group('SGR: colori e attributi', () {
    test('i 16 colori', () {
      final e = nuovo();
      scrivi(e, '\x1b[31ma\x1b[92mb\x1b[44mc\x1b[0md');
      expect(e.riga(0).fg[0], colore256(1));
      expect(e.riga(0).fg[1], colore256(10));
      expect(e.riga(0).bg[2], colore256(4));
      expect(e.riga(0).fg[3], colDefault);
      expect(e.riga(0).bg[3], colDefault);
    });

    test('256 e 24 bit, con punto e virgola e con i due punti', () {
      final e = nuovo();
      scrivi(e, '\x1b[38;5;208ma\x1b[38;2;10;20;30mb\x1b[38:2::1:2:3mc\x1b[48:5:7md');
      expect(e.riga(0).fg[0], colore256(208));
      expect(e.riga(0).fg[1], coloreRgb(10, 20, 30));
      expect(e.riga(0).fg[2], coloreRgb(1, 2, 3));
      expect(e.riga(0).bg[3], colore256(7));
    });

    test('grassetto, corsivo, sottolineato, inverso e i loro spegnimenti', () {
      final e = nuovo();
      scrivi(e, '\x1b[1;3;4;7ma\x1b[22;23;24;27mb');
      expect(e.riga(0).fl[0],
          flGrassetto | flCorsivo | flSottolineato | flInverso);
      expect(e.riga(0).fl[1], 0);
    });

    test('SGR 0 in mezzo a una lista azzera e poi applica il resto', () {
      final e = nuovo();
      scrivi(e, '\x1b[1;31m\x1b[0;32mX');
      expect(e.riga(0).fl[0], 0);
      expect(e.riga(0).fg[0], colore256(2));
    });
  });

  group('caratteri larghi e UTF-8', () {
    test('la larghezza delle celle', () {
      expect(larghezzaCella('a'.codeUnitAt(0)), 1);
      expect(larghezzaCella('中'.runes.first), 2);
      expect(larghezzaCella('😀'.runes.first), 2);
      expect(larghezzaCella(0x0301), 0);
      expect(larghezzaCella('é'.runes.first), 1);
    });

    test('un ideogramma prende due celle, la seconda è seguito', () {
      final e = nuovo();
      scrivi(e, '中a');
      expect(e.riga(0).cp[0], '中'.runes.first);
      expect(e.riga(0).fl[0] & flLargo, flLargo);
      expect(e.riga(0).fl[1] & flSeguito, flSeguito);
      expect(e.riga(0).cp[2], 'a'.codeUnitAt(0));
      expect(e.cx, 3);
      expect(e.riga(0).testo(), '中a');
    });

    test('un ideogramma in ultima colonna va a capo intero', () {
      final e = nuovo(c: 4);
      scrivi(e, 'abc中');
      expect(e.riga(0).testo(), 'abc');
      expect(e.riga(1).testo(), '中');
    });

    test('scrivere sopra metà di un carattere largo lo toglie tutto', () {
      final e = nuovo();
      scrivi(e, '中\x1b[2GX');
      expect(e.riga(0).cp[0], 0x20);
      expect(e.riga(0).fl[0] & flLargo, 0);
      expect(e.riga(0).cp[1], 'X'.codeUnitAt(0));
    });

    test('UTF-8 spezzato fra due pacchetti', () {
      final e = nuovo();
      final byte = utf8.encode('aè中');
      e.scrivi(byte.sublist(0, 2)); // 'a' + primo byte di è
      e.scrivi(byte.sublist(2, 4)); // secondo byte di è + primo di 中
      e.scrivi(byte.sublist(4));
      expect(e.riga(0).testo(), 'aè中');
    });

    test('un byte di spazzatura non blocca il resto', () {
      final e = nuovo();
      e.scrivi([0x61, 0xff, 0x62]);
      expect(e.riga(0).testo(), 'ab');
    });

    test('un accento combinante non prende una cella', () {
      final e = nuovo();
      scrivi(e, 'éx');
      expect(e.riga(0).testo(), 'ex');
      expect(e.cx, 2);
    });
  });

  group('lo schermo alternativo', () {
    test('1049 salva, disegna a parte, e torna intatto', () {
      final e = nuovo(r: 3);
      scrivi(e, 'principale\x1b[2;4H');
      scrivi(e, '\x1b[?1049h');
      expect(e.sulloSchermoAlternativo, isTrue);
      expect(e.testoSchermo(), ['', '', '']);
      scrivi(e, 'vim');
      expect(e.riga(0).testo(), 'vim');
      scrivi(e, '\x1b[?1049l');
      expect(e.sulloSchermoAlternativo, isFalse);
      expect(e.riga(0).testo(), 'principale');
      expect(e.cy, 1);
      expect(e.cx, 3);
    });

    test('sull\'alternativo lo scorrimento non riempie lo scrollback', () {
      final e = nuovo(r: 2);
      scrivi(e, '\x1b[?1049h1\r\n2\r\n3');
      expect(e.scrollback, isEmpty);
    });
  });

  group('i modi', () {
    test('DECAWM spento: si resta sull\'ultima colonna', () {
      final e = nuovo(c: 4);
      scrivi(e, '\x1b[?7labcdefg');
      expect(e.riga(0).testo(), 'abcg');
      expect(e.cy, 0);
    });

    test('mouse, incolla fra parentesi, tasti cursore', () {
      final e = nuovo();
      scrivi(e, '\x1b[?1002h\x1b[?1006h\x1b[?2004h\x1b[?1h');
      expect(e.modoMouse, 1002);
      expect(e.mouseSgr, isTrue);
      expect(e.incollaFraParentesi, isTrue);
      expect(e.tastiCursoreApplicazione, isTrue);
      scrivi(e, '\x1b[?1002l');
      expect(e.modoMouse, 0);
    });

    test('inserimento (IRM) spinge a destra', () {
      final e = nuovo(c: 8);
      scrivi(e, 'abc\x1b[2G\x1b[4hX\x1b[4l');
      expect(e.riga(0).testo(), 'aXbc');
    });

    test('la grafica DEC disegna le cornici', () {
      final e = nuovo();
      scrivi(e, '\x1b(0lqk\x1b(Ba');
      expect(e.riga(0).testo(), '┌─┐a');
    });

    test('RIS rimette tutto a posto', () {
      final e = nuovo();
      scrivi(e, '\x1b[31m\x1b[?25l\x1b[3;3Habc\x1bc');
      expect(e.cursoreVisibile, isTrue);
      expect(e.cx, 0);
      expect(e.cy, 0);
      expect(e.testoSchermo().every((r) => r.isEmpty), isTrue);
    });
  });

  group('OSC', () {
    test('il titolo, con BEL e con ST', () {
      final e = nuovo();
      scrivi(e, '\x1b]0;primo\x07');
      expect(e.titolo, 'primo');
      scrivi(e, '\x1b]2;secondo\x1b\\');
      expect(e.titolo, 'secondo');
    });

    test('il titolo si tronca a 200', () {
      final e = nuovo();
      scrivi(e, '\x1b]0;${'x' * 5000}\x07a');
      expect(e.titolo.length, 200);
      expect(e.riga(0).testo(), 'a', reason: 'il resto non finisce a schermo');
    });

    test('OSC 7 dà la cartella, sciolta', () {
      final e = nuovo();
      scrivi(e, '\x1b]7;file://cachyos/home/giacomo/Documenti/Minerva%20Shell\x07');
      expect(e.cartella, '/home/giacomo/Documenti/Minerva Shell');
    });

    test('OSC 133: i marcatori dei blocchi con la riga assoluta', () {
      final e = nuovo(r: 2);
      scrivi(e, '\x1b]133;A\x07\$ \x1b]133;B\x07ls\r\n\x1b]133;C\x07a\r\nb\r\n\x1b]133;D;0\x07');
      final tipi = e.marcatori.map((m) => m.tipo).join();
      expect(tipi, 'ABCD');
      expect(e.marcatori[0].rigaAssoluta, 0);
      expect(e.marcatori[2].rigaAssoluta, 1);
      expect(e.marcatori[3].rigaAssoluta, 3);
      expect(e.marcatori[3].codice, 0);
    });

    test('OSC 133 D con codice e argomenti in più', () {
      final e = nuovo();
      scrivi(e, '\x1b]133;D;127;aid=42\x07');
      expect(e.marcatori.single.codice, 127);
    });

    test('OSC 52 non fa niente', () {
      final e = nuovo();
      scrivi(e, '\x1b]52;c;Y2lhbw==\x07a');
      expect(e.riga(0).testo(), 'a');
    });

    test('un DCS si legge e si butta', () {
      final e = nuovo();
      scrivi(e, 'a\x1bPqspazzatura\x1b\\b');
      expect(e.riga(0).testo(), 'ab');
    });
  });

  group('la misura', () {
    test('rimpicciolire manda le righe in cima nello scrollback', () {
      final e = nuovo(r: 4);
      scrivi(e, 'a\r\nb\r\nc\r\nd');
      e.ridimensiona(20, 2);
      expect(e.testoSchermo(), ['c', 'd']);
      expect(e.scrollback.map((r) => r.testo()), ['a', 'b']);
      expect(e.cy, 1);
    });

    test('rimpicciolire toglie prima le righe vuote in fondo', () {
      final e = nuovo(r: 4);
      scrivi(e, 'a\r\nb');
      e.ridimensiona(20, 2);
      expect(e.testoSchermo(), ['a', 'b']);
      expect(e.scrollback, isEmpty);
    });

    test('ingrandire riporta le righe dallo scrollback', () {
      final e = nuovo(r: 2);
      scrivi(e, 'a\r\nb\r\nc');
      e.ridimensiona(20, 4);
      expect(e.testoSchermo(), ['a', 'b', 'c', '']);
      expect(e.cy, 2);
    });

    test('stringere le colonne taglia, allargare conserva', () {
      final e = nuovo(c: 6);
      scrivi(e, 'abcdef');
      e.ridimensiona(3, 5);
      expect(e.riga(0).testo(), 'abc');
      e.ridimensiona(8, 5);
      expect(e.riga(0).testo(), 'abc');
      expect(e.cx, 2);
    });
  });

  group('lo sporco', () {
    test('si segnano solo le righe toccate', () {
      final e = nuovo(r: 5);
      e.pulisci();
      scrivi(e, '\x1b[3;1HX');
      expect(e.sporche, {2});
      expect(e.tuttoSporco, isFalse);
    });

    test('uno scorrimento intero sporca tutto', () {
      final e = nuovo(r: 2);
      scrivi(e, 'a\r\nb');
      e.pulisci();
      scrivi(e, '\r\nc');
      expect(e.tuttoSporco, isTrue);
    });
  });

  group('una sequenza vera', () {
    test('quello che stampa un prompt colorato di fish', () {
      final e = nuovo(c: 40);
      scrivi(e,
          '\x1b]133;A\x07\x1b[32m~/Progetti\x1b[0m \x1b[36mon\x1b[0m \x1b[1;35mmain\x1b[0m\r\n'
          '\x1b[32m❯\x1b[0m \x1b]133;B\x07');
      expect(e.riga(0).testo(), '~/Progetti on main');
      expect(e.riga(1).testo(), '❯');
      expect(e.cx, 2);
      expect(e.marcatori.map((m) => m.tipo).join(), 'AB');
    });

    test('htop-like: regione, grafica DEC, colori e cursore nascosto', () {
      final e = nuovo(c: 10, r: 4);
      scrivi(e, '\x1b[?1049h\x1b[?25l\x1b[1;3r\x1b[H\x1b(0lqqqk\x1b(B\x1b[2;1H\x1b[44m x \x1b[0m');
      expect(e.riga(0).testo(), '┌───┐');
      expect(e.riga(1).testo(), ' x');
      expect(e.riga(1).bg[1], colore256(4));
      expect(e.cursoreVisibile, isFalse);
      scrivi(e, '\x1b[?25h\x1b[?1049l');
      expect(e.sulloSchermoAlternativo, isFalse);
    });
  });
}
