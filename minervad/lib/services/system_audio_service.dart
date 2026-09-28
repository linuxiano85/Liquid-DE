import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef AudioRun = Future<ProcessResult> Function(List<String> args);

/// Audio del desktop: una sola sorgente autorevole, comandi senza shell.
class SystemAudioService {
  final AudioRun run;
  SystemAudioService({AudioRun? run}) : run = run ?? _run;
  static Future<ProcessResult> _run(List<String> args) async {
    final process = await Process.start(
      'pactl',
      args,
      environment: {'LC_ALL': 'C.UTF-8'},
    );
    final out = process.stdout.transform(utf8.decoder).join();
    final err = process.stderr.transform(utf8.decoder).join();
    try {
      final code = await process.exitCode.timeout(const Duration(seconds: 5));
      return ProcessResult(process.pid, code, await out, await err);
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
      throw StateError('Il servizio audio non risponde');
    }
  }

  final changes = StreamController<Map<String, dynamic>>.broadcast();
  Process? _watch;
  Timer? _debounce, _retry;
  bool _closed = false, _starting = false, _reading = false, _again = false;
  bool _selecting = false;

  Future<String> _command(List<String> args) async {
    final r = await run(args);
    if (r.exitCode != 0) throw StateError('Audio: ${r.stderr}'.trim());
    return '${r.stdout}'.trim();
  }

  Future<List<Map<String, dynamic>>> _list(String kind) async =>
      (jsonDecode(await _command(['--format=json', 'list', kind])) as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();

  static List<Map<String, dynamic>> named(dynamic value) {
    if (value is List) {
      return value.map((v) => Map<String, dynamic>.from(v as Map)).toList();
    }
    if (value is Map) {
      return value.entries
          .map(
            (e) => <String, dynamic>{
              ...Map<String, dynamic>.from(e.value as Map),
              'name': e.key,
            },
          )
          .toList();
    }
    return [];
  }

  static List<Map<String, dynamic>> hdmiOptions(
    List<Map<String, dynamic>> cards,
  ) {
    final result = <Map<String, dynamic>>[];
    for (final card in cards) {
      final profiles = named(card['profiles']);
      for (final port in named(card['ports'])) {
        if (!'${port['name']}'.contains('hdmi') || port['direction'] == 'input') {
          continue;
        }
        final related = port['profiles'];
        final names = related is List
            ? related.map((v) => v is Map ? v['name'] : v).toSet()
            : related is Map
            ? related.keys.toSet()
            : <dynamic>{};
        // ── Una porta, una voce ─────────────────────────────────────────
        //
        // Qui si aggiungeva una voce per ogni profilo della porta — stereo,
        // 5.1, 7.1, e le loro combinazioni col microfono — e il nome del
        // profilo arrivava spesso vuoto: la pagina Audio mostrava una
        // ventina di «HDMI / DisplayPort — (null)» prima ancora del volume
        // (28 settembre 2026). Chi collega un monitor sceglie il MONITOR:
        // del profilo si prende il migliore — disponibile prima, poi con la
        // priorità più alta.
        Map<String, dynamic>? migliore;
        var migliorDisponibile = false;
        num migliorPriorita = -1;
        for (final profile in profiles) {
          if (!names.contains(profile['name']) ||
              ((profile['sinks'] ?? profile['n_sinks']) as num? ?? 0) < 1) {
            continue;
          }
          final available =
              port['availability'] != 'not available' &&
              port['availability'] != 'no' &&
              profile['available'] != false &&
              profile['available'] != 'no' &&
              profile['available'] != 'not available';
          final priorita = (profile['priority'] as num?) ?? 0;
          final meglio = migliore == null ||
              (available && !migliorDisponibile) ||
              (available == migliorDisponibile && priorita > migliorPriorita);
          if (!meglio) continue;
          migliore = profile;
          migliorDisponibile = available;
          migliorPriorita = priorita;
        }
        if (migliore == null) continue;
        final descrizione = port['description'];
        result.add({
          'card': card['name'],
          'profile': migliore['name'],
          'port': port['name'],
          'label': (descrizione is String &&
                  descrizione.isNotEmpty &&
                  descrizione != '(null)')
              ? descrizione
              : '${port['name']}',
          'available': migliorDisponibile,
        });
      }
    }
    return result;
  }

  Future<Map<String, dynamic>> snapshot() async {
    final data = await Future.wait([
      _list('sinks'),
      _list('sources'),
      _list('cards'),
    ]);
    final defaults = await Future.wait([
      _command(['get-default-sink']),
      _command(['get-default-source']),
    ]);
    return {
      'ok': true,
      'sinks': data[0],
      'sources': data[1]
          .where((s) => !'${s['name']}'.endsWith('.monitor'))
          .toList(),
      'cards': data[2],
      'hdmi': hdmiOptions(data[2]),
      'defaultSink': defaults[0],
      'defaultSource': defaults[1],
    };
  }

  Future<Map<String, dynamic>> status() async {
    try {
      return await snapshot();
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
  }

  Future<void> start() async {
    if (_closed || _watch != null || _starting) return;
    _starting = true;
    try {
      final p = await Process.start(
        'pactl',
        ['subscribe'],
        environment: {'LC_ALL': 'C.UTF-8'},
      );
      if (_closed) {
        p.kill();
        return;
      }
      _watch = p;
      p.stderr.drain<void>();
      p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((
        line,
      ) {
        if (RegExp(r'on (sink|source|card|server)').hasMatch(line)) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 150), _publish);
        }
      }, onError: (_) {});
      unawaited(
        p.exitCode.then((_) {
          if (identical(_watch, p)) _watch = null;
          _reconnect();
        }),
      );
      await _publish();
    } catch (_) {
      _reconnect();
    } finally {
      _starting = false;
    }
  }

  void _reconnect() {
    if (_closed) return;
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 2), start);
  }

  Future<void> _publish() async {
    if (_closed) return;
    if (_reading) {
      _again = true;
      return;
    }
    _reading = true;
    do {
      _again = false;
      final data = await status();
      if (!_closed) changes.add(data);
    } while (_again && !_closed);
    _reading = false;
  }

  /// Selezione serializzata: la UI riceve solo lo stato riletto dal server.
  Future<Map<String, dynamic>> select(Map<String, dynamic> request) async {
    if (_selecting) return {'ok': false, 'error': 'Cambio audio già in corso'};
    _selecting = true;
    String? changedCard, oldProfile;
    try {
      final before = await snapshot();
      final kind = request['kind'];
      if (kind != 'sink' && kind != 'source') {
        throw ArgumentError('Tipo audio non valido');
      }
      String? target = request['name'] as String?;
      if (request['card'] != null) {
        if (kind != 'sink') throw ArgumentError('HDMI richiede una uscita');
        final choices = (before['hdmi'] as List).cast<Map<String, dynamic>>();
        final option = choices.where(
          (v) =>
              v['card'] == request['card'] &&
              v['profile'] == request['profile'] &&
              v['port'] == request['port'] &&
              v['available'] == true,
        );
        if (option.isEmpty) throw StateError('Uscita HDMI non disponibile');
        final card = (before['cards'] as List).firstWhere(
          (c) => c['name'] == request['card'],
        );
        changedCard = card['name'] as String;
        final active = card['active_profile'];
        oldProfile = active is Map
            ? active['name'] as String?
            : active as String?;
        await _command([
          'set-card-profile',
          changedCard,
          request['profile'] as String,
        ]);
        target = null;
        for (var i = 0; i < 20; i++) {
          final sinks = await _list('sinks');
          for (final sink in sinks) {
            if ('${sink['card']}' == '${card['index']}' &&
                named(sink['ports']).any((p) => p['name'] == request['port'])) {
              target = sink['name'] as String;
              break;
            }
          }
          if (target != null) break;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        if (target == null) {
          throw StateError('Il profilo non ha creato l’uscita HDMI');
        }
        await _command(['set-sink-port', target, request['port'] as String]);
      } else {
        final devices = before[kind == 'sink' ? 'sinks' : 'sources'] as List;
        if (!devices.any((d) => d['name'] == target)) {
          throw StateError('Dispositivo non disponibile');
        }
      }
      if (target == null || target.isEmpty) throw StateError('Uscita mancante');
      await _command(['set-default-$kind', target]);
      if (await _command(['get-default-$kind']) != target) {
        throw StateError('Selezione audio non confermata');
      }
      final warnings = <String>[];
      for (final stream in await _list(
        kind == 'sink' ? 'sink-inputs' : 'source-outputs',
      )) {
        try {
          await _command([
            'move-${kind == 'sink' ? 'sink-input' : 'source-output'}',
            '${stream['index']}',
            target,
          ]);
        } catch (e) {
          warnings.add('$e');
        }
      }
      final after = await snapshot();
      if (warnings.isNotEmpty) {
        after['warning'] =
            'Alcuni flussi non sono stati trasferiti: ${warnings.join('; ')}';
      }
      return after;
    } catch (e) {
      String rollback = '';
      if (changedCard != null && oldProfile != null) {
        try {
          await _command(['set-card-profile', changedCard, oldProfile]);
        } catch (failure) {
          rollback = '; ripristino profilo fallito: $failure';
        }
      }
      return {'ok': false, 'error': '$e$rollback', 'state': await status()};
    } finally {
      _selecting = false;
      unawaited(_publish());
    }
  }

  Future<void> close() async {
    _closed = true;
    _retry?.cancel();
    _debounce?.cancel();
    _watch?.kill();
    if (_watch != null) await _watch!.exitCode;
    await changes.close();
  }
}
