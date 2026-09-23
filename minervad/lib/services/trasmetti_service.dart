import 'dart:async';
import 'dart:io';

import 'foto/castv2.dart';
import 'foto/dlna.dart';
import 'foto/genere.dart';
import 'foto/servizio_effimero.dart';
import 'foto/servizio_flusso.dart';
import 'schermi_esterni.dart';

/// TrasmettiService — Mandare un file a un televisore, e riprenderselo.
///
/// ── Il filo, non il motore ─────────────────────────────────────────────────
///
/// I due pezzi difficili erano già scritti e provati, e non li usava nessuno:
///
///   · `foto/castv2.dart`        il protocollo Chromecast, a mano, 354 righe
///   · `foto/servizio_effimero.dart`  il servizio HTTP che presta UN file
///
/// Più la scoperta (`schermi_esterni.dart`, che i televisori li trova già col
/// loro nome vero) e il permesso del firewall (`minerva-radice trasmetti-apri`).
/// Quattro pezzi buoni, e in mezzo un buco: nel pannello di controllo la
/// levetta «Trasmetti» aveva il corpo vuoto,
/// `onToggled: function(v) { /* il motore è la tappa dopo */ }`.
///
/// Questo file è il filo. Non aggiunge protocollo: mette in fila le cose nel
/// solo ordine in cui funzionano, e — soprattutto — le disfa tutte anche
/// quando una di loro fallisce a metà.
///
/// ── L'ordine, e perché è quello ────────────────────────────────────────────
///
/// 1. **il firewall**, per primo. Se si aprisse dopo, il televisore avrebbe
///    già provato a scaricare e sarebbe stato respinto: e quel no non torna
///    indietro a nessuno — il lettore ha già detto sì, e resta uno schermo
///    nero. Trovato guardando, il 30 agosto 2026 (vedi il commento in
///    `servizio_effimero.dart`).
/// 2. **il servizio HTTP**, che deve esistere *prima* che il televisore
///    riceva l'indirizzo: un Chromecast va a prendersi il file subito.
/// 3. **il canale col televisore**, e infine il comando `mostra`.
///
/// Chiudere va nell'ordine inverso, e va fatto SEMPRE — anche se il passo 3
/// esplode. Un servizio HTTP con dentro una fotografia di casa, rimasto su
/// perché un `throw` ha saltato la riga che lo spegneva, è precisamente il
/// difetto che `servizio_effimero.dart` è stato scritto per non avere.
///
/// ── Una per volta ──────────────────────────────────────────────────────────
///
/// Se ne trasmette **una sola alla volta**, e chiederne un'altra ferma la
/// prima. Non è una limitazione tecnica: due servizi effimeri aperti insieme
/// vogliono due porte, e il firewall ne apre una — la seconda trasmissione
/// finirebbe nello schermo nero silenzioso di prima, che è il modo peggiore
/// di fallire.
class TrasmettiService {
  TrasmettiService({
    SchermiEsterni? schermi,
    this.permesso,
    String? comandoSpecchio,
  })  : _schermi = schermi ?? SchermiEsterni(),
        comandoSpecchio = comandoSpecchio ??
            Platform.environment['MINERVA_SPECCHIO'] ??
            'minerva-specchio';

  /// La conduttura che comprime lo schermo (`scripts/minerva-specchio`).
  ///
  /// Si può sostituire, e serve a una cosa sola: **provare che quando la
  /// conduttura fallisce non resta niente in piedi**. Quella prova ha bisogno
  /// di una conduttura che fallisca a comando, e una macchina senza schermo
  /// non ne ha una.
  final String comandoSpecchio;

  final SchermiEsterni _schermi;

  /// Chi apre e chiude la porta del firewall. È una funzione e non il servizio
  /// intero perché quel servizio chiama `pkexec`, e le prove non devono far
  /// comparire una finestra della password sullo schermo di chi le lancia.
  final Future<Map<String, dynamic>> Function(String, List<String>)? permesso;

  ServizioEffimero? _presta;
  ServizioFlusso? _flusso;
  Process? _conduttura;
  CastV2? _canale;
  Dlna? _dlna;
  Timer? _battito;
  bool _specchio = false;

  /// Vero se siamo stati NOI ad aprire la porta del firewall.
  ///
  /// Serve a non chiuderla quando non l'avevamo aperta. Sembra pedanteria e
  /// non lo è: `manda()` comincia con un `ferma()` — una trasmissione per
  /// volta — e senza questo interruttore ogni trasmissione partiva con una
  /// chiamata a `pkexec` per chiudere una porta che non era aperta. Cioè una
  /// finestra della password in più, ogni volta, per non fare niente.
  /// Trovato dalla prova, il 3 settembre 2026.
  bool _portaAperta = false;

  /// Il televisore a cui stiamo trasmettendo adesso, se c'è.
  SchermoEsterno? _verso;
  String _fileInCorso = '';

  bool get inCorso => _canale != null || _dlna != null;
  String get versoChi => _verso?.nome ?? '';
  String get fileCorrente => _fileInCorso;

  /// Vero se quello che sta andando in onda è lo SCHERMO, non un file.
  bool get specchio => _specchio;

  Map<String, dynamic> get stato => {
        'inCorso': inCorso,
        'verso': versoChi,
        'file': _fileInCorso,
        'specchio': _specchio,
      };

  /// I televisori che si vedono adesso.
  Future<List<SchermoEsterno>> cerca() => _schermi.cerca();

  /// Manda `file` al televisore `verso`.
  ///
  /// Torna `{'ok': true, ...}` oppure `{'ok': false, 'error': '…'}`: chi
  /// chiama è il bus, e il bus non deve poter esplodere per una rete che non
  /// risponde.
  Future<Map<String, dynamic>> manda({
    required File file,
    required SchermoEsterno verso,
    String tipo = 'image/jpeg',
    String titolo = '',
  }) async {
    if (!await file.exists()) {
      return {'ok': false, 'error': 'Il file non c\'è: ${file.path}'};
    }
    if (verso.modo != 'cast' && verso.modo != 'dlna') {
      // Resta AirPlay, che su un Samsung vuole un accoppiamento in stile
      // HomeKit. Dirlo è meglio che provarci e fallire in un modo che sembra
      // un guasto della rete.
      return {
        'ok': false,
        'error': '«${verso.nome}» parla ${verso.modo}, e Minerva sa parlare '
            'Chromecast e DLNA. Non è un guasto: è una cosa che non c\'è '
            'ancora.',
      };
    }

    // ── Il rifiuto che arriva PRIMA, e dice di chi è la colpa ──────────
    //
    // Il modo in cui un Chromecast rifiuta un formato che non conosce è
    // **muto**: accetta il comando, risponde «va bene», e poi resta nero. Chi
    // guarda conclude che Minerva è rotta, e va a cercare un difetto che non
    // c'è.
    //
    // Vale solo per i Chromecast: il controllo è sul lettore predefinito, e
    // un televisore DLNA ha il suo, spesso più capace (un Samsung gli MKV li
    // legge). Chiedere a un DLNA di rispettare i limiti di un Chromecast
    // vorrebbe dire rifiutare cose che funzionano.
    if (verso.modo == 'cast') {
      final no = SaLeggere.perche(tipo, verso.nome);
      if (no != null) return {'ok': false, 'error': no};
    }

    // Una sola alla volta: la seconda ferma la prima invece di accodarsi.
    await ferma();

    try {
      // 1. Il firewall PRIMA di tutto. Se fallisce non ci si ferma: su una
      //    macchina senza firewall la chiamata non ha niente da fare, e
      //    rifiutare la trasmissione per questo sarebbe assurdo.
      if (permesso != null) {
        await permesso!.call('trasmetti-apri', const []);
        _portaAperta = true;
      }

      // 2. Il servizio che presta il file. Nasce con la sua sveglia: anche se
      //    tutto il resto sparisce, dopo dieci minuti si spegne da solo.
      final s = ServizioEffimero(file: file, tipo: tipo);
      final indirizzo = await s.apri(versoIl: verso.indirizzo);
      _presta = s;

      // 3. Il televisore, nella lingua che parla.
      String risposta;
      if (verso.modo == 'dlna') {
        // ── DLNA non tiene nessun canale aperto ────────────────────────
        //
        // Due POST e via: `SetAVTransportURI` e `Play`. Niente TLS, niente
        // battito, niente presa da tenere viva — è un protocollo del 2004 e
        // si vede, in bene. Quello che resta aperto è solo il nostro servizio
        // HTTP, finché il televisore non ha finito di scaricare.
        final d = verso.descrizione.isNotEmpty
            ? Dlna(descrizione: verso.descrizione)
            : await Dlna.interroga(verso.indirizzo);
        if (d == null) {
          throw StateError('«${verso.nome}» non espone più un renderer DLNA: '
              'può essersi spento.');
        }
        _dlna = d;
        await d.mostra(
          indirizzoFoto: indirizzo,
          tipo: tipo,
          titolo: titolo.isEmpty ? _nomeDi(file) : titolo,
        );
        risposta = 'DLNA';
      } else {
        final c = CastV2(indirizzo: verso.indirizzo, porta: verso.porta);
        await c.apri();
        _canale = c;
        final r = await c.mostra(
          indirizzoFoto: indirizzo,
          tipo: tipo,
          titolo: titolo.isEmpty ? _nomeDi(file) : titolo,
        );
        // Il battito tiene vivo il canale: senza, il televisore lo chiude dopo
        // una decina di secondi e la fotografia sparisce da sola.
        _battito = Timer.periodic(const Duration(seconds: 5), (_) {
          if (_canale == null) return;
          _canale!.battito();
        });
        risposta = '${r['type']}';
      }

      _verso = verso;
      _fileInCorso = file.path;
      return {'ok': true, 'verso': verso.nome, 'risposta': risposta};
    } catch (e) {
      // Qualunque cosa sia andata storta, si disfa TUTTO: il servizio HTTP
      // rimasto aperto è il difetto peggiore che questo file possa avere.
      await ferma();
      return {'ok': false, 'error': _leggibile(e, verso)};
    }
  }

  /// Manda al televisore **lo schermo**, dal vivo.
  ///
  /// ── Perché sta qui dentro e non in un servizio suo ────────────────────
  ///
  /// Perché non può convivere con la trasmissione di un file: stessa porta
  /// (8010), stesso permesso del firewall, stesso canale col televisore. Due
  /// servizi separati avrebbero potuto partire insieme, e il secondo sarebbe
  /// finito nello schermo nero silenzioso che questo file esiste per evitare.
  /// Qui «una per volta» è già garantito da `ferma()`.
  ///
  /// ── I tre secondi, detti prima ────────────────────────────────────────
  ///
  /// La strada è: cattura → H.264 → **HLS** → il televisore se lo viene a
  /// prendere. HLS manda pezzetti da un secondo, e un lettore ne vuole
  /// qualcuno in mano prima di cominciare: sono circa **tre secondi** fra
  /// quello che fai e quello che si vede.
  ///
  /// Non è un difetto da riparare: è come è fatto il protocollo. Per guardare
  /// un film, delle foto, una presentazione va benissimo. Per *usare* il
  /// computer sullo schermo grande no, e Minerva lo deve dire invece di
  /// lasciarlo scoprire. Il rispecchiamento a bassa latenza dei Chromecast è
  /// un protocollo chiuso: non lo implementa nessun ambiente desktop, KDE
  /// compreso.
  Future<Map<String, dynamic>> specchia({
    required SchermoEsterno verso,
    String schermo = '',
    int fps = 30,
    bool cursore = true,
    bool muto = false,
  }) async {
    if (verso.modo != 'cast' && verso.modo != 'dlna') {
      return {
        'ok': false,
        'error': '«${verso.nome}» parla ${verso.modo}, e Minerva sa parlare '
            'Chromecast e DLNA.',
      };
    }

    await ferma();

    final cartella = Directory(
        '${Platform.environment['XDG_RUNTIME_DIR'] ?? '/tmp'}'
        '/minerva-specchio');

    try {
      if (permesso != null) {
        await permesso!.call('trasmetti-apri', const []);
        _portaAperta = true;
      }

      final opzioni = <String>[
        if (schermo.isNotEmpty) ...['--schermo', schermo],
        '--fps', '$fps',
        if (!cursore) '--senza-cursore',
        if (muto) '--muto',
      ];

      // ── Due strade, e la scelta è del televisore ──────────────────────
      //
      // Un **Chromecast** vuole una playlist HLS: riceve l'indirizzo di una
      // lista e va a prendersi i pezzi. Un apparecchio **DLNA** no — un
      // Samsung un `.m3u8` non sa leggerlo, e il modo in cui lo dice è non
      // dire niente. A lui si dà un indirizzo che, aperto, comincia a versare
      // MPEG-TS.
      //
      // La seconda strada è anche migliore dove si può usare: uno o due
      // secondi di ritardo invece di tre, e **niente scritto su disco**.
      ServizioFlusso f;
      if (verso.modo == 'dlna') {
        // Un controllo prima, perché il flusso parte solo quando il
        // televisore apre l'indirizzo: senza, un ffmpeg mancante si
        // scoprirebbe come uno schermo nero e nient'altro.
        final prova = await Process.run(comandoSpecchio, ['schermi'])
            .timeout(const Duration(seconds: 20));
        if (prova.exitCode != 0) {
          throw StateError(
              (prova.stderr as String).trim().split('\n').first.isEmpty
                  ? 'la cattura dello schermo non risponde'
                  : (prova.stderr as String).trim().split('\n').first);
        }
        f = ServizioFlusso(
          cartella: cartella,
          diretto: true,
          comando: comandoSpecchio,
          argomenti: opzioni,
        );
      } else {
        // 1. La conduttura. Non le si parla: si guarda la cartella. Un
        //    processo che scrive file è più facile da provare di un processo
        //    con cui si conversa, e se muore la cartella smette di crescere —
        //    che è un segnale più affidabile di un codice di uscita.
        _conduttura = await Process.start(
            comandoSpecchio, ['avvia', cartella.path, ...opzioni]);
        // Gli errori della conduttura non si buttano: senza, «non parte» non
        // ha nessuna spiegazione. Vedi «Rumore nei registri» — si toglie la
        // ripetizione, mai l'informazione.
        final lamentele = StringBuffer();
        _conduttura!.stderr.transform(const SystemEncoding().decoder).listen(
            lamentele.write, onError: (_) {});

        // 2. Si aspetta che ci sia qualcosa da guardare. Dare al televisore
        //    una lista vuota vuol dire che smette di provarci e resta nero.
        final pronta = await _attendiLaLista(cartella, _conduttura!);
        if (!pronta) {
          final detto = lamentele.toString().trim();
          throw StateError(detto.isEmpty
              ? 'la compressione non è partita: manca ffmpeg, o il '
                  'compositore non risponde a wlr-screencopy'
              : detto.split('\n').first);
        }
        f = ServizioFlusso(cartella: cartella);
      }

      // 3. Il servizio che presta il flusso.
      final indirizzo = await f.apri(versoIl: verso.indirizzo);
      _flusso = f;

      // 4. Il televisore.
      final tipo = f.tipo;
      final titolo = 'Schermo di Minerva';
      String risposta;
      if (verso.modo == 'dlna') {
        final d = verso.descrizione.isNotEmpty
            ? Dlna(descrizione: verso.descrizione)
            : await Dlna.interroga(verso.indirizzo);
        if (d == null) {
          throw StateError('«${verso.nome}» non espone più un renderer DLNA: '
              'può essersi spento, o essere in attesa.');
        }
        _dlna = d;
        await d.mostra(indirizzoFoto: indirizzo, tipo: tipo, titolo: titolo);
        risposta = 'DLNA';
      } else {
        final c = CastV2(indirizzo: verso.indirizzo, porta: verso.porta);
        await c.apri();
        _canale = c;
        final r = await c.mostra(
          indirizzoFoto: indirizzo,
          tipo: tipo,
          titolo: titolo,
        );
        _battito = Timer.periodic(const Duration(seconds: 5), (_) {
          if (_canale == null) return;
          _canale!.battito();
        });
        risposta = '${r['type']}';
      }

      _verso = verso;
      _specchio = true;
      _fileInCorso = '';
      return {'ok': true, 'verso': verso.nome, 'risposta': risposta};
    } catch (e) {
      await ferma();
      return {'ok': false, 'error': _leggibile(e, verso)};
    }
  }

  /// Aspetta che la lista HLS abbia almeno due segmenti veri.
  ///
  /// «Il file esiste» non basta: ffmpeg la crea vuota e la riempie dopo, e un
  /// televisore che riceve una lista vuota smette di provarci e resta nero —
  /// senza errori da nessuna parte, che è la famiglia di guasti peggiore.
  /// Si conta `#EXTINF`, che è una riga per segmento.
  static Future<bool> _attendiLaLista(Directory dove, Process conduttura) async {
    final lista = File('${dove.path}/schermo.m3u8');
    var morta = false;
    unawaited(conduttura.exitCode.then((_) => morta = true));
    // Venti secondi: la GPU si sveglia, ffmpeg apre il dispositivo, il primo
    // segmento dura un secondo. Su questa macchina il primo arriva in circa
    // due secondi; venti è il margine per una macchina lenta, e si paga solo
    // quando qualcosa non va.
    for (var i = 0; i < 100; i++) {
      if (morta) return false;
      if (await lista.exists()) {
        final testo = await lista.readAsString();
        if ('#EXTINF'.allMatches(testo).length >= 2) return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  /// Ferma la trasmissione e rimette tutto com'era. Si può chiamare sempre,
  /// anche quando non sta trasmettendo niente.
  Future<void> ferma() async {
    _battito?.cancel();
    _battito = null;

    final c = _canale;
    _canale = null;
    if (c != null) {
      // Un televisore che non risponde più non deve impedire di chiudere il
      // resto: il canale si abbandona, il servizio HTTP no.
      try {
        await c.chiudi().timeout(const Duration(seconds: 3));
      } catch (_) {}
    }

    final d = _dlna;
    _dlna = null;
    if (d != null) {
      try {
        await d.ferma().timeout(const Duration(seconds: 4));
      } catch (_) {}
      d.chiudi();
    }

    final s = _presta;
    _presta = null;
    if (s != null) {
      try {
        await s.chiudi();
      } catch (_) {}
    }

    // Prima si smette di prestare, poi si smette di produrre: al contrario,
    // il televisore chiederebbe segmenti che non esistono più e mostrerebbe
    // un errore invece di fermarsi.
    final fl = _flusso;
    _flusso = null;
    if (fl != null) {
      try {
        await fl.chiudi();
      } catch (_) {}
    }

    final c2 = _conduttura;
    _conduttura = null;
    if (c2 != null) {
      // SIGTERM e non SIGKILL: lo script ha un `trap` che ferma cattura e
      // ffmpeg e cancella i segmenti — cioè i fotogrammi dello schermo. Con
      // SIGKILL quel `trap` non gira, e resterebbero sul disco (in RAM) due
      // processi vivi e i pezzi del tuo schermo.
      c2.kill(ProcessSignal.sigterm);
      try {
        await c2.exitCode.timeout(const Duration(seconds: 6));
      } on TimeoutException {
        c2.kill(ProcessSignal.sigkill);
      }
    }

    _specchio = false;
    _verso = null;
    _fileInCorso = '';

    if (_portaAperta) {
      _portaAperta = false;
      try {
        await permesso?.call('trasmetti-chiudi', const []);
      } catch (_) {}
    }
  }

  static String _nomeDi(File f) {
    final p = f.uri.pathSegments;
    return p.isEmpty ? f.path : p.last;
  }

  /// Da un'eccezione a una frase che dice cosa fare.
  ///
  /// Non è cosmesi: gli errori di questa catena arrivano dalla rete di casa, e
  /// «SocketException: Connection refused» non dice a nessuno che il
  /// televisore si è spento.
  static String _leggibile(Object e, SchermoEsterno verso) {
    if (e is TimeoutException) {
      // Non «è acceso?»: quasi sempre lo è, e stava accendendo il lettore. Un
      // messaggio che manda a controllare una cosa che è a posto fa perdere
      // più tempo del guasto. Vedi la pazienza di `mostra` in `castv2.dart`.
      return '«${verso.nome}» ci sta mettendo troppo. Se si era appena '
          'acceso, riprova fra qualche secondo: la prima volta deve caricare '
          'il lettore.';
    }
    if (e is SocketException) {
      return 'Non riesco a raggiungere «${verso.nome}» (${verso.indirizzo}). '
          'Può essersi spento, o aver cambiato indirizzo.';
    }
    if (e is HandshakeException) {
      return '«${verso.nome}» ha rifiutato il collegamento sicuro.';
    }
    return 'Non è andata: $e';
  }
}
