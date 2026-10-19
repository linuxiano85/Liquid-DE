import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'migrations.dart' as m;

/// Il file non è un database SQLite o è danneggiato.
/// Il daemon può reagire ricostruendo la cache dal server: tutto ciò che sta
/// nel database locale è riscaricabile, tranne le bozze non ancora salvate.
class DatabaseCorruptException implements Exception {
  DatabaseCorruptException(this.path, this.detail);
  final String path;
  final String detail;
  @override
  String toString() => 'Database danneggiato ($path): $detail';
}

/// Il database è stato creato da una versione più recente del daemon.
/// Aprirlo con una versione vecchia rischierebbe di corromperlo.
class DatabaseTooNewException implements Exception {
  DatabaseTooNewException(this.found, this.supported);
  final int found;
  final int supported;
  @override
  String toString() =>
      'Database versione $found, questo daemon supporta fino alla $supported';
}

/// Una migrazione è fallita: il database è rimasto alla versione precedente.
class MigrationFailedException implements Exception {
  MigrationFailedException(this.version, this.cause);
  final int version;
  final Object cause;
  @override
  String toString() => 'Migrazione $version fallita (rollback eseguito): $cause';
}

/// Connessione al database locale con migrazioni e controlli all'apertura.
class MailDatabase {
  MailDatabase._(this.db, this.path);

  final Database db;
  final String path;

  static const _sqliteCorrupt = 11;
  static const _sqliteNotADb = 26;

  /// Apre (o crea) il database e lo porta all'ultima versione.
  ///
  /// [migrationList] è sostituibile solo nei test, per simulare
  /// migrazioni difettose.
  static MailDatabase open(String path,
      {List<m.Migration> migrationList = m.migrations}) {
    final db = path == ':memory:' ? sqlite3.openInMemory() : sqlite3.open(path);
    try {
      _checkIntegrity(db, path);
      db.execute('PRAGMA foreign_keys = ON');
      db.execute('PRAGMA busy_timeout = 5000');
      if (path != ':memory:') {
        // Prima i permessi, poi il WAL: SQLite crea -wal e -shm copiando i
        // permessi del database, quindi da qui in poi nascono già 0600.
        _restrict([path]);
        db.execute('PRAGMA journal_mode = WAL');
        _restrict(['$path-wal', '$path-shm'].where((f) => File(f).existsSync()).toList());
      }
      _migrate(db, migrationList);
      return MailDatabase._(db, path);
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  int get schemaVersion => db.userVersion;

  void close() => db.close();

  /// Esegue [action] in una transazione: se lancia, nulla viene salvato.
  T transaction<T>(T Function() action) {
    db.execute('BEGIN IMMEDIATE');
    try {
      final result = action();
      db.execute('COMMIT');
      return result;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Il database contiene oggetti, mittenti e testi delle email: solo il
  /// proprietario lo legge, anche se la cartella intorno fosse più aperta.
  static void _restrict(List<String> files) {
    if (files.isEmpty) return;
    final r = Process.runSync('chmod', ['600', ...files]);
    if (r.exitCode != 0) {
      throw FileSystemException('chmod 600 fallito: ${r.stderr}', files.first);
    }
  }

  static void _checkIntegrity(Database db, String path) {
    try {
      final rows = db.select('PRAGMA quick_check');
      final problems =
          rows.map((r) => r.columnAt(0) as String).where((s) => s != 'ok').toList();
      if (problems.isNotEmpty) {
        throw DatabaseCorruptException(path, problems.take(3).join('; '));
      }
    } on SqliteException catch (e) {
      if (e.resultCode == _sqliteCorrupt || e.resultCode == _sqliteNotADb) {
        throw DatabaseCorruptException(path, e.message);
      }
      rethrow;
    }
  }

  static void _migrate(Database db, List<m.Migration> list) {
    for (var i = 0; i < list.length; i++) {
      if (list[i].version != i + 1) {
        throw StateError('Migrazioni non consecutive: attesa ${i + 1}, '
            'trovata ${list[i].version}');
      }
    }
    final current = db.userVersion;
    final latest = list.length;
    if (current > latest) throw DatabaseTooNewException(current, latest);

    for (final migration in list.skip(current)) {
      db.execute('BEGIN IMMEDIATE');
      try {
        for (final sql in migration.statements) {
          db.execute(sql);
        }
        db.userVersion = migration.version;
        db.execute('COMMIT');
      } catch (e) {
        db.execute('ROLLBACK');
        throw MigrationFailedException(migration.version, e);
      }
    }
  }
}
