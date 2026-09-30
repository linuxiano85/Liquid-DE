import 'dart:async';
import 'dart:io';

import '../core/event_bus.dart';
import 'dbus.dart';
import 'processo_limitato.dart';

/// SystemStateService — Lo stato dell'apparecchio, letto UNA VOLTA per tutti.
///
/// ── Perché sta nel demone ──────────────────────────────────────────────────
///
/// Prima stava in `minerva-shell/core/SystemState.qml`, che è un singleton —
/// ma un singleton per PROCESSO, e i processi di Minerva sono tre: la barra,
/// il gestore file, le Impostazioni. Ognuno interrogava il sistema per conto
/// suo con il proprio giro da dodici secondi.
///
/// Due conseguenze, e la seconda è quella che si sentiva.
///
/// La prima: tre volte i processi lanciati. Ogni giro sono quattro comandi di
/// shell (`bluetoothctl`, `nmcli`, `brightnessctl`, la batteria da sysfs), e
/// `nmcli` da solo non è leggero. Per tre finestre aperte fanno dodici
/// processi ogni dodici secondi, per dati che cambiano una volta all'ora.
///
/// La seconda: **i tre non si parlavano**. Spegnendo il Bluetooth dalle
/// Impostazioni, la barra continuava a mostrarlo acceso fino al proprio giro —
/// fino a dodici secondi, in media sei. È il ritardo che Giacomo aveva
/// segnalato, e non era lentezza: era una finestra che non poteva sapere.
///
/// Qui la lettura è una e il risultato arriva a tutti nello stesso istante.
/// Anche i comandi passano da qui, e per lo stesso motivo: chi spegne il
/// Bluetooth non deve avvisare le altre finestre — non le conosce — ma il
/// demone sì.
///
/// ── Che cosa NON sta qui ───────────────────────────────────────────────────
///
/// Il volume. PipeWire lo ANNUNCIA nell'istante in cui cambia, chiunque
/// l'abbia cambiato, e ogni processo lo riceve da sé senza interrogare
/// niente: farlo passare di qui aggiungerebbe un rimbalzo a un dato che
/// arriva già istantaneo. La regola è quella, e vale anche per il prossimo
/// pezzo di stato che aggiungeremo: **si sposta qui ciò che va INTERROGATO,
/// resta dov'è ciò che il sistema già ANNUNCIA.**
/// La potenza del Wi-Fi in percentuale, ricavata dal testo di
/// `/proc/net/wireless`. Zero se lì dentro non c'è nessuna interfaccia.
///
/// Sta fuori dalla classe perché è l'unico pezzo di questo file che si può
/// provare senza un computer: gli si dà un testo e dice un numero. Il testo
/// vero è fatto così — due righe di intestazione e poi una riga per scheda:
///
///     Inter-| sta-|   Quality        |   Discarded packets  | Missed | WE
///      face | tus | link level noise |  nwid crypt frag ... | beacon | 22
///      wlan0: 0000   47.  -63.  -256     0     0    0   ...        0
///
/// Le intestazioni si riconoscono dal non avere i due punti attaccati al nome
/// dell'interfaccia. «link» è il secondo numero e arriva col punto finale.
/// La scala è su 70: è quella dei driver `nl80211`, non una percentuale.
/// Un blocco `rfkill` letto da sysfs: che cosa è, e se è bloccato.
class VoceRfkill {
  final String tipo; // 'wlan', 'bluetooth', ...
  final bool soft;
  final bool hard;
  const VoceRfkill(this.tipo, this.soft, this.hard);
}

/// La radio Wi-Fi è accesa? E ce n'è una?
///
/// ── Perché serviva, e perché non c'era ────────────────────────────────────
///
/// L'interruttore del Wi-Fi nel pannello guardava `networkConnected`, cioè
/// «esiste una connessione attiva». Non è la stessa cosa, e i due casi in cui
/// si vedeva sono tutti e due normali:
///
///   * **col cavo attaccato** la connessione attiva c'è, quindi l'interruttore
///     del Wi-Fi risultava ACCESO anche con la radio spenta;
///   * **radio accesa ma nessuna rete agganciata** — appena rientrato in casa,
///     o in un posto nuovo — l'interruttore risultava spento, e premerlo
///     spegneva davvero la radio invece di accenderla.
///
/// La verità sta in `/sys/class/rfkill`, che è dove `nmcli radio wifi off`
/// scrive: nessun processo da lanciare, solo file da leggere. `hard` è
/// l'interruttore fisico del portatile, e da software non si tocca.
({bool presente, bool accesa}) wifiDaRfkill(List<VoceRfkill> voci) {
  var presente = false;
  var accesa = false;
  for (final v in voci) {
    if (v.tipo != 'wlan') continue;
    presente = true;
    if (!v.soft && !v.hard) accesa = true;
  }
  return (presente: presente, accesa: accesa);
}

int potenzaDaProcNetWireless(String testo) {
  for (final riga in testo.split('\n')) {
    final i = riga.indexOf(':');
    if (i < 0) continue;
    final campi = riga.substring(i + 1).trim().split(RegExp(r'\s+'));
    if (campi.length < 2) continue;
    final qualita = double.tryParse(campi[1].replaceAll('.', ''));
    if (qualita == null) continue;
    return (qualita * 100 / 70).round().clamp(0, 100);
  }
  return 0;
}

class SystemStateService {
  final EventBus _eventBus;

  SystemStateService(this._eventBus);

  // ── Lo stato ─────────────────────────────────────────────────────────────

  int _batteryPercent = -1; // -1 = nessuna batteria
  bool _batteryCharging = false;
  int _brightness = -1; // -1 = non regolabile
  String _networkName = '';
  int _networkStrength = 0;
  bool _networkWired = false;
  bool _wifiPresent = false;
  bool _wifiOn = false;
  bool _bluetoothPresent = true;
  bool _bluetoothOn = false;
  String _bluetoothBlock = ''; // '', 'soft', 'hard'
  String _bluetoothDevice = '';
  /// Tutti gli apparecchi accoppiati, con quanto sanno dire di sé: nome,
  /// classe (`Icon` di BlueZ: `input-mouse`, `audio-headset`, `phone`…),
  /// se sono connessi, e la batteria — che BlueZ espone in
  /// `org.bluez.Battery1` solo per chi è connesso e la dichiara. Serve al
  /// widget della scrivania (14 settembre 2026): un elenco, non un nome.
  List<Map<String, dynamic>> _bluetoothDispositivi = const [];

  Map<String, dynamic> get state => {
        'batteryPercent': _batteryPercent,
        'batteryCharging': _batteryCharging,
        'brightness': _brightness,
        'networkName': _networkName,
        'networkStrength': _networkStrength,
        'networkWired': _networkWired,
        'wifiPresent': _wifiPresent,
        'wifiOn': _wifiOn,
        'bluetoothPresent': _bluetoothPresent,
        'bluetoothOn': _bluetoothOn,
        'bluetoothBlock': _bluetoothBlock,
        'bluetoothDevice': _bluetoothDevice,
        'bluetoothDevices': _bluetoothDispositivi,
      };

  Timer? _slow;
  Timer? _verify;
  bool _leggendo = false;
  bool _daRileggere = false;

  /// Ogni quanto si rilegge quando non succede niente.
  static const Duration _riposo = Duration(seconds: 12);

  /// Quanto si aspetta dopo un comando prima di rileggere. Non zero: fra il
  /// `bluetoothctl power on` e il momento in cui l'adattatore lo dice passa
  /// del tempo, e rileggendo subito si otterrebbe lo stato di prima — cioè si
  /// rimetterebbe l'interruttore dove stava, sotto le dita di chi l'ha appena
  /// spostato.
  static const Duration _dopoUnComando = Duration(milliseconds: 900);

  Future<void> init() async {
    await leggi();
    _slow = Timer.periodic(_riposo, (_) => leggi());
    print('[MINERVA][SISTEMA][OK] Stato di sistema condiviso, letto ogni '
        '${_riposo.inSeconds} s per tutte le finestre.');
  }

  Future<void> dispose() async {
    _slow?.cancel();
    _verify?.cancel();
  }

  // ── Lettura ──────────────────────────────────────────────────────────────

  /// Esegue uno script di shell e ne restituisce l'uscita, o "" se qualcosa
  /// va storto. Un comando che manca (niente `nmcli`, niente `brightnessctl`)
  /// non è un errore: è un computer diverso dal nostro.
  ///
  /// Con `eseguiLimitato`: allo scadere la shell si uccide invece di restare
  /// viva dietro a un future che nessuno aspetta più (30 settembre 2026).
  Future<String> _sh(String script) async {
    try {
      final r = await eseguiLimitato('sh', ['-c', script],
          limite: const Duration(seconds: 8));
      return r.scaduto ? '' : r.stdout;
    } catch (_) {
      return '';
    }
  }

  /// Rilegge tutto e, se è cambiato qualcosa, lo dice a tutti.
  ///
  /// Le quattro letture partono INSIEME: in fila indiana il giro durerebbe
  /// quanto la loro somma, e `nmcli` da solo può prendersi un secondo.
  /// ── Una lettura alla volta, ma nessuna buttata ─────────────────────────
  ///
  /// Prima chi arrivava mentre un giro era in corso tornava indietro e basta.
  /// Sembra prudente e invece perde proprio la lettura che conta: dopo ogni
  /// comando (`setBluetooth`, `setWifi`) parte una **riverifica**, che serve a
  /// correggere l'interruttore se il comando non ha funzionato. Se cadeva
  /// dentro il giro periodico da dodici secondi veniva scartata, e l'unica
  /// cosa che restava a schermo era il valore ottimistico che avevamo scritto
  /// noi: l'interruttore diceva «acceso» perché gliel'avevamo detto, non
  /// perché lo fosse.
  ///
  /// Ora si segna che va rifatta e si rifà **una volta** alla fine.
  Future<void> leggi() async {
    if (_leggendo) {
      _daRileggere = true;
      return;
    }
    _leggendo = true;
    try {
      do {
        _daRileggere = false;
        final prima = state.toString();
        await Future.wait([
          _leggiBatteria(),
          _leggiLuminosita(),
          _leggiRete(),
          _leggiBluetooth(),
        ]);
        // Si annuncia solo se è cambiato qualcosa: svegliare tre processi ogni
        // dodici secondi per dire che è tutto come prima è esattamente lo
        // spreco che questo file esiste per togliere.
        if (state.toString() != prima) {
          _eventBus.publish(MinervaEvent(type: 'system_state', payload: state));
        }
      } while (_daRileggere);
    } catch (e) {
      print('[MINERVA][SISTEMA][ERRORE] Lettura dello stato fallita: $e');
    } finally {
      _leggendo = false;
    }
  }

  /// Legge un file di sysfs, o "" se non c'è. Non è la stessa cosa che
  /// chiedere a `sh` di fare `cat`: è una lettura sola, dentro questo
  /// processo, senza fork, senza exec e senza aspettare che un altro
  /// programma parta e finisca.
  String _file(String percorso) {
    try {
      return File(percorso).readAsStringSync().trim();
    } catch (_) {
      return '';
    }
  }

  /// Tutti i blocchi `rfkill` del computer, letti da sysfs.
  List<VoceRfkill> _leggiRfkill() {
    final voci = <VoceRfkill>[];
    try {
      for (final v in Directory('/sys/class/rfkill').listSync()) {
        final tipo = _file('${v.path}/type');
        if (tipo.isEmpty) continue;
        voci.add(VoceRfkill(
          tipo,
          _file('${v.path}/soft') == '1',
          _file('${v.path}/hard') == '1',
        ));
      }
    } catch (_) {
      // Nessun rfkill: un computer senza radio, o un contenitore.
    }
    return voci;
  }

  /// La prima cartella che corrisponde a un modello del tipo /a/b/PREFISSO*,
  /// o "" se non ce n'è nessuna.
  String _primaCartella(String genitore, String prefisso) {
    try {
      final voci = Directory(genitore).listSync();
      for (final v in voci) {
        final nome = v.path.split('/').last;
        if (nome.startsWith(prefisso)) return v.path;
      }
    } catch (_) {}
    return '';
  }

  /// Legge la batteria da sysfs: nessun demone di mezzo, e funziona anche
  /// dove upower non è installato.
  ///
  /// Si leggono i file direttamente. Prima qui c'era un `sh -c` con dentro un
  /// ciclo e due `cat`: quattro processi ogni dodici secondi per due numeri
  /// che stanno in due file. Il costo di un dato non è leggerlo, è svegliare
  /// qualcuno perché lo legga al posto tuo.
  Future<void> _leggiBatteria() async {
    final bat = _primaCartella('/sys/class/power_supply', 'BAT');
    if (bat.isEmpty) {
      _batteryPercent = -1;
      _batteryCharging = false;
      return;
    }
    final capacita = _file('$bat/capacity');
    if (capacita.isEmpty) {
      _batteryPercent = -1;
      _batteryCharging = false;
      return;
    }
    final stato = _file('$bat/status');
    _batteryPercent = int.tryParse(capacita) ?? -1;
    _batteryCharging = stato == 'Charging' || stato == 'Full';
  }

  /// La luminosità, sempre da sysfs.
  ///
  /// `brightnessctl` legge esattamente questi due file, e per farlo bisognava
  /// lanciarlo due volte. Resta indispensabile per SCRIVERE la luminosità —
  /// lì serve il permesso, che lui ha e noi no — ma per leggerla no.
  Future<void> _leggiLuminosita() async {
    final b = _primaCartella('/sys/class/backlight', '');
    if (b.isEmpty) {
      _brightness = -1;
      return;
    }
    final cur = int.tryParse(_file('$b/brightness'));
    final max = int.tryParse(_file('$b/max_brightness'));
    if (cur == null || max == null || max <= 0) {
      _brightness = -1;
      return;
    }
    _brightness = (cur * 100 / max).round();
  }

  /// La rete.
  ///
  /// `LC_ALL=C` non è un vezzo: senza, `nmcli` risponde nella lingua del
  /// sistema e in italiano scrive «sì» dove il codice cercava «yes». Il
  /// Wi-Fi risultava sempre scollegato pur essendo attivo. Si legge il TIPO
  /// della connessione (`802-11-wireless`), che è un identificatore e non
  /// viene tradotto in nessuna lingua.
  ///
  /// ── Il costo nascosto: `nmcli dev wifi` fa una SCANSIONE ─────────────
  ///
  /// Qui prima c'erano tre `nmcli` e tre `awk` dentro una shell, e uno dei
  /// tre era `nmcli -t -f IN-USE,SIGNAL dev wifi`. Quel comando non legge un
  /// numero: chiede a NetworkManager l'elenco delle reti, e con la politica
  /// di serie (`--rescan auto`) fa rifare la scansione se l'ultima è
  /// vecchia. Misurato il 30 luglio 2026 su questa macchina: il gruppo di
  /// processi restava vivo per secondi interi, ogni dodici. E una scansione
  /// Wi-Fi non costa solo CPU — la scheda smette di ascoltare il proprio
  /// canale mentre gira sugli altri, quindi la rete stessa singhiozza.
  ///
  /// La potenza del segnale sta già in `/proc/net/wireless`, aggiornata dal
  /// kernel: un file, nessun processo, nessuna scansione. La qualità è su 70
  /// (è la scala che usano i driver `nl80211`), da cui la conversione.
  ///
  /// Resta un solo `nmcli`, per i NOMI delle connessioni attive, che
  /// NetworkManager conosce e sysfs no. Lanciato direttamente, senza shell in
  /// mezzo: da sette processi a uno.
  Future<void> _leggiRete() async {
    var wired = false, wiredName = '', name = '';
    var strength = 0;

    // `LC_ALL=C` non è un vezzo: senza, `nmcli` risponde nella lingua del
    // sistema. Si legge comunque il TIPO (`802-11-wireless`), che è un
    // identificatore e non viene tradotto, ma il resto dell'uscita sì.
    String attive = '';
    try {
      final r = await eseguiLimitato(
        'nmcli',
        ['-t', '-f', 'TYPE,NAME', 'connection', 'show', '--active'],
        ambiente: {'LC_ALL': 'C'},
        limite: const Duration(seconds: 8),
      );
      if (!r.scaduto) attive = r.stdout;
    } catch (_) {
      // nmcli che manca non è un errore: è un computer diverso dal nostro.
    }

    for (final riga in attive.split('\n')) {
      // Il nome può contenere due punti; il tipo no. Si divide una volta sola.
      final i = riga.indexOf(':');
      if (i < 0) continue;
      final tipo = riga.substring(0, i);
      final n = riga.substring(i + 1).trim();
      if (tipo == '802-11-wireless' && name.isEmpty) {
        name = n;
      } else if (tipo == '802-3-ethernet' && !wired) {
        wired = true;
        wiredName = n;
      }
    }

    if (!wired && name.isNotEmpty) {
      strength = potenzaDaProcNetWireless(_file('/proc/net/wireless'));
    }

    // La radio, che è un'altra cosa dalla connessione. Solo letture di file.
    final radio = wifiDaRfkill(_leggiRfkill());
    _wifiPresent = radio.presente;
    _wifiOn = radio.accesa;

    // Il cavo ha la precedenza sul Wi-Fi: quando ci sono entrambi è il cavo
    // che porta il traffico, ed è quello che conta dire.
    _networkWired = wired;
    _networkName = wired ? (wiredName.isNotEmpty ? wiredName : 'Ethernet') : name;
    _networkStrength = wired ? 100 : strength;
  }

  /// Il Bluetooth.
  ///
  /// Si legge anche `rfkill`, e non per completezza: senza, un adattatore
  /// bloccato via software è indistinguibile da uno spento, e l'unica
  /// differenza che conta — «lo posso accendere?» — resta invisibile.
  ///
  /// L'adattatore si cerca con `bluetoothctl list` e NON con la riga
  /// `Address:` dentro `bluetoothctl show`: su BlueZ 5.7x quella riga non
  /// esiste più, e Minerva dichiarava «nessun adattatore Bluetooth» su un
  /// computer col Bluetooth acceso e funzionante. Non era rotto: era
  /// invisibile.
  Future<void> _leggiBluetooth() async {
    // ── Una domanda a BlueZ, non quattro grep ─────────────────────────────
    //
    // `GetManagedObjects` torna in un colpo solo tutti gli adattatori e tutti
    // i dispositivi, con le loro proprietà già tipate. Prima ci volevano
    // quattro comandi in fila e tre erano `grep` su prosa: è esattamente lì
    // che si era rotto, quando BlueZ ha smesso di stampare `Address:`.
    final oggetti = await Dbus.oggetti('org.bluez', '/');

    if (oggetti == null) {
      // Nessun BlueZ sul bus: il Bluetooth non c'è proprio. È diverso da
      // «c'è ed è spento», e l'interfaccia lo mostra in modo diverso.
      _bluetoothPresent = false;
      _bluetoothOn = false;
      _bluetoothBlock = '';
      _bluetoothDevice = '';
      _bluetoothDispositivi = const [];
      return;
    }

    var trovatoAdattatore = false;
    var acceso = false;
    var connesso = '';
    final elenco = <Map<String, dynamic>>[];

    for (final interfacce in oggetti.values) {
      final adattatore = interfacce['org.bluez.Adapter1'];
      if (adattatore != null) {
        trovatoAdattatore = true;
        // Basta UNO acceso: con due adattatori, dire spento perché il secondo
        // lo è sarebbe falso proprio sul computer che ne ha di più.
        if (adattatore['Powered'] == true) acceso = true;
      }
      final dispositivo = interfacce['org.bluez.Device1'];
      if (dispositivo != null) {
        // `Alias` è il nome che l'utente vede e può cambiare; `Name` quello
        // che dichiara l'apparecchio. Il primo che c'è dei due.
        final alias = dispositivo['Alias'] ?? dispositivo['Name'];
        final nome = alias is String ? alias.trim() : '';
        final connessoOra = dispositivo['Connected'] == true;
        if (connessoOra && connesso.isEmpty && nome.isNotEmpty) connesso = nome;

        // Solo gli accoppiati: gli altri sono quello che BlueZ ha sentito
        // passare durante una ricerca — il telefono del vicino — e non sono
        // «i tuoi apparecchi».
        if (dispositivo['Paired'] == true && nome.isNotEmpty) {
          final batteria = interfacce['org.bluez.Battery1']?['Percentage'];
          elenco.add(<String, dynamic>{
            'nome': nome,
            'icona': dispositivo['Icon'] is String ? dispositivo['Icon'] : '',
            'connesso': connessoOra,
            'batteria': batteria is num ? batteria.toInt() : -1,
            'mac': dispositivo['Address'] is String ? dispositivo['Address'] : '',
          });
        }
      }
    }
    // I connessi prima, poi per nome: chi guarda cerca «quello che sto
    // usando», e un elenco che cambia ordine a ogni lettura è un elenco in
    // cui l'occhio non trova mai niente.
    elenco.sort((a, b) {
      if (a['connesso'] != b['connesso']) return a['connesso'] == true ? -1 : 1;
      return (a['nome'] as String).toLowerCase().compareTo((b['nome'] as String).toLowerCase());
    });
    _bluetoothDispositivi = elenco;

    _bluetoothPresent = trovatoAdattatore;
    _bluetoothOn = trovatoAdattatore && acceso;
    _bluetoothDevice = connesso;

    // ── `rfkill` resta, e non è un ripiego ───────────────────────────────
    //
    // Il blocco hardware (l'interruttore fisico, il tasto Fn) non è una
    // proprietà di BlueZ: BlueZ vede solo un adattatore spento. La differenza
    // che conta per chi guarda — «lo posso riaccendere da qui?» — la sa solo
    // il kernel, e la dice `rfkill`. Non c'è un'interfaccia D-Bus che la
    // esponga senza tirarsi dentro tutto systemd-rfkill.
    _bluetoothBlock = trovatoAdattatore ? await _leggiBlocco() : '';
  }

  /// Se l'adattatore è bloccato, e da cosa: `hard` (interruttore fisico),
  /// `soft` (bloccato via software, si sblocca), vuoto se libero.
  Future<String> _leggiBlocco() async {
    final out = await _sh('rfkill list bluetooth 2>/dev/null | awk \''
        '/Hard blocked: yes/{h=1} /Soft blocked: yes/{s=1} '
        'END{print h ? "hard" : (s ? "soft" : "")}\'');
    return out.trim();
  }

  // ── Comandi ──────────────────────────────────────────────────────────────
  //
  // Passano da qui e non dalla finestra che li ha chiesti, così l'effetto lo
  // vedono tutte insieme. Lo stato si aggiorna SUBITO in memoria e si annuncia
  // — l'interruttore deve scattare sotto il dito, non fra un secondo — e poi
  // si rilegge la realtà per correggersi se il comando non ha funzionato.

  Future<void> setBluetooth(bool acceso) async {
    _bluetoothOn = acceso;
    _eventBus.publish(MinervaEvent(type: 'system_state', payload: state));

    if (acceso) {
      // Prima si toglie il blocco, e non è un dettaglio: su certi portatili
      // `rfkill` tiene l'adattatore soft-blocked, e finché è così accenderlo
      // non fallisce — non fa proprio niente, in silenzio. L'interruttore si
      // accendeva e l'adattatore restava spento.
      //
      // Resta un comando e non una chiamata D-Bus perché il blocco è del
      // kernel, non di BlueZ: vedi `_leggiBlocco`. Il mezzo secondo serve
      // perché fra lo sblocco e l'adattatore che torna sul bus passa un
      // istante, e scrivendo subito si scrive su un oggetto che non c'è.
      await _sh('rfkill unblock bluetooth 2>/dev/null; sleep 0.3');
    }
    await _accendiAdattatori(acceso);
    _riverifica();
  }

  /// Accende o spegne OGNI adattatore Bluetooth, scrivendo la proprietà
  /// `Powered` su D-Bus.
  ///
  /// Non passa più da `bluetoothctl power`, che è un programma interattivo
  /// pilotato da riga di comando: lì «acceso» era una parola in una frase,
  /// qui è un booleano su un'interfaccia che BlueZ mantiene apposta.
  ///
  /// Il risultato non si crede sulla parola — `setBluetooth` rilegge subito
  /// dopo con `_riverifica()`, ed è quella lettura a dire la verità.
  Future<void> _accendiAdattatori(bool acceso) async {
    final oggetti = await Dbus.oggetti('org.bluez', '/');
    if (oggetti == null) return;
    for (final voce in oggetti.entries) {
      if (!voce.value.containsKey('org.bluez.Adapter1')) continue;
      await Dbus.scrivi('org.bluez', voce.key, 'org.bluez.Adapter1', 'Powered',
          'b', acceso ? 'true' : 'false');
    }
  }

  /// Come il Bluetooth: lo stato si scrive subito e si annuncia, così
  /// l'interruttore scatta sotto il dito, e poi si rilegge la realtà.
  /// Mancava, ed era l'unico dei tre comandi a non farlo: si premeva, e per
  /// quasi un secondo l'interruttore restava dov'era.
  Future<void> setWifi(bool acceso) async {
    _wifiOn = acceso;
    _eventBus.publish(MinervaEvent(type: 'system_state', payload: state));
    await _sh('nmcli radio wifi ${acceso ? "on" : "off"} >/dev/null 2>&1');
    _riverifica();
  }

  Future<void> setBrightness(int percento) async {
    final v = percento.clamp(1, 100);
    _brightness = v;
    _eventBus.publish(MinervaEvent(type: 'system_state', payload: state));
    await _sh('brightnessctl -q set $v% 2>/dev/null');
  }

  void _riverifica() {
    _verify?.cancel();
    _verify = Timer(_dopoUnComando, () => leggi());
  }
}
