import 'dart:io';

import 'package:test/test.dart';
import 'package:minervad/ipc/websocket_server.dart';

// Un programma da terminale si lancia dentro `sh -c`, e la riga `Exec=` di un
// `.desktop` ci finisce dentro fra virgolette singole. Proteggere le
// virgolette che ci sono già dentro è l'unica cosa difficile di quella riga, e
// per un anno era scritta sbagliata.
//
// La sequenza giusta è `'\''`: chiudi la stringa, metti una virgoletta
// protetta dalla shell, riapri. Minerva metteva `'''`, che è chiudi-apri-chiudi
// e lascia la riga sbilanciata: da lì in poi tutto quello che segue è FUORI
// dalle virgolette, cioè comandi.
//
// Trovato il 7 settembre 2026 rileggendo il demone. Quanto vale davvero, detto
// preciso: la riga `Exec=` finisce comunque dentro `sh -c` anche senza
// terminale, quindi non si guadagna nessun potere che non si avesse già — e
// `app_scanner` toglie i segnaposto `%f`/`%F`, quindi nessun NOME DI FILE
// arriva mai qui. Il danno vero è che un programma da terminale con un
// apostrofo nel comando non parte, e non dice perché. Sui 167 `.desktop` di
// questo computer non ne colpiva nessuno: era una trappola che aspettava.
//
// La prova non guarda il testo prodotto: lo ESEGUE. Una prova che confronta
// stringhe si convince di una protezione sbagliata quanto di una giusta.
void main() {
  /// Esegue `printf %s '<protetta>'` e restituisce quello che la shell ha
  /// visto davvero, più tutto quello che ha stampato di suo.
  Future<String> dentroLaShell(String grezza) async {
    final protetta = WebSocketServer.protettaPerShell(grezza);
    final r = await Process.run('sh', ['-c', "printf '%s' '$protetta'"]);
    return '${r.stdout}${r.stderr}';
  }

  group('la riga di un programma da terminale', () {
    test('una virgoletta sopravvive e non spezza niente', () async {
      const grezza = "echo l'ora";
      expect(await dentroLaShell(grezza), grezza);
    });

    test('quello che sembra un secondo comando resta testo', () async {
      // Con la protezione sbagliata (`'''`) questa riga stampava «INIETTATO»:
      // la shell usciva dalle virgolette ed eseguiva.
      const grezza = "x' ; echo INIETTATO ; echo 'y";
      final visto = await dentroLaShell(grezza);
      expect(visto, isNot(contains('INIETTATO\n')),
          reason: 'la shell ha ESEGUITO quello che doveva restare testo');
      expect(visto, grezza);
    });

    test('anche con una virgoletta sola, che sbilancia la riga', () async {
      // Il caso più semplice e il più cattivo: un numero DISPARI di virgolette
      // lascia una stringa aperta, e `sh` resta ad aspettare o muore.
      const grezza = "cd /home/l'utente && ls";
      expect(await dentroLaShell(grezza), grezza);
    });

    test('e le righe normali non cambiano', () async {
      for (final grezza in [
        'htop',
        'sh -c "arch-update"',
        '/usr/bin/env python3 /home/giacomo/Documenti/Minerva Shell/x.py',
        r'bash -c "echo $HOME"',
      ]) {
        expect(await dentroLaShell(grezza), grezza, reason: grezza);
      }
    });

    test('il comando completo mette la riga fra virgolette', () {
      // La protezione serve a stare DENTRO `'...'`: se un domani chi scrive
      // quella riga togliesse le virgolette, questa protezione diventerebbe
      // dannosa invece che inutile.
      final riga = WebSocketServer.dentroUnTerminale("echo l'ora");
      expect(riga, contains("sh -c '"));
      expect(riga, contains(WebSocketServer.protettaPerShell("echo l'ora")));
    });

    test('e il comando intero è shell valida, apostrofi compresi', () async {
      // `sh -n` controlla la sintassi senza eseguire niente. È la prova che
      // prende il caso peggiore: non «la parte protetta è giusta», ma «la riga
      // che mandiamo davvero a `sh -c` sta in piedi».
      for (final exec in [
        "echo l'ora",
        "cd /home/l'utente && ls",
        "x' ; echo INIETTATO ; echo 'y",
        'htop',
      ]) {
        final r = await Process.run(
            'sh', ['-n', '-c', WebSocketServer.dentroUnTerminale(exec)]);
        expect(r.exitCode, 0,
            reason: 'con «$exec» la riga non è nemmeno shell valida:\n'
                '${r.stderr}');
      }
    });
  });
}
