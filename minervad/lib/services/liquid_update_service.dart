import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../core/minerva_paths.dart';
import 'liquid_update_changes.dart';

/// Solo aggiornamenti del progetto: nessun comando remoto viene eseguito.
/// Finché non ci sono release, l'unità verificabile è il commit del ramo
/// predefinito. Il download resta inchiodato al commit mostrato nella UI.
class LiquidUpdateService {
  static const repository = 'linuxiano85/Liquid-DE';
  static const massimoArchivio = 512 * 1024 * 1024;
  final String installRoot;
  final Directory downloadDirectory;
  final File stateFile;
  final Uri apiBase;
  final Uri archiveBase;
  final HttpClient _http = HttpClient();
  final changes = StreamController<Map<String, dynamic>>.broadcast();
  final _etags = <String, String>{};
  final _responses = <String, Map<String, dynamic>>{};
  Map<String, dynamic> _installed = {};
  Map<String, dynamic> _latest = {};
  Map<String, dynamic> _comparison = {};
  String _comparisonError = "";
  final Duration automaticInterval;
  final Duration initialDelay;
  List<Map<String, dynamic>> _history = [];
  String _phase = 'idle';
  String _error = '';
  String _checkedAt = '';
  String _pauseUntil = '';
  String _retryAt = '';
  int _received = 0;
  int _total = -1;
  int _generation = 0;
  bool _closed = false;
  Future<void>? _checking;
  Future<void>? _downloading;
  Future<void> _saving = Future.value();
  HttpClientRequest? _downloadRequest;
  Timer? _initialTimer;
  Timer? _periodicTimer;

  LiquidUpdateService({
    String? root,
    String? directory,
    String? state,
    Uri? api,
    Uri? archive,
    bool test = false,
    Duration? interval,
    Duration? delay,
  }) : automaticInterval = test
           ? (interval ?? const Duration(hours: 6))
           : const Duration(hours: 6),
       initialDelay = test
           ? (delay ?? const Duration(seconds: 30))
           : const Duration(seconds: 30),
       installRoot = root ?? MinervaPaths.installRoot,
       downloadDirectory = Directory(
         directory ?? '${MinervaPaths.cache()}/updates',
       ),
       stateFile = File(state ?? '${MinervaPaths.dati()}/updates/state.json'),
       apiBase = api ?? Uri.parse('https://api.github.com/'),
       archiveBase = archive ?? Uri.parse('https://codeload.github.com/') {
    // Le prove possono usare esclusivamente un server locale. Il canale IPC
    // non offre URL, repository o percorsi di destinazione modificabili.
    for (final uri in [apiBase, archiveBase]) {
      final production =
          uri.scheme == 'https' &&
          ['api.github.com', 'codeload.github.com'].contains(uri.host);
      final local = test && uri.scheme == 'http' && uri.host == '127.0.0.1';
      if (!production && !local) {
        throw ArgumentError('Origine aggiornamenti non consentita');
      }
    }
    _http.connectionTimeout = const Duration(seconds: 20);
    _http.autoUncompress = false;
  }

  static bool validRevision(dynamic value) =>
      value is String && RegExp(r'^[0-9a-f]{40}$').hasMatch(value);
  bool get busy => _checking != null || _downloading != null;
  bool get paused =>
      (DateTime.tryParse(_pauseUntil)?.isAfter(DateTime.now()) ?? false);
  String _path(String revision) =>
      '${downloadDirectory.path}/Liquid-DE-$revision.zip';
  Map<String, dynamic> get state {
    final revision = _latest['revision'];
    final downloaded =
        validRevision(revision) &&
        _history.any(
          (h) =>
              h['revision'] == revision && File(_path(revision)).existsSync(),
        );
    return {
      'repository': repository,
      'phase': _phase,
      'error': _error,
      'installed': {..._installed},
      'latest': {..._latest},
      'comparison': _comparison,
      'comparisonError': _comparisonError,
      'updateAvailable':
          _comparison['status'] != 'behind' &&
          validRevision(revision) &&
          validRevision(_installed['revision']) &&
          revision != _installed['revision'],
      'checkedAt': _checkedAt,
      'paused': paused,
      'pauseUntil': _pauseUntil,
      'retryAt': _retryAt,
      'received': _received,
      'total': _total,
      'history': _history.map((h) => {...h}).toList(),
      'downloaded': downloaded,
      'downloadFolder': downloadDirectory.path,
    };
  }

  void _emit() {
    if (!_closed) changes.add(state);
  }

  Future<void> _readInstalled() async {
    _installed = {};
    try {
      final file = File('$installRoot/liquid-build.json');
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        if (data is Map && data['repository'] == repository) {
          _installed = {
            'revision': validRevision(data['revision']) ? data['revision'] : '',
            'version': data['version'] is String ? data['version'] : '',
            'dirty': data['dirty'] == true,
          };
        }
      }
    } catch (_) {
      // Una vecchia installazione senza manifesto resta utilizzabile.
    }
  }

  Future<void> init() async {
    await _readInstalled();
    try {
      if (await stateFile.exists()) {
        final data = jsonDecode(await stateFile.readAsString());
        if (data is! Map || data['repository'] != repository) {
          throw const FormatException();
        }
        final latest = data['latest'];
        if (latest is Map &&
            validRevision(latest['revision']) &&
            latest['branch'] is String &&
            latest['message'] is String &&
            latest['date'] is String) {
          _latest = {
            'revision': latest['revision'],
            'branch': latest['branch'],
            'message': latest['message'],
            'date': latest['date'],
          };
        }
        _checkedAt = data['checkedAt'] is String ? data['checkedAt'] : '';
        _pauseUntil = data['pauseUntil'] is String ? data['pauseUntil'] : '';
        if (data['history'] is List) {
          _history = (data['history'] as List)
              .whereType<Map>()
              .where(
                (h) =>
                    validRevision(h['revision']) &&
                    h['sha256'] is String &&
                    RegExp(r'^[0-9a-f]{64}$').hasMatch(h['sha256']) &&
                    h['bytes'] is int &&
                    h['bytes'] >= 0 &&
                    h['bytes'] <= massimoArchivio &&
                    h['date'] is String,
              )
              .take(20)
              .map((h) => Map<String, dynamic>.from(h))
              .toList();
        }
      }
    } catch (_) {
      _error = 'state_invalid';
    }
    _emit();
  }

  Future<void> _save() {
    // Le modifiche della pausa e la fine di un download possono coincidere.
    // Una sola coda evita due rinomine concorrenti del manifesto temporaneo.
    final pending = _saving.then((_) async {
      await stateFile.parent.create(recursive: true);
      final temporary = File('${stateFile.path}.tmp');
      await temporary.writeAsString(
        jsonEncode({
          'repository': repository,
          'latest': _latest,
          'checkedAt': _checkedAt,
          'pauseUntil': _pauseUntil,
          'history': _history,
        }),
        flush: true,
      );
      await temporary.rename(stateFile.path);
    });
    _saving = pending.catchError((Object _) {});
    return pending;
  }

  void startAutomatic() {
    void tick({bool scheduled = false}) {
      final previous = DateTime.tryParse(_checkedAt);
      final due =
          previous == null ||
          DateTime.now().difference(previous) >= automaticInterval;
      if (!_closed && !busy && !paused && (scheduled || due)) {
        unawaited(check());
      }
    }

    _initialTimer ??= Timer(initialDelay, () => tick());
    _periodicTimer ??= Timer.periodic(
      automaticInterval,
      (_) => tick(scheduled: true),
    );
  }

  Future<void> pause(int days) async {
    if (days < 0 || days > 35) return;
    _pauseUntil = days == 0
        ? ''
        : DateTime.now().toUtc().add(Duration(days: days)).toIso8601String();
    try {
      await _save();
    } catch (_) {
      _error = 'storage';
    }
    _emit();
  }

  Future<Map<String, dynamic>> _json(String path) async {
    final req = await _http
        .getUrl(apiBase.resolve(path))
        .timeout(const Duration(seconds: 20));
    req.followRedirects = false;
    req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    req.headers.set(HttpHeaders.userAgentHeader, 'Liquid-DE-Update');
    req.headers.set('X-GitHub-Api-Version', '2022-11-28');
    if (_etags.containsKey(path)) {
      req.headers.set(HttpHeaders.ifNoneMatchHeader, _etags[path]!);
    }
    final response = await req.close().timeout(const Duration(seconds: 20));
    if (response.statusCode == 304 && _responses.containsKey(path)) {
      await response.drain<void>();
      return _responses[path]!;
    }
    if (response.statusCode != 200) {
      if (response.statusCode == 403 || response.statusCode == 429) {
        final reset = int.tryParse(
          response.headers.value('x-ratelimit-reset') ?? '',
        );
        if (reset != null) {
          _retryAt = DateTime.fromMillisecondsSinceEpoch(
            reset * 1000,
            isUtc: true,
          ).toIso8601String();
        }
      }
      await response.drain<void>();
      throw HttpException('http_${response.statusCode}');
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 20))) {
      bytes.addAll(chunk);
      if (bytes.length > 2 * 1024 * 1024) {
        throw const FormatException('response_size');
      }
    }
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Map<String, dynamic>) throw const FormatException('response');
    final tag = response.headers.value(HttpHeaders.etagHeader);
    if (tag != null) _etags[path] = tag;
    _responses[path] = data;
    return data;
  }

  Future<void> check() {
    if (_closed || _downloading != null) return Future.value();
    return _checking ??= _check().whenComplete(() => _checking = null);
  }

  Future<void> _check() async {
    _phase = 'checking';
    _error = '';
    _retryAt = '';
    _comparison = {};
    _comparisonError = '';
    _emit();
    try {
      await _readInstalled();
      final repo = await _json('repos/$repository');
      if (repo['full_name'] != repository ||
          repo['default_branch'] is! String) {
        throw const FormatException('repository');
      }
      final branch = repo['default_branch'] as String;
      final commit = await _json(
        'repos/$repository/commits/${Uri.encodeComponent(branch)}',
      );
      if (!validRevision(commit['sha'])) {
        throw const FormatException('revision');
      }
      final info = commit['commit'];
      if (info is! Map ||
          info['message'] is! String ||
          info['committer'] is! Map) {
        throw const FormatException('commit');
      }
      _latest = {
        'revision': commit['sha'],
        'branch': branch,
        'message': (info['message'] as String).split('\n').first,
        'date': info['committer']['date'] is String
            ? info['committer']['date']
            : '',
      };
      if (validRevision(_installed['revision'])) {
        try {
          final base = _installed['revision'];
          final target = _latest['revision'];
          final comparison = await _json(
            'repos/$repository/compare/$base...$target',
          );
          _comparison = LiquidUpdateChanges.parse(comparison);
          _comparison['base'] = base;
          _comparison['revision'] = target;
        } catch (error) {
          // Un changelog indisponibile non deve diventare «nessuna modifica».
          _comparisonError = _errorCode(error);
        }
      }
      _checkedAt = DateTime.now().toUtc().toIso8601String();
      _phase = 'checked';
      await _save();
    } catch (e) {
      _phase = 'error';
      _error = _errorCode(e);
      if (e is FormatException) {
        _etags.clear();
        _responses.clear();
      }
    }
    _emit();
  }

  static String _errorCode(Object error) {
    if (error is HttpException && error.message.startsWith('http_')) {
      return error.message;
    }
    if (error is SocketException ||
        error is TimeoutException ||
        error is HandshakeException) {
      return 'network';
    }
    if (error is FormatException) return 'invalid_response';
    if (error is FileSystemException) return 'storage';
    return 'download_failed';
  }

  Future<String> _validate(File file) async {
    // Python è già una dipendenza del DE. testzip verifica struttura e CRC
    // senza estrarre né interpretare script provenienti dall'archivio.
    final zip = await Process.run('python3', [
      '-I',
      '-c',
      'import sys,zipfile\nwith zipfile.ZipFile(sys.argv[1]) as z:\n if sum(i.file_size for i in z.infolist()) > 2147483648: raise ValueError("size")\n if z.testzip() is not None: raise ValueError("CRC")',
      file.path,
    ]);
    if (zip.exitCode != 0) throw const FormatException('archive');
    final hash = await Process.run('sha256sum', ['--', file.path]);
    final digest = hash.stdout.toString().split(' ').first.trim();
    if (hash.exitCode != 0 || !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
      throw const FormatException('checksum');
    }
    return digest;
  }

  Future<bool> _cachedValid(File file, Map<String, dynamic>? entry) async {
    if (entry == null || !await file.exists()) return false;
    try {
      return await _validate(file) == entry['sha256'];
    } catch (_) {
      // Una cache danneggiata si ricostruisce dalla fonte, non impedisce
      // tutti i download successivi della stessa revisione.
      return false;
    }
  }

  Future<void> download(String revision) {
    if (_closed ||
        _checking != null ||
        !validRevision(revision) ||
        revision != _latest['revision']) {
      return Future.value();
    }
    return _downloading ??= _download(
      revision,
    ).whenComplete(() => _downloading = null);
  }

  Future<void> _download(String revision) async {
    final generation = ++_generation;
    final temporary = File('${_path(revision)}.part');
    IOSink? sink;
    _phase = 'downloading';
    _error = '';
    _received = 0;
    _total = -1;
    _emit();
    try {
      await downloadDirectory.create(recursive: true);
      final file = File(_path(revision));
      final previous = _history
          .where((h) => h['revision'] == revision)
          .firstOrNull;
      if (await _cachedValid(file, previous)) {
        _phase = 'ready';
        _emit();
        return;
      }
      final request = await _http
          .getUrl(archiveBase.resolve('$repository/zip/$revision'))
          .timeout(const Duration(seconds: 20));
      _downloadRequest = request;
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, 'Liquid-DE-Update');
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != 200) {
        throw HttpException('http_${response.statusCode}');
      }
      _total = response.contentLength;
      if (_total > massimoArchivio) throw const FormatException('archive_size');
      sink = temporary.openWrite();
      var last = DateTime.now();
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        if (generation != _generation || _closed) throw const _Cancelled();
        _received += chunk.length;
        if (_received > massimoArchivio) {
          throw const FormatException('archive_size');
        }
        sink.add(chunk);
        // Non si accumula l'archivio in memoria: il disco governa il ritmo.
        await sink.flush();
        final now = DateTime.now();
        if (now.difference(last) >= const Duration(milliseconds: 200)) {
          last = now;
          _emit();
        }
      }
      await sink.close();
      sink = null;
      if (_total >= 0 && _received != _total) {
        throw const FormatException('truncated');
      }
      final checksum = await _validate(temporary);
      if (generation != _generation || _closed) throw const _Cancelled();
      await temporary.rename(file.path);
      _history.removeWhere((h) => h['revision'] == revision);
      _history.insert(0, {
        'revision': revision,
        'sha256': checksum,
        'bytes': _received,
        'date': DateTime.now().toUtc().toIso8601String(),
      });
      _history = _history.take(20).toList();
      _phase = 'ready';
      await _save();
    } catch (e) {
      _phase = generation != _generation || e is _Cancelled
          ? 'cancelled'
          : 'error';
      _error = _phase == 'cancelled' ? '' : _errorCode(e);
    } finally {
      _downloadRequest = null;
      try {
        await sink?.close();
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {
        _phase = 'error';
        _error = 'storage';
      }
    }
    _emit();
  }

  void cancel() {
    if (_downloading == null) return;
    _generation++;
    _downloadRequest?.abort();
  }

  Future<void> close() async {
    _closed = true;
    _initialTimer?.cancel();
    _periodicTimer?.cancel();
    cancel();
    _http.close(force: true);
    await _checking;
    await _downloading;
    await _saving;
    await changes.close();
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}
