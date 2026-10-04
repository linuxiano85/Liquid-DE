import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'albero.dart';
import 'patch.dart';
import 'prova_avvio.dart';
import 'ricetta.dart';
import 'rilievo.dart';
import 'sorgenti.dart';

/// L'officina: esegue una ricetta, passo dopo passo, e racconta.
///
/// ── Una compilazione alla volta, per tutto il demone ────────────────────
///
/// Due compilazioni dello stesso albero insieme si pestano i file a vicenda,
/// e due di alberi diversi si dividono i processori finendo tutte e due più
/// tardi. Quindi l'officina è UNA, e chi chiede di avviarne una seconda si
/// sente rispondere che ce n'è già una — con il suo nome.
///
/// ── Chi ascolta ─────────────────────────────────────────────────────────
///
/// Una compilazione dura minuti, e in quei minuti la finestra si può
/// chiudere e riaprire. Il racconto non va quindi a «chi l'ha chiesta» ma a
/// chi sta ascoltando adesso: la finestra che si riapre chiede lo stato,
/// riceve le ultime righe e da lì in poi il seguito. Un ascoltatore morto si
/// toglie da solo al primo messaggio che non gli arriva.
///
/// ── Che cosa NON sopravvive ─────────────────────────────────────────────
///
/// La compilazione è figlia del demone: se il demone si riavvia (un
/// `minerva-reload.sh`, un aggiornamento), la compilazione si ferma con lui.
/// L'albero resta, e la volta dopo si riparte da dove si era rimasti —
/// `make` ricompila solo quello che manca — ma va rilanciata a mano. È
/// scritto qui perché è la prima cosa che sorprende.
class Officina {
  /// Dove la Fucina tiene archivi, alberi e kernel pronti.
  final String lavoro;

  /// Dove tiene quello che deve ricordare fra un avvio e l'altro: le misure
  /// delle compilazioni passate e i dispositivi attesi per la verifica.
  final String statoDir;

  /// La radice da cui leggere la configurazione di partenza (`/` davvero).
  final String radice;

  final Sorgenti sorgenti;

  /// Quanto spazio serve almeno per cominciare, in byte. Un kernel scremato
  /// ne usa meno, uno con la configurazione della distribuzione quasi il
  /// doppio: sei gigabyte sono la soglia sotto cui non vale la pena partire.
  /// Si cambia nelle prove, che girano in una /tmp che può essere piccola.
  final int spazioMinimo;

  /// Lancia un processo. Si sostituisce nelle prove.
  final Future<Process> Function(String eseguibile, List<String> argomenti,
      {String? workingDirectory}) lancia;

  /// Scarica un file. Si sostituisce nelle prove.
  final Future<String?> Function(Uri, File,
      {void Function(int, int)? progresso,
      bool Function()? annullato}) scarica;

  /// Verifica la firma dello sviluppatore su un archivio. Restituisce `null`
  /// se la firma è buona e di uno dei firmatari noti, o la frase da dire. Si
  /// sostituisce nelle prove: quella vera va in rete e chiede gpg.
  final Future<String?> Function(String versione, File archivio)? verificaFirma;

  /// Dice se c'è KVM per la prova d'avvio. Si sostituisce nelle prove.
  final Future<bool> Function()? conKvm;

  Officina({
    required this.lavoro,
    required this.statoDir,
    this.radice = '/',
    this.spazioMinimo = 6000000000,
    Sorgenti? sorgenti,
    Future<Process> Function(String, List<String>, {String? workingDirectory})?
        lancia,
    Future<String?> Function(Uri, File,
            {void Function(int, int)? progresso, bool Function()? annullato})?
        scarica,
    this.verificaFirma,
    this.conKvm,
  })  : sorgenti = sorgenti ?? Sorgenti(),
        lancia = lancia ?? _lanciaVero,
        scarica = scarica ?? scaricaFile;

  static Future<Process> _lanciaVero(String e, List<String> a,
          {String? workingDirectory}) =>
      Process.start(e, a, workingDirectory: workingDirectory);

  /// Le cartelle di una scelta. Una funzione sola, usata anche dal servizio
  /// per calcolare la ricetta da mostrare: il piano che si vede e quello che
  /// si esegue devono nominare gli stessi posti.
  static Cartelle cartellePer(Scelte s, String lavoro) {
    final base = '$lavoro/alberi/${s.versione}-${s.sorgente.name}';
    return Cartelle(
      albero: '$base/linux-${s.versione}',
      uscita: '$lavoro/uscita/${s.rilascio}',
      lsmod: '$lavoro/lsmod-${s.nome}.txt',
      profilo: s.profilo.isEmpty ? '' : '${profiliDi(lavoro, s.profilo)}/autofdo.prof',
    );
  }

  /// Dove stanno le cose di un kernel per AutoFDO: il suo `vmlinux` (perf e
  /// llvm-profgen hanno bisogno di QUELLO, con gli stessi indirizzi del
  /// kernel che girava), la sua configurazione e il profilo convertito.
  static String profiliDi(String lavoro, String rilascio) =>
      '$lavoro/profili/$rilascio';

  // ── Lo stato ─────────────────────────────────────────────────────────

  bool _inCorso = false;
  bool get inCorso => _inCorso;
  bool _annullato = false;
  Process? _processo;
  String _rilascio = '';
  String _passo = '';
  DateTime? _inizio;
  Map<String, dynamic>? _ultimoEsito;

  /// Le ultime righe, per chi arriva a metà. Quattrocento bastano a capire
  /// un errore di compilazione, che si legge dal fondo.
  final List<String> _coda = [];
  static const int _codaMax = 400;

  /// Chi ascolta riceve un TIPO (`passo`, `righe`, `avanzamento`, `fatto`)
  /// e i dati. Il nome dell'evento sul canale lo sceglie il server: i nomi
  /// del bus stanno tutti in `websocket_server.dart`, dove le prove li
  /// contano contro `EVENTS.md`.
  final Map<Object, void Function(String tipo, Map<String, dynamic> dati)>
      _ascoltatori = {};

  void ascolta(Object chi,
          void Function(String tipo, Map<String, dynamic> dati) manda) =>
      _ascoltatori[chi] = manda;

  void smetti(Object chi) => _ascoltatori.remove(chi);

  /// Lo stato di ogni passo, e la fase con i suoi conti: servono a chi
  /// riapre la finestra a metà, per vedere i passi già fatti come fatti e la
  /// barra dov'è. (Trovato da una revisione automatica della PR.)
  final Map<String, String> _statiPassi = {};
  String _titoloPasso = '';
  Map<String, dynamic> _avanzamento = const {};

  Map<String, dynamic> stato() => {
        'inCorso': _inCorso,
        'rilascio': _rilascio,
        'passo': _titoloPasso,
        'passi': Map<String, String>.from(_statiPassi),
        'avanzamento': _avanzamento,
        'secondi': _inizio == null
            ? 0
            : DateTime.now().difference(_inizio!).inSeconds,
        'righe': List<String>.from(_coda),
        'esito': _ultimoEsito,
      };

  /// Un messaggio a tutti quelli che ascoltano. Si cammina su una copia: un
  /// ascoltatore che si toglie mentre si manda cambierebbe l'elenco sotto i
  /// piedi.
  void _manda(String tipo, Map<String, dynamic> dati) {
    if (tipo == 'passo') {
      _statiPassi['${dati['id']}'] = '${dati['stato']}';
      if (dati['stato'] == 'via') _titoloPasso = '${dati['titolo']}';
    } else if (tipo == 'avanzamento') {
      _avanzamento = dati;
    }
    for (final f in List.of(_ascoltatori.values)) {
      try {
        f(tipo, dati);
      } catch (_) {}
    }
  }

  // ── Le righe ─────────────────────────────────────────────────────────

  final List<String> _daMandare = [];
  Timer? _spedizione;
  int _oggetti = 0;
  int _attesi = 0;
  static final RegExp _oggetto = RegExp(r'^  (CC|CC \[M\]|AS|AS \[M\]) ');

  void _riga(String r) {
    if (_oggetto.hasMatch(r)) _oggetti++;
    _coda.add(r);
    if (_coda.length > _codaMax) _coda.removeRange(0, _coda.length - _codaMax);
    _daMandare.add(r);
    _spedizione ??= Timer(const Duration(milliseconds: 300), _spedisci);
  }

  /// Le righe partono a mazzi, tre volte al secondo al massimo. `make -j12`
  /// ne scrive centinaia al secondo, e un messaggio per riga intaserebbe il
  /// canale per tutte le altre finestre.
  void _spedisci() {
    _spedizione = null;
    if (_daMandare.isEmpty) return;
    var righe = List.of(_daMandare);
    _daMandare.clear();
    if (righe.length > 200) {
      final saltate = righe.length - 200;
      righe = ['… $saltate righe saltate …', ...righe.sublist(saltate)];
    }
    _manda('righe', {'righe': righe});
    if (_passo == 'compila') {
      _manda('avanzamento',
          {'fase': 'compila', 'fatti': _oggetti, 'attesi': _attesi});
    }
  }

  // ── Avviare e fermare ────────────────────────────────────────────────

  /// Avvia la ricetta e torna subito: il seguito arriva a chi ascolta.
  Map<String, dynamic> avvia(Ricetta r, Rilievo rilievo) {
    if (_inCorso) {
      return {
        'ok': false,
        'errore': 'C\'è già una compilazione in corso ($_rilascio).',
      };
    }
    if (!Platform.version.contains('linux_x64')) {
      return {
        'ok': false,
        'errore': 'Per ora la Fucina compila solo per x86-64.',
      };
    }
    _inCorso = true;
    _annullato = false;
    _rilascio = r.rilascio;
    _inizio = DateTime.now();
    _coda.clear();
    _oggetti = 0;
    _ultimoEsito = null;
    _statiPassi.clear();
    _titoloPasso = '';
    _avanzamento = const {};
    // ── Un errore qui non deve arrivare alla zona del demone ─────────────
    //
    // `_esegui` gira senza che nessuno la aspetti: un'eccezione che ne
    // uscisse non avrebbe un chiamante a cui tornare, e finirebbe alla zona
    // — che è il modo in cui il 31 agosto un errore di scrittura ha fatto
    // ripartire il demone. Ogni passo ha già il suo `try`; questo prende
    // quello che sta fra un passo e l'altro (il segno di «pronto», le
    // misure) e rimette l'officina in piedi.
    unawaited(_esegui(r, rilievo).catchError((Object e) {
      _inCorso = false;
      _processo = null;
      _passo = '';
      final esito = {
        'ok': false,
        'annullato': _annullato,
        'errore': 'Errore inatteso: $e',
        'rilascio': r.rilascio,
        'uscita': '',
        'secondi': DateTime.now().difference(_inizio!).inSeconds,
        'avvisi': <String>[],
      };
      _ultimoEsito = esito;
      _manda('fatto', esito);
    }));
    return {'ok': true, 'rilascio': r.rilascio};
  }

  /// Ferma la compilazione. Il gruppo di processi intero: `make -j12` ha
  /// dodici figli, e fermare solo lui li lascerebbe a finire da soli.
  Future<void> ferma() async {
    if (!_inCorso) return;
    _annullato = true;
    final p = _processo;
    if (p == null) return;
    await _segnale(p.pid, 'TERM');
    // Cinque secondi per chiudere da sé, poi si stacca la spina.
    final uscito = await p.exitCode
        .timeout(const Duration(seconds: 5), onTimeout: () => -999);
    if (uscito == -999) await _segnale(p.pid, 'KILL');
  }

  Future<void> _segnale(int pid, String quale) async {
    try {
      // Con il meno davanti è il GRUPPO: i processi partono con `setsid`,
      // quindi il gruppo è loro e non quello del demone.
      if (_conSetsid) {
        await Process.run('kill', ['-$quale', '--', '-$pid']);
      } else {
        Process.killPid(pid,
            quale == 'KILL' ? ProcessSignal.sigkill : ProcessSignal.sigterm);
      }
    } catch (_) {}
  }

  static final bool _conSetsid = File('/usr/bin/setsid').existsSync() ||
      File('/bin/setsid').existsSync();

  // ── L'esecuzione ─────────────────────────────────────────────────────

  Future<void> _esegui(Ricetta r, Rilievo rilievo) async {
    final c = cartellePer(r.scelte, lavoro);
    final base = c.albero.substring(0, c.albero.lastIndexOf('/'));
    final segno = File('$base/.fucina-pronto');
    final pronto = await segno.exists();
    final avvisi = <String>[...r.avvisi];
    final misure = await _leggiMisure();
    _attesi = (misure[r.rilascio]?['oggetti'] as int?) ?? 0;
    String? errore;

    final ultimoPrimaVolta =
        r.passi.lastIndexWhere((p) => p.soloLaPrimaVolta);
    _mappa = null;
    _completati = const [];

    // Il secondo tempo di AutoFDO senza il profilo è un kernel compilato
    // «col profilo» che di profilo non ne ha: lo si dice prima di scaricare.
    if (c.profilo.isNotEmpty && !await File(c.profilo).exists()) {
      errore = 'Non trovo il profilo di ${r.scelte.profilo} (${c.profilo}): '
          'registralo prima dalla pagina Kernel, avviato su quel kernel.';
    }

    // ── Prima di tutto, lo spazio ──────────────────────────────────────
    //
    // Un albero del kernel con la compilazione dentro occupa da tre a
    // quindici gigabyte, a seconda di quanti moduli restano. Scoprirlo a
    // metà, con il disco pieno e `make` che scrive errori incomprensibili, è
    // il modo peggiore: lo si dice prima di scaricare.
    final libero = errore == null ? await _spazioLibero() : null;
    if (libero != null && libero < spazioMinimo) {
      errore = 'Servono almeno ${spazioMinimo ~/ 1000000000} GB liberi dove '
          'la Fucina lavora ($lavoro): ce ne sono '
          '${(libero / 1e9).toStringAsFixed(1)}.';
    }

    for (var i = 0; errore == null && i < r.passi.length; i++) {
      final p = r.passi[i];
      if (_annullato) {
        errore = 'Fermata.';
        break;
      }
      _passo = p.id;
      final t0 = DateTime.now();
      // Le righe del passo prima partono PRIMA del passo dopo: senza, il
      // diario mostrava «Da accendere…» (di «completa») sotto il titolo di
      // «imposta». Visto nel diario della compilazione vera.
      _spedizione?.cancel();
      _spedisci();
      if (p.soloLaPrimaVolta && pronto) {
        _manda('passo', {
          'id': p.id, 'titolo': p.titolo, 'indice': i,
          'quanti': r.passi.length, 'stato': 'saltato',
        });
        continue;
      }
      _manda('passo', {
        'id': p.id, 'titolo': p.titolo, 'indice': i,
        'quanti': r.passi.length, 'stato': 'via',
      });
      _riga('── ${p.titolo}');

      try {
        errore = await _passoUno(p, r, rilievo, c, base, avvisi);
      } catch (e) {
        errore = 'Errore inatteso in «${p.titolo}»: $e';
      }
      if (errore == null && _annullato) errore = 'Fermata.';

      _manda('passo', {
        'id': p.id, 'titolo': p.titolo, 'indice': i,
        'quanti': r.passi.length,
        'stato': errore == null ? 'fatto' : 'fallito',
        'secondi': DateTime.now().difference(t0).inSeconds,
      });
      if (errore != null) break;

      if (i == ultimoPrimaVolta) {
        await segno.writeAsString('${DateTime.now().toIso8601String()}\n');
      }
      if (p.id == 'compila' && _oggetti > 0) {
        final prima = (misure[r.rilascio]?['oggetti'] as int?) ?? 0;
        // Si tiene il massimo: una ricompilazione che rifà dieci file non
        // deve far credere alla prossima compilazione intera di durarne dieci.
        if (_oggetti > prima) {
          misure[r.rilascio] = {'oggetti': _oggetti};
          await _scriviMisure(misure);
        }
      }
    }

    _spedizione?.cancel();
    _spedisci();
    final esito = {
      'ok': errore == null,
      'annullato': _annullato,
      'errore': errore ?? '',
      'rilascio': r.rilascio,
      'uscita': c.uscita,
      'secondi': DateTime.now().difference(_inizio!).inSeconds,
      'avvisi': avvisi,
    };
    _ultimoEsito = esito;
    _inCorso = false;
    _processo = null;
    _passo = '';
    _manda('fatto', esito);
  }

  /// Un passo. Restituisce `null` se è andato, o la frase da dire.
  Future<String?> _passoUno(Passo p, Ricetta r, Rilievo rilievo, Cartelle c,
      String base, List<String> avvisi) async {
    switch (p.id) {
      case 'scarica':
        return r.scelte.sorgente == TipoSorgente.cachyos
            ? _scaricaCachyos(r.scelte.versione)
            : _scarica(r.scelte.versione);
      case 'estrai':
        return _estrai(r.scelte.versione, base, c.albero,
            cachyos: r.scelte.sorgente == TipoSorgente.cachyos);
      case 'patch':
        return _patch(r.scelte.versione, c.albero);
      case 'base':
        if (p.comando.isNotEmpty) {
          // Da defconfig non c'è una configurazione «da cui si è partiti» da
          // portare col kernel: quella di una compilazione precedente non
          // deve restare lì a mentire.
          final vecchia = File('${c.albero}/.fucina-partenza.config');
          if (await vecchia.exists()) await vecchia.delete();
          return _lancia(p.comando, c.albero);
        }
        return _base(rilievo.configPartenza, c.albero);
      case 'completa':
        return _completa(r, rilievo, c);
      case 'screma':
        await File(c.lsmod).parent.create(recursive: true);
        await File(c.lsmod).writeAsString('${r.fileLsmod}\n');
        return _lancia(p.comando, c.albero, invii: true);
      case 'controlla':
        final config = await File('${c.albero}/.config').readAsString();
        for (final a in controllaConfig(config, r.impostazioni)) {
          _riga('⚠ $a');
          avvisi.add(a);
        }
        // I moduli che «completa» ha acceso: Kconfig può averne rimesso a
        // «n» qualcuno, se dipende da qualcosa che in questa configurazione
        // non c'è. Si dice per nome di modulo, che è quello che chi guarda
        // ha scelto, e non per simbolo.
        final m = _mappa;
        if (m != null && _completati.isNotEmpty) {
          final ancora =
              confronta(leggiConfig(config), m, _completati).mancanti;
          if (ancora.isNotEmpty) {
            final a = 'Non sono entrati, anche se li avevi chiesti (scorte, '
                'essenziali o aggiunti): ${ancora.join(', ')}. Kconfig li ha '
                'lasciati fuori perché dipendono da qualcosa che questa '
                'configurazione non ha.';
            _riga('⚠ $a');
            avvisi.add(a);
          }
        }
        return null;
      case 'rilascio':
        final letto = <String>[];
        final e = await _lancia(p.comando, c.albero, raccogli: letto);
        if (e != null) return e;
        final nome = letto.where((l) => l.trim().isNotEmpty).join().trim();
        if (nome != r.rilascio) {
          return 'Il kernel si chiama «$nome» e non «${r.rilascio}»: qualcosa '
              'ha cambiato il nome (una patch, un EXTRAVERSION). Mi fermo '
              'prima di preparare un kernel che l\'installazione non '
              'riconoscerebbe.';
        }
        return null;
      case 'moduli':
        final u = Directory(c.uscita);
        if (c.uscita.startsWith('$lavoro/uscita/') && await u.exists()) {
          await u.delete(recursive: true);
        }
        return _lancia(p.comando, c.albero);
      case 'impacchetta':
        return _impacchetta(r, rilievo, c);
      case 'avvia':
        return _provaAvvio(r, c, avvisi);
      default:
        if (p.comando.isEmpty) return null;
        return _lancia(p.comando, c.albero);
    }
  }

  Future<String?> _scarica(String versione) async {
    final archivi = '$lavoro/archivi';
    final nome = 'linux-$versione.tar.xz';
    final file = File('$archivi/$nome');
    // Il segno che QUESTO archivio (con questa somma) ha già una firma
    // verificata: la verifica decomprime tutto l'archivio, e rifarla a ogni
    // compilazione costerebbe mezzo minuto per niente.
    final verificato = File('$archivi/$nome.firma-verificata');

    _riga('Leggo la somma di controllo da kernel.org.');
    final somme = await sorgenti.testo(Sorgenti.somme(versione));
    if (somme == null) {
      return 'Non riesco a leggere le somme di controllo da kernel.org.';
    }
    final attesa = Sorgenti.sommaDi(somme, nome);
    if (attesa == null) {
      return 'kernel.org non pubblica una somma per $nome: non scarico un '
          'archivio che non posso controllare.';
    }

    if (await file.exists()) {
      if (await _somma(file.path) == attesa) {
        _riga('Già scaricato, e la somma torna.');
        return _firma(versione, file, verificato, attesa);
      }
      _riga('L\'archivio che c\'era non torna con la somma: lo riscarico.');
      await file.delete();
    }

    _riga('Scarico $nome.');
    final e = await scarica(Sorgenti.archivio(versione), file,
        progresso: (fatti, attesi) => _manda('avanzamento',
            {'fase': 'scarica', 'fatti': fatti, 'attesi': attesi}),
        annullato: () => _annullato);
    if (e != null) return e;

    final vista = await _somma(file.path);
    if (vista != attesa) {
      await file.delete();
      return 'L\'archivio scaricato non torna con la somma di kernel.org: '
          'l\'ho cancellato. Riprova; se succede ancora, non fidarti della '
          'rete che stai usando.';
    }
    _riga('La somma SHA-256 torna.');
    return _firma(versione, file, verificato, attesa);
  }

  // ── CachyOS: il loro archivio, quando c'è ─────────────────────────────
  //
  // Dalla 6.17 CachyOS pubblica il suo albero già patchato; prima, solo le
  // patch da mettere sopra kernel.org. Quale delle due si è presa resta
  // scritto in `cachyos-<versione>.etichetta` accanto agli archivi: `estrai`
  // e `patch` lo rileggono.
  File _fileEtichetta(String versione) =>
      File('$lavoro/archivi/cachyos-$versione.etichetta');

  Future<String?> _etichettaScelta(String versione) async {
    try {
      final t = (await _fileEtichetta(versione).readAsString()).trim();
      return t.isEmpty ? null : t;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _scaricaCachyos(String versione) async {
    _riga('Chiedo a CachyOS se ha l\'archivio del $versione.');
    final refs = await sorgenti.testo(Sorgenti.refsLinuxCachyos);
    final etichetta =
        refs == null ? null : Sorgenti.etichettaCachyos(refs, versione);
    final segno = _fileEtichetta(versione);
    await segno.parent.create(recursive: true);
    if (etichetta == null) {
      if (refs == null) {
        return 'Non riesco a chiedere a CachyOS quali archivi ha. Sei in rete?';
      }
      if (await segno.exists()) await segno.delete();
      _riga('CachyOS non ha un archivio suo per il $versione: prendo quello '
          'di kernel.org e ci metto sopra le loro patch.');
      return _scarica(versione);
    }
    await segno.writeAsString('$etichetta\n');

    final nome = '$etichetta.tar.gz';
    final file = File('$lavoro/archivi/$nome');
    final verificato = File('$lavoro/archivi/$nome.firma-verificata');
    if (await file.exists()) {
      final somma = await _somma(file.path);
      try {
        if (somma != null &&
            (await verificato.readAsString()).trim() == somma) {
          _riga('$nome già scaricato, e la sua firma è già stata verificata.');
          return null;
        }
      } catch (_) {}
    } else {
      _riga('Scarico $nome da CachyOS.');
      final e = await scarica(Sorgenti.archivioCachyos(etichetta), file,
          progresso: (fatti, attesi) => _manda('avanzamento',
              {'fase': 'scarica', 'fatti': fatti, 'attesi': attesi}),
          annullato: () => _annullato);
      if (e != null) return e;
    }
    _riga('Verifico la firma degli sviluppatori di CachyOS (gpg).');
    final e = await (verificaFirma ?? _verificaCachyosVera)(etichetta, file);
    if (e != null) {
      try {
        await file.delete();
      } catch (_) {}
      return e;
    }
    final somma = await _somma(file.path) ?? '';
    await verificato.writeAsString('$somma\n');
    return null;
  }

  Future<String?> _verificaCachyosVera(String etichetta, File archivio) =>
      verificaArchivioCachyos(
        etichetta: etichetta,
        archivio: archivio,
        portachiavi: '$lavoro/gnupg',
        sorgenti: sorgenti,
        scarica: (u, f) => scarica(u, f, annullato: () => _annullato),
        racconta: _riga,
      );

  /// La firma dello sviluppatore, una volta per archivio. Una firma che non
  /// torna butta via l'archivio: non si compila un kernel che nessuno dei
  /// firmatari di kernel.org ha firmato.
  Future<String?> _firma(
      String versione, File archivio, File verificato, String somma) async {
    try {
      if (await verificato.exists() &&
          (await verificato.readAsString()).trim() == somma) {
        _riga('La firma di questo archivio è già stata verificata.');
        return null;
      }
    } catch (_) {}
    _riga('Verifico la firma dello sviluppatore (gpg).');
    final e = await (verificaFirma ?? _verificaFirmaVera)(versione, archivio);
    if (e != null) {
      try {
        await archivio.delete();
      } catch (_) {}
      return e;
    }
    await verificato.writeAsString('$somma\n');
    return null;
  }

  Future<String?> _verificaFirmaVera(String versione, File archivio) =>
      verificaArchivio(
        versione: versione,
        archivio: archivio,
        portachiavi: '$lavoro/gnupg',
        sorgenti: sorgenti,
        scarica: (u, f) => scarica(u, f, annullato: () => _annullato),
        racconta: _riga,
      );

  /// La somma con `sha256sum` e non in Dart: centocinquanta megabyte sul
  /// filo unico del demone fermerebbero tutte le finestre per secondi.
  Future<String?> _somma(String percorso) async {
    try {
      final r = await Process.run('sha256sum', [percorso]);
      if (r.exitCode != 0) return null;
      return '${r.stdout}'.split(RegExp(r'\s')).first.trim();
    } catch (_) {
      return null;
    }
  }

  Future<String?> _estrai(String versione, String base, String albero,
      {bool cachyos = false}) async {
    final d = Directory(base);
    // Un albero senza il segno di «pronto» è un'estrazione o una patch
    // rimasta a metà: si butta e si rifà. Solo dentro la nostra cartella —
    // il controllo sul prefisso è la differenza fra «rifaccio l'albero» e
    // «cancello una cartella qualunque».
    if (await d.exists()) {
      if (!base.startsWith('$lavoro/alberi/')) {
        return 'Cartella dell\'albero inattesa: $base.';
      }
      _riga('Tolgo un albero rimasto a metà.');
      await d.delete(recursive: true);
    }
    await d.create(recursive: true);
    final etichetta = cachyos ? await _etichettaScelta(versione) : null;
    final String? e;
    if (etichetta != null) {
      // L'archivio di CachyOS si apre in `cachyos-<versione>-<n>/`: lo si
      // mette dove la Fucina si aspetta l'albero, `linux-<versione>/`.
      await Directory(albero).create(recursive: true);
      e = await _lancia([
        'tar', '-xzf', '$lavoro/archivi/$etichetta.tar.gz',
        '-C', albero, '--strip-components=1',
      ], base);
    } else {
      e = await _lancia(
          ['tar', '-xf', '$lavoro/archivi/linux-$versione.tar.xz', '-C', base],
          base);
    }
    if (e != null) return e;
    if (!await File('$albero/Makefile').exists()) {
      return 'L\'archivio non contiene ${etichetta ?? 'linux-$versione'}/Makefile.';
    }
    return null;
  }

  Future<String?> _patch(String versione, String albero) async {
    final serie = serieDi(versione);
    final etichetta = await _etichettaScelta(versione);
    if (etichetta != null) {
      // L'albero È già il kernel di CachyOS: le loro patch e BORE ci sono.
      // Riapplicarle è quello che falliva (4 ottobre 2026).
      _riga('Sorgenti di CachyOS ($etichetta): le loro patch e lo scheduler '
          'BORE ci sono già, non applico niente.');
      final somma =
          await _somma('$lavoro/archivi/$etichetta.tar.gz') ?? '?';
      await _segnaPatch(albero, '$etichetta.tar.gz', somma, etichetta);
      return null;
    }
    // ── Un commit, non «master» ────────────────────────────────────────
    //
    // `master` cambia sotto i piedi: due download a un minuto di distanza
    // possono dare due patch diverse. Si chiede prima a che commit è, e si
    // scarica da QUEL commit: le patch della base e di BORE vengono dallo
    // stesso istante del loro repository, e il commit resta scritto nel
    // kernel pronto. Non è una firma — CachyOS non firma le patch — ma dice
    // esattamente che cosa c'è dentro. (Da una revisione automatica.)
    final refs = await sorgenti.testo(Sorgenti.refsCachyos);
    final commit = refs == null ? null : Sorgenti.commitDaRefs(refs);
    if (commit == null) {
      return 'Non riesco a sapere a che commit sono le patch di CachyOS: senza, '
          'non so che cosa applicherei.';
    }
    _riga('Patch di CachyOS al commit $commit.');
    // La serie base prima, se c'è; BORE poi, e senza BORE ci si ferma.
    final daApplicare = <Uri>[];
    if (await sorgenti.esiste(Sorgenti.baseCachyos(serie, commit))) {
      daApplicare.add(Sorgenti.baseCachyos(serie, commit));
    } else {
      // BORE da solo sopra kernel.org NON è il kernel di CachyOS, e la patch
      // è scritta per il loro albero: non si applica (9 blocchi su 22 sul
      // 7.2.9). Meglio fermarsi e dirlo.
      return 'CachyOS non ha né un archivio suo né la serie base per il '
          '$versione: le sue patch da sole non si applicano ai sorgenti di '
          'kernel.org. Scegli «Linux», o un\'altra versione.';
    }
    daApplicare.add(Sorgenti.boreCachyos(serie, commit));

    for (final u in daApplicare) {
      final nome = 'cachyos-$serie-${u.pathSegments.last}';
      final f = File('$lavoro/archivi/$nome');
      _riga('Scarico ${u.pathSegments.last}.');
      final e = await scarica(u, f, annullato: () => _annullato);
      if (e != null) {
        return 'CachyOS non ha (o non ha ancora) ${u.pathSegments.last} per '
            'la serie $serie: $e';
      }
      final prova = await applicaPatch(file: f.path,
          esegui: (comando) => _lancia(comando, albero));
      if (!prova.ok) {
        return '${u.pathSegments.last} non si applica interamente a linux-$versione '
            'e non risulta già presente. Nessuna patch incompatibile viene ignorata. '
            'La volta successiva i sorgenti saranno estratti di nuovo.';
      }
      if (prova.giaPresente) _riga('${u.pathSegments.last}: modifiche già presenti, non riapplico.');
      // Le patch di CachyOS non sono firmate: se ne scrive la somma, che
      // resta nel kernel pronto (`fucina.json`) e dice ESATTAMENTE che cosa
      // c'è dentro.
      final somma = await _somma(f.path) ?? '?';
      _riga('Applicata ${u.pathSegments.last} (SHA-256 $somma).');
      await _segnaPatch(albero, u.pathSegments.last, somma, commit);
    }
    return null;
  }

  Future<void> _segnaPatch(
      String albero, String nome, String somma, String commit) async {
    final f = File('$albero/.fucina-patch.json');
    var elenco = <dynamic>[];
    try {
      elenco = jsonDecode(await f.readAsString()) as List;
    } catch (_) {}
    elenco.add({'nome': nome, 'sha256': somma, 'commit': commit});
    await f.writeAsString(jsonEncode(elenco));
  }

  Future<String?> _base(String partenza, String albero) async {
    if (partenza.isEmpty) {
      return 'Non c\'è una configurazione del kernel in uso da cui partire.';
    }
    final vero = '$radice${partenza.substring(1)}';
    final byte = await File(vero).readAsBytes();
    final testo = partenza.endsWith('.gz') ? gzip.decode(byte) : byte;
    await File('$albero/.config').writeAsBytes(testo);
    // Una copia che viaggia col kernel: `impacchetta` la mette accanto ai
    // moduli, e quando questo kernel sarà quello in uso il rilievo ripartirà
    // da lei e non dalla sua configurazione già scremata.
    await File('$albero/.fucina-partenza.config').writeAsBytes(testo);
    _riga('Configurazione di partenza: $partenza.');
    return null;
  }

  // ── Completare quello che localmodconfig non aggiunge ────────────────

  /// La mappa moduli → simboli dell'albero di questa compilazione, e i
  /// moduli che `completa` ha acceso: servono ancora a `controlla`.
  MappaModuli? _mappa;
  List<String> _completati = const [];

  Future<String?> _completa(Ricetta r, Rilievo rilievo, Cartelle c) async {
    _riga('Leggo nei Makefile quale simbolo costruisce ogni modulo.');
    final mappa = await MappaModuli.leggi(c.albero);
    _mappa = mappa;
    final config = await File('${c.albero}/.config').readAsString();
    final voluti = daCompletare(r, rilievo);
    final esito = confronta(leggiConfig(config), mappa, voluti);
    // Gli sconosciuti si dicono solo fra quelli scelti da chi guarda: gli
    // essenziali hanno nomi di più versioni (`sha256_generic` e `sha256`),
    // e uno che in questo albero non c'è non è una notizia.
    final scelti = {...voluti}..removeAll(rilievo.avvio.moduli);
    final ignoti = esito.sconosciuti.where(scelti.contains).toList();
    if (ignoti.isNotEmpty) {
      _riga('⚠ Non trovo nei sorgenti di questa versione: ${ignoti.join(', ')} '
          '(nome cambiato, o un modulo che viene da fuori).');
    }
    if (esito.mancanti.isEmpty) {
      _riga('Niente da aggiungere: la configurazione accende già tutti i '
          '${voluti.length} moduli promessi.');
      _completati = const [];
      return null;
    }
    _completati = esito.mancanti;
    final moduli = leggiConfig(config)['MODULES'] == 'y';
    _riga('Da accendere (${esito.mancanti.length}): ${esito.mancanti.join(', ')}'
        '${moduli ? '' : ' — la configurazione non ha moduli: entrano nel '
            'kernel (=y)'}.');
    return _lancia([
      'scripts/config',
      '--file',
      '.config',
      for (final s in esito.daAccendere) ...['--module', s],
    ], c.albero);
  }

  Future<String?> _impacchetta(Ricetta r, Rilievo rilievo, Cartelle c) async {
    final rel = r.rilascio;
    final moduli = Directory('${c.uscita}/lib/modules/$rel');
    if (!await moduli.exists()) {
      return 'I moduli non sono finiti in ${moduli.path}.';
    }
    // I due collegamenti che `modules_install` lascia verso l'albero dei
    // sorgenti. Puntano dentro la tua cartella, e l'aiutante di root rifiuta
    // qualunque collegamento: in /usr/lib/modules non devono arrivare.
    for (final l in ['build', 'source']) {
      final link = Link('${moduli.path}/$l');
      if (await link.exists()) await link.delete();
    }
    final boot = Directory('${c.uscita}/boot');
    await boot.create(recursive: true);
    final immagine = File('${c.albero}/arch/x86/boot/bzImage');
    if (!await immagine.exists()) return 'Manca arch/x86/boot/bzImage.';
    await immagine.copy('${boot.path}/vmlinuz-$rel');
    await File('${c.albero}/.config').copy('${boot.path}/config-$rel');
    final partenza = File('${c.albero}/.fucina-partenza.config');
    if (await partenza.exists()) {
      await partenza.copy('${moduli.path}/fucina-partenza.config');
    }

    // ── Il primo tempo di AutoFDO: il vmlinux da parte ────────────────
    //
    // Il profilo si converte con il vmlinux del kernel che girava mentre lo
    // si registrava, indirizzo per indirizzo. L'albero invece si riusa: la
    // prossima compilazione — compresa quella col profilo — riscrive il suo
    // vmlinux. Quindi una copia, `--reflink=auto`: su Btrfs (CachyOS di
    // serie) non occupa spazio finché i due file non divergono.
    if (r.scelte.autofdo) {
      final dove = Directory(profiliDi(lavoro, rel));
      await dove.create(recursive: true);
      final e = await _lancia([
        'cp', '--reflink=auto', '--',
        '${c.albero}/vmlinux', '${dove.path}/vmlinux',
      ], c.albero);
      if (e != null) return 'Non riesco a mettere da parte il vmlinux: $e';
      await File('${c.albero}/.config').copy('${dove.path}/config');
      _riga('vmlinux da parte per il profilo: ${dove.path}');
    }

    List<dynamic> patch = const [];
    try {
      patch = jsonDecode(
          await File('${c.albero}/.fucina-patch.json').readAsString()) as List;
    } catch (_) {}
    await File('${c.uscita}/fucina.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert({
      'rilascio': rel,
      'scelte': r.scelte.toJson(),
      'moduli': r.moduli.length,
      'patch': patch,
      if (r.scelte.profilo.isNotEmpty)
        'profilo': {
          'da': r.scelte.profilo,
          'sha256': await _somma(c.profilo) ?? '?',
        },
      'quando': DateTime.now().toIso8601String(),
    }));

    // ── Quello che deve esserci al primo avvio ─────────────────────────
    //
    // I dispositivi che ADESSO hanno un driver. Al primo avvio del kernel
    // nuovo la verifica rilegge `/sys` e dice quali sono rimasti senza: è la
    // rete sotto una scrematura aggressiva.
    await Directory(statoDir).create(recursive: true);
    await File('$statoDir/attesi-$rel.json').writeAsString(jsonEncode([
      for (final d in rilievo.dispositivi)
        if (d.driver != null)
          {
            'percorso': d.percorso,
            'modalias': d.modalias,
            'driver': d.driver,
            'modulo': d.modulo,
          },
    ]));
    _riga('Pronto da installare: ${c.uscita}');
    return null;
  }

  // ── La prova d'avvio ─────────────────────────────────────────────────

  /// Se c'è KVM per chi compila. Si sostituisce nelle prove (vedi il
  /// costruttore): la macchina di chi le lancia non è quella di Giacomo.
  Future<bool> _conKvm() async {
    try {
      final r = await Process.run('test', ['-r', '/dev/kvm', '-a', '-w', '/dev/kvm']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Avvia il kernel appena impacchettato in QEMU, con l'initramfs minimo di
  /// `prova_avvio.dart`, e scrive com'è andata in `fucina.json`: un kernel
  /// che non è partito non si installa (`FucinaService.installa`).
  ///
  /// Tre esiti, non due. **Partito**; **non partito**, e la compilazione
  /// finisce in errore; **non so**: QEMU non c'è, o il kernel è compilato
  /// per QUESTO processore e non c'è KVM per dargli il processore vero —
  /// l'emulazione può non avere le sue istruzioni, e un fallimento lì non
  /// direbbe niente del kernel.
  Future<String?> _provaAvvio(Ricetta r, Cartelle c, List<String> avvisi) async {
    final rel = r.rilascio;
    final initramfs = File('$lavoro/prova-avvio.cpio');
    await initramfs.writeAsBytes(initramfsMinimo());
    final kvm = await (conKvm ?? _conKvm)();
    final t0 = DateTime.now();
    final righe = <String>[];
    _riga(kvm ? 'Con KVM: il processore vero (-cpu host).'
        : 'Senza KVM: emulazione (-cpu max), più lenta.');
    final limite = Duration(seconds: kvm ? 120 : 600);
    final esito = await _lanciaConCodice(
        comandoQemu(
            kernel: '${c.uscita}/boot/vmlinuz-$rel',
            initramfs: initramfs.path,
            kvm: kvm),
        lavoro,
        raccogli: righe,
        limite: limite);
    final secondi = DateTime.now().difference(t0).inSeconds;
    bool? ok;
    var perche = '';
    // Con `setsid` davanti, un QEMU che non c'è non è un'eccezione: è
    // `setsid` che esce con 127 (126 se c'è ma non si esegue).
    if (esito.codice == 127 || esito.codice == 126) {
      ok = null;
      perche = 'manca QEMU (su Arch: pacman -S qemu-system-x86)';
    } else if (esito.codice == null) {
      if (_annullato) return 'Fermata.';
      perche = esito.errore ?? '';
      if (perche.startsWith('Non riesco ad avviare')) {
        perche = 'manca QEMU (su Arch: pacman -S qemu-system-x86)';
      } else {
        ok = false; // scaduto: un kernel piantato prima di /init
      }
    } else if (riuscita(esito.codice!, righe)) {
      ok = true;
    } else {
      ok = false;
      // L'ultima riga che dice qualcosa: di solito il panico.
      perche = righe.lastWhere(
          (l) => l.contains('panic') || l.contains('Panic'),
          orElse: () => righe.isEmpty
              ? 'nessuna riga sulla console (codice ${esito.codice})'
              : righe.last).trim();
    }
    if (ok == false) {
      if (r.scelte.nativo && !kvm) {
        ok = null;
        perche = 'kernel per questo processore senza KVM: l\'emulazione può non '
            'avere le sue istruzioni ($perche)';
      }
    }
    await _segnaProvaAvvio(c, {
      'ok': ok,
      'secondi': secondi,
      'kvm': kvm,
      'perche': perche,
    });
    if (ok == true) {
      _riga('Partito: arrivato allo spazio utente in $secondi s.');
      return null;
    }
    if (ok == null) {
      final a = 'Prova d\'avvio non fatta: $perche.';
      _riga('⚠ $a');
      avvisi.add(a);
      return null;
    }
    return 'Il kernel non arriva allo spazio utente in QEMU ($perche): non '
        'installarlo. Il diario ha le ultime righe della sua console.';
  }

  Future<void> _segnaProvaAvvio(Cartelle c, Map<String, dynamic> prova) async {
    final f = File('${c.uscita}/fucina.json');
    try {
      final j = (jsonDecode(await f.readAsString()) as Map).cast<String, dynamic>();
      j['provaAvvio'] = prova;
      await f.writeAsString(const JsonEncoder.withIndent('  ').convert(j));
    } catch (_) {}
  }

  /// Come [_lancia], ma dice il codice d'uscita invece di giudicarlo (per
  /// QEMU 0 e 99 vogliono dire cose diverse, e nessuno dei due è un errore
  /// di per sé), e ferma il processo dopo `limite`. `codice` è null se il
  /// processo non è partito, è stato fermato o è scaduto: allora `errore`
  /// dice perché.
  Future<({int? codice, String? errore})> _lanciaConCodice(
      List<String> comando, String cartella,
      {List<String>? raccogli, required Duration limite}) async {
    var codice = -1;
    var scaduto = false;
    final e = await _lancia(comando, cartella,
        raccogli: raccogli,
        limite: limite,
        quandoScade: () => scaduto = true,
        codiceVisto: (c) => codice = c,
        tuttiBuoni: true);
    if (scaduto) {
      return (codice: null,
          errore: 'tempo scaduto (${limite.inSeconds} s) senza arrivare allo '
              'spazio utente');
    }
    if (e != null) return (codice: null, errore: e);
    return (codice: codice, errore: null);
  }

  /// Lancia un comando e ne racconta l'uscita riga per riga.
  ///
  /// `invii`: `localmodconfig` può fare domande sulle opzioni nuove, e
  /// senza qualcuno che risponda aspetterebbe per sempre. Si danno quattromila
  /// «invio», cioè «il valore di serie» a quattromila domande: più di quante
  /// Kconfig ne possa fare, meno di quanto stia nel tubo senza bloccarsi.
  ///
  /// `raccogli`: le righe dell'uscita normale finiscono anche qui.
  Future<String?> _lancia(List<String> comando, String cartella,
      {bool invii = false,
      List<String>? raccogli,
      Duration? limite,
      void Function()? quandoScade,
      void Function(int)? codiceVisto,
      bool tuttiBuoni = false}) async {
    if (_annullato) return 'Fermata.';
    var eseguibile = comando.first;
    if (eseguibile.startsWith('scripts/')) eseguibile = '$cartella/$eseguibile';
    final argomenti = comando.sublist(1);
    final Process p;
    try {
      p = _conSetsid
          ? await lancia('setsid', [eseguibile, ...argomenti],
              workingDirectory: cartella)
          : await lancia(eseguibile, argomenti, workingDirectory: cartella);
    } on ProcessException catch (e) {
      return 'Non riesco ad avviare «${comando.first}»: ${e.message}. È '
          'installato?';
    }
    _processo = p;
    // «Ferma» può arrivare mentre il processo sta ancora nascendo: `ferma()`
    // non trova niente da fermare, e un `make` che parte dopo lavorerebbe per
    // un'ora con la compilazione già «fermata». Trovato da una prova che
    // premeva «ferma» un istante dopo l'avvio del passo.
    if (_annullato) unawaited(_segnale(p.pid, 'TERM'));
    final ultime = <String>[];
    void ascolta(String r, bool err) {
      _riga(r);
      if (!err) raccogli?.add(r);
      if (err || r.contains('rror')) {
        ultime.add(r);
        if (ultime.length > 20) ultime.removeAt(0);
      }
    }

    final a = p.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((r) => ascolta(r, false))
        .asFuture<void>();
    final b = p.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((r) => ascolta(r, true))
        .asFuture<void>();
    try {
      if (invii) p.stdin.add(List.filled(4000, 10));
      await p.stdin.close();
    } catch (_) {
      // Il processo ha chiuso l'ingresso senza leggerlo: va bene così.
    }
    // Un limite di tempo, per chi può non finire mai da solo (QEMU con un
    // kernel che si pianta senza andare in panico).
    final sveglia = limite == null
        ? null
        : Timer(limite, () {
            quandoScade?.call();
            unawaited(_segnale(p.pid, 'KILL'));
          });
    final codice = await p.exitCode;
    sveglia?.cancel();
    await a;
    await b;
    _processo = null;
    if (_annullato) return 'Fermata.';
    codiceVisto?.call(codice);
    if (codice == 0 || tuttiBuoni) return null;
    final errore = ultime.lastWhere(
        (r) => r.contains('rror') || r.contains('rrore'),
        orElse: () => ultime.isEmpty ? '' : ultime.last);
    return '«${comando.first}» è uscito con $codice'
        '${errore.isEmpty ? '' : ': $errore'}';
  }


  /// I byte liberi nel filesystem della cartella di lavoro, da `df`. `null`
  /// se non si riesce a saperlo: in quel caso si parte lo stesso, perché un
  /// controllo che non sa rispondere non deve fermare niente.
  Future<int?> _spazioLibero() async {
    try {
      await Directory(lavoro).create(recursive: true);
      final r = await Process.run('df', ['--output=avail', '-B1', lavoro]);
      if (r.exitCode != 0) return null;
      final righe = '${r.stdout}'.trim().split('\n');
      return int.tryParse(righe.last.trim());
    } catch (_) {
      return null;
    }
  }

  // ── Le misure ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _leggiMisure() async {
    try {
      final t = await File('$statoDir/misure.json').readAsString();
      return (jsonDecode(t) as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  Future<void> _scriviMisure(Map<String, dynamic> m) async {
    try {
      await Directory(statoDir).create(recursive: true);
      await File('$statoDir/misure.json').writeAsString(jsonEncode(m));
    } catch (_) {}
  }
}
