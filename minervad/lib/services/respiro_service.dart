import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/settings_api.dart';
import '../providers/compositor_provider.dart';

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
  Future<Set<int>> _pidInVista() async {
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

  /// Gli scope da comprimere adesso. Aggiorna lo stato.
  List<String> daComprimere(Map<String, bool> visibili, DateTime adesso) {
    ultimaVista.removeWhere((s, _) => !visibili.containsKey(s));
    compressi.removeWhere((s) => !visibili.containsKey(s));
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
