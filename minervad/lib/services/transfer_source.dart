import 'dart:io';
import '../core/linux_files.dart';

/// Versioni delle voci effettivamente attraversate dalla copia.
/// Verifica conservativa: nessuna rimozione se l'albero è cambiato o non
/// è più leggibile. Non sostituisce uno snapshot del filesystem o un lock
/// condiviso con gli altri writer: fra verifica e unlink resta una finestra.
final class TransferSource {
  final _entries = <String, LinuxFileVersion>{};

  void record(String path) => _entries[path] = LinuxFiles.version(path);

  void verifyEntry(String path) =>
      verifyVersion(path, LinuxFiles.version(path));

  void verifyVersion(String path, LinuxFileVersion current) {
    final expected = _entries[path];
    if (expected == null || !expected.sameAs(current)) {
      throw FileSystemException(
        'La sorgente è cambiata durante il trasferimento. '
        'Non viene eliminata; controlla le versioni prima di riprovare.',
        path,
      );
    }
  }

  Future<void> verify(String root) async {
    var count = 0;
    Future<void> visit(String path) async {
      verifyEntry(path);
      count++;
      if (_entries[path]!.kind == 0x4000) {
        await for (final entry in Directory(path).list(followLinks: false)) {
          await visit(entry.path);
        }
        // Anche una modifica mentre si enumerano i figli deve emergere.
        verifyEntry(path);
      }
    }

    await visit(root);
    if (count != _entries.length) {
      throw FileSystemException(
        'Il contenuto della cartella sorgente è cambiato. '
        'La sorgente non viene eliminata.',
        root,
      );
    }
  }

  /// Rimuove solo le voci copiate. Mai delete(recursive:true): un figlio
  /// aggiunto dopo verify deve far fallire rmdir, non essere cancellato.
  /// Ogni foglia è ricontrollata prima della propria rimozione. Restano
  /// possibili scritture/rinominazioni non cooperative dopo tale controllo.
  Future<void> remove() async {
    final removedLinks = <(int, int, int), int>{};
    for (final path in _entries.keys.toList().reversed) {
      final expected = _entries[path]!;
      if (expected.kind == 0x4000) {
        if (!expected.sameDirectoryAfterRemoval(LinuxFiles.version(path))) {
          throw FileSystemException(
            'La cartella sorgente è stata sostituita durante lo spostamento.',
            path,
          );
        }
        await Directory(path).delete();
      } else {
        final removed = removedLinks[expected.node] ?? 0;
        final current = LinuxFiles.version(path);
        if (!(removed == 0
            ? expected.sameAs(current)
            : expected.sameAfterRemovingLinks(current, removed))) {
          throw FileSystemException(
            'La sorgente è cambiata prima della rimozione. '
            'La copia pubblicata viene conservata.',
            path,
          );
        }
        if (expected.kind == 0xa000) {
          await Link(path).delete();
        } else {
          await File(path).delete();
        }
        removedLinks[expected.node] = removed + 1;
      }
    }
  }
}
