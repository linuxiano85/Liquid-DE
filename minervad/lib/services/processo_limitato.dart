import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../core/linux_files.dart';

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

  final bool outputTroncato;
  final bool annullato;
  const UscitaLimitata(this.codice, this.stdout, this.stderr, this.scaduto,
      [this.outputTroncato = false, this.annullato = false]);

  bool get ok => !scaduto && !outputTroncato && !annullato && codice == 0;
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
  int? massimoCaratteri,
  Future<void>? annullamento,
  bool gruppoProcessi = false,
}) async {
  if (massimoCaratteri != null && massimoCaratteri < 1) {
    throw ArgumentError.value(massimoCaratteri, 'massimoCaratteri');
  }
  final p = await Process.start(gruppoProcessi ? '/usr/bin/setsid' : programma,
      gruppoProcessi ? [programma,...argomenti] : argomenti, environment: ambiente);
  var terminato = false;
  var annullato = false;
  void ferma() {
    if (gruppoProcessi) { LinuxFiles.segnalaGruppo(p.pid,9); }
    p.kill(ProcessSignal.sigkill);
  }
  if (annullamento != null) {
    unawaited(annullamento.then((_) {
      if (!terminato) { annullato = true; ferma(); }
    }));
  }
  // Niente da dire al figlio: un programma che si mette a chiedere qualcosa
  // trova lo stdin chiuso e smette, invece di aspettare una risposta.
  unawaited(p.stdin.close().then((_) {}, onError: (Object _) {}));

  final fuori = StringBuffer();
  final errori = StringBuffer();
  var outputTroncato = false;
  var raccolti = 0;
  void raccogli(StringBuffer buffer, String text) {
    final limite = massimoCaratteri;
    if (limite == null) { buffer.write(text); return; }
    final rimasti = limite - raccolti;
    if (text.length > rimasti) {
      if (rimasti > 0) buffer.write(text.substring(0,rimasti));
      raccolti = limite;
      outputTroncato = true;
      ferma();
    } else {
      buffer.write(text);
      raccolti += text.length;
    }
  }
  final finitoFuori = Completer<void>();
  final finitoErrori = Completer<void>();
  final sFuori = p.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .listen((text) => raccogli(fuori,text),
          onError: (Object _) {}, onDone: finitoFuori.complete);
  final sErrori = p.stderr
      .transform(const Utf8Decoder(allowMalformed: true))
      .listen((text) => raccogli(errori,text),
          onError: (Object _) {}, onDone: finitoErrori.complete);

  var scaduto = false;
  int codice;
  try {
    codice = await p.exitCode.timeout(limite);
  } on TimeoutException {
    scaduto = true;
    ferma();
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
  terminato = true;

  return UscitaLimitata(codice, fuori.toString(), errori.toString(), scaduto, outputTroncato, annullato);
}
