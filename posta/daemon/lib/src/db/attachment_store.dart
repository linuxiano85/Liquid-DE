import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Archivio degli allegati, indirizzato per contenuto: ogni file si chiama
/// con lo SHA-256 dei suoi byte, in `<radice>/ab/abcdef…`.
///
/// - **Deduplicazione**: lo stesso PDF arrivato in dieci email occupa spazio
///   una volta sola.
/// - **Scrittura atomica**: si scrive un file temporaneo nella stessa
///   cartella e lo si rinomina. Uno spegnimento a metà lascia al massimo un
///   temporaneo, che [collectGarbage] toglie, mai un allegato troncato con
///   il nome giusto.
/// - **Riservatezza**: cartelle 0700, file 0600.
/// - **Nessun nome dall'email**: il percorso dipende solo dall'hash, quindi
///   un nome file ostile ("../../.bashrc") non può decidere dove si scrive.
///   Il nome da mostrare sta nel database.
class AttachmentStore {
  AttachmentStore(this.root);

  final Directory root;
  final _random = Random.secure();

  static final _hex64 = RegExp(r'^[0-9a-f]{64}$');

  File fileFor(String sha256Hex) {
    if (!_hex64.hasMatch(sha256Hex)) {
      throw ArgumentError.value(sha256Hex, 'sha256Hex', 'non è uno SHA-256 esadecimale minuscolo');
    }
    return File(p.join(root.path, sha256Hex.substring(0, 2), sha256Hex));
  }

  /// Salva [bytes] e restituisce il loro SHA-256. Se c'è già, non riscrive.
  Future<String> put(Uint8List bytes) async {
    final hash = sha256.convert(bytes).toString();
    final target = fileFor(hash);
    if (await target.exists() && await target.length() == bytes.length) return hash;
    final dir = target.parent;
    await _privateDir(root);
    await _privateDir(dir);
    final tmp = File(p.join(dir.path, '.tmp-${_random.nextInt(1 << 32).toRadixString(16)}'));
    try {
      await tmp.writeAsBytes(const []);
      await _chmod('600', tmp.path);
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(target.path);
    } catch (_) {
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
    return hash;
  }

  /// Byte dell'allegato, o null se manca. Verificati contro l'hash: un file
  /// alterato sul disco non viene mai consegnato come se fosse quello vero.
  Future<Uint8List?> read(String sha256Hex) async {
    final file = fileFor(sha256Hex);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    if (sha256.convert(bytes).toString() != sha256Hex) return null;
    return bytes;
  }

  /// Toglie i file non più citati da nessun messaggio e i temporanei
  /// rimasti da scritture interrotte. Restituisce quanti file ha tolto.
  ///
  /// [referenced] va letto dal database DOPO aver fermato le scritture di
  /// allegati: un allegato salvato ma non ancora registrato verrebbe tolto.
  Future<int> collectGarbage(Set<String> referenced) async {
    if (!await root.exists()) return 0;
    var removed = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('.tmp-') || (_hex64.hasMatch(name) && !referenced.contains(name))) {
        await entity.delete();
        removed++;
      }
    }
    return removed;
  }

  static Future<void> _privateDir(Directory dir) async {
    if (!await dir.exists()) await dir.create(recursive: true);
    await _chmod('700', dir.path);
  }

  static Future<void> _chmod(String mode, String path) async {
    final r = await Process.run('chmod', [mode, path]);
    if (r.exitCode != 0) {
      throw FileSystemException('chmod $mode fallito: ${r.stderr}', path);
    }
  }
}
