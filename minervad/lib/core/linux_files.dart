import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

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
  static final _rename = _libc.lookupFunction<
      Int32 Function(Int32, Pointer<Uint8>, Int32, Pointer<Uint8>, Uint32),
      int Function(int, Pointer<Uint8>, int, Pointer<Uint8>, int)>('renameat2');
  static final _mkdir = _libc.lookupFunction<Int32 Function(Pointer<Uint8>, Uint32),
      int Function(Pointer<Uint8>, int)>('mkdir');

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

  /// Rende duraturo un `rename` appena fatto dentro [cartella].
  ///
  /// Il file scritto con `flush: true` è al sicuro, ma il NOME nuovo sta nella
  /// cartella: senza questo, dopo un'interruzione di corrente la cartella può
  /// ancora indicare il file vecchio. Dart non sa aprire una cartella, quindi
  /// si passa da libc.
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
