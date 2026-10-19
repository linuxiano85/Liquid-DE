import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'yt_dlp.dart';
import '../../util/sha256.dart';
import '../../core/linux_files.dart';

/// La coda dei download di Minerva Media.
///
/// ── Cosa fa ──────────────────────────────────────────────────────────────
///
/// Un lavoro è un indirizzo (video o playlist) da scaricare in audio o in
/// video. I lavori vivono nel demone: chiudere Media non li ferma, e chi
/// riapre la finestra li ritrova (`elenco`). Due alla volta: YouTube rallenta
/// chi apre troppe connessioni, e un terzo download in parallelo non finisce
/// prima, finiscono tutti dopo.
///
/// ── Dove vanno i file ────────────────────────────────────────────────────
///
/// Audio nella cartella Musica, video nella cartella Video (quelle di
/// `user-dirs.dirs`, nella lingua del sistema); una playlist nella sua
/// sottocartella. I pezzi intermedi stanno in una cartella di lavoro in
/// `~/.cache/liquid-de/media/`, una per playlist: un download interrotto e
/// rilanciato riprende i `.part` e salta (con l'archivio) ciò che ha già.
///
/// ── Annullare ────────────────────────────────────────────────────────────
///
/// yt-dlp lancia ffmpeg per unire e convertire: fermare solo yt-dlp lascia
/// ffmpeg a scrivere da solo. Per questo parte in una sessione sua
/// (`setsid`), e l'annullamento ferma tutto il gruppo.
class Scaricatore {
  Scaricatore({
    required this.ytdlp,
    required this.cartellaMusica,
    required this.cartellaVideo,
    required this.cartellaStato,
    required this.cartellaLavoro,
    this.contemporanei = 2,
    this.setsid = '/usr/bin/setsid',
  }) {
    if (contemporanei < 1 || contemporanei > 4) {
      throw ArgumentError.value(contemporanei, 'contemporanei');
    }
  }

  final YtDlp ytdlp;
  final Future<String> Function() cartellaMusica;
  final Future<String> Function() cartellaVideo;

  /// Dove stanno gli archivi delle playlist (`~/.local/state/liquid-de/media`).
  final String cartellaStato;

  /// Dove stanno i pezzi intermedi (`~/.cache/liquid-de/media`).
  final String cartellaLavoro;
  final int contemporanei;
  final String setsid;

  final _cambi = StreamController<Map<String, dynamic>>.broadcast();

  /// Un evento per ogni cambiamento di un lavoro (avanzamento compreso, ma
  /// non più di uno ogni 250 ms per lavoro).
  Stream<Map<String, dynamic>> get cambi => _cambi.stream;

  // Una mappa letterale di Dart conserva l'ordine di inserimento: la coda.
  final _lavori = <String, LavoroMedia>{};
  int _contatore = 0;
  bool _chiuso = false;
  Future<void>? _chiusura;
  final _esecuzioni = <String, Future<void>>{};

  List<Map<String, dynamic>> elenco() =>
      [for (final l in _lavori.values) l.toJson()];

  /// Mette in coda. Ritorna l'id del lavoro, o solleva [ArgumentError] se la
  /// richiesta non va bene (indirizzo, formato).
  String aggiungi({
    required String indirizzo,
    required bool audio,
    required bool playlist,
    String titolo = '',
    String formatoAudio = 'mp3',
    int altezzaMassima = 0,
    List<int>? indici,
  }) {
    final scelti = YtDlp.selezioneValida(indici, playlist:playlist);
    if (_chiuso) throw StateError('Scaricatore chiuso');
    if (!YtDlp.indirizzoAccettabile(indirizzo)) {
      throw ArgumentError('Indirizzo non valido: serve un https://');
    }
    if (!const {'mp3', 'm4a', 'opus'}.contains(formatoAudio)) {
      throw ArgumentError('Formato audio non previsto: $formatoAudio');
    }
    if (!const {0, 480, 720, 1080, 1440, 2160}.contains(altezzaMassima)) {
      throw ArgumentError('Risoluzione non prevista: $altezzaMassima');
    }
    // Lo stesso indirizzo nello stesso formato già in coda o in corso: un
    // doppio clic non deve scaricare due volte (vedi i telefoni USB).
    for (final l in _lavori.values) {
      if (l.indirizzo == indirizzo && l.audio == audio &&
          l.playlist == playlist && l.formatoAudio == formatoAudio &&
          l.altezzaMassima == altezzaMassima &&
          jsonEncode(l.indici) == jsonEncode(scelti) && l.attivo && !l.annullando) {
        return l.id;
      }
    }
    if (_lavori.length >= 256) throw StateError('Elenco download pieno: pulisci i lavori terminati.');
    final id = 'media${++_contatore}';
    final l = LavoroMedia(
      id: id,
      indirizzo: indirizzo,
      audio: audio,
      playlist: playlist,
      titolo: titolo,
      formatoAudio: formatoAudio,
      altezzaMassima: altezzaMassima,
      indici: scelti,
    );
    _lavori[id] = l;
    _annuncia(l, subito: true);
    _avanti();
    return id;
  }

  /// Ferma un lavoro in coda o in corso. I file già finiti restano; i pezzi
  /// intermedi restano nella cartella di lavoro, così rilanciare riprende.
  Future<void> annulla(String id) async {
    final l = _lavori[id];
    if (l == null || !l.attivo) return;
    if (l.stato == 'in_coda') {
      l.stato = 'annullato';
      _annuncia(l, subito: true);
      _avanti();
      return;
    }
    l.annullando = true;
    if (!l.stop.isCompleted) l.stop.complete();
    _fermaGruppo(l);
    await _esecuzioni[id];
  }

  /// Toglie dall'elenco i lavori finiti (non quelli in corso).
  void pulisci() {
    _lavori.removeWhere((_, l) => !l.attivo);
    _ultimoAnnuncio.removeWhere((id, _) => !_lavori.containsKey(id));
    if (!_cambi.isClosed) _cambi.add({'tipo': 'elenco', 'lavori': elenco()});
  }

  void _avanti() {
    if (_chiuso) return;
    final inCorso = _lavori.values.where((l) => l.stato == 'in_corso').length;
    var liberi = contemporanei - inCorso;
    for (final l in _lavori.values) {
      if (liberi <= 0) break;
      if (l.stato != 'in_coda') continue;
      // Selezioni diverse della stessa playlist condividono archivio e parziali.
      if (_lavori.values.any((other) => other.stato == 'in_corso' &&
          other.indirizzo == l.indirizzo && other.audio == l.audio &&
          other.formatoAudio == l.formatoAudio && other.altezzaMassima == l.altezzaMassima)) { continue; }
      liberi--;
      l.stato = 'in_corso';
      final task = _esegui(l);
      _esecuzioni[l.id] = task;
      unawaited(task.whenComplete(() { _esecuzioni.remove(l.id); }));
    }
  }

  Future<void> _esegui(LavoroMedia l) async {
    try {
      final eseguibile = await _attendi(l,ytdlp.eseguibile());
      _controllaAnnullamento(l);
      if (eseguibile == null) {
        _finisci(l, 'errore', 'yt-dlp non è installato.');
        return;
      }
      final cartella = await _attendi(l,l.audio ? cartellaMusica() : cartellaVideo());
      _controllaAnnullamento(l);
      await _attendi(l,Directory(cartella).create(recursive: true));
      _controllaAnnullamento(l);
      final destinazione = await _attendi(l,Directory(cartella).resolveSymbolicLinks());
      final chiave = _chiave(l, destinazione);
      final lavoro = '$cartellaLavoro/$chiave';
      await _attendi(l,Directory(lavoro).create(recursive: true));
      String? archivio;
      if (l.playlist) {
        await _attendi(l,Directory(cartellaStato).create(recursive: true));
        archivio = '$cartellaStato/archivio-$chiave.txt';
      }
      _controllaAnnullamento(l);
      final argomenti = YtDlp.argomentiDownload(
        indirizzo: l.indirizzo,
        audio: l.audio,
        playlist: l.playlist,
        cartella: destinazione,
        cartellaDiLavoro: lavoro,
        formatoAudio: l.formatoAudio,
        altezzaMassima: l.altezzaMassima,
        archivio: archivio,
        indici: l.indici,
      );
      l.cartella = destinazione;
      _controllaAnnullamento(l);
      final p = await Process.start(
        setsid,
        [eseguibile, ...argomenti],
        // Niente da chiedere: yt-dlp che aspetta una risposta su stdin
        // resterebbe appeso per sempre.
        environment: const {'LC_ALL': 'C.UTF-8', 'PYTHONUNBUFFERED': '1'},
      );
      l.pid = p.pid;
      l.processo = p;
      unawaited(p.stdin.close().then((_) {}, onError: (Object _) {}));
      if (l.annullando) _fermaGruppo(l);
      final errori = StringBuffer();
      final erroriFiniti = Completer<void>();
      final fuoriFinito = Completer<void>();
      final subErrori = p.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((t) {
            errori.write(t);
            if (errori.length > 16384) {
              final tail = errori.toString();
              errori..clear()..write(tail.substring(tail.length - 8192));
            }
          }, onError: (Object _) {
            l.outputNonValido = true;
            if (!erroriFiniti.isCompleted) erroriFiniti.complete();
          }, onDone: () { if (!erroriFiniti.isCompleted) erroriFiniti.complete(); });
      final subFuori = _righeLimitate(p.stdout)
          .asyncMap((riga) => _riga(l, riga))
          .listen((_) {}, onError: (Object _) {
            l.outputNonValido = true;
            _fermaGruppo(l);
            if (!fuoriFinito.isCompleted) fuoriFinito.complete();
          }, onDone: () { if (!fuoriFinito.isCompleted) fuoriFinito.complete(); });
      late int codice;
      try {
        codice = await p.exitCode;
        final drain = Future.wait([fuoriFinito.future, erroriFiniti.future]);
        try {
          await drain.timeout(const Duration(milliseconds: 500));
        } on TimeoutException {
          // A descendant left pipes open after its leader exited. Reap the
          // owned group before releasing a queue slot or completing shutdown.
          l.outputNonValido = true;
          _fermaGruppo(l);
          await drain.timeout(const Duration(seconds: 6));
        }
      } finally {
        await subFuori.cancel();
        await subErrori.cancel();
      }
      l.pid = null;
      if (l.annullando) {
        _finisci(l, 'annullato', '');
      } else if (l.outputNonValido) {
        _finisci(l, 'errore', 'Percorso del file completato non valido.');
      } else if (codice == 0) {
        _finisci(l, 'fatto', '');
      } else if (l.fatti.isNotEmpty && l.playlist) {
        // Una playlist con qualche video privato o tolto: i file buoni ci
        // sono, e va detto quanti e perché gli altri no.
        _finisci(l, 'parziale', YtDlp.spiegaErrore(errori.toString()));
      } else {
        _finisci(l, 'errore', YtDlp.spiegaErrore(errori.toString()));
      }
    } catch (e) {
      _finisci(l, l.annullando || _chiuso ? 'annullato' : 'errore',
          l.annullando || _chiuso ? '' : '$e');
    } finally {
      l.escalation?.cancel();
      l.processo = null;
      l.pid = null;
      _avanti();
    }
  }

  static Stream<String> _righeLimitate(Stream<List<int>> bytes) async* {
    var pending = '';
    await for (final chunk in bytes.transform(const Utf8Decoder(allowMalformed: true))) {
      final parts = chunk.split('\n');
      for (var i = 0; i < parts.length; i++) {
        if (pending.length + parts[i].length > 65536) {
          throw const FormatException('Riga yt-dlp troppo lunga');
        }
        pending += parts[i];
        if (i < parts.length - 1) {
          yield pending.endsWith('\r') ? pending.substring(0,pending.length-1) : pending;
          pending = '';
        }
      }
    }
    if (pending.isNotEmpty) yield pending;
  }

  Future<T> _attendi<T>(LavoroMedia l, Future<T> operation) => Future.any([
    operation, l.stop.future.then<T>((_) => throw StateError('Lavoro annullato')),
  ]);

  void _controllaAnnullamento(LavoroMedia l) {
    if (_chiuso || l.annullando) throw StateError('Lavoro annullato');
  }

  Future<void> _riga(LavoroMedia l, String riga) async {
    final r = YtDlp.leggiRiga(riga);
    if (r == null) return;
    switch (r['tipo']) {
      case 'avanzamento':
        l.scaricati = (r['scaricati'] as num).toInt();
        l.totale = (r['totale'] as num).toInt();
        l.velocita = (r['velocita'] as num).toDouble();
        l.eta = (r['eta'] as num).toInt();
        if ((r['voci'] as num) > 0) l.voci = (r['voci'] as num).toInt();
        if ((r['indice'] as num) > 0) l.indice = (r['indice'] as num).toInt();
        _annuncia(l);
      case 'inizio':
        l.corrente = '${r['titolo']}';
        if ((r['indice'] as int) > 0) l.indice = r['indice'] as int;
        if (l.titolo.isEmpty && !l.playlist) l.titolo = l.corrente;
        _annuncia(l, subito: true);
      case 'fatto':
        final percorso = '${r['percorso']}';
        // Solo dentro la cartella scelta: un nome che yt-dlp avesse portato
        // altrove (non dovrebbe) non diventa un file «nostro».
        final root = l.cartella;
        try {
          final file = File(percorso);
          final normalized = file.absolute.uri.normalizePath().toFilePath();
          if (root == null || !percorso.startsWith('/') ||
              !normalized.startsWith('$root/') ||
              await FileSystemEntity.type(percorso, followLinks: false) != FileSystemEntityType.file) {
            l.outputNonValido = true;
            return;
          }
          final resolved = await file.resolveSymbolicLinks();
          if (!resolved.startsWith('$root/')) { l.outputNonValido = true; return; }
          if (!l.fatti.contains(resolved)) l.fatti.add(resolved);
          _annuncia(l, subito: true);
        } on FileSystemException {
          l.outputNonValido = true;
        }
    }
  }

  void _finisci(LavoroMedia l, String stato, String errore) {
    l.stato = stato;
    l.errore = errore;
    _annuncia(l, subito: true);
  }

  /// Un nome stabile per indirizzo e formato: la stessa playlist riscaricata
  /// ritrova archivio e pezzi. Nessun carattere dell'indirizzo finisce nel
  /// nome di un file.
  static String _chiave(LavoroMedia l, String destinazione) =>
      Sha256.esa(utf8.encode(jsonEncode([
        l.indirizzo, l.audio, l.playlist, l.formatoAudio,
        l.altezzaMassima, destinazione,
      ])));

  void _fermaGruppo(LavoroMedia l) {
    final pid = l.pid;
    if (pid == null || pid <= 1 || l.escalation != null) return;
    // `setsid` ha reso yt-dlp capo del suo gruppo: -pid li prende tutti.
    LinuxFiles.segnalaGruppo(pid,15);
    l.processo?.kill(ProcessSignal.sigterm);
    l.escalation = Timer(const Duration(seconds: 5), () {
      if (l.pid == pid) {
        LinuxFiles.segnalaGruppo(pid,9);
        l.processo?.kill(ProcessSignal.sigkill);
      }
    });
  }

  final _ultimoAnnuncio = <String, int>{};
  final _annunciInAttesa = <String, Timer>{};
  final _clock = Stopwatch()..start();

  void _annuncia(LavoroMedia l, {bool subito = false}) {
    if (_cambi.isClosed) return;
    final ora = _clock.elapsedMilliseconds;
    final prima = _ultimoAnnuncio[l.id];
    if (!subito && prima != null && ora - prima < 250) {
      _annunciInAttesa.putIfAbsent(l.id, () => Timer(
          Duration(milliseconds:250-(ora-prima)), () {
        _annunciInAttesa.remove(l.id);
        _annuncia(l,subito:true);
      }));
      return;
    }
    _annunciInAttesa.remove(l.id)?.cancel();
    _ultimoAnnuncio[l.id] = ora;
    _cambi.add({'tipo': 'lavoro', 'lavoro': l.toJson()});
  }

  /// Ferma tutto all'arresto del demone. I pezzi restano per la prossima
  /// volta.
  Future<void> chiudi() => _chiusura ??= _chiudiDavvero();

  Future<void> _chiudiDavvero() async {
    _chiuso = true;
    for (final l in _lavori.values) {
      if (!l.attivo) continue;
      l.annullando = true;
      if (!l.stop.isCompleted) l.stop.complete();
      if (l.stato == 'in_coda') {
        _finisci(l, 'annullato', '');
      } else {
        _fermaGruppo(l);
      }
    }
    await Future.wait(_esecuzioni.values.toList());
    for (final timer in _annunciInAttesa.values) { timer.cancel(); }
    _annunciInAttesa.clear();
    await _cambi.close();
  }

}

class LavoroMedia {
  LavoroMedia({
    required this.id,
    required this.indirizzo,
    required this.audio,
    required this.playlist,
    required this.titolo,
    required this.formatoAudio,
    required this.altezzaMassima,
    this.indici,
  });

  final String id;
  final String indirizzo;
  final bool audio;
  final bool playlist;
  String titolo;
  final String formatoAudio;
  final int altezzaMassima;
  final List<int>? indici;

  /// `in_coda`, `in_corso`, `fatto`, `parziale`, `errore`, `annullato`.
  String stato = 'in_coda';
  String errore = '';
  String corrente = '';
  String? cartella;
  int? pid;
  Process? processo;
  final stop = Completer<void>();
  bool annullando = false;
  bool outputNonValido = false;
  Timer? escalation;
  int scaricati = 0;
  int totale = 0;
  double velocita = 0;
  int eta = 0;
  int indice = 0;
  int voci = 0;
  final List<String> fatti = [];

  bool get attivo => stato == 'in_coda' || stato == 'in_corso';

  Map<String, dynamic> toJson() => {
        'id': id,
        'indirizzo': indirizzo,
        'audio': audio,
        'playlist': playlist,
        'titolo': titolo,
        'formatoAudio': formatoAudio,
        'altezzaMassima': altezzaMassima,
        'selezione': indici == null ? null : List<int>.of(indici!),
        'stato': stato,
        'errore': errore,
        'corrente': corrente,
        'cartella': cartella ?? '',
        'scaricati': scaricati,
        'totale': totale,
        'velocita': velocita,
        'eta': eta,
        'indice': indice,
        'voci': voci,
        'fatti': List<String>.of(fatti),
      };
}
