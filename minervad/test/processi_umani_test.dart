import 'package:minervad/services/processi_umani.dart';
import 'package:test/test.dart';

void main() {
  group('che cos\'è questo processo', () {
    test('i pezzi di Minerva si spiegano da sé', () {
      expect(descrizione('qs', 'qs -p /tmp/shell.qml'), contains('scrivania'));
      expect(descrizione('minervad', 'minervad'), contains('servizio di Minerva'));
      expect(descrizione('Hyprland', 'Hyprland'), contains('compositore'));
    });

    test('i servizi di sistema hanno una riga che si legge senza sapere Linux', () {
      expect(descrizione('pipewire', 'pipewire'), contains('audio'));
      expect(descrizione('polkitd', 'polkitd'), contains('permesso'));
      expect(descrizione('agetty', 'agetty'), contains('Ctrl+Alt'));
    });

    // I nomi arrivano da `/proc/<pid>/comm` in tutte le forme che il kernel
    // usa: fra parentesi quadre i thread, con la barra i lavoratori numerati.
    test('i thread del kernel si riconoscono comunque siano scritti', () {
      expect(eDiSistema('kworker/0:1', 'kworker/0:1'), isTrue);
      expect(eDiSistema('[kworker/u16:3]', '[kworker/u16:3]'), isTrue);
      expect(eDiSistema('systemd-udevd', 'systemd-udevd'), isTrue);
    });

    test('i programmi dell\'utente NON sono di sistema', () {
      expect(eDiSistema('firefox', '/usr/lib/firefox/firefox'), isFalse);
      expect(eDiSistema('qs', 'qs -p x'), isFalse);
      expect(eDiSistema('alacritty', 'alacritty'), isFalse);
    });

    // `python3 /usr/bin/qualcosa` non dice niente scritto così: quello che
    // conta è il secondo pezzo.
    test('chi gira dentro un interprete si spiega col secondo pezzo', () {
      expect(descrizione('python3', 'python3 /usr/bin/grim'), contains('Fotografa'));
      expect(descrizione('sh', 'sh -c cliphist store'), contains('appunti'));
    });

    test('quello che non si sa non si inventa', () {
      expect(descrizione('roba-mai-vista', 'roba-mai-vista --con -argomenti'), '');
    });

    test('il nome mostrato è quello del programma, non del binario', () {
      expect(etichetta('qs', 'qs -p x'), 'Interfaccia di Minerva');
      expect(etichetta('soffice.bin', ''), 'LibreOffice');
      // Uno sconosciuto si mostra com'è, con l'iniziale maiuscola.
      expect(etichetta('pippo', 'pippo'), 'Pippo');
    });
  });

  group('come sta il computer', () {
    final calmo = [
      {'nome': 'firefox', 'comando': 'firefox', 'cpu': 3.0},
      {'nome': 'qs', 'comando': 'qs', 'cpu': 1.0},
    ];
    final affannato = [
      {'nome': 'firefox', 'comando': 'firefox', 'cpu': 71.0},
      {'nome': 'qs', 'comando': 'qs', 'cpu': 2.0},
    ];

    test('con poco da fare lo dice in due parole', () {
      expect(comeSta(calmo, 8, 40), 'Tutto tranquillo.');
    });

    // È la domanda per cui si apre un gestore attività: non «quanto», ma
    // «CHI». I cinque numeri in cima dicono già quanto.
    test('quando la ventola si sente, dice CHI', () {
      final f = comeSta(affannato, 78, 40);
      expect(f, contains('Firefox'));
      expect(f, contains('71%'));
    });

    test('se nessuno spicca, non accusa nessuno', () {
      final tanti = List.generate(
          20, (i) => {'nome': 'p$i', 'comando': 'p$i', 'cpu': 4.0});
      expect(comeSta(tanti, 80, 40), contains('non da un solo programma'));
    });

    // La memoria piena viene prima: un computer che sta per andare in swap
    // rallenta in un modo che nessuna percentuale di CPU spiega.
    test('la memoria quasi piena viene prima di tutto il resto', () {
      expect(comeSta(affannato, 90, 93), contains('memoria'));
    });
  });

// ─────────────────────────────────────────────────────────────────────────
//  Le finestre di Minerva sono tutte lo stesso binario
// ─────────────────────────────────────────────────────────────────────────
//
// Gestore file, Impostazioni, Attività, Anteprima, blocco e accesso girano
// tutte come `qs`. Guardando il solo nome sono la stessa cosa, e nel gestore
// attività si vedeva: la riga si chiamava «Attività» e sotto diceva «La
// scrivania: barra, dock, menu e finestre di Minerva» — la descrizione di
// un'ALTRA finestra. Quale sia sta scritto nella riga di comando.
  group('le sei finestre di Minerva si distinguono', () {
    const base = 'qs -p /opt/minerva/minerva-shell/';
    test('ognuna dice quale è', () {
      // `app.qml` e non `monitor.qml`: Calcolatrice, Editor, Anteprima e
      // Attività girano tutte in quel processo. Finché mancava, in Attività
      // comparivano come «qs» — il nome di nessuno, che è esattamente il
      // difetto che questo gruppo esiste per evitare.
      expect(descrizione('qs', '${base}app.qml'), contains('attività'));
      expect(descrizione('qs', '${base}minervamedia.qml'), contains('lettore'));
      expect(descrizione('qs', '${base}filemanager.qml'), contains('gestore file'));
      expect(descrizione('qs', '${base}settings.qml'), contains('impostazioni'));
      expect(descrizione('qs', '${base}viewer.qml'), contains('immagini'));
      expect(descrizione('qs', '${base}blocco.qml'), contains('blocco'));
      expect(descrizione('qs', '${base}shell.qml'), contains('scrivania'));
    });

    test('e nessuna prende la descrizione di un\'altra', () {
      final a = descrizione('qs', '${base}app.qml');
      final b = descrizione('qs', '${base}shell.qml');
      expect(a, isNot(equals(b)));
    });
  });

  // `/proc/<pid>/comm` per un binario Dart compilato dice `dart:minervad`: la
  // macchina virtuale ci mette il proprio nome davanti. Nel gestore attività
  // si leggeva «Dart:minervad», che è il nome di nessuno.
  group('i nomi che il sistema scrive a modo suo', () {
    test('il demone si riconosce anche scritto dart:minervad', () {
      expect(etichetta('dart:minervad', 'minervad'), 'Demone di Minerva');
      expect(descrizione('dart:minervad', 'minervad'), contains('servizio di Minerva'));
    });

    test('e i thread del kernel non ci rimettono', () {
      expect(eDiSistema('kworker/u16:3', 'kworker/u16:3'), isTrue);
    });
  });

  // ── I nostri, tutti quanti ────────────────────────────────────────────
  //
  // Fino al 3 settembre 2026 questa tabella conosceva `hyprland` e non
  // `minerva-wayland`. In Minerva Attività il processo che disegna l'intera
  // scrivania compariva col nome nudo e senza una riga che dicesse cos'è,
  // mentre il compositore che non gira più aveva la sua descrizione completa.
  //
  // Una tabella scritta a mano dimentica per costruzione: questa prova nomina
  // i processi che una sessione di Minerva ha SEMPRE, e chiede che sappiano
  // dire chi sono. Se un domani ne nasce un altro, si aggiunge qui — ed è un
  // posto in cui si passa, perché diventa rosso.
  group('i processi che Minerva ha sempre sanno dire chi sono', () {
    for (final p in ['minerva-wayland', 'minervad', 'minerva-polkit', 'qs']) {
      test('«$p» ha un nome e una descrizione', () {
        expect(etichetta(p, p), isNotEmpty);
        expect(etichetta(p, p).toLowerCase(), isNot(equals(p)),
            reason: 'mostra il nome del binario invece di un nome per chi legge');
        // La descrizione dice cosa FA, e non deve nominare Minerva: «chiede
        // la password quando serve il permesso di root» è la riga giusta per
        // `minerva-polkit`, e infilarci il nome del prodotto la peggiorerebbe.
        // Quello che conta è che ci sia e che non sia il nome del binario.
        final d = descrizione(p, p);
        expect(d, isNotEmpty,
            reason: 'in Attività comparirebbe senza dire cos\'è');
        expect(d, isNot(equals(p)));
        expect(d.length, greaterThan(15),
            reason: 'una riga di tre parole non spiega niente a chi non sa '
                'cos\'è un compositore');
      });
    }
  });
}
