import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Quello che un programma esterno ha detto prima di finire, o prima che lo
/// fermassimo.
class UscitaLimitata {
  /// Il codice d'uscita. Se lo si è dovuto fermare è quello del segnale
  /// (negativo, come lo riporta Dart), e `scaduto` è vero.
  final int codice;
  final String stdout;
  final String stderr;

  /// Vero se il tempo è finito e il programma è stato ucciso.
  final bool scaduto;

  const UscitaLimitata(this.codice, this.stdout, this.stderr, this.scaduto);

  bool get ok => !scaduto && codice == 0;
}

/// Lancia un programma e non lo aspetta più di `limite`.
///
/// ── Perché non basta `Process.run(...).timeout(...)` (30 settembre 2026) ──
///
/// Perché `timeout` smette di aspettare il FUTURO, non il processo: il figlio
/// resta vivo, attaccato ai suoi tubi, finché non decide da solo di finire.
/// Un `busctl` davanti a un servizio impallato resta lì i suoi venticinque
/// secondi; un `stat` su un disco di rete caduto resta lì per sempre, e ogni
/// finestra «Proprietà» aperta ne aggiunge un altro. E quello che il
/// programma aveva già scritto va perso: `avahi-browse` che ha trovato due
/// televisori su tre e aspetta il terzo, spento, tornava un elenco vuoto.
///
/// Qui, finito il tempo, il figlio si uccide e si restituisce quello che
/// aveva già detto.
///
/// Se il programma non si può nemmeno lanciare solleva `ProcessException`,
/// esattamente come `Process.run`: chi chiama lo tratta già così.
Future<UscitaLimitata> eseguiLimitato(
  String programma,
  List<String> argomenti, {
  Duration limite = const Duration(seconds: 5),
  Map<String, String>? ambiente,
}) async {
  final p = await Process.start(programma, argomenti, environment: ambiente);
  // Niente da dire al figlio: un programma che si mette a chiedere qualcosa
  // trova lo stdin chiuso e smette, invece di aspettare una risposta.
  unawaited(p.stdin.close().then((_) {}, onError: (Object _) {}));

  final fuori = StringBuffer();
  final errori = StringBuffer();
  final finitoFuori = Completer<void>();
  final finitoErrori = Completer<void>();
  final sFuori = p.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .listen(fuori.write,
          onError: (Object _) {}, onDone: finitoFuori.complete);
  final sErrori = p.stderr
      .transform(const Utf8Decoder(allowMalformed: true))
      .listen(errori.write,
          onError: (Object _) {}, onDone: finitoErrori.complete);

  var scaduto = false;
  int codice;
  try {
    codice = await p.exitCode.timeout(limite);
  } on TimeoutException {
    scaduto = true;
    p.kill(ProcessSignal.sigkill);
    codice = await p.exitCode;
  }

  // I tubi si chiudono quando li chiude l'ultimo che li tiene: un nipote
  // (`sh -c 'a | b'`) può tenerli aperti dopo che il figlio è morto. Si
  // aspetta poco, e poi si smette di ascoltare.
  try {
    await Future.wait([finitoFuori.future, finitoErrori.future])
        .timeout(const Duration(milliseconds: 500));
  } on TimeoutException {
    // Resta quello che è arrivato fin qui.
  }
  await sFuori.cancel();
  await sErrori.cancel();

  return UscitaLimitata(codice, fuori.toString(), errori.toString(), scaduto);
}
