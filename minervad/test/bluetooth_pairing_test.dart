import 'package:minervad/services/bluetooth_pairing_service.dart';
import 'package:test/test.dart';

/// Prove sull'accoppiamento di un dispositivo che vuole confrontare un codice.
///
/// Quello che si può provare qui è la **lettura di quello che dice BlueZ**, ed
/// è anche la parte che sbaglia più facilmente: il resto è una sessione di
/// `bluetoothctl` vera, con dentro un telefono vero e una persona che guarda.
///
/// Le stringhe qui sotto sono quelle che `bluetoothctl` stampa davvero,
/// compresi i colori: senza toglierli, «Confirm passkey» non combacia mai
/// perché in mezzo c'è un `\x1b[0;93m`, e l'accoppiamento scade mentre la
/// domanda era già arrivata.
void main() {
  group('le domande di BlueZ', () {
    test('il confronto del codice — la domanda che il telefono pretende', () {
      final d = BluetoothPairingService.leggiDomanda(
          '[agent] Confirm passkey 418322 (yes/no): ');
      expect(d, isNotNull);
      expect(d!['tipo'], 'codice');
      expect(d['codice'], '418322');
    });

    test('e la riconosce anche vestita dei colori di bluetoothctl', () {
      // È il caso VERO: `bluetoothctl` colora tutto quello che stampa.
      final d = BluetoothPairingService.leggiDomanda(
          '\x1b[0;93m[agent]\x1b[0m Confirm passkey \x1b[1m036114\x1b[0m '
          '(yes/no): ');
      expect(d, isNotNull);
      expect(d!['tipo'], 'codice');
      expect(d['codice'], '036114');
    });

    test('un codice che comincia per zero non perde lo zero', () {
      // Se si leggesse come numero invece che come testo, «036114» diventerebbe
      // «36114» e chi guarda confronterebbe cinque cifre con sei.
      final d = BluetoothPairingService.leggiDomanda(
          '[agent] Confirm passkey 036114 (yes/no): ');
      expect(d!['codice'], '036114');
      expect((d['codice'] as String).length, 6);
    });

    test('«accetti l\'accoppiamento?» senza nessun codice', () {
      final d = BluetoothPairingService.leggiDomanda(
          '[agent] Accept pairing (yes/no): ');
      expect(d!['tipo'], 'conferma');
    });

    test('l\'autorizzazione di un servizio si riconosce a parte', () {
      // Va risposta da soli: arriva dopo l'accoppiamento, una volta per
      // servizio, e chiede di un numero che non vuol dire niente per nessuno.
      final d = BluetoothPairingService.leggiDomanda(
          '[agent] Authorize service 0000110d-0000-1000-8000-00805f9b34fb '
          '(yes/no): ');
      expect(d!['tipo'], 'servizio');
    });

    test('il codice da BATTERE qui è un\'altra cosa', () {
      expect(BluetoothPairingService.leggiDomanda(
          '[agent] Enter passkey (number in 0-999999): ')!['tipo'], 'pin');
      expect(BluetoothPairingService.leggiDomanda(
          '[agent] Enter PIN code: ')!['tipo'], 'pin');
    });

    test('il chiacchiericcio normale non è una domanda', () {
      // `bluetoothctl` stampa in continuazione le proprietà che cambiano.
      // Scambiarne una per una domanda vorrebbe dire fermare l'accoppiamento
      // per chiedere qualcosa a cui nessuno può rispondere.
      const rumore = '[CHG] Device 04:BD:BF:45:BD:6D RSSI: -62\n'
          '[CHG] Controller D8:F3:BC:4D:EF:24 Discovering: yes\n'
          'Attempting to pair with 04:BD:BF:45:BD:6D\n';
      expect(BluetoothPairingService.leggiDomanda(rumore), isNull);
    });
  });

  group('com\'è andata a finire', () {
    test('riuscito', () {
      final e = BluetoothPairingService.leggiEsito(
          '[\x1b[0;92mCHG\x1b[0m] Device 04:BD:BF:45:BD:6D Paired: yes\n'
          'Pairing successful\n');
      expect(e!['ok'], isTrue);
    });

    test('già accoppiato NON è un guasto', () {
      // Dirlo come errore manderebbe a cercare un problema che non c'è.
      final e = BluetoothPairingService.leggiEsito(
          'Failed to pair: org.bluez.Error.AlreadyExists');
      expect(e!['ok'], isTrue);
      expect(e['giaAccoppiato'], isTrue);
    });

    test('ogni modo di fallire ha il suo motivo, e non è un codice', () {
      // Chi legge deve sapere che cosa fare dopo: rimettere in modalità
      // accoppiamento è una cosa, «il codice non corrispondeva» un'altra.
      final casi = {
        'org.bluez.Error.AuthenticationCanceled': 'annullato',
        'org.bluez.Error.AuthenticationRejected': 'rifiutato',
        'org.bluez.Error.AuthenticationFailed': 'corrispondeva',
        'org.bluez.Error.AuthenticationTimeout': 'tempo',
      };
      casi.forEach((errore, atteso) {
        final e = BluetoothPairingService.leggiEsito('Failed to pair: $errore');
        expect(e, isNotNull, reason: errore);
        expect(e!['ok'], isFalse, reason: errore);
        expect((e['error'] as String).toLowerCase(), contains(atteso),
            reason: '$errore → ${e['error']}');
      });
    });

    test('finché non è finita, non si dice niente', () {
      // Un esito inventato a metà strada chiuderebbe la sessione mentre il
      // telefono sta ancora aspettando.
      expect(
          BluetoothPairingService.leggiEsito(
              'Attempting to pair with 04:BD:BF:45:BD:6D\n'
              '[CHG] Device 04:BD:BF:45:BD:6D Connected: yes\n'),
          isNull);
    });
  });

  group('i colori non devono cambiare il senso', () {
    test('pulisci toglie i colori e lascia il testo', () {
      expect(
          BluetoothPairingService.pulisci('\x1b[0;93mciao\x1b[0m mondo'),
          'ciao mondo');
    });

    test('e il ritorno a capo di bluetoothctl non incolla due righe', () {
      // `bluetoothctl` usa `\r` per riscrivere il prompt: lasciandolo, due
      // righe diverse diventano una sola e i confronti saltano.
      expect(BluetoothPairingService.pulisci('primo\rsecondo'),
          'primo\nsecondo');
    });
  });
}
