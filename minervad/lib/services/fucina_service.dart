import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/minerva_paths.dart';
import 'fucina/officina.dart';
import 'fucina/blocco_lavoro.dart';
import 'fucina/profili_kernel.dart';
import 'fucina/ricetta.dart';
import 'fucina/rilievo.dart';
import 'fucina/regole_moduli.dart';
import 'fucina/scaffale.dart';
import 'fucina/storico_dispositivi.dart';
import 'fucina/sorgenti.dart';

/// Minerva Fucina — kernel su misura per questo computer.
///
/// ── Da dove nasce ──────────────────────────────────────────────────────────
///
/// il manutentore, 30 settembre 2026: «vorrei inserire una utility per creare
/// kernel [...] ultra snelli e ottimizzati per il computer, con i moduli
/// necessari per leggere tutto l'hardware e solamente i moduli per leggere
/// tutti i vari file system, controller di gioco [...] in modo per avere un
/// kernel più snello possibile e quindi meno attaccabile a livello di
/// sicurezza». E: «durante lo sviluppo perdere un'ora per una prova non è
/// giusto».
///
/// ── Com'è divisa ───────────────────────────────────────────────────────────
///
/// | pezzo                  | che cosa fa                                    |
/// |------------------------|------------------------------------------------|
/// | `fucina/rilievo.dart`  | guarda la macchina, non tocca niente           |
/// | `fucina/alias.dart`    | chi guida quale dispositivo (`modules.alias`)  |
/// | `fucina/catalogo.dart` | famiglie, scorte, preset: tutto dichiarato     |
/// | `fucina/ricetta.dart`  | dalle scelte al piano, funzione pura           |
/// | `fucina/sorgenti.dart` | kernel.org e CachyOS, con la somma di controllo|
/// | `fucina/officina.dart` | esegue il piano e racconta                     |
/// | `fucina/scaffale.dart` | i kernel nostri, e la verifica al primo avvio  |
/// | `fucina/albero.dart`   | quale simbolo di Kconfig costruisce un modulo  |
/// | `fucina/prova_avvio.dart` | il kernel nuovo avviato in QEMU, prima di /boot |
///
/// Questo file li tiene insieme e basta: è quello che il server chiama.
///
/// ── Il confine con root ────────────────────────────────────────────────────
///
/// Tutto quello che sta qui gira come te, nella tua cartella di cache.
/// Installare e togliere un kernel toccano `/boot` e `/usr/lib/modules`, e
/// passano dall'aiutante di root (`scripts/minerva-radice`, verbi
/// `fucina-installa` e `fucina-togli`), che ricontrolla tutto da capo e non
/// accetta nomi che non comincino per `-fucina-`.
class FucinaService {
  final String lavoro;
  final String statoDir;
  final Officina officina;
  final Scaffale scaffale;
  final Sorgenti sorgenti;
  final StoricoDispositivi storicoDispositivi;
  final ProfiliKernel profiliKernel;
  final RegoleModuli regoleModuli;

  /// L'aiutante di root: `RadiceService.chiedi`. Una funzione, non il
  /// servizio: questo file non sa nemmeno che cosa sia `pkexec`.
  final Future<Map<String, dynamic>> Function(String, List<String>) radice;
  final Future<Map<String, dynamic>> Function()? statoAmministrazione;
  final Future<List<Map<String, dynamic>>> Function(Map<String, dynamic>)?
  targetCompilatori;
  final Future<Map<String, dynamic>> Function()? risorseCompilazione;

  /// Come si costruisce un rilevatore. Si sostituisce nelle prove.
  final Rilevatore Function(
    void Function(String, String, int, int)? racconta,
    List<String> modaliasStorici,
  )
  nuovoRilevatore;

  /// Lancia un programma e ne aspetta la fine (llvm-profgen,
  /// llvm-profdata). Si sostituisce nelle prove.
  final Future<ProcessResult> Function(String, List<String>) esegui;

  FucinaService({
    required this.radice,
    this.statoAmministrazione,
    this.targetCompilatori,
    this.risorseCompilazione,
    String? lavoro,
    String? statoDir,
    Officina? officina,
    Scaffale? scaffale,
    Sorgenti? sorgenti,
    StoricoDispositivi? storicoDispositivi,
    ProfiliKernel? profiliKernel,
    RegoleModuli? regoleModuli,
    Rilevatore Function(
      void Function(String, String, int, int)? racconta,
      List<String> modaliasStorici,
    )?
    nuovoRilevatore,
    Future<ProcessResult> Function(String, List<String>)? esegui,
  }) : lavoro = lavoro ?? '${MinervaPaths.cache()}/fucina',
       esegui = esegui ?? ((e, a) => Process.run(e, a)),
       statoDir = statoDir ?? '${MinervaPaths.stato()}/fucina',
       sorgenti = sorgenti ?? Sorgenti(),
       storicoDispositivi =
           storicoDispositivi ??
           StoricoDispositivi(
             statoDir: statoDir ?? '${MinervaPaths.stato()}/fucina',
           ),
       profiliKernel =
           profiliKernel ??
           ProfiliKernel(
             statoDir: statoDir ?? '${MinervaPaths.stato()}/fucina',
           ),
       regoleModuli =
           regoleModuli ??
           RegoleModuli(statoDir: statoDir ?? '${MinervaPaths.stato()}/fucina'),
       nuovoRilevatore =
           nuovoRilevatore ??
           ((r, alias) => Rilevatore(racconta: r, modaliasStorici: alias)),
       officina =
           officina ??
           Officina(
             lavoro: lavoro ?? '${MinervaPaths.cache()}/fucina',
             statoDir: statoDir ?? '${MinervaPaths.stato()}/fucina',
             sorgenti: sorgenti,
           ),
       scaffale =
           scaffale ??
           Scaffale(
             lavoro: lavoro ?? '${MinervaPaths.cache()}/fucina',
             statoDir: statoDir ?? '${MinervaPaths.stato()}/fucina',
           );

  // ── Il rilievo, ricordato per un po' ─────────────────────────────────
  //
  // La ricetta si ricalcola a ogni spunta (la finestra mostra il piano mentre
  // si sceglie), e rifare il rilievo ogni volta vorrebbe dire rileggere tutto
  // `/sys` per ogni clic. Dieci minuti: abbastanza per scegliere con calma,
  // poco perché una chiavetta collegata nel frattempo resti fuori a lungo.
  // «Rileggi» lo rifà subito.

  Rilievo? _rilievo;
  DateTime? _quando;
  static const Duration _vale = Duration(minutes: 10);

  Future<Rilievo> _rilievoFresco({
    void Function(String, String, int, int)? racconta,
    bool forza = false,
  }) async {
    final r = _rilievo;
    final q = _quando;
    if (!forza &&
        r != null &&
        q != null &&
        DateTime.now().difference(q) < _vale) {
      return r;
    }
    final aliasStorici = await storicoDispositivi.leggi();
    final nuovo = await nuovoRilevatore(racconta, aliasStorici).rileva();
    try {
      await storicoDispositivi.aggiorna(
        nuovo.dispositivi.map((d) => d.modalias),
      );
    } catch (_) {
      nuovo.avvisi.add(
        'Non sono riuscito ad aggiornare lo storico locale delle '
        'periferiche; il rilievo corrente resta valido.',
      );
    }
    _rilievo = nuovo;
    _quando = DateTime.now();
    _dimentica();
    return nuovo;
  }

  /// Passati i dieci minuti il rilievo si lascia andare davvero. Prima
  /// «valeva dieci minuti» ma restava in memoria per tutta la sessione:
  /// aperta la Fucina una volta, il demone se lo portava dietro fino al
  /// logout (4 ottobre 2026).
  Timer? _scadenza;
  void _dimentica() {
    _scadenza?.cancel();
    _scadenza = Timer(_vale, () {
      _rilievo = null;
      _quando = null;
      _versioni = null;
      _versioniQuando = null;
      _scadenza = null;
    });
  }

  Future<Map<String, dynamic>> rileva(
    void Function(String, String, int, int)? racconta,
  ) async {
    final r = await _rilievoFresco(racconta: racconta, forza: true);
    return {
      'ok': true,
      ...r.toJson(),
      'targetCompilatori': targetCompilatori == null
          ? <Map<String, dynamic>>[]
          : await targetCompilatori!(r.macchina),
      'regoleModuli': await regoleModuli.elenco(),
    };
  }

  Future<Map<String, dynamic>> impostaRegolaModulo(
    Object? nome,
    Object? scelta,
  ) async {
    try {
      if (scelta == 'escludi' && nome is String) {
        final rilievo = await _rilievoFresco();
        if (rilievo.avvio.moduli.contains(nome.replaceAll('-', '_'))) {
          return {
            'ok': false,
            'errore':
                'Questo modulo è necessario per avviare il sistema e non può essere escluso.',
          };
        }
      }
      return await regoleModuli.imposta(nome, scelta);
    } on FileSystemException catch (e) {
      return {'ok': false, 'errore': e.message};
    } catch (_) {
      return {
        'ok': false,
        'errore': 'Non riesco a salvare la regola del modulo.',
      };
    }
  }

  Future<Map<String, dynamic>> regoleModuliCorrenti() async => {
    'ok': true,
    'regole': await regoleModuli.elenco(),
  };

  /// Salva su richiesta un report diagnostico locale. I report sono JSON,
  /// non includono percorsi personali o seriali e sono limitati agli ultimi
  /// dieci rilievi.
  Future<Map<String, dynamic>> esportaRilievo() async {
    try {
      final rilievo = await _rilievoFresco();
      final ora = DateTime.now().toUtc();
      final id = ora
          .toIso8601String()
          .replaceAll(RegExp(r'[-:.]'), '')
          .replaceAll('T', '-')
          .replaceAll('Z', '');
      final cartella = Directory('$statoDir/rapporti');
      await cartella.create(recursive: true);
      final file = File('${cartella.path}/rilievo-$id.json');
      final temporaneo = File('${file.path}.tmp-$pid');
      await temporaneo.writeAsString(
        const JsonEncoder.withIndent(
          '  ',
        ).convert(rilievo.rapportoJson(generato: ora)),
        flush: true,
      );
      await temporaneo.rename(file.path);

      final rapporti = <File>[];
      await for (final voce in cartella.list(followLinks: false)) {
        if (voce is File &&
            voce.uri.pathSegments.last.startsWith('rilievo-') &&
            voce.path.endsWith('.json')) {
          rapporti.add(voce);
        }
      }
      rapporti.sort((a, b) => b.path.compareTo(a.path));
      for (final vecchio in rapporti.skip(10)) {
        await vecchio.delete();
      }
      return {
        'ok': true,
        'percorso': file.path,
        'dispositivi': rilievo.dispositivi.length,
        'moduli': rilievo.moduli.length,
      };
    } on Object {
      return {
        'ok': false,
        'errore': 'Non riesco a salvare il report locale del rilievo.',
      };
    }
  }

  Future<Map<String, dynamic>> dimenticaDispositivi() async {
    try {
      await storicoDispositivi.dimentica();
      return {'ok': true};
    } catch (_) {
      return {
        'ok': false,
        'errore': 'Non riesco a cancellare lo storico locale.',
      };
    }
  }

  Future<Map<String, dynamic>> profili() async => {
    'ok': true,
    'profili': await profiliKernel.elenco(),
  };

  Future<Map<String, dynamic>> salvaProfilo(Object? nome, Object? raw) async {
    try {
      if (nome is! String) {
        return {'ok': false, 'errore': 'Inserisci un nome per il profilo.'};
      }
      if (raw is! Map) {
        return {'ok': false, 'errore': 'Scelte del profilo non valide.'};
      }
      final r = await _rilievoFresco();
      final richieste = Map<String, dynamic>.from(raw);
      // Un profilo conserva le preferenze, non la versione o il nome del
      // prossimo kernel. I segnaposto servono solo alla validazione comune.
      richieste['versione'] = '6.0';
      richieste['nome'] = 'profilo';
      richieste['profilo'] = '';
      richieste['provaVeloce'] = false;
      richieste['misura'] = true;
      final scelte = Scelte.daJson(richieste).toJson()
        ..remove('versione')
        ..remove('nome')
        ..remove('profilo')
        ..remove('provaVeloce');
      final live = r.configKernel['statoLive'];
      final filesystem = live is Map && live['filesystemMontati'] is List
          ? List<String>.from(live['filesystemMontati'] as List)
          : <String>[];
      final lsm = live is Map && live['lsmAttivi'] is List
          ? List<String>.from(live['lsmAttivi'] as List)
          : <String>[];
      final macchina = r.macchina;
      final salvato = await profiliKernel.salva(
        nome: nome,
        scelte: scelte,
        hardware: {
          'cpu': macchina['cpu'],
          'fornitore': macchina['fornitore'],
          'livelloX86': macchina['livelloX86'],
        },
        evidenze: {
          'dispositivi': r.dispositivi.length,
          'moduli': r.moduli.length,
          'dispositiviStorici': r.dispositiviStorici,
          'filesystemMontati': filesystem,
          'lsmAttivi': lsm,
        },
      );
      return {
        'ok': true,
        'profilo': salvato,
        'profili': await profiliKernel.elenco(),
      };
    } on SceltaNonValida catch (e) {
      return {'ok': false, 'errore': e.messaggio};
    } on FormatException catch (e) {
      return {'ok': false, 'errore': e.message};
    } on FileSystemException catch (e) {
      return {'ok': false, 'errore': e.message};
    } catch (_) {
      return {'ok': false, 'errore': 'Non riesco a salvare il profilo locale.'};
    }
  }

  Future<Map<String, dynamic>> caricaProfilo(Object? id) async {
    try {
      final profilo = await profiliKernel.carica(id);
      if (profilo == null) {
        return {'ok': false, 'errore': 'Profilo non trovato.'};
      }
      final scelte = profilo['scelte'];
      if (scelte is! Map) {
        return {'ok': false, 'errore': 'Il profilo è danneggiato.'};
      }
      final r = await _rilievoFresco();
      final hardware = profilo['hardware'] is Map
          ? Map<String, dynamic>.from(profilo['hardware'] as Map)
          : <String, dynamic>{};
      final vecchiaCpu = hardware['cpu'];
      final cpuCorrente = r.macchina['cpu'];
      final fornitoreSalvato = hardware['fornitore'];
      final fornitoreCorrente = r.macchina['fornitore'];
      final livelloSalvato = hardware['livelloX86'];
      final livelloCorrente = r.macchina['livelloX86'];
      final stessaCpu =
          r.macchina['flagsCpuUniformi'] != false &&
          r.macchina['flagsCpuCompleti'] != false &&
          vecchiaCpu is String &&
          vecchiaCpu.isNotEmpty &&
          cpuCorrente is String &&
          cpuCorrente.isNotEmpty &&
          vecchiaCpu == cpuCorrente &&
          fornitoreSalvato is String &&
          fornitoreSalvato.isNotEmpty &&
          fornitoreSalvato == fornitoreCorrente &&
          livelloSalvato is String &&
          livelloSalvato.isNotEmpty &&
          livelloSalvato == livelloCorrente;
      return {
        'ok': true,
        'profilo': profilo,
        'scelte': Map<String, dynamic>.from(scelte),
        'nativoCompatibile': stessaCpu,
        'avvisoHardware': stessaCpu
            ? ''
            : 'CPU non verificata come compatibile: disattivo '
                  'l’ottimizzazione nativa.',
      };
    } catch (_) {
      return {'ok': false, 'errore': 'Non riesco a leggere il profilo locale.'};
    }
  }

  Future<Map<String, dynamic>> eliminaProfilo(Object? id) async {
    try {
      final eliminato = await profiliKernel.elimina(id);
      return {
        'ok': eliminato,
        'profili': await profiliKernel.elenco(),
        if (!eliminato) 'errore': 'Profilo non trovato.',
      };
    } on FileSystemException catch (e) {
      return {'ok': false, 'errore': e.message};
    }
  }

  Map<String, dynamic>? _versioni;
  DateTime? _versioniQuando;

  Future<Map<String, dynamic>> versioni() async {
    final v = _versioni;
    final q = _versioniQuando;
    if (v != null && q != null && DateTime.now().difference(q) < _vale) {
      return v;
    }
    final nuove = await sorgenti.versioni();
    if (nuove['ok'] == true) {
      _versioni = nuove;
      _versioniQuando = DateTime.now();
      _dimentica();
    }
    return nuove;
  }

  // ── La ricetta ───────────────────────────────────────────────────────

  Future<({Ricetta? ricetta, Rilievo? rilievo, String? errore})> _calcola(
    Object? scelte,
  ) async {
    if (scelte is! Map) {
      return (ricetta: null, rilievo: null, errore: 'Mancano le scelte.');
    }
    final scelteRaw = Map<String, dynamic>.from(scelte);
    final regole = await regoleModuli.elenco();
    final mantieni = Set<String>.from(regole['mantieni'] ?? const <String>[]);
    final escludi = Set<String>.from(regole['escludi'] ?? const <String>[]);
    final aggiunti = {
      if (scelteRaw['aggiunti'] is List)
        ...(scelteRaw['aggiunti'] as List).whereType<String>(),
    };
    final tolti = {
      if (scelteRaw['tolti'] is List)
        ...(scelteRaw['tolti'] as List).whereType<String>(),
    };
    tolti.removeAll(mantieni);
    tolti.addAll(escludi);
    aggiunti.removeAll(escludi);
    aggiunti.addAll(mantieni);
    scelteRaw['aggiunti'] = aggiunti.toList();
    scelteRaw['tolti'] = tolti.toList();

    final Scelte s;
    try {
      s = Scelte.daJson(scelteRaw);
    } on SceltaNonValida catch (e) {
      return (ricetta: null, rilievo: null, errore: e.messaggio);
    }
    final r = await _rilievoFresco();
    if (s.nativo &&
        (r.macchina['flagsCpuUniformi'] == false ||
            r.macchina['flagsCpuCompleti'] == false)) {
      return (
        ricetta: null,
        rilievo: r,
        errore:
            'I flag delle CPU non sono uniformi o completi. Usa il target generico: native non è verificabile su tutte le CPU descritte.',
      );
    }
    final ccache = (r.macchina['attrezzi'] as List? ?? const []).any(
      (a) => a is Map && a['nome'] == 'ccache' && a['presente'] == true,
    );
    final ricetta = calcola(
      r,
      s,
      Officina.cartellePer(s, lavoro),
      nuclei: (r.macchina['nuclei'] as int?) ?? 1,
      ccache: ccache,
      risorse: risorseCompilazione == null
          ? const {}
          : await risorseCompilazione!(),
    );
    return (ricetta: ricetta, rilievo: r, errore: null);
  }

  Future<Map<String, dynamic>> ricetta(Object? scelte) async {
    final c = await _calcola(scelte);
    if (c.errore != null) return {'ok': false, 'errore': c.errore};
    return {'ok': true, ...c.ricetta!.toJson()};
  }

  /// Avvia la compilazione. Le scelte arrivano di nuovo e la ricetta si
  /// ricalcola qui: quella mostrata nella finestra non viaggia sul canale.
  Future<Map<String, dynamic>> avvia(Object? scelte) async {
    if (officina.inCorso) {
      return {'ok': false, 'errore': 'C\'è già una compilazione in corso.'};
    }
    if (_installando) {
      return {
        'ok': false,
        'errore':
            'Aspetta che finisca l\'installazione in corso: compilare '
            'adesso riscriverebbe i file che si stanno installando.',
      };
    }
    final c = await _calcola(scelte);
    if (c.errore != null) return {'ok': false, 'errore': c.errore};
    final ricetta = c.ricetta!;
    if (ricetta.requisitiMancanti.isNotEmpty) {
      final pacchetti = ricetta.requisitiMancanti.join(' ');
      return {
        'ok': false,
        'errore':
            'Mancano i prerequisiti per compilare: '
            '${ricetta.requisitiMancanti.join(', ')}. Installali con '
            '`sudo pacman -S --needed $pacchetti`, poi riprova.',
        'requisitiMancanti': ricetta.requisitiMancanti,
      };
    }
    return officina.avvia(ricetta, c.rilievo!);
  }

  Future<Map<String, dynamic>> ferma() async {
    final era = officina.inCorso;
    await officina.ferma();
    return {'ok': true, 'eraInCorso': era};
  }

  // ── Lo scaffale ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> kernel() async => {
    'ok': true,
    ...await scaffale.elenco(),
    'cache': await _statoCache(),
    if (statoAmministrazione != null)
      'amministrazione': await statoAmministrazione!(),
  };

  /// Inventario leggero della cache: non attraversa gli alberi dei sorgenti,
  /// che possono contenere centinaia di migliaia di file.
  Future<Map<String, dynamic>> _statoCache() async {
    String nomePercorso(String percorso) => percorso
        .split(Platform.pathSeparator)
        .where((parte) => parte.isNotEmpty)
        .last;

    final archivi = <Map<String, dynamic>>[];
    final archivioDir = Directory('$lavoro/archivi');
    try {
      await for (final elemento in archivioDir.list(followLinks: false)) {
        if (elemento is! File ||
            !(elemento.path.endsWith('.tar.xz') ||
                elemento.path.endsWith('.tar.gz'))) {
          continue;
        }
        final nome = nomePercorso(elemento.path);
        final stamp = File('${elemento.path}.firma-verificata');
        archivi.add({
          'nome': nome,
          'byte': (await elemento.stat()).size,
          'verificato': await stamp.exists(),
        });
      }
    } on FileSystemException {
      // La cache vuota è uno stato normale al primo avvio.
    }
    archivi.sort((a, b) => '${a['nome']}'.compareTo('${b['nome']}'));

    final alberi = <Map<String, dynamic>>[];
    final alberiDir = Directory('$lavoro/alberi');
    try {
      await for (final base in alberiDir.list(followLinks: false)) {
        if (base is! Directory) continue;
        final nome = nomePercorso(base.path);
        final pronti = await File('${base.path}/.fucina-pronto').exists();
        var versione = '';
        var sorgentiPresenti = false;
        try {
          await for (final albero in base.list(followLinks: false)) {
            if (albero is Directory &&
                File('${albero.path}/Makefile').existsSync()) {
              sorgentiPresenti = true;
              versione = nomePercorso(albero.path);
              break;
            }
          }
        } on FileSystemException {
          // La directory può essere stata rimossa durante l'inventario.
        }
        alberi.add({
          'nome': nome,
          'versione': versione,
          'sorgentiPresenti': sorgentiPresenti,
          'pronto': pronti && sorgentiPresenti,
        });
      }
    } on FileSystemException {
      // Nessun albero scaricato finora.
    }
    alberi.sort((a, b) => '${a['nome']}'.compareTo('${b['nome']}'));

    return {
      'percorso': lavoro,
      'percorsoArchivi': archivioDir.path,
      'percorsoAlberi': alberiDir.path,
      'archivi': archivi,
      'alberi': alberi,
      'recupero': await BloccoLavoro.verifica(lavoro),
    };
  }

  Future<Map<String, dynamic>> verifica() => scaffale.verifica();

  Future<Map<String, dynamic>> recuperaCache(Object? token) async {
    if (officina.inCorso || _installando || _rimuovendo) {
      return {'ok': false, 'errore': 'Attendi la fine del lavoro in corso.'};
    }
    try {
      return await BloccoLavoro.recupera(lavoro, token);
    } on FileSystemException catch (e) {
      return {'ok': false, 'errore': e.message};
    } on FormatException {
      return {
        'ok': false,
        'errore':
            'I dati del lavoro interrotto non sono validi. Il segnale viene conservato.',
      };
    } catch (e) {
      return {'ok': false, 'errore': 'Non posso riaprire la cache: $e'};
    }
  }

  /// Vero mentre l'aiutante di root sta installando. Si alza PRIMA del primo
  /// `await`: fra un `await` e l'altro il demone serve altri messaggi, e un
  /// «compila» arrivato in quel mezzo cancellerebbe la cartella d'uscita
  /// mentre root la sta leggendo. (Trovato da una revisione automatica.)
  bool _installando = false;
  bool _rimuovendo = false;

  /// Installa un kernel pronto. Arriva un NOME, mai un percorso: la cartella
  /// la ricava il demone, e l'aiutante di root la ricontrolla.
  Future<Map<String, dynamic>> installa(Object? rilascio) async {
    final rel = '${rilascio ?? ''}';
    if (!Scaffale.nostro(rel)) {
      return {'ok': false, 'errore': '«$rel» non è un kernel della Fucina.'};
    }
    if (officina.inCorso) {
      return {
        'ok': false,
        'errore': 'Aspetta che finisca la compilazione in corso.',
      };
    }
    if (_installando || _rimuovendo) {
      return {
        'ok': false,
        'errore': 'C\'è già un\'operazione sui kernel in corso.',
      };
    }
    _installando = true;
    BloccoLavoro? blocco;
    try {
      blocco = await BloccoLavoro.prendi(
        lavoro,
        tipo: 'installazione',
        dettagli: {'rilascio': rel},
      );
      final elenco = (await scaffale.elenco())['kernel'] as List;
      final voce = elenco.cast<Map>().where((k) => k['rilascio'] == rel);
      if (voce.isEmpty || voce.first['pronto'] != true) {
        final preparazione = voce.isEmpty ? null : voce.first['preparazione'];
        final blocchi = preparazione is Map ? preparazione['blocchi'] : null;
        return {
          'ok': false,
          'errore':
              '«$rel» non è pronto da installare.'
              '${blocchi is List && blocchi.isNotEmpty ? ' ${blocchi.join(' ')}' : ''}',
        };
      }
      if (rel == await scaffale.inUso()) {
        return {
          'ok': false,
          'errore':
              'È il kernel che stai usando adesso: riavvia su un altro prima di reinstallarlo.',
        };
      }
      // Un kernel che in QEMU non è arrivato allo spazio utente non va in
      // /boot: è la ragione per cui la prova esiste.
      final prova = voce.first['provaAvvio'];
      if (prova is Map && prova['ok'] == false) {
        return {
          'ok': false,
          'errore':
              '«$rel» non è partito nella prova d\'avvio in QEMU '
              '(${prova['perche'] ?? ''}): non lo installo. Ricompilalo, o '
              'rifai la prova.',
        };
      }
      final impedimento = await _impedimentoAmministrativo('installazione');
      if (impedimento != null) return {'ok': false, 'errore': impedimento};
      return await _conRadice('fucina-installa', ['$lavoro/uscita/$rel', rel]);
    } on FileSystemException catch (e) {
      return {'ok': false, 'errore': e.message};
    } finally {
      try {
        await blocco?.chiudi();
      } finally {
        _installando = false;
      }
    }
  }

  Future<Map<String, dynamic>> togli(Object? rilascio) async {
    final rel = '${rilascio ?? ''}';
    if (!Scaffale.nostro(rel)) {
      return {'ok': false, 'errore': '«$rel» non è un kernel della Fucina.'};
    }
    if (_installando || _rimuovendo) {
      return {
        'ok': false,
        'errore': 'C\'è già un\'operazione sui kernel in corso.',
      };
    }
    _rimuovendo = true;
    try {
      if (rel == await scaffale.inUso()) {
        return {
          'ok': false,
          'errore':
              'È il kernel che stai usando adesso: riavvia su un altro, '
              'poi toglilo.',
        };
      }
      final impedimento = await _impedimentoAmministrativo('rimozione');
      if (impedimento != null) return {'ok': false, 'errore': impedimento};
      return await _conRadice('fucina-togli', [rel]);
    } finally {
      _rimuovendo = false;
    }
  }

  Future<String?> _impedimentoAmministrativo(String azione) async {
    final leggi = statoAmministrazione;
    if (leggi == null) return null; // callback root sostituito nelle prove
    try {
      final info = await leggi();
      if (info['${azione}Possibile'] == true) return null;
      final controlli = info['controlli'];
      final messaggi = controlli is List
          ? controlli
                .whereType<Map>()
                .where(
                  (c) =>
                      c['ok'] != true &&
                      c['necessarioPer'] is List &&
                      (c['necessarioPer'] as List).contains(azione),
                )
                .map((c) => '${c['messaggio'] ?? ''}')
                .where((s) => s.isNotEmpty)
                .toList()
          : <String>[];
      return messaggi.isNotEmpty
          ? messaggi.join(' ')
          : 'I prerequisiti amministrativi non sono verificati. Aggiorna l’elenco e riprova.';
    } catch (_) {
      return 'Non riesco a verificare i prerequisiti amministrativi. Nessuna operazione avviata.';
    }
  }

  // ── Su misura del tuo uso: il profilo AutoFDO ────────────────────────
  //
  // il manutentore, 1° ottobre 2026: kernel «su misura del PC, con le ultime
  // tecnologie di compilazione». La più su misura di tutte è AutoFDO
  // (Linux 6.13, Clang 17+; llvm-profgen per la conversione dal LLVM 19):
  // Clang ottimizza il kernel sapendo quali rami prende davvero sul TUO
  // computer, con quello che fai tu. Due tempi:
  //
  //  1. **Pronto al profilo**: si compila con `AUTOFDO_CLANG` (scelta
  //     «autofdo»), si installa, ci si avvia. L'officina ha messo da parte
  //     il suo vmlinux.
  //  2. **Registra**: mentre usi il computer come sempre (o lanci un lavoro
  //     tipico), perf registra i salti del kernel per qualche minuto — da
  //     root, con l'aiutante (`fucina-profila`). Poi, come te,
  //     `llvm-profgen --kernel` lo converte col vmlinux. Più registrazioni
  //     si sommano (`llvm-profdata merge`): il profilo si fa sull'uso di più
  //     giorni, non di dieci minuti.
  //  3. **Ricompila col profilo** (scelta «profilo»: il NOME del kernel
  //     profilato): stessa configurazione, `CLANG_AUTOFDO_PROFILE` a ogni
  //     `make`.
  //
  // Che cosa NON fa, e perché: Propeller (6.13, Clang 19+) vorrebbe un
  // terzo giro — compilare col profilo AutoFDO, registrare di nuovo, e
  // convertire con `generate_propeller_profiles`, che non è in nessun
  // pacchetto di Arch o CachyOS. Senza poterlo provare su un processore con
  // LBR, un terzo giro scritto alla cieca sarebbe una promessa: resta fuori
  // e la ricetta lo spegne. Polly non c'entra col kernel: ottimizza nidi di
  // cicli su matrici (codice scientifico), e il kernel ne ha pochissimi e
  // pieni di dipendenze che Polly non tocca — e Kbuild non ha nessun
  // sostegno per lui.

  /// Dove l'aiutante di root lascia quello che registra perf. È scritto
  /// anche in `scripts/minerva-radice`, che non legge niente da fuori.
  static const String cartellaRegistrazioni = '/var/lib/minerva-fucina/profili';

  bool _profilando = false;

  Future<Map<String, dynamic>> profila(Object? rilascio, Object? minuti) async {
    final rel = '${rilascio ?? ''}';
    Map<String, dynamic> no(String e) => {'ok': false, 'errore': e};
    if (!Scaffale.nostro(rel)) {
      return no('«$rel» non è un kernel della Fucina.');
    }
    if (_profilando) return no('C\'è già una registrazione in corso.');
    final uso = await scaffale.inUso();
    if (rel != uso) {
      return no(
        'Il profilo di «$rel» si registra avviati su quel kernel: '
        'adesso stai usando «$uso». Riavvia su «$rel» e riprova.',
      );
    }
    final dir = Officina.profiliDi(lavoro, rel);
    if (!await File('$dir/vmlinux').exists()) {
      return no(
        '«$rel» non è pronto al profilo: non è stato compilato con '
        'AutoFDO, o il suo vmlinux non c\'è più ($dir).',
      );
    }
    final r = await _rilievoFresco();
    final hw = r.macchina['profilo'];
    if (hw is! Map || hw['possibile'] != true) {
      return no(
        'Su questo computer il profilo non si può registrare: '
        '${hw is Map ? hw['perche'] : 'non so dire perché.'}',
      );
    }
    final m = (minuti is num ? minuti.toInt() : int.tryParse('$minuti') ?? 10)
        .clamp(1, 60);
    _profilando = true;
    try {
      final esito = await _conRadice('fucina-profila', [
        '${m * 60}',
        '${hw['tipo']}',
      ]);
      if (esito['ok'] != true) return esito;
      final dati = '$cartellaRegistrazioni/$rel.data';
      if (!(esito['note'] as List).contains('fatto $dati')) {
        return no(
          'L\'aiutante ha registrato da un\'altra parte: '
          '${(esito['note'] as List).join(' ')}',
        );
      }
      final prof = File('$dir/autofdo.prof');
      final nuovo = '$dir/autofdo.prof.nuovo';
      var e = await _prova('llvm-profgen', [
        '--kernel',
        '--binary=$dir/vmlinux',
        '--perfdata=$dati',
        '-o',
        nuovo,
      ]);
      if (e != null) return no('La conversione del profilo non è riuscita: $e');
      final sommato = await prof.exists();
      if (sommato) {
        // Il profilo di oggi si somma a quelli di prima: i rami di chi apre
        // il browser e di chi compila stanno insieme.
        e = await _prova('llvm-profdata', [
          'merge',
          '--sample',
          '--extbinary',
          '-o',
          '$nuovo.somma',
          prof.path,
          nuovo,
        ]);
        if (e != null) {
          return no('Non riesco a sommare il profilo nuovo al vecchio: $e');
        }
        await File('$nuovo.somma').rename(prof.path);
        await File(nuovo).delete();
      } else {
        await File(nuovo).rename(prof.path);
      }
      return {
        'ok': true,
        'rilascio': rel,
        'minuti': m,
        'sommato': sommato,
        'byte': await prof.length(),
        'note': esito['note'],
      };
    } finally {
      _profilando = false;
    }
  }

  /// Lancia e aspetta. `null` se è andata, o le ultime righe dell'errore.
  Future<String?> _prova(String eseguibile, List<String> argomenti) async {
    try {
      final r = await esegui(eseguibile, argomenti);
      if (r.exitCode == 0) return null;
      final righe = '${r.stderr}'.trim().split('\n');
      return righe.skip(righe.length > 3 ? righe.length - 3 : 0).join(' ');
    } on ProcessException {
      return 'manca «$eseguibile» (su Arch è nel pacchetto llvm).';
    }
  }

  Future<Map<String, dynamic>> _conRadice(
    String verbo,
    List<String> argomenti,
  ) async {
    final esito = await radice(verbo, argomenti);
    final note = esito['uscita'] is List<int>
        ? utf8.decode(esito['uscita'] as List<int>, allowMalformed: true)
        : '';
    return {
      'ok': esito['ok'] == true,
      'annullato': esito['annullato'] == true,
      'errore': esito['ok'] == true ? '' : '${esito['error'] ?? ''}',
      'note': [
        for (final r in note.split('\n'))
          if (r.trim().isNotEmpty) r.trim(),
      ],
    };
  }
}
