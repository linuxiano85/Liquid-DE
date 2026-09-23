// terminale.dart — Il motore del Terminale di Minerva, un processo per
// finestra. Il perché e il protocollo stanno in `lib/terminale/motore.dart`.
//
//     minerva-terminale-motore --pty PERCORSO [--colonne N] [--righe N]
//                              [--cartella DIR] [--esegui CMD] [--shell PROG]
//                              [--scrollback N] [--integrazione DIR]
import 'dart:convert';
import 'dart:io';

import 'package:minervad/terminale/motore.dart';

Future<void> main(List<String> argv) async {
  String? pty;
  var colonne = 80;
  var righe = 24;
  String? cartella;
  String? esegui;
  String? shell;
  var scrollback = 10000;
  String? integrazione;
  String? dizionario;
  for (var i = 0; i < argv.length; i++) {
    final a = argv[i];
    String prossimo() => i + 1 < argv.length ? argv[++i] : '';
    switch (a) {
      case '--pty':
        pty = prossimo();
      case '--colonne':
        colonne = int.tryParse(prossimo()) ?? 80;
      case '--righe':
        righe = int.tryParse(prossimo()) ?? 24;
      case '--cartella':
        cartella = prossimo();
      case '--esegui':
        esegui = prossimo();
      case '--shell':
        shell = prossimo();
      case '--integrazione':
        integrazione = prossimo();
      case '--dizionario':
        dizionario = prossimo();
      case '--scrollback':
        scrollback = (int.tryParse(prossimo()) ?? 10000).clamp(0, 1000000);
      default:
        stderr.writeln('minerva-terminale-motore: argomento sconosciuto «$a»');
        exit(2);
    }
  }
  if (pty == null || !File(pty).existsSync()) {
    stderr.writeln('minerva-terminale-motore: --pty deve dire dove sta minerva-pty');
    exit(2);
  }

  final motore = Motore(
    percorsoPty: pty,
    fuori: stdout,
    colonne: colonne,
    righe: righe,
    cartella: cartella,
    esegui: esegui,
    shell: shell,
    scrollback: scrollback,
    integrazione: integrazione,
    percorsoDizionario: dizionario,
  );
  await motore.avvia();

  // La finestra parla su stdin, un JSON per riga. Se chiude lo stdin se n'è
  // andata: si chiude anche la shell, e si esce.
  stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(motore.dallaFinestra, onDone: () {
    motore.dallaFinestra('{"t":"chiudi"}');
  });
}
