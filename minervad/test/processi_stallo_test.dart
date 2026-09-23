import 'dart:async';
import 'dart:math';

import 'package:test/test.dart';
import 'package:minervad/core/event_bus.dart';
import 'package:minervad/services/process_service.dart';

// Quanto tempo il gestore attività tiene fermo TUTTO il demone.
//
// ── Perché è una prova e non un'ottimizzazione a occhio ────────────────────
//
// Dart ha un filo solo, e in tutte le 28.000 righe del demone non c'è nessun
// isolate. Il giro su `/proc` legge, per ogni processo, `stat`, `statm`,
// `smaps_rollup` e `cmdline` — e li legge in modo SINCRONO. Mentre li legge, il
// demone non fa nient'altro: non le finestre, non le impostazioni, niente.
// Non è il gestore attività a rallentare: è tutta la scrivania, e solo perché
// quella finestra è aperta.
//
// Misurato dall'esterno il 7 settembre 2026, con due client e un battito ogni
// 4 ms: col Monitor chiuso il peggiore era 0,56 ms, col Monitor aperto
// 22,09 ms.
//
// Questa prova misura la stessa cosa da dentro, ed è il modo giusto: un
// cronometro che dovrebbe suonare ogni millisecondo non suona finché il filo è
// occupato, quindi il buco più lungo fra due rintocchi È il tempo in cui il
// demone era sordo.
void main() {
  test('leggere i processi non tiene fermo il demone', () async {
    final servizio = ProcessService(EventBus());

    // Un giro a vuoto: il primo paga la cache del disco fredda, e misurarlo
    // vorrebbe dire misurare il kernel invece di noi.
    await servizio.leggi();

    final buchi = <int>[];
    var ultimo = DateTime.now();
    final cronometro = Timer.periodic(const Duration(milliseconds: 1), (_) {
      final ora = DateTime.now();
      buchi.add(ora.difference(ultimo).inMicroseconds);
      ultimo = ora;
    });

    // Tre giri di fila e non uno: un giro solo, su una macchina che in quel
    // momento non ha altro da fare, può durare quattro millisecondi e dare tre
    // rintocchi — troppo pochi perché «il buco più lungo» voglia dire qualcosa.
    // Con la suite intera in parallelo è successo davvero.
    final quanto = Stopwatch()..start();
    late Map<String, dynamic> letto;
    for (var g = 0; g < 3; g++) {
      letto = await servizio.leggi();
    }
    quanto.stop();
    cronometro.cancel();
    servizio.dispose();

    expect(letto['processi'], isNotNull,
        reason: 'la lettura non ha prodotto processi: la prova misurerebbe '
            'il nulla');
    expect(buchi.length, greaterThan(3),
        reason: 'il cronometro non ha battuto abbastanza per dire qualcosa');

    final peggiore = buchi.reduce(max) / 1000.0;
    print('  processi letti: ${(letto['processi'] as List).length}, '
        'tre giri ${quanto.elapsedMilliseconds} ms, '
        'buco più lungo ${peggiore.toStringAsFixed(1)} ms');

    // ── La soglia è una PROPORZIONE, non un numero di millisecondi ────
    //
    // Prima era 25 ms fissi, e `prove.sh` l'ha fatta fallire per 2,2: la
    // suite fa girare sessioni annidate, la macchina è carica, i processi
    // diventano 233 invece di 217 e tutto rallenta insieme. Una prova che si
    // lamenta quando il computer sta facendo altro insegna a ignorarla, ed è
    // il difetto peggiore che possa avere una guardia.
    //
    // Quello che va chiesto non è «quanto è veloce», è «quanto di un giro il
    // demone lo passa sordo di fila». Senza il respiro nel ciclo il fermo più
    // lungo È il giro intero — misurato: 115 ms di fermo su 111 ms di giro
    // medio, cioè tutto. Col respiro ogni otto processi va a 15 su 110, cioè
    // un settimo. Se la macchina raddoppia il carico raddoppiano tutti e due,
    // e la proporzione regge.
    final giroMedio = quanto.elapsedMilliseconds / 3.0;
    final quota = peggiore / giroMedio;
    print('  giro medio ${giroMedio.toStringAsFixed(0)} ms, '
        'il fermo più lungo ne è il ${(quota * 100).round()}%');

    expect(quota, lessThan(0.4),
        reason: 'il demone è rimasto sordo per ${peggiore.toStringAsFixed(1)} '
            'ms di fila, che è il ${(quota * 100).round()}% di un giro intero: '
            'il ciclo su /proc non sta cedendo il filo. In quel tempo non '
            'risponde a nessuna finestra — non è il gestore attività a '
            'rallentare, è tutta la scrivania.');

    // E un tetto assoluto largo, per il caso patologico che la proporzione da
    // sola non prenderebbe: un giro lentissimo diviso in pezzi lentissimi.
    expect(peggiore, lessThan(60),
        reason: 'fermo di ${peggiore.toStringAsFixed(1)} ms: troppo comunque, '
            'qualunque sia la proporzione');
  });
}
