import 'dart:convert';
import 'dart:io';

import 'media.dart';
import '../../core/minerva_paths.dart';

/// Dove si cercano le fotografie, e dove non si cercano.
///
/// ── Perché non «tutta la cartella personale» ───────────────────────────────
///
/// Giacomo ha chiesto «una scansione delle cartelle della home». Preso alla
/// lettera darebbe questo, misurato il 26 agosto 2026:
///
/// ```
///   88.982  file immagine o video sotto ~
///   74.602  di questi sono PNG — icone di temi e risorse di programmi
///      826  fotografie e video veri
/// ```
///
/// Una galleria con dentro 74.602 icone non è «completa», è inservibile. Ma la
/// risposta non è dirgli di no: è che la casa **si guarda davvero**, con le
/// esclusioni giuste già accese, e che il programma **propone** le cartelle
/// dove le fotografie ci sono per davvero, col conteggio, e lui spunta.
///
/// Le esclusioni di serie sono **spente, non vietate**: si tolgono. `Scaricati`
/// è il primo caso che ha nominato — e le sue foto stanno proprio lì dentro,
/// il che è esattamente il motivo per cui gliele proponiamo invece di
/// decidere noi.
class Cartelle {
  /// Il file. Iniettabile: una prova non tocca la configurazione vera.
  final String percorso;

  /// La casa. Iniettabile per lo stesso motivo.
  final String casa;

  Cartelle({String? percorso, String? casa})
      : casa = casa ?? (Platform.environment['HOME'] ?? '/tmp'),
        percorso = percorso ?? _percorsoVero();

  static String _percorsoVero() {
    return '${MinervaPaths.config()}/foto/cartelle.json';
  }

  /// Quante fotografie deve avere una cartella perché valga la pena proporla.
  static const int sogliaProposta = 20;

  /// Fin dove si scende cercando cartelle da proporre. Tre livelli bastano:
  /// `~/documento rinominato/DCIM/Camera` è il più profondo di questa casa.
  static const int profonditaProposta = 3;

  Map<String, dynamic> leggi() {
    try {
      final f = File(percorso);
      if (!f.existsSync()) return _diSerie();
      final d = jsonDecode(f.readAsStringSync());
      if (d is! Map<String, dynamic>) return _diSerie();
      return {
        'versione': 1,
        'cartelle': _stringhe(d['cartelle']),
        'escludi': _stringhe(d['escludi']),
        'mostraSchermate': d['mostraSchermate'] != false,
      };
    } catch (_) {
      return _diSerie();
    }
  }

  /// Le esclusioni di serie non sono una legge: sono un punto di partenza.
  ///
  /// Ci sono perché senza di esse la prima scansione restituisce le icone dei
  /// programmi invece dei ricordi. Si tolgono dalle impostazioni, una per una.
  Map<String, dynamic> _diSerie() => {
        'versione': 1,
        'cartelle': <String>[],
        'escludi': [for (final s in spenteDiSerie) '$casa/$s'],
        'mostraSchermate': true,
      };

  void scrivi(Map<String, dynamic> stato) {
    final f = File(percorso);
    f.parent.createSync(recursive: true);
    // Temporaneo e poi rinomina: un'interruzione a metà scrittura non deve
    // poter lasciare una configurazione monca. Come già `custodia/registro`.
    final t = File('$percorso.nuovo');
    t.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(stato), flush: true);
    t.renameSync(f.path);
  }

  // ── Aggiungere e togliere ──────────────────────────────────────────────

  Map<String, dynamic> aggiungi(String cartella) {
    final c = _pulisci(cartella);
    if (!c.startsWith('/')) {
      return _no('Mi serve il percorso completo, non «$cartella».');
    }
    final d = Directory(c);
    if (!d.existsSync()) return _no('«$c» non c\'è.');
    if (c == '/') {
      return _no('Tutto il disco no: là dentro non ci sono ricordi, '
          'ci sono i file di sistema.');
    }

    final stato = leggi();
    final gia = (stato['cartelle'] as List).cast<String>();
    if (gia.contains(c)) return _no('«${_nome(c)}» c\'è già.');
    // Annidamento nei due versi: due cartelle una dentro l'altra farebbero
    // comparire ogni fotografia due volte.
    for (final g in gia) {
      if (_dentro(c, g)) {
        return _no('«${_nome(c)}» sta già dentro «${_nome(g)}».');
      }
      if (_dentro(g, c)) {
        return _no('«${_nome(g)}» sta dentro «${_nome(c)}»: '
            'toglila prima, o le fotografie compariranno due volte.');
      }
    }

    stato['cartelle'] = [...gia, c];
    scrivi(stato);
    return {'ok': true, 'cartelle': stato['cartelle']};
  }

  Map<String, dynamic> togli(String cartella) {
    final c = _pulisci(cartella);
    final stato = leggi();
    final gia = (stato['cartelle'] as List).cast<String>();
    if (!gia.contains(c)) return _no('«${_nome(c)}» non è nell\'elenco.');
    stato['cartelle'] = gia.where((g) => g != c).toList();
    scrivi(stato);
    return {'ok': true, 'cartelle': stato['cartelle']};
  }

  Map<String, dynamic> escludi(String cartella, bool si) {
    final c = _pulisci(cartella);
    if (!c.startsWith('/')) {
      return _no('Mi serve il percorso completo, non «$cartella».');
    }
    final stato = leggi();
    final gia = (stato['escludi'] as List).cast<String>();
    stato['escludi'] =
        si ? {...gia, c}.toList() : gia.where((g) => g != c).toList();
    scrivi(stato);
    return {'ok': true, 'escludi': stato['escludi']};
  }

  Map<String, dynamic> schermate(bool si) {
    final stato = leggi();
    stato['mostraSchermate'] = si;
    scrivi(stato);
    return {'ok': true, 'mostraSchermate': si};
  }

  // ── Chi entra e chi no, durante il cammino ─────────────────────────────

  /// La domanda che il cammino fa per ogni cartella che incontra.
  ///
  /// [escluse] arriva dalla configurazione: sono percorsi interi, non nomi,
  /// perché «escludi Scaricati» vuol dire quella lì, non ogni cartella che si
  /// chiama così.
  static bool siGuarda(String percorsoCartella, Set<String> escluse) {
    final nome = percorsoCartella.split('/').last;
    if (!siEntra(nome)) return false;
    if (escluse.contains(percorsoCartella)) return false;
    for (final e in escluse) {
      if (_dentro(percorsoCartella, e)) return false;
    }
    return true;
  }

  // ── La proposta ────────────────────────────────────────────────────────

  /// Cerca dove sono davvero le fotografie, e propone.
  ///
  /// Restituisce l'elenco già ordinato per quantità, con dentro anche le
  /// cartelle di sistema per immagini e video — quelle si propongono sempre,
  /// anche vuote, perché sono il posto dove uno *si aspetta* che stiano.
  ///
  /// Si propone la cartella **più in alto** che superi la soglia: chi ha il
  /// backup del telefono vuole spuntare «documento rinominato», non tre volte
  /// `DCIM/Camera`, `DCIM/Snapchat`, `DCIM/Screenshots`.
  List<Map<String, dynamic>> proposte({Set<String>? escluse}) {
    final fuori = escluse ?? (leggi()['escludi'] as List).cast<String>().toSet();
    final trovate = <String, int>{};

    void guarda(Directory d, int profondita) {
      if (profondita > profonditaProposta) return;
      List<FileSystemEntity> voci;
      try {
        voci = d.listSync(followLinks: false);
      } catch (_) {
        return;
      }
      var quiSotto = 0;
      final figlie = <Directory>[];
      for (final v in voci) {
        if (v is File) {
          final n = v.path.split('/').last;
          if (!n.startsWith('.') && eMedia(v.path)) quiSotto++;
        } else if (v is Directory && siGuarda(v.path, fuori)) {
          figlie.add(v);
        }
      }
      for (final f in figlie) {
        guarda(f, profondita + 1);
        quiSotto += trovate[f.path] ?? 0;
      }
      trovate[d.path] = quiSotto;
    }

    guarda(Directory(casa), 0);

    // Le cartelle di sistema: sempre in cima, anche vuote.
    final sistema = <String>['$casa/Immagini', '$casa/Pictures',
      '$casa/Video', '$casa/Videos'];
    final elenco = <Map<String, dynamic>>[];
    final presi = <String>{};

    for (final s in sistema) {
      if (!Directory(s).existsSync()) continue;
      elenco.add({
        'percorso': s,
        'quante': trovate[s] ?? 0,
        'consigliata': true,
      });
      presi.add(s);
    }

    // Poi le altre, dalla più in alto alla più in basso, saltando chi sta
    // dentro una già proposta.
    final candidate = trovate.entries
        .where((e) => e.value >= sogliaProposta && e.key != casa)
        .toList()
      ..sort((a, b) {
        final pa = '/'.allMatches(a.key).length;
        final pb = '/'.allMatches(b.key).length;
        if (pa != pb) return pa.compareTo(pb); // più in alto prima
        return b.value.compareTo(a.value);
      });

    for (final c in candidate) {
      if (presi.any((p) => c.key == p || _dentro(c.key, p))) continue;
      presi.add(c.key);
      elenco.add({
        'percorso': c.key,
        'quante': c.value,
        'consigliata': false,
      });
    }

    return elenco;
  }

  // ── Utilità ────────────────────────────────────────────────────────────

  static String _pulisci(String p) {
    var c = p.trim();
    while (c.length > 1 && c.endsWith('/')) {
      c = c.substring(0, c.length - 1);
    }
    return c;
  }

  static String _nome(String p) => p.split('/').last;

  /// `figlia` sta dentro `madre`?
  static bool _dentro(String figlia, String madre) =>
      figlia.startsWith(madre.endsWith('/') ? madre : '$madre/');

  static List<String> _stringhe(dynamic v) =>
      v is List ? v.whereType<String>().toList() : <String>[];

  static Map<String, dynamic> _no(String perche) =>
      {'ok': false, 'error': perche};
}
