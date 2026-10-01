import 'dart:convert';
import 'dart:io';

import '../core/minerva_paths.dart';
import 'fucina/officina.dart';
import 'fucina/ricetta.dart';
import 'fucina/rilievo.dart';
import 'fucina/scaffale.dart';
import 'fucina/sorgenti.dart';

/// Minerva Fucina — kernel su misura per questo computer.
///
/// ── Da dove nasce ──────────────────────────────────────────────────────────
///
/// Giacomo, 30 settembre 2026: «vorrei inserire una utility per creare
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

  /// L'aiutante di root: `RadiceService.chiedi`. Una funzione, non il
  /// servizio: questo file non sa nemmeno che cosa sia `pkexec`.
  final Future<Map<String, dynamic>> Function(String, List<String>) radice;

  /// Come si costruisce un rilevatore. Si sostituisce nelle prove.
  final Rilevatore Function(
          void Function(String, String, int, int)? racconta)
      nuovoRilevatore;

  /// Lancia un programma e ne aspetta la fine (llvm-profgen,
  /// llvm-profdata). Si sostituisce nelle prove.
  final Future<ProcessResult> Function(String, List<String>) esegui;

  FucinaService({
    required this.radice,
    String? lavoro,
    String? statoDir,
    Officina? officina,
    Scaffale? scaffale,
    Sorgenti? sorgenti,
    Rilevatore Function(void Function(String, String, int, int)?)?
        nuovoRilevatore,
    Future<ProcessResult> Function(String, List<String>)? esegui,
  })  : lavoro = lavoro ?? '${MinervaPaths.cache()}/fucina',
        esegui = esegui ?? ((e, a) => Process.run(e, a)),
        statoDir = statoDir ?? '${MinervaPaths.stato()}/fucina',
        sorgenti = sorgenti ?? Sorgenti(),
        nuovoRilevatore =
            nuovoRilevatore ?? ((r) => Rilevatore(racconta: r)),
        officina = officina ??
            Officina(
              lavoro: lavoro ?? '${MinervaPaths.cache()}/fucina',
              statoDir: statoDir ?? '${MinervaPaths.stato()}/fucina',
              sorgenti: sorgenti,
            ),
        scaffale = scaffale ??
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

  Future<Rilievo> _rilievoFresco(
      {void Function(String, String, int, int)? racconta,
      bool forza = false}) async {
    final r = _rilievo;
    final q = _quando;
    if (!forza &&
        r != null &&
        q != null &&
        DateTime.now().difference(q) < _vale) {
      return r;
    }
    final nuovo = await nuovoRilevatore(racconta).rileva();
    _rilievo = nuovo;
    _quando = DateTime.now();
    return nuovo;
  }

  Future<Map<String, dynamic>> rileva(
      void Function(String, String, int, int)? racconta) async {
    final r = await _rilievoFresco(racconta: racconta, forza: true);
    return {'ok': true, ...r.toJson()};
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
    }
    return nuove;
  }

  // ── La ricetta ───────────────────────────────────────────────────────

  Future<({Ricetta? ricetta, Rilievo? rilievo, String? errore})> _calcola(
      Object? scelte) async {
    if (scelte is! Map) {
      return (ricetta: null, rilievo: null, errore: 'Mancano le scelte.');
    }
    final Scelte s;
    try {
      s = Scelte.daJson(scelte.cast<String, dynamic>());
    } on SceltaNonValida catch (e) {
      return (ricetta: null, rilievo: null, errore: e.messaggio);
    }
    final r = await _rilievoFresco();
    final ccache = (r.macchina['attrezzi'] as List? ?? const []).any(
        (a) => a is Map && a['nome'] == 'ccache' && a['presente'] == true);
    final ricetta = calcola(r, s, Officina.cartellePer(s, lavoro),
        nuclei: (r.macchina['nuclei'] as int?) ?? 1, ccache: ccache);
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
        'errore': 'Aspetta che finisca l\'installazione in corso: compilare '
            'adesso riscriverebbe i file che si stanno installando.',
      };
    }
    final c = await _calcola(scelte);
    if (c.errore != null) return {'ok': false, 'errore': c.errore};
    return officina.avvia(c.ricetta!, c.rilievo!);
  }

  Future<Map<String, dynamic>> ferma() async {
    final era = officina.inCorso;
    await officina.ferma();
    return {'ok': true, 'eraInCorso': era};
  }

  // ── Lo scaffale ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> kernel() async =>
      {'ok': true, ...await scaffale.elenco()};

  Future<Map<String, dynamic>> verifica() => scaffale.verifica();

  /// Vero mentre l'aiutante di root sta installando. Si alza PRIMA del primo
  /// `await`: fra un `await` e l'altro il demone serve altri messaggi, e un
  /// «compila» arrivato in quel mezzo cancellerebbe la cartella d'uscita
  /// mentre root la sta leggendo. (Trovato da una revisione automatica.)
  bool _installando = false;

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
    if (_installando) {
      return {'ok': false, 'errore': 'C\'è già un\'installazione in corso.'};
    }
    _installando = true;
    try {
      final elenco = (await scaffale.elenco())['kernel'] as List;
      final voce = elenco.cast<Map>().where((k) => k['rilascio'] == rel);
      if (voce.isEmpty || voce.first['pronto'] != true) {
        return {'ok': false, 'errore': '«$rel» non è pronto da installare.'};
      }
      // Un kernel che in QEMU non è arrivato allo spazio utente non va in
      // /boot: è la ragione per cui la prova esiste.
      final prova = voce.first['provaAvvio'];
      if (prova is Map && prova['ok'] == false) {
        return {
          'ok': false,
          'errore': '«$rel» non è partito nella prova d\'avvio in QEMU '
              '(${prova['perche'] ?? ''}): non lo installo. Ricompilalo, o '
              'rifai la prova.',
        };
      }
      return await _conRadice('fucina-installa', ['$lavoro/uscita/$rel', rel]);
    } finally {
      _installando = false;
    }
  }

  Future<Map<String, dynamic>> togli(Object? rilascio) async {
    final rel = '${rilascio ?? ''}';
    if (!Scaffale.nostro(rel)) {
      return {'ok': false, 'errore': '«$rel» non è un kernel della Fucina.'};
    }
    if (rel == await scaffale.inUso()) {
      return {
        'ok': false,
        'errore': 'È il kernel che stai usando adesso: riavvia su un altro, '
            'poi toglilo.',
      };
    }
    return _conRadice('fucina-togli', [rel]);
  }

  // ── Su misura del tuo uso: il profilo AutoFDO ────────────────────────
  //
  // Giacomo, 1° ottobre 2026: kernel «su misura del PC, con le ultime
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
    if (!Scaffale.nostro(rel)) return no('«$rel» non è un kernel della Fucina.');
    if (_profilando) return no('C\'è già una registrazione in corso.');
    final uso = await scaffale.inUso();
    if (rel != uso) {
      return no('Il profilo di «$rel» si registra avviati su quel kernel: '
          'adesso stai usando «$uso». Riavvia su «$rel» e riprova.');
    }
    final dir = Officina.profiliDi(lavoro, rel);
    if (!await File('$dir/vmlinux').exists()) {
      return no('«$rel» non è pronto al profilo: non è stato compilato con '
          'AutoFDO, o il suo vmlinux non c\'è più ($dir).');
    }
    final r = await _rilievoFresco();
    final hw = r.macchina['profilo'];
    if (hw is! Map || hw['possibile'] != true) {
      return no('Su questo computer il profilo non si può registrare: '
          '${hw is Map ? hw['perche'] : 'non so dire perché.'}');
    }
    final m = (minuti is num ? minuti.toInt() : int.tryParse('$minuti') ?? 10)
        .clamp(1, 60);
    _profilando = true;
    try {
      final esito = await _conRadice('fucina-profila', ['${m * 60}', '${hw['tipo']}']);
      if (esito['ok'] != true) return esito;
      final dati = '$cartellaRegistrazioni/$rel.data';
      if (!(esito['note'] as List).contains('fatto $dati')) {
        return no('L\'aiutante ha registrato da un\'altra parte: '
            '${(esito['note'] as List).join(' ')}');
      }
      final prof = File('$dir/autofdo.prof');
      final nuovo = '$dir/autofdo.prof.nuovo';
      var e = await _prova('llvm-profgen', [
        '--kernel', '--binary=$dir/vmlinux', '--perfdata=$dati',
        '-o', nuovo,
      ]);
      if (e != null) return no('La conversione del profilo non è riuscita: $e');
      final sommato = await prof.exists();
      if (sommato) {
        // Il profilo di oggi si somma a quelli di prima: i rami di chi apre
        // il browser e di chi compila stanno insieme.
        e = await _prova('llvm-profdata', [
          'merge', '--sample', '--extbinary', '-o', '$nuovo.somma',
          prof.path, nuovo,
        ]);
        if (e != null) return no('Non riesco a sommare il profilo nuovo al vecchio: $e');
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
      String verbo, List<String> argomenti) async {
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
