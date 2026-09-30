import 'dart:convert';

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

  FucinaService({
    required this.radice,
    String? lavoro,
    String? statoDir,
    Officina? officina,
    Scaffale? scaffale,
    Sorgenti? sorgenti,
    Rilevatore Function(void Function(String, String, int, int)?)?
        nuovoRilevatore,
  })  : lavoro = lavoro ?? '${MinervaPaths.cache()}/fucina',
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
