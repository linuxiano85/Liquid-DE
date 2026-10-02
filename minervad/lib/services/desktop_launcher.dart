import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'app_scanner.dart';

class DesktopLaunchError implements Exception {
  DesktopLaunchError(this.message);
  final String message;
  @override
  String toString() => message;
}

class DesktopSnapshot {
  DesktopSnapshot(this.canonicalPath, this.bytes);
  final String canonicalPath;
  final Uint8List bytes;
}

class ApprovedDesktopLaunch {
  ApprovedDesktopLaunch(this.path, this.app, this.command);
  final String path;
  final DesktopApp app;
  final String command;
}

class _Session {
  int reads = 0;
}

class _Consent {
  _Consent(this.owner, this.session, this.path, this.snapshot, this.app,
      this.command, this.deadline);
  final Object owner;
  final _Session session;
  final String path;
  final DesktopSnapshot snapshot;
  final DesktopApp app;
  final String command;
  final DateTime deadline;
}

/// One-use consent for files opened from the desktop, not installed menu items.
/// This protects accidental GUI launches; it is not a sandbox for same-UID code.
class DesktopLauncher {
  DesktopLauncher({
    required this.parse,
    required this.commandFor,
    Future<DesktopSnapshot> Function(String)? reader,
    DateTime Function()? clock,
    this.ttl = const Duration(seconds: 60),
    this.readTimeout = const Duration(seconds: 5),
    this.capacity = 64,
    this.perClient = 8,
  }) : _reader = reader ?? readSnapshot,
       _clock = clock ?? DateTime.now;

  static const maxBytes = 256 * 1024;
  final DesktopApp? Function(String, String) parse;
  final String Function(DesktopApp) commandFor;
  final Future<DesktopSnapshot> Function(String) _reader;
  final DateTime Function() _clock;
  final Duration ttl;
  final Duration readTimeout;
  final int capacity;
  final int perClient;
  final _random = Random.secure();
  final _sessions = <Object, _Session>{};
  final _pending = <String, _Consent>{};
  int _reads = 0;

  int get pendingCount {
    _prune();
    return _pending.length;
  }

  void _prune() {
    final now = _clock();
    _pending.removeWhere((_, value) => !now.isBefore(value.deadline));
  }

  Future<DesktopSnapshot> _read(String path, _Session session) async {
    _prune();
    if (_reads + _pending.length >= capacity || session.reads >= 2) {
      throw DesktopLaunchError('Troppe richieste di avvio in corso.');
    }
    _reads++;
    session.reads++;
    // A timed-out OS read retains its slot until it actually ends: no unbounded
    // accumulation of blocked opens if a regular file is swapped with a FIFO.
    final Future<DesktopSnapshot> future;
    try {
      future = _reader(path);
    } catch (_) {
      _reads--;
      session.reads--;
      rethrow;
    }
    unawaited(future.then<void>((_) {
      _reads--;
      session.reads--;
    }, onError: (Object error, StackTrace stack) {
      _reads--;
      session.reads--;
    }));
    try {
      final snapshot = await future.timeout(readTimeout);
      if (snapshot.bytes.length > maxBytes) {
        throw DesktopLaunchError('Launcher troppo grande.');
      }
      return snapshot;
    } on TimeoutException {
      throw DesktopLaunchError('Tempo massimo per leggere il launcher.');
    }
  }

  Future<Map<String, dynamic>> prepare(Object owner, String path) async {
    _prune();
    if (!path.startsWith('/') || !path.endsWith('.desktop') || path.contains('\u0000')) {
      throw DesktopLaunchError('Percorso del launcher non valido.');
    }
    final session = _sessions.putIfAbsent(owner, _Session.new);
    if (_pending.values.where((c) => identical(c.owner, owner)).length + session.reads >= perClient) {
      throw DesktopLaunchError('Troppe conferme aperte.');
    }
    final snapshot = await _read(path, session);
    if (!identical(_sessions[owner], session)) {
      throw DesktopLaunchError('Richiesta annullata alla disconnessione.');
    }
    if (_pending.length + _reads >= capacity ||
        _pending.values.where((c) => identical(c.owner, owner)).length >= perClient) {
      throw DesktopLaunchError('Troppe conferme aperte.');
    }
    final app = parse(snapshot.canonicalPath, utf8.decode(snapshot.bytes));
    if (app == null || app.exec.trim().isEmpty) {
      throw DesktopLaunchError('Launcher non valido o senza comando.');
    }
    final command = commandFor(app);
    final deadline = _clock().add(ttl);
    final token = base64UrlEncode(List<int>.generate(32, (_) => _random.nextInt(256)));
    _pending[token] = _Consent(owner, session, path, snapshot, app, command, deadline);
    return {'path': path, 'resolvedPath': snapshot.canonicalPath,
            'name': app.name, 'command': command, 'token': token,
            'expires': deadline.millisecondsSinceEpoch};
  }

  Future<ApprovedDesktopLaunch> approve(Object owner, String path, String token) async {
    _prune();
    final consent = _pending[token];
    if (consent == null || !identical(consent.owner, owner) || consent.path != path) {
      throw DesktopLaunchError('Conferma assente, scaduta o di un altro client.');
    }
    // Consume before the first await: duplicates cannot both start the program.
    _pending.remove(token);
    final current = await _read(path, consent.session);
    if (!identical(_sessions[owner], consent.session) ||
        !_clock().isBefore(consent.deadline)) {
      throw DesktopLaunchError('Conferma scaduta o connessione chiusa.');
    }
    if (current.canonicalPath != consent.snapshot.canonicalPath ||
        !_equal(current.bytes, consent.snapshot.bytes)) {
      throw DesktopLaunchError('Il launcher è cambiato: aprilo di nuovo e verifica il comando.');
    }
    // Never reparse the mutable path after verification. Launch the shown command.
    return ApprovedDesktopLaunch(consent.path, consent.app, consent.command);
  }

  bool cancel(Object owner, String token) {
    if (!identical(_pending[token]?.owner, owner)) return false;
    return _pending.remove(token) != null;
  }

  void forget(Object owner) {
    _sessions.remove(owner);
    _pending.removeWhere((_, value) => identical(value.owner, owner));
  }

  static bool _equal(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static Future<DesktopSnapshot> readSnapshot(String path) async {
    final canonical = await File(path).resolveSymbolicLinks();
    if (await FileSystemEntity.type(canonical, followLinks: false) != FileSystemEntityType.file) {
      throw DesktopLaunchError('Il launcher non è un file regolare.');
    }
    final file = await File(canonical).open(mode: FileMode.read);
    try {
      if (await file.length() > maxBytes) {
        throw DesktopLaunchError('Launcher troppo grande.');
      }
      final bytes = BytesBuilder(copy: false);
      while (bytes.length <= maxBytes) {
        final block = await file.read(min(65536, maxBytes + 1 - bytes.length));
        if (block.isEmpty) break;
        bytes.add(block);
      }
      if (bytes.length > maxBytes) throw DesktopLaunchError('Launcher troppo grande.');
      return DesktopSnapshot(canonical, bytes.takeBytes());
    } finally {
      await file.close();
    }
  }
}
