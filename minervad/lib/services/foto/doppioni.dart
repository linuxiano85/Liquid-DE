import 'dart:io';
import 'dart:typed_data';

import 'indice.dart';

/// Un gruppo di file che sono la stessa cosa.
class Gruppo {
  /// I percorsi, dal «migliore» in giù. Il primo è quello da tenere.
  final List<String> percorsi;

  /// `esatti` — byte per byte identici.
  /// `scatto` — stesso scatto, qualità diversa (l'originale e la copia di
  /// WhatsApp).
  final String genere;

  /// Quanto si libererebbe tenendo solo il primo.
  final int byteInPiu;

  const Gruppo({
    required this.percorsi,
    required this.genere,
    required this.byteInPiu,
  });

  Map<String, dynamic> toJson() => {
        'percorsi': percorsi,
        'genere': genere,
        'byteInPiu': byteInPiu,
      };
}

/// Trova le fotografie che ci sono due volte.
///
/// ── Perché due generi e non uno ───────────────────────────────────────────
///
/// Perché sono due domande diverse, e solo una ha una risposta certa.
///
/// **Copie esatte**: gli stessi byte. Qui non c'è niente da giudicare, solo da
/// scegliere quale cartella tenere. Sulla macchina di Giacomo, misurato il 26
/// agosto 2026: **295 dei 748 file di `DCIM` sono doppioni esatti** — la stessa
/// copia del telefono fatta due volte, in `documento rinominato/DCIM` e in
/// `Scaricati/DCIM`. Verificato con MD5 su 120 coppie: 120 identiche.
///
/// **Stesso scatto, qualità diversa**: l'originale e la copia passata da
/// WhatsApp. Qui c'è un giudizio, e il giudizio si può sbagliare — quindi
/// resta un gruppo a parte, e la decisione è di chi guarda.
///
/// ── Come si confronta senza leggere tutto ────────────────────────────────
///
/// A tre livelli, e ognuno serve a non fare il successivo:
///
///  1. **la dimensione** — due file di lunghezza diversa non sono lo stesso
///     file, e questo costa zero perché il numero sta già nell'indice;
///  2. **i primi e gli ultimi 64 KB** — bastano a separare quasi tutto, e
///     costano due letture invece di leggere 2,7 MB;
///  3. **il file intero**, solo quando i primi due non hanno deciso.
///
/// Senza il primo livello, confrontare 525 fotografie a due a due sarebbe
/// centotrentasettemila confronti. Con la dimensione diventano poche decine.
class Doppioni {
  Doppioni(Indice indice) : _voci = indice.voci;

  /// ── Per chi ha già l'elenco, e non un indice di fotografie ───────────
  ///
  /// La Manutenzione cerca i doppioni in TUTTA la cartella di casa, dove un
  /// indice di foto non c'entra niente: le tre copie dello stesso scarico del
  /// telefono sono video, ma i 6,94 GB sprecati su questa macchina
  /// comprendono anche ISO, archivi e librerie compilate.
  ///
  /// Il confronto è lo stesso — dimensione, estremità, file intero — e questo
  /// costruttore esiste per non copiarlo altrove: un secondo algoritmo di
  /// doppioni sarebbe un secondo posto dove sbagliarlo.
  Doppioni.suElenco(List<Voce> voci) : _voci = voci;

  final List<Voce> _voci;

  /// Quanto si legge dalle due estremità per l'impronta veloce.
  static const int assaggio = 64 * 1024;

  /// I gruppi di copie ESATTE.
  ///
  /// `avanza` viene chiamata ogni tanto con quanti file sono stati guardati:
  /// serve a far vedere che il lavoro procede, non a misurarlo.
  Future<List<Gruppo>> esatti({void Function(int fatti, int totale)? avanza}) async {
    // ── Primo livello: la dimensione ─────────────────────────────────────
    //
    // Sta già nell'indice, quindi questo giro non tocca il disco.
    final perDimensione = <int, List<Voce>>{};
    for (final v in _voci) {
      if (v.dimensione <= 0) continue;
      (perDimensione[v.dimensione] ??= []).add(v);
    }
    // Chi è solo della sua misura non ha doppioni, e non si legge affatto.
    perDimensione.removeWhere((_, lista) => lista.length < 2);

    final fuori = <Gruppo>[];
    var fatti = 0;
    final totale = perDimensione.values.fold<int>(0, (a, b) => a + b.length);

    for (final entry in perDimensione.entries) {
      final dimensione = entry.key;

      // ── Secondo livello: le due estremità ────────────────────────────
      final perAssaggio = <String, List<Voce>>{};
      for (final v in entry.value) {
        final impronta = await _assaggia(v.percorso, dimensione);
        fatti++;
        if (impronta == null) continue;
        (perAssaggio[impronta] ??= []).add(v);
        if (avanza != null && fatti % 25 == 0) avanza(fatti, totale);
      }
      perAssaggio.removeWhere((_, lista) => lista.length < 2);

      // ── Terzo livello: tutto, e solo dove serve ──────────────────────
      for (final quasi in perAssaggio.values) {
        // Un file più piccolo dell'assaggio è già stato letto tutto: il
        // confronto di prima è già la risposta, e rileggerlo sarebbe
        // rileggerlo per niente.
        if (dimensione <= assaggio * 2) {
          fuori.add(_gruppo(quasi, 'esatti', dimensione));
          continue;
        }
        final perIntero = <String, List<Voce>>{};
        for (final v in quasi) {
          final impronta = await _intero(v.percorso);
          if (impronta == null) continue;
          (perIntero[impronta] ??= []).add(v);
        }
        for (final uguali in perIntero.values) {
          if (uguali.length < 2) continue;
          fuori.add(_gruppo(uguali, 'esatti', dimensione));
        }
      }
    }

    // I gruppi che liberano di più, per primi: è l'ordine in cui uno vuole
    // guardarli, e non l'ordine alfabetico dei percorsi.
    fuori.sort((a, b) => b.byteInPiu.compareTo(a.byteInPiu));
    return fuori;
  }

  /// Ordina un gruppo mettendo davanti quello da tenere, e conta lo spreco.
  ///
  /// ── Quale si tiene, quando i byte sono identici ──────────────────────
  ///
  /// Sono lo stesso file: non c'è un «migliore». Si tiene quello con il
  /// percorso **più corto**, e non è un capriccio: fra
  /// `Immagini/vacanze/mare.jpg` e `Scaricati/DCIM/Camera/mare.jpg` il primo
  /// è quello che qualcuno ha messo dove voleva, il secondo è dove è caduto.
  /// A parità di lunghezza, l'ordine alfabetico — perché la stessa cartella
  /// deve dare la stessa risposta domani.
  static Gruppo _gruppo(List<Voce> voci, String genere, int dimensione) {
    final p = voci.map((v) => v.percorso).toList()
      ..sort((a, b) {
        final c = a.length.compareTo(b.length);
        return c != 0 ? c : a.compareTo(b);
      });
    return Gruppo(
      percorsi: p,
      genere: genere,
      byteInPiu: dimensione * (p.length - 1),
    );
  }

  /// L'impronta delle due estremità, più la lunghezza.
  ///
  /// Le due estremità e non solo l'inizio: due fotografie della stessa
  /// raffica hanno lo stesso EXIF nei primi kilobyte e differiscono in fondo.
  /// Con il solo inizio finirebbero nello stesso mucchio e si pagherebbe la
  /// lettura intera per scoprire che erano diverse.
  static Future<String?> _assaggia(String percorso, int dimensione) async {
    RandomAccessFile? f;
    try {
      f = await File(percorso).open();
      final quanto = dimensione < assaggio ? dimensione : assaggio;
      final testa = await f.read(quanto);
      Uint8List coda = testa;
      if (dimensione > assaggio) {
        await f.setPosition(dimensione - quanto);
        coda = await f.read(quanto);
      }
      return '$dimensione:${_somma(testa)}:${_somma(coda)}';
    } catch (_) {
      // Un file sparito o illeggibile non è un doppione: si salta. Fermarsi
      // qui vorrebbe dire perdere i doppioni di tutti gli altri per colpa di
      // un permesso.
      return null;
    } finally {
      await f?.close();
    }
  }

  static Future<String?> _intero(String percorso) async {
    try {
      var somma = _base;
      var quanti = 0;
      await for (final pezzo in File(percorso).openRead()) {
        somma = _accumula(somma, pezzo);
        quanti += pezzo.length;
      }
      return '$quanti:$somma';
    } catch (_) {
      return null;
    }
  }

  // ── Perché una somma scritta a mano e non MD5 ────────────────────────────
  //
  // Perché `crypto` sarebbe una dipendenza, e `minervad/pubspec.yaml` ne
  // dichiara zero di proposito. E perché qui non serve una funzione
  // crittografica: serve distinguere file diversi, non resistere a qualcuno
  // che ne costruisce due apposta per confonderci.
  //
  // È FNV-1a a 64 bit, quella canonica. In Dart gli interi sono a 64 bit
  // veri, quindi la moltiplicazione è quella giusta senza trucchi.
  //
  // E si confronta SEMPRE insieme alla lunghezza — «lunghezza:impronta» — che
  // è quello che rende trascurabile la coincidenza: due file di lunghezza
  // diversa non finiscono mai nello stesso mucchio, comunque vadano le
  // impronte.
  static const int _primo = 0x100000001b3;
  static const int _base = 0xcbf29ce484222325;

  static int _somma(List<int> dati) => _accumula(_base, dati);

  /// **`da` è lo stato di partenza, e non ha casi speciali.** La prima
  /// versione trattava lo zero come «ricomincia da capo»: un'impronta che
  /// fosse arrivata a zero leggendo un pezzo avrebbe fatto ripartire il conto
  /// a metà file, e due file diversi potevano finire con lo stesso numero.
  static int _accumula(int da, List<int> dati) {
    var h = da;
    for (final b in dati) {
      h ^= b;
      h = (h * _primo) & 0xFFFFFFFFFFFFFFFF;
    }
    return h;
  }
}
