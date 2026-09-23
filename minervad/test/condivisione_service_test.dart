import 'dart:io';

import 'package:minervad/services/app_scanner.dart';
import 'package:minervad/services/condivisione_service.dart';
import 'package:minervad/services/mime_service.dart';
import 'package:minervad/services/trasmetti_service.dart';
import 'package:test/test.dart';

/// Prove sulla condivisione: Bluetooth e posta.
///
/// Girano contro il bus vero, come `archive_service_test.dart` gira contro
/// `bsdtar` vero: una finzione di BlueZ riprodurrebbe quello che credo di
/// sapere di lui, non quello che fa davvero.
///
/// Non si può contare su un dispositivo accoppiato che accetta OPP, né su un
/// programma di posta installato: sono proprietà DELLA MACCHINA su cui gira
/// la prova, non del codice. Quello che si prova qui è la REGOLA che il
/// servizio dichiara di sé stesso: «non si offre una destinazione che non può
/// funzionare, e quando non può si dice perché» — e i percorsi che non
/// toccano il bus (file mancanti, cartelle, destinazione sconosciuta), che
/// sono sempre veri, ovunque giri la prova.
void main() {
  late CondivisioneService condivisione;
  late Directory temp;

  setUp(() async {
    // Il servizio che trasmette è quello vero, senza `permesso`: così non
    // chiama `pkexec` e non fa comparire la finestra della password sullo
    // schermo di chi lancia le prove. Le prove qui sotto non arrivano mai a
    // usarlo — provano i rifiuti, che vengono prima.
    condivisione =
        CondivisioneService(MimeService(AppScanner()), TrasmettiService());
    temp = await Directory.systemTemp.createTemp('minerva-condividi-');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<String> scrivi(String nome, [String contenuto = 'ciao']) async {
    final f = File('${temp.path}/$nome');
    await f.writeAsString(contenuto);
    return f.path;
  }

  group('quali destinazioni ci sono', () {
    test('tornano sempre tutte e due, mai una lista corta', () async {
      final r = await condivisione.destinazioni();
      expect(r['ok'], isTrue);
      final elenco = r['destinazioni'] as List;
      expect(elenco.map((d) => d['id']), containsAll(['bluetooth', 'email']));
    });

    test('ogni destinazione spenta dice perché, ogni accesa non dice niente',
        () async {
      final r = await condivisione.destinazioni();
      for (final d in (r['destinazioni'] as List)) {
        if (d['disponibile'] == true) {
          expect(d['motivo'], isEmpty,
              reason: '${d['id']} è disponibile ma ha ancora un motivo');
        } else {
          expect(d['motivo'], isNotEmpty,
              reason: '${d['id']} è spenta e non dice perché — è la cosa '
                  'peggiore che possa fare una voce di menu');
        }
      }
    });

    test('il Bluetooth porta sempre il campo dispositivi, anche vuoto',
        () async {
      final r = await condivisione.destinazioni();
      final bt = (r['destinazioni'] as List)
          .firstWhere((d) => d['id'] == 'bluetooth');
      expect(bt['dispositivi'], isA<List>());
    });
  });

  group('mandare, quello che non dipende dalla macchina', () {
    test('niente file, niente invio', () async {
      final r = await condivisione.invia('email', []);
      expect(r['ok'], isFalse);
    });

    test('un file sparito fra il menu e il clic si dice, non si tenta',
        () async {
      final r = await condivisione
          .invia('email', ['${temp.path}/non-esiste-più.txt']);
      expect(r['ok'], isFalse);
      expect(r['error'], contains('non-esiste-più.txt'));
    });

    test('una destinazione che non conosciamo non fa niente in silenzio',
        () async {
      final f = await scrivi('lettera.txt');
      final r = await condivisione.invia('fax', [f]);
      expect(r['ok'], isFalse);
      expect(r['error'], contains('fax'));
    });

    test('il Bluetooth senza un dispositivo scelto lo dice subito', () async {
      final f = await scrivi('lettera.txt');
      final r = await condivisione.invia('bluetooth', [f]);
      expect(r['ok'], isFalse);
      expect(r['error'], isNotEmpty);
    });

    test('una cartella non si manda per Bluetooth: va compressa prima',
        () async {
      final cartella = Directory('${temp.path}/foto')..createSync();
      final r = await condivisione.invia(
          'bluetooth', [cartella.path], bersaglio: 'AA:BB:CC:DD:EE:FF');
      expect(r['ok'], isFalse);
      expect(r['error'], contains('foto'));
      expect(r['error'], contains('cartell'));
    });

    test('un nome con una virgoletta si rifiuta invece di eseguirlo', () async {
      // `obexctl` prende il percorso fra virgolette (divide i comandi sugli
      // spazi, e «preventivo casa.txt» diventerebbe due argomenti). Una
      // virgoletta DENTRO il nome romperebbe la citazione: si controlla,
      // invece di sperare che nessuno chiami così un file.
      final f = await scrivi('vir"goletta.txt');
      final r = await condivisione.invia('bluetooth', [f],
          bersaglio: 'AA:BB:CC:DD:EE:FF');
      expect(r['ok'], isFalse);
      expect(r['error'], contains('virgoletta'));
    });

    test('una cartella non si allega a un\'email: va compressa prima',
        () async {
      final cartella = Directory('${temp.path}/foto')..createSync();
      final r = await condivisione.invia('email', [cartella.path]);
      expect(r['ok'], isFalse);
      expect(r['error'], contains('foto'));
      expect(r['error'], contains('cartell'));
    });
  });
}
