import 'dart:convert';
import 'dart:io';
import '../core/linux_files.dart';

/// Confine delle rinomine native, sostituibile nel banco per provocare errori
/// dopo una syscall riuscita senza affidarsi a una corsa temporale nei test.
abstract interface class RenameOperations {
  void noReplace(String from, String to);
  void exchange(String from, String to);
}

final class NativeRenameOperations implements RenameOperations {
  const NativeRenameOperations();
  @override
  void noReplace(String from, String to) =>
      LinuxFiles.renameNoReplace(from, to);
  @override
  void exchange(String from, String to) => LinuxFiles.exchange(from, to);
}

/// Lo staging può contenere un originale: il chiamante NON deve eliminarlo.
final class OriginalRecoveryRequired extends FileSystemException {
  OriginalRecoveryRequired(
    this.staging,
    List<String> paths,
    OSError? error, {
    this.recoveryErrorCode,
  }) : paths = List.unmodifiable(paths),
       super(
         'Spostamento interrotto. Non eliminare la cartella di recupero. '
         'Verificare i dati in: ${paths.join('; ')}',
         staging,
         error,
       );
  final String staging;
  final List<String> paths;
  final int? recoveryErrorCode;
}

/// Sostituzione sullo stesso filesystem, senza copiare e poi eliminare
/// l'inode sorgente. Gli fd già aperti continuano a puntare al file spostato.
/// Il vecchio bersaglio resta nello staging privato fino alla pulizia.
final class StagedReplacement {
  const StagedReplacement({this.operations = const NativeRenameOperations()});
  final RenameOperations operations;

  /// false solo per EXDEV PRIMA di acquisire la sorgente. Negli altri errori
  /// si ripristina senza sovrascrivere, oppure si conserva lo staging.
  bool publish(String source, String target, Directory staging) {
    source = File(source).absolute.path;
    target = File(target).absolute.path;
    final held = '${staging.path}/contenuto';
    final original = LinuxFiles.version(source);
    final previous = LinuxFiles.version(target);
    final intent = File('${staging.path}/spostamento.json');
    intent.writeAsStringSync(
      jsonEncode({
        'schema': 1,
        'operation': 'replace-by-rename',
        'source': source,
        'target': target,
        'held': held,
        'sourceNode': [original.node.$1, original.node.$2, original.node.$3],
        'targetNode': [previous.node.$1, previous.node.$2, previous.node.$3],
      }),
      flush: true,
    );
    LinuxFiles.fsyncCartella(staging.path);
    LinuxFiles.fsyncCartella(staging.parent.path);
    var claimed = false;
    LinuxFileVersion? claimedVersion;
    try {
      try {
        operations.noReplace(source, held);
      } catch (e) {
        // Anche un errore del backend dopo una rinomina eseguita non deve
        // autorizzare il chiamante a cancellare un originale nello staging.
        try {
          if (LinuxFiles.entryExists(held)) {
            claimed = true;
            claimedVersion = LinuxFiles.version(held);
          }
        } catch (probeError) {
          throw OriginalRecoveryRequired(
            staging.path,
            [held, target, source],
            e is FileSystemException ? e.osError : null,
            recoveryErrorCode: probeError is FileSystemException
                ? probeError.osError?.errorCode
                : null,
          );
        }
        if (!claimed &&
            e is FileSystemException &&
            e.osError?.errorCode == 18) {
          // Non lasciare un intento di rinomina nello staging che verrà
          // riutilizzato per una copia, eventualmente ancora parziale.
          intent.deleteSync();
          return false;
        }
        rethrow;
      }
      claimed = true;
      claimedVersion = LinuxFiles.version(held);
      if (claimedVersion.node != original.node) {
        throw FileSystemException(
          'La sorgente è stata sostituita prima dello spostamento.',
          source,
        );
      }
      LinuxFiles.fsyncCartella(staging.path);
      operations.exchange(held, target);
      claimed = false;
      return true;
    } catch (error, stack) {
      if (error is OriginalRecoveryRequired) {
        rethrow;
      }
      if (claimed) {
        try {
          // Se un backend ha completato exchange ma riportato un errore,
          // non riportare il vecchio bersaglio al posto della sorgente.
          if (claimedVersion == null ||
              LinuxFiles.version(held).node != claimedVersion.node) {
            throw StateError('Identità del contenuto di recupero incerta');
          }
          operations.noReplace(held, source);
          // Conservare l'intento se il ripristino non è stato sincronizzato:
          // un successo solo in memoria non autorizza a perdere la diagnosi.
          LinuxFiles.fsyncCartella(staging.path);
          LinuxFiles.fsyncCartella(File(source).parent.path);
        } catch (restoreError) {
          throw OriginalRecoveryRequired(
            staging.path,
            [held, target, source],
            error is FileSystemException ? error.osError : null,
            recoveryErrorCode: restoreError is FileSystemException
                ? restoreError.osError?.errorCode
                : null,
          );
        }
      }
      Error.throwWithStackTrace(error, stack);
    }
  }
}
