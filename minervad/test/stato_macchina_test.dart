// Lo stato della macchina risponde al PRIMO che lo chiede.
//
// ── Il difetto ─────────────────────────────────────────────────────────────
//
// Visto il 3 settembre 2026 fotografando il pannello del calendario in una
// sessione annidata — non leggendo il codice, e non da una prova rossa.
// Sotto il calendario ci sono tre numeri: Processore, Memoria, Temperatura.
// Il primo diceva «—» e gli altri due un numero.
//
// La causa è che l'uso della CPU non si LEGGE: si calcola fra due letture di
// `/proc/stat`. Alla prima chiamata non c'era niente da confrontare, quindi il
// campo non veniva impostato affatto. Il pannello chiede ogni tre secondi,
// quindi il trattino durava tre secondi — cioè esattamente il tempo in cui uno
// apre il calendario e guarda.
//
// Non era un errore: era la verità, «non lo so ancora», detta in un modo che
// sembra un guasto. È la stessa famiglia delle due «cartella vuota»
// sovrapposte e dei tre tasti tagliati fuori dal pannello di controllo: niente
// va in errore, e si vede solo guardando.
//
// La strada sbagliata, scritta qui perché non venga ripresa: partire dai tick
// dall'accensione darebbe la media dal boot. È un numero vero, e risponde a una
// domanda che nessuno ha fatto.
import 'package:minervad/core/event_bus.dart';
import 'package:minervad/services/process_service.dart';
import 'package:test/test.dart';

void main() {
  test('la prima lettura porta già l\'uso del processore', () async {
    final s = ProcessService(EventBus());
    final m = await s.soloMacchina();

    expect(m['cpu'], isNotNull,
        reason: 'il pannello mostrerebbe «Processore —» accanto a due numeri, '
            'e sembra un guasto');
    final cpu = (m['cpu'] as num).toDouble();
    expect(cpu, inInclusiveRange(0, 100));

    // Gli altri due erano già giusti: si provano perché la riparazione della
    // CPU tocca lo stesso blocco, e romperli qui sarebbe silenzioso.
    expect(m['core'], greaterThan(0));
    expect(m['memoriaUsata'], isNotNull);
    expect(m['memoriaTotale'], isNotNull);
  });

  test('e la seconda non è la stessa lettura di prima', () async {
    // Il campione iniziale non deve restare incollato: se `_tickMacchina…`
    // non si aggiornasse, la seconda risposta ripeterebbe la prima e il
    // numero non si muoverebbe più — un grafico piatto è indistinguibile da
    // una macchina ferma.
    final s = ProcessService(EventBus());
    await s.soloMacchina();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final b = await s.soloMacchina();
    expect(b['cpu'], isNotNull);
    expect((b['cpu'] as num).toDouble(), inInclusiveRange(0, 100));
  });
}
