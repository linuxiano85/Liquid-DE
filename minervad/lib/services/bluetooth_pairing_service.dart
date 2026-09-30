import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Accoppiare un dispositivo che vuole CONFRONTARE UN CODICE.
///
/// ── Perché esiste, e perché il telefono non si accoppiava ─────────────────
///
/// Giacomo, 18 agosto 2026: «non riesco ad accoppiare il mio Redmi Note 12
/// Pro Plus 5G». Il difetto era già scritto, e da un mese: la pagina delle
/// Impostazioni registra `agent NoInputNoOutput`, e accanto c'era la nota
/// «per i dispositivi che vogliono confrontare un codice a video servirà un
/// agente vero — non è ancora stato fatto».
///
/// Ma la causa vera è un'altra, e si scopre solo provando: **quella riga non
/// faceva niente.** `bluetoothctl` registra un agente da solo all'avvio, e a
/// `agent NoInputNoOutput` rispondeva «Agent is already registered» — la
/// capacità richiesta veniva buttata via. L'agente attivo era quello di
/// fabbrica, che è già `KeyboardDisplay`, cioè quello giusto.
///
/// Il difetto era che **nessuno rispondeva.** I comandi venivano versati tutti
/// insieme dentro `bluetoothctl` con delle pause in mezzo:
///
///     pair MAC   ·   (pausa 9s)   ·   trust MAC   ·   connect MAC
///
/// Quando BlueZ chiedeva «Confirm passkey 418322 (yes/no)?», la risposta che
/// gli arrivava era `trust MAC`. Non è «yes», quindi l'accoppiamento restava
/// lì fino a scadere. Con delle cuffie non succedeva mai — non chiedono
/// niente — e per questo il difetto è rimasto in piedi un mese.
///
/// Quindi la capacità la si impone lo stesso (togliendo prima quella di
/// fabbrica, vedi `accoppia`), ma la cosa che ripara è tenere la sessione
/// aperta e RISPONDERE.
///
/// ── Perché `bluetoothctl` e non un agente D-Bus vero ──────────────────────
///
/// Un agente vero vuol dire ESPORRE un oggetto su D-Bus (`org.bluez.Agent1`),
/// e `busctl` sa solo chiamare, non servire. Servirebbe una libreria D-Bus, e
/// il demone ha zero dipendenze per scelta — è ciò che lo tiene a 22 MB.
///
/// `bluetoothctl` un agente vero lo registra già, e con la capacità che gli
/// diciamo noi. Tenendo la sessione APERTA e parlandoci — leggendo le domande,
/// scrivendo le risposte — si ottiene lo stesso risultato senza aggiungere
/// niente al demone. La capacità che chiediamo è `KeyboardDisplay`, che è la
/// verità su questa macchina: uno schermo per leggere il codice e una tastiera
/// per confermarlo.
///
/// ── La trappola che costa più tempo di tutte ──────────────────────────────
///
/// **Le domande di `bluetoothctl` NON finiscono con un a capo.** La riga è
/// `[agent] Confirm passkey 123456 (yes/no):` e poi il programma si ferma ad
/// aspettare. Chi legge l'uscita riga per riga — `transform(LineSplitter())` —
/// resta a aspettare per sempre una riga che non arriverà, e l'accoppiamento
/// scade mentre la domanda era già lì da un minuto.
///
/// Quindi si legge a PEZZI e si guarda dentro quello che si è accumulato.
class BluetoothPairingService {
  /// Il programma da lanciare. Si cambia solo nelle prove, con un
  /// `bluetoothctl` finto che risponde come quello vero.
  final String programma;

  BluetoothPairingService({this.programma = 'bluetoothctl'});

  Process? _sessione;
  StreamSubscription<String>? _ascolto;
  StreamSubscription<String>? _ascoltoErrori;
  Timer? _scadenza;

  // ── Tre difetti dello stesso giro (30 settembre 2026) ───────────────────
  //
  // Trovati in revisione con un `bluetoothctl` finto, e tutti e tre dopo il
  // «Pairing successful»:
  //
  //  1. `connect` NON partiva mai. `_scrivi` faceva `write` + `flush` senza
  //     aspettare il `flush`, e il `write` successivo — `connect` subito
  //     dopo `trust` — sollevava «StreamSink is bound to a stream»,
  //     inghiottito dal `catch`. La finestra diceva «Accoppiato e collegato»
  //     e il dispositivo restava scollegato.
  //  2. L'esito scattava a OGNI pezzo di uscita successivo, perché il testo
  //     accumulato conteneva ancora «Pairing successful»: undici «fatto»,
  //     undici `trust`, undici timer di chiusura.
  //  3. L'ascolto di stderr non si cancellava mai, e quei timer non sapevano
  //     di quale sessione fossero: uno rimasto indietro poteva chiudere
  //     l'accoppiamento successivo.
  //
  // Da qui la fila delle scritture, l'esito una volta sola, e il numero
  // della sessione.

  /// L'ultima scrittura messa in fila: ognuna aspetta il `flush` della
  /// precedente.
  Future<void> _fila = Future<void>.value();

  /// Vero quando questa sessione ha già avuto il suo esito.
  bool _finito = false;

  /// Cresce a ogni accoppiamento: i timer si ricordano il loro, e se nel
  /// frattempo ne è cominciato un altro non toccano niente.
  int _numeroSessione = 0;

  /// Quello che `bluetoothctl` ha detto finora e che non è ancora stato
  /// riconosciuto. Si azzera a ogni domanda riconosciuta, altrimenti la stessa
  /// domanda verrebbe letta due volte.
  String _accumulato = '';

  String _mac = '';

  /// L'ultima domanda posta a chi guarda, per non riproporla identica.
  String _domandaInCorso = '';

  final StreamController<Map<String, dynamic>> _eventi =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Quello che succede durante l'accoppiamento, mentre succede.
  Stream<Map<String, dynamic>> get eventi => _eventi.stream;

  bool get inCorso => _sessione != null;

  /// Quanto si aspetta in tutto. Generoso: fra tirare fuori il telefono,
  /// sbloccarlo e leggere il codice passa più di un minuto vero.
  static const Duration _tempoMassimo = Duration(seconds: 120);

  // ── Leggere quello che dice BlueZ ─────────────────────────────────────────

  /// I colori e i comandi di posizionamento del cursore che `bluetoothctl`
  /// infila nella sua uscita. Senza toglierli, `Confirm passkey` non combacia
  /// mai perché in mezzo c'è un `\x1b[0;93m`.
  static final RegExp _colori = RegExp(r'\x1b\[[0-9;?]*[a-zA-Z]');

  static String pulisci(String grezzo) => grezzo
      .replaceAll(_colori, '')
      .replaceAll('\r', '\n');

  /// La domanda che BlueZ sta facendo, se ce n'è una.
  ///
  /// Statica e senza stato apposta: è la parte che si può provare senza un
  /// adattatore Bluetooth, un telefono e una persona che guarda lo schermo.
  static Map<String, dynamic>? leggiDomanda(String uscita) {
    final testo = pulisci(uscita);

    // «Confermi che sul telefono c'è scritto 123456?» — è QUESTA la domanda
    // che il telefono pretende, ed è quella che prima non si sapeva porre.
    final codice = RegExp(r'Confirm passkey (\d{4,6})').firstMatch(testo);
    if (codice != null) {
      return {
        'tipo': 'codice',
        'codice': codice.group(1),
      };
    }

    // Il telefono mostra il codice e lo vuole battuto qui. Capita con
    // apparecchi vecchi; si riconosce per non lasciare la sessione muta.
    final daBattere = RegExp(r'Enter passkey|Enter PIN code').firstMatch(testo);
    if (daBattere != null) {
      return {'tipo': 'pin'};
    }

    // «Accetti l'accoppiamento?» senza nessun codice da confrontare.
    if (testo.contains('Accept pairing')) {
      return {'tipo': 'conferma'};
    }

    // «Gli lasci usare questo servizio?» — arriva DOPO l'accoppiamento, una
    // volta per servizio, e un telefono ne chiede più d'uno. Si risponde di sì
    // da soli: chi ha appena confermato il codice ha già detto che si fida, e
    // una seconda domanda su un numero che non vuol dire niente per nessuno
    // («0000110d-0000-1000-8000-00805f9b34fb») non aggiunge nessuna sicurezza.
    if (testo.contains('Authorize service')) {
      return {'tipo': 'servizio'};
    }

    return null;
  }

  /// Com'è finita, se è finita.
  static Map<String, dynamic>? leggiEsito(String uscita) {
    final testo = pulisci(uscita);

    if (testo.contains('Pairing successful')) {
      return {'ok': true};
    }
    if (testo.contains('AuthenticationCanceled')) {
      return {
        'ok': false,
        'error': 'L\'accoppiamento è stato annullato dall\'altro dispositivo.',
      };
    }
    if (testo.contains('AuthenticationRejected')) {
      return {
        'ok': false,
        'error': 'Il dispositivo ha rifiutato l\'accoppiamento.',
      };
    }
    if (testo.contains('AuthenticationFailed')) {
      return {
        'ok': false,
        'error': 'Il codice non corrispondeva.',
      };
    }
    if (testo.contains('AuthenticationTimeout')) {
      return {
        'ok': false,
        'error': 'Non ha risposto in tempo. Rimettilo in modalità '
            'accoppiamento e riprova.',
      };
    }
    if (testo.contains('AlreadyExists')) {
      // Non è un guasto: è già accoppiato. Dirlo come errore manderebbe a
      // cercare un problema che non c'è.
      return {'ok': true, 'giaAccoppiato': true};
    }
    if (testo.contains('Failed to pair')) {
      return {
        'ok': false,
        'error': 'Non è riuscito. Controlla che sia acceso, vicino e in '
            'modalità accoppiamento.',
      };
    }
    return null;
  }

  // ── Accoppiare ────────────────────────────────────────────────────────────

  /// Apre la sessione e comincia. Torna subito: quello che succede dopo arriva
  /// da `eventi`, perché in mezzo c'è una persona che deve guardare un telefono.
  Future<Map<String, dynamic>> accoppia(String mac) async {
    if (mac.isEmpty) {
      return {'ok': false, 'error': 'Non hai detto quale dispositivo.'};
    }
    if (_sessione != null) {
      return {
        'ok': false,
        'error': 'C\'è già un accoppiamento in corso. Aspetta che finisca.',
      };
    }

    _mac = mac;
    _accumulato = '';
    _domandaInCorso = '';
    _finito = false;
    _fila = Future<void>.value();
    final mia = ++_numeroSessione;

    try {
      // `LC_ALL=C` perché tutto quello che si riconosce qui sotto sono parole
      // inglesi di `bluetoothctl`: con un'altra lingua non combacia più niente
      // e l'accoppiamento risulta fallito mentre sta funzionando. Trappola già
      // presa in questo progetto.
      _sessione = await Process.start(
        programma,
        const [],
        environment: const {'LC_ALL': 'C'},
      );
    } catch (e) {
      _sessione = null;
      return {'ok': false, 'error': 'Non trovo «bluetoothctl».'};
    }

    _ascolto = _sessione!.stdout.transform(utf8.decoder).listen((pezzo) {
      if (mia == _numeroSessione) _arrivato(pezzo);
    }, onError: (_) {}, cancelOnError: false);
    // Anche stderr: `Failed to pair` a volte esce di là. Si tiene la
    // sottoscrizione per poterla chiudere con il resto.
    _ascoltoErrori =
        _sessione!.stderr.transform(utf8.decoder).listen((pezzo) {
      if (mia == _numeroSessione) _arrivato(pezzo);
    }, onError: (_) {}, cancelOnError: false);

    _scadenza = Timer(_tempoMassimo, () {
      if (mia != _numeroSessione || _finito) return;
      _finito = true;
      _annuncia({
        'stato': 'fallito',
        'error': 'Ci ha messo troppo. Rimettilo in modalità accoppiamento e '
            'riprova.',
      });
      _chiudi();
    });

    // ── Perché tre comandi e non uno, e perché con le pause ──────────────
    //
    // `bluetoothctl` registra un agente **da solo all'avvio**. Chiedendogli
    // `agent <capacità>` risponde «Agent is already registered» e la capacità
    // richiesta NON viene applicata — verificato sulla macchina il 19 agosto
    // 2026. Quindi prima si toglie il suo, poi si mette il nostro.
    //
    // E ci vogliono le pause: la registrazione passa da D-Bus, non è
    // istantanea, e `default-agent` mandato subito dopo risponde «No agent is
    // registered» — verificato anche questo.
    //
    // Dopo ogni pausa si guarda se la sessione è ancora questa: annullata nel
    // frattempo, e magari già ricominciata per un altro dispositivo, il
    // `pair` di questo MAC finirebbe dentro la sessione nuova.
    bool ancoraMia() => mia == _numeroSessione && _sessione != null;
    _scrivi('agent off');
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!ancoraMia()) return {'ok': false, 'error': 'Annullato.'};
    _scrivi('agent KeyboardDisplay');
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!ancoraMia()) return {'ok': false, 'error': 'Annullato.'};
    _scrivi('default-agent');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!ancoraMia()) return {'ok': false, 'error': 'Annullato.'};
    _scrivi('pair $mac');

    _annuncia({'stato': 'avviato', 'mac': mac});
    return {'ok': true, 'avviato': true};
  }

  /// La risposta di chi guarda: «sì, il codice è quello» oppure no.
  Future<Map<String, dynamic>> rispondi(bool si) async {
    if (_sessione == null) {
      return {'ok': false, 'error': 'Non c\'è nessun accoppiamento in corso.'};
    }
    _domandaInCorso = '';
    _scrivi(si ? 'yes' : 'no');
    if (!si) {
      _finito = true;
      _annuncia({'stato': 'fallito', 'error': 'Annullato.'});
      _chiudi();
    }
    return {'ok': true};
  }

  /// Chi ha cambiato idea. Si chiude tutto senza lasciare in giro una sessione
  /// che tiene occupato l'adattatore.
  Future<Map<String, dynamic>> annulla() async {
    if (_sessione == null) return {'ok': true};
    _scrivi('cancel-pairing $_mac');
    _finito = true;
    _annuncia({'stato': 'fallito', 'error': 'Annullato.'});
    _chiudi();
    return {'ok': true};
  }

  // ── Il filo che tiene insieme le due cose ─────────────────────────────────

  void _arrivato(String pezzo) {
    _accumulato += pezzo;
    // Non si lascia crescere all'infinito: `bluetoothctl` stampa anche tutto
    // il traffico delle proprietà, e in due minuti diventa parecchio.
    if (_accumulato.length > 8000) {
      _accumulato = _accumulato.substring(_accumulato.length - 4000);
    }

    // Un esito per sessione: quello che `bluetoothctl` stampa dopo — le
    // proprietà che cambiano, l'eco di `trust` e `connect` — non deve farlo
    // scattare di nuovo. Resta una sola domanda a cui rispondere, ed è
    // proprio una di quelle che arrivano DOPO: l'autorizzazione dei servizi.
    if (_finito) {
      if (leggiDomanda(_accumulato)?['tipo'] == 'servizio') {
        _scrivi('yes');
        _accumulato = '';
      }
      return;
    }

    final esito = leggiEsito(_accumulato);
    if (esito != null) {
      _finito = true;
      _accumulato = '';
      if (esito['ok'] == true) {
        // Accoppiato: adesso «fidati» e «connetti», dentro la STESSA sessione.
        // Fuori sarebbero due sessioni senza agente, che è il difetto da cui
        // è cominciata tutta questa storia.
        _scrivi('trust $_mac');
        _scrivi('connect $_mac');
        _annuncia({
          'stato': 'fatto',
          'messaggio': esito['giaAccoppiato'] == true
              ? 'Era già accoppiato. L\'ho collegato.'
              : 'Accoppiato e collegato.',
        });
        // Un istante per lasciar passare `trust` e `connect` prima di chiudere.
        // Solo QUESTA sessione: se nel frattempo ne è cominciata un'altra, il
        // timer non la tocca.
        final mia = _numeroSessione;
        Timer(const Duration(seconds: 4), () {
          if (mia == _numeroSessione) _chiudi();
        });
      } else {
        _annuncia({'stato': 'fallito', 'error': esito['error']});
        _chiudi();
      }
      return;
    }

    final domanda = leggiDomanda(_accumulato);
    if (domanda == null) return;

    // Il servizio si autorizza da soli: vedi il perché in `leggiDomanda`.
    if (domanda['tipo'] == 'servizio') {
      _scrivi('yes');
      _accumulato = '';
      return;
    }

    // Il PIN da battere qui non è supportato: si dice, invece di restare muti
    // finché non scade.
    if (domanda['tipo'] == 'pin') {
      _finito = true;
      _annuncia({
        'stato': 'fallito',
        'error': 'Questo dispositivo vuole che il codice venga battuto sul '
            'computer, e Minerva non sa ancora chiederlo.',
      });
      _chiudi();
      return;
    }

    final chiave = '${domanda['tipo']}:${domanda['codice'] ?? ''}';
    if (chiave == _domandaInCorso) return;
    _domandaInCorso = chiave;
    _accumulato = '';

    _annuncia({
      'stato': 'chiede',
      'tipo': domanda['tipo'],
      'codice': domanda['codice'] ?? '',
    });
  }

  void _scrivi(String comando) {
    final s = _sessione;
    if (s == null) return;
    _mettiInFila(s, comando);
  }

  /// Scrive dopo che la scrittura precedente è arrivata: vedi `_fila`.
  void _mettiInFila(Process s, String comando) {
    _fila = _fila.then((_) async {
      try {
        s.stdin.write('$comando\n');
        await s.stdin.flush();
      } catch (_) {
        // Sessione già chiusa: non è un guasto da raccontare, il chiamante lo
        // scopre dall'evento di esito.
      }
    });
  }

  void _annuncia(Map<String, dynamic> evento) {
    if (!_eventi.isClosed) _eventi.add({...evento, 'mac': _mac});
  }

  void _chiudi() {
    _scadenza?.cancel();
    _scadenza = null;
    _ascolto?.cancel();
    _ascolto = null;
    _ascoltoErrori?.cancel();
    _ascoltoErrori = null;
    final s = _sessione;
    _sessione = null;
    if (s == null) return;
    // In fila anche lui: dopo un `no` o un `cancel-pairing` il `quit` si
    // perdeva allo stesso modo del `connect`.
    _mettiInFila(s, 'quit');
    // E se «quit» non basta, si insiste: una sessione lasciata viva tiene
    // l'agente registrato, e il prossimo accoppiamento trova il posto occupato.
    Timer(const Duration(seconds: 2), () => s.kill());
  }

  Future<void> spegni() async {
    _chiudi();
    await _eventi.close();
  }
}
