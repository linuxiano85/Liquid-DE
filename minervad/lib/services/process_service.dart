import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/event_bus.dart';

import 'processi_umani.dart';

/// ProcessService — Chi sta girando, e quanto costa.
///
/// ── Perché si legge `/proc` e non si lancia `ps` ───────────────────────────
///
/// Perché `ps aux` è un processo che nasce, legge esattamente questi file, li
/// formatta in colonne e muore. Farlo due volte al secondo per tenere aggiornato
/// un elenco vuol dire accendere e spegnere un programma centoventi volte al
/// minuto per leggere dei file che possiamo aprire noi. È la stessa ragione per
/// cui il demone parla al compositore sul suo socket invece di lanciare un
/// programma a ogni domanda.
///
/// ── Come si calcola l'uso della CPU ────────────────────────────────────────
///
/// Non esiste un file che dica «questo processo sta usando il 12%». `/proc/PID/stat`
/// dice quanti TICK di CPU quel processo ha consumato **da quando è nato**. La
/// percentuale è una derivata: si legge due volte a distanza nota e si divide la
/// differenza per il tempo passato.
///
/// Da qui una conseguenza che vale la pena sapere: **la prima lettura non ha una
/// percentuale**. Non è un difetto da nascondere con uno zero — uno zero dice
/// «non sta consumando», che è falso. Si dice `null` e chi disegna mostra un
/// trattino finché non c'è il secondo campione.
///
/// ── Quando si legge ────────────────────────────────────────────────────────
///
/// Solo se qualcuno guarda. Il campionamento parte quando il primo client si
/// iscrive e si ferma quando esce l'ultimo: a monitor chiuso questo servizio non
/// costa un ciclo. È la regola della casa — svegliarsi costa più che chiedere.
class ProcessService {
  ProcessService(this._eventBus);

  final EventBus _eventBus;

  Timer? _timer;
  int _iscritti = 0;

  /// Tick di CPU consumati da ogni processo all'ultima lettura, per calcolare
  /// la differenza alla prossima.
  final Map<int, int> _tickPrecedenti = {};

  /// Tick totali della macchina all'ultima lettura.
  int _tickMacchinaPrecedenti = 0;

  /// Quanti tick al secondo conta il kernel. Su Linux è 100 da sempre, ma
  /// chiederlo costa una volta sola e non si basa su una costante che un
  /// giorno potrebbe non valere.
  int _tickAlSecondo = 100;

  /// Byte letti e scritti in rete all'ultima lettura, per la velocità.
  int _reteGiuPrecedente = 0;
  int _reteSuPrecedente = 0;
  DateTime _ultimaLettura = DateTime.now();

  int get _memoriaPagina => 4096;

  Future<void> init() async {
    try {
      final r = await Process.run('getconf', ['CLK_TCK']);
      final v = int.tryParse((r.stdout as String).trim());
      if (v != null && v > 0) _tickAlSecondo = v;
    } catch (_) {
      // Resta 100: è il valore su ogni Linux che conti.
    }
  }

  // ── Iscrizioni ───────────────────────────────────────────────────────────

  /// Un client ha aperto il monitor. Il campionamento parte al primo.
  void iscrivi() {
    _iscritti++;
    if (_iscritti == 1) {
      // Un primo giro subito, o la finestra resterebbe vuota per due secondi
      // prima di dire qualunque cosa.
      unawaited(_giro());
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _giro());
    }
  }

  // ── E l'iscrizione LEGGERA, per i widget della scrivania ────────────────
  //
  // I widget della scrivania vogliono tre numeri — processore, memoria,
  // temperatura — e li vogliono per tutto il giorno. Farli passare da
  // `iscrivi()` vorrebbe dire leggere `/proc` di OGNI processo del computer
  // ogni due secondi, per sempre: la visura del 7 settembre 2026 ha misurato
  // che col Monitor aperto il demone ha un fermo di **22 millisecondi** nel
  // caso peggiore, ed è tutta la scrivania che si ferma, perché Dart ha un
  // filo solo.
  //
  // `soloMacchina()` non guarda nessun processo: legge `/proc/stat`,
  // `/proc/meminfo`, i contatori della rete e le sonde. Quattro file.
  //
  // Cinque secondi e non due: un widget non è un monitor. Chi vuole vedere il
  // grafico muoversi apre il Monitor, che è lì per quello.
  /// L'ultima lettura di `rc6_residency_ms`. Come i tick della CPU, la
  /// percentuale è una DERIVATA: si calcola fra due letture, e alla prima non
  /// c'è niente da confrontare.
  int _rc6Precedente = 0;

  int _iscrittiMacchina = 0;
  Timer? _timerMacchina;

  void iscriviMacchina() {
    _iscrittiMacchina++;
    if (_iscrittiMacchina == 1) {
      unawaited(_giroMacchina());
      _timerMacchina =
          Timer.periodic(const Duration(seconds: 5), (_) => _giroMacchina());
    }
  }

  void disiscriviMacchina() {
    if (_iscrittiMacchina > 0) _iscrittiMacchina--;
    if (_iscrittiMacchina == 0) {
      _timerMacchina?.cancel();
      _timerMacchina = null;
    }
  }

  Future<void> _giroMacchina() async {
    try {
      _eventBus.publish(
          MinervaEvent(type: 'machine_state', payload: await soloMacchina()));
    } catch (e) {
      print('[MINERVA][PROC][ERRORE] Giro della macchina fallito: $e');
    }
  }

  /// Un client ha chiuso il monitor. All'ultimo si smette di leggere.
  void disiscrivi() {
    if (_iscritti > 0) _iscritti--;
    if (_iscritti == 0) {
      _timer?.cancel();
      _timer = null;
      _tickPrecedenti.clear();
      _tickMacchinaPrecedenti = 0;
    }
  }

  Future<void> _giro() async {
    try {
      final dati = await leggi();
      _eventBus.publish(MinervaEvent(type: 'processes', payload: dati));
    } catch (e) {
      print('[MINERVA][PROC][ERRORE] Giro di lettura fallito: $e');
    }
  }

  // ── La lettura ───────────────────────────────────────────────────────────

  /// Tutto quello che il monitor mostra: i processi e lo stato della macchina.
  Future<Map<String, dynamic>> leggi() async {
    final adesso = DateTime.now();
    final trascorso = adesso.difference(_ultimaLettura).inMicroseconds / 1e6;
    _ultimaLettura = adesso;

    final macchina = await _leggiMacchina(trascorso);
    final processi = await _leggiProcessi();

    // La frase in cima alla finestra. Non una percentuale in più — di quelle
    // ce ne sono già cinque — ma la cosa che si andrebbe a cercare
    // guardandole: CHI.
    final memTot = (macchina['memoriaTotale'] as num?)?.toDouble() ?? 0;
    final memUso = (macchina['memoriaUsata'] as num?)?.toDouble() ?? 0;
    macchina['comeSta'] = comeSta(
      processi,
      (macchina['cpu'] as num?)?.toDouble() ?? 0,
      memTot > 0 ? memUso / memTot * 100 : 0,
    );

    return {
      'macchina': macchina,
      'processi': processi,
    };
  }

  /// Solo lo stato della macchina, senza l'elenco dei processi.
  ///
  /// Esiste per chi vuole tre numeri e non trecento righe: il calendario ne
  /// mostra CPU, memoria e temperatura in una striscia alta venti pixel, e
  /// leggere `/proc` per ogni processo del computer per riempirla sarebbe
  /// diventare il consumo che si sta misurando.
  ///
  /// Aggiorna la stessa contabilità di `leggi()` — l'istante dell'ultima
  /// lettura e i tick precedenti — perché la percentuale di CPU è una
  /// DERIVATA: va calcolata sull'intervallo davvero trascorso dall'ultima
  /// lettura, chiunque l'abbia fatta. Due lettori a ritmi diversi si
  /// accorciano l'intervallo a vicenda, e va bene: le percentuali restano
  /// giuste, cambia solo su quanto tempo sono misurate.
  Future<Map<String, dynamic>> soloMacchina() async {
    final adesso = DateTime.now();
    final trascorso = adesso.difference(_ultimaLettura).inMicroseconds / 1e6;
    _ultimaLettura = adesso;
    return _leggiMacchina(trascorso);
  }

  /// Lo stato della macchina: CPU, memoria, scambio, rete, temperatura, carico.
  Future<Map<String, dynamic>> _leggiMacchina(double trascorso) async {
    final fuori = <String, dynamic>{};

    // ── CPU totale ──────────────────────────────────────────────────────
    //
    // La prima riga di `/proc/stat` sono i tick di tutta la macchina divisi
    // per stato. Il tempo «occupato» è tutto tranne `idle` e `iowait`: un core
    // che aspetta il disco non sta lavorando, e contarlo farebbe salire il
    // grafico quando in realtà non succede niente.
    //
    // ── E la PRIMA volta si legge due volte ──────────────────────────────
    //
    // Un uso della CPU non si legge: si calcola fra due letture. Alla prima
    // chiamata non c'è niente da confrontare, quindi `cpu` non veniva
    // impostato affatto — e chi guardava vedeva «Processore —» accanto a
    // «Memoria 20%» e «Temperatura 57°».
    //
    // Visto il 3 settembre 2026 fotografando il calendario in una sessione
    // annidata. Non era un errore: era la verità («non lo so ancora»), detta
    // però in un modo che sembra un guasto — due numeri e un trattino. E
    // durava tre secondi, cioè il tempo in cui uno guarda.
    //
    // La cura non è inventare un numero: è prendersi il secondo campione
    // subito, centoventi millesimi dopo il primo. Succede UNA volta per
    // sessione del demone, e solo se nessuno aveva ancora chiesto.
    //
    // La strada sbagliata sarebbe stata partire dai tick dall'accensione: si
    // otterrebbe la media dal boot, che è un numero vero e risponde a una
    // domanda che nessuno ha fatto.
    try {
      var righe = await File('/proc/stat').readAsLines();
      if (_tickMacchinaPrecedenti == 0) {
        final primo = righe.firstWhere((r) => r.startsWith('cpu '),
            orElse: () => '');
        final n0 = primo.split(RegExp(r'\s+')).skip(1).map(int.tryParse).toList();
        if (n0.length >= 5) {
          final tot0 = n0.fold<int>(0, (a, b) => a + (b ?? 0));
          _tickMacchinaTotale = tot0;
          _tickMacchinaPrecedenti = tot0 - ((n0[3] ?? 0) + (n0[4] ?? 0));
          await Future<void>.delayed(const Duration(milliseconds: 120));
          righe = await File('/proc/stat').readAsLines();
        }
      }
      final cpu = righe.firstWhere((r) => r.startsWith('cpu '), orElse: () => '');
      if (cpu.isNotEmpty) {
        final n = cpu.split(RegExp(r'\s+')).skip(1).map(int.tryParse).toList();
        if (n.length >= 5) {
          final totale = n.fold<int>(0, (a, b) => a + (b ?? 0));
          final fermo = (n[3] ?? 0) + (n[4] ?? 0);
          final occupato = totale - fermo;

          if (_tickMacchinaPrecedenti > 0) {
            final dTot = totale - _tickMacchinaTotale;
            final dOcc = occupato - _tickMacchinaPrecedenti;
            fuori['cpu'] = dTot > 0 ? (dOcc / dTot * 100).clamp(0, 100) : 0;
          }
          _tickMacchinaPrecedenti = occupato;
          _tickMacchinaTotale = totale;
        }
      }

      // Quanti core, per sapere che il 100% di un processo è un core intero e
      // non tutta la macchina.
      fuori['core'] = righe.where((r) => RegExp(r'^cpu\d').hasMatch(r)).length;
    } catch (_) {}

    // ── Memoria ─────────────────────────────────────────────────────────
    //
    // `MemAvailable` e non `MemFree`: la memoria usata dalla cache è libera in
    // pratica, e mostrare `MemFree` fa credere che il computer sia pieno
    // quando non lo è. È l'errore che rende inutili metà dei monitor in giro.
    try {
      final m = <String, int>{};
      for (final riga in await File('/proc/meminfo').readAsLines()) {
        final p = riga.split(':');
        if (p.length < 2) continue;
        final v = int.tryParse(p[1].trim().split(' ').first);
        if (v != null) m[p[0]] = v * 1024;
      }
      final totale = m['MemTotal'] ?? 0;
      final disponibile = m['MemAvailable'] ?? m['MemFree'] ?? 0;
      fuori['memoriaTotale'] = totale;
      fuori['memoriaUsata'] = totale - disponibile;
      fuori['memoriaCache'] = (m['Cached'] ?? 0) + (m['Buffers'] ?? 0);
      fuori['scambioTotale'] = m['SwapTotal'] ?? 0;
      fuori['scambioUsato'] = (m['SwapTotal'] ?? 0) - (m['SwapFree'] ?? 0);
    } catch (_) {}

    // ── Rete ────────────────────────────────────────────────────────────
    //
    // La somma di tutte le interfacce tranne `lo`: il traffico verso sé stessi
    // non è traffico, e su una macchina che fa sviluppo è quasi tutto.
    try {
      var giu = 0, su = 0;
      for (final riga in await File('/proc/net/dev').readAsLines().then((l) => l.skip(2))) {
        final p = riga.split(':');
        if (p.length < 2) continue;
        final nome = p[0].trim();
        if (nome == 'lo') continue;
        final c = p[1].trim().split(RegExp(r'\s+'));
        if (c.length < 9) continue;
        giu += int.tryParse(c[0]) ?? 0;
        su += int.tryParse(c[8]) ?? 0;
      }
      if (_reteGiuPrecedente > 0 && trascorso > 0) {
        fuori['reteGiu'] = ((giu - _reteGiuPrecedente) / trascorso).round();
        fuori['reteSu'] = ((su - _reteSuPrecedente) / trascorso).round();
      }
      _reteGiuPrecedente = giu;
      _reteSuPrecedente = su;
    } catch (_) {}

    // ── Temperatura ─────────────────────────────────────────────────────
    //
    // Si prende la zona più calda invece della prima: la prima è spesso il
    // chipset, che sta sempre a quaranta gradi e non dice niente. Quella che
    // interessa è la più alta, perché è quella che fa partire le ventole.
    try {
      var massima = 0.0;
      final base = Directory('/sys/class/thermal');
      if (base.existsSync()) {
        for (final z in base.listSync()) {
          final f = File('${z.path}/temp');
          if (!f.existsSync()) continue;
          final v = int.tryParse((await f.readAsString()).trim());
          if (v != null && v > 1000) {
            final gradi = v / 1000.0;
            if (gradi > massima && gradi < 130) massima = gradi;
          }
        }
      }
      if (massima > 0) fuori['temperatura'] = massima;
    } catch (_) {}

    // ── La GPU, e va chiamata col suo nome ──────────────────────────────
    //
    // Su questa macchina — Intel `i915` — l'USO della GPU non si può leggere
    // da utente normale: non c'è il `gpu_busy_percent` di AMD, e il contatore
    // del kernel sta dietro `perf_event_paranoid = 2`.
    //
    // Quello che si legge è `rc6_residency_ms`: i millisecondi che la GPU ha
    // passato nel sonno più profondo. Cento meno quella percentuale è il tempo
    // in cui la GPU era **SVEGLIA**, che non è la stessa cosa dell'uso — una
    // GPU sveglia può non star facendo niente — ma è un tetto all'uso ed è un
    // numero vero. Misurato il 9 settembre 2026 a scrivania quasi ferma:
    // +1720 ms su 2009, cioè sveglia il 15 %.
    //
    // Si chiama `gpuSveglia` e non `gpu` di proposito: il nome è la prima
    // riga di documentazione, e chiamarlo «uso» vorrebbe dire mentire in ogni
    // punto in cui viene mostrato. L'uso vero, motore per motore, arriva
    // dall'aiutante col permesso — e quando arriverà si chiamerà `gpuUso`, che
    // è un'altra cosa e va detta con un'altra parola.
    try {
      for (final card in ['card0', 'card1', 'card2']) {
        final f = File('/sys/class/drm/$card/power/rc6_residency_ms');
        if (!f.existsSync()) continue;
        final ms = int.tryParse((await f.readAsString()).trim());
        if (ms == null) break;
        if (_rc6Precedente > 0 && trascorso > 0) {
          final dorme = (ms - _rc6Precedente) / (trascorso * 1000.0) * 100.0;
          fuori['gpuSveglia'] = (100.0 - dorme).clamp(0.0, 100.0);
        }
        _rc6Precedente = ms;
        break;
      }
    } catch (_) {}

    // ── Carico e tempo acceso ───────────────────────────────────────────
    try {
      final l = (await File('/proc/loadavg').readAsString()).split(' ');
      fuori['carico'] = double.tryParse(l.first) ?? 0;
    } catch (_) {}
    try {
      final u = (await File('/proc/uptime').readAsString()).split(' ');
      fuori['acceso'] = (double.tryParse(u.first) ?? 0).round();
    } catch (_) {}

    // ── Il disco ────────────────────────────────────────────────────────
    //
    // È l'unico valore di questo giro che NON si legge da un file: lo spazio
    // libero di un filesystem si chiede con `statvfs`, e Dart non ce l'ha.
    // Quindi passa da `df`, che è un processo — l'unico di tutta la lettura.
    //
    // Perciò si chiede **una volta al minuto e non ogni cinque secondi**: lo
    // spazio libero di un disco da 950 GB non cambia in cinque secondi, e un
    // processo lanciato dodici volte al minuto per un numero che si muove una
    // volta all'ora sarebbe esattamente il tipo di consumo che questo file
    // passa il tempo a evitare (vedi il respiro ogni otto processi, più
    // sotto). Fra una lettura e l'altra si ripete l'ultimo valore, che è
    // vero: non è una stima, è la misura di cinquanta secondi fa.
    //
    // `-B1` per avere byte e non blocchi, e `--output` per non dover leggere
    // una tabella a colonne fisse che cambia con la lunghezza del nome del
    // dispositivo.
    final adesso = DateTime.now();
    if (_discoLetto == null ||
        adesso.difference(_discoLetto!).inSeconds >= 60) {
      _discoLetto = adesso;
      try {
        final r = await Process.run(
            'df', <String>['-B1', '--output=size,avail', '/']);
        final righe = (r.stdout as String).trim().split('\n');
        if (righe.length >= 2) {
          final n = righe[1].trim().split(RegExp(r'\s+'));
          if (n.length >= 2) {
            _discoTotale = int.tryParse(n[0]) ?? 0;
            _discoLibero = int.tryParse(n[1]) ?? 0;
          }
        }
      } catch (_) {}
    }
    if (_discoTotale > 0) {
      fuori['discoTotale'] = _discoTotale;
      fuori['discoLibero'] = _discoLibero;
    }

    return fuori;
  }

  /// Quando si è chiesto al disco l'ultima volta, e cosa ha risposto.
  DateTime? _discoLetto;
  int _discoTotale = 0;
  int _discoLibero = 0;

  int _tickMacchinaTotale = 0;

  /// Un processo per ogni cartella numerica in `/proc`.
  /// Ogni quanti processi si cede il filo.
  ///
  /// Otto, misurato e non scelto a occhio. Su 217 processi, in JIT:
  ///
  ///   senza respiro   tre giri 334 ms, fermo più lungo 115 ms
  ///   ogni 32         tre giri 321 ms, fermo più lungo  34 ms
  ///   ogni 16         tre giri 322 ms, fermo più lungo  21 ms
  ///   ogni 8          tre giri 346 ms, fermo più lungo  15 ms
  ///
  /// Il lavoro totale non cambia — è la stessa roba letta nello stesso modo —
  /// e a otto costa l'otto per cento in più di tempo di calendario per un
  /// fermo sette volte più corto. Scendere ancora (a quattro il fermo va a 10
  /// ms) rende meno di quel che costa: sotto c'è un fondo che non viene dal
  /// ciclo.
  static const int _respiroOgni = 8;

  /// Chi sa del respiro delle app (RespiroService.perPid): lo aggancia il
  /// nucleo. Nella schermata di accesso non c'è, e le righe restano senza.
  Map<int, Map<String, dynamic>> Function()? respiro;

  Future<List<Map<String, dynamic>>> _leggiProcessi() async {
    final fuori = <Map<String, dynamic>>[];
    final vivi = <int>{};
    var respiri = const <int, Map<String, dynamic>>{};
    try {
      respiri = respiro?.call() ?? respiri;
    } catch (_) {}

    final proc = Directory('/proc');
    if (!proc.existsSync()) return fuori;

    var letti = 0;
    for (final voce in proc.listSync(followLinks: false)) {
      final nome = voce.path.split('/').last;
      final pid = int.tryParse(nome);
      if (pid == null) continue;

      // ── Ogni tanto si respira ─────────────────────────────────────────
      //
      // Le letture qui sotto sono sincrone, ed è giusto che lo siano: un file
      // di `/proc` è venti byte in memoria, e farne duecento letture
      // asincrone costerebbe più del lavoro. Il problema non è la singola
      // lettura, è che sono DUECENTO di fila senza mai cedere il filo.
      //
      // Dart ne ha uno solo, e in tutto il demone non c'è nessun isolate:
      // finché questo ciclo gira, il demone non risponde a nessuno. Non è il
      // gestore attività a rallentare — è tutta la scrivania, ogni due
      // secondi, per il solo fatto che quella finestra è aperta.
      //
      // Misurato il 7 settembre 2026: 22 ms sul demone compilato, ~95-115 ms
      // in JIT — e in tutti e due i casi il ciclo non cedeva MAI, dal primo
      // processo all'ultimo.
      //
      // `Future.delayed(Duration.zero)` e non `await null`: il secondo cede
      // solo alla coda dei microtask, che è nostra, e le richieste dei client
      // resterebbero ferme lo stesso. Serve un giro completo dell'anello.
      if (letti > 0 && letti % _respiroOgni == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      letti++;

      try {
        final stat = File('/proc/$pid/stat').readAsStringSync();

        // Il nome del comando sta fra parentesi e PUÒ CONTENERE SPAZI e
        // parentesi. Spezzare la riga sugli spazi — l'istinto — dà campi
        // sfalsati per ogni processo con un nome composto, e i numeri che ne
        // escono sono di un altro campo. Si taglia sull'ULTIMA parentesi.
        final chiusa = stat.lastIndexOf(')');
        if (chiusa < 0) continue;
        final aperta = stat.indexOf('(');
        final comando = stat.substring(aperta + 1, chiusa);
        final resto = stat.substring(chiusa + 2).split(' ');
        if (resto.length < 22) continue;

        final stato = resto[0];
        final utime = int.tryParse(resto[11]) ?? 0;
        final stime = int.tryParse(resto[12]) ?? 0;
        final rss = (int.tryParse(resto[21]) ?? 0) * _memoriaPagina;
        final tick = utime + stime;

        vivi.add(pid);

        double? cpu;
        final precedente = _tickPrecedenti[pid];
        if (precedente != null && _tickAlSecondo > 0) {
          final d = tick - precedente;
          // Due secondi è il passo del timer. Si usa quello e non il tempo
          // vero perché i tick sono interi e il rumore su intervalli corti
          // farebbe ballare le percentuali.
          final secondi = 2.0;
          cpu = (d / _tickAlSecondo / secondi * 100).clamp(0, 100 * 64);
        }
        _tickPrecedenti[pid] = tick;

        // Quanta di quella memoria è CONDIVISA con altri processi.
        //
        // Serve perché l'RSS mente per omissione: dentro ci sono le librerie
        // (Qt, Mesa: centoventi megabyte) che stanno in memoria UNA VOLTA
        // SOLA e vengono contate in ognuno dei processi che le usano.
        // Sommando l'RSS di cinque finestre di Minerva si ottengono
        // seicento megabyte di cui quattrocentottanta sono le stesse pagine
        // contate cinque volte.
        //
        // Il terzo campo di `statm` è proprio quello, in pagine. Costa una
        // lettura di venti byte per processo — la fa anche `ps`.
        var condivisa = 0;
        try {
          final statm = File('/proc/$pid/statm').readAsStringSync().split(' ');
          if (statm.length >= 3) {
            condivisa = (int.tryParse(statm[2]) ?? 0) * _memoriaPagina;
          }
        } catch (_) {}

        // ── Il numero onesto: il PSS ────────────────────────────────────
        //
        // «Condivisa» non basta a raddrizzare il conto. Dice QUANTE pagine
        // sono condivise, non CON QUANTI: e la riga finiva per contare i
        // centoventi megabyte di Qt e Mesa per intero dentro OGNI nostra
        // finestra. Cinque app aperte, e le stesse pagine comparivano cinque
        // volte in cinque righe diverse.
        //
        // Il PSS le divide fra chi le usa: una pagina in cinque processi vale
        // un quinto in ognuno, e la somma delle righe torna a essere un
        // numero che esiste davvero. È quello che mostra anche il monitor di
        // KDE, e senza di lui i due non si possono confrontare.
        //
        // Costa: `smaps_rollup` fa camminare al kernel le tabelle delle
        // pagine. Misurato l'11 agosto 2026, 20 ms per quaranta processi —
        // sostenibile ogni due secondi, ma solo se non lo si chiede per tutti
        // e trecento. Sotto i dodici megabyte non cambierebbe niente di
        // leggibile, e si lascia stare. Per i processi di altri utenti il
        // file non è leggibile: lì resta la stima di prima.
        var pss = 0;
        if (rss >= 12 * 1024 * 1024) {
          try {
            final rollup = File('/proc/$pid/smaps_rollup').readAsStringSync();
            for (final riga in const LineSplitter().convert(rollup)) {
              if (riga.startsWith('Pss:')) {
                final campi = riga.split(RegExp(r'\s+'));
                if (campi.length >= 2) pss = (int.tryParse(campi[1]) ?? 0) * 1024;
                break;
              }
            }
          } catch (_) {}
        }

        // La riga di comando dice molto più del nome: `dartvm` non significa
        // niente, `dart run bin/minervad.dart` sì.
        var riga = '';
        try {
          riga = File('/proc/$pid/cmdline').readAsStringSync()
              .replaceAll('\x00', ' ')
              .trim();
        } catch (_) {}

        final rigaVera = riga.isEmpty ? comando : riga;
        fuori.add({
          'pid': pid,
          'nome': comando,
          'comando': rigaVera,
          // ── Le tre cose che rendono l'elenco leggibile ─────────────────
          //
          // Il monitor scriveva sotto ogni riga la riga di comando vera:
          // `qs -p ~/Minerva Shell/…/app.qml`, precisa, lunga tre volte la
          // finestra, e muta sulla domanda che si ha in testa aprendo un
          // gestore attività — «questa roba cos'è, e la posso chiudere?».
          // Vedi `processi_umani.dart`.
          'etichetta': etichetta(comando, rigaVera),
          'descrizione': descrizione(comando, rigaVera),
          'sistema': eDiSistema(comando, rigaVera),
          'stato': stato,
          'cpu': cpu,
          'memoria': rss,
          'memoriaCondivisa': condivisa,
          'memoriaEqua': pss,
          // Le nostre app nel loro scope: in vista, fuori vista o compressa,
          // e quanto tengono in RAM e in zram. Vedi RespiroService.
          if (respiri[pid] != null) 'respiro': respiri[pid],
        });
      } catch (_) {
        // Un processo può morire fra il `listSync` e la lettura: è normale, e
        // non è un errore da riportare.
      }
    }

    // I morti non restano nella tabella dei tick, o cresce per tutta la
    // sessione e prima o poi un PID riciclato eredita i tick di un altro
    // processo — con una percentuale assurda al primo giro.
    _tickPrecedenti.removeWhere((pid, _) => !vivi.contains(pid));

    return fuori;
  }

  // ── Chiudere ─────────────────────────────────────────────────────────────

  /// Chiede al processo di chiudersi (SIGTERM): ha modo di salvare.
  Future<bool> chiudi(int pid) async {
    return Process.killPid(pid, ProcessSignal.sigterm);
  }

  /// Lo termina senza chiedere (SIGKILL). Da offrire solo dopo che il primo
  /// non ha funzionato: qui il programma non salva niente.
  Future<bool> termina(int pid) async {
    return Process.killPid(pid, ProcessSignal.sigkill);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
