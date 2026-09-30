import 'dart:io';

import 'linux_files.dart';

/// Salvataggio — Riscrivere un documento senza rovinare quello che aveva
/// intorno.
///
/// ── Cosa faceva `fs_write`, provato il 30 settembre 2026 ───────────────────
///
/// Scriveva in `<file>.minerva.tmp` e poi lo spostava sopra il vero. L'idea è
/// giusta — una scrittura interrotta non tronca il documento — ma il file
/// provvisorio nasceva con l'umask, e lo spostamento sostituisce il NOME:
///
///  · `~/.ssh/config` o un `.env` a 0600, salvati dall'editor, diventavano
///    0644, cioè leggibili da chiunque sul computer;
///  · un dotfile tenuto con un collegamento simbolico (stow, un repository di
///    configurazioni) diventava un file normale, e il file vero restava com'era:
///    si «salvava» e la modifica non arrivava dove doveva;
///  · il nome provvisorio era sempre lo stesso: due salvataggi dello stesso
///    file da due finestre si scrivevano addosso, e un `x.minerva.tmp` vero
///    dell'utente veniva schiacciato.
///
/// ── Come si fa adesso ──────────────────────────────────────────────────────
///
///  1. si risolve il collegamento e si scrive sul file vero;
///  2. il provvisorio sta in una cartella privata (0700, nome casuale) accanto
///     al file, sullo stesso filesystem, quindi lo spostamento resta atomico;
///  3. prima di spostarlo gli si danno il gruppo e i permessi del file di
///     prima;
///  4. dopo lo spostamento si fa fsync della cartella, perché il nome nuovo
///     sopravviva a un'interruzione di corrente.
///
/// Se il proprietario o il gruppo non si possono conservare — il file è di un
/// altro utente e noi possiamo solo scriverci dentro — si scrive AL POSTO,
/// come fa vim con `backupcopy=auto`: meglio un file che resta di chi era che
/// un file che cambia padrone di nascosto. Lo stesso per un file con più
/// collegamenti fisici, che lo spostamento separerebbe.
class Salvataggio {
  const Salvataggio._();

  /// Scrive [testo] in [percorso] e restituisce il file vero che ha scritto.
  static Future<String> scrivi(String percorso, String testo) async {
    final vero = await _bersaglio(percorso);
    final file = File(vero);
    final cartella = file.parent;
    final cera = await file.exists();

    if (cera && !await _siPuoSostituire(vero)) {
      await file.writeAsString(testo, flush: true);
      return vero;
    }

    final riparo = LinuxFiles.privateTemp(cartella, '.minerva-salva-');
    try {
      final provvisorio = File('${riparo.path}/documento');
      await provvisorio.writeAsString(testo, flush: true);
      if (cera) {
        // Prima il gruppo, poi i permessi: `chown` toglie i bit speciali, e
        // `chmod --reference` li rimette com'erano. Il proprietario è già il
        // nostro (vedi `_siPuoSostituire`); il gruppo può non esserlo — un
        // file di un gruppo condiviso — e se non si riesce a conservarlo si
        // scrive al posto, per la stessa ragione del proprietario.
        final g = await Process.run(
            'chown', ['--reference=$vero', '--', provvisorio.path]);
        if (g.exitCode != 0) {
          await file.writeAsString(testo, flush: true);
          return vero;
        }
        final m = await Process.run(
            'chmod', ['--reference=$vero', '--', provvisorio.path]);
        if (m.exitCode != 0) {
          throw FileSystemException(
              'Non riesco a conservare i permessi: ${m.stderr}'.trim(), vero);
        }
      } else {
        // Un file nuovo nasce come lo farebbe nascere chiunque altro: con
        // l'umask di chi lavora, e non 0600 perché il provvisorio stava in una
        // cartella privata.
        await _comeUnFileNuovo(provvisorio.path);
      }
      await provvisorio.rename(vero);
    } finally {
      await riparo.delete(recursive: true);
    }
    try {
      LinuxFiles.fsyncCartella(cartella.path);
    } catch (_) {
      // Il documento è già scritto e al suo posto: una cartella su cui non si
      // riesce a fare fsync (un filesystem di rete) non è un salvataggio
      // fallito.
    }
    return vero;
  }

  /// Il file su cui scrivere davvero: se [percorso] è un collegamento, il suo
  /// bersaglio. Un collegamento che non porta da nessuna parte è un errore da
  /// dire, non un file da creare al posto del collegamento.
  static Future<String> _bersaglio(String percorso) async {
    final tipo = await FileSystemEntity.type(percorso, followLinks: false);
    if (tipo != FileSystemEntityType.link) return percorso;
    try {
      return await File(percorso).resolveSymbolicLinks();
    } on FileSystemException {
      throw FileSystemException(
          'È un collegamento che non porta a nessun file', percorso);
    }
  }

  /// Vero se sostituire il file non gli cambia proprietario né lo separa da
  /// altri collegamenti fisici.
  static Future<bool> _siPuoSostituire(String vero) async {
    final r = await Process.run('stat', ['-c', '%u %h', '--', vero]);
    final io = await Process.run('id', ['-u']);
    if (r.exitCode != 0 || io.exitCode != 0) return false;
    final campi = '${r.stdout}'.trim().split(' ');
    if (campi.length != 2) return false;
    return campi[0] == '${io.stdout}'.trim() && campi[1] == '1';
  }

  static Future<void> _comeUnFileNuovo(String p) async {
    final r = await Process.run('sh', [
      '-c',
      r'chmod "$(printf "%o" $((0666 & ~$(umask))))" -- "$1"',
      'sh',
      p,
    ]);
    if (r.exitCode != 0) {
      throw FileSystemException('Non riesco a dare i permessi: ${r.stderr}', p);
    }
  }
}
