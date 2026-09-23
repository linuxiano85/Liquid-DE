/// Che cosa si vuole fare a un file, e dove finirebbe.
class Passo {
  final String da;
  final String a;

  /// Vuoto se si fa; altrimenti il motivo, in italiano, per cui NON si fa.
  final String rifiuto;

  const Passo({required this.da, required this.a, this.rifiuto = ''});

  bool get siFa => rifiuto.isEmpty;

  Map<String, dynamic> toJson() =>
      {'da': da, 'a': a, if (rifiuto.isNotEmpty) 'rifiuto': rifiuto};
}

/// Una cosa da riordinare: un percorso, una data, e quanto ci si crede.
///
/// **Non sa che sia una fotografia**, ed è voluto: quando toccherà ai
/// documenti dentro l'Editor, la parte da scrivere sarà solo il datatore. Il
/// riordino, l'anteprima, i rifiuti e i punti di ritorno sono gli stessi.
class DaRiordinare {
  final String percorso;
  final DateTime? data;

  /// `certa` · `probabile` · `incerta` · `ultima-spiaggia`
  final String fiducia;

  /// Le fonti non sono d'accordo fra loro: la data è contesa.
  final bool daControllare;

  const DaRiordinare({
    required this.percorso,
    required this.data,
    this.fiducia = 'certa',
    this.daControllare = false,
  });
}

/// Dove va messo un file, e con che nome.
///
/// ── Perché piano, anteprima ed esecuzione sono tre cose ───────────────────
///
/// Perché spostare fotografie è irreversibile in pratica anche quando è
/// reversibile in teoria: chi si accorge dello sbaglio il giorno dopo non sa
/// più dove fossero prima. Quindi si costruisce **il piano intero** — ogni
/// «da → a», compresi i rifiuti — lo si guarda, e solo dopo si tocca un byte.
///
/// Questo file fa il PIANO e basta. Non sposta niente, non legge il disco,
/// non ha bisogno di un disco: è conto puro, e per questo si prova con dei
/// numeri.
class Riordino {
  /// `anno` · `anno-mese` · `anno-mese-giorno`
  final String struttura;

  /// Se vero, dentro ogni cartella si separa per tipo: `Foto/`, `Video/`,
  /// `Schermate/`.
  final bool perTipo;

  /// Rinominare col nome-data. **Spento di serie**, ed è una scelta: il nome
  /// che un file ha addosso è, per alcuni, l'unica prova della data che
  /// abbiamo. Cambiarlo su una supposizione è irreversibile.
  final bool rinomina;

  /// La cartella in cui va la roba riordinata.
  final String destinazione;

  const Riordino({
    required this.destinazione,
    this.struttura = 'anno-mese',
    this.perTipo = false,
    this.rinomina = false,
  });

  static const mesi = [
    'gennaio', 'febbraio', 'marzo', 'aprile', 'maggio', 'giugno',
    'luglio', 'agosto', 'settembre', 'ottobre', 'novembre', 'dicembre',
  ];

  /// Il piano completo: un passo per ogni cosa, rifiuti compresi.
  ///
  /// I rifiuti **restano nell'elenco** invece di sparire: chi guarda deve
  /// vedere che quelle quattordici fotografie non si toccano, e perché. Un
  /// elenco che mostra solo quello che si farà nasconde proprio le cose su
  /// cui serve una decisione.
  List<Passo> piano(List<DaRiordinare> roba, {Map<String, String>? tipi}) {
    final fuori = <Passo>[];
    // I nomi già presi, per non far finire due file nello stesso posto.
    final presi = <String>{};

    for (final r in roba) {
      final rifiuto = _perche(r);
      if (rifiuto.isNotEmpty) {
        fuori.add(Passo(da: r.percorso, a: '', rifiuto: rifiuto));
        continue;
      }
      final tipo = tipi?[r.percorso] ?? 'foto';
      var dove = '$destinazione/${_cartella(r.data!, tipo)}/'
          '${_nome(r, tipo)}';
      dove = _libero(dove, presi);
      presi.add(dove);
      fuori.add(Passo(da: r.percorso, a: dove));
    }
    return fuori;
  }

  /// ── I due rifiuti, e sono il cuore di questo file ────────────────────
  ///
  /// 1. **Senza data non si sposta.** Una fotografia in `2026/marzo` che in
  ///    marzo non c'entra niente è peggio di una fotografia dov'era: nella
  ///    seconda si sa ancora dove cercarla.
  /// 2. **Su una data CONTESA non si tocca niente.** «Contesa» vuol dire che
  ///    l'EXIF e il nome del file dicono cose diverse di più di un giorno, e
  ///    il datatore l'ha marcata. Rinominare su una data contesa cancella
  ///    l'unica altra prova che avevamo — il nome — e la cancella per sempre.
  ///
  /// E la fiducia `ultima-spiaggia` è la data di modifica: sulle 826
  /// fotografie di questa macchina è **l'istante della copia dal telefono**,
  /// uguale per tutte. Riordinare su quella vuol dire un giorno solo con
  /// dentro tutto.
  static String _perche(DaRiordinare r) {
    if (r.data == null) {
      return 'non so quando è stata scattata';
    }
    if (r.daControllare) {
      return 'le fonti non vanno d\'accordo sulla data: va guardata';
    }
    if (r.fiducia == 'ultima-spiaggia') {
      return 'l\'unica data che ho è quella del file, e non è la data dello '
          'scatto';
    }
    return '';
  }

  String _cartella(DateTime d, String tipo) {
    final anno = d.year.toString();
    final mese = '${d.month.toString().padLeft(2, "0")} '
        '${mesi[d.month - 1]}';
    final giorno = d.day.toString().padLeft(2, '0');

    var base = switch (struttura) {
      'anno' => anno,
      'anno-mese-giorno' => '$anno/$mese/$giorno',
      _ => '$anno/$mese',
    };
    if (perTipo) base = '$base/${_nomeTipo(tipo)}';
    return base;
  }

  static String _nomeTipo(String tipo) => switch (tipo) {
        'video' => 'Video',
        'schermata' => 'Schermate',
        _ => 'Foto',
      };

  String _nome(DaRiordinare r, String tipo) {
    final vecchio = r.percorso.split('/').last;
    if (!rinomina) return vecchio;
    final d = r.data!;
    // I due punti no: su alcuni dischi non si possono scrivere, e un nome che
    // funziona sul portatile e non sulla chiavetta è un nome sbagliato.
    final base = '${d.year}-${_due(d.month)}-${_due(d.day)} '
        '${_due(d.hour)}.${_due(d.minute)}.${_due(d.second)}';
    final punto = vecchio.lastIndexOf('.');
    final coda = punto > 0 ? vecchio.substring(punto) : '';
    return '$base$coda';
  }

  static String _due(int n) => n.toString().padLeft(2, '0');

  /// Se il posto è già preso, `-2`, `-3`, … Due scatti nello stesso secondo
  /// esistono — una raffica ne fa dieci — e senza questo il secondo
  /// sovrascriverebbe il primo.
  static String _libero(String dove, Set<String> presi) {
    if (!presi.contains(dove)) return dove;
    final punto = dove.lastIndexOf('.');
    final base = punto > 0 ? dove.substring(0, punto) : dove;
    final coda = punto > 0 ? dove.substring(punto) : '';
    for (var n = 2; n < 10000; n++) {
      final prova = '$base-$n$coda';
      if (!presi.contains(prova)) return prova;
    }
    return dove;
  }

  /// Il conto di un piano, per dirlo a parole prima di farlo.
  static Map<String, dynamic> conto(List<Passo> passi) {
    final rifiutati = passi.where((p) => !p.siFa).toList();
    final perMotivo = <String, int>{};
    for (final p in rifiutati) {
      perMotivo[p.rifiuto] = (perMotivo[p.rifiuto] ?? 0) + 1;
    }
    return {
      'ok': true,
      'quanti': passi.length,
      'siFanno': passi.length - rifiutati.length,
      'rifiutati': rifiutati.length,
      'perche': perMotivo,
    };
  }
}
