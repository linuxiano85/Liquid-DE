import 'dart:io';

import 'package:minervad/core/minerva_paths.dart';
import 'package:test/test.dart';
import 'codice_vivo.dart';

/// Il bus è il punto in cui due programmi che non si conoscono devono essere
/// d'accordo, e il modo in cui si rompe non è un errore: è il SILENZIO.
///
/// Un'azione scritta male arriva al demone, non trova nessun `case`, e non
/// succede niente — nessuna eccezione, nessuna risposta. La shell resta ad
/// aspettare per sempre una cosa che non arriverà. È già costato ore due
/// volte: `get_windows`/`get_monitors` chiamati e non gestiti, e le
/// impostazioni chieste a un file che il demone non legge più.
///
/// `EVENTS.md` è l'elenco di quello che esiste. Queste prove esistono perché
/// un elenco che non si aggiorna da solo è peggio di nessun elenco: dice il
/// falso con l'aria di dire il vero.
void main() {
  final radice = MinervaPaths.installRoot;
  final server = File('$radice/minervad/lib/ipc/websocket_server.dart');
  final doc = File('$radice/EVENTS.md');

  Set<String> azioniNelCodice() => RegExp(r"case '([a-z_0-9]+)':")
      .allMatches(server.codiceVivo())
      .map((m) => m.group(1)!)
      .toSet();

  Set<String> eventiNelCodice() => RegExp(r"'event':\s*'([a-z_0-9]+)'")
      .allMatches(server.codiceVivo())
      .map((m) => m.group(1)!)
      .toSet();

  Set<String> nomiNelDocumento() => RegExp(r'`([a-z_0-9]+)`')
      .allMatches(doc.codiceVivo())
      .map((m) => m.group(1)!)
      .toSet();

  group('il bus e la sua documentazione', () {
    test('EVENTS.md esiste', () {
      expect(doc.existsSync(), isTrue,
          reason: 'senza EVENTS.md nessuno può sapere cosa il bus accetta, e '
              'un\'azione scritta male non dà nessun errore: dà silenzio');
    });


    // ── E i due numeri in testa al documento ────────────────────────────
    //
    // Dicevano «81 azioni, 38 eventi» mentre il documento ne elencava più del
    // doppio: le voci si aggiungevano in fondo e il totale in cima restava
    // quello del giorno in cui era stato scritto. Un numero che non si
    // aggiorna è la forma più tranquilla di bugia, perché chi legge si fida
    // del numero e non conta le righe.
    test('e i due totali in cima dicono il vero', () {
      final testo = doc.codiceVivo();
      final m = RegExp(r'\*\*(\d+) azioni\*\*.*?\*\*(\d+) eventi\*\*',
              dotAll: true)
          .firstMatch(testo);
      expect(m, isNotNull, reason: 'non trovo più la riga dei totali');
      expect(int.parse(m!.group(1)!), azioniNelCodice().length,
          reason: 'il numero di azioni in cima a EVENTS.md non è quello vero');
      expect(int.parse(m.group(2)!), eventiNelCodice().length,
          reason: 'il numero di eventi in cima a EVENTS.md non è quello vero');
    });

    test('ogni azione del demone è raccontata', () {
      final mancanti = azioniNelCodice().difference(nomiNelDocumento());
      expect(mancanti, isEmpty,
          reason: 'azioni che il demone accetta e che EVENTS.md non nomina: '
              '${mancanti.join(", ")}. Chi scrive la shell non può sapere che '
              'esistono.');
    });

    test('ogni evento del demone è raccontato', () {
      final mancanti = eventiNelCodice().difference(nomiNelDocumento());
      expect(mancanti, isEmpty,
          reason: 'eventi che il demone manda e che EVENTS.md non nomina: '
              '${mancanti.join(", ")}');
    });

    // L'altro verso conta quanto il primo: un elenco che nomina cose morte
    // manda chi legge a chiamare un'azione che non risponde — che è
    // esattamente il difetto che questo file dovrebbe impedire.
    test('EVENTS.md non promette azioni che non esistono', () {
      final tutte = azioniNelCodice().union(eventiNelCodice());
      // Nel documento ci sono anche parole in `backtick` che non sono nomi del
      // bus: percorsi, comandi, file. Si guardano solo quelle che HANNO la
      // forma di un nome del bus — minuscole e trattini bassi, con almeno un
      // trattino basso o già note.
      final promesse = nomiNelDocumento()
          .where((n) => n.contains('_') && !n.contains('.'))
          .toSet();
      final fantasmi = promesse.difference(tutte);
      expect(fantasmi, isEmpty,
          reason: 'EVENTS.md nomina cose che il demone non conosce: '
              '${fantasmi.join(", ")}');
    });
  });
}
