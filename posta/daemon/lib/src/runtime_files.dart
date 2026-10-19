import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// Gestisce i file di runtime condivisi con la UI:
/// `$XDG_RUNTIME_DIR/liquid-mail/{token,port}`.
///
/// La cartella è 0700 e i file 0600: solo l'utente proprietario della
/// sessione può leggere il token e quindi parlare con il daemon.
class RuntimeFiles {
  RuntimeFiles(this.directory);

  /// Usa $XDG_RUNTIME_DIR; senza di esso il daemon si rifiuta di partire,
  /// perché /tmp è condiviso tra utenti e non garantisce la riservatezza.
  factory RuntimeFiles.fromEnvironment([Map<String, String>? env]) {
    final runtimeDir = (env ?? Platform.environment)['XDG_RUNTIME_DIR'];
    if (runtimeDir == null || runtimeDir.isEmpty) {
      throw StateError(
          'XDG_RUNTIME_DIR non impostata: impossibile salvare il token in modo sicuro');
    }
    return RuntimeFiles(Directory(p.join(runtimeDir, 'liquid-mail')));
  }

  final Directory directory;

  File get tokenFile => File(p.join(directory.path, 'token'));
  File get portFile => File(p.join(directory.path, 'port'));
  File get lockFile => File(p.join(directory.path, 'lock'));

  RandomAccessFile? _lock;

  /// Prende il posto di unico daemon della sessione. False se un altro
  /// daemon lo tiene già: in quel caso questo processo deve uscire SENZA
  /// toccare token, porta e database.
  ///
  /// Senza blocco un secondo avvio (doppio clic, autostart più lanciatore)
  /// sovrascriveva token e porta del primo, che restava vivo ma
  /// irraggiungibile, e i due sincronizzavano lo stesso database insieme.
  ///
  /// È un lock di sistema (`fcntl`): muore con il processo, anche con
  /// SIGKILL, quindi un crash non lascia un blocco da togliere a mano. Il
  /// file non si cancella mai: cancellarlo aprirebbe una finestra in cui
  /// due processi bloccano due file diversi con lo stesso nome.
  Future<bool> acquireInstanceLock() async {
    if (_lock != null) return true;
    await directory.create(recursive: true);
    await _chmod('700', directory.path);
    final file = await lockFile.open(mode: FileMode.append);
    try {
      await file.lock(FileLock.exclusive);
    } on FileSystemException {
      await file.close();
      return false;
    }
    _lock = file;
    return true;
  }

  Future<void> releaseInstanceLock() async {
    final file = _lock;
    _lock = null;
    if (file == null) return;
    await file.unlock();
    await file.close();
  }

  /// Genera un token casuale da 32 byte (base64url, 43 caratteri).
  static String generateToken([Random? random]) {
    final rnd = random ?? Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Scrive token e porta con permessi restrittivi.
  Future<void> write({required String token, required int port}) async {
    await directory.create(recursive: true);
    await _chmod('700', directory.path);
    // Il file viene creato vuoto, ristretto a 0600 e solo dopo riempito:
    // il token non è mai leggibile da altri, nemmeno per un istante.
    await _writePrivate(tokenFile, token);
    await _writePrivate(portFile, '$port');
  }

  Future<void> clear() async {
    for (final f in [tokenFile, portFile]) {
      if (await f.exists()) await f.delete();
    }
  }

  Future<void> _writePrivate(File file, String content) async {
    await file.writeAsString('');
    await _chmod('600', file.path);
    await file.writeAsString(content, flush: true);
  }

  static Future<void> _chmod(String mode, String path) async {
    final result = await Process.run('chmod', [mode, path]);
    if (result.exitCode != 0) {
      throw FileSystemException('chmod $mode fallito: ${result.stderr}', path);
    }
  }
}
