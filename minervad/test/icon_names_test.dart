import 'dart:io';
import 'package:test/test.dart';
import 'package:minervad/core/minerva_paths.dart';
import 'package:minervad/services/icon_names.dart';
import 'package:minervad/services/icon_resolver.dart';

/// La tabella delle icone classiche è un ponte fra due file che non si
/// conoscono: `icon_names.dart` qui nel demone e `minerva-shell/ui/Icon.qml`
/// nella shell. Nessuno dei due può accorgersi da solo se l'altro cambia —
/// una chiave scritta male non dà nessun errore, dà un'icona che ogni tanto
/// non compare. Queste prove sono l'unico posto in cui i due si guardano.
void main() {
  final iconQml = File('${MinervaPaths.installRoot}/minerva-shell/ui/Icon.qml');

  group('nomi delle icone', () {
    test('ogni nome tradotto esiste davvero fra i tracciati della shell', () {
      final sorgente = iconQml.readAsStringSync();

      final mancanti = <String>[];
      for (final nome in minervaIconNames.keys) {
        // ── I nomi «cartella-*» sono un caso a parte, e voluto ───────────
        //
        // Servono a chiedere al TEMA DI ICONE il disegno che ha per una
        // cartella particolare — Documenti con un foglio, Immagini con una
        // fotografia. Il tratto di Minerva invece non ha una cartella diversa
        // per ogni contenuto, e non deve averla: il nostro segno è uno solo.
        //
        // Non sono quindi nomi «dimenticati»: sono nomi che di proposito
        // ricadono su «folder», e `Icon.qml` lo fa esplicitamente. Questa
        // prova continua a servire perché controlla che quel ripiego CI SIA:
        // senza, con le icone di Minerva accese le cartelle di casa
        // resterebbero righe vuote.
        if (nome.startsWith('cartella-')) continue;
        // I tracciati sono scritti come  "settings":  "M12 5.5a…",
        if (!sorgente.contains('"$nome":')) mancanti.add(nome);
      }

      expect(mancanti, isEmpty,
          reason: 'nomi tradotti che la shell non disegna: '
              '${mancanti.join(", ")}');
    });

    // ── L'altra direzione, che mancava ──────────────────────────────────
    //
    // La prova qui sopra guarda da una parte sola: che ogni nome TRADOTTO sia
    // disegnato. Non si accorge del contrario — un tracciato nostro senza
    // controparte classica — e quello è il difetto che si vede.
    //
    // Giacomo, 18 agosto 2026: «in impostazioni e nel file manager sul lato
    // sinistro non sono tutte del set icone selezionate». Non mancava niente:
    // quindici tracciati su ottantadue non erano in questa tabella, e con un
    // tema classico acceso restavano disegnati da Minerva in mezzo agli altri.
    // Cinque erano segni — i comandi del lettore, i tre puntini — e devono
    // restare nostri; dieci erano dimenticanze.
    //
    // Da qui in poi la differenza fra le due cose va DICHIARATA in `_segni`.
    test('ogni tracciato o è tradotto o è dichiarato un segno', () {
      final sorgente = iconQml.readAsStringSync();

      final corpo = sorgente.split('readonly property var _paths: ({');
      expect(corpo.length, 2,
          reason: 'non trovo la tabella dei tracciati in Icon.qml');
      final tracciati = RegExp(r'^\s*"([A-Za-z0-9_-]+)":', multiLine: true)
          .allMatches(corpo[1])
          .map((m) => m.group(1)!)
          .toSet();
      expect(tracciati.length, greaterThan(60),
          reason: 'ne ho letti troppo pochi: la forma del file è cambiata');

      final segni = RegExp(r'readonly property var _segni:\s*\[([^\]]*)\]')
          .firstMatch(sorgente);
      expect(segni, isNotNull,
          reason: 'Icon.qml non dichiara più quali nomi restano disegnati: '
              'senza quell\'elenco, «tradotto» e «dimenticato» tornano a '
              'essere la stessa cosa');
      final dichiarati = RegExp('"([A-Za-z0-9_-]+)"')
          .allMatches(segni!.group(1)!)
          .map((m) => m.group(1)!)
          .toSet();

      for (final s in dichiarati) {
        expect(tracciati, contains(s),
            reason: '«$s» è dichiarato un segno ma non è disegnato da nessuna '
                'parte');
      }

      final orfani = tracciati
          .where((n) => !minervaIconNames.containsKey(n) && !dichiarati.contains(n))
          .toList()
        ..sort();
      expect(orfani, isEmpty,
          reason: 'tracciati senza controparte classica e non dichiarati '
              'segni: ${orfani.join(", ")}. Con un tema di icone acceso '
              'restano disegnati da Minerva in mezzo agli altri: o si '
              'traducono qui, o si mettono in `_segni` di Icon.qml.');
    });

    test('i nomi «cartella-*» ricadono su «folder» invece di sparire', () {
      final sorgente = iconQml.readAsStringSync();
      expect(sorgente.contains('cartella-'), isTrue,
          reason: 'Icon.qml non conosce il ripiego dei nomi «cartella-*»: '
              'con le icone di Minerva accese, Documenti, Immagini, Musica e '
              'le altre resterebbero righe senza icona');
      expect(sorgente.contains('_paths["folder"]'), isTrue,
          reason: 'il ripiego dei nomi «cartella-*» non punta a «folder»');
    });

    test('nessun candidato ripetuto dentro la stessa voce', () {
      for (final voce in minervaIconNames.entries) {
        expect(voce.value.toSet().length, voce.value.length,
            reason: 'la voce "${voce.key}" ripete un candidato');
      }
      expect(minervaIconNames.values.every((c) => c.isNotEmpty), isTrue);
    });

    test('«sliders» e «settings» non finiscono sulla stessa icona', () {
      // Sono due disegni diversi per noi — le manopole e l'ingranaggio — e
      // nel pannello di controllo stanno uno accanto all'altro: se il primo
      // candidato coincide, «Animazioni» e «Impostazioni» diventano gemelli.
      expect(minervaIconNames['sliders']!.first,
          isNot(equals(minervaIconNames['settings']!.first)));
    });
  });

  group('risoluzione nel tema', () {
    test('hicolor da solo non traduce quasi niente, e non è un errore', () {
      // hicolor è il tema di riserva della specifica freedesktop: contiene le
      // icone delle applicazioni installate, non quelle dell'interfaccia. Se
      // un giorno questa prova cominciasse a trovarci dentro tutto vorrebbe
      // dire che il risolutore sta pescando da un altro tema senza dirlo.
      final resolver = IconResolver();
      resolver.setTheme('hicolor');
      final mappa = resolveMinervaIcons(resolver);
      expect(mappa.length, lessThan(minervaIconNames.length));
    });

    test('un nome inventato non ripiega sull\'icona generica', () {
      // È la ragione per cui `resolveMinervaIcons` chiede `generic: false`:
      // col ripiego acceso, un nome che nessun tema conosce tornerebbe
      // l'icona dell'eseguibile generico, e nella barra comparirebbe un
      // ingranaggio al posto di «ordina» — peggio di un'icona mancante,
      // perché sembra voluto.
      final resolver = IconResolver();
      expect(resolver.resolve('minerva-icona-che-non-esiste', generic: false),
          isEmpty);
    });

    test('i temi installati si elencano senza quelli di soli puntatori', () {
      final temi = IconResolver().listThemes();
      // Su un computer con Hyprland c'è sempre almeno hicolor.
      expect(temi, contains('hicolor'));
      // I temi di cursori dichiarano `index.theme` ma non hanno cartelle di
      // icone: nell'elenco delle Impostazioni sarebbero voci che non cambiano
      // niente.
      for (final t in temi) {
        expect(t.toLowerCase().contains('cursor'), isFalse,
            reason: '"$t" è un tema di puntatori, non di icone');
      }
    });

    test('l\'elenco mostra le famiglie, non le varianti chiara e scura', () {
      // «Colloid», «Colloid-Dark» e «Colloid-Light» sono lo stesso tema
      // colorato per due sfondi diversi. Mostrarli tutti e tre vuol dire
      // chiedere a chi guarda di scegliere per quale sfondo va bene
      // un'icona — che è una cosa che Minerva sa e lui no. Giacomo aveva
      // scelto «-Light» su un'interfaccia scura, e nel pannello di controllo
      // l'ingranaggio di «Animazioni» c'era e non si vedeva.
      final temi = IconResolver().listThemes();
      for (final t in temi) {
        expect(IconResolver.famiglia(t), equals(t),
            reason: '"$t" è una variante, non una famiglia');
      }
    });

    test('la famiglia si ricava togliendo la desinenza dello sfondo', () {
      expect(IconResolver.famiglia('Colloid-Light'), 'Colloid');
      expect(IconResolver.famiglia('Papirus-Dark'), 'Papirus');
      expect(IconResolver.famiglia('breeze-dark'), 'breeze');
      expect(IconResolver.famiglia('Tela-light'), 'Tela');
      // Un tema che non ha varianti resta com'è.
      expect(IconResolver.famiglia('hicolor'), 'hicolor');
      expect(IconResolver.famiglia('Adwaita'), 'Adwaita');
      // E una desinenza che è tutto il nome non lascia una famiglia vuota.
      expect(IconResolver.famiglia('-Dark'), '-Dark');
    });

    test('scegliere una variante vale come scegliere la sua famiglia', () {
      // Nelle impostazioni di Giacomo c'è ancora «Colloid-Light», scritto
      // quando l'elenco mostrava anche le varianti. Deve continuare a valere,
      // e valere come «Colloid».
      final resolver = IconResolver();
      resolver.setTheme('Colloid-Light');
      expect(resolver.chosenTheme, 'Colloid');
    });

    test('su fondo scuro si prende la variante scura, se esiste', () {
      final resolver = IconResolver();
      final temi = resolver.listThemes();
      // La prova ha senso solo dove c'è davvero una famiglia con due
      // varianti: su una macchina con il solo hicolor non c'è niente da
      // scegliere, e non è un errore.
      final conVariante = temi.where((t) {
        final r = IconResolver();
        r.setInterfacciaScura(true);
        return r.variantePer(t) != t;
      });
      for (final fam in conVariante) {
        resolver.setInterfacciaScura(true);
        final scura = resolver.variantePer(fam);
        expect(scura.toLowerCase(), endsWith('dark'),
            reason: 'su fondo scuro "$fam" deve dare la variante scura');
        resolver.setInterfacciaScura(false);
        final chiara = resolver.variantePer(fam);
        expect(chiara, isNot(equals(scura)),
            reason: 'cambiando sfondo "$fam" deve cambiare variante');
      }
    });
  });

  // ── L'altra metà: chi si tiene il tracciato NOSTRO ────────────────────
  //
  // Il gruppo in cima controlla che ogni nostro disegno abbia un nome
  // classico. Ma un nome tradotto non basta: al punto di chiamata si può
  // scrivere `alwaysDrawn: true`, e allora l'icona del tema non viene
  // guardata nemmeno. Trenta punti nella shell lo fanno.
  //
  // Giacomo, 23 agosto 2026: «alcune icone se cambio il tema icone rimane con
  // le icone base di minerva». Ha ragione, e i motivi sono DUE, non uno:
  //
  //  1. `_segni` — cinque disegni che sono nostri per scelta (i comandi del
  //     lettore, i tre puntini);
  //  2. **la tinta** — ed è il motivo vero, quello che si vede di più.
  //     `Icon.qml` disegna TRACCIATI, che prendono qualunque colore; un tema
  //     consegna FILE già colorati, che non si possono ricolorare (e non si
  //     può nemmeno rimediare con un effetto, perché le nostre app disegnano
  //     col processore e lì `MultiEffect` non disegna niente). Quindi un'icona
  //     che deve essere grigio pallido, o del colore della batteria che si sta
  //     scaricando, resta per forza la nostra.
  //
  // Questa prova non vieta niente: pretende che uno dei due motivi ci sia.
  // Senza, `alwaysDrawn: true` torna a essere una parola che si copia da
  // un'altra riga, e le icone smettono di seguire il tema una alla volta.
  group('chi si tiene il disegno di Minerva ha un motivo', () {
    test('ogni alwaysDrawn è o un segno o un\'icona tinta', () {
      final sorgente = iconQml.readAsStringSync();
      final segni = RegExp(r'readonly property var _segni:\s*\[([^\]]*)\]')
          .firstMatch(sorgente);
      final dichiarati = RegExp('"([A-Za-z0-9_-]+)"')
          .allMatches(segni!.group(1)!)
          .map((m) => m.group(1)!)
          .toSet();

      final radice = Directory('${MinervaPaths.installRoot}/minerva-shell');
      final forzato = RegExp(r'alwaysDrawn:\s*true');
      final senzaMotivo = <String>[];
      var visti = 0;

      for (final f in radice.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.qml')) continue;
        // `ui/Icon.qml` dichiara la proprietà e la spiega: le sue occorrenze
        // sono documentazione, non usi.
        if (f.path.endsWith('/ui/Icon.qml')) continue;
        final righe = f.readAsLinesSync();
        for (var i = 0; i < righe.length; i++) {
          if (!forzato.hasMatch(righe[i])) continue;
          if (righe[i].trimLeft().startsWith('//')) continue;
          visti++;
          // Il blocco `Ui.Icon { … }` intorno: si risale all'apertura e si
          // scende alla graffa di chiusura.
          var su = i;
          while (su > 0 && !righe[su].contains('Icon {')) {
            su--;
          }
          var giu = i;
          while (giu < righe.length - 1 && righe[giu].trim() != '}') {
            giu++;
          }
          final blocco = righe.sublist(su, giu + 1).join('\n');
          final tinta = RegExp(r'^\s*color:', multiLine: true).hasMatch(blocco);
          final nome = RegExp(r'\bname:\s*"([A-Za-z0-9_-]+)"').firstMatch(blocco);
          final eSegno = nome != null && dichiarati.contains(nome.group(1));
          if (!tinta && !eSegno) {
            senzaMotivo.add('${f.path.split('minerva-shell/').last}:${i + 1}');
          }
        }
      }

      expect(visti, greaterThan(10),
          reason: 'ne ho letti troppo pochi: è cambiato il nome della '
              'proprietà, e questa prova sta guardando il vuoto');
      expect(senzaMotivo, isEmpty,
          reason: 'qui si forza il disegno di Minerva senza tingerlo e senza '
              'che sia un segno: col tema di icone acceso resta il nostro in '
              'mezzo agli altri, e nessuno sa perché. '
              '${senzaMotivo.join(", ")}');
    });
  });
}
