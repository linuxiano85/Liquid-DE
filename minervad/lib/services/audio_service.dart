import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// AudioService — Quello che serve a Minerva Suono e che la finestra non può
/// fare da sé: leggere com'è fatto un file audio, ricavarne l'onda da
/// disegnare, e tagliarne un pezzo.
///
/// ── PERCHÉ L'ONDA LA CALCOLA IL DEMONE ─────────────────────────────────────
///
/// Perché in QML non c'è modo di leggere i campioni di un mp3. `MediaPlayer`
/// lo SUONA e basta: sa dire a che punto è arrivato, non che cosa c'è dentro.
/// Un lettore che mostra solo una barra di avanzamento è un lettore in cui non
/// si trova niente — e qui il mestiere è proprio trovare: il ritornello, la
/// battuta, i due secondi buoni per una notifica. Quei due secondi si
/// riconoscono a occhio in un istante e a orecchio in mezzo minuto.
///
/// ── COME SI RICAVA, E PERCHÉ COSÌ ──────────────────────────────────────────
///
/// `ffmpeg` decodifica in PCM grezzo su standard output, mono a 8000 Hz, e noi
/// contiamo i picchi. Tre scelte non ovvie:
///
///  · **mono**: due canali darebbero due onde quasi identiche e il doppio del
///    lavoro. L'onda serve per orientarsi, non per masterizzare.
///  · **8000 Hz**: la voce sta tutta lì sotto, e per un'onda a 1200 barre su
///    quattro minuti sono comunque 1600 campioni per barra. Scendere ancora
///    farebbe sparire i colpi brevi — un rullante diventerebbe invisibile.
///  · **a flusso, non tutto in memoria**: un podcast di un'ora sono 57 MB di
///    PCM. Si contano i picchi mentre arrivano e si tiene solo il risultato,
///    che sono 1200 numeri.
///
/// ── LA CACHE, CHE NON È UNA MICRO-OTTIMIZZAZIONE ───────────────────────────
///
/// Mezzo secondo per una canzone. Sembra poco, e lo è — la prima volta. Ma
/// l'onda si ricalcola a ogni apertura, e chi ritaglia una suoneria apre lo
/// stesso file dieci volte di fila: la decima attesa è la stessa della prima, e
/// a quel punto il programma «è lento». La chiave tiene dentro anche data e
/// peso del file: se il file cambia, l'onda vecchia non viene riusata.
class AudioService {
  AudioService({
    this.ffmpeg = 'ffmpeg',
    this.ffprobe = 'ffprobe',
    String? cartellaCache,
  }) : _cacheOverride = cartellaCache;

  final String ffmpeg;
  final String ffprobe;
  final String? _cacheOverride;

  /// Quanti campioni al secondo si decodificano per disegnare l'onda.
  static const int frequenzaOnda = 8000;

  /// I formati in cui sappiamo salvare un pezzo, nell'ordine in cui ha senso
  /// proporli.
  ///
  /// L'ordine è un consiglio, non un'estetica: chi taglia un pezzo di audio
  /// quasi sempre lo vuole per il telefono (MP3 lo suona qualunque cosa) o per
  /// un avviso di sistema (WAV, che è l'unico che `SoundEffect` di Qt sa
  /// aprire — e quindi l'unico che Minerva stessa può usare come notifica).
  static const List<Map<String, dynamic>> formati = [
    {
      'id': 'mp3',
      'estensione': '.mp3',
      'nome': 'MP3',
      'nota': 'Lo suonano tutti, telefoni compresi',
      'nota_en': 'Everything plays it, phones included',
    },
    {
      'id': 'wav',
      'estensione': '.wav',
      'nome': 'WAV',
      'nota': 'Senza perdite. È il formato dei suoni di Minerva',
      'nota_en': 'Lossless. The format of Minerva\'s own sounds',
    },
    {
      'id': 'ogg',
      'estensione': '.ogg',
      'nome': 'OGG Vorbis',
      'nota': 'Leggero e libero',
      'nota_en': 'Small and free',
    },
    {
      'id': 'opus',
      'estensione': '.opus',
      'nome': 'Opus',
      'nota': 'Il più leggero a parità di resa',
      'nota_en': 'The smallest for the same quality',
    },
    {
      'id': 'm4a',
      'estensione': '.m4a',
      'nome': 'AAC (M4A)',
      'nota': 'Per iPhone e iPad',
      'nota_en': 'For iPhone and iPad',
    },
    {
      'id': 'flac',
      'estensione': '.flac',
      'nome': 'FLAC',
      'nota': 'Senza perdite e compresso',
      'nota_en': 'Lossless and compressed',
    },
  ];

  /// Le estensioni che dichiariamo di saper aprire. La stessa lista sta nel
  /// file `.desktop`: è la promessa che facciamo al resto del sistema, e le due
  /// devono dire la stessa cosa.
  static const List<String> estensioni = [
    '.mp3', '.flac', '.ogg', '.oga', '.opus', '.m4a', '.aac', '.wav',
    '.wma', '.aiff', '.aif', '.ape', '.mka', '.mp2', '.ac3', '.amr',
  ];

  static Map<String, dynamic>? _formato(String id) {
    for (final f in formati) {
      if (f['id'] == id) return f;
    }
    return null;
  }

  // ── Com'è fatto ──────────────────────────────────────────────────────────

  /// Durata, formato e cartellino del file. Tutto quello che serve alla
  /// finestra per intitolarsi e per sapere quanto è lungo il nastro.
  ///
  /// La durata la si chiede a `ffprobe` e non a `MediaPlayer` per una ragione
  /// di ordine: l'onda va disegnata PRIMA che il lettore abbia finito di
  /// caricare, altrimenti la finestra si apre vuota e poi sussulta.
  Future<Map<String, dynamic>> info(String path) async {
    final f = File(path);
    if (!await f.exists()) {
      return {'ok': false, 'errore': 'Il file non esiste', 'path': path};
    }

    ProcessResult r;
    try {
      r = await Process.run(ffprobe, [
        '-v', 'quiet',
        '-print_format', 'json',
        '-show_format',
        '-show_streams',
        '-select_streams', 'a:0',
        path,
      ]);
    } on ProcessException catch (e) {
      return {'ok': false, 'errore': 'ffprobe non disponibile: ${e.message}'};
    }

    if (r.exitCode != 0) {
      return {'ok': false, 'errore': 'Non è un file audio leggibile', 'path': path};
    }

    Map<String, dynamic> j;
    try {
      j = jsonDecode(r.stdout as String) as Map<String, dynamic>;
    } catch (_) {
      return {'ok': false, 'errore': 'Risposta di ffprobe illeggibile'};
    }

    final flussi = (j['streams'] as List?) ?? const [];
    if (flussi.isEmpty) {
      return {'ok': false, 'errore': 'Nel file non c\'è audio', 'path': path};
    }
    final s = flussi.first as Map<String, dynamic>;
    final formato = (j['format'] as Map<String, dynamic>?) ?? const {};

    // La durata sta in due posti e a volte in uno solo dei due: certi flussi
    // non la dichiarano, certi contenitori sì. Si prende la prima che c'è.
    double durata = _numero(s['duration']);
    if (durata <= 0) durata = _numero(formato['duration']);

    final tag = <String, dynamic>{};
    for (final fonte in [formato['tags'], s['tags']]) {
      if (fonte is Map) {
        fonte.forEach((k, v) => tag[k.toString().toLowerCase()] = v);
      }
    }

    return {
      'ok': true,
      'path': path,
      'nome': path.substring(path.lastIndexOf('/') + 1),
      'durata': durata,
      'codec': s['codec_name'] ?? '',
      'codecNome': s['codec_long_name'] ?? '',
      'canali': s['channels'] ?? 0,
      'frequenza': int.tryParse('${s['sample_rate']}') ?? 0,
      'bitrate': int.tryParse('${formato['bit_rate'] ?? s['bit_rate']}') ?? 0,
      'peso': int.tryParse('${formato['size']}') ?? await f.length(),
      'titolo': tag['title'] ?? '',
      'artista': tag['artist'] ?? tag['album_artist'] ?? '',
      'album': tag['album'] ?? '',
    };
  }

  static double _numero(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0.0;
  }

  // ── L'onda ───────────────────────────────────────────────────────────────

  /// I picchi del file, `barre` numeri da 0 a 100.
  ///
  /// Normalizzati sul picco più alto del brano e non sul fondo scala: una
  /// registrazione fatta piano darebbe altrimenti una riga piatta, e una riga
  /// piatta non aiuta a trovare niente. Quello che conta qui è la FORMA.
  Future<Map<String, dynamic>> onda(String path, {int barre = 1200}) async {
    barre = barre.clamp(64, 6000);

    final f = File(path);
    if (!await f.exists()) {
      return {'ok': false, 'errore': 'Il file non esiste', 'path': path};
    }
    final st = await f.stat();

    final cache = _fileCache(path, st, barre);
    if (cache != null && await cache.exists()) {
      try {
        final j = jsonDecode(await cache.readAsString()) as Map<String, dynamic>;
        if (j['barre'] is List) {
          return {
            'ok': true,
            'path': path,
            'durata': _numero(j['durata']),
            'barre': j['barre'],
            'daCache': true,
          };
        }
      } catch (_) {
        // Una cache illeggibile non è un errore: si ricalcola.
      }
    }

    final dati = await info(path);
    if (dati['ok'] != true) return dati;
    final durata = _numero(dati['durata']);
    if (durata <= 0) {
      return {'ok': false, 'errore': 'Il file non dichiara una durata', 'path': path};
    }

    final campioniPerBarra =
        math.max(1, (durata * frequenzaOnda / barre).round());

    Process p;
    try {
      p = await Process.start(ffmpeg, [
        '-v', 'quiet',
        '-i', path,
        '-vn',
        '-f', 's16le',
        '-ac', '1',
        '-ar', '$frequenzaOnda',
        '-',
      ]);
    } on ProcessException catch (e) {
      return {'ok': false, 'errore': 'ffmpeg non disponibile: ${e.message}'};
    }

    // Va svuotato comunque: un processo che scrive su un tubo che nessuno
    // legge si blocca, e resterebbe lì per sempre.
    unawaited(p.stderr.drain<void>());

    final picchi = <int>[];
    var picco = 0;
    var contati = 0;
    var avanzo = -1; // il byte basso rimasto a cavallo di due blocchi

    void aggiungi(int v) {
      if (v > picco) picco = v;
      contati++;
      if (contati >= campioniPerBarra) {
        picchi.add(picco);
        picco = 0;
        contati = 0;
      }
    }

    await for (final blocco in p.stdout) {
      var i = 0;
      if (avanzo >= 0 && blocco.isNotEmpty) {
        aggiungi(_campione(avanzo, blocco[0]));
        avanzo = -1;
        i = 1;
      }
      for (; i + 1 < blocco.length; i += 2) {
        aggiungi(_campione(blocco[i], blocco[i + 1]));
      }
      if (i < blocco.length) avanzo = blocco[i];
    }
    if (contati > 0) picchi.add(picco);

    final uscita = await p.exitCode;
    if (uscita != 0 && picchi.isEmpty) {
      return {'ok': false, 'errore': 'ffmpeg non è riuscito a leggere il file'};
    }

    // Il conto dei campioni per barra è una stima: se la durata dichiarata non
    // combacia col decodificato si finisce con qualche barra in più o in meno.
    // Si pareggia qui, così chi disegna sa sempre quante ne riceve.
    while (picchi.length < barre) {
      picchi.add(0);
    }
    if (picchi.length > barre) picchi.removeRange(barre, picchi.length);

    var massimo = 0;
    for (final v in picchi) {
      if (v > massimo) massimo = v;
    }
    final scala = massimo > 0 ? 100.0 / massimo : 0.0;
    final normalizzati = [for (final v in picchi) (v * scala).round()];

    if (cache != null) {
      try {
        await cache.parent.create(recursive: true);
        await cache.writeAsString(
            jsonEncode({'durata': durata, 'barre': normalizzati}));
      } catch (_) {
        // Se la cache non si può scrivere si va avanti lo stesso: è un
        // acceleratore, non un pezzo del meccanismo.
      }
    }

    return {
      'ok': true,
      'path': path,
      'durata': durata,
      'barre': normalizzati,
      'daCache': false,
    };
  }

  static int _campione(int basso, int alto) {
    var v = basso | (alto << 8);
    if (v >= 32768) v -= 65536;
    return v.abs();
  }

  File? _fileCache(String path, FileStat st, int barre) {
    final base = _cartellaCache();
    if (base == null) return null;
    final chiave = _impronta('$path|${st.modified.millisecondsSinceEpoch}'
        '|${st.size}|$barre|$frequenzaOnda');
    return File('$base/onde/$chiave.json');
  }

  String? _cartellaCache() {
    if (_cacheOverride != null) return _cacheOverride;
    final env = Platform.environment;
    final c = env['XDG_CACHE_HOME'];
    if (c != null && c.isNotEmpty) return '$c/minerva';
    final home = env['HOME'];
    if (home == null || home.isEmpty) return null;
    return '$home/.cache/minerva';
  }

  /// FNV-1a a 64 bit. Serve un nome di file corto e stabile, non una firma:
  /// niente librerie da aggiungere per questo.
  static String _impronta(String s) {
    var h = 0xcbf29ce484222325;
    for (final u in s.codeUnits) {
      h ^= u;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return h.toRadixString(36);
  }

  // ── Il taglio ────────────────────────────────────────────────────────────

  /// Salva il pezzo fra `inizio` e `fine` (secondi) dentro `destinazione`.
  ///
  /// ── PERCHÉ SI RICODIFICA SEMPRE ──────────────────────────────────────────
  ///
  /// `-c copy` sarebbe istantaneo, e sbagliato: un mp3 si può tagliare solo
  /// sui confini dei suoi blocchi, quindi il pezzo comincerebbe fino a
  /// ventisei millisecondi prima o dopo il punto scelto — e soprattutto non si
  /// potrebbe sfumare. Una suoneria che parte con uno scoppio è il difetto più
  /// comune di questo mestiere, ed è esattamente quello che le dissolvenze
  /// esistono per togliere.
  ///
  /// ── L'ORDINE DEI FILTRI NON È INDIFFERENTE ───────────────────────────────
  ///
  /// Prima si normalizza, poi si sfuma. Al contrario, il normalizzatore
  /// vedrebbe la dissolvenza come un calo di volume da correggere e la
  /// spianerebbe: si sarebbe chiesta una sfumatura e si otterrebbe un gradino.
  Future<Map<String, dynamic>> taglia({
    required String sorgente,
    required String destinazione,
    required double inizio,
    required double fine,
    String formato = 'mp3',
    double dissolvenzaIn = 0,
    double dissolvenzaOut = 0,
    bool normalizza = false,
  }) async {
    if (!await File(sorgente).exists()) {
      return {'ok': false, 'errore': 'Il file di partenza non esiste'};
    }
    if (inizio < 0) inizio = 0;
    final durata = fine - inizio;
    if (durata <= 0.02) {
      return {'ok': false, 'errore': 'La selezione è troppo corta'};
    }

    final f = _formato(formato);
    if (f == null) {
      return {'ok': false, 'errore': 'Formato sconosciuto: $formato'};
    }

    // La destinazione arriva col nome che ha scelto chi taglia; l'estensione
    // la decide il formato, perché è quella che dice al resto del sistema che
    // cosa c'è dentro.
    var dest = destinazione;
    final est = f['estensione'] as String;
    if (!dest.toLowerCase().endsWith(est)) {
      final punto = dest.lastIndexOf('.');
      final barra = dest.lastIndexOf('/');
      if (punto > barra && punto > 0) dest = dest.substring(0, punto);
      dest = '$dest$est';
    }

    if (dest == sorgente) {
      return {
        'ok': false,
        'errore': 'Non si può salvare il pezzo sopra il file di partenza'
      };
    }

    final cartella = Directory(dest.substring(0, dest.lastIndexOf('/')));
    try {
      if (!await cartella.exists()) await cartella.create(recursive: true);
    } on FileSystemException catch (e) {
      return {'ok': false, 'errore': 'Non posso scrivere lì: ${e.message}'};
    }

    // Mai sopra un file che c'è già, e senza chiedere niente: chi taglia dieci
    // pezzi dalla stessa canzone li vuole tutti e dieci, non l'ultimo.
    dest = await _libero(dest, est);

    // Le dissolvenze non possono essere più lunghe del pezzo: due sfumature da
    // tre secondi su un pezzo da quattro si sovrapporrebbero e il centro
    // resterebbe muto. Si stringono invece di rifiutare.
    var fin = math.max(0.0, dissolvenzaIn);
    var fout = math.max(0.0, dissolvenzaOut);
    if (fin + fout > durata) {
      final k = durata / (fin + fout);
      fin *= k;
      fout *= k;
    }

    final filtri = <String>[];
    if (normalizza) {
      // I valori sono quelli della raccomandazione EBU R128 per il parlato e
      // la musica da ascolto; `TP=-1.5` lascia il margine che serve a non far
      // saturare i codificatori con perdita subito dopo.
      filtri.add('loudnorm=I=-16:TP=-1.5:LRA=11');
    }
    if (fin > 0.01) {
      filtri.add('afade=t=in:st=0:d=${fin.toStringAsFixed(3)}');
    }
    if (fout > 0.01) {
      final quando = durata - fout;
      filtri.add(
          'afade=t=out:st=${quando.toStringAsFixed(3)}:d=${fout.toStringAsFixed(3)}');
    }

    final args = <String>[
      '-nostdin',
      '-v', 'error',
      // `-ss` PRIMA di `-i`: così ffmpeg salta al punto invece di decodificare
      // e buttare via tutto quello che viene prima. Su un file di un'ora è la
      // differenza fra un istante e mezzo minuto — ed è accurato al campione
      // da ffmpeg 2.1 in avanti, quando `-ss` davanti smise di essere solo
      // approssimativo.
      '-ss', inizio.toStringAsFixed(3),
      '-t', durata.toStringAsFixed(3),
      '-i', sorgente,
      // Via la copertina: è un flusso video travestito, e mezzo mondo non sa
      // che farsene dentro una suoneria.
      '-vn',
      '-map_metadata', '0',
    ];
    if (filtri.isNotEmpty) args.addAll(['-af', filtri.join(',')]);
    args.addAll((f['codifica'] as List<String>?) ?? _codifica(formato));
    args.add(dest);

    ProcessResult r;
    try {
      r = await Process.run(ffmpeg, args);
    } on ProcessException catch (e) {
      return {'ok': false, 'errore': 'ffmpeg non disponibile: ${e.message}'};
    }

    if (r.exitCode != 0) {
      // Se è fallito a metà resta un file monco col nome giusto: chi lo trova
      // domani crede di avere una suoneria e ha un rumore.
      try {
        final avanzo = File(dest);
        if (await avanzo.exists()) await avanzo.delete();
      } catch (_) {}
      final msg = (r.stderr as String).trim();
      return {
        'ok': false,
        'errore': msg.isEmpty ? 'ffmpeg è tornato con errore' : msg.split('\n').last,
      };
    }

    final uscita = File(dest);
    return {
      'ok': true,
      'path': dest,
      'nome': dest.substring(dest.lastIndexOf('/') + 1),
      'cartella': dest.substring(0, dest.lastIndexOf('/')),
      'peso': await uscita.exists() ? await uscita.length() : 0,
      'durata': durata,
    };
  }

  static List<String> _codifica(String id) {
    switch (id) {
      case 'wav':
        // 16 bit interi: è quello che `SoundEffect` di Qt sa aprire, e quindi
        // l'unico modo perché il pezzo possa diventare un suono di Minerva.
        return ['-c:a', 'pcm_s16le'];
      case 'ogg':
        return ['-c:a', 'libvorbis', '-q:a', '5'];
      case 'opus':
        return ['-c:a', 'libopus', '-b:a', '96k'];
      case 'm4a':
        return ['-c:a', 'aac', '-b:a', '192k'];
      case 'flac':
        return ['-c:a', 'flac'];
      case 'mp3':
      default:
        // `-q:a 2` è VBR intorno ai 190 kb/s: indistinguibile dall'originale
        // per un pezzo di trenta secondi, e la metà del posto di un CBR 320.
        return ['-c:a', 'libmp3lame', '-q:a', '2'];
    }
  }

  /// Il primo nome libero: `pezzo.mp3`, poi `pezzo (2).mp3`, e così via.
  static Future<String> _libero(String dest, String estensione) async {
    if (!await File(dest).exists()) return dest;
    final senza = dest.substring(0, dest.length - estensione.length);
    for (var n = 2; n < 1000; n++) {
      final tentativo = '$senza ($n)$estensione';
      if (!await File(tentativo).exists()) return tentativo;
    }
    return '$senza (${DateTime.now().millisecondsSinceEpoch})$estensione';
  }
}
