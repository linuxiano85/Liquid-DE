import 'dart:io';

import 'package:test/test.dart';
import 'package:minervad/core/ambiente.dart';

/// Le prove di «chi è questo demone».
///
/// Servono a una cosa sola: che il segno non si stacchi dal significato. Il
/// demone della schermata di accesso salta il lavoro che non gli serve — la
/// tabella delle icone classiche, la ricerca del tema di icone — e lo fa
/// perché si riconosce dal nome della sessione. Se quel nome cambiasse da una
/// parte sola, il greeter tornerebbe a fare settantasei ricerche su disco per
/// zero icone e **nessuno se ne accorgerebbe**: non è un guasto, è solo
/// lentezza, e nel posto in cui la lentezza si nota di più.
void main() {
  group('il demone della schermata di accesso', () {
    test('si riconosce dal nome della sessione', () {
      expect(Ambiente.eNomeDelGreeter('greeter'), isTrue);
    });

    test('e una sessione vera non gli somiglia', () {
      // I nomi che una sessione vera può avere: il numero di logind, la
      // console, il ripiego.
      for (final nome in ['2', '4', 'vt7', 'unica', '', 'Greeter', 'greeter2']) {
        expect(Ambiente.eNomeDelGreeter(nome), isFalse,
            reason: '«$nome» si spaccia per la schermata di accesso');
      }
    });

    test('è lo stesso nome che scrive lo script del greeter', () async {
      // Il nome lo decide `scripts/minerva-greetd` scrivendo
      // `/etc/greetd/minerva-greeter.conf`, e lo legge il demone. Sono due
      // file in due linguaggi: possono divergere in silenzio.
      final script = File('${Directory.current.path}/../scripts/minerva-greetd');
      if (!script.existsSync()) {
        markTestSkipped('minerva-greetd non trovato da qui');
        return;
      }
      final testo = await script.readAsString();
      final riga = RegExp(r'^env = MINERVA_SESSIONE,(.+)$', multiLine: true)
          .firstMatch(testo);
      expect(riga, isNotNull,
          reason: 'la configurazione del greeter non imposta più '
              'MINERVA_SESSIONE: senza, il suo demone ricade su «unica» e '
              'scrive nella cartella della sessione dell\'utente');
      expect(riga!.group(1)!.trim(), Ambiente.sessioneGreeter,
          reason: 'lo script chiama la sessione del greeter '
              '«${riga.group(1)!.trim()}», il demone si aspetta '
              '«${Ambiente.sessioneGreeter}»');
    });
  });
}
