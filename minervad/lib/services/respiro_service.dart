import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/settings_api.dart';
import '../providers/compositor_provider.dart';
import '../providers/minerva/minerva_provider.dart';

/// La memoria che respira: le app che non si guardano si comprimono.
///
/// ── Perché ────────────────────────────────────────────────────────────────
///
/// Giacomo, 28 settembre 2026: «rendere tutto veloce, piccolo, senza singolo
/// processo». Un processo Qt Quick ha un pavimento di ~10 MB suoi e una
/// nostra app ne occupa 30–90: restando processi separati non si possono
/// rimpicciolire. Si può fare quello che fa Android con le app in secondo
/// piano: scrivere la loro memoria in `memory.reclaim` del loro cgroup, e il
/// kernel la manda in zram, compressa.
///
/// Misurato nella sessione di prova sulla Calcolatrice nascosta: 32,3 MB
/// veri → 1,4 in RAM + 6,9 in zram (28,3 MB compressi 5:1); la prima
/// risposta dopo, 38 ms — più svelta di prima, perché torna solo quello che
/// serve. La compressione stessa ~220 ms, fatta in un momento in cui
/// nessuno guarda quell'app.
///
/// ── Di chi ────────────────────────────────────────────────────────────────
///
/// Solo dei cgroup che si chiamano `liquid-<app>-<pid>.scope`: li crea
/// `minerva_avvia_app` in `scripts/minerva-ambiente-app`, nel ramo delegato
/// all'utente (scrivibile senza root). Mai lo scope della sessione, mai i
/// programmi degli altri.
///
/// ── Quando ────────────────────────────────────────────────────────────────
///
/// Un'app è «in vista» se almeno un suo processo ha una finestra non ridotta
/// sulla scrivania attiva. Fuori vista da `soglia` (60 s) si comprime, una
/// volta; tornata in vista si ri-arma. Un'app tenuta pronta, senza finestre
/// visibili, è fuori vista per definizione: è il caso che vale di più (oggi
/// File tenuto pronto costa 84 MB per sempre).
class RespiroService {
  RespiroService(this._compositore, this._impostazioni,
      {String? radice, this.passo = const Duration(seconds: 10)})
      : _radice = radice ?? _radiceUtente();

  final CompositorProvider _compositore;
  final SettingsApi _impostazioni;
  final String _radice;
  final Duration passo;

  /// In prova soglia e passo si accorciano (MINERVA_RESPIRO_SOGLIA e
  /// _PASSO, in secondi): una prova che aspetta un minuto a giro non la
  /// lancia nessuno. Fuori prova le variabili non contano.
  static Duration _daAmbiente(String nome, Duration serie) {
    if (Platform.environment['MINERVA_PROVA'] != '1') return serie;
    final s = int.tryParse(Platform.environment[nome] ?? '');
    return s == null ? serie : Duration(seconds: s);
  }

  final _regola = Respiro(
      soglia: _daAmbiente('MINERVA_RESPIRO_SOGLIA', const Duration(seconds: 60)));
  Timer? _timer;
  StreamSubscription? _ascolto;
  bool _inGiro = false;

  /// Dove `systemd-run --user --scope` mette gli scope delle app.
  static String _radiceUtente() {
    final uid = _uid();
    return '/sys/fs/cgroup/user.slice/user-$uid.slice/'
        'user@$uid.service/app.slice';
  }

  static String _uid() {
    try {
      for (final riga in File('/proc/self/status').readAsLinesSync()) {
        if (riga.startsWith('Uid:')) return riga.split(RegExp(r'\s+'))[1];
      }
    } catch (_) {}
    return '1000';
  }

  /// `liquid-<app>-<pid>.scope`, o `liquid-prova-…` in una sessione di
  /// prova: ogni demone tocca solo i suoi (stanno nello stesso ramo).
  static final _nomeScope = Platform.environment['MINERVA_PROVA'] == '1'
      ? RegExp(r'^liquid-prova-[a-z0-9]+-[0-9]+\.scope$')
      : RegExp(r'^liquid-[a-z0-9]+-[0-9]+\.scope$');

  void avvia() {
    _timer = Timer.periodic(_daAmbiente('MINERVA_RESPIRO_PASSO', passo), (_) => giro());
    // Il fuoco e la scrivania cambiano chi è in vista: si ricontrolla
    // subito, così un'app tornata davanti si ri-arma senza aspettare.
    _ascolto = _compositore.events.listen((e) {
      if (e.type == CompositorEventType.windowFocused ||
          e.type == CompositorEventType.workspaceChanged ||
          e.type == CompositorEventType.windowClosed) {
        giro();
      }
    });
  }

  Future<void> ferma() async {
    _timer?.cancel();
    await _ascolto?.cancel();
  }

  String get livello =>
      '${_impostazioni.getValue('memoria.respiro', 'delicata')}';

  /// Un passo: chi è in vista, chi va compresso.
  Future<void> giro() async {
    if (_inGiro || livello == 'spenta') return;
    _inGiro = true;
    try {
      final scope = _scopeDelleApp();
      if (scope.isEmpty) return;
      final inVista = await _pidInVista();
      // Il compositore non ha risposto: questo giro si salta. Contarlo come
      // «nessuna finestra in vista» comprimeva, un minuto dopo, anche l'app
      // che si stava usando (30 settembre 2026).
      if (inVista == null) return;
      final visibili = <String, bool>{
        for (final s in scope)
          s: _processi(s).any(inVista.contains),
      };
      for (final s in _regola.daComprimere(visibili, DateTime.now())) {
        await _comprimi(s);
      }
    } catch (e) {
      stderr.writeln('[MINERVA][RESPIRO][WARN] giro non riuscito: $e');
    } finally {
      _inGiro = false;
    }
  }

  /// Per Attività: di ogni processo che sta in uno scope delle nostre app,
  /// l'app, lo stato del respiro e dove sta la sua memoria. Letto a ogni
  /// giro dell'elenco dei processi (pochi scope, tre file piccoli l'uno).
  Map<int, Map<String, dynamic>> perPid() {
    final fuori = <int, Map<String, dynamic>>{};
    var mm = '';
    try {
      mm = File('/sys/block/zram0/mm_stat').readAsStringSync();
    } catch (_) {}
    for (final s in _scopeDelleApp()) {
      final nome = s.split('/').last;
      int leggi(String f) {
        try {
          return int.tryParse(File('$s/$f').readAsStringSync().trim()) ?? 0;
        } catch (_) {
          return 0;
        }
      }
      final swap = leggi('memory.swap.current');
      final info = <String, dynamic>{
        'app': Respiro.nomeApp(nome),
        'stato': livello == 'spenta' ? null : _regola.stato(s),
        'inRam': leggi('memory.current'),
        'inSwap': swap,
        'inZram': Respiro.inZram(swap, mm),
      };
      for (final pid in _processi(s)) {
        fuori[pid] = info;
      }
    }
    return fuori;
  }

  List<String> _scopeDelleApp() {
    final d = Directory(_radice);
    if (!d.existsSync()) return const [];
    return [
      for (final e in d.listSync())
        if (e is Directory && _nomeScope.hasMatch(e.uri.pathSegments
            .lastWhere((p) => p.isNotEmpty)))
          e.path,
    ];
  }

  List<int> _processi(String scope) {
    try {
      return [
        for (final r in File('$scope/cgroup.procs').readAsLinesSync())
          if (int.tryParse(r.trim()) != null) int.parse(r.trim()),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// I pid con una finestra in vista: non ridotta, sulla scrivania attiva.
  /// `null` quando non si sa.
  ///
  /// Con minerva-wayland si usano le domande che distinguono «nessuna
  /// finestra» da «non ha risposto»: `getClientsRaw` e `getWorkspaces`
  /// ripiegano su `[]` e su una scrivania 1 finta, e con quelle — stando
  /// sulla scrivania 3 durante un intoppo — tutte le app risultavano fuori
  /// vista.
  Future<Set<int>?> _pidInVista() async {
    final c = _compositore;
    if (c is MinervaProvider) {
      final attiva = await c.scrivaniaAttivaSeRisponde();
      if (attiva == null) return null;
      final finestre = await c.finestreSeRisponde();
      if (finestre == null) return null;
      return Respiro.pidInVista(finestre, attiva);
    }
    final scrivanie = await _compositore.getWorkspaces();
    final attiva = scrivanie
        .firstWhere((w) => w.isActive, orElse: () => scrivanie.first)
        .id;
    return Respiro.pidInVista(await _compositore.getClientsRaw(), attiva);
  }

  Future<void> _comprimi(String scope) async {
    try {
      final quanto = File('$scope/memory.current').readAsStringSync().trim();
      // Un «tutto» chiesto al kernel: prende quello che può. Se non ci
      // arriva risponde EAGAIN, e va bene lo stesso — quello che ha preso
      // l'ha preso.
      //
      // In SOLA scrittura: `memory.reclaim` è `--w-------`, e
      // `writeAsString` apre in lettura e scrittura — il kernel risponde
      // «permesso negato» e non si comprimeva niente (visto il 28 settembre
      // nella prova annidata). Asincrono: la compressione dura ~200 ms, e
      // il demone nel frattempo risponde agli altri.
      final f = await File('$scope/memory.reclaim').open(mode: FileMode.writeOnly);
      try {
        await f.writeString(quanto);
      } finally {
        await f.close();
      }
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode != 11) {
        stderr.writeln('[MINERVA][RESPIRO][WARN] $scope: $e');
      }
    }
  }
}

/// La regola, senza sistema: si prova coi numeri.
class Respiro {
  Respiro({this.soglia = const Duration(seconds: 60)});

  final Duration soglia;

  /// L'ultima volta che ogni scope era in vista (o la prima volta che lo si
  /// è visto: un'app appena nata ha tutta la soglia davanti).
  final Map<String, DateTime> ultimaVista = {};

  /// Già compressi in questo periodo fuori vista.
  final Set<String> compressi = {};

  /// Com'era ogni scope all'ultimo giro: serve a Attività per dirlo.
  final Map<String, bool> _visibili = {};

  /// Gli scope da comprimere adesso. Aggiorna lo stato.
  List<String> daComprimere(Map<String, bool> visibili, DateTime adesso) {
    ultimaVista.removeWhere((s, _) => !visibili.containsKey(s));
    compressi.removeWhere((s) => !visibili.containsKey(s));
    _visibili
      ..clear()
      ..addAll(visibili);
    final fuori = <String>[];
    visibili.forEach((s, vista) {
      if (vista) {
        ultimaVista[s] = adesso;
        compressi.remove(s);
        return;
      }
      final da = ultimaVista.putIfAbsent(s, () => adesso);
      if (!compressi.contains(s) && adesso.difference(da) >= soglia) {
        compressi.add(s);
        fuori.add(s);
      }
    });
    return fuori;
  }

  /// `vista`, `fuori` (fuori vista, non ancora compressa) o `compressa`;
  /// null per uno scope che l'ultimo giro non ha visto.
  String? stato(String scope) {
    final v = _visibili[scope];
    if (v == null) return null;
    if (v) return 'vista';
    return compressi.contains(scope) ? 'compressa' : 'fuori';
  }

  /// `liquid-calcolatrice-4242.scope` → `calcolatrice` (anche `liquid-prova-…`).
  static String? nomeApp(String scope) {
    final m = RegExp(r'^liquid-(?:prova-)?([a-z0-9]+)-[0-9]+\.scope$')
        .firstMatch(scope);
    return m?.group(1);
  }

  /// Quanto occupano DAVVERO in zram i byte che un cgroup ha nello swap.
  ///
  /// `memory.swap.current` conta le pagine com'erano (28 MB per la
  /// Calcolatrice), non quanto pesano compresse: zram non tiene il conto per
  /// cgroup. Si usa il rapporto di tutto zram (`mm_stat`: originali, poi
  /// compressi), che per le nostre app è quello (misurato ~5:1). Con zram
  /// vuoto il rapporto non esiste: null, non un numero inventato.
  static int? inZram(int swap, String mmStat) {
    final c = mmStat.trim().split(RegExp(r'\s+'));
    if (c.length < 2) return null;
    final orig = int.tryParse(c[0]) ?? 0;
    final compr = int.tryParse(c[1]) ?? 0;
    if (orig <= 0) return null;
    return (swap * compr / orig).round();
  }

  /// Dal JSON delle finestre di minerva-wayland (`finestre`): i pid delle
  /// finestre non ridotte sulla scrivania attiva.
  static Set<int> pidInVista(String json, int scrivaniaAttiva) {
    final fuori = <int>{};
    try {
      final l = jsonDecode(json);
      if (l is! List) return fuori;
      for (final f in l.whereType<Map>()) {
        final pid = (f['pid'] as num?)?.toInt() ?? 0;
        if (pid <= 0 || f['ridotta'] == true) continue;
        if ((f['scrivania'] as num?)?.toInt() != scrivaniaAttiva) continue;
        fuori.add(pid);
      }
    } catch (_) {}
    return fuori;
  }
}
