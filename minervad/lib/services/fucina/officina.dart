import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
    );
  }

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

  Map<String, dynamic> stato() => {
        'inCorso': _inCorso,
        'rilascio': _rilascio,
        'passo': _passo,
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

    // ── Prima di tutto, lo spazio ──────────────────────────────────────
    //
    // Un albero del kernel con la compilazione dentro occupa da tre a
    // quindici gigabyte, a seconda di quanti moduli restano. Scoprirlo a
    // metà, con il disco pieno e `make` che scrive errori incomprensibili, è
    // il modo peggiore: lo si dice prima di scaricare.
    final libero = await _spazioLibero();
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
        return _scarica(r.scelte.versione);
      case 'estrai':
        return _estrai(r.scelte.versione, base, c.albero);
      case 'patch':
        return _patch(r.scelte.versione, c.albero);
      case 'base':
        if (p.comando.isNotEmpty) return _lancia(p.comando, c.albero);
        return _base(rilievo.configPartenza, c.albero);
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
      default:
        if (p.comando.isEmpty) return null;
        return _lancia(p.comando, c.albero);
    }
  }

  Future<String?> _scarica(String versione) async {
    final archivi = '$lavoro/archivi';
    final nome = 'linux-$versione.tar.xz';
    final file = File('$archivi/$nome');

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
        return null;
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
    return null;
  }

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

  Future<String?> _estrai(String versione, String base, String albero) async {
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
    final e = await _lancia(
        ['tar', '-xf', '$lavoro/archivi/linux-$versione.tar.xz', '-C', base],
        base);
    if (e != null) return e;
    if (!await File('$albero/Makefile').exists()) {
      return 'L\'archivio non contiene linux-$versione/Makefile.';
    }
    return null;
  }

  Future<String?> _patch(String versione, String albero) async {
    final serie = serieDi(versione);
    for (final u in Sorgenti.patchCachyos(serie)) {
      final nome = 'cachyos-$serie-${u.pathSegments.last}';
      final f = File('$lavoro/archivi/$nome');
      _riga('Scarico ${u.pathSegments.last}.');
      final e = await scarica(u, f, annullato: () => _annullato);
      if (e != null) {
        return 'CachyOS non ha (o non ha ancora) le patch per la serie '
            '$serie: $e';
      }
      final prova =
          await _lancia(['patch', '-Np1', '--dry-run', '-i', f.path], albero);
      if (prova != null) {
        return '${u.pathSegments.last} non si applica a linux-$versione. Le '
            'patch di CachyOS seguono l\'ultima versione della serie: prova '
            'quella.';
      }
      final e2 = await _lancia(['patch', '-Np1', '-i', f.path], albero);
      if (e2 != null) return e2;
    }
    return null;
  }

  Future<String?> _base(String partenza, String albero) async {
    if (partenza.isEmpty) {
      return 'Non c\'è una configurazione del kernel in uso da cui partire.';
    }
    final vero = '$radice${partenza.substring(1)}';
    final byte = await File(vero).readAsBytes();
    final testo = partenza.endsWith('.gz') ? gzip.decode(byte) : byte;
    await File('$albero/.config').writeAsBytes(testo);
    _riga('Configurazione di partenza: $partenza.');
    return null;
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

    await File('${c.uscita}/fucina.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert({
      'rilascio': rel,
      'scelte': r.scelte.toJson(),
      'moduli': r.moduli.length,
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

  /// Lancia un comando e ne racconta l'uscita riga per riga.
  ///
  /// `invii`: `localmodconfig` può fare domande sulle opzioni nuove, e
  /// senza qualcuno che risponda aspetterebbe per sempre. Si danno quattromila
  /// «invio», cioè «il valore di serie» a quattromila domande: più di quante
  /// Kconfig ne possa fare, meno di quanto stia nel tubo senza bloccarsi.
  ///
  /// `raccogli`: le righe dell'uscita normale finiscono anche qui.
  Future<String?> _lancia(List<String> comando, String cartella,
      {bool invii = false, List<String>? raccogli}) async {
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
    final codice = await p.exitCode;
    await a;
    await b;
    _processo = null;
    if (_annullato) return 'Fermata.';
    if (codice == 0) return null;
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
