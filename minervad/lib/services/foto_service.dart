import 'dart:async';

import 'foto/cartelle.dart';
import 'foto/doppioni.dart';
import 'foto/indice.dart';
import 'foto/miniature.dart';

/// La porta della galleria: una sola, e sottile.
///
/// Sotto ci sono quattro pezzi che non si conoscono fra loro — le cartelle
/// scelte, il catalogo, le miniature, e il datatore che sta dentro al catalogo.
/// Qui non c'è logica: c'è l'elenco di quello che la shell può chiedere.
///
/// ── Perché le proposte sono un'azione a parte ──────────────────────────────
///
/// Perché costano. Leggere la configurazione è istantaneo e succede a ogni
/// apertura; cercare dove sono le fotografie vuol dire camminare per la casa —
/// 0,4 secondi su questa, di più su una piena. Metterle nella stessa risposta
/// vorrebbe dire pagare quella camminata anche quando le cartelle sono già
/// scelte da mesi.
class FotoService {
  final Cartelle cartelle;
  final Indice indice;
  final Miniature miniature;

  FotoService({Cartelle? cartelle, Indice? indice, Miniature? miniature})
      : cartelle = cartelle ?? Cartelle(),
        indice = indice ??
            Indice(cartelle: cartelle ?? Cartelle()),
        miniature = miniature ?? Miniature();

  // ── Le cartelle ────────────────────────────────────────────────────────

  Map<String, dynamic> vediCartelle() {
    final s = cartelle.leggi();
    return {
      'ok': true,
      'cartelle': s['cartelle'],
      'escludi': s['escludi'],
      'mostraSchermate': s['mostraSchermate'],
    };
  }

  Map<String, dynamic> proposte() =>
      {'ok': true, 'proposte': cartelle.proposte()};

  Map<String, dynamic> aggiungiCartella(String? percorso) =>
      percorso == null || percorso.isEmpty
          ? _no('Non hai detto quale cartella.')
          : cartelle.aggiungi(percorso);

  Map<String, dynamic> togliCartella(String? percorso) =>
      percorso == null || percorso.isEmpty
          ? _no('Non hai detto quale cartella.')
          : cartelle.togli(percorso);

  Map<String, dynamic> escludi(String? percorso, bool si) =>
      percorso == null || percorso.isEmpty
          ? _no('Non hai detto quale cartella.')
          : cartelle.escludi(percorso, si);

  Map<String, dynamic> schermate(bool si) => cartelle.schermate(si);

  // ── Il catalogo ────────────────────────────────────────────────────────

  Stream<Map<String, dynamic>> scansiona(String id) => indice.scansiona(id);

  void fermaScansione(String id) => indice.ferma(id);

  Map<String, dynamic> panoramica() => indice.panoramica();

  /// Prepara lo scarto di un gruppo di doppioni.
  ///
  /// **Non cancella: dice che cosa si può buttare.** A buttare è `fs_trash`,
  /// che manda nel cestino ed è recuperabile — e sta in un altro servizio
  /// perché è lui che sa dov'è il cestino.
  ///
  /// ── I tre rifiuti, e perché sono qui e non nell'interfaccia ───────────
  ///
  /// Perché un'interfaccia si può sbagliare, e questa è l'unica strada verso
  /// la cancellazione di una fotografia. La regola è che **«butta tutte le
  /// copie» non deve essere una cosa esprimibile**:
  ///
  ///  1. senza un file da TENERE non si butta niente;
  ///  2. il file da tenere non può stare fra quelli da buttare — è la forma
  ///     in cui un errore di un clic diventa una foto persa;
  ///  3. si buttano solo file che stanno nell'indice, cioè fotografie che
  ///     Minerva conosce: questa non è una via per cancellare `/etc`.
  Map<String, dynamic> scartoDoppioni(String? tieni, List<String>? butta) {
    final t = (tieni ?? '').trim();
    final b = (butta ?? const <String>[])
        .map((x) => x.trim())
        .where((x) => x.isNotEmpty)
        .toSet();

    if (t.isEmpty) {
      return _no('Non hai detto quale copia tenere: senza quella non butto '
          'niente.');
    }
    if (b.isEmpty) return _no('Non hai detto quali copie buttare.');
    if (b.contains(t)) {
      return _no('La copia da tenere è anche fra quelle da buttare. Non '
          'butto niente: così si perde la fotografia.');
    }

    final conosciuti = {for (final v in indice.voci) v.percorso};
    if (!conosciuti.contains(t)) {
      return _no('«$t» non è una fotografia dell\'archivio.');
    }
    final estranei = b.where((x) => !conosciuti.contains(x)).toList();
    if (estranei.isNotEmpty) {
      return _no('Non sono fotografie dell\'archivio: '
          '${estranei.take(3).join(", ")}. Non butto niente.');
    }

    return {'ok': true, 'tieni': t, 'butta': b.toList()};
  }

  /// Le fotografie che ci sono due volte.
  ///
  /// Non cancella niente e non propone di cancellare: torna i gruppi, col
  /// primo di ognuno marcato come «quello da tenere». Chi decide è chi guarda
  /// — ed è il motivo per cui questa azione e quella che sposta nel cestino
  /// sono due, e non una con un interruttore.
  Future<Map<String, dynamic>> doppioni() async {
    final gruppi = await Doppioni(indice).esatti();
    return {
      'ok': true,
      'gruppi': [for (final g in gruppi) g.toJson()],
      'quanti': gruppi.length,
      // Quanto si libererebbe tenendone una per gruppo. È il numero che fa
      // decidere se vale la pena guardarli.
      'byteInPiu': gruppi.fold<int>(0, (a, g) => a + g.byteInPiu),
    };
  }

  Map<String, dynamic> giorno(String? quale) => quale == null
      ? _no('Non hai detto quale giorno.')
      : indice.giorno(quale);

  Map<String, dynamic> preferito(String? percorso, bool si) =>
      percorso == null || percorso.isEmpty
          ? _no('Non hai detto quale fotografia.')
          : indice.preferito(percorso, si);

  // ── Le miniature ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>> miniaturaDi(String? percorso, int lato) async =>
      percorso == null || percorso.isEmpty
          ? _no('Non hai detto quale fotografia.')
          : await miniature.per(percorso, lato: lato);

  static Map<String, dynamic> _no(String perche) =>
      {'ok': false, 'error': perche};
}
