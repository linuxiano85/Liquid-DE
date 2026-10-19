import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Identità e versione osservata, senza atime (la lettura lo può cambiare).
/// Non è un lock e non certifica l'assenza di scritture successive.
final class LinuxFileVersion {
  LinuxFileVersion(this._values);
  final List<int> _values;
  int get kind => _values[2] & 0xf000;
  (int, int, int) get node => (_values[0], _values[1], _values[3]);
  int get mode => _values[2] & 0xfff;
  int get uid => _values[6];
  int get size => _values[4];
  bool sameAs(LinuxFileVersion other) {
    for (var i = 0; i < _values.length; i++) {
      if (_values[i] != other._values[i]) return false;
    }
    return true;
  }

  /// Rimuovere figli cambia size/nlink/mtime/ctime della directory. Restano
  /// obbligatori device, inode, modo, uid e gid: non basta il vecchio nome.
  bool sameDirectoryAfterRemoval(LinuxFileVersion other) =>
      kind == 0x4000 && other.kind == 0x4000 &&
      [0, 1, 2, 3, 6, 7].every((i) => _values[i] == other._values[i]);

  /// Un nostro unlink di un altro hard link cambia nlink e ctime anche qui.
  /// Dimensione, mtime, identità e permessi devono invece restare invariati.
  bool sameAfterRemovingLinks(LinuxFileVersion other, int removed) =>
      other._values[5] == _values[5] - removed &&
      [0, 1, 2, 3, 4, 6, 7, 10, 11]
          .every((i) => _values[i] == other._values[i]);
}

/// Riferimento stabile a un file regolare. O_PATH non apre il contenuto e
/// non attende un writer se il nome è diventato una FIFO. La lettura tramite
/// procfs riapre questo inode e controlla i permessi del file: non il nome
/// originale, che nel frattempo può indicare un altro oggetto.
final class LinuxRegularSource {
  LinuxRegularSource._(this._fd, this.version, this.sourcePath);
  int _fd;
  final LinuxFileVersion version;
  final String sourcePath;

  String get descriptorPath {
    if (_fd < 0) throw StateError('Sorgente già chiusa');
    return '/proc/self/fd/$_fd';
  }

  Stream<List<int>> openRead() => File(descriptorPath).openRead();

  void close() {
    if (_fd < 0) return;
    final fd = _fd;
    _fd = -1;
    if (LinuxFiles._close(fd) != 0) {
      throw FileSystemException(
        'Chiusura della sorgente non riuscita',
        sourcePath,
        OSError('close', LinuxFiles._errno().value),
      );
    }
  }
}

/// Primitive Linux mancanti in dart:io. Solo FFI della libreria standard:
/// nessuna dipendenza Dart esterna e nessun programma ausiliario.
/// Non ripiegare su exists()+rename(): fra le due chiamate il nome può cambiare.
abstract final class LinuxFiles {
  static final _libc = DynamicLibrary.process();
  static final _malloc = _libc.lookupFunction<Pointer<Void> Function(IntPtr),
      Pointer<Void> Function(int)>('malloc');
  static final _free = _libc.lookupFunction<Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('free');
  static final _errno = _libc.lookupFunction<Pointer<Int32> Function(),
      Pointer<Int32> Function()>('__errno_location');
  static final _getuid =
      _libc.lookupFunction<Uint32 Function(), int Function()>('getuid');

  /// L'utente reale del processo: serve a riconoscere una cartella nostra.
  static int get uid => _getuid();

  static final _kill = _libc.lookupFunction<Int32 Function(Int32, Int32),
      int Function(int, int)>('kill');

  /// Only for a process group created and still owned by the caller.
  static bool segnalaGruppo(int gruppo, int segnale) {
    if (gruppo <= 1 || gruppo > 0x7fffffff || ![9,15].contains(segnale)) {
      throw ArgumentError('Gruppo o segnale non valido');
    }
    return _kill(-gruppo, segnale) == 0;
  }

  /// Segnale zero: controlla l'esistenza del gruppo senza inviare segnali.
  /// Solo ESRCH prova l'assenza; permessi insufficienti restano un'incertezza.
  static bool? gruppoProcessiEsiste(int gruppo) {
    if (gruppo <= 1 || gruppo > 0x7fffffff) return null;
    final errore = _errno();
    if (_kill(-gruppo, 0) == 0) return true;
    return errore.value == 3 ? false : null; // ESRCH su Linux
  }
  static final _rename = _libc.lookupFunction<
      Int32 Function(Int32, Pointer<Uint8>, Int32, Pointer<Uint8>, Uint32),
      int Function(int, Pointer<Uint8>, int, Pointer<Uint8>, int)>('renameat2');
  static final _mkdir = _libc.lookupFunction<Int32 Function(Pointer<Uint8>, Uint32),
      int Function(Pointer<Uint8>, int)>('mkdir');

  static final _chmod = _libc.lookupFunction<Int32 Function(Pointer<Uint8>, Uint32),
      int Function(Pointer<Uint8>, int)>('chmod');

  static final _utimensat = _libc.lookupFunction<
      Int32 Function(Int32, Pointer<Uint8>, Pointer<Int64>, Int32),
      int Function(int, Pointer<Uint8>, Pointer<Int64>, int)>('utimensat');

  static final _faccessat = _libc.lookupFunction<
      Int32 Function(Int32, Pointer<Uint8>, Int32, Int32),
      int Function(int, Pointer<Uint8>, int, int)>('faccessat');

  static final _statx = _libc.lookupFunction<
      Int32 Function(Int32, Pointer<Uint8>, Int32, Uint32, Pointer<Uint8>),
      int Function(int, Pointer<Uint8>, int, int, Pointer<Uint8>)>('statx');

  /// Layout UAPI Linux statx: 256 byte, stessi offset su x86_64/aarch64.
  /// Non segue il link finale; nessun ripiego su stat che perda l'identità.
  static LinuxFileVersion version(String path) =>
      _versionAt(-100, path, 0x100, path);

  static LinuxFileVersion _versionAt(
    int dirfd,
    String path,
    int flags,
    String diagnosticPath,
  ) {
    final p = _string(path);
    final memory = _malloc(256).cast<Uint8>();
    if (memory == nullptr) {
      _free(p.cast<Void>());
      throw StateError('Memoria insufficiente per statx');
    }
    try {
      if (_statx(dirfd, p, flags, 0x7ff, memory) != 0) {
        throw FileSystemException(
          'Versione della sorgente non verificabile',
          diagnosticPath,
          OSError('statx', _errno().value),
        );
      }
      final data = ByteData.sublistView(memory.asTypedList(256));
      final endian = Endian.host;
      // TYPE, MODE, NLINK, UID, GID, MTIME, CTIME, INO, SIZE.
      if ((data.getUint32(0, endian) & 0x3df) != 0x3df) {
        throw FileSystemException(
          'Metadati della sorgente incompleti',
          diagnosticPath,
        );
      }
      return LinuxFileVersion([
        data.getUint32(136, endian),
        data.getUint32(140, endian),
        data.getUint16(28, endian),
        data.getUint64(32, endian),
        data.getUint64(40, endian),
        data.getUint32(16, endian),
        data.getUint32(20, endian),
        data.getUint32(24, endian),
        data.getInt64(96, endian),
        data.getUint32(104, endian),
        data.getInt64(112, endian),
        data.getUint32(120, endian),
      ]);
    } finally {
      _free(memory.cast<Void>());
      _free(p.cast<Void>());
    }
  }

  /// Il descrittore viene acquisito senza leggere il contenuto. Prima di
  /// esporre lo stream devono coincidere tipo, identità e versione osservati
  /// al nome e sull'fd. Anche se open segue un link concorrente, nessun byte
  /// di un inode diverso viene letto. Nessun fallback alla lettura per nome.
  static LinuxRegularSource pinRegularSource(String path) {
    final expected = version(path);
    if (expected.kind != 0x8000) {
      throw FileSystemException(
        'Copia di un file speciale non supportata',
        path,
      );
    }
    final p = _string(path);
    int fd;
    try {
      fd = _open(p, 0x200000 | 0x80000); // O_PATH | O_CLOEXEC, UAPI Linux.
      if (fd < 0) {
        throw FileSystemException(
          'Sorgente non acquisita',
          path,
          OSError('open', _errno().value),
        );
      }
    } finally {
      _free(p.cast<Void>());
    }
    try {
      final captured = _versionAt(fd, '', 0x1000, path); // AT_EMPTY_PATH.
      if (captured.kind != 0x8000 || !expected.sameAs(captured)) {
        throw FileSystemException(
          'La sorgente è cambiata prima della lettura',
          path,
        );
      }
      return LinuxRegularSource._(fd, captured, path);
    } catch (_) {
      if (_close(fd) != 0) {
        final error = _errno().value;
        print('[MINERVA][FILE][WARN] Chiusura pin sorgente fallita: errno=$error');
      }
      rethrow;
    }
  }

  /// Verifica l'elemento stesso, anche un symlink interrotto. Solo ENOENT
  /// prova l'assenza: dart:io type/stat possono nascondere altri errori con
  /// notFound. Non ritentare una cancellazione per disambiguare l'errore.
  static bool entryExists(String path) {
    final p = _string(path);
    try {
      // AT_FDCWD, F_OK, AT_SYMLINK_NOFOLLOW | AT_EACCESS (UAPI Linux).
      if (_faccessat(-100, p, 0, 0x100 | 0x200) == 0) return true;
      final error = _errno().value;
      if (error == 2) return false;
      throw FileSystemException('Verifica dell’elemento non riuscita', path,
          OSError('faccessat', error));
    } finally {
      _free(p.cast<Void>());
    }
  }

  /// Imposta solo i bit rwx, senza processi ausiliari. Il chiamante deve
  /// possedere il percorso: per gli staging si usa una directory privata.
  static void setPermissions(String path, int mode) {
    if (mode < 0 || mode > 0x1ff) throw ArgumentError.value(mode, 'mode');
    final p = _string(path);
    try {
      if (_chmod(p, mode) != 0) {
        throw FileSystemException('Permessi non impostati', path,
            OSError('chmod', _errno().value));
      }
    } finally {
      _free(p.cast<Void>());
    }
  }

  /// Solo la data di modifica, anche di una cartella, senza processi
  /// ausiliari (prima era un `touch` per ogni cartella copiata). L'accesso
  /// resta com'è (`UTIME_OMIT`). Segue i collegamenti come `touch -m`.
  static void setModificationTime(String path, DateTime quando) {
    final us = quando.microsecondsSinceEpoch;
    final p = _string(path);
    final tempi = _malloc(32).cast<Int64>();
    if (tempi == nullptr) {
      _free(p.cast<Void>());
      throw StateError('Memoria insufficiente per utimensat');
    }
    try {
      // struct timespec[2] di x86_64/aarch64: {secondi, nanosecondi} ×2.
      tempi[0] = 0;
      tempi[1] = (1 << 30) - 2; // UTIME_OMIT: l'accesso non si tocca.
      tempi[2] = us ~/ 1000000;
      tempi[3] = (us % 1000000) * 1000;
      if (_utimensat(-100, p, tempi, 0) != 0) { // AT_FDCWD
        throw FileSystemException('Data non impostata', path,
            OSError('utimensat', _errno().value));
      }
    } finally {
      _free(tempi.cast<Void>());
      _free(p.cast<Void>());
    }
  }

  /// Nasce 0700: nessuna finestra di esposizione prima di un chmod.
  static Directory privateTemp(Directory parent, String prefix) {
    final random = Random.secure();
    for (var attempt = 0; attempt < 10; attempt++) {
      final suffix = List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      final path = '${parent.path}/$prefix$suffix';
      final p = _string(path);
      try {
        if (_mkdir(p, 0x1c0) == 0) return Directory(path);
        final error = _errno().value;
        if (error != 17) throw FileSystemException('Creazione directory privata fallita', path, OSError('mkdir', error));
      } finally {
        _free(p.cast<Void>());
      }
    }
    throw FileSystemException('Impossibile riservare un nome temporaneo', parent.path);
  }

  static Pointer<Uint8> _string(String value) {
    if (value.contains('\u0000')) throw ArgumentError('NUL nel percorso');
    final bytes = utf8.encode(value);
    final p = _malloc(bytes.length + 1).cast<Uint8>();
    if (p == nullptr) throw StateError('Memoria insufficiente');
    p.asTypedList(bytes.length + 1).setAll(0, [...bytes, 0]);
    return p;
  }

  static void _renameWith(String from, String to, int flags) {
    final a = _string(from);
    try {
      final b = _string(to);
      try {
        if (_rename(-100, a, -100, b, flags) != 0) {
          final error = _errno().value;
          throw FileSystemException('Rinomina atomica non riuscita', from,
              OSError('renameat2 → $to', error));
        }
      } finally {
        _free(b.cast<Void>());
      }
    } finally {
      _free(a.cast<Void>());
    }
  }

  /// Fallisce anche per un symlink interrotto o un conflitto concorrente.
  static void renameNoReplace(String from, String to) => _renameWith(from, to, 1);

  /// Entrambi i nomi devono esistere: il vecchio bersaglio resta recuperabile
  /// al nome temporaneo fino alla pulizia successiva al commit.
  static void exchange(String from, String to) => _renameWith(from, to, 2);

  // `open` è variadica in C; senza il terzo argomento (il modo, che serve solo
  // a O_CREAT) chiamarla con due argomenti fissi è corretto su x86_64 e
  // aarch64. Niente O_DIRECTORY: vale 0x10000 su uno e 0x4000 sull'altro, e
  // una cartella si apre benissimo con O_RDONLY.
  static final _open = _libc.lookupFunction<Int32 Function(Pointer<Uint8>, Int32),
      int Function(Pointer<Uint8>, int)>('open');
  static final _fsync = _libc.lookupFunction<Int32 Function(Int32),
      int Function(int)>('fsync');
  static final _close = _libc.lookupFunction<Int32 Function(Int32),
      int Function(int)>('close');
  static final _syncfs = _libc.lookupFunction<Int32 Function(Int32),
      int Function(int)>('syncfs');

  static final _flock = _libc.lookupFunction<Int32 Function(Int32, Int32),
      int Function(int, int)>('flock');

  /// Lock cooperativo sulla directory, non sull'inode sostituito dal rename.
  /// Ogni open ha un proprio lock anche nello stesso processo. Niente file
  /// laterale prevedibile o attesa bloccante dell'event loop.
  static Future<LinuxDirectoryLease> lockDirectory(Directory directory,
      {Duration timeout = const Duration(seconds: 2)}) async {
    if (Abi.current() != Abi.linuxX64 && Abi.current() != Abi.linuxArm64) {
      throw UnsupportedError('Lock directory: ABI Linux non verificata');
    }
    if (timeout.isNegative) throw ArgumentError.value(timeout, 'timeout');
    final path = await directory.resolveSymbolicLinks();
    final p = _string(path);
    late final int fd;
    try {
      // O_RDONLY | O_CLOEXEC, UAPI Linux x86_64/aarch64. Non ereditare il
      // lock nei programmi avviati mentre la transazione è in corso.
      fd = _open(p, 0x80000);
      if (fd < 0) {
        throw FileSystemException('Directory del salvataggio non apribile', path,
            OSError('open', _errno().value));
      }
    } finally {
      _free(p.cast<Void>());
    }
    var acquired = false;
    final clock = Stopwatch()..start();
    try {
      while (true) {
        if (_flock(fd, 2 | 4) == 0) { // LOCK_EX | LOCK_NB
          acquired = true;
          return LinuxDirectoryLease._(fd);
        }
        final error = _errno().value;
        if (error != 11 && error != 4) { // EWOULDBLOCK / EINTR
          throw FileSystemException('Lock del salvataggio non disponibile', path,
              OSError('flock', error));
        }
        if (clock.elapsed >= timeout) {
          throw FileSystemException('Attesa del salvataggio concorrente scaduta', path,
              const OSError('flock timeout', 110));
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    } finally {
      if (!acquired) _close(fd);
    }
  }

  /// Rende duraturo un `rename` appena fatto dentro [cartella].
  ///
  /// Il file scritto con `flush: true` è al sicuro, ma il NOME nuovo sta nella
  /// cartella: senza questo, dopo un'interruzione di corrente la cartella può
  /// ancora indicare il file vecchio. Dart non sa aprire una cartella, quindi
  /// si passa da libc.
  /// Scrive davvero sul disco tutto quello che il filesystem di [percorso]
  /// tiene in memoria: UNA chiamata per tutti i file di una copia, invece
  /// di un fsync per file. Blocca finché il disco non ha finito: su una
  /// chiavetta lenta sono secondi, quindi va chiamata fuori dal filo del
  /// demone (`Isolate.run`).
  static void syncfs(String percorso) {
    final p = _string(percorso);
    try {
      final fd = _open(p, 0x80000); // O_RDONLY | O_CLOEXEC
      if (fd < 0) {
        throw FileSystemException('Non riesco ad aprire il percorso', percorso,
            OSError('open', _errno().value));
      }
      try {
        if (_syncfs(fd) != 0) {
          throw FileSystemException('Scrittura sul disco non completata',
              percorso, OSError('syncfs', _errno().value));
        }
      } finally {
        _close(fd);
      }
    } finally {
      _free(p.cast<Void>());
    }
  }

  static void fsyncCartella(String cartella) {
    final p = _string(cartella);
    try {
      final fd = _open(p, 0); // O_RDONLY
      if (fd < 0) {
        throw FileSystemException('Non riesco ad aprire la cartella', cartella,
            OSError('open', _errno().value));
      }
      try {
        if (_fsync(fd) != 0) {
          throw FileSystemException('fsync della cartella non riuscito',
              cartella, OSError('fsync', _errno().value));
        }
      } finally {
        _close(fd);
      }
    } finally {
      _free(p.cast<Void>());
    }
  }
}

/// Chiudere l'open file description rilascia il lock anche all'uscita del
/// processo. Non si cancella alcun percorso condiviso con altri scrittori.
class LinuxDirectoryLease {
  LinuxDirectoryLease._(this._fd);
  int _fd;
  void release() {
    if (_fd < 0) return;
    final fd = _fd;
    _fd = -1;
    if (LinuxFiles._close(fd) != 0) {
      print('[MINERVA][FILE][WARN] Chiusura lock directory: errno=${LinuxFiles._errno().value}');
    }
  }
}
