import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../image_dims.dart';
import 'cartelle.dart';
import 'data_scatto.dart';
import 'exif.dart';
import 'media.dart';
import '../../core/minerva_paths.dart';

/// Una fotografia o un video, con tutto quello che si è riusciti a sapere.
class Voce {
  final String percorso;
  final int dimensione;
  final DateTime mtime;

  /// `foto`, `video` o `schermata`.
  final String tipo;

  final DateTime? data;
  final String fonte;
  final String fiducia;
  final bool daControllare;

  final int larghezza;
  final int altezza;
  final int orientamento;
  final String macchina;
  final double? lat;
  final double? lon;
  final int durataMs;

  /// Si porta dentro la miniatura: la griglia si riempirà senza costo.
  final bool miniaturaDentro;

  const Voce({
    required this.percorso,
    required this.dimensione,
    required this.mtime,
    required this.tipo,
    this.data,
    this.fonte = '',
    this.fiducia = 'nessuna',
    this.daControllare = false,
    this.larghezza = 0,
    this.altezza = 0,
    this.orientamento = 0,
    this.macchina = '',
    this.lat,
    this.lon,
    this.durataMs = 0,
    this.miniaturaDentro = false,
  });

  String get nome => percorso.split('/').last;

  /// Il giorno a cui appartiene, `AAAA-MM-GG`, o vuoto se la data non c'è.
  String get giorno {
    final d = data;
    if (d == null) return '';
    return '${d.year}-${_due(d.month)}-${_due(d.day)}';
  }

  /// Le misure come si vedono, cioè dopo la rotazione dell'EXIF.
  ///
  /// Da 5 a 8 la fotografia è coricata: una verticale di telefono si dichiara
  /// orizzontale, e una griglia che le credesse la taglierebbe di traverso.
  int get larghezzaVista =>
      (orientamento >= 5 && orientamento <= 8) ? altezza : larghezza;
  int get altezzaVista =>
      (orientamento >= 5 && orientamento <= 8) ? larghezza : altezza;

  Map<String, dynamic> toJson() => {
        'percorso': percorso,
        'dimensione': dimensione,
        'mtime': mtime.millisecondsSinceEpoch,
        'tipo': tipo,
        'data': ?data?.millisecondsSinceEpoch,
        'fonte': fonte,
        'fiducia': fiducia,
        if (daControllare) 'daControllare': true,
        'larghezza': larghezza,
        'altezza': altezza,
        if (orientamento > 1) 'orientamento': orientamento,
        if (macchina.isNotEmpty) 'macchina': macchina,
        'lat': ?lat,
        'lon': ?lon,
        if (durataMs > 0) 'durataMs': durataMs,
        if (miniaturaDentro) 'miniaturaDentro': true,
      };

  static Voce? daJson(dynamic v) {
    if (v is! Map) return null;
    final p = v['percorso'];
    if (p is! String || p.isEmpty) return null;
    final d = v['data'];
    return Voce(
      percorso: p,
      dimensione: (v['dimensione'] as num?)?.toInt() ?? 0,
      mtime: DateTime.fromMillisecondsSinceEpoch(
          (v['mtime'] as num?)?.toInt() ?? 0),
      tipo: '${v['tipo'] ?? 'foto'}',
      data: d is num ? DateTime.fromMillisecondsSinceEpoch(d.toInt()) : null,
      fonte: '${v['fonte'] ?? ''}',
      fiducia: '${v['fiducia'] ?? 'nessuna'}',
      daControllare: v['daControllare'] == true,
      larghezza: (v['larghezza'] as num?)?.toInt() ?? 0,
      altezza: (v['altezza'] as num?)?.toInt() ?? 0,
      orientamento: (v['orientamento'] as num?)?.toInt() ?? 0,
      macchina: '${v['macchina'] ?? ''}',
      lat: (v['lat'] as num?)?.toDouble(),
      lon: (v['lon'] as num?)?.toDouble(),
      durataMs: (v['durataMs'] as num?)?.toInt() ?? 0,
      miniaturaDentro: v['miniaturaDentro'] == true,
    );
  }

  static String _due(int n) => n.toString().padLeft(2, '0');
}

/// Il catalogo: cosa c'è, quando è stato scattato, e in che giorno sta.
///
/// ── Le due cartelle, e perché sono due ─────────────────────────────────────
///
/// L'indice sta nella **cache**: è tutto ricavabile dai file, e buttarlo costa
/// solo una scansione. I **preferiti** stanno nella configurazione, insieme
/// alle cartelle scelte: quelli non si ricavano da niente, e chi svuota una
/// cache non si aspetta di perdere le stelle che ha messo.
///
/// Il giorno che le due cose fossero nello stesso file, la prima pulizia della
/// cache cancellerebbe scelte di una persona senza dirle niente.
///
/// ── Perché a mazzetti, e perché si può fermare ─────────────────────────────
///
/// La prima scansione di questa libreria costa qualche secondo, e quasi tutto
/// è `ffprobe` sui video: 85 ms l'uno. Chi apre la galleria deve vedere le
/// prime fotografie subito, non dopo. E chi la chiude a metà non deve lasciare
/// un processo che continua a frugare.
class Indice {
  final Cartelle cartelle;
  final Datatore datatore;

  /// Dove si tiene il catalogo. Iniettabile per le prove.
  final String percorsoIndice;

  /// Dove si tengono le stelle. Iniettabile per le prove.
  final String percorsoPreferiti;

  Indice({
    Cartelle? cartelle,
    Datatore? datatore,
    String? percorsoIndice,
    String? percorsoPreferiti,
  })  : cartelle = cartelle ?? Cartelle(),
        datatore = datatore ?? Datatore(),
        percorsoIndice = percorsoIndice ?? _inCache('indice.json'),
        percorsoPreferiti = percorsoPreferiti ?? _inConfig('preferiti.json');

  static String _inCache(String nome) {
    return '${MinervaPaths.cache()}/foto/$nome';
  }

  static String _inConfig(String nome) {
    return '${MinervaPaths.config()}/foto/$nome';
  }

  /// Quante voci per mazzetto. Cinquanta come la ricerca del gestore file:
  /// abbastanza da non intasare il canale, poche da vedersi arrivare.
  static const int mazzetto = 50;

  /// Le scansioni in corso, per poterle fermare. La chiave è di chi chiede.
  final Map<String, bool> _vive = {};

  List<Voce> _voci = [];
  bool _caricato = false;

  // ── Leggere e scrivere ─────────────────────────────────────────────────

  List<Voce> get voci {
    if (!_caricato) _carica();
    return _voci;
  }

  void _carica() {
    _caricato = true;
    _voci = [];
    try {
      final f = File(percorsoIndice);
      if (!f.existsSync()) return;
      final d = jsonDecode(f.readAsStringSync());
      if (d is! Map || d['voci'] is! List) return;
      for (final v in d['voci'] as List) {
        final voce = Voce.daJson(v);
        if (voce != null) _voci.add(voce);
      }
    } catch (_) {
      _voci = [];
    }
  }

  void _salva() {
    final f = File(percorsoIndice);
    f.parent.createSync(recursive: true);
    final t = File('$percorsoIndice.nuovo');
    t.writeAsStringSync(
        jsonEncode({
          'versione': 1,
          'quando': DateTime.now().toIso8601String(),
          'voci': [for (final v in _voci) v.toJson()],
        }),
        flush: true);
    t.renameSync(f.path);
  }

  // ── I preferiti ────────────────────────────────────────────────────────

  Set<String> preferiti() {
    try {
      final f = File(percorsoPreferiti);
      if (!f.existsSync()) return {};
      final d = jsonDecode(f.readAsStringSync());
      if (d is List) return d.whereType<String>().toSet();
    } catch (_) {}
    return {};
  }

  Map<String, dynamic> preferito(String percorso, bool si) {
    if (!percorso.startsWith('/')) {
      return {'ok': false, 'error': 'Mi serve il percorso completo.'};
    }
    final p = preferiti();
    if (si) {
      p.add(percorso);
    } else {
      p.remove(percorso);
    }
    final f = File(percorsoPreferiti);
    f.parent.createSync(recursive: true);
    final t = File('$percorsoPreferiti.nuovo');
    t.writeAsStringSync(jsonEncode(p.toList()..sort()), flush: true);
    t.renameSync(f.path);
    // Il percorso torna indietro: la galleria aggiorna la stella di QUELLA
    // miniatura senza rileggere tutto il giorno.
    return {'ok': true, 'percorso': percorso, 'preferito': si, 'quanti': p.length};
  }

  // ── La scansione ───────────────────────────────────────────────────────

  void ferma(String id) => _vive[id] = false;

  /// Guarda le cartelle scelte e aggiorna il catalogo.
  ///
  /// Si fa in tre tempi, e l'ordine non è un dettaglio:
  ///
  /// 1. **Il cammino.** Costa poco (0,4 s su questa casa) e raccoglie percorso,
  ///    dimensione e data di modifica di tutto.
  /// 2. **Il giudizio sugli `mtime`.** Si può dare solo adesso, guardando tutti
  ///    insieme — ma si dà PRIMA di leggere un solo EXIF, così ogni file riceve
  ///    subito la sua risposta definitiva invece di una provvisoria da
  ///    correggere alla fine, con l'interfaccia che vede le date cambiare sotto
  ///    gli occhi.
  /// 3. **La lettura.** Solo per i file nuovi o cambiati: gli altri li si
  ///    riprende dall'indice, e una riapertura non costa niente.
  Stream<Map<String, dynamic>> scansiona(String id) async* {
    _vive[id] = true;
    if (!_caricato) _carica();

    final stato = cartelle.leggi();
    final scelte = (stato['cartelle'] as List).cast<String>();
    final fuori = (stato['escludi'] as List).cast<String>().toSet();

    if (scelte.isEmpty) {
      yield {
        'id': id,
        'fine': true,
        'totale': 0,
        'nessunaCartella': true,
        'proposte': cartelle.proposte(escluse: fuori),
      };
      _vive.remove(id);
      return;
    }

    // ── 1. Il cammino ────────────────────────────────────────────────────
    final trovati = <String, FileStat>{};
    for (final radice in scelte) {
      if (_vive[id] != true) break;
      await for (final _ in _cammina(radice, fuori, trovati, id)) {
        yield {'id': id, 'fase': 'cammino', 'trovati': trovati.length};
      }
    }
    if (_vive[id] != true) {
      yield {'id': id, 'fine': true, 'fermata': true, 'totale': _voci.length};
      _vive.remove(id);
      return;
    }

    // ── 2. Il giudizio sugli mtime, prima di leggere ─────────────────────
    final sospetti = Datatore.secondiDiCopia([
      for (final s in trovati.values) s.modified.millisecondsSinceEpoch ~/ 1000,
    ]);

    // ── 3. La lettura, solo di ciò che è cambiato ────────────────────────
    final vecchie = {for (final v in _voci) v.percorso: v};
    final nuove = <Voce>[];
    var lette = 0;
    var riuse = 0;
    var mazzo = <Map<String, dynamic>>[];

    for (final e in trovati.entries) {
      if (_vive[id] != true) break;
      final vecchia = vecchie[e.key];
      Voce voce;
      if (vecchia != null &&
          vecchia.dimensione == e.value.size &&
          vecchia.mtime.millisecondsSinceEpoch ==
              e.value.modified.millisecondsSinceEpoch) {
        voce = vecchia;
        riuse++;
      } else {
        voce = await _leggi(e.key, e.value, sospetti);
        lette++;
      }
      nuove.add(voce);
      mazzo.add(voce.toJson());

      if (mazzo.length >= mazzetto) {
        yield {'id': id, 'voci': mazzo, 'fine': false};
        mazzo = <Map<String, dynamic>>[];
        // Senza questo il canale resta muto per tutta la scansione: è il
        // difetto che la ricerca del gestore file aveva già incontrato.
        await Future<void>.delayed(Duration.zero);
      }
    }

    final fermata = _vive[id] != true;
    if (!fermata) {
      _voci = nuove;
      _salva();
    }
    _vive.remove(id);

    if (mazzo.isNotEmpty) yield {'id': id, 'voci': mazzo, 'fine': false};
    yield {
      'id': id,
      'fine': true,
      'fermata': fermata,
      'totale': _voci.length,
      'lette': lette,
      'riuse': riuse,
    };
  }

  /// Il cammino a ventaglio, con una coda esplicita.
  ///
  /// Non ricorsivo di proposito: una cartella vicina viene prima di una
  /// lontana, e le prime fotografie arrivano subito. Stessa forma della
  /// ricerca in `ricerca_service.dart`, che questo problema l'aveva già
  /// risolto.
  Stream<void> _cammina(String radice, Set<String> fuori,
      Map<String, FileStat> dentro, String id) async* {
    final coda = <String>[radice];
    var guardate = 0;
    while (coda.isNotEmpty) {
      if (_vive[id] != true) return;
      final qui = coda.removeAt(0);
      List<FileSystemEntity> voci;
      try {
        voci = Directory(qui).listSync(followLinks: false);
      } catch (_) {
        continue;
      }
      for (final v in voci) {
        final nome = v.path.split('/').last;
        if (v is Directory) {
          if (Cartelle.siGuarda(v.path, fuori)) coda.add(v.path);
        } else if (v is File && !nome.startsWith('.') && eMedia(v.path)) {
          try {
            dentro[v.path] = v.statSync();
          } catch (_) {}
        }
      }
      guardate++;
      if (guardate % 20 == 0) {
        yield null;
        await Future<void>.delayed(Duration.zero);
      }
    }
    yield null;
  }

  /// Legge un file: EXIF o `ffprobe`, misure, tipo, e la data decisa.
  Future<Voce> _leggi(
      String percorso, FileStat s, Set<int> sospetti) async {
    final nome = percorso.split('/').last;
    final mtime = s.modified;
    final mtimeUsabile =
        !sospetti.contains(mtime.millisecondsSinceEpoch ~/ 1000);

    if (eVideo(percorso)) {
      final d = await datatore.dettagliVideo(percorso);
      final quando = d['quando'] as DateTime?;
      final scelta = Datatore.decidi(
        percorso: percorso,
        video: quando,
        mtime: mtime,
        mtimeUsabile: mtimeUsabile,
      );
      return Voce(
        percorso: percorso,
        dimensione: s.size,
        mtime: mtime,
        tipo: 'video',
        data: scelta.quando,
        fonte: scelta.fonte,
        fiducia: scelta.fiducia.name,
        daControllare: scelta.daControllare,
        larghezza: (d['larghezza'] as int?) ?? 0,
        altezza: (d['altezza'] as int?) ?? 0,
        durataMs: (d['durataMs'] as int?) ?? 0,
      );
    }

    final e = DatiExif.leggi(percorso);
    final misure = ImageDims.read(percorso);
    final scelta = Datatore.decidi(
      percorso: percorso,
      exif: e.scattata,
      mtime: mtime,
      mtimeUsabile: mtimeUsabile,
    );
    return Voce(
      percorso: percorso,
      dimensione: s.size,
      mtime: mtime,
      tipo: Datatore.eSchermata(nome, haExif: e.scattata != null)
          ? 'schermata'
          : 'foto',
      data: scelta.quando,
      fonte: scelta.fonte,
      fiducia: scelta.fiducia.name,
      daControllare: scelta.daControllare,
      larghezza: misure?.width ?? 0,
      altezza: misure?.height ?? 0,
      orientamento: e.orientamento,
      macchina: e.macchina,
      lat: e.latitudine,
      lon: e.longitudine,
      miniaturaDentro: e.haMiniatura,
    );
  }

  // ── Quello che la galleria chiede ──────────────────────────────────────

  /// I giorni, dal più recente al più vecchio, col conteggio.
  ///
  /// Serve al righello del tempo e alle intestazioni: la galleria può
  /// disegnare la sua struttura senza tirarsi dietro migliaia di voci.
  Map<String, dynamic> panoramica({bool? conSchermate}) {
    final mostra =
        conSchermate ?? (cartelle.leggi()['mostraSchermate'] != false);
    final perGiorno = <String, int>{};
    var senzaData = 0;
    var video = 0;
    var schermate = 0;
    final stelle = preferiti();

    for (final v in voci) {
      if (v.tipo == 'schermata') {
        schermate++;
        if (!mostra) continue;
      }
      if (v.tipo == 'video') video++;
      final g = v.giorno;
      if (g.isEmpty) {
        senzaData++;
        continue;
      }
      perGiorno[g] = (perGiorno[g] ?? 0) + 1;
    }

    final giorni = perGiorno.keys.toList()..sort((a, b) => b.compareTo(a));
    return {
      'ok': true,
      'totale': voci.length,
      'giorni': [
        for (final g in giorni) {'giorno': g, 'quante': perGiorno[g]},
      ],
      'senzaData': senzaData,
      'video': video,
      'schermate': schermate,
      'preferiti': stelle.length,
      'mostraSchermate': mostra,
    };
  }

  /// Le voci di un giorno, dalla più recente alla più vecchia.
  ///
  /// `giorno` vuoto vuol dire «quelle di cui non sappiamo la data»: esistono,
  /// sono 94 in questa casa, e nasconderle sarebbe perderle.
  Map<String, dynamic> giorno(String quale, {bool? conSchermate}) {
    final mostra =
        conSchermate ?? (cartelle.leggi()['mostraSchermate'] != false);
    final stelle = preferiti();
    final dentro = voci.where((v) {
      if (v.tipo == 'schermata' && !mostra) return false;
      return v.giorno == quale;
    }).toList()
      ..sort((a, b) {
        final da = a.data ?? a.mtime;
        final db = b.data ?? b.mtime;
        final c = db.compareTo(da);
        return c != 0 ? c : a.percorso.compareTo(b.percorso);
      });
    return {
      'ok': true,
      'giorno': quale,
      'voci': [
        for (final v in dentro)
          {...v.toJson(), if (stelle.contains(v.percorso)) 'preferito': true},
      ],
    };
  }
}
