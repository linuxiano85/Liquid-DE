import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../core/linux_files.dart';

import 'archive_service.dart';
import 'image_dims.dart';
import '../core/minerva_paths.dart';

/// Servizio file di Minerva: elenca cartelle ed esegue i trasferimenti.
///
/// I trasferimenti vivono qui e non nella shell per un motivo preciso: devono
/// poter essere messi in pausa, ripresi e annullati. Un `cp` lanciato come
/// processo esterno non si mette in pausa — si può solo uccidere, e uccidere
/// una copia a metà lascia un file troncato che sembra completo. Copiando qui
/// blocco per blocco, la pausa è semplicemente «non leggere il blocco
/// successivo», e l'annullamento cancella ciò che ha scritto finora.
///
/// Ogni lavoro ha un identificativo; la shell lo usa per comandarlo e per
/// mostrare l'avanzamento.
class FileService {
  /// Dove sta il cestino. Si può indicare da fuori **solo per le prove**.
  ///
  /// Senza questo, provare il ripristino vorrebbe dire scrivere nel cestino
  /// VERO di chi esegue le prove — e svuotarlo, perché una delle prove è
  /// proprio «svuota». Nessuna prova deve poter cancellare la roba di
  /// qualcuno. `Platform.environment` in Dart è di sola lettura, quindi non
  /// basta cambiare `XDG_DATA_HOME`: serve un parametro.
  FileService({this.cestinoDiProva});

  final String? cestinoDiProva;

  // ── L'aspetto di una cartella ──────────────────────────────────────────
  //
  // GNOME 2 lo faceva, e nessuno lo fa più: una cartella poteva avere il suo
  // sfondo, e uno riconosceva «Lavoro» prima di leggere il nome. È memoria
  // visiva, e funziona meglio di qualunque etichetta.
  //
  // Sta in un file NOSTRO, fuori dalle cartelle, per due ragioni: non si
  // sporca la roba dell'utente con file di servizio, e funziona anche dove
  // non si può scrivere (un disco di sola lettura, una cartella di sistema).
  // Il prezzo è che l'aspetto non viaggia con la cartella — se un giorno lo
  // vorremo, si aggiunge un `.minerva` DENTRO, senza togliere questo.
  Map<String, dynamic>? _aspetti;

  String get _percorsoAspetti {
    return '${MinervaPaths.dati()}/cartelle.json';
  }

  void _leggiAspetti() {
    if (_aspetti != null) return;
    _aspetti = {};
    try {
      final f = File(_percorsoAspetti);
      if (f.existsSync()) {
        final d = jsonDecode(f.readAsStringSync());
        if (d is Map) _aspetti = Map<String, dynamic>.from(d);
      }
    } catch (_) {
      // Un file rovinato non deve impedire di aprire una cartella: si
      // riparte da vuoto. È uno sfondo, non un dato dell'utente.
      _aspetti = {};
    }
  }

  /// L'aspetto di una cartella, o `null`. `{tipo: 'tinta'|'immagine',
  /// valore: '#rrggbb'|'/percorso'}`.
  Map<String, dynamic>? aspetto(String percorso) {
    _leggiAspetti();
    final v = _aspetti![percorso];
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }

  /// Mette o toglie (`null`) l'aspetto di una cartella.
  Future<Map<String, dynamic>> impostaAspetto(
      String percorso, Map<String, dynamic>? valore) async {
    _leggiAspetti();
    if (valore == null) {
      _aspetti!.remove(percorso);
    } else {
      _aspetti![percorso] = valore;
    }
    try {
      final f = File(_percorsoAspetti);
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode(_aspetti));
      return {'ok': true, 'error': ''};
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
  }

  final Map<String, TransferJob> _jobs = {};
  int _counter = 0;

  /// Notificato a ogni cambio di stato o avanzamento di un lavoro.
  final _progress = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get progress => _progress.stream;

  // ── Lettura ────────────────────────────────────────────────────────────

  /// Contenuto di una cartella. Non solleva mai: una cartella illeggibile
  /// restituisce un errore descritto, che la shell può mostrare al posto di
  /// una finestra vuota e inspiegabile.
  Future<Map<String, dynamic>> list(String path, {bool showHidden = false}) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      return {'path': path, 'error': 'Cartella inesistente', 'entries': []};
    }

    final entries = <Map<String, dynamic>>[];
    try {
      await for (final e in dir.list(followLinks: false)) {
        final name = e.path.split(Platform.pathSeparator).last;
        if (!showHidden && name.startsWith('.')) continue;

        FileStat st;
        try {
          st = await e.stat();
        } catch (_) {
          continue; // voce sparita mentre elencavamo: non è un errore
        }

        final isDir = st.type == FileSystemEntityType.directory;
        entries.add({
          'name': name,
          'path': e.path,
          'isDir': isDir,
          'isLink': e is Link,
          'size': isDir ? 0 : st.size,
          'modified': st.modified.millisecondsSinceEpoch,
          'mode': st.modeString(),
          // «Estrai qui» compare solo su un archivio, e la voce del menu si
          // decide qui e non nell'interfaccia: l'elenco delle estensioni sta
          // in un posto solo (`ArchiveService`), o prima o poi le due copie
          // si allontanano e il gestore file offre di estrarre un `.7z` che
          // il demone non sa aprire.
          'archive': !isDir && ArchiveService.eArchivio(name),
        });
      }
    } on FileSystemException catch (err) {
      return {
        'path': path,
        'error': err.osError?.message ?? 'Accesso negato',
        'entries': [],
      };
    }

    // Cartelle prima, poi per nome senza distinzione di maiuscole: è l'ordine
    // che chiunque si aspetta e non va spiegato.
    entries.sort((a, b) {
      if (a['isDir'] != b['isDir']) return a['isDir'] ? -1 : 1;
      return (a['name'] as String)
          .toLowerCase()
          .compareTo((b['name'] as String).toLowerCase());
    });

    // ── Si DICE com'è ordinato ─────────────────────────────────────────
    //
    // L'elenco esce già in ordine, e la shell lo riordinava lo stesso: 55 ms
    // su quattromila voci, buttati, ogni volta che si apre una cartella.
    //
    // Non basta però che la shell «sappia» che qui si ordina per nome: sarebbe
    // un accordo scritto in due posti, e il giorno che uno dei due cambia si
    // rompe in silenzio — l'elenco esce in un ordine e viene mostrato in un
    // altro, senza nessun errore da nessuna parte. Quindi l'ordine si
    // DICHIARA nella risposta, e chi legge decide guardando questo campo.
    return {
      'path': path,
      'error': '',
      'entries': entries,
      'ordinatoPer': 'name',
      'ordinatoAlContrario': false,
      // ── Se questa cartella si può cambiare ──────────────────────────
      //
      // Giacomo, 18 agosto 2026: «se clicco su sistema posso cancellare
      // qualsiasi file di sistema come se fossero nella mia home, non c'è
      // nessuna protezione dalla cancellazione».
      //
      // Cancellare non si poteva — per togliere un file bisogna poter
      // scrivere nella cartella che lo contiene, e le cartelle di sistema
      // sono di root — ma **il programma non lo diceva in nessun modo**:
      // «Nuova cartella» e «Nuovo documento» a colori pieni, «Sposta nel
      // cestino» con la sua conferma tranquilla, e il rifiuto arrivava solo
      // dopo, come eccezione Dart. Da fuori è indistinguibile da un gestore
      // file che sta per farti fare un disastro.
      //
      // Si chiede al kernel con `test`, e non si calcola dai bit del modo:
      // il conto a mano ignora le ACL e i filesystem montati in sola lettura,
      // e sbagliare QUI vuol dire dire il falso proprio sulla cosa che si è
      // messa lì per rassicurare.
      'scrivibile': await _siPuoCambiare(path),
      // Viaggia con l'elenco e non con una domanda a parte: lo sfondo deve
      // essere già lì quando compaiono le icone, altrimenti si vede la
      // cartella cambiare colore mezzo secondo dopo essere stata aperta.
      'aspetto': aspetto(path),
    };
  }

  // ── Operazioni immediate ───────────────────────────────────────────────

  /// Un file vuoto. Stessa regola della cartella: se il nome è preso, si
  /// dice — non si scrive dentro un file che esiste, che sarebbe il modo più
  /// silenzioso di cancellarne il contenuto.
  Future<Map<String, dynamic>> creaFile(String path) async {
    try {
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        return {'ok': false, 'error': 'Esiste già qualcosa con questo nome'};
      }
      await File(path).create(recursive: false);
      return {'ok': true, 'error': ''};
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
  }

  /// Cancella per davvero: niente cestino, niente ritorno.
  ///
  /// Esiste perché il cestino non è sempre possibile — su un disco esterno
  /// senza `.Trash`, o quando serve liberare spazio ADESSO — e perché la
  /// scorciatoia Maiusc+Canc è quella che tutti conoscono. La conferma la
  /// chiede la shell, ed è l'unica finestra del gestore file che non si può
  /// saltare.
  Future<Map<String, dynamic>> eliminaDefinitivamente(List<String> percorsi) async {
    var fatti = 0;
    final errori = <String>[];
    for (final p in percorsi) {
      try {
        final tipo = await FileSystemEntity.type(p, followLinks: false);
        if (tipo == FileSystemEntityType.notFound) continue;

        // ── Si CHIEDE PRIMA, e qui non è pignoleria ──────────────────────
        //
        // `delete(recursive: true)` non è atomico: scende, cancella tutto
        // quello che riesce a cancellare, e solo alla fine fallisce sulla
        // cartella che non si lascia togliere. Misurato il 18 agosto 2026 su
        // una cartella dentro una `r-x`:
        //
        //     prima:  prot/dentro/dato.txt
        //     dopo:   prot/dentro/          ← vuota, e «operazione fallita»
        //
        // Cioè il contenuto distrutto e un messaggio che dice che non è
        // successo niente. È il peggiore dei difetti possibili in un gestore
        // file, ed è il motivo per cui questa riga sta PRIMA di ogni tocco.
        final genitore = p.contains(Platform.pathSeparator)
            ? p.substring(0, p.lastIndexOf(Platform.pathSeparator))
            : '.';
        if (!await _siPuoCambiare(genitore.isEmpty ? '/' : genitore)) {
          errori.add(motivo(p.split(Platform.pathSeparator).last,
              const FileSystemException('', '', OSError('', _eacces))));
          continue;
        }

        // ── I tre casi, e il terzo è quello che mancava ─────────────────
        //
        // Un COLLEGAMENTO a una cartella non è né una cartella né un file.
        // `File(p).delete()` su di lui solleva «Is a directory», e da fuori
        // il sintomo era: selezioni un collegamento, premi elimina, e non
        // succede niente con un messaggio che non spiega niente. Trovato il
        // 23 agosto 2026 dalla prova che verificava tutt'altro — che
        // cancellare un collegamento non cancellasse la cartella a cui punta.
        //
        // `Link.delete()` toglie il collegamento e **non segue il
        // bersaglio**, che è l'unica cosa che conta qui: seguirlo vorrebbe
        // dire cancellare una cartella che nessuno ha scelto.
        if (tipo == FileSystemEntityType.link) {
          await Link(p).delete();
        } else if (tipo == FileSystemEntityType.directory) {
          await Directory(p).delete(recursive: true);
        } else {
          await File(p).delete();
        }
        fatti++;
      } catch (e) {
        errori.add(motivo(p.split(Platform.pathSeparator).last, e));
      }
    }
    return {
      'ok': errori.isEmpty,
      'error': errori.join('\n'),
      'eliminati': fatti,
    };
  }

  Future<Map<String, dynamic>> makeDirectory(String path) async {
    try {
      // `Directory.create` non si lamenta se la cartella c'è già: torna
      // tranquillamente senza fare niente. Per Dart è ragionevole — «assicura
      // che esista» —, per un gestore file no: chi scrive un nome nella
      // finestrella «Nuova cartella» sta chiedendo una cartella NUOVA, e
      // rispondergli «fatto» senza averne creata nessuna gli fa credere che la
      // roba che ci metterà dentro andrà in un posto suo. Va invece detto che
      // quel nome è già preso.
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        return {'ok': false, 'error': 'Esiste già qualcosa con questo nome'};
      }
      await Directory(path).create(recursive: false);
      return {'ok': true, 'error': ''};
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> rename(String from, String to) async {
    try {
      if (await _sameEntry(from, to)) return {'ok': true, 'error': ''};
      LinuxFiles.renameNoReplace(from, to);
      return {'ok': true, 'error': ''};
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
  }

  /// Sposta nel cestino secondo la specifica freedesktop. Non cancella mai
  /// davvero: un gestore file che elimina senza rete è un gestore file che
  /// prima o poi fa un disastro.
  ///
  /// Chi non si lascia cestinare non ferma gli altri: con dieci file scelti e
  /// uno protetto, i nove vanno nel cestino e il decimo si dice per nome.
  /// Prima il primo intoppo interrompeva tutto il resto senza dirlo.
  Future<Map<String, dynamic>> trash(List<String> paths) async {
    final trashFiles = Directory(cartellaCestino);
    final trashInfo = Directory(_cartellaInfo);
    try {
      await trashFiles.create(recursive: true);
      await trashInfo.create(recursive: true);
    } catch (e) {
      return {'ok': false, 'error': 'Cestino non disponibile: $e'};
    }

    final rifiutati = <String>[];
    var cestinati = 0;

    for (final p in paths) {
      final name = p.split(Platform.pathSeparator).last;
      var target = '${trashFiles.path}/$name';
      var n = 1;
      while (await FileSystemEntity.type(target, followLinks: false) !=
          FileSystemEntityType.notFound) {
        target = '${trashFiles.path}/$name.$n';
        n++;
      }

      final stamp = DateTime.now().toIso8601String().split('.').first;
      final info = File('${trashInfo.path}/${target.split('/').last}.trashinfo');
      Directory? preparazione;
      var pubblicata = false;
      try {
        preparazione = LinuxFiles.privateTemp(trashInfo, '.minerva-info-');
        final pronta = File('${preparazione.path}/scheda');
        await pronta.writeAsString(
            '[Trash Info]\nPath=${_percorsoScappato(File(p).absolute.path)}\nDeletionDate=$stamp\n',
            flush: true);
        LinuxFiles.renameNoReplace(pronta.path, info.path);
        pubblicata = true;
        await _sposta(p, target);
        cestinati++;
      } catch (e) {
        rifiutati.add(motivo(name, e));
        // Se una copia cross-device è stata pubblicata prima di un errore
        // nella rimozione della sorgente, conservarne anche la scheda.
        if (pubblicata && await FileSystemEntity.type(target, followLinks: false) == FileSystemEntityType.notFound) {
          await _deletePathQuiet(info.path);
        }
      } finally {
        if (preparazione != null) await _deletePathQuiet(preparazione.path);
      }
    }

    return {
      'ok': rifiutati.isEmpty,
      'error': rifiutati.join('\n'),
      'cestinati': cestinati,
    };
  }

  /// Vero se dentro questa cartella si possono creare e togliere cose.
  ///
  /// Servono TUTTI E DUE i permessi: `w` per cambiare l'elenco, `x` per
  /// arrivare alle voci. Una cartella `r-x` si legge benissimo e non si tocca,
  /// ed è esattamente il caso di `/usr` e `/etc`.
  Future<bool> _siPuoCambiare(String path) async {
    try {
      final r = await Process.run('test', ['-w', path, '-a', '-x', path])
          .timeout(const Duration(seconds: 2));
      return r.exitCode == 0;
    } catch (_) {
      // Nel dubbio si dice di sì: l'alternativa è un gestore file che si
      // rifiuta di lavorare perché non è riuscito a lanciare `test`.
      return true;
    }
  }

  // ── Dettagli di un file ────────────────────────────────────────────────

  /// Tutto quello che c'è da sapere su un percorso.
  ///
  /// Si chiede a `stat`, non a `FileStat` di Dart, per una ragione sola ma
  /// decisiva: Dart dà i permessi come stringa (`rwxr-xr-x`) e NON dà il
  /// proprietario. Una finestra «Proprietà» senza il nome del proprietario e
  /// senza i permessi in ottale non serve a niente — sono le due cose per cui
  /// la si apre quando qualcosa non si lascia scrivere.
  Future<Map<String, dynamic>> info(String path) async {
    try {
      final r = await Process.run('stat', [
        '-c',
        '%F|%s|%a|%A|%U|%G|%u|%g|%h|%i|%X|%Y|%Z|%N',
        '--',
        path,
      ]);
      if (r.exitCode != 0) {
        return {'ok': false, 'error': (r.stderr as String).trim(), 'path': path};
      }
      final f = (r.stdout as String).trim().split('|');
      if (f.length < 14) {
        return {'ok': false, 'error': 'Risposta di stat illeggibile', 'path': path};
      }

      // `%N` è il nome fra virgolette, e per un collegamento diventa
      // `'link' -> 'bersaglio'`: è l'unico modo di sapere DOVE punta senza
      // una seconda chiamata.
      var linkTarget = '';
      final arrow = f[13].indexOf(' -> ');
      if (arrow >= 0) {
        linkTarget = f[13].substring(arrow + 4).replaceAll("'", '');
      }

      // `%F` di `stat` è TRADOTTO: con LANG italiano risponde «directory» ma
      // anche «file normale», «collegamento simbolico». Va benissimo da
      // mostrare, e non va usato per decidere niente — il tipo vero lo dice
      // Dart, che non parla nessuna lingua.
      final kind = await FileSystemEntity.type(path, followLinks: false);
      final resolved = await FileSystemEntity.type(path, followLinks: true);

      return {
        'ok': true,
        'error': '',
        'path': path,
        'name': path.split('/').last,
        'kind': f[0],
        'isDir': resolved == FileSystemEntityType.directory,
        'isLink': kind == FileSystemEntityType.link,
        'size': int.tryParse(f[1]) ?? 0,
        'mode': f[2],
        'modeString': f[3],
        'owner': f[4],
        'group': f[5],
        'uid': int.tryParse(f[6]) ?? -1,
        'gid': int.tryParse(f[7]) ?? -1,
        'links': int.tryParse(f[8]) ?? 1,
        'inode': f[9],
        'accessed': (int.tryParse(f[10]) ?? 0) * 1000,
        'modified': (int.tryParse(f[11]) ?? 0) * 1000,
        'changed': (int.tryParse(f[12]) ?? 0) * 1000,
        'linkTarget': linkTarget,
        // Le misure dell'immagine, lette dall'intestazione: zero quando il
        // file non è un'immagine o il formato non si riconosce.
        //
        // Servono ad Anteprima per decidere QUANTO IN GRANDE decodificare
        // prima di decodificare — vedi `image_dims.dart`. Viaggiano insieme al
        // resto perché `fs_info` viene già chiesto per ogni file mostrato, e
        // una seconda domanda sarebbe un secondo giro sul socket per sedici
        // byte già letti.
        ...(() {
          final d = resolved == FileSystemEntityType.file
              ? ImageDims.read(path)
              : null;
          return {
            'imageWidth': d?.width ?? 0,
            'imageHeight': d?.height ?? 0,
          };
        })(),
      };
    } catch (e) {
      return {'ok': false, 'error': '$e', 'path': path};
    }
  }

  /// Quanto occupa una cartella, contando dentro.
  ///
  /// È una domanda che può durare minuti su una cartella grande, quindi la
  /// finestra la fa a parte e la mostra quando arriva, invece di restare
  /// bianca ad aspettare. `du` esiste ovunque ed è più veloce di qualunque
  /// giro ricorsivo scritto qui.
  Future<Map<String, dynamic>> measure(String path) async {
    try {
      final r = await Process.run('du', ['-sb', '--', path]);
      if (r.exitCode != 0) {
        return {'ok': false, 'error': (r.stderr as String).trim(), 'path': path};
      }
      final out = (r.stdout as String).trim().split(RegExp(r'\s+'));
      return {
        'ok': true,
        'error': '',
        'path': path,
        'bytes': int.tryParse(out.first) ?? 0,
      };
    } catch (e) {
      return {'ok': false, 'error': '$e', 'path': path};
    }
  }

  /// Cambia i permessi. Il modo è in ottale (`644`, `755`).
  ///
  /// Ricorsivo solo se richiesto ESPLICITAMENTE, e mai come impostazione
  /// predefinita: un `chmod -R` partito per sbaglio su una cartella grande non
  /// si annulla, perché i permessi di prima non li sa più nessuno.
  Future<Map<String, dynamic>> chmod(String path, String mode,
      {bool recursive = false}) async {
    if (!RegExp(r'^[0-7]{3,4}$').hasMatch(mode)) {
      return {'ok': false, 'error': 'Permessi non validi: $mode'};
    }
    try {
      final args = <String>[if (recursive) '-R', mode, '--', path];
      final r = await Process.run('chmod', args);
      if (r.exitCode != 0) {
        return {'ok': false, 'error': (r.stderr as String).trim()};
      }
      return {'ok': true, 'error': '', 'path': path, 'mode': mode};
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
  }

  // ── Le cartelle di casa ────────────────────────────────────────────────

  /// Le cartelle personali, lette da `~/.config/user-dirs.dirs`.
  ///
  /// Erano scritte a mano nella barra laterale — «Documenti», «Immagini»,
  /// «Musica», «Scaricati» — e funzionavano su questa macchina perché è
  /// italiana. Su un sistema inglese quelle quattro cartelle non esistono e la
  /// barra laterale mostra quattro voci che non portano da nessuna parte;
  /// chi ha spostato i propri Documenti altrove sta anche peggio. Il file
  /// `user-dirs.dirs` è lo standard freedesktop che risponde a questa
  /// domanda, e lo scrivono tutti gli ambienti.
  Future<Map<String, dynamic>> places() async {
    final home = Platform.environment['HOME'] ?? '';
    // ── Quelle nella barra, e quelle che servono solo per l'icona ────────
    //
    // Scrivania, Pubblici e Modelli stanno nella cartella di casa come le
    // altre, e ogni tema di icone le disegna a parte. Scrivania nella barra
    // c'è — è il posto dove si trascina la roba più spesso, e mettercela è
    // la prima cosa che chiunque cerca. Pubblici e Modelli no: due voci in
    // più che quasi nessuno apre.
    //
    // Quindi si riportano tutte, e si dice quali vanno mostrate. Chi disegna
    // la barra filtra, chi sceglie le icone no.
    final wanted = {
      'XDG_DESKTOP_DIR': 'desktop',
      'XDG_DOCUMENTS_DIR': 'documents',
      'XDG_DOWNLOAD_DIR': 'downloads',
      'XDG_PICTURES_DIR': 'pictures',
      'XDG_MUSIC_DIR': 'music',
      'XDG_VIDEOS_DIR': 'videos',
      'XDG_PUBLICSHARE_DIR': 'publicshare',
      'XDG_TEMPLATES_DIR': 'templates',
    };
    const nellaBarra = {
      'desktop', 'documents', 'downloads', 'pictures', 'music', 'videos',
    };
    final found = <Map<String, dynamic>>[];

    final config = Platform.environment['XDG_CONFIG_HOME']?.isNotEmpty == true
        ? Platform.environment['XDG_CONFIG_HOME']!
        : '$home/.config';
    final file = File('$config/user-dirs.dirs');
    final resolved = <String, String>{};
    if (await file.exists()) {
      try {
        for (final raw in await file.readAsLines()) {
          final line = raw.trim();
          if (line.isEmpty || line.startsWith('#')) continue;
          final eq = line.indexOf('=');
          if (eq <= 0) continue;
          final key = line.substring(0, eq).trim();
          if (!wanted.containsKey(key)) continue;
          var value = line.substring(eq + 1).trim();
          if (value.startsWith('"') && value.endsWith('"')) {
            value = value.substring(1, value.length - 1);
          }
          value = value.replaceFirst(r'$HOME', home);
          resolved[key] = value;
        }
      } catch (_) {
        // File illeggibile: si va avanti con le sole cartelle di ripiego.
      }
    }

    for (final entry in wanted.entries) {
      final path = resolved[entry.key];
      if (path == null || path.isEmpty || path == home) continue;
      if (!await Directory(path).exists()) continue;
      found.add({
        'kind': entry.value,
        'path': path,
        'name': path.split('/').last,
        'nellaBarra': nellaBarra.contains(entry.value),
      });
    }

    // Il cestino in fondo, staccato dalle cartelle vere: non è un posto dove
    // si mette roba, è dove finisce quella tolta di mezzo. Compare sempre —
    // anche vuoto — perché è l'unico modo di scoprire che esiste, e perché
    // una voce che va e viene si cerca proprio quando non c'è.
    //
    // Con il campo `vuoto` chi disegna la colonna può abbassare la voce
    // quando dentro non c'è niente: un cestino spento è un cestino che non
    // ha bisogno di niente, e la voce resta lì come promemoria che esiste.
    var vuoto = true;
    try {
      final files = Directory(cartellaCestino);
      if (await files.exists()) {
        await for (final _ in files.list(followLinks: false)) {
          vuoto = false;
          break;
        }
      }
    } catch (_) {
      vuoto = true;
    }
    found.add({
      'kind': 'trash',
      'path': cartellaCestino,
      'name': 'Cestino',
      'nellaBarra': true,
      'vuoto': vuoto,
    });

    return {'home': home, 'places': found, 'error': ''};
  }

  // ── Il cestino ─────────────────────────────────────────────────────────
  //
  // `trash()` più sopra ci sposta dentro la roba secondo la specifica
  // freedesktop, e per un mese è stato tutto: non c'era modo di APRIRLO.
  // «Sposta nel cestino» senza un cestino da guardare è «elimina» detto con
  // parole gentili — e il senso di un cestino sta tutto nel poterci
  // ripescare dentro.
  //
  // Non serve una vista speciale: la cartella dei file è una cartella vera e
  // l'elenco normale la mostra. Servono le due azioni che una cartella
  // qualunque non ha — rimettere a posto, e svuotare.

  /// Il percorso come vuole la specifica: scappato come un indirizzo web.
  ///
  /// Non è pignoleria. Il file `.trashinfo` è **lo stesso formato che usano
  /// Dolphin e Nautilus**: se scrivessimo il percorso crudo, un file con un
  /// `%` nel nome cestinato da Minerva e ripescato da Dolphin tornerebbe con
  /// un nome diverso — e viceversa. Un cestino è utile solo se tutti quelli
  /// che ci guardano dentro leggono la stessa cosa.
  ///
  /// `encodeFull` lascia stare la barra (che qui è un separatore vero e non va
  /// toccata) ma si dimentica il cancelletto, che nei nomi di file capita.
  static String _percorsoScappato(String percorso) =>
      Uri.encodeFull(percorso).replaceAll('#', '%23');

  /// La radice del cestino: dentro ci stanno `files/` e `info/`.
  String get radiceCestino {
    if (cestinoDiProva != null) return cestinoDiProva!;
    final home = Platform.environment['HOME'] ?? '';
    final dati = Platform.environment['XDG_DATA_HOME']?.isNotEmpty == true
        ? Platform.environment['XDG_DATA_HOME']!
        : '$home/.local/share';
    return '$dati/Trash';
  }

  String get cartellaCestino => '$radiceCestino/files';
  String get _cartellaInfo => '$radiceCestino/info';

  /// Vero se `percorso` è dentro il cestino. Serve al gestore file per
  /// mostrare «Ripristina» solo lì.
  bool nelCestino(String percorso) {
    final c = cartellaCestino;
    return percorso == c || percorso.startsWith('$c/');
  }

  /// Rimette dove stavano gli elementi indicati.
  ///
  /// Dove stavano lo dice il file `.trashinfo` scritto al momento del
  /// cestinamento. Senza quello non si sa dove rimetterli: si dice, invece di
  /// scaricarli in una cartella a caso e lasciare a chi guarda il compito di
  /// capire cos'è successo.
  Future<Map<String, dynamic>> restoreFromTrash(List<String> paths) async {
    final info = Directory(_cartellaInfo);
    var rimessi = 0;
    final falliti = <String>[];

    for (final p in paths) {
      final nome = p.split('/').last;
      final scheda = File('${info.path}/$nome.trashinfo');

      String? origine;
      if (await scheda.exists()) {
        try {
          for (final riga in await scheda.readAsLines()) {
            if (riga.startsWith('Path=')) {
              origine = Uri.decodeFull(riga.substring(5).trim());
              break;
            }
          }
        } catch (_) {
          // scheda illeggibile: si tratta come se non ci fosse
        }
      }

      if (origine == null || origine.isEmpty) {
        falliti.add('$nome (non so da dove veniva)');
        continue;
      }

      // La cartella di partenza può non esistere più: si rifà, o il
      // ripristino fallirebbe per un motivo che non è colpa di nessuno.
      final genitore = origine.substring(0, origine.lastIndexOf('/'));
      try {
        await Directory(genitore).create(recursive: true);
      } catch (_) {
        falliti.add('$nome (non riesco a ricreare $genitore)');
        continue;
      }

      // Se al suo posto c'è già qualcos'altro non lo si sovrascrive: il
      // ripristino è un'operazione di recupero, e un recupero che cancella
      // è peggio del danno.
      var destinazione = origine;
      var n = 2;
      while (await FileSystemEntity.type(destinazione, followLinks: false) !=
          FileSystemEntityType.notFound) {
        destinazione = '$origine $n';
        n++;
      }

      // Stessa rete del cestinamento: si copia solo fra dischi diversi, e se
      // l'originale non si lascia togliere la copia si butta. Rimettere a
      // posto un file lasciandone una copia nel cestino vuol dire che al
      // prossimo «svuota» quello che si è appena salvato torna a sparire.
      try {
        await _sposta(p, destinazione);
      } catch (e) {
        falliti.add(motivo(nome, e));
        continue;
      }

      try {
        if (await scheda.exists()) await scheda.delete();
      } catch (_) {
        // La scheda orfana non fa danni: punta a un file che non c'è più.
      }
      rimessi++;
    }

    if (falliti.isEmpty) return {'ok': true, 'error': '', 'rimessi': rimessi};
    return {
      'ok': false,
      'error': 'Non sono riuscito a rimettere a posto: ${falliti.join('; ')}',
      'rimessi': rimessi,
    };
  }

  /// Svuota il cestino. Questa sì che cancella davvero.
  Future<Map<String, dynamic>> emptyTrash() async {
    final files = Directory(cartellaCestino);
    final info = Directory(_cartellaInfo);
    try {
      if (await files.exists()) {
        await for (final e in files.list(followLinks: false)) {
          await _deletePath(e.path);
        }
      }
      if (await info.exists()) {
        await for (final e in info.list(followLinks: false)) {
          // `_deletePath` e non `File.delete()`: nel cestino può finirci un
          // collegamento, e su un collegamento a una cartella `File.delete()`
          // solleva. Uno solo così bloccava lo svuotamento di TUTTO il resto.
          await _deletePath(e.path);
        }
      }
      return {'ok': true, 'error': ''};
    } catch (e) {
      return {'ok': false, 'error': 'Non riesco a svuotare il cestino: $e'};
    }
  }

  // ── Dischi e chiavette ─────────────────────────────────────────────────

  /// I dischi che si possono aprire dalla barra laterale.
  ///
  /// Si legge `lsblk`, che conosce anche ciò che è collegato ma NON montato —
  /// ed è il caso che conta: una chiavetta appena infilata non compare in
  /// `/proc/mounts`, e una barra laterale che mostra solo ciò che è già
  /// montato è una barra laterale che non serve a montare niente.
  ///
  /// Si scartano le partizioni di sistema (`/`, `/boot`, la swap): non sono
  /// posti dove si va a mettere roba, e mostrarle vuol dire offrire a
  /// chiunque il pulsante «smonta» sul disco da cui sta girando tutto.
  Future<Map<String, dynamic>> volumes() async {
    try {
      final r = await Process.run('lsblk', [
        '-J',
        '-o',
        'NAME,PATH,LABEL,MOUNTPOINTS,FSTYPE,SIZE,RM,HOTPLUG,TYPE,VENDOR,MODEL',
      ]);
      if (r.exitCode != 0) {
        return {'volumes': [], 'error': (r.stderr as String).trim()};
      }
      final found = <Map<String, dynamic>>[];
      _walkBlockDevices(_decode(r.stdout as String), found, await _rootDevice());
      return {'volumes': found, 'error': ''};
    } catch (e) {
      return {'volumes': [], 'error': '$e'};
    }
  }

  List<dynamic> _decode(String json) {
    try {
      final map = jsonDecode(json);
      final list = map['blockdevices'];
      return list is List ? list : [];
    } catch (_) {
      return [];
    }
  }

  /// Il disco su cui gira il sistema.
  ///
  /// `findmnt` risponde `/dev/nvme0n1p2[/@]` su btrfs: la parte fra parentesi
  /// quadre è il sottovolume, e va tolta per confrontare con `lsblk`.
  Future<String> _rootDevice() async {
    try {
      final r = await Process.run('findmnt', ['-no', 'SOURCE', '/']);
      if (r.exitCode != 0) return '';
      var s = (r.stdout as String).trim();
      final bracket = s.indexOf('[');
      if (bracket > 0) s = s.substring(0, bracket);
      return s;
    } catch (_) {
      return '';
    }
  }

  static const Set<String> _systemMounts = {'/', '/boot', '/boot/efi', '[SWAP]'};

  /// Le cartelle sotto cui un punto di montaggio è roba di sistema.
  static const List<String> _systemTrees = ['/boot', '/efi', '/usr', '/var',
                                            '/etc', '/nix', '/run', '/sys'];

  /// Dove finisce quello che monti TU. Sta a parte perché `/run/media` è
  /// dentro `/run`, che è un albero di sistema: senza questa eccezione una
  /// chiavetta USB sparirebbe dall'elenco.
  static const List<String> _postiTuoi = ['/run/media/', '/media/', '/mnt/'];

  static bool _montaggioDiSistema(String m) {
    for (final p in _postiTuoi) {
      if (m.startsWith(p)) return false;
    }
    if (_systemMounts.contains(m)) return true;
    return _systemTrees.any((t) => m == t || m.startsWith('$t/'));
  }

  /// I volumi che si mostrano, dato l'albero che stampa `lsblk --json`.
  ///
  /// Pubblica per una ragione sola: **provare il filtro senza avere quei
  /// dischi.** La regola su chi è un dispositivo e chi è il computer è la
  /// parte di questo file che si è rotta più volte — il disco di sistema fra
  /// le chiavette, i loop di waydroid fra i dischi — e ogni volta il difetto
  /// si è visto su una macchina sola. Con un albero finto si prova la regola
  /// e non il computer.
  List<Map<String, dynamic>> volumiDa(List<dynamic> nodes, String rootDevice) {
    final fuori = <Map<String, dynamic>>[];
    _walkBlockDevices(nodes, fuori, rootDevice);
    return fuori;
  }

  void _walkBlockDevices(List<dynamic> nodes, List<Map<String, dynamic>> out,
      String rootDevice) {
    for (final node in nodes) {
      if (node is! Map) continue;
      final children = node['children'];
      if (children is List) _walkBlockDevices(children, out, rootDevice);

      final type = '${node['type'] ?? ''}';
      final fstype = '${node['fstype'] ?? ''}';
      // `loop` c'è perché un'immagine ISO o un file .img aperti sono, per chi
      // guarda, un disco in più: si aprono e si espellono come una chiavetta.
      if (type != 'part' && type != 'disk' && type != 'crypt' &&
          type != 'loop') {
        continue;
      }
      // Senza filesystem non c'è niente da aprire; un disco intero che ha
      // partizioni è già rappresentato dalle sue partizioni.
      if (fstype.isEmpty || fstype == 'swap') continue;
      // I pacchetti Snap e AppImage montano una decina di squashfs a testa.
      // Sono programmi installati, non dischi da sfogliare.
      if (type == 'loop' && fstype == 'squashfs') continue;

      final path = '${node['path'] ?? ''}';
      // Un'immagine aperta si stacca come una chiavetta anche se il kernel non
      // la dichiara staccabile: `rm` e `hotplug` sono falsi su un loop.
      final removable =
          node['rm'] == true || node['hotplug'] == true || type == 'loop';

      // ── QUALE DISCO NON È UN «DISPOSITIVO» ────────────────────────────
      //
      // Il disco di sistema compariva nella colonna come «nvme0n1p2,
      // /var/tmp». Due errori in una riga sola: non è una chiavetta da
      // aprire e staccare, e `/var/tmp` non è nemmeno dove sta montato — è
      // uno dei tanti punti in cui btrfs monta i suoi sottovolumi, e
      // `lsblk` ne stampava uno a caso.
      //
      // Si guardano quindi TUTTI i punti di montaggio (`mountpoints`, non
      // `mountpoint`) e si chiede a `findmnt` qual è il disco della radice.
      // Un disco interno non staccabile che regge il sistema non è un
      // dispositivo: è il computer.
      final mounts = <String>[];
      final raw = node['mountpoints'];
      if (raw is List) {
        for (final m in raw) {
          if (m == null) continue;
          final s = '$m';
          if (s.isNotEmpty) mounts.add(s);
        }
      }

      if (!removable) {
        if (path.isNotEmpty && path == rootDevice) continue;
        if (mounts.any(_montaggioDiSistema)) continue;
      }

      // ── I loop che non sono dischi ─────────────────────────────────────
      //
      // Un `loop` è staccabile per costruzione (vedi sopra), e questo lo
      // faceva passare oltre il filtro di sistema. Risultato, il 23 agosto
      // 2026: nella colonna «Dispositivi» comparivano «/» e «vendor», che
      // erano i due loop di **waydroid** montati su
      // `/var/lib/waydroid/rootfs` e `.../vendor`. Premendo espelli,
      // UDisks rispondeva «Not authorized» — giustamente, perché non sono
      // roba tua da staccare.
      //
      // La regola: un'immagine che hai aperto tu finisce in `/run/media`,
      // `/media` o `/mnt`. Un loop montato dentro l'albero di sistema è
      // infrastruttura — waydroid, i contenitori, l'immagine di ripristino —
      // e non è un disco da sfogliare.
      if (type == 'loop' &&
          mounts.isNotEmpty &&
          mounts.every(_montaggioDiSistema)) {
        continue;
      }

      // Fra i molti punti di montaggio si mostra quello che serve ad aprirlo:
      // il più corto, che è la radice del volume e non un suo ramo.
      var mount = '';
      for (final m in mounts) {
        if (m.startsWith('[')) continue;
        if (mount.isEmpty || m.length < mount.length) mount = m;
      }

      final label = '${node['label'] ?? ''}';
      final vendor = '${node['vendor'] ?? ''}'.trim();
      final model = '${node['model'] ?? ''}'.trim();
      final fallback = [vendor, model].where((s) => s.isNotEmpty).join(' ');

      out.add({
        'name': label.isNotEmpty
            ? label
            : (fallback.isNotEmpty ? fallback : '${node['name'] ?? ''}'),
        'device': path,
        'mountPoint': mount,
        'mounted': mount.isNotEmpty,
        'fsType': fstype,
        'size': '${node['size'] ?? ''}',
        'removable': removable,
      });
    }
  }

  /// Da un errore di `udisksctl` a una frase che si legge.
  ///
  /// Quello che arriva è, per esteso: «Error unmounting /dev/loop1:
  /// GDBus.Error:org.freedesktop.UDisks2.Error.NotAuthorized: Not authorized
  /// to perform operation». Su una barra rossa in fondo al gestore file,
  /// questa riga dice a chi la legge tre cose che non gli servono (che
  /// esistono GDBus, org.freedesktop e UDisks2) e nasconde l'unica che gli
  /// serve: **non era roba sua da staccare**.
  ///
  /// Non si traduce con una tabella di stringhe: si riconoscono i pochi casi
  /// che capitano davvero, e per tutti gli altri si tiene la frase originale
  /// senza il guscio tecnico — meglio una frase in inglese che una frase in
  /// italiano inventata da noi che dice un'altra cosa.
  /// Pubblica per poterla provare: le frasi che vede chi usa il programma
  /// sono un prodotto quanto il resto.
  static String errorePulito(String grezzo) {
    final m = grezzo.trim();
    if (m.isEmpty) return 'Non è andata.';

    if (m.contains('NotAuthorized')) {
      return 'Questo disco non è tuo da staccare: lo tiene il sistema.';
    }
    if (m.contains('DeviceBusy') || m.contains('target is busy')) {
      return 'Il disco è in uso: chiudi i programmi che lo stanno leggendo '
          'e riprova.';
    }
    if (m.contains('AlreadyUnmounting')) return 'Lo sto già staccando.';
    if (m.contains('NotMounted')) return 'Non risulta montato.';
    if (m.contains('AlreadyMounted')) return 'È già montato.';

    // Il guscio: «Error <verbo> <dispositivo>: GDBus.Error:org.…Error.<Nome>:»
    // davanti alla frase vera.
    final i = m.lastIndexOf(': ');
    if (m.contains('GDBus.Error') && i > 0 && i + 2 < m.length) {
      return m.substring(i + 2).trim();
    }
    return m;
  }

  /// Monta e smonta con `udisksctl`, che chiede i permessi a polkit e non
  /// pretende di essere amministratore: montare una chiavetta dal proprio
  /// utente è una cosa normale, e chiedere la password per farlo è il segno
  /// che si sta usando lo strumento sbagliato.
  Future<Map<String, dynamic>> mountVolume(String device) async {
    return _udisks(['mount', '-b', device]);
  }

  Future<Map<String, dynamic>> unmountVolume(String device) async {
    return _udisks(['unmount', '-b', device]);
  }

  // ── Formattare ─────────────────────────────────────────────────────────
  //
  // È l'unica operazione di tutto Minerva che distrugge dati senza rete: non
  // c'è un cestino da cui ripescare una chiavetta formattata. Quindi qui
  // dentro non ci si fida di niente che arrivi da fuori — nemmeno della
  // nostra interfaccia.
  //
  // ── I TRE MURI, in ordine ───────────────────────────────────────────────
  //
  // 1. **Deve essere fra i volumi che mostriamo.** L'elenco si rilegge adesso,
  //    non si usa quello che aveva in mano chi ha chiesto: fra il momento in
  //    cui ha visto la finestra e il momento in cui ha premuto «Formatta», una
  //    chiavetta può essere stata staccata e `/dev/sdb1` può essere diventato
  //    un altro disco.
  // 2. **Deve essere STACCABILE.** `rm` o `hotplug` veri. Un disco interno non
  //    si formatta da qui, punto: non è una funzione che manca, è una funzione
  //    che non deve esserci in un gestore file.
  // 3. **UDisks deve essere d'accordo.** `HintSystem` è il giudizio che dà il
  //    sistema stesso su «questo è hardware di sistema». È un parere che non
  //    viene da noi, ed è per questo che vale: sbagliare i primi due controlli
  //    è un errore nostro, sbagliarli tutti e tre è molto più difficile.
  //
  // ── Perché UDisks e non `mkfs` ─────────────────────────────────────────
  //
  // Perché `mkfs` vuole essere amministratore, e per arrivarci servirebbe uno
  // script sotto `pkexec` che accetta un percorso di dispositivo — cioè
  // esattamente il genere di cosa che, se sbagliata, formatta il disco di
  // sistema. UDisks fa la stessa cosa passando da polkit, applica i PROPRI
  // controlli, e sa anche cancellare le firme del filesystem vecchio: senza,
  // una chiavetta riformattata continua a farsi riconoscere per quello che
  // era prima.

  /// I filesystem che si possono davvero creare su questa macchina.
  ///
  /// Non un elenco scritto a mano: lo si chiede a UDisks, che risponde anche
  /// QUALE programma manca quando non si può. Un elenco fisso mostrerebbe
  /// «NTFS» su una macchina senza `mkfs.ntfs`, e chi lo sceglie scoprirebbe
  /// che non funziona solo dopo aver confermato di cancellare tutto.
  Future<Map<String, dynamic>> formatiDisponibili() async {
    const candidati = [
      {'id': 'vfat', 'nome': 'FAT32', 'nota': 'Lo leggono tutti: Windows, Mac, televisori, autoradio'},
      {'id': 'exfat', 'nome': 'exFAT', 'nota': 'Come FAT32 ma senza il limite dei 4 GB per file'},
      {'id': 'ext4', 'nome': 'ext4', 'nota': 'Solo Linux. Tiene i permessi dei file'},
      {'id': 'ntfs', 'nome': 'NTFS', 'nota': 'Quello di Windows'},
      {'id': 'btrfs', 'nome': 'Btrfs', 'nota': 'Solo Linux, con le istantanee'},
    ];

    final fuori = <Map<String, dynamic>>[];
    for (final c in candidati) {
      final r = await Process.run('busctl', [
        '--system', 'call', 'org.freedesktop.UDisks2',
        '/org/freedesktop/UDisks2/Manager',
        'org.freedesktop.UDisks2.Manager', 'CanFormat', 's', c['id']!,
      ]);
      if (r.exitCode != 0) continue;
      // La risposta è `(bs) true ""` oppure `(bs) false "mkfs.ntfs"`.
      final testo = '${r.stdout}'.trim();
      final si = testo.contains(' true ');
      final manca = RegExp(r'"([^"]*)"').firstMatch(testo)?.group(1) ?? '';
      fuori.add({
        'id': c['id'],
        'nome': c['nome'],
        'nota': c['nota'],
        'possibile': si,
        'manca': si ? '' : manca,
      });
    }
    return {'formati': fuori, 'error': ''};
  }

  /// Cancella tutto quello che c'è sul volume e ci mette un filesystem nuovo.
  Future<Map<String, dynamic>> formatVolume(
      String device, String filesystem, String etichetta) async {
    // ── Muro 1: lo conosciamo? ──
    final elenco = await volumes();
    Map<String, dynamic>? voce;
    for (final v in (elenco['volumes'] as List)) {
      if (v is Map<String, dynamic> && v['device'] == device) voce = v;
    }
    if (voce == null) {
      return {
        'ok': false,
        'error': 'Non trovo più «$device». Forse è stato staccato: '
            'ricontrolla l\'elenco dei dischi prima di riprovare.'
      };
    }

    // ── Muro 2: è staccabile? ──
    if (voce['removable'] != true) {
      return {
        'ok': false,
        'error': 'Minerva formatta solo i dischi staccabili. '
            '«$device» è un disco interno.'
      };
    }

    // ── Muro 3: cosa ne dice UDisks? ──
    final oggetto = await _oggettoUdisks(device);
    if (oggetto == null) {
      return {'ok': false, 'error': 'UDisks non conosce «$device».'};
    }
    if (await _diSistema(oggetto)) {
      return {
        'ok': false,
        'error': 'Il sistema segnala «$device» come disco di sistema. '
            'Non lo formatto.'
      };
    }

    // Smontare prima: UDisks rifiuta di formattare un volume montato, e il
    // messaggio che dà in quel caso non spiega niente a chi legge.
    if (voce['mounted'] == true) {
      final u = await unmountVolume(device);
      if (u['ok'] != true) {
        return {
          'ok': false,
          'error': 'Non riesco a smontarlo prima di formattarlo: '
              '${u['error']}\nProbabilmente c\'è un programma che lo sta usando.'
        };
      }
    }

    // ── L'operazione ──
    //
    // `take-ownership` solo dove ha senso: su FAT ed exFAT i permessi non
    // esistono, e passarlo lì fa fallire la chiamata. Su ext4 e btrfs invece
    // serve, o la chiavetta appena formattata risulta di `root` e chi l'ha
    // formattata non può scriverci — che è il modo più assurdo di finire
    // un'operazione riuscita.
    final conProprietario = filesystem == 'ext4' || filesystem == 'btrfs';
    final opzioni = <String>[];
    var quante = 0;
    if (etichetta.trim().isNotEmpty) {
      opzioni.addAll(['label', 's', etichetta.trim()]);
      quante++;
    }
    if (conProprietario) {
      opzioni.addAll(['take-ownership', 'b', 'true']);
      quante++;
    }

    final r = await Process.run('busctl', [
      '--system', 'call', 'org.freedesktop.UDisks2', oggetto,
      'org.freedesktop.UDisks2.Block', 'Format', 'sa{sv}',
      filesystem, '$quante', ...opzioni,
    ]);

    if (r.exitCode != 0) {
      var messaggio = '${r.stderr}'.trim();
      if (messaggio.contains('NotAuthorized')) {
        messaggio = 'Autorizzazione negata.';
      }
      return {
        'ok': false,
        'error': messaggio.isEmpty ? 'La formattazione non è riuscita.' : messaggio
      };
    }

    // Rimontarlo: una chiavetta appena formattata che resta smontata sembra
    // sparita, e chi guarda pensa che l'operazione l'abbia rotta.
    final m = await mountVolume(device);
    return {
      'ok': true,
      'error': '',
      'mountPoint': m['mountPoint'] ?? '',
    };
  }

  /// Il percorso dell'oggetto D-Bus di un dispositivo.
  ///
  /// Si chiede a UDisks invece di costruirlo da `/dev/sdb1` → `…/sdb1`:
  /// i nomi con caratteri strani vengono trasformati (`dm-0` diventa
  /// `dm_2d0`), e una regola scritta a mano sbaglia proprio nei casi rari.
  Future<String?> _oggettoUdisks(String device) async {
    try {
      final r = await Process.run('busctl', [
        '--system', 'call', 'org.freedesktop.UDisks2',
        '/org/freedesktop/UDisks2/Manager',
        'org.freedesktop.UDisks2.Manager', 'ResolveDevice', 'a{sv}a{sv}',
        '1', 'path', 's', device, '0',
      ]);
      if (r.exitCode != 0) return null;
      // Risposta: `ao 1 "/org/freedesktop/UDisks2/block_devices/sdb1"`.
      final m = RegExp(r'"([^"]+)"').firstMatch('${r.stdout}');
      return m?.group(1);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _diSistema(String oggetto) async {
    try {
      final r = await Process.run('busctl', [
        '--system', 'get-property', 'org.freedesktop.UDisks2', oggetto,
        'org.freedesktop.UDisks2.Block', 'HintSystem',
      ]);
      // Se non si riesce a chiedere si risponde SÌ: davanti a un dubbio su
      // «è il disco di sistema?», l'unica risposta prudente è fermarsi.
      if (r.exitCode != 0) return true;
      if (!'${r.stdout}'.contains('true')) return false;

      // ── L'unica eccezione, e perché è sicura ────────────────────────────
      //
      // UDisks dice `HintSystem = true` anche per i dispositivi **loop**, cioè
      // per un file `.img` o una ISO aperti come se fossero un disco. Lo fa
      // perché quel dispositivo non appartiene a nessun `Drive`, non perché
      // sia hardware di sistema — verificato: su questa macchina un file da
      // 64 MB appena aperto risulta «di sistema».
      //
      // Rifiutarli tutti sarebbe incoerente: nella colonna dei dischi li
      // mostriamo apposta come dispositivi che si aprono e si staccano. E
      // sarebbe anche l'unico modo per cui questa funzione non si può provare
      // senza mettere in gioco una chiavetta vera.
      //
      // L'eccezione è stretta quanto basta: **un loop che ha aperto QUESTO
      // utente**. `SetupByUID` è il numero di chi l'ha creato, e lo tiene
      // UDisks, non noi. Un file aperto da me è roba mia per definizione; un
      // loop di sistema (una immagine montata dall'avvio) ha un altro
      // proprietario e resta rifiutato.
      final l = await Process.run('busctl', [
        '--system', 'get-property', 'org.freedesktop.UDisks2', oggetto,
        'org.freedesktop.UDisks2.Loop', 'SetupByUID',
      ]);
      if (l.exitCode != 0) return true;   // non è un loop: resta «di sistema»
      final chi = RegExp(r'(\d+)').firstMatch('${l.stdout}')?.group(1);
      final io = _uidCorrente();
      if (chi == null || io == null) return true;
      return chi != io;
    } catch (_) {
      return true;
    }
  }

  String? _uidCorrente() {
    try {
      final r = Process.runSync('id', ['-u']);
      if (r.exitCode != 0) return null;
      final s = '${r.stdout}'.trim();
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _udisks(List<String> args) async {
    try {
      final r = await Process.run('udisksctl', args);
      if (r.exitCode != 0) {
        return {'ok': false, 'error': errorePulito((r.stderr as String))};
      }
      // `udisksctl mount` stampa «Mounted /dev/sdb1 at /run/media/...»: il
      // punto di mount serve per andarci subito dopo.
      final out = (r.stdout as String).trim();
      final at = out.lastIndexOf(' at ');
      return {
        'ok': true,
        'error': '',
        'mountPoint': at >= 0 ? out.substring(at + 4).replaceAll('.', '') : '',
      };
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
  }

  // ── Trasferimenti ──────────────────────────────────────────────────────

  /// Avvia una copia o uno spostamento e restituisce l'identificativo del
  /// lavoro. Il conteggio dei byte totali viene fatto prima di cominciare,
  /// così la barra di avanzamento è veritiera dal primo istante invece di
  /// riempirsi e allungarsi mentre si scoprono nuovi file.
  /// I nomi che in `destinazione` esistono già. Si chiede PRIMA di iniziare:
  /// una domanda a metà copia, con la barra di avanzamento che corre, è una
  /// domanda a cui si risponde male.
  List<String> conflitti(List<String> sorgenti, String destinazione) {
    final fuori = <String>[];
    for (final s in sorgenti) {
      final nome = s.split(Platform.pathSeparator).last;
      final voluto = '$destinazione/$nome';
      // Un file non è in conflitto con sé stesso: capita trascinando dentro
      // la cartella in cui si è già.
      if (voluto == s) continue;
      if (FileSystemEntity.typeSync(voluto, followLinks: false) != FileSystemEntityType.notFound) {
        fuori.add(nome);
      }
    }
    return fuori;
  }

  Future<String> startTransfer({
    required List<String> sources,
    required String destination,
    required bool move,
    String conflitto = 'entrambi',
  }) async {
    final id = 'job${++_counter}';
    final job = TransferJob(
      id: id,
      sources: sources,
      destination: destination,
      move: move,
      conflitto: conflitto,
    );
    _jobs[id] = job;

    // Non si attende: il lavoro procede in sottofondo e si annuncia da solo.
    unawaited(_run(job));
    return id;
  }

  void pause(String id) {
    final j = _jobs[id];
    if (j == null || j.state != 'running') return;
    j.state = 'paused';
    _emit(j);
  }

  void resume(String id) {
    final j = _jobs[id];
    if (j == null || j.state != 'paused') return;
    j.state = 'running';
    j.resumeSignal?.complete();
    j.resumeSignal = null;
    _emit(j);
  }

  void cancel(String id) {
    final j = _jobs[id];
    if (j == null || j.isFinished) return;
    j.state = 'cancelling';
    // Un lavoro in pausa è fermo dentro l'attesa: va svegliato, altrimenti
    // l'annullamento non ha effetto finché qualcuno non preme «riprendi».
    j.resumeSignal?.complete();
    j.resumeSignal = null;
    _emit(j);
  }

  /// Solo i lavori ancora vivi. Un gestore file appena aperto non deve
  /// ereditare l'elenco di tutto ciò che è stato copiato dall'accensione:
  /// quelli conclusi li ha già visti chi era lì quando sono finiti.
  List<Map<String, dynamic>> jobsJson() => _jobs.values
      .where((j) => !j.isFinished)
      .map((j) => j.toJson())
      .toList();

  /// Toglie dalla memoria i lavori conclusi da un po'. Senza questo la mappa
  /// cresce per tutta la durata della sessione.
  void _prune() {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 2));
    _jobs.removeWhere((_, j) =>
        j.isFinished && j.finishedAt != null && j.finishedAt!.isBefore(cutoff));
  }

  void _emit(TransferJob j) {
    if (!_progress.isClosed) _progress.add(j.toJson());
  }

  Future<void> _run(TransferJob job) async {
    Directory? staging;
    try {
      if (!['entrambi', 'salta', 'sostituisci'].contains(job.conflitto)) {
        throw const FileSystemException('Politica di conflitto non valida');
      }
      final destination = await Directory(job.destination).resolveSymbolicLinks();
      // Validare TUTTO il lotto prima di misurare o creare copie.
      for (final s in job.sources) {
        if (await FileSystemEntity.type(s, followLinks: false) == FileSystemEntityType.directory) {
          final source = await Directory(s).resolveSymbolicLinks();
          if (destination == source || destination.startsWith('$source/')) {
            throw FileSystemException('Non si può copiare una cartella dentro sé stessa', s);
          }
        }
      }
      // 1. Quanto c'è da spostare
      for (final s in job.sources) {
        job.bytesTotal += await _measure(s);
      }
      _emit(job);

      // 2. Trasferimento
      for (final s in job.sources) {
        if (job.state == 'cancelling') break;
        final name = s.split(Platform.pathSeparator).last;
        if (name.isEmpty || name == '.' || name == '..') {
          throw FileSystemException('Nome sorgente non valido', s);
        }
        final voluto = '$destination/$name';
        if (await _sameEntry(s, voluto)) continue;
        final occupato =
            FileSystemEntity.typeSync(voluto, followLinks: false) != FileSystemEntityType.notFound;

        if (occupato && job.conflitto == 'salta') {
          job.currentFile = name;
          _emit(job);
          continue;
        }
        final target = job.conflitto == 'entrambi'
            ? _uniqueTarget(voluto)
            : voluto;

        if (job.move && !(occupato && job.conflitto == 'sostituisci')) {
          // Sullo stesso filesystem lo spostamento è istantaneo: non c'è
          // niente da copiare, solo un nome da cambiare.
          try {
            LinuxFiles.renameNoReplace(s, target);
            job.bytesDone += await _measureQuiet(target);
            job.currentFile = name;
            _emit(job);
            continue;
          } catch (e) {
            // Si prosegue copiando SOLO se i due posti sono su dischi
            // diversi. Per ogni altro motivo — e su un file di sistema il
            // motivo è sempre lo stesso, i permessi — copiare vorrebbe dire
            // finire con il file in due posti e chiamarlo «spostato».
            if (_codiceErrore(e) != _exdev) {
              throw FileSystemException(motivo(name, e), s);
            }
          }
        }

        // Directory temporanea privata sul filesystem di destinazione.
        // Nessun contenuto parziale è pubblicato sotto il nome definitivo.
        staging = LinuxFiles.privateTemp(Directory(destination), '.minerva-transfer-');
        final prepared = '${staging.path}/contenuto';
        await _copyTree(s, prepared, job);
        if (job.state == 'cancelling') break;
        if (occupato && job.conflitto == 'sostituisci') {
          LinuxFiles.exchange(prepared, target);
        } else {
          LinuxFiles.renameNoReplace(prepared, target);
        }
        // Da qui target è una copia COMPLETA: non eliminarla mai nel rollback,
        // nemmeno se la successiva rimozione della sorgente fallisce a metà.
        await _deletePathQuiet(staging.path);
        staging = null;
        if (job.move) {
          try {
            await _deletePath(s);
          } catch (e) {
            throw FileSystemException('Copia completa conservata in $target; '
                'rimozione della sorgente incompleta: ${motivo(name, e)}', s);
          }
        }
      }

      if (job.state == 'cancelling') {
        // Solo lo staging corrente è parziale. I file già pubblicati restano.
        job.state = 'cancelled';
      } else {
        job.state = 'done';
        job.bytesDone = job.bytesTotal;
      }
    } catch (e) {
      job.state = 'failed';
      // `motivo` è già stato applicato dove si sapeva di quale file si
      // trattava; qui si toglie solo l'involucro dell'eccezione.
      job.error = e is FileSystemException ? e.message : '$e';
    } finally {
      if (staging != null) await _deletePathQuiet(staging.path);
    }

    job.finishedAt = DateTime.now();
    _emit(job);
    _prune();
  }

  Future<int> _measure(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.file) {
      return (await File(path).stat()).size;
    }
    if (type != FileSystemEntityType.directory) return 0;

    var total = 0;
    try {
      await for (final e in Directory(path).list(recursive: true, followLinks: false)) {
        if (e is File) {
          try {
            total += (await e.stat()).size;
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  Future<int> _measureQuiet(String path) async {
    try {
      return await _measure(path);
    } catch (_) {
      return 0;
    }
  }

  String _uniqueTarget(String wanted) {
    var target = wanted;
    var n = 1;
    while (FileSystemEntity.typeSync(target, followLinks: false) != FileSystemEntityType.notFound) {
      final dot = wanted.lastIndexOf('.');
      final slash = wanted.lastIndexOf(Platform.pathSeparator);
      if (dot > slash + 1) {
        target = '${wanted.substring(0, dot)} ($n)${wanted.substring(dot)}';
      } else {
        target = '$wanted ($n)';
      }
      n++;
    }
    return target;
  }

  /// Copia ricorsiva, un blocco alla volta. È il cuore della pausa: fra un
  /// blocco e l'altro si controlla lo stato del lavoro, e se è in pausa ci si
  /// ferma lì finché non arriva «riprendi».
  Future<void> _copyTree(String from, String to, TransferJob? job) async {
    final type = await FileSystemEntity.type(from, followLinks: false);

    if (type == FileSystemEntityType.directory) {
      await Directory(to).create(recursive: true);
      await for (final e in Directory(from).list(followLinks: false)) {
        if (job?.state == 'cancelling') return;
        final name = e.path.split(Platform.pathSeparator).last;
        await _copyTree(e.path, '$to/$name', job);
      }
      await _copyMode(from, to);
      return;
    }

    if (type == FileSystemEntityType.link) {
      final target = await Link(from).target();
      await Link(to).create(target);
      return;
    }

    if (type != FileSystemEntityType.file) {
      throw FileSystemException('Sorgente assente o tipo non supportato', from);
    }

    final src = File(from);
    final dst = File(to);
    job?.currentFile = from.split(Platform.pathSeparator).last;

    final input = src.openRead();
    final output = await dst.open(mode: FileMode.write);
    try {
      await for (final chunk in input) {
        if (job != null) {
          if (job.state == 'cancelling') break;
          await job.waitIfPaused();
          if (job.state == 'cancelling') break;
        }
        await output.writeFrom(chunk);
        if (job != null) {
          job.bytesDone += chunk.length;
          // Si annuncia ogni 64 blocchi circa: notificare a ogni blocco
          // riempirebbe il socket di messaggi che nessuno riesce a disegnare.
          job.sinceEmit += chunk.length;
          if (job.sinceEmit > 2 * 1024 * 1024) {
            job.sinceEmit = 0;
            _emit(job);
          }
        }
      }
      await output.flush();
    } finally {
      await output.close();
    }

    await _copyMode(from, to);
  }

  Future<void> _copyMode(String from, String to) async {
    final st = await FileStat.stat(from);
    final octal = (st.mode & 0x1FF).toRadixString(8).padLeft(3, '0');
    final r = await Process.run('chmod', [octal, '--', to])
        .timeout(const Duration(seconds: 2));
    if (r.exitCode != 0) throw FileSystemException('Permessi non conservati: ${r.stderr}', to);
  }

  Future<bool> _sameEntry(String from, String to) async {
    // Risolve i genitori ma NON il symlink finale: spostiamo il link stesso.
    final a = File(from).absolute;
    final b = File(to).absolute;
    final ap = await a.parent.resolveSymbolicLinks();
    final bp = await b.parent.resolveSymbolicLinks();
    if ('$ap/${a.uri.pathSegments.last}' == '$bp/${b.uri.pathSegments.last}') return true;
    if (await FileSystemEntity.type(from, followLinks: false) == FileSystemEntityType.file &&
        await FileSystemEntity.type(to, followLinks: false) == FileSystemEntityType.file) {
      return FileSystemEntity.identical(from, to);
    }
    return false;
  }

  // ── Perché un «sposta» non è riuscito ──────────────────────────────────
  //
  // Sono quattro cose diverse e il codice di prima le trattava come una sola:
  // `catch (_)` e poi «filesystem diverso: si copia e si cancella». Ma un
  // `rename` fallisce quasi sempre per un altro motivo, e su un file di
  // sistema fallisce SEMPRE per questo: la cartella che lo contiene non è tua.
  //
  // Il danno non era teorico. Cestinando `importante.conf` dentro una cartella
  // non scrivibile, Minerva lo COPIAVA nel cestino, poi non riusciva a
  // togliere l'originale, e la copia restava lì — senza `.trashinfo`, quindi
  // senza modo di rimetterla a posto e senza che si vedesse che era un
  // avanzo. Su una cartella di sistema sarebbero stati gigabyte copiati nella
  // home per un'operazione che non poteva riuscire.
  static const int _eperm = 1;   // operazione non permessa (bit sticky)
  static const int _eacces = 13; // permesso negato
  static const int _exdev = 18;  // sono due dischi diversi: QUESTO si copia
  static const int _erofs = 30;  // il disco è montato in sola lettura

  static int? _codiceErrore(Object e) =>
      e is FileSystemException ? e.osError?.errorCode : null;

  /// Il motivo, detto a chi sta guardando invece che a chi ha scritto Dart.
  ///
  /// Prima nella finestra compariva `PathAccessException: Cannot delete file,
  /// path = '/…' (OS Error: Permission denied, errno = 13)`. È vero, ed è
  /// illeggibile: non dice di chi è la colpa né che cosa si può fare.
  static String motivo(String nome, Object e) {
    switch (_codiceErrore(e)) {
      case _eacces:
      case _eperm:
        return '«$nome» non si può togliere da dov\'è: la cartella che lo '
            'contiene non è tua. I file di sistema si cambiano solo da '
            'amministratore.';
      case _erofs:
        return '«$nome» sta su un disco montato in sola lettura.';
      default:
        final m = e is FileSystemException
            ? (e.osError?.message ?? e.message)
            : '$e';
        return '«$nome»: $m';
    }
  }

  /// Sposta senza sovrascrivere. Su EXDEV pubblica prima la copia completa;
  /// se la rimozione della sorgente fallisce, conserva la copia e segnala errore.
  Future<void> _sposta(String da, String a) async {
    try {
      LinuxFiles.renameNoReplace(da, a);
      return;
    } catch (e) {
      if (_codiceErrore(e) != _exdev) rethrow;
    }

    final staging = LinuxFiles.privateTemp(File(a).parent, '.minerva-transfer-');
    try {
      final prepared = '${staging.path}/contenuto';
      await _copyTree(da, prepared, null);
      LinuxFiles.renameNoReplace(prepared, a);
      await _deletePath(da);
    } finally {
      await _deletePathQuiet(staging.path);
    }
  }

  /// Toglie un percorso, qualunque cosa sia.
  ///
  /// Il ramo dei collegamenti c'è per lo stesso motivo per cui c'è in
  /// `eliminaDefinitivamente`: `File.delete()` su un collegamento a una
  /// CARTELLA solleva «Is a directory», e da qui quell'eccezione arrivava
  /// dentro uno spostamento — che quindi si annullava a metà, lasciando la
  /// copia e non togliendo l'originale. Vedi la prova nel gruppo «i
  /// collegamenti simbolici».
  Future<void> _deletePath(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      await Link(path).delete();
    } else if (type == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
    } else if (type != FileSystemEntityType.notFound) {
      await File(path).delete();
    }
  }

  Future<void> _deletePathQuiet(String path) async {
    try {
      await _deletePath(path);
    } catch (_) {}
  }

  void dispose() {
    _progress.close();
  }
}

/// Un trasferimento in corso.
class TransferJob {
  final String id;
  final List<String> sources;
  final String destination;
  final bool move;

  /// Cosa fare quando in destinazione c'è già un nome uguale:
  /// `entrambi` (si tiene anche il vecchio, col nome cambiato),
  /// `sostituisci`, `salta`.
  ///
  /// `entrambi` è il valore di serie e non per pigrizia: è l'unico che non
  /// perde niente. Prima era anche l'unico possibile, e succedeva in
  /// silenzio — chi copiava una foto sopra un'altra si ritrovava
  /// «foto (2).png» senza aver deciso niente.
  final String conflitto;

  /// `running` · `paused` · `cancelling` · `cancelled` · `done` · `failed`
  String state = 'running';
  int bytesTotal = 0;
  int bytesDone = 0;
  int sinceEmit = 0;
  String currentFile = '';
  String error = '';
  DateTime? finishedAt;

  /// Completato quando arriva «riprendi». Esiste solo mentre è in pausa.
  Completer<void>? resumeSignal;

  TransferJob({
    required this.id,
    required this.sources,
    required this.destination,
    required this.move,
    this.conflitto = 'entrambi',
  });

  bool get isFinished =>
      state == 'done' || state == 'cancelled' || state == 'failed';

  Future<void> waitIfPaused() async {
    while (state == 'paused') {
      resumeSignal ??= Completer<void>();
      await resumeSignal!.future;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'state': state,
        'move': move,
        'destination': destination,
        'sources': sources,
        'bytesTotal': bytesTotal,
        'bytesDone': bytesDone,
        'currentFile': currentFile,
        'error': error,
      };
}
