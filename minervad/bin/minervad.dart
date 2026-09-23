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
/// Ora i gestori ci sono dal primo istante, e sanno distinguere i due casi:
/// se l'avvio non è finito non si prova a fermare quello che non è ancora
/// partito.
/// ── L'ultima rete, e perché non ingoia tutto ────────────────────────────────
///
/// Il 31 agosto 2026 il demone è uscito con 255 quattro volte in quattro
/// sessioni, sempre per la stessa ragione: una finestra si chiudeva mentre lui
/// le stava scrivendo addosso, e l'EPIPE non tornava a chi aveva scritto —
/// Dart lo consegna alla ZONA. Un errore non raccolto nella zona di radice
/// uccide il processo. Il guardiano lo rimetteva in piedi, ma la shell non lo
/// ritrovava più: Giacomo si è ritrovato senza dock e senza menù delle
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
  var avviato = false;
  var inChiusura = false;

  Future<void> chiudi(String segnale) async {
    if (inChiusura) return;
    inChiusura = true;
    print('\n[MINERVA][DAEMON][INFO] Ricevuto $segnale. Arresto pulito...');
    try {
      if (avviato) {
        await core.stop();
      } else {
        print('[MINERVA][DAEMON][INFO] L\'avvio non era finito: niente da '
            'fermare.');
      }
    } catch (e) {
      print('[MINERVA][DAEMON][ERRORE] Arresto non pulito: $e');
    }
    exit(0);
  }

  ProcessSignal.sigint.watch().listen((_) => chiudi('SIGINT'));
  ProcessSignal.sigterm.watch().listen((_) => chiudi('SIGTERM'));

  // Un test di avvio rapido: parte, respira, si ferma. Serve a sapere se il
  // demone è sano senza lasciarlo acceso.
  if (arguments.contains('--test-start')) {
    try {
      await core.start();
      avviato = true;
      await Future.delayed(const Duration(milliseconds: 100));
      await core.stop();
      print('[MINERVA][DAEMON][OK] minervad avviato in modalità test di '
          'autodiagnosi.');
      exit(0);
    } catch (e, dove) {
      print('[MINERVA][DAEMON][ERRORE] L\'autodiagnosi è fallita: $e');
      print(dove);
      exit(1);
    }
  }

  // ── Un guasto in avvio si dice, non si stampa e basta ────────────────────
  //
  // Senza questo, un errore usciva come «Unhandled exception» più venti righe
  // di traccia: chi legge il registro vede un muro e non la frase che gli
  // serve. La causa che capita davvero è una sola — la porta occupata — e il
  // servizio la nomina già (vedi `WebSocketServer.start`). Qui si aggiunge
  // solo l'uscita diversa da zero, che è quello che il guardiano guarda.
  try {
    await core.start();
    avviato = true;
  } catch (e, dove) {
    print('[MINERVA][DAEMON][ERRORE] minervad non è riuscito a partire: $e');
    print(dove);
    exit(1);
  }

  print('[MINERVA][DAEMON][OK] minervad in esecuzione. Premi Ctrl+C per fermare.');
}
