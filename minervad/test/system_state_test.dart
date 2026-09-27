import 'dart:io';

import 'package:test/test.dart';
import 'package:minervad/core/event_bus.dart';
import 'package:minervad/services/system_state_service.dart';
import 'codice_vivo.dart';

/// Il file QML che consuma questo stato.
File _systemStateQml() {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    final f = File('${dir.path}/minerva-shell/core/SystemState.qml');
    if (f.existsSync()) return f;
    dir = dir.parent;
  }
  fail('non trovo minerva-shell/core/SystemState.qml');
}

void main() {
  group('stato di sistema', () {
    test('lo stato parte da valori che dicono «non lo so ancora»', () {
      final s = SystemStateService(EventBus()).state;
      // -1 e non 0: zero per cento di batteria è un'informazione, «non c'è
      // batteria» è un'altra, e la barra deve poterle distinguere o su un
      // computer fisso mostrerebbe una batteria scarica che non esiste.
      expect(s['batteryPercent'], -1);
      expect(s['brightness'], -1);
      expect(s['networkName'], '');
      expect(s['bluetoothOn'], false);
    });

    test('ogni campo letto dal QML esiste davvero nello stato del demone', () {
      // È lo stesso vincolo delle icone, e lo stesso motivo per cui va
      // controllato da una macchina: `SystemState.qml` legge i campi per nome
      // e salta quelli `undefined`. Rinominandone uno qui, il QML non dà
      // nessun errore — si limita a tenere per sempre il valore di partenza.
      // La batteria resterebbe a «-1», cioè sparirebbe dalla barra, e nessuno
      // saprebbe perché.
      final qml = _systemStateQml().codiceVivo();
      final letti = RegExp(r's\.(\w+) !== undefined')
          .allMatches(qml)
          .map((m) => m.group(1)!)
          .toSet();

      expect(letti, isNotEmpty,
          reason: 'il QML non legge più nessun campo: cambiata la forma?');

      final offerti = SystemStateService(EventBus()).state.keys.toSet();
      for (final campo in letti) {
        expect(offerti, contains(campo),
            reason: '`SystemState.qml` legge "$campo", che il demone non manda');
      }
    });

    test('il QML non lancia più nessun processo per leggere lo stato', () {
      // Il punto di tutto lo spostamento: se qui ricomparisse un `Process`,
      // tornerebbero tre finestre che interrogano il sistema per conto loro e
      // non si parlano — il ritardo di sei secondi sul Bluetooth.
      final qml = _systemStateQml().codiceVivo();
      final righe = qml
          .split('\n')
          .where((r) => !r.trimLeft().startsWith('//'))
          .join('\n');
      expect(righe.contains('Process {'), isFalse,
          reason: 'un processo di lettura è tornato in SystemState.qml');
    });

    test('la potenza del Wi-Fi si legge da /proc/net/wireless', () {
      // Il testo è quello vero, copiato da questa macchina il 30 luglio 2026.
      // Le due righe di intestazione DEVONO essere ignorate: la seconda
      // contiene numeri («22» in fondo) e un parser distratto li prende per
      // qualità del segnale, riportando 31% con la scheda spenta.
      const vero = 'Inter-| sta-|   Quality        |   Discarded packets   '
          '            | Missed | WE\n'
          ' face | tus | link level noise |  nwid  crypt   frag  retry   '
          'misc | beacon | 22\n'
          ' wlan0: 0000   47.  -63.  -256        0      0      0      0    '
          '352        0\n';
      // 47 su 70 fanno 67.
      expect(potenzaDaProcNetWireless(vero), 67);
    });

    // ── La radio Wi-Fi non è la connessione ────────────────────────────────
    //
    // L'interruttore guardava `networkConnected`. Sbagliava in tutti e due i
    // versi, e tutti e due i casi sono normali: col cavo attaccato risultava
    // acceso a radio spenta, e con la radio accesa ma nessuna rete agganciata
    // risultava spento — così premerlo la spegneva invece di accenderla.
    test('la radio è accesa quando nessun blocco è attivo', () {
      final r = wifiDaRfkill(const [VoceRfkill('wlan', false, false)]);
      expect(r.presente, isTrue);
      expect(r.accesa, isTrue);
    });

    test('un blocco software spegne la radio', () {
      final r = wifiDaRfkill(const [VoceRfkill('wlan', true, false)]);
      expect(r.presente, isTrue);
      expect(r.accesa, isFalse,
          reason: '`nmcli radio wifi off` scrive proprio qui');
    });

    test('l\'interruttore fisico del portatile spegne la radio', () {
      final r = wifiDaRfkill(const [VoceRfkill('wlan', false, true)]);
      expect(r.accesa, isFalse);
    });

    test('il Bluetooth bloccato non spegne il Wi-Fi', () {
      final r = wifiDaRfkill(const [
        VoceRfkill('bluetooth', true, false),
        VoceRfkill('wlan', false, false),
      ]);
      expect(r.presente, isTrue);
      expect(r.accesa, isTrue,
          reason: 'sono due radio diverse: guardare il tipo sbagliato '
              'spegnerebbe il Wi-Fi a chi ha solo il Bluetooth bloccato');
    });

    test('su un fisso senza scheda Wi-Fi non c\'è radio da mostrare', () {
      final r = wifiDaRfkill(const [VoceRfkill('bluetooth', false, false)]);
      expect(r.presente, isFalse);
      expect(r.accesa, isFalse);
      expect(wifiDaRfkill(const []).presente, isFalse);
    });

    test('due schede Wi-Fi: basta che una sia accesa', () {
      final r = wifiDaRfkill(const [
        VoceRfkill('wlan', true, false),
        VoceRfkill('wlan', false, false),
      ]);
      expect(r.accesa, isTrue);
    });

    test('senza scheda Wi-Fi la potenza è zero, non un numero a caso', () {
      // Su un fisso il file esiste con le sole intestazioni. Se ne uscisse un
      // numero, la barra mostrerebbe un Wi-Fi che non c'è.
      const soloIntestazioni = 'Inter-| sta-|   Quality        |\n'
          ' face | tus | link level noise |\n';
      expect(potenzaDaProcNetWireless(soloIntestazioni), 0);
      expect(potenzaDaProcNetWireless(''), 0);
    });

    test('lo stato di sistema non fa più scansioni Wi-Fi', () {
      // `nmcli dev wifi` non legge un numero: chiede l'elenco delle reti, e
      // con la politica di serie fa RIFARE la scansione. Ogni dodici secondi,
      // per un dato che sta già in un file del kernel — e mentre la scheda
      // scandisce gli altri canali, la rete vera singhiozza.
      var dir = Directory.current;
      File? f;
      for (var i = 0; i < 4; i++) {
        final c = File('${dir.path}/minervad/lib/services/'
            'system_state_service.dart');
        if (c.existsSync()) {
          f = c;
          break;
        }
        final c2 =
            File('${dir.path}/lib/services/system_state_service.dart');
        if (c2.existsSync()) {
          f = c2;
          break;
        }
        dir = dir.parent;
      }
      expect(f, isNotNull, reason: 'non trovo system_state_service.dart');
      final codice = f!
          .readAsLinesSync()
          .where((r) => !r.trimLeft().startsWith('//') &&
              !r.trimLeft().startsWith('///'))
          .join('\n');
      expect(codice.contains('dev wifi'), isFalse,
          reason: 'è tornata una scansione Wi-Fi periodica');
      expect(codice.contains('brightnessctl get'), isFalse,
          reason: 'la luminosità si rilegge di nuovo lanciando un processo');
    });

    test('il guardiano riparte comunque il demone sia uscito', () {
      // La prima versione non ripartiva sull'uscita pulita, e il demone
      // intercetta SIGTERM: qualunque `kill` lo spegneva per il resto della
      // sessione. Vedi `scripts/minerva-demone`.
      var dir = Directory.current;
      File? script;
      for (var i = 0; i < 4; i++) {
        final f = File('${dir.path}/scripts/minerva-demone');
        if (f.existsSync()) {
          script = f;
          break;
        }
        dir = dir.parent;
      }
      expect(script, isNotNull, reason: 'non trovo scripts/minerva-demone');
      final testo = script!.codiceVivo();
      expect(testo.contains('Uscita pulita: non riparte'), isFalse,
          reason: 'il guardiano si arrende di nuovo sull\'uscita pulita');
      expect(testo.contains('trap fermati TERM INT'), isTrue,
          reason: 'fermando il guardiano deve fermarsi anche il demone, '
              'o resta un orfano che tiene la porta 11432');
    });
  });
}
