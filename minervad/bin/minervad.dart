import 'dart:async';
import 'dart:io';
import 'package:minervad/core/minerva_core.dart';

/// L'avvio del demone.
///
/// ── Perché i segnali si ascoltano PRIMA di partire ─────────────────────────
///
/// Perché `core.start()` non è istantaneo: legge le impostazioni, scandisce le
/// applicazioni, si connette al compositore, apre la porta. Un `SIGTERM` che
/// arriva in quella finestra — ed è proprio la finestra in cui arriva, perché
/// è quando si riavvia il demone — trovava il gestore non ancora registrato:
/// il processo moriva col comportamento predefinito, cioè **senza chiudere
/// niente**. Timer vivi, socket aperti, il file delle impostazioni magari a
/// metà scrittura.
///
/// I gestori vengono registrati prima dell'avvio. Un segnale attende che
/// l'avvio termini prima di fermare i servizi, senza sovrapporre start/stop
/// o dichiarare pronto il demone dopo che ne è stata chiesta la chiusura.
/// Se l'avvio fallisce, l'uscita resta diversa da zero; il recupero delle
/// risorse parzialmente inizializzate appartiene al contratto del Core.
/// ── L'ultima rete, e perché non ingoia tutto ────────────────────────────────
///
/// Il 31 agosto 2026 il demone è uscito con 255 quattro volte in quattro
/// sessioni, sempre per la stessa ragione: una finestra si chiudeva mentre lui
/// le stava scrivendo addosso, e l'EPIPE non tornava a chi aveva scritto —
/// Dart lo consegna alla ZONA. Un errore non raccolto nella zona di radice
/// uccide il processo. Il guardiano lo rimetteva in piedi, ma la shell non lo
/// ritrovava più: il manutentore si è ritrovato senza dock e senza menù delle
/// applicazioni, in tutte e due le sessioni.
///
/// La causa è riparata dov'era (`WebSocketClientConnection`), e questa è la
/// rete sotto: **nessun client che se ne va può portare giù il demone.**
///
/// E la rete NON ingoia tutto, che sarebbe barattare questo guasto con uno
/// peggiore — un difetto vero che non lascia traccia e si manifesta come una
/// finestra che «ogni tanto non si aggiorna».
///
///   * un guasto di socket è la vita normale di un canale: una riga e si tira
///     avanti;
///   * qualunque altra cosa si stampa per intero e si esce con 1, così il
///     guardiano riparte da pulito e il registro dice perché.
void main(List<String> arguments) {
  runZonedGuarded(() => _avvia(arguments), (errore, dove) {
    if (errore is SocketException) {
      print('[MINERVA][DAEMON][WARN] Un canale si è rotto sotto i piedi: '
          '$errore');
      print('[MINERVA][DAEMON][WARN] Il demone resta in piedi: un client che '
          'se ne va non è un guasto del demone.');
      return;
    }
    print('[MINERVA][DAEMON][ERRORE] Guasto non previsto, e non è un socket: '
        '$errore');
    print(dove);
    print('[MINERVA][DAEMON][ERRORE] Esco con 1: che riparta pulito invece di '
        'restare acceso in uno stato che nessuno sa descrivere.');
    exit(1);
  });
}

Future<void> _avvia(List<String> arguments) async {
  print('[MINERVA][DAEMON][INFO] Avvio di minervad...');

  if (arguments.contains('--disable-analytics')) {
    print('[MINERVA][DAEMON][INFO] Analytics disabilitate.');
    return;
  }

  final core = MinervaCore();
  final avvioTerminato = Completer<void>();
  var avvioFallito = false;
  var inChiusura = false;
  Future<void>? arresto;

  // Signals and --test-start must share one stop operation, including errors.
  Future<void> fermaUnaVolta() => arresto ??= core.stop();

  Future<void> chiudi(String segnale) async {
    if (inChiusura) return;
    inChiusura = true;
    print('\n[MINERVA][DAEMON][INFO] Ricevuto $segnale. Arresto richiesto...');
    await avvioTerminato.future;
    if (avvioFallito) exit(1);
    var risultato = 0;
    try {
      await fermaUnaVolta();
    } catch (e) {
      print('[MINERVA][DAEMON][ERRORE] Arresto non pulito: $e');
      risultato = 1;
    }
    exit(risultato);
  }

  ProcessSignal.sigint.watch().listen((_) => chiudi('SIGINT'));
  ProcessSignal.sigterm.watch().listen((_) => chiudi('SIGTERM'));

  // One startup path for the session and the self-test. The completion signal
  // never completes with an error: startup failures are logged and represented
  // by avvioFallito, avoiding an unobserved Future error without a signal.
  try {
    await core.start();
  } catch (e, dove) {
    avvioFallito = true;
    print('[MINERVA][DAEMON][ERRORE] minervad non è riuscito a partire: $e');
    print(dove);
  } finally {
    avvioTerminato.complete();
  }
  if (avvioFallito) exit(1);
  if (inChiusura) return;

  // A real quick startup/shutdown check. A signal during the observation
  // interval or stop takes ownership of exit and uses the same stop Future.
  if (arguments.contains('--test-start')) {
    try {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (inChiusura) return;
      await fermaUnaVolta();
      if (inChiusura) return;
      print('[MINERVA][DAEMON][OK] minervad avviato in modalità test di '
          'autodiagnosi.');
      exit(0);
    } catch (e, dove) {
      print('[MINERVA][DAEMON][ERRORE] L\'autodiagnosi è fallita: $e');
      print(dove);
      exit(1);
    }
  }

  print('[MINERVA][DAEMON][OK] minervad in esecuzione. Premi Ctrl+C per fermare.');
}
