import 'dart:io';
import '../../core/minerva_paths.dart';

/// PuntiMotore — i «punti di ritorno»: com'era la cartella, prima.
///
/// ── Cos'è un punto di ritorno, e perché non è un salvataggio ───────────────
///
/// Un **salvataggio** è un commit: git registra i file che conosce, e sa
/// riportarli indietro. Un **punto di ritorno** è la cartella intera com'era in
/// un istante — `.git` compreso, la roba compilata compresa, i file che git non
/// ha mai visto compresi, le prove lasciate a metà comprese.
///
/// Sono cose diverse e servono a momenti diversi. Quando Giacomo scrive
/// «se rompiamo qualcosa possiamo tornare ad un backup del progetto
/// precedente», sta parlando di **questo**, non di un commit: quello che si
/// rompe, di solito, è proprio la roba che git non guarda.
///
/// ── Perché costa zero ──────────────────────────────────────────────────────
///
/// Perché su btrfs (e su XFS con reflink) una copia non copia i dati: i due
/// file puntano alle stesse estensioni sul disco, e il disco si consuma solo
/// quando uno dei due cambia. Si chiama copy-on-write.
///
/// Misurato su questa macchina, il 24 agosto 2026, sulla cartella di Minerva:
///
///     86 MB, 922 file  →  90 millisecondi, 8 KB di spazio occupato.
///
/// Otto kilobyte. È il motivo per cui questo programma può permettersi di
/// prendere un punto di ritorno **prima di ogni singola operazione
/// pericolosa**, senza chiedere il permesso e senza far pesare la scelta a
/// nessuno. Le quattro copie che Giacomo si era fatto a mano in
/// `Documenti/Progetti/Minerva-Copie/` costano 114 MB e ci sono solo perché lui
/// si è ricordato di farle.
///
/// ── Perché NON si usa `btrfs subvolume snapshot` ───────────────────────────
///
/// Perché quello vuole un **sottovolume**, e la cartella di un progetto è una
/// cartella normale dentro `@home`. Trasformarla in sottovolume sarebbe una
/// migrazione sul disco dell'utente, e servirebbero i permessi di root.
///
/// `cp --reflink` invece funziona su una cartella qualsiasi, **da utente
/// normale**. È la ragione per cui la Custodia non ha un aiutante privilegiato
/// e non compare in nessun file di polkit — al contrario della modalità
/// amministratore del gestore file, che ne aveva bisogno davvero.
class PuntiMotore {
  PuntiMotore({String? radice, this.esegui = Process.run})
      : radice = radice ?? _radicePredefinita();

  /// Dove vivono i punti: `<radice>/<progetto>/<id>/`.
  final String radice;

  /// Come si lanciano i comandi. Sostituibile solo per le prove — il codice
  /// vero non passa mai niente qui.
  final Future<ProcessResult> Function(String, List<String>) esegui;

  static String _radicePredefinita() {
    return '${MinervaPaths.dati()}/custodia/punti';
  }

  // ── Il nome di un punto ────────────────────────────────────────────────
  //
  // `2026-08-24_1725_prima-della-custodia`. Data, ora, e cosa stavi per fare —
  // che è esattamente la convenzione che Giacomo aveva già inventato da solo
  // per i suoi archivi. Non la cambio: era giusta.
  //
  // La nota diventa un **nome di cartella**, e un nome di cartella che arriva
  // dall'utente è un ingresso come tutti gli altri. Vedi `nomePulito()`.

  static final RegExp _cattivi = RegExp(r'[^a-zA-Z0-9àèéìòùÀÈÉÌÒÙ _.-]');

  /// Ripulisce una nota perché possa essere un nome di cartella.
  ///
  /// Non è pignoleria: una nota è testo scritto da una persona, e finisce come
  /// argomento di `cp` e come pezzo di percorso. Una barra la spedirebbe in
  /// un'altra cartella; un trattino iniziale la farebbe leggere a `cp` come
  /// un'opzione; due punti la manderebbero verso l'alto.
  ///
  /// Vuota è lecito: un punto di ritorno senza nota resta un punto di ritorno.
  static String nomePulito(String nota) {
    var n = nota.trim().replaceAll(_cattivi, '-');
    n = n.replaceAll(RegExp(r'\s+'), '-');
    n = n.replaceAll(RegExp(r'-{2,}'), '-');
    // Un punto iniziale nasconderebbe la cartella; un trattino iniziale la
    // farebbe scambiare per un'opzione.
    n = n.replaceAll(RegExp(r'^[-._]+'), '');
    n = n.replaceAll(RegExp(r'[-._]+$'), '');
    if (n.length > 60) n = n.substring(0, 60);
    return n;
  }

  /// L'identificativo di un punto, che è anche il nome della sua cartella.
  static String idPunto(DateTime quando, String nota) {
    String due(int v) => v.toString().padLeft(2, '0');
    final base = '${quando.year}-${due(quando.month)}-${due(quando.day)}'
        '_${due(quando.hour)}${due(quando.minute)}';
    final n = nomePulito(nota);
    return n.isEmpty ? base : '${base}_$n';
  }

  /// Rilegge data e nota da un identificativo. `null` se non è dei nostri —
  /// nella cartella dei punti può finirci qualsiasi cosa, e una cartella che
  /// non riconosciamo non la tocchiamo e non la contiamo.
  static Punto? leggiId(String id, String percorso) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})_(\d{2})(\d{2})(?:_(.*))?$')
        .firstMatch(id);
    if (m == null) return null;
    final q = DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
    );
    return Punto(
      id: id,
      quando: q,
      nota: (m.group(6) ?? '').replaceAll('-', ' '),
      percorso: percorso,
    );
  }
  // ── Sa copiare gratis, qui? ────────────────────────────────────────────
  //
  // Non si guarda il tipo di filesystem, e non è pedanteria: btrfs con
  // `nodatacow` non fa reflink, XFS lo fa solo se formattato con `reflink=1`,
  // e una cartella può stare su un montaggio diverso da quello che sembra.
  // L'unico modo onesto di sapere se una cosa funziona è **farla**.
  //
  // Si scrive un file di quattro byte accanto alla cartella, lo si copia con
  // `--reflink=always`, e si guarda se `cp` protesta. Poi si pulisce.

  Future<bool> copiaGratuita(String cartella) async {
    final padre = Directory(cartella).parent.path;
    final a = File('$padre/.minerva-custodia-prova-$pid');
    final b = File('$padre/.minerva-custodia-prova-$pid.copia');
    try {
      await a.writeAsString('cow\n');
      final r = await esegui('cp', ['--reflink=always', '--', a.path, b.path]);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    } finally {
      try { if (await a.exists()) await a.delete(); } catch (_) {}
      try { if (await b.exists()) await b.delete(); } catch (_) {}
    }
  }

  // ── Prendere un punto ──────────────────────────────────────────────────

  /// Copia `cartella` in un punto di ritorno nuovo.
  ///
  /// `--reflink=auto` e non `always`: su un filesystem che non sa fare
  /// copy-on-write, `always` fallirebbe e basta. `auto` copia davvero — più
  /// lento e con un costo vero, ma **una copia c'è**. Chi chiama sa già da
  /// `copiaGratuita()` in che mondo si trova e lo ha detto all'utente; qui non
  /// è il momento di rifiutarsi di proteggere qualcuno.
  Future<EsitoPunto> crea(
    String progetto,
    String cartella, {
    String nota = '',
    DateTime? quando,
  }) async {
    final sorgente = Directory(cartella);
    if (!await sorgente.exists()) {
      return EsitoPunto.no('La cartella «$cartella» non esiste più.');
    }
    final nomeP = nomePulito(progetto);
    if (nomeP.isEmpty) {
      return EsitoPunto.no('Il progetto deve avere un nome.');
    }

    final casa = Directory('$radice/$nomeP');
    await casa.create(recursive: true);

    // Se in questo minuto ne è già stato preso uno con la stessa nota, il nome
    // collide. Non si sovrascrive: si aggiunge un secondo nome.
    var id = idPunto(quando ?? DateTime.now(), nota);
    var dest = '${casa.path}/$id';
    var n = 2;
    while (await Directory(dest).exists() || await File(dest).exists()) {
      dest = '${casa.path}/$id-$n';
      n++;
      if (n > 50) return EsitoPunto.no('Troppi punti nello stesso minuto.');
    }
    id = dest.split('/').last;

    // `--` chiude le opzioni: un percorso che comincia per trattino è raro ma
    // legale, e senza questa riga `cp` lo leggerebbe come un'opzione.
    final r = await esegui(
      'cp',
      ['-a', '--reflink=auto', '--', sorgente.path, dest],
    );
    if (r.exitCode != 0) {
      // Una copia a metà è peggio di nessuna copia: chi la trova domani crede
      // di avere una rete che non ha.
      try { await Directory(dest).delete(recursive: true); } catch (_) {}
      return EsitoPunto.no(_erroreLeggibile('${r.stderr}'));
    }

    final p = leggiId(id, dest);
    if (p == null) return EsitoPunto.no('Punto creato con un nome illeggibile.');
    return EsitoPunto.si(p);
  }

  // ── Guardarli ──────────────────────────────────────────────────────────

  /// I punti di un progetto, dal più recente al più vecchio.
  Future<List<Punto>> elenca(String progetto) async {
    final casa = Directory('$radice/${nomePulito(progetto)}');
    if (!await casa.exists()) return const [];
    final fuori = <Punto>[];
    await for (final e in casa.list(followLinks: false)) {
      if (e is! Directory) continue;
      final p = leggiId(e.path.split('/').last, e.path);
      if (p != null) fuori.add(p);
    }
    fuori.sort((a, b) => b.quando.compareTo(a.quando));
    return fuori;
  }

  // ── Tornare indietro ───────────────────────────────────────────────────

  /// Riporta `cartella` a com'era nel punto `id`.
  ///
  /// ── L'ordine delle mosse, che è tutto ────────────────────────────────
  ///
  /// La strada ingenua — cancella la cartella, poi ricopia il punto — ha un
  /// istante in cui il lavoro **non esiste da nessuna parte**. Se la copia
  /// fallisce lì in mezzo (disco pieno, corrente che va via), non si è tornati
  /// indietro: si è perso tutto.
  ///
  /// Qui l'ordine è:
  ///
  ///   1. si prende un punto di ritorno di **adesso** — così anche il tornare
  ///      indietro si può annullare, ed è la sola ragione per cui questa
  ///      funzione si può offrire a chi non sa cosa sta facendo;
  ///   2. si copia il punto accanto alla cartella, con un nome di lavoro;
  ///   3. si **rinomina** la cartella vecchia da parte;
  ///   4. si **rinomina** la nuova al posto giusto;
  ///   5. solo adesso si butta la vecchia.
  ///
  /// I due rinomini sono atomici, e fra il 3 e il 4 passa un microsecondo. In
  /// nessun istante i dati sono assenti: al massimo sono in due posti.
  ///
  /// Il passo 2 vuole che punto e cartella stiano sullo **stesso filesystem** —
  /// se non è così il rinomino fallisce, e lo diciamo invece di lasciare in
  /// giro una `.custodia-nuova` che nessuno capisce.
  Future<EsitoPunto> ripristina(
    String progetto,
    String id,
    String cartella, {
    DateTime? quando,
  }) async {
    final punto = Directory('$radice/${nomePulito(progetto)}/$id');
    if (leggiId(id, punto.path) == null) {
      return EsitoPunto.no('«$id» non è un punto di ritorno.');
    }
    if (!await punto.exists()) {
      return EsitoPunto.no('Quel punto di ritorno non c\'è più.');
    }
    final viva = Directory(cartella);
    if (!await viva.exists()) {
      return EsitoPunto.no('La cartella «$cartella» non esiste.');
    }

    // 1. La rete prima del salto. Se questa fallisce non si salta: è la
    //    condizione, non un tentativo.
    final rete = await crea(
      progetto,
      cartella,
      nota: 'prima-di-tornare-a-$id',
      quando: quando,
    );
    if (!rete.riuscito) {
      return EsitoPunto.no(
        'Non sono riuscito a mettere al sicuro com\'è adesso, quindi non '
        'torno indietro. ${rete.errore}',
      );
    }

    final nuova = '$cartella.custodia-nuova';
    final vecchia = '$cartella.custodia-vecchia';
    try { await Directory(nuova).delete(recursive: true); } catch (_) {}
    try { await Directory(vecchia).delete(recursive: true); } catch (_) {}

    // 2.
    final c = await esegui('cp', ['-a', '--reflink=auto', '--', punto.path, nuova]);
    if (c.exitCode != 0) {
      try { await Directory(nuova).delete(recursive: true); } catch (_) {}
      return EsitoPunto.no(_erroreLeggibile('${c.stderr}'));
    }

    try {
      await viva.rename(vecchia);          // 3.
    } catch (e) {
      try { await Directory(nuova).delete(recursive: true); } catch (_) {}
      return EsitoPunto.no('Non riesco a spostare la cartella attuale: $e');
    }
    try {
      await Directory(nuova).rename(cartella);  // 4.
    } catch (e) {
      // Il passo 4 è fallito: la cartella vera è ancora tutta lì, si rimette
      // dov'era. Questo è il ramo che rende il passo 3 reversibile.
      try { await Directory(vecchia).rename(cartella); } catch (_) {}
      return EsitoPunto.no('Non riesco a mettere al suo posto il punto: $e');
    }
    try { await Directory(vecchia).delete(recursive: true); } catch (_) {}  // 5.

    return EsitoPunto.si(rete.punto);
  }

  /// Butta un punto di ritorno. L'unica cosa che questo programma cancella
  /// davvero — e per questo non tocca niente che non sia sotto `radice`.
  Future<EsitoPunto> elimina(String progetto, String id) async {
    if (leggiId(id, '') == null) {
      return EsitoPunto.no('«$id» non è un punto di ritorno.');
    }
    final d = Directory('$radice/${nomePulito(progetto)}/$id');
    if (!await d.exists()) return EsitoPunto.no('Quel punto non c\'è.');
    try {
      await d.delete(recursive: true);
      return EsitoPunto.si(null);
    } catch (e) {
      return EsitoPunto.no('Non riesco a eliminarlo: $e');
    }
  }

  // ── Quali si buttano ───────────────────────────────────────────────────
  //
  // Funzione **pura**: prende una lista e ne torna una. Non guarda il disco e
  // non cancella niente, così si può provare con cento punti finti senza
  // creare cento cartelle — ed è la parte in cui un errore costa il lavoro di
  // qualcuno, quindi è la parte che voglio poter provare a fondo.
  //
  // La regola: tutti quelli degli ultimi 7 giorni; poi uno al giorno fino a 30
  // giorni; poi uno a settimana. Su reflink si può essere generosi, e la
  // generosità qui è la funzione.
  //
  // Due garanzie che non dipendono dalle date:
  //   · il più recente non si butta MAI, nemmeno se è vecchissimo — se un
  //     progetto è fermo da un anno, il suo unico punto è tutto ciò che ha;
  //   · non si butta mai l'ultimo rimasto.

  /// Butta i punti che la regola qui sotto non tiene, e dice quanti.
  ///
  /// C'era la regola e non c'era chi la applicava: i punti si accumulavano
  /// per sempre, e su copy-on-write un punto vecchio trattiene tutti i dati
  /// cambiati dopo di lui (5 ottobre 2026). Non fallisce mai: un punto che
  /// non si riesce a togliere resta, e ci si riprova al prossimo.
  ///
  /// **Mai dentro `ripristina`**: lì il punto a cui si torna deve esserci
  /// fino alla fine. La chiama chi prende un punto per conto suo.
  Future<int> pota(String progetto, {DateTime? adesso}) async {
    var tolti = 0;
    try {
      final via = daPotare(await elenca(progetto), adesso: adesso);
      for (final p in via) {
        if ((await elimina(progetto, p.id)).riuscito) tolti++;
      }
    } catch (e) {
      stderr.writeln('[MINERVA][CUSTODIA] Potatura dei punti saltata: $e');
    }
    return tolti;
  }

  static List<Punto> daPotare(List<Punto> tutti, {DateTime? adesso}) {
    if (tutti.length <= 1) return const [];
    final ora = adesso ?? DateTime.now();
    final ordinati = [...tutti]..sort((a, b) => b.quando.compareTo(a.quando));

    final tieni = <String>{ordinati.first.id};
    final giorniVisti = <String>{};
    final settimaneViste = <String>{};

    for (final p in ordinati) {
      final eta = ora.difference(p.quando).inDays;
      if (eta < 7) {
        tieni.add(p.id);
        continue;
      }
      final giorno = '${p.quando.year}-${p.quando.month}-${p.quando.day}';
      if (eta < 30) {
        if (giorniVisti.add(giorno)) tieni.add(p.id);
        continue;
      }
      // Il numero della settimana basta che sia stabile, non che sia ISO.
      final settimana = '${p.quando.year}-${(p.quando.difference(
            DateTime(p.quando.year),
          ).inDays ~/ 7)}';
      if (settimaneViste.add(settimana)) tieni.add(p.id);
    }
    return ordinati.where((p) => !tieni.contains(p.id)).toList();
  }

  // ── Gli errori, in italiano ────────────────────────────────────────────
  //
  // `cp` parla la lingua di chi l'ha scritto e di chi l'ha compilato. Chi legge
  // «cp: cannot create directory: No space left on device» dentro una finestra
  // di Minerva non sta leggendo un messaggio: sta leggendo un guasto.
  static String _erroreLeggibile(String grezzo) {
    final g = grezzo.toLowerCase();
    if (g.contains('no space left')) {
      return 'Il disco è pieno: non c\'è posto per il punto di ritorno.';
    }
    if (g.contains('permission denied')) {
      return 'Non ho il permesso di leggere tutto quello che c\'è dentro '
          'quella cartella.';
    }
    if (g.contains('read-only file system')) {
      return 'Il disco è in sola lettura.';
    }
    if (g.contains('file exists')) {
      return 'C\'è già qualcosa con quel nome.';
    }
    final riga = grezzo.trim().split('\n').first;
    return riga.isEmpty ? 'La copia non è riuscita.' : riga;
  }
}

/// L'esito di un'operazione sui punti.
///
/// Riuscito/non riuscito e basta: chi chiama non deve interpretare un codice.
/// Quando è andata male c'è **sempre** una frase in italiano, perché quella
/// frase finisce dritta sotto gli occhi di una persona.
class EsitoPunto {
  const EsitoPunto.si(this.punto) : riuscito = true, errore = null;
  const EsitoPunto.no(this.errore) : riuscito = false, punto = null;

  final bool riuscito;
  final String? errore;
  final Punto? punto;

  Map<String, dynamic> toJson() => {
        'ok': riuscito,
        if (errore != null) 'errore': errore,
        if (punto != null) 'punto': punto!.toJson(),
      };
}

/// Un punto di ritorno, come lo vede chi lo guarda.
class Punto {
  const Punto({
    required this.id,
    required this.quando,
    required this.nota,
    required this.percorso,
  });

  final String id;
  final DateTime quando;
  final String nota;
  final String percorso;

  Map<String, dynamic> toJson() => {
        'id': id,
        'quando': quando.toIso8601String(),
        'nota': nota,
        'percorso': percorso,
      };
}
