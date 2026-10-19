import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../processo_limitato.dart';

/// yt-dlp per Minerva Media: quale eseguibile, quali argomenti, come si
/// leggono le risposte.
///
/// ── Perché nel demone e non nella finestra ───────────────────────────────
///
/// Fino al 18 ottobre 2026 ricerca e download giravano in
/// `minerva-shell/media/MediaBackend.qml`, dentro il processo della finestra:
/// chiudere Media voleva dire perdere il download a metà. Il demone vive per
/// tutta la sessione; la finestra ordina e guarda.
///
/// ── Le regole di questo file ──────────────────────────────────────────────
///
///   · **Nessuna shell.** Ogni valore arriva a yt-dlp come argomento, dopo
///     `--`: un titolo di YouTube è testo di chiunque, e un indirizzo che
///     comincia con `-` non deve poter diventare un'opzione.
///   · **`--ignore-config`.** Un `~/.config/yt-dlp/config` scritto per la
///     riga di comando (un `-o` diverso, un `--exec`) cambierebbe dove
///     finiscono i file e cosa si esegue alla fine.
///   · Le funzioni che costruiscono argomenti e leggono risposte sono pure:
///     le prove le verificano sulle risposte vere salvate, senza rete.
class YtDlp {
  YtDlp({List<String>? candidati}) : candidati = candidati ?? _candidatiDiSerie();

  /// Dove cercarlo, in ordine. Vince la versione più recente, non il primo
  /// trovato: il 18 ottobre c'erano il pacchetto di sistema (2026.08.19) e
  /// una copia pipx dimenticata (2026.03.17) che stava prima nel PATH. Con
  /// YouTube una versione di sette mesi prima spesso non funziona più.
  final List<String> candidati;

  static List<String> _candidatiDiSerie() {
    final casa = Platform.environment['HOME'] ?? '';
    final percorso = (Platform.environment['PATH'] ?? '').split(':');
    return {
      '/usr/bin/yt-dlp',
      for (final d in percorso)
        if (d.isNotEmpty) '$d/yt-dlp',
      if (casa.isNotEmpty) '$casa/.local/bin/yt-dlp',
    }.toList();
  }

  final _arresto = Completer<void>();
  final _pending = <Completer<void>>{};
  bool _closed = false;
  Future<void>? _closing;

  Future<void> chiudi() => _closing ??= _chiudi();
  Future<void> _chiudi() async {
    _closed = true;
    _arresto.complete();
    await Future.wait(_pending.map((c)=>c.future).toList());
  }

  String? _scelto;
  String _versione = '';

  /// La versione dell'eseguibile scelto, per dirla nella pagina («yt-dlp
  /// 2026.08.19»): quando YouTube cambia, è la prima cosa da guardare.
  String get versione => _versione;

  /// L'eseguibile da usare, o null se yt-dlp non c'è.
  Future<String?> eseguibile() async {
    if (_closed) return null;
    final s = _scelto;
    if (s != null) return s;
    String? migliore;
    var migliorVersione = '';
    for (final c in candidati) {
      if (_closed) return null;
      if (!await File(c).exists()) continue;
      try {
        final r = await eseguiLimitato(c, ['--version'],
            limite: const Duration(seconds: 10), massimoCaratteri: 4096, annullamento:_arresto.future, gruppoProcessi:true);
        final v = r.stdout.trim();
        if (!r.ok || !versioneValida(v)) continue;
        if (migliore == null || confrontaVersioni(v, migliorVersione) > 0) {
          migliore = c;
          migliorVersione = v;
        }
      } on ProcessException {
        continue;
      }
    }
    _scelto = migliore;
    _versione = migliorVersione;
    return migliore;
  }

  /// Dimentica la scelta: dopo un aggiornamento di yt-dlp.
  void dimentica() {
    _scelto = null;
    _versione = '';
  }

  int _ricerche = 0;
  Future<Map<String,dynamic>> cerca(String testo, {int quanti = 20, bool playlist = false, int inizio = 1}) async {
    if (_closed) return {'error':'media-closed','voci':[]};
    if (testo.trim().isEmpty || testo.length > 2048 || inizio < 1 || inizio > 100000) return {'error':'invalid-query','voci':[]};
    if (_ricerche >= 2) return {'error':'search-busy','voci':[]};
    _ricerche++;
    final done=Completer<void>();_pending.add(done);
    try {
      final binary = await eseguibile();
      if (binary == null) return {'error':'missing-ytdlp','voci':[]};
      final result = await eseguiLimitato(binary, argomentiElenco(testo,quanti:quanti,playlist:playlist,inizio:inizio),
          limite:const Duration(seconds:90),massimoCaratteri:4*1024*1024,annullamento:_arresto.future,gruppoProcessi:true);
      if (!result.ok) return {'error':result.outputTroncato?'search-output-limit':result.scaduto?'search-timeout':'search-failed','voci':[]};
      return {...leggiElenco(result.stdout,ricerca:!indirizzoAccettabile(testo),inizio:inizio),
              'error':'','versione':versione, 'inizio':inizio,
              'prossimo':inizio + 200, 'paginaPiena':_paginaPiena(result.stdout)};
    } on ProcessException {
      return {'error':'tool-unavailable','voci':[]};
    } finally { _ricerche--;_pending.remove(done);done.complete(); }
  }

  // ── Versioni ──────────────────────────────────────────────────────────

  /// `2026.08.19` o `2026.08.19.1`: le versioni di yt-dlp sono date.
  static bool versioneValida(String v) =>
      RegExp(r'^\d{4}\.\d{2}\.\d{2}(\.\d+)?$').hasMatch(v);

  static int confrontaVersioni(String a, String b) {
    List<int> parti(String v) =>
        v.split('.').map((x) => int.tryParse(x) ?? 0).toList();
    final pa = parti(a), pb = parti(b);
    for (var i = 0; i < 4; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  // ── Cosa si accetta ───────────────────────────────────────────────────

  /// Un indirizzo che si può passare a yt-dlp: solo `https://`, senza spazi
  /// né caratteri di controllo. `http://` no: niente in chiaro.
  static bool indirizzoAccettabile(String s) {
    if (s.length > 2048) return false;
    if (s.contains(RegExp(r'[\s\x00-\x1f\x7f]'))) return false;
    final u = Uri.tryParse(s);
    return u != null && u.scheme == 'https' && u.host.isNotEmpty && u.userInfo.isEmpty;
  }

  /// Le parole di una ricerca: senza a capo né caratteri di controllo, e
  /// non troppo lunghe. Restano argomento, mai pezzo di riga.
  static String testoDiRicerca(String s) {
    final pulito = s.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim();
    return pulito.length <= 200 ? pulito : pulito.substring(0, 200).trim();
  }

  // ── Ricerca ───────────────────────────────────────────────────────────

  /// Argomenti per cercare [testo] su YouTube, o per elencare cosa c'è a un
  /// indirizzo (una playlist, un canale, un video).
  static List<String> argomentiElenco(String testoOIndirizzo,
      {int quanti = 20, bool playlist = false, int inizio = 1}) {
    if (inizio < 1 || inizio > 100000) throw ArgumentError('inizio');
    final n = quanti.clamp(1, 50);
    final indirizzo = indirizzoAccettabile(testoOIndirizzo);
    final bersaglio = indirizzo ? testoOIndirizzo : playlist
        ? Uri.https('www.youtube.com', '/results', {
            'search_query':testoDiRicerca(testoOIndirizzo), 'sp':'EgIQAw==',
          }).toString()
        : 'ytsearch$n:${testoDiRicerca(testoOIndirizzo)}';
    return [
      '--ignore-config', '--no-warnings', '-J', '--flat-playlist',
      '--playlist-start', '$inizio',
      '--playlist-end', '${indirizzo ? inizio + 199 : n}',
      '--', bersaglio,
    ];
  }

  static bool _paginaPiena(String raw) {
    try {
      final data = jsonDecode(raw);
      return data is Map && data['entries'] is List && (data['entries'] as List).length >= 200;
    } on FormatException { return false; }
  }

  /// null significa tutta la playlist; [] non significa mai «tutti».
  static List<int>? selezioneValida(List<int>? indici, {required bool playlist}) {
    if (indici == null) return null;
    if (!playlist || indici.isEmpty || indici.length > 10000 ||
        indici.any((i) => i < 1 || i > 100000)) {
      throw ArgumentError('selezione playlist non valida');
    }
    return List<int>.unmodifiable(indici.toSet().toList()..sort());
  }

  /// Legge la risposta di `-J`: un video solo, o una playlist (anche una
  /// ricerca è una «playlist» per yt-dlp).
  ///
  /// Ritorna `{tipo, titolo, id, url, voci}` dove `tipo` è `video`,
  /// `playlist` o `ricerca`, e ogni voce è `{tipo, id, titolo, durata,
  /// canale, url, miniatura}` con `tipo` `video` o `playlist` (un canale
  /// elenca playlist).
  static Map<String, dynamic> leggiElenco(String json, {bool ricerca = false, int inizio = 1}) {
    final Object? d;
    try {
      d = jsonDecode(json);
    } on FormatException {
      return {'tipo': 'vuoto', 'titolo': '', 'id': '', 'url': '', 'voci': []};
    }
    if (d is! Map) {
      return {'tipo': 'vuoto', 'titolo': '', 'id': '', 'url': '', 'voci': []};
    }
    if (d['_type'] != 'playlist') {
      return {
        'tipo': 'video',
        'titolo': '${d['title'] ?? ''}',
        'id': '${d['id'] ?? ''}',
        'url': '${d['webpage_url'] ?? d['original_url'] ?? ''}',
        'voci': [_voce(d)],
      };
    }
    final voci = <Map<String, dynamic>>[];
    final entries = d['entries'];
    if (entries is List) {
      for (var offset = 0; offset < entries.length; offset++) {
        final e = entries[offset];
        if (e is Map && '${e['title'] ?? ''}'.isNotEmpty) {
          voci.add({..._voce(e), 'indice': e['playlist_index'] is int
              ? e['playlist_index'] : inizio + offset});
        }
      }
    }
    return {
      'tipo': ricerca ? 'ricerca' : 'playlist',
      'titolo': '${d['title'] ?? ''}',
      'id': '${d['id'] ?? ''}',
      'url': '${d['webpage_url'] ?? d['original_url'] ?? ''}',
      'quanti': d['playlist_count'] is int ? d['playlist_count'] : voci.length,
      'voci': voci,
    };
  }

  static Map<String, dynamic> _voce(Map e) {
    final url = '${e['url'] ?? e['webpage_url'] ?? ''}';
    final id = '${e['id'] ?? ''}';
    // Un canale elenca playlist: `ie_key` YoutubeTab, indirizzo
    // `…/playlist?list=…`. Si scaricano intere, non si riproducono.
    final playlist = e['ie_key'] == 'YoutubeTab' || url.contains('/playlist?list=');
    return {
      'indice': 0,
      'tipo': playlist ? 'playlist' : 'video',
      'id': id,
      'titolo': '${e['title'] ?? ''}',
      'durata': e['duration'] is num ? (e['duration'] as num).round() : 0,
      'canale': '${e['channel'] ?? e['uploader'] ?? ''}',
      'url': url.startsWith('https://')
          ? url
          : (id.isNotEmpty && !playlist ? 'https://www.youtube.com/watch?v=$id' : ''),
      'miniatura': _miniatura(e, id, playlist),
      'dal_vivo': e['live_status'] == 'is_live',
    };
  }

  /// La più piccola che basta a una riga d'elenco (≥ 320 px di larghezza),
  /// non la più grande: sessanta righe sono sessanta immagini.
  static String _miniatura(Map e, String id, bool playlist) {
    final t = e['thumbnails'];
    if (t is List) {
      final validi = t
          .whereType<Map>()
          .where((x) => '${x['url'] ?? ''}'.startsWith('https://'))
          .toList();
      int larghezza(Map x) => x['width'] is num ? (x['width'] as num).toInt() : 0;
      Map? scelta;
      for (final x in validi) {
        final w = larghezza(x);
        if (w >= 320 && (scelta == null || w < larghezza(scelta))) scelta = x;
      }
      // Nessuna abbastanza larga (o nessuna larghezza dichiarata): l'ultima,
      // che in yt-dlp è la più grande.
      scelta ??= validi.isEmpty ? null : validi.last;
      if (scelta != null) return '${scelta['url']}';
    }
    if (!playlist && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) {
      return 'https://i.ytimg.com/vi/$id/mqdefault.jpg';
    }
    return '';
  }

  // ── Download ──────────────────────────────────────────────────────────

  /// Il segnaposto delle righe che leggiamo noi: tutto il resto è di yt-dlp.
  static const String segno = '[liquid]';

  /// Argomenti per scaricare.
  ///
  /// [cartellaDiLavoro] tiene i file intermedi (vedi `-P temp:`).
  ///
  /// [cartella] è la cartella Musica o Video; una playlist ci mette dentro
  /// una sottocartella col proprio nome. [archivio], solo per le playlist,
  /// è il file dove yt-dlp segna cosa ha già scaricato: rilanciare la stessa
  /// playlist riprende da dove si era fermata e salta i doppioni.
  static List<String> argomentiDownload({
    required String indirizzo,
    required bool audio,
    required bool playlist,
    required String cartella,
    required String cartellaDiLavoro,
    String formatoAudio = 'mp3',
    int altezzaMassima = 0,
    String? archivio,
    List<int>? indici,
  }) {
    final scelti = selezioneValida(indici, playlist:playlist);
    final qualitySuffix = audio ? '' : altezzaMassima > 0 ? ' [max${altezzaMassima}p]' : ' [best]';
    final fileName = '%(title)s [%(id)s]$qualitySuffix.%(ext)s';
    final fuori = <String>[
      '--ignore-config',
      '--no-warnings',
      '--newline',
      '--no-colors',
      '--output-na-placeholder', 'null',
      // `--print` mette yt-dlp in silenzio; `--progress` rimette la barra,
      // che con il modello qui sotto diventa una riga che sappiamo leggere.
      '--progress',
      '--progress-template',
      'download:$segno {"tipo":"avanzamento","scaricati":%(progress.downloaded_bytes)j,'
          '"totale":%(progress.total_bytes,progress.total_bytes_estimate)j,'
          '"velocita":%(progress.speed)j,"eta":%(progress.eta)j,'
          '"indice":%(info.playlist_index)j,"voci":%(info.n_entries)j}',
      '--print', 'before_dl:$segno {"tipo":"inizio","indice":%(playlist_index)j,"titolo":%(title)j}',
      '--print', 'after_move:$segno {"tipo":"fatto","percorso":%(filepath)j}',
      '--no-simulate',
      // La data del file è quella del download: con la data di
      // pubblicazione un video scaricato adesso spariva in fondo ai
      // «recenti» del gestore file.
      '--no-mtime',
      // Nomi che si possono copiare su una chiavetta (exFAT, NTFS): niente
      // `:` `?` `"`… Gli accenti restano, a differenza di
      // `--restrict-filenames`.
      '--windows-filenames',
      '--embed-metadata',
      '-P', cartella,
      // Parziali (`.part`), copertine e pezzi da unire stanno qui, non nella
      // cartella Musica: il 18 ottobre un download fallito ci aveva lasciato
      // una copertina `.jpg` orfana. Nella cartella vera arriva solo il file
      // finito; la cartella di lavoro di una playlist resta uguale da un
      // tentativo all'altro, così i `.part` riprendono.
      '-P', 'temp:$cartellaDiLavoro',
      '-o',
      playlist
          ? '%(playlist_title,playlist_id|Playlist)s/%(playlist_index)03d - $fileName'
          : fileName,
      playlist ? '--yes-playlist' : '--no-playlist',
      if (playlist && archivio != null) ...['--download-archive', archivio],
      if (scelti != null) ...['--playlist-items', scelti.join(',')],
    ];
    if (audio) {
      final f = const {'mp3', 'm4a', 'opus'}.contains(formatoAudio)
          ? formatoAudio
          : 'mp3';
      fuori.addAll([
        '-x',
        '--audio-format', f,
        // mp3 a 192k come prima (il formato dei telefoni); m4a e opus
        // nella qualità migliore che il video offre.
        '--audio-quality', f == 'mp3' ? '192K' : '0',
      ]);
      // La copertina dentro il file: mp3 e m4a la tengono senza moduli in
      // più; opus vorrebbe `mutagen`, e senza il passo fallirebbe.
      if (f != 'opus') {
        fuori.addAll(['--embed-thumbnail', '--convert-thumbnails', 'jpg']);
      }
    } else {
      fuori.addAll([
        '-f', altezzaMassima > 0 ? 'bv*[height<=$altezzaMassima]+ba/b[height<=$altezzaMassima]' : 'bv*+ba/b',
        // Fino all'altezza scelta, e a parità mp4+m4a: è il formato che
        // apre qualunque lettore, telefono e TV compresi.
        '-S', altezzaMassima > 0 ? 'res:$altezzaMassima,ext:mp4:m4a' : 'ext:mp4:m4a',
        '--merge-output-format', 'mp4',
        '--embed-thumbnail',
      ]);
    }
    fuori.addAll(['--', indirizzo]);
    return fuori;
  }

  /// Una riga d'uscita del download, se è nostra.
  ///
  /// `avanzamento` → `{tipo, scaricati, totale, velocita, eta, indice, voci}`
  /// (numeri, 0 se yt-dlp non li sa); `inizio` → `{tipo, indice, titolo}`;
  /// `fatto` → `{tipo, percorso}`.
  static Map<String, dynamic>? leggiRiga(String riga) {
    if (!riga.startsWith('$segno ') || riga.length > 65536) return null;
    const i = 0;
    final resto = riga.substring(i + segno.length).trimLeft();
    if (resto.startsWith('{')) {
      try {
        final data = jsonDecode(resto);
        if (data is! Map<String, dynamic>) return null;
        num number(String key) {
          final value = data[key];
          return value is num && value.isFinite && value >= 0 ? value : 0;
        }
        switch (data['tipo']) {
          case 'avanzamento':
            return {'tipo':'avanzamento', for(final key in ['scaricati','totale','velocita','eta','indice','voci']) key:number(key)};
          case 'inizio':
            return data['titolo'] is String ? {'tipo':'inizio','indice':number('indice').toInt(),'titolo':data['titolo']} : null;
          case 'fatto':
            return data['percorso'] is String ? {'tipo':'fatto','percorso':data['percorso']} : null;
        }
      } on FormatException { return null; }
      return null;
    }
    final spazio = resto.indexOf(' ');
    if (spazio < 0) return null;
    final tipo = resto.substring(0, spazio);
    final corpo = resto.substring(spazio + 1);
    num numero(String s) {
      final value = num.tryParse(s);
      return value != null && value.isFinite && value >= 0 ? value : 0;
    }
    switch (tipo) {
      case 'avanzamento':
        final p = corpo.trim().split(RegExp(r'\s+'));
        if (p.length < 6) return null;
        return {
          'tipo': 'avanzamento',
          'scaricati': numero(p[0]),
          'totale': numero(p[1]),
          'velocita': numero(p[2]),
          'eta': numero(p[3]),
          'indice': numero(p[4]).toInt(),
          'voci': numero(p[5]).toInt(),
        };
      case 'inizio':
        final s = corpo.indexOf(' ');
        return {
          'tipo': 'inizio',
          'indice': s < 0 ? 0 : numero(corpo.substring(0, s)).toInt(),
          'titolo': s < 0 ? corpo : corpo.substring(s + 1),
        };
      case 'fatto':
        return {'tipo': 'fatto', 'percorso': corpo};
    }
    return null;
  }

  /// Una spiegazione per chi guarda, dall'ultima riga d'errore di yt-dlp.
  static String spiegaErrore(String stderr) {
    final righe = stderr
        .split('\n')
        .map((r) => r.trim())
        .where((r) => r.startsWith('ERROR:'))
        .toList();
    final r = righe.isEmpty ? stderr.trim().split('\n').last.trim() : righe.last;
    if (r.contains('Sign in to confirm') || r.contains('not a bot')) {
      return 'YouTube chiede di confermare che non sei un robot: riprova più tardi.';
    }
    if (r.contains('Private video')) return 'Il video è privato.';
    // Vimeo dal 2026, e altri: senza un account il sito non dà niente.
    if (r.contains('logged-in') || r.contains('--cookies') ||
        r.contains('login required') || r.contains('Login required')) {
      return 'Questo sito vuole che tu entri con un account: così non si può scaricare.';
    }
    if (r.contains('Access forbidden') || r.contains('geo restrict') ||
        r.contains('not available in your country')) {
      return 'Il sito non lo permette da qui (accesso negato o blocco per paese).';
    }
    if (r.contains('Video unavailable')) return 'Il video non è disponibile.';
    if (r.contains('ffmpeg') && r.contains('not found')) {
      return 'Manca ffmpeg: serve per unire audio e video e per convertire.';
    }
    if (r.contains('HTTP Error 403') || r.contains('nsig') ||
        r.contains('Unable to extract') || r.contains('Signature extraction')) {
      return 'YouTube è cambiato e questa versione di yt-dlp non basta più: '
          'aggiornala.';
    }
    if (r.contains('No space left')) return 'Il disco è pieno.';
    final pulita = r.replaceFirst(RegExp(r'^ERROR:\s*(\[[^\]]+\]\s*)?'), '');
    return pulita.isEmpty ? 'yt-dlp non è riuscito.' : pulita;
  }
}
