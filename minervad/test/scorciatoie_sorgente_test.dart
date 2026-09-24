// La sorgente delle scorciatoie e il file che ne esce.
//
// `config/scorciatoie.minerva` è la verità: novantacinque scelte nostre nel
// vocabolario nostro.
//
// ── C'era un secondo prodotto, e non c'è più ──────────────────────────────
//
// `config/hypr/keybinds.conf`: le stesse scelte tradotte nella lingua di
// Hyprland, generate e messe sotto git perché Hyprland le legge prima che il
// demone esista. Metà di questo file sorvegliava che i due non andassero alla
// deriva — due file che dicono la stessa cosa ci vanno sempre.
//
// Il 2 settembre 2026 la sessione Hyprland è sparita, e con lei il prodotto e
// il suo generatore. Resta l'unico che conta: le righe `scorciatoia …` che la
// shell manda al nostro compositore (`perMinervaWayland`).
//
// Le prove che confrontavano sorgente e prodotto se ne sono andate con lui:
// una prova che confronta con un file che non esiste dice verde per
// costruzione, che è peggio di nessuna prova.

import 'dart:io';
import 'package:test/test.dart';
import 'package:minervad/services/scorciatoie.dart';

File _file(String relativo) {
  for (final base in ['.', '..', '../..']) {
    final f = File('$base/$relativo');
    if (f.existsSync()) return f;
  }
  fail('non trovo $relativo');
}

void main() {
  late Scorciatoie sorgente;

  setUpAll(() {
    sorgente = Scorciatoie.leggi(_file('config/scorciatoie.minerva').readAsStringSync());
  });

  group('la sorgente si legge tutta', () {
    test('tutte le scorciatoie, nessuna riga incomprensibile', () {
      // `leggi` lancia su una riga che non capisce: se siamo qui, le ha
      // capite tutte. Il numero si aggiorna a mano quando se ne aggiunge
      // una: l'ultima è Super+O, l'Isola (24 settembre 2026).
      expect(sorgente.tutte.length, 97);
    });

    test('tutte hanno un tasto', () {
      for (final s in sorgente.tutte) {
        expect(s.tasto, isNotEmpty, reason: 'riga ${s.riga}: «${s.tasti}»');
      }
    });

    test('una sola sta fuori dal promemoria, ed è quella giusta', () {
      final nascoste = sorgente.tutte.where((s) => s.categoria == null).toList();
      expect(nascoste.length, 1);
      expect(nascoste.first.azione, contains('switchercommit'),
          reason: 'il rilascio di Alt conferma l\'Alt+Tab: è il seguito di '
              'un\'altra scorciatoia, non una da imparare');
    });
  });

  group('il vocabolario è chiuso', () {
    test('ogni azione usata sa tradursi', () {
      // `perMinervaWayland` lancia su un'azione che non conosce. Chiamarlo QUI
      // vuol dire che nessuna scorciatoia resterà muta perché qualcuno ha
      // inventato un verbo senza aggiungerlo al traduttore.
      //
      // Prima si chiamava `perHyprland`, per la stessa ragione: era l'unico
      // dei due prodotti che si rifiutava di generare una riga che non
      // capiva. Adesso il traduttore è uno solo, ed è quello giusto.
      expect(() => sorgente.perMinervaWayland(), returnsNormally);
    });

    test('nessuna scorciatoia chiama un programma che non esiste più', () {
      // ── Il difetto: una scorciatoia che si vede e non fa niente ───────
      //
      // Trovato il 3 settembre 2026 leggendo il file. `$mod SHIFT R` diceva
      // `avvia: hyprctl reload && hyprctl notify …`. Sotto minerva-wayland
      // `hyprctl` non esiste: la scorciatoia compariva nel promemoria F1,
      // premendola non succedeva niente, e non c'era nemmeno un errore —
      // quella riga finisce in una shell che non ha dove scriverlo.
      //
      // Non l'aveva presa nessuna prova perché tutte guardavano la FORMA
      // (c'è un tasto? l'azione si traduce?) e nessuna il CONTENUTO di un
      // `avvia:`. Una riga sintatticamente perfetta che invoca un fantasma
      // passa ogni controllo di forma.
      //
      // L'elenco è chiuso apposta: si nomina quello che è stato tolto, non si
      // prova a indovinare cosa esiste sulla macchina di chi legge — una prova
      // che dipende dai pacchetti installati diventa rossa da sola un giorno
      // a caso.
      const spariti = ['hyprctl', 'hyprpaper', 'hypridle', 'hyprlock',
                       'hyprpicker'];
      for (final s in sorgente.tutte) {
        if (!s.azione.startsWith('avvia:')) continue;
        final comando = s.azione.substring('avvia:'.length).trim();
        for (final morto in spariti) {
          expect(comando.contains(morto), isFalse,
              reason: '«${s.tasto}» lancia «$morto», che non esiste più: '
                  'la scorciatoia si vede nel promemoria e non fa niente');
        }
      }
    });

    test('le azioni nostre non sono più della metà legate a Hyprland', () {
      // Misura, non regola: dice quanto costerebbe cambiare compositore.
      // `minerva:` e `avvia:` sono neutre — l'azione è nostra o è universale.
      final tutte = sorgente.tutte;
      final neutre = tutte
          .where((s) =>
              s.azione.startsWith('minerva:') || s.azione.startsWith('avvia:'))
          .length;
      expect(neutre, greaterThanOrEqualTo(48),
          reason: 'erano 48 su 95 l\'11 agosto 2026: se scendono, stiamo '
              'riportando dentro semantica del compositore');
    });
  });

  // ── E lo stesso, per minerva-wayland ─────────────────────────────────
  //
  // Il secondo prodotto dalla stessa sorgente. È qui che si vede se quel file
  // è davvero la sorgente unica o soltanto «la configurazione di Hyprland con
  // un altro nome».

  group('le righe per minerva-wayland', () {
    test('le variabili arrivano sciolte, o la riga non esce affatto', () {
      // Un `$mod` che arrivasse così sarebbe un modificatore che non esiste,
      // cioè una scorciatoia che non scatta mai. E non darebbe nessun errore:
      // il compositore registrerebbe la riga e il tasto non farebbe niente.
      final righe = sorgente.perMinervaWayland(anche: {'minerva': '/casa/mia'});
      for (final r in righe) {
        expect(r, isNot(contains(r'$')), reason: r);
      }
      expect(righe.any((r) => r.startsWith('scorciatoia SUPER K - minerva:')),
          isTrue, reason: righe.take(4).join(' | '));

      // E senza chi la dichiara, quella riga NON esce: registrarla vorrebbe
      // dire mangiarsi il tasto e non fare la cosa.
      final zoppe = sorgente.perMinervaWayland();
      for (final r in zoppe) {
        expect(r, isNot(contains(r'$')), reason: r);
      }
      expect(zoppe.any((r) => r.contains('minerva-blocca')), isFalse);
      expect(zoppe.length, lessThan(righe.length));
    });

    test('e anche quelle che la sorgente non dichiara', () {
      // `$minerva` la dichiara il compositore, non la sorgente: sotto Hyprland
      // sta in `~/.config/hypr/minerva-paths.conf`. Senza, «blocca lo schermo»
      // diventa un comando che la shell esegue senza lamentarsi e che non fa
      // niente.
      final righe = sorgente.perMinervaWayland(anche: {'minerva': '/casa/mia'});
      expect(righe.any((r) => r.contains('/casa/mia/scripts/minerva-blocca')),
          isTrue);
    });

    test('la prima riga azzera, sempre', () {
      // Aggiungere e basta vorrebbe dire una tabella che cresce a ogni
      // ricarica, con dentro le regole di ieri.
      expect(sorgente.perMinervaWayland().first, 'scorciatoie azzera');
    });

    test('quattro campi prima dell\'azione, e il flag NON in fondo', () {
      // L'argomento di `avvia` è una riga di comando intera: un flag in coda
      // sarebbe indistinguibile dall'ultima parola del comando.
      for (final r in sorgente.perMinervaWayland().skip(1)) {
        final p = r.split(' ');
        expect(p[0], 'scorciatoia', reason: r);
        expect(p.length, greaterThanOrEqualTo(5), reason: r);
        // I flag si attaccano col `+`, come i modificatori: `-`,
        // `bloccato`, `rilascio`, `tocco`, `bloccato+rilascio`.
        for (final f in p[3].split('+')) {
          expect(f, anyOf('-', 'bloccato', 'rilascio', 'tocco'), reason: r);
        }
        expect(p[4], contains(RegExp(r'^[a-z-]+')), reason: r);
      }
    });

    test('l\'Alt che conferma l\'Alt+Tab arriva col suo flag', () {
      // Senza, `ALT Tab` apre il selettore delle finestre e **nessuno lo
      // chiude**: a chiuderlo è il momento in cui si molla Alt. Il riquadro
      // resta aperto sullo schermo e la finestra scelta non prende il fuoco.
      //
      // Ed è peggio di una scorciatoia che manca: la riga partiva lo stesso,
      // senza flag, e il compositore la registrava come una scorciatoia della
      // PRESSIONE su Alt_L. Non scattava mai — Alt è già premuto quando lo si
      // preme — quindi il gesto era rotto in silenzio da tutte e due le parti.
      final righe = sorgente.perMinervaWayland();
      final commit = righe.firstWhere(
          (r) => r.contains('switchercommit'),
          orElse: () => '');
      expect(commit, isNotEmpty,
          reason: 'la conferma dell\'Alt+Tab non viene mandata affatto');
      expect(commit.split(' ')[3].split('+'), contains('rilascio'),
          reason: 'manda la conferma senza dire che è al rilascio: '
              'il compositore la aspetterebbe alla pressione. $commit');

      // ── E NON deve essere un «tocco» ─────────────────────────────────
      //
      // È la trappola del flag nuovo, ed è a un carattere di distanza.
      // «tocco» vuol dire «premuto e lasciato DA SOLO», e serve al gesto di
      // Super che apre il menù. Qui sarebbe esattamente il contrario di ciò
      // che serve: l'Alt che conferma l'Alt+Tab deve scattare **proprio**
      // quando in mezzo è stato premuto Tab. Con «tocco» non scatterebbe
      // mai, e il selettore resterebbe aperto sullo schermo — cioè lo stesso
      // difetto di prima, tornato da un'altra porta.
      expect(commit.split(' ')[3].split('+'), isNot(contains('tocco')),
          reason: 'la conferma dell\'Alt+Tab è marcata «tocco»: non '
              'scatterà mai, perché in mezzo si preme Tab. $commit');
    });

    test('il tasto Super da solo apre il menù, e col flag giusto', () {
      // Il difetto del 30 agosto 2026, e non poteva funzionare in NESSUNO dei
      // due compositori: la riga diceva `SUPER SUPER`, e «SUPER» non è il nome
      // di un tasto — è il nome di un modificatore. Verificato chiamando xkb:
      // `xkb_keysym_from_name("SUPER")` risponde NoSymbol. Il nostro
      // compositore rifiutava la riga; Hyprland la leggeva come «Super mentre
      // tieni premuto Super», che è vero nell'istante in cui premi Super —
      // quindi il menù si apriva anche in mezzo a Super+E.
      final righe = sorgente.perMinervaWayland();
      final menu = righe.firstWhere((r) => r.endsWith('minerva:appmenu')
          && r.contains('Super'), orElse: () => '');
      expect(menu, isNotEmpty,
          reason: 'il gesto «tocca Super» non viene mandato affatto');
      final p = menu.split(' ');
      expect(p[2], 'Super_L',
          reason: 'il tasto deve avere un nome che xkb conosce: «SUPER» non '
              'esiste, «Super_L» sì. $menu');
      expect(p[3].split('+'), contains('tocco'),
          reason: 'senza «tocco» il menù si aprirebbe alla fine di ogni '
              'Super+qualcosa, cioè dopo quarantatré scorciatoie. $menu');
    });

    // Qui c'era «e la riga del tocco NON finisce nel file di Hyprland».
    // Hyprland ha `bindr`, che scatta a OGNI rilascio e non sa dire «premuto e
    // lasciato da solo»: la riga del tocco restava fuori dal suo file, e
    // questa prova verificava che ci fosse scritto perché. Il file non c'è
    // più. Il nostro compositore il tocco lo sa fare, e la riga ci arriva —
    // lo verifica «il tasto Super da solo apre il menù» qui sopra.

    test('quelle che restano fuori sono solo di Hyprland', () {
      // ── Erano venti. Il 31 agosto 2026 sono diventate OTTO ──────────────
      //
      // Le dodici recuperate sono le frecce: `fuoco`, `sposta-finestra` e
      // `ridimensiona`. Erano saltate con un ragionamento giusto e una
      // conclusione sbagliata — «vogliono dire qualcosa solo dove c'è una
      // griglia» — e intanto comparivano nel promemoria F1 senza fare niente.
      //
      // Le otto che restano ci restano per due ragioni diverse, e vanno tenute
      // distinte:
      //
      //   * QUATTRO sono gesti col mouse (`mouse:272`, `mouse:273`,
      //     `mouse_down`, `mouse_up`). Non sono tasti della tastiera e non
      //     hanno un nome XKB: come SCORCIATOIE non possono esistere. **Ma i
      //     gesti funzionano tutti e quattro**, fatti dal compositore dov'è
      //     giusto farli — `cursore_rotella` per la rotellina, e
      //     `cursore_bottone` per Super+trascina e Super+destro. Le righe
      //     restano nella sorgente perché sono la documentazione del gesto e
      //     finiscono nel promemoria F1.
      //   * QUATTRO sono concetti che in Minerva non esistono: i gruppi a
      //     schede e la scrivania speciale. Il tiling è stato tolto a luglio,
      //     e queste sono rimaste indietro.
      //
      // Se questo numero risale, qualcuno ha aggiunto una riga che non arriva
      // da nessuna parte: si guarda l'elenco e si decide, invece di scoprirlo
      // premendo un tasto che non fa niente.
      final fuori = sorgente.saltatePerMinervaWayland;
      expect(fuori.length, 8, reason: fuori.join('\n'));
      for (final f in fuori) {
        expect(
            f,
            anyOf(
              contains('gruppo'),
              contains('scrivania-speciale'),
              contains('special:'),
              contains('mouse'),
            ),
            reason: 'questa è rimasta fuori e non si sa perché: $f');
      }
    });

    test('e le frecce ARRIVANO, tutte e dodici', () {
      // La prova che il recupero del 31 agosto 2026 non si perda per strada:
      // dodici righe che stavano nel promemoria e non facevano niente.
      final righe = sorgente.perMinervaWayland();
      final quante = righe
          .where((r) =>
              r.contains('fuoco:') ||
              r.contains('sposta-finestra:') ||
              r.contains('ridimensiona:'))
          .length;
      expect(quante, 12,
          reason: 'quattro frecce per tre azioni: se scende, quei tasti sono '
              'tornati a non fare niente');
    });

    test('il volume e la luminosità valgono anche a schermo bloccato', () {
      // Sono le uniche cose che ha senso poter fare senza aver sbloccato. Se
      // questo flag si perdesse per strada, alzare il volume da bloccati
      // smetterebbe di funzionare — e nessuno saprebbe dire da quando.
      final righe = sorgente.perMinervaWayland();
      final volume = righe.firstWhere((r) => r.contains('XF86AudioRaiseVolume'));
      expect(volume.split(' ')[3], 'bloccato', reason: volume);
      final k = righe.firstWhere((r) => r.contains('minerva:cheatsheet'));
      expect(k.split(' ')[3], '-', reason: k);
    });

    test('nessun tasto che il compositore non sappia nominare', () {
      // `mouse_down` non è un tasto della tastiera e non ha un nome XKB: il
      // compositore risponderebbe «il tasto non esiste», e la riga sarebbe
      // stata scritta per niente.
      for (final r in sorgente.perMinervaWayland().skip(1)) {
        expect(r.split(' ')[2], isNot(startsWith('mouse')), reason: r);
      }
    });
  });
}
