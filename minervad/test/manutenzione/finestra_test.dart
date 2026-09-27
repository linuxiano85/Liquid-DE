import 'dart:io';

import 'package:test/test.dart';
import '../codice_vivo.dart';

// Le due guardie della finestra di Manutenzione.
//
// Sono guardie di TESTO su file QML, come `impostazioni_sezioni_test.dart`, e
// per la stessa ragione: quello che sorvegliano non lo prende nessuna prova
// unitaria, perché non è un calcolo sbagliato — è una cosa che sembra fatta e
// non lo è, e sullo schermo non dà nessun errore.
//
// Tutte e due nascono da un difetto vero, visto da Giacomo il 9 settembre
// 2026 guardando la finestra.
void main() {
  final finestra =
      File('../minerva-shell/manutenzione/Manutenzione.qml').codiceVivo();

  group('una mappa non si riassegna a sé stessa', () {
    // ── Il difetto ───────────────────────────────────────────────────────
    //
    // Giacomo: «non riesco a selezionare una singola voce ad esempio se non
    // voglio cancellare tutto».
    //
    //     var m = finestra.scelte;   // lo STESSO oggetto
    //     m[id] = m[id] !== true;
    //     finestra.scelte = m;       // riassegnato a sé stesso
    //
    // In QML una `property var` riassegnata allo stesso oggetto non è un
    // cambiamento: il valore è identico perché è lo stesso indirizzo, e i
    // legami che leggono `scelte[id]` non si svegliano. Spuntare una voce
    // non faceva niente.
    //
    // Visto rosso e verde a mano il 9 settembre, sulla finestra viva: col
    // codice vecchio il conto in fondo restava a 6,70 GB togliendo una cache
    // da 4,92; col codice nuovo passa a 1,78.
    test('le mappe di stato si copiano prima di scriverci dentro', () {
      final mappe = RegExp(r'property var (scelte|aperte)')
          .allMatches(finestra)
          .map((m) => m.group(1)!)
          .toSet();
      expect(mappe, {'scelte', 'aperte'},
          reason: 'se questi nomi cambiano, la guardia va aggiornata: una '
              'guardia che non trova più il suo bersaglio passa sempre');

      final colpe = <String>[];
      for (final nome in mappe) {
        // La presa diretta: `= finestra.scelte;` senza una copia in mezzo.
        final diretta = RegExp('=\\s*finestra\\.$nome\\s*;');
        for (final m in diretta.allMatches(finestra)) {
          final riga = finestra.substring(0, m.start).split('\n').length;
          colpe.add('$nome preso di riferimento alla riga $riga');
        }
      }
      expect(colpe, isEmpty,
          reason: 'una mappa presa così e riassegnata non sveglia nessun '
              'legame: si copia (`_copia`) o si costruisce nuova');
    });
  });

  group('quello che è disegnato con Shape non scorre', () {
    // ── Il difetto ───────────────────────────────────────────────────────
    //
    // Giacomo: «il grafico a torta scendendo nella pagina rimane impresso a
    // schermo un residuo e fa schifo».
    //
    // È la famiglia di difetti di `minerva-residui-software`: la shell
    // disegna col processore, Qt ridipinge solo ciò che qualcuno dichiara
    // sporco, e una forma dentro una superficie che scorre lascia i propri
    // pixel dov'erano.
    //
    // La cura è strutturale e non si può ottenere con un ritocco: l'anello
    // deve stare FUORI dal Flickable. Questa guardia lo pretende.
    test('l\'anello sta fuori dalla parte che scorre', () {
      final anello = finestra.indexOf('Anello {');
      final rotolo = finestra.indexOf('Flickable {');
      expect(anello, greaterThan(0), reason: 'l\'anello non c\'è più?');
      expect(rotolo, greaterThan(0), reason: 'il rotolo non c\'è più?');
      expect(anello, lessThan(rotolo),
          reason: 'l\'anello è finito dentro il Flickable: col processore '
              'lascerà il suo residuo sullo schermo a ogni scorrimento');
      // E il rotolo comincia dove finisce il quadro fermo, non sotto la
      // testata: se qualcuno lo riattacca a `testata.bottom`, il quadro
      // fermo gli finisce sotto.
      expect(finestra, contains('anchors.top: cima.bottom'));
    });
  });

  group('niente Shape dentro la parte che scorre', () {
    // ── Il difetto ───────────────────────────────────────────────────────
    //
    // Giacomo, 9 settembre 2026: «electron builder e pip e pacchetti già
    // installati una volta cliccato lasciano residui di spunte sul grafico»,
    // e poi «miniature e cache addirittura risultano passare attraverso il
    // grafico, facendo scroll su e giù si muovono su e giù dentro al
    // grafico».
    //
    // Col renderer software una `Shape` dipinge anche FUORI dal ritaglio del
    // `Flickable` che la contiene. Fotografato: scorrendo l'elenco, dentro
    // l'anello compariva una colonna di spunte nere.
    //
    // La cura delle Impostazioni — ridipingere tutta la finestra mentre si
    // scorre — qui c'è e resta, ma è una rete: insegue una scia appena
    // depositata. La causa si toglie tenendo le `Shape` fuori dalla lista, e
    // questa guardia è l'unica cosa che lo garantisce domani.
    //
    // L'anello invece è una `Shape` e deve restarlo: sta fuori dal rotolo, e
    // ce lo pretende la guardia qui sopra.
    test('le righe non contengono forme che sfuggono al ritaglio', () {
      // ── I commenti si tolgono PRIMA di guardare ──────────────────────
      //
      // Scritta la prima volta, questa guardia è diventata rossa sul
      // COMMENTO di `Freccia.qml`, che spiega perché non usa `Ui.Icon`. È la
      // stessa trappola già presa in `disegno_senza_gpu_test.dart`: una prova
      // che legge il codice deve leggere il codice, non quello che ci si
      // racconta intorno.
      String senzaCommenti(String x) =>
          x.split('\n').map((r) {
            final i = r.indexOf('//');
            return i < 0 ? r : r.substring(0, i);
          }).join('\n');

      final dentroLaLista = ['RigaVoce.qml', 'Spunta.qml', 'Freccia.qml'];
      final colpe = <String>[];
      for (final nome in dentroLaLista) {
        final f = File('../minerva-shell/manutenzione/$nome');
        expect(f.existsSync(), isTrue, reason: '$nome non c\'è più?');
        final testo = senzaCommenti(f.codiceVivo());
        if (testo.contains('QtQuick.Shapes')) colpe.add('$nome importa Shapes');
        if (RegExp(r'\bUi\.Icon\b').hasMatch(testo)) {
          colpe.add('$nome usa Ui.Icon, che è una Shape');
        }
      }
      // E nella finestra: dopo il `Flickable` non ci può essere un'icona.
      final finestraTesto = senzaCommenti(finestra);
      final rotolo = finestraTesto.indexOf('Flickable {');
      final dopo = finestraTesto.substring(rotolo);
      if (RegExp(r'\bUi\.Icon\b').hasMatch(dopo)) {
        colpe.add('Manutenzione.qml usa Ui.Icon dentro il rotolo');
      }
      expect(colpe, isEmpty,
          reason: 'una Shape dentro la lista lascia la sua copia sul grafico '
              'a ogni fotogramma dello scorrimento');
    });

    test('e il pennello che ridipinge resta, come rete', () {
      // Non cura questo difetto — l'ha curato togliere le Shape — ma cura
      // quello delle Impostazioni: le scie che restano dove nessuno
      // ridipinge più. Toglierlo perché «adesso non serve» vorrebbe dire
      // riscoprirlo la prossima volta.
      expect(finestra, contains('ridipingiTutto'));
      expect(finestra, contains('onContentYChanged'));
    });
  });
}
