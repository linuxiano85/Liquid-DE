import 'dart:async';
import 'dart:io';

import 'dbus.dart';
import 'processo_limitato.dart';

/// ControllerService — I controller di gioco, uguali per tutti i giochi.
///
/// ── IL PROBLEMA (4 ottobre 2026) ────────────────────────────────────────────
///
/// Il DualShock 4 di Giacomo, collegato in Bluetooth, funzionava sulla
/// scrivania e non dentro GTA V avviato da Faugus. Il kernel lo vedeva
/// (`hid_playstation`), i permessi c'erano: il guaio stava sopra. Ogni gioco
/// sceglie da sé come leggere un pad — XInput, hidraw, SDL — e un DS4 grezzo
/// piace ad alcuni e non ad altri. Steam lo risolve con Steam Input, ma solo
/// per i giochi avviati DA Steam: Faugus, Heroic e Lutris lo lasciano fuori.
///
/// ── LA STRADA ───────────────────────────────────────────────────────────────
///
/// InputPlumber (ShadowBlip, quello di Bazzite e ChimeraOS) prende il pad
/// vero, lo nasconde ai giochi e ne presenta uno virtuale — di serie un pad
/// Xbox, che ogni gioco e ogni launcher capisce. Ha già le configurazioni dei
/// pad comuni, ma di suo gestisce solo quelli delle console portatili: per
/// gli altri qualcuno deve accendere `ManageAllDevices`. Quel qualcuno è
/// questo servizio, e lo fa da sé quando compare un pad: è il «Steam Input
/// per tutto» che mancava, senza che l'utente debba sapere che esiste.
///
/// Non serve la radice: la regola polkit di InputPlumber apre tutto al gruppo
/// `wheel`. Se InputPlumber non c'è, lo stato lo dice (`motore: assente`) e
/// non succede altro.
///
/// ── OGNI PAD A MODO SUO (4 ottobre 2026) ────────────────────────────────────
///
/// Giacomo: un controller Battletron, uguale a quello della PS5, ma «alla
/// giapponese» — si conferma con ○. Per ogni pad si sceglie quindi:
///
///   · un PRESET: Xbox (i giochi vedono un pad Xbox, ✕ al posto di A), o
///     PlayStation (vedono un DualSense, con i simboli giusti), o
///     Personalizzato, che diventa da sé appena si cambia un tasto;
///   · «scambia ✕ e ○», il rimedio di un tocco per i pad giapponesi;
///   · i COLORI della barra luminosa: uno a riposo e uno quando un gioco sta
///     usando il pad. «Usando» vuol dire che un processo che non è dei
///     nostri — non InputPlumber, non Steam, non il compositore — tiene
///     aperto un pad: è il momento in cui il gioco lo ha riconosciuto, non
///     quello in cui è partito.
///
/// La mappatura passa da un profilo di InputPlumber (`LoadProfileFromYaml`),
/// i colori dai LED del kernel (`/sys/class/leds`), resi scrivibili al gruppo
/// `input` da `config/udev/70-liquid-de-pad-led.rules`.
class ControllerService {
  ControllerService({
    required this.automatico,
    required this.tipo,
    required this.perPad,
    this.radiceSys = '/sys/class/input',
    this.programma = '/usr/bin/inputplumber',
  });

  static const servizio = 'org.shadowblip.InputPlumber';
  static const _gestore = '/org/shadowblip/InputPlumber/Manager';
  static const _ifGestore = 'org.shadowblip.InputManager';
  static const _ifComposito = 'org.shadowblip.Input.CompositeDevice';

  /// I pad virtuali che si possono scegliere, nell'ordine della pagina. Sono
  /// gli identificativi di InputPlumber (`composite_device_v1.json`).
  static const tipi = ['xbox-series', 'xbox-elite', 'xb360', 'ds5'];
  static const tipoPredefinito = 'xbox-series';

  static const preset = ['xbox', 'playstation', 'personalizzato'];

  /// I tasti che si possono rimappare: quelli digitali, coi nomi di
  /// InputPlumber (`Gamepad:Button:…`). I grilletti no: sono assi, e un asse
  /// mandato su un tasto è un'altra cosa da un tasto scambiato.
  static const tasti = [
    'South', 'East', 'West', 'North', 'LeftBumper', 'RightBumper',
    'LeftStick', 'RightStick', 'Select', 'Start', 'Guide',
    'DPadUp', 'DPadDown', 'DPadLeft', 'DPadRight',
  ];

  /// Blu come una PlayStation appena accesa; bianco quando si gioca.
  static const ledRiposoPredefinito = '#0040ff';
  static const ledGiocoPredefinito = '#ffffff';

  /// Chi tiene aperto un pad senza essere un gioco. `comm` è troncato a
  /// quindici caratteri, ed è con quello che si confronta.
  static const _nonGiochi = {
    'inputplumber', 'steam', 'steamwebhelper', 'minervad', 'minerva-wayland',
    'Xwayland', 'qs', 'systemd', 'systemd-logind', 'systemd-udevd', 'udevadm',
    'upowerd', 'bluetoothd', 'pipewire', 'wireplumber', 'gamescope',
    'kwin_wayland', 'plasmashell', 'cosmic-comp', 'kded6',
  };

  /// Le impostazioni si leggono ogni volta, non si copiano: così un cambio
  /// dalla pagina vale al giro dopo senza un secondo posto da tenere allineato.
  final bool Function() automatico;
  final String Function() tipo;

  /// `input.controllerPad`: per ogni pad (la chiave è il suo indirizzo, o
  /// marca e modello) preset, mappa, «scambia ✕ e ○» e i due colori.
  final Map<String, dynamic> Function() perPad;
  final String radiceSys;
  final String programma;

  final changes = StreamController<Map<String, dynamic>>.broadcast();

  Process? _ascolto;
  Timer? _presto, _riprova, _ronda;
  bool _avviato = false, _chiuso = false, _lavora = false, _ancora = false;
  // Il rifiuto si dice una volta: la ronda riprova ogni trenta secondi.
  bool _rifiutoDetto = false;
  Map<String, dynamic>? _stato;
  String _firma = '';

  /// A quali dispositivi composti si è già dato il tipo, e quale. Si ricorda
  /// qui e non si rilegge da InputPlumber perché `TargetDevices` elenca i
  /// percorsi dei pad virtuali, non il loro tipo. Cambiare il tipo ricrea i
  /// pad virtuali, che fanno scattare udev, che riporta qui: senza questo
  /// ricordo sarebbe un giro senza fine.
  final _tipoDato = <String, String>{};

  /// Lo stesso ricordo per il profilo di tasti dato a ogni composto.
  final _profiloDato = <String, String>{};

  /// Le cartelle dei LED di ogni pad, il colore che gli si è dato, e se si
  /// è potuto scrivere.
  final _ledDi = <String, List<String>>{};
  final _ledDato = <String, String>{};
  final _ledScrivibile = <String, bool>{};

  /// Qualcuno sta giocando con un pad: il colore dei LED dipende da qui.
  bool _inGioco = false;
  Timer? _guardaGioco;

  Future<void> start() async {
    if (_avviato || _chiuso) return;
    _avviato = true;
    _ascolta();
    // ── La ronda ────────────────────────────────────────────────────────
    //
    // udev avvisa quando un pad arriva o se ne va, ma non quando InputPlumber
    // si riavvia: in quel caso `ManageAllDevices` torna spento e nessun
    // evento lo dice. Un giro ogni trenta secondi, e solo se c'è un pad che
    // dovrebbe essere gestito e non lo è.
    _ronda = Timer.periodic(const Duration(seconds: 30), (_) {
      final pad = (_stato?['pad'] as List?) ?? const [];
      if (automatico() && pad.any((p) => p['gestito'] != true)) _subito();
    });
    // ── Chi sta giocando ────────────────────────────────────────────────
    //
    // Nessun evento dice «un programma ha aperto il pad»: si guarda ogni
    // tre secondi, e solo se c'è un pad da colorare.
    _guardaGioco = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_ledDi.isEmpty || _lavora) return;
      final ora = _qualcunoGioca();
      if (ora == _inGioco) return;
      _inGioco = ora;
      _subito();
    });
    await _aggiorna();
  }

  Future<Map<String, dynamic>> status() async {
    if (_stato == null) await _aggiorna();
    return _stato!;
  }

  /// Le impostazioni sono cambiate: si riguarda tutto.
  void applica() {
    if (_avviato && !_chiuso) _subito();
  }

  Future<void> close() async {
    _chiuso = true;
    _presto?.cancel();
    _riprova?.cancel();
    _ronda?.cancel();
    _guardaGioco?.cancel();
    _ascolto?.kill();
    _ascolto = null;
    await changes.close();
  }

  // ── L'ascolto ───────────────────────────────────────────────────────────

  void _ascolta() {
    if (_chiuso) return;
    Process.start('udevadm', ['monitor', '--udev', '--subsystem-match=input'])
        .then((p) {
      if (_chiuso) {
        p.kill();
        return;
      }
      _ascolto = p;
      p.stdout.listen((_) => _subito(), onError: (Object _) {});
      p.stderr.listen((_) {}, onError: (Object _) {});
      p.exitCode.then((_) {
        _ascolto = null;
        if (!_chiuso) {
          _riprova = Timer(const Duration(seconds: 5), _ascolta);
        }
      });
    }, onError: (Object e) {
      print('[MINERVA][CONTROLLER] udevadm non parte: $e');
      if (!_chiuso) _riprova = Timer(const Duration(seconds: 30), _ascolta);
    });
  }

  /// Un pad che si accende manda una decina di eventi in mezzo secondo
  /// (il pad, il touchpad, i sensori di movimento): si aspetta che taccia.
  void _subito() {
    _presto?.cancel();
    _presto = Timer(const Duration(milliseconds: 700), () => _aggiorna());
  }

  // ── Il giro ─────────────────────────────────────────────────────────────

  Future<void> _aggiorna() async {
    if (_lavora) {
      _ancora = true;
      return;
    }
    _lavora = true;
    try {
      do {
        _ancora = false;
        await _unGiro();
      } while (_ancora && !_chiuso);
    } catch (e) {
      print('[MINERVA][CONTROLLER] Giro fallito: $e');
    } finally {
      _lavora = false;
    }
  }

  Future<void> _unGiro() async {
    final pad = await _inventario();
    final installato = File(programma).existsSync();
    final acceso = installato && await Dbus.ceIlServizio(servizio);
    var compositi = acceso ? await _compositi() : <_Composito>[];
    if (acceso && await _decidi(pad, compositi)) {
      compositi = await _compositi();
    }

    for (final p in pad) {
      p['gestito'] =
          compositi.any((c) => c.sorgenti.any((s) => s.endsWith('/${p['id']}')));
      final chiave = p['chiave'] as String;
      final conf = _conf(chiave);
      p.addAll(conf);
      p['led'] = (_ledDi[chiave] ?? const []).isNotEmpty;
      if (p['led'] == true) {
        final colore = (_inGioco ? conf['ledGioco'] : conf['ledRiposo']) as String;
        if (_ledDato[chiave] != colore) {
          _ledScrivibile[chiave] = _colora(_ledDi[chiave]!, colore);
          _ledDato[chiave] = colore;
        }
      }
      p['ledScrivibile'] = _ledScrivibile[chiave] ?? true;
    }
    // Un pad che se ne va si dimentica: riaccendendolo il kernel rimette il
    // suo colore, e il nostro va ridato.
    final presenti = pad.map((p) => p['chiave']).toSet();
    _ledDato.removeWhere((k, _) => !presenti.contains(k));
    _ledDi.removeWhere((k, _) => !presenti.contains(k));
    if (_ledDi.isEmpty) _inGioco = false;

    final stato = <String, dynamic>{
      'motore': !installato ? 'assente' : (acceso ? 'pronto' : 'spento'),
      'automatico': automatico(),
      'tipo': _tipoValido(),
      'tipi': tipi,
      'tasti': tasti,
      'inGioco': _inGioco,
      'pad': pad,
    };
    final firma = '$stato';
    _stato = stato;
    if (firma != _firma && !_chiuso) {
      _firma = firma;
      changes.add(stato);
    }
  }

  String _tipoValido() {
    final t = tipo();
    return tipi.contains(t) ? t : tipoPredefinito;
  }

  /// Le scelte per un pad, con i valori di serie al posto di quelli che
  /// mancano o non hanno senso.
  Map<String, dynamic> _conf(String chiave) {
    final tutti = perPad();
    final c = tutti[chiave] is Map
        ? Map<String, dynamic>.from(tutti[chiave] as Map)
        : <String, dynamic>{};
    final colore = RegExp(r'^#[0-9a-fA-F]{6}$');
    final mappa = <String, String>{};
    if (c['mappa'] is Map) {
      (c['mappa'] as Map).forEach((k, v) {
        if (tasti.contains(k) && tasti.contains(v) && k != v) mappa['$k'] = '$v';
      });
    }
    return {
      'preset': preset.contains(c['preset'])
          ? c['preset']
          : (tipo() == 'ds5' ? 'playstation' : 'xbox'),
      'mappa': mappa,
      'scambiaXO': c['scambiaXO'] == true,
      'ledRiposo': colore.hasMatch('${c['ledRiposo']}')
          ? '${c['ledRiposo']}'.toLowerCase()
          : ledRiposoPredefinito,
      'ledGioco': colore.hasMatch('${c['ledGioco']}')
          ? '${c['ledGioco']}'.toLowerCase()
          : ledGiocoPredefinito,
    };
  }

  /// Il pad virtuale che vedono i giochi, secondo il preset.
  String _tipoPer(Map<String, dynamic> conf) {
    if (conf['preset'] == 'playstation') return 'ds5';
    final t = _tipoValido();
    return t == 'ds5' ? tipoPredefinito : t;
  }

  /// Il profilo di InputPlumber per un pad: un tasto per ogni riga, solo
  /// quelli che non vanno dove andrebbero da soli. Vuoto vuol dire «come di
  /// fabbrica», ed è anche quello che si carica per togliere una mappatura.
  static String profilo(String nome, Map<String, dynamic> conf) {
    final dove = <String, String>{
      if (conf['preset'] == 'personalizzato')
        ...Map<String, String>.from(conf['mappa'] as Map),
    };
    String verso(String t) => dove[t] ?? t;
    final fuori = <String, String>{for (final t in tasti) t: verso(t)};
    if (conf['scambiaXO'] == true) {
      fuori['South'] = verso('East');
      fuori['East'] = verso('South');
    }
    final righe = StringBuffer()
      ..writeln('version: 1')
      ..writeln('kind: DeviceProfile')
      ..writeln('name: "Liquid DE — ${nome.replaceAll('"', '')}"');
    final cambiati = fuori.entries.where((e) => e.key != e.value).toList();
    if (cambiati.isEmpty) {
      righe.writeln('mapping: []');
      return righe.toString();
    }
    righe.writeln('mapping:');
    for (final e in cambiati) {
      righe
        ..writeln('  - name: ${e.key}')
        ..writeln('    source_event:')
        ..writeln('      gamepad:')
        ..writeln('        button: ${e.key}')
        ..writeln('    target_events:')
        ..writeln('      - gamepad:')
        ..writeln('          button: ${e.value}');
    }
    return righe.toString();
  }

  /// Fa quello che le impostazioni chiedono. Vero se ha cambiato qualcosa,
  /// e quindi i dispositivi composti vanno riletti.
  Future<bool> _decidi(
      List<Map<String, dynamic>> pad, List<_Composito> compositi) async {
    final vuole = automatico();
    final tutti = await Dbus.proprieta(
        servizio, _gestore, _ifGestore, 'ManageAllDevices');
    var cambiato = false;

    if (vuole && pad.isNotEmpty && tutti != true) {
      if (await Dbus.scrivi(servizio, _gestore, _ifGestore,
          'ManageAllDevices', 'b', 'true')) {
        print('[MINERVA][CONTROLLER] InputPlumber gestisce ora i pad');
        _rifiutoDetto = false;
        cambiato = true;
      } else if (!_rifiutoDetto) {
        _rifiutoDetto = true;
        print('[MINERVA][CONTROLLER] InputPlumber ha rifiutato '
            'ManageAllDevices (l\'utente è nel gruppo wheel?)');
      }
    } else if (!vuole && tutti == true) {
      // Spento dalla pagina: i pad tornano grezzi, come prima.
      await Dbus.scrivi(servizio, _gestore, _ifGestore, 'ManageAllDevices',
          'b', 'false');
      _tipoDato.clear();
      return true;
    }
    if (!vuole) return cambiato;

    // ── Il tipo del pad virtuale, e i suoi tasti ──────────────────────────
    //
    // Solo ai composti che contengono un pad che conosciamo: il pad interno
    // di una console portatile ha la sua configurazione, e non è nostro.
    final vivi = <String>{};
    for (final c in compositi) {
      vivi.add(c.percorso);
      Map<String, dynamic>? suo;
      for (final p in pad) {
        if (c.sorgenti.any((s) => s.endsWith('/${p['id']}'))) suo = p;
      }
      if (suo == null) continue;
      final conf = _conf(suo['chiave'] as String);
      final voluto = _tipoPer(conf);
      if (_tipoDato[c.percorso] != voluto) {
        final ok = await Dbus.chiama(servizio, c.percorso, _ifComposito,
            'SetTargetDevices',
            firma: 'as', argomenti: ['3', voluto, 'mouse', 'keyboard']);
        if (ok != null) {
          _tipoDato[c.percorso] = voluto;
          cambiato = true;
          print('[MINERVA][CONTROLLER] «${c.nome}» ora è un pad $voluto');
        }
      }
      if (await _filtraSensori(c, suo)) cambiato = true;
      final yaml = profilo('${suo['nome']}', conf);
      if (_profiloDato[c.percorso] != yaml) {
        final ok = await Dbus.chiama(servizio, c.percorso, _ifComposito,
            'LoadProfileFromYaml',
            firma: 's', argomenti: [yaml]);
        if (ok != null) {
          _profiloDato[c.percorso] = yaml;
          print('[MINERVA][CONTROLLER] «${c.nome}»: tasti aggiornati');
        } else {
          print('[MINERVA][CONTROLLER] «${c.nome}»: InputPlumber ha rifiutato '
              'il profilo dei tasti');
        }
      }
    }
    // I composti che non ci sono più si dimenticano: lo stesso percorso può
    // tornare con un altro pad dentro.
    _tipoDato.removeWhere((k, _) => !vivi.contains(k));
    _profiloDato.removeWhere((k, _) => !vivi.contains(k));
    return cambiato;
  }

  // ── Le levette vengono solo dalle levette ───────────────────────────────
  //
  // 4 ottobre 2026, GTA V: il personaggio camminava da solo all'indietro e
  // la levetta destra non muoveva la visuale. Misurato sul pad virtuale con
  // il DS4 fermo sul tavolo: levetta sinistra Y = 8356 su 32767, grilletti
  // a 133 e 128 su 255 — premuti a metà. InputPlumber (0.81) traduce anche
  // i SENSORI DI MOVIMENTO del pad (`… Motion Sensors`, `event21`) in
  // levette e grilletti: l'accelerometro sente la gravità e la spinge sulla
  // levetta sinistra, il giroscopio copre la destra. Il touchpad fa lo
  // stesso con la levetta sinistra.
  //
  // Regola generale invece di un elenco di nomi: levette e grilletti li
  // può mandare solo il dispositivo PRINCIPALE del pad, quello con il suo
  // `js`. Ogni altra sorgente dello stesso composto li ha filtrati
  // (`FilteredEvents`); i suoi tasti — il clic del touchpad — passano.
  Future<bool> _filtraSensori(_Composito c, Map<String, dynamic> pad) async {
    final filtrabili = await Dbus.proprieta(
        servizio, c.percorso, _ifComposito, 'FilterableEvents');
    if (filtrabili is! Map) return false;
    final principale = 'evdev://${pad['id']}';
    final voluti = <String, List<String>>{};
    filtrabili.forEach((sorgente, eventi) {
      if (sorgente == principale || eventi is! List) return;
      final via = eventi
          .map((e) => '$e')
          .where((e) =>
              e.startsWith('Gamepad:Axis:') || e.startsWith('Gamepad:Trigger:'))
          .toList()
        ..sort();
      if (via.isNotEmpty) voluti['$sorgente'] = via;
    });

    final ora = await Dbus.proprieta(
        servizio, c.percorso, _ifComposito, 'FilteredEvents');
    final attuali = <String, List<String>>{};
    if (ora is Map) {
      ora.forEach((k, v) {
        if (v is List) attuali['$k'] = v.map((e) => '$e').toList()..sort();
      });
    }
    final chiavi = {...voluti.keys, ...attuali.keys};
    final uguali = chiavi.every((k) =>
        (voluti[k] ?? const []).join('|') == (attuali[k] ?? const []).join('|'));
    if (uguali) return false;

    final argomenti = <String>['${voluti.length}'];
    voluti.forEach((sorgente, eventi) {
      argomenti
        ..add(sorgente)
        ..add('${eventi.length}')
        ..addAll(eventi);
    });
    try {
      final r = await eseguiLimitato('busctl', [
        '--system', 'set-property', servizio, c.percorso, _ifComposito,
        'FilteredEvents', 'a{sas}', ...argomenti,
      ], limite: const Duration(seconds: 3));
      if (!r.ok) {
        print('[MINERVA][CONTROLLER] «${c.nome}»: filtro dei sensori '
            'rifiutato: ${r.stderr.trim()}');
        return false;
      }
    } on ProcessException {
      return false;
    }
    print('[MINERVA][CONTROLLER] «${c.nome}»: levette e grilletti solo dal '
        'pad, non dai sensori (${voluti.keys.join(', ')})');
    return false;
  }

  // ── Che pad ci sono ─────────────────────────────────────────────────────
  //
  // Da `/sys/class/input/js*`: joydev crea un `js` solo per ciò che il kernel
  // riconosce come joystick o pad, ed è la domanda giusta senza lanciare un
  // `udevadm info` per ogni dispositivo d'ingresso. I pad VIRTUALI — quelli
  // di InputPlumber, di Steam — stanno in `/devices/virtual/input/` e si
  // saltano: sono il risultato, non la sorgente. Attenzione a non saltare
  // anche i pad Bluetooth: passano da uhid, e stanno in
  // `/devices/virtual/misc/uhid/`.

  Future<List<Map<String, dynamic>>> _inventario() async {
    final fuori = <Map<String, dynamic>>[];
    final radice = Directory(radiceSys);
    if (!radice.existsSync()) return fuori;
    for (final voce in radice.listSync()) {
      final nomeJs = voce.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (!nomeJs.startsWith('js')) continue;
      try {
        final vero = Link('${voce.path}/device').resolveSymbolicLinksSync();
        if (vero.contains('/devices/virtual/input/')) continue;
        final evento = Directory(vero)
            .listSync()
            .map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last)
            .firstWhere((n) => n.startsWith('event'), orElse: () => '');
        if (evento.isEmpty) continue;
        final bus = _leggi('$vero/id/bustype');
        // La chiave che resta: l'indirizzo Bluetooth (o il seriale) se c'è,
        // altrimenti marca, modello e nome — due pad uguali via cavo
        // condividono le scelte, che è il meno peggio.
        final uniq = _leggi('$vero/uniq').toLowerCase();
        final chiave = uniq.isNotEmpty
            ? uniq
            : '${_leggi('$vero/id/vendor')}:${_leggi('$vero/id/product')}'
                ':${_leggi('$vero/name')}';
        _ledDi[chiave] = _led(vero);
        fuori.add({
          'chiave': chiave,
          'id': evento,
          'nome': _leggi('$vero/name'),
          'collegamento': switch (bus) {
            '0005' => 'bluetooth',
            '0003' => 'usb',
            _ => 'altro',
          },
          'batteria': _batteria(vero),
          'gestito': false,
        });
      } catch (_) {
        // Un pad che si stacca mentre lo si legge: al prossimo giro non c'è.
      }
    }
    fuori.sort((a, b) => '${a['id']}'.compareTo('${b['id']}'));
    return fuori;
  }

  /// I LED della barra luminosa, accanto al dispositivo HID come la
  /// batteria. Solo quelli di colore: i cinque LED bianchi del giocatore di
  /// un DualSense non sono una barra luminosa.
  static List<String> _led(String dispositivo) {
    final cartella = Directory('${Directory(dispositivo).parent.parent.path}'
        '/leds');
    if (!cartella.existsSync()) return const [];
    return cartella
        .listSync()
        .map((e) => e.path)
        .where((p) => RegExp(r':(red|green|blue|global)$|rgb').hasMatch(p))
        .toList();
  }

  /// Colora la barra. Falso se il kernel non lascia scrivere — la regola
  /// udev non è installata — e allora la pagina lo dice.
  static bool _colora(List<String> led, String hex) {
    final r = int.parse(hex.substring(1, 3), radix: 16);
    final g = int.parse(hex.substring(3, 5), radix: 16);
    final b = int.parse(hex.substring(5, 7), radix: 16);
    var ok = true;
    void scrivi(String percorso, String valore) {
      try {
        File(percorso).writeAsStringSync(valore);
      } on FileSystemException {
        ok = false;
      }
    }

    for (final d in led) {
      if (d.endsWith(':red')) {
        scrivi('$d/brightness', '$r');
      } else if (d.endsWith(':green')) {
        scrivi('$d/brightness', '$g');
      } else if (d.endsWith(':blue')) {
        scrivi('$d/brightness', '$b');
      } else if (d.endsWith(':global')) {
        scrivi('$d/brightness', '1');
      } else if (File('$d/multi_intensity').existsSync()) {
        scrivi('$d/multi_intensity', '$r $g $b');
        scrivi('$d/brightness', _leggi('$d/max_brightness').isEmpty
            ? '255'
            : _leggi('$d/max_brightness'));
      }
    }
    return ok;
  }

  // ── Chi sta giocando ────────────────────────────────────────────────────
  //
  // I nodi di tutti i pad, veri e virtuali — `js*` e il loro `event*` — e
  // si cerca chi li tiene aperti in `/proc/*/fd`. Dei processi degli altri
  // utenti non si vede niente, ed è giusto: i giochi sono nostri.
  bool _qualcunoGioca() {
    final nodi = <String>{};
    try {
      for (final voce in Directory(radiceSys).listSync()) {
        final nome = voce.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (!nome.startsWith('js')) continue;
        nodi.add('/dev/input/$nome');
        for (final e in Directory('${voce.path}/device').listSync()) {
          final n = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
          if (n.startsWith('event')) nodi.add('/dev/input/$n');
        }
      }
    } catch (_) {
      return false;
    }
    if (nodi.isEmpty) return false;
    final mio = '$pid';
    for (final p in Directory('/proc').listSync(followLinks: false)) {
      final numero = p.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (numero == mio || int.tryParse(numero) == null) continue;
      final List<FileSystemEntity> fd;
      try {
        fd = Directory('${p.path}/fd').listSync(followLinks: false);
      } catch (_) {
        continue;
      }
      for (final f in fd) {
        String dove;
        try {
          dove = Link(f.path).targetSync();
        } catch (_) {
          continue;
        }
        if (!nodi.contains(dove)) continue;
        if (!_nonGiochi.contains(_leggi('${p.path}/comm'))) return true;
        break;
      }
    }
    return false;
  }

  /// La batteria sta accanto al dispositivo HID, due piani sopra quello di
  /// input: `…/0005:054C:09CC.0008/power_supply/ps-controller-battery-…`.
  static int? _batteria(String dispositivo) {
    final cartella = Directory('${Directory(dispositivo).parent.parent.path}'
        '/power_supply');
    if (!cartella.existsSync()) return null;
    for (final b in cartella.listSync()) {
      final v = int.tryParse(_leggi('${b.path}/capacity'));
      if (v != null) return v;
    }
    return null;
  }

  static String _leggi(String percorso) {
    try {
      return File(percorso).readAsStringSync().trim();
    } catch (_) {
      return '';
    }
  }

  // ── I dispositivi composti di InputPlumber ──────────────────────────────

  Future<List<_Composito>> _compositi() async {
    final UscitaLimitata r;
    try {
      r = await eseguiLimitato(
          'busctl', ['--system', '--list', 'tree', servizio],
          limite: const Duration(seconds: 3));
    } on ProcessException {
      return const [];
    }
    if (!r.ok) return const [];
    final fuori = <_Composito>[];
    final composto = RegExp(r'/CompositeDevice\d+$');
    for (final riga in r.stdout.split('\n')) {
      final percorso = riga.trim();
      if (!composto.hasMatch(percorso)) continue;
      final nome = await Dbus.proprieta(
          servizio, percorso, _ifComposito, 'Name');
      final sorgenti = await Dbus.proprieta(
          servizio, percorso, _ifComposito, 'SourceDevicePaths');
      fuori.add(_Composito(
        percorso,
        nome is String ? nome : '',
        sorgenti is List ? sorgenti.map((s) => '$s').toList() : const [],
      ));
    }
    return fuori;
  }
}

class _Composito {
  const _Composito(this.percorso, this.nome, this.sorgenti);
  final String percorso;
  final String nome;
  final List<String> sorgenti;
}
