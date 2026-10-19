import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Un telefono o una chiavetta attaccati adesso: si aprono da soli.
///
/// ── Perché esiste ────────────────────────────────────────────────────────
///
/// Fino al 18 ottobre 2026 attaccare un telefono in «Trasferimento file» non
/// faceva niente: bisognava aprire il gestore file, trovarlo nella barra
/// laterale (che se ne accorgeva entro otto secondi, e solo se era già
/// aperta) e cliccarlo. Windows e GNOME aprono una finestra; così fa Liquid.
///
/// ── Come se ne accorge ───────────────────────────────────────────────────
///
/// `gio mount -o` resta acceso e scrive una riga a ogni volume che compare o
/// sparisce: gvfs sa già tutto (MTP, PTP, UDisks), e qui non si interroga
/// niente a intervalli. Una riga è solo un segnale: lo stato vero si rilegge
/// con `gio mount -l -i`, e si confronta con quello di prima. Quello che c'era
/// già all'avvio del demone non si apre: non è stato «attaccato adesso».
///
/// Questo file non monta niente e non apre finestre: dice COSA è nuovo. Chi
/// lo usa (il canale) sa montare e sa aprire.
class ArrivoDispositivi {
  ArrivoDispositivi({
    this.gio = 'gio',
    this.attesa = const Duration(milliseconds: 600),
  });

  /// Il programma da lanciare. Le prove ne passano uno finto.
  final String gio;

  /// Un telefono che passa da «ricarica» a «trasferimento file» si stacca e
  /// si riattacca, e gvfs scrive più righe di fila: si aspetta che si calmi.
  final Duration attesa;

  final _cambi = StreamController<void>.broadcast();

  /// Un segnale per ogni gruppo di cambiamenti. Si rilegge lo stato con
  /// [leggiVolumi] e si chiede a [nuovi] cosa è comparso.
  Stream<void> get cambi => _cambi.stream;

  Process? _monitor;
  Timer? _calma;
  bool _fermo = false;
  int _ripartenze = 0;

  static const Map<String, String> _ambiente = {'LC_ALL': 'C', 'LANG': 'C'};

  Future<void> start() async {
    if (_fermo || _monitor != null) return;
    try {
      final p = await Process.start(gio, ['mount', '-o'],
          environment: _ambiente);
      _monitor = p;
      p.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(_riga, onError: (Object _) {});
      p.stderr.drain<void>().catchError((Object _) {});
      unawaited(p.exitCode.then((_) {
        _monitor = null;
        // gvfs riavviato, sessione D-Bus caduta: si riprova, ma non
        // all'infinito — un `gio` che muore subito non deve diventare un
        // processo lanciato ogni cinque secondi per tutta la sessione.
        if (!_fermo && _ripartenze < 5) {
          _ripartenze++;
          Timer(const Duration(seconds: 5), start);
        }
      }));
    } on ProcessException catch (e) {
      print('[MINERVA][DISPOSITIVI][WARN] gio mount -o non parte: ${e.message}');
    }
  }

  void _riga(String riga) {
    if (!rigaDiCambio(riga)) return;
    _calma?.cancel();
    _calma = Timer(attesa, () {
      if (!_cambi.isClosed) _cambi.add(null);
    });
  }

  /// `Volume added:      'realme Phone'`, `Mount removed: …`, `Drive
  /// connected: …`. Le righe sotto (rientrate) sono i dettagli: non servono,
  /// lo stato si rilegge intero.
  static bool rigaDiCambio(String riga) => RegExp(
        r'^(Volume|Mount|Drive) (added|removed|changed|connected|disconnected)',
      ).hasMatch(riga);

  Future<void> stop() async {
    _fermo = true;
    _calma?.cancel();
    _monitor?.kill();
    _monitor = null;
    await _cambi.close();
  }

  // ── Una finestra per disco ────────────────────────────────────────────
  //
  // Una chiavetta Ventoy ha due partizioni («Ventoy» e «VTOYEFI», 32 MB):
  // aprirle entrambe erano due finestre una sopra l'altra per una chiavetta
  // sola (18 ottobre 2026). Si montano tutte, si apre la più grande — come
  // Windows, che chiede una volta per unità.

  /// Il disco di una partizione: `/dev/sda1` → `/dev/sda`,
  /// `/dev/nvme0n1p2` → `/dev/nvme0n1`, `/dev/mmcblk0p1` → `/dev/mmcblk0`.
  static String disco(String dispositivo) {
    final conP = RegExp(r'^(/dev/(?:nvme\d+n\d+|mmcblk\d+|loop\d+))p\d+$')
        .firstMatch(dispositivo);
    if (conP != null) return conP.group(1)!;
    final sd = RegExp(r'^(/dev/[a-z]+)\d+$').firstMatch(dispositivo);
    return sd?.group(1) ?? dispositivo;
  }

  /// I volumi nuovi raggruppati per disco, nell'ordine in cui sono arrivati.
  /// Un telefono è un gruppo da solo.
  static List<List<VolumeArrivato>> perDisco(List<VolumeArrivato> volumi) {
    final gruppi = <String, List<VolumeArrivato>>{};
    for (final v in volumi) {
      final chiave = v.chiavetta ? disco(v.dispositivo) : v.chiave;
      (gruppi[chiave] ??= []).add(v);
    }
    return gruppi.values.toList();
  }

  /// Quanti settori ha una partizione, da `/sys/class/block`; 0 se non si sa.
  static int settori(String dispositivo, {String sys = '/sys/class/block'}) {
    if (!dispositivo.startsWith('/dev/')) return 0;
    try {
      return int.parse(
          File('$sys/${dispositivo.substring(5)}/size').readAsStringSync().trim());
    } catch (_) {
      return 0;
    }
  }

  // ── Cosa è nuovo ──────────────────────────────────────────────────────

  Set<String>? _visti;

  /// I volumi comparsi dall'ultima volta, da aprire.
  ///
  /// La prima chiamata non restituisce niente: registra cosa c'è. Un volume
  /// che sparisce esce dall'elenco, e se torna (lo stesso telefono staccato e
  /// riattaccato) è di nuovo nuovo — è proprio il caso in cui lo si vuole
  /// vedere aprirsi.
  List<VolumeArrivato> nuovi(List<VolumeArrivato> adesso) {
    final chiavi = {for (final v in adesso) v.chiave};
    final prima = _visti;
    _visti = chiavi;
    if (prima == null) return const [];
    return [
      for (final v in adesso)
        if (!prima.contains(v.chiave) && v.daAprire) v,
    ];
  }

  /// Legge `gio mount -l -i`: i volumi, con quello che serve a montarli.
  ///
  /// Un volume montato ha sotto di sé la riga `Mount(n): nome -> uri`. Un
  /// telefono ha `activation_root=mtp://…`; una chiavetta ha
  /// `unix-device: '/dev/sdb1'` e nessuna radice.
  static List<VolumeArrivato> leggiVolumi(String testo) {
    final fuori = <VolumeArrivato>[];
    _Volume? v;
    void chiudi() {
      final c = v;
      if (c != null) fuori.add(c.finito());
      v = null;
    }

    final rigaVolume = RegExp(r'^(\s*)Volume\(\d+\): (.*?)\s*$');
    final rigaDrive = RegExp(r'^Drive\(\d+\):');
    final rigaMount = RegExp(r'^\s*Mount\(\d+\): .* -> (\S+)\s*$');
    final rigaRadice = RegExp(r'^\s*activation_root=(\S+)\s*$');
    final rigaDev = RegExp(r"^\s*unix-device: '([^']+)'\s*$");
    final rigaAuto = RegExp(r'^\s*should_automount=(\d)\s*$');
    final rigaTipo = RegExp(r'^\s*Type: \S+ \((\w+)\)\s*$');
    for (final riga in const LineSplitter().convert(testo)) {
      final mv = rigaVolume.firstMatch(riga);
      if (mv != null) {
        chiudi();
        v = _Volume(mv.group(2)!, mv.group(1)!.length);
        continue;
      }
      if (rigaDrive.hasMatch(riga)) {
        chiudi();
        continue;
      }
      final c = v;
      if (c == null) continue;
      final mm = rigaMount.firstMatch(riga);
      if (mm != null) {
        // Un `Mount` rientrato più del volume è il SUO; uno a sinistra è un
        // montaggio senza volume (una cartella di rete) e chiude il volume.
        final rientro = riga.length - riga.trimLeft().length;
        if (rientro > c.rientro) {
          c.montato = true;
        } else {
          chiudi();
        }
        continue;
      }
      final r = rigaRadice.firstMatch(riga);
      if (r != null) c.radice = r.group(1)!;
      final d = rigaDev.firstMatch(riga);
      if (d != null) c.dispositivo = d.group(1)!;
      final a = rigaAuto.firstMatch(riga);
      if (a != null) c.automatico = a.group(1) == '1';
      final t = rigaTipo.firstMatch(riga);
      if (t != null) c.monitor = t.group(1)!;
    }
    chiudi();
    return fuori;
  }
}

class _Volume {
  _Volume(this.nome, this.rientro);
  final String nome;
  final int rientro;
  String radice = '';
  String dispositivo = '';
  String monitor = '';
  bool automatico = false;
  bool montato = false;

  VolumeArrivato finito() => VolumeArrivato(
        nome: nome,
        radice: radice,
        dispositivo: dispositivo,
        monitor: monitor,
        automatico: automatico,
        montato: montato,
      );
}

/// Un volume visto da gvfs.
class VolumeArrivato {
  const VolumeArrivato({
    required this.nome,
    this.radice = '',
    this.dispositivo = '',
    this.monitor = '',
    this.automatico = false,
    this.montato = false,
  });

  final String nome;

  /// `mtp://realme_realme_Phone_…/` per un telefono, vuoto per una chiavetta.
  final String radice;

  /// `/dev/sdb1` per una chiavetta, `/dev/bus/usb/001/012` per un telefono.
  final String dispositivo;

  /// Chi l'ha visto: `GProxyVolumeMonitorMTP`, `…UDisks2`, `…GPhoto2`.
  final String monitor;

  /// gvfs dice che va montato da solo (`should_automount=1`): lo dice per
  /// chiavette e telefoni, non per i dischi interni.
  final bool automatico;
  final bool montato;

  bool get telefono =>
      radice.startsWith('mtp://') || radice.startsWith('gphoto2://');

  /// Una partizione di un disco esterno. I dischi interni non hanno
  /// `should_automount`, e restano a chi li vuole aprire.
  bool get chiavetta =>
      radice.isEmpty && dispositivo.startsWith('/dev/') &&
      !dispositivo.startsWith('/dev/bus/');

  bool get daAprire => automatico && !montato && (telefono || chiavetta);

  /// Cosa identifica lo stesso volume fra una lettura e l'altra. Il numero
  /// USB (`/dev/bus/usb/001/012`) cambia a ogni riattacco, e va bene così:
  /// riattaccato è nuovo.
  String get chiave => '$nome\u0000$radice\u0000$dispositivo';
}

/// Il kernel ha visto errori di linea USB negli ultimi minuti?
///
/// `error -71` (EPROTO), «not accepting address», «disabled by hub (EMI?)»:
/// sono byte rovinati sul cavo, prima di ogni protocollo. Il 18 ottobre 2026
/// un realme non si apriva per questo, e la sola cosa da dire a chi guarda
/// era «cambia cavo o porta» — non «il telefono non risponde».
Future<bool> lineaUsbDisturbata({
  String journalctl = 'journalctl',
  Duration finestra = const Duration(minutes: 3),
}) async {
  try {
    final r = await Process.run(journalctl, [
      '-k',
      '--no-pager',
      '-o',
      'cat',
      '--since',
      '-${finestra.inSeconds}s',
    ]).timeout(const Duration(seconds: 3));
    return righeDiLineaDisturbata('${r.stdout}');
  } catch (_) {
    return false;
  }
}

bool righeDiLineaDisturbata(String registro) => RegExp(
      r'^usb [\w.-]+: .*(error -71|not accepting address|'
      r'device descriptor read.*error|disabled by hub \(EMI\?\))',
      multiLine: true,
    ).hasMatch(registro);
