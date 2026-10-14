import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'processi_lavoro.dart';
import '../../core/linux_files.dart';

/// Esclusione fra sessioni e registro persistente per il recupero dopo crash.
class BloccoLavoro {
  static final Set<String> _occupati = {};
  final String _chiave;
  final RandomAccessFile _file;
  final File _segnale;
  final Map<String, dynamic> _dati;
  bool _chiuso = false;
  bool _conserva = false;
  BloccoLavoro._(this._chiave, this._file, this._segnale, this._dati);

  static Future<({String chiave, RandomAccessFile file})> _apri(
    String lavoro,
  ) async {
    final cartella = await Directory(lavoro).create(recursive: true);
    final chiave = await cartella.resolveSymbolicLinks();
    // fcntl è per processo: due istanze Dart non devono aprire lo stesso inode.
    if (!_occupati.add(chiave)) {
      throw const FileSystemException('La cache Fucina è occupata.');
    }
    RandomAccessFile? f;
    try {
      f = await File('$chiave/.lavoro.lock').open(mode: FileMode.append);
      await f.lock(FileLock.exclusive);
      return (chiave: chiave, file: f);
    } catch (_) {
      try {
        await f?.close();
      } finally {
        _occupati.remove(chiave);
      }
      throw const FileSystemException(
        'La cache Fucina è occupata o non posso bloccarla.',
      );
    }
  }

  static Future<void> _rilascia(String chiave, RandomAccessFile file) async {
    try {
      await file.close();
    } finally {
      _occupati.remove(chiave);
    }
  }

  static Future<BloccoLavoro> prendi(
    String lavoro, {
    String tipo = 'generico',
    Map<String, dynamic> dettagli = const {},
  }) async {
    final l = await _apri(lavoro);
    final segnale = File('${l.chiave}/.lavoro-attivo.json');
    try {
      if (await FileSystemEntity.type(segnale.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const FileSystemException(
          'Un lavoro Fucina precedente non è stato chiuso regolarmente. Apri Kernel installati e verifica il recupero della cache.',
        );
      }
      const p = ProcessiLavoro();
      final identita = await p.leggi(pid);
      final b = BloccoLavoro._(l.chiave, l.file, segnale, {
        'versione': 2,
        'id': base64Url.encode(
          List.generate(18, (_) => Random.secure().nextInt(256)),
        ),
        'pid': pid,
        'inizio': identita?['inizio'],
        'boot': await p.boot(),
        'spazioPid': await p.spazioPid(),
        'quando': DateTime.now().toUtc().toIso8601String(),
        'tipo': tipo,
        'fase': 'nessun-processo',
        'processi': <Map<String, dynamic>>[],
        'dettagli': dettagli,
      });
      await b._salva();
      return b;
    } catch (_) {
      await _rilascia(l.chiave, l.file);
      rethrow;
    }
  }

  Future<void> _salva() async {
    final tmp = File(
      '$_chiave/.lavoro-attivo-$pid-${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await tmp.writeAsString(jsonEncode(_dati), flush: true);
      await tmp.rename(_segnale.path);
      LinuxFiles.fsyncCartella(_chiave);
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }
  }

  /// Pubblicare PRIMA dello spawn: se il daemon muore nella finestra fra spawn
  /// e registrazione, il recupero nello stesso boot resta vietato.
  Future<void> preparaProcesso() async {
    _dati['fase'] = 'avvio-processo';
    await _salva();
  }

  Future<void> registraProcesso(int numero, {required bool conSetsid}) async {
    const osservatore = ProcessiLavoro();
    Map<String, dynamic>? p;
    for (var i = 0; i < 20; i++) {
      p = await osservatore.leggi(numero);
      if (p == null || p['gruppo'] == numero) break;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    // Un processo già uscito può ancora avere figli nel gruppo creato da setsid.
    final isolato =
        conSetsid &&
        (p == null || (p['gruppo'] == numero && p['sessione'] == numero));
    (_dati['processi'] as List).add({
      'pid': numero,
      'gruppo': numero,
      'isolato': isolato,
      'inizio': p?['inizio'],
    });
    _dati['fase'] = 'processo-registrato';
    await _salva();
  }

  /// Se la registrazione fallisce dopo lo spawn, non rimuovere il segnale:
  /// il processo potrebbe continuare anche dopo l'uscita del daemon.
  void conservaPerRecupero() => _conserva = true;

  Future<void> completaProcesso(int numero) async {
    if (await const ProcessiLavoro().gruppoEsiste(numero) == false) {
      (_dati['processi'] as List).removeWhere(
        (p) => p is Map && p['pid'] == numero,
      );
      _dati['fase'] = (_dati['processi'] as List).isEmpty
          ? 'nessun-processo'
          : 'processo-registrato';
      await _salva();
    }
  }

  static Future<Map<String, dynamic>> _diagnosi(
    String chiave,
    ProcessiLavoro proc,
  ) async {
    final segnale = File('$chiave/.lavoro-attivo.json');
    final type = await FileSystemEntity.type(segnale.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return {
        'stato': 'libero',
        'recuperabile': false,
        'messaggio': 'La cache è pronta.',
      };
    }
    if (type != FileSystemEntityType.file || await segnale.length() > 65536) {
      throw const FormatException('Segnale di recupero non valido.');
    }
    final d = jsonDecode(await segnale.readAsString()) as Map<String, dynamic>;
    final result = <String, dynamic>{
      'stato': 'da-verificare',
      'recuperabile': false,
      'messaggio':
          'I processi del lavoro precedente non sono verificabili. Conserva i log: serve una verifica manuale prima di riaprire la cache.',
      'quando': d['quando'],
      'tipo': d['tipo'],
    };
    if (d['versione'] != 2 ||
        d['id'] is! String ||
        d['boot'] is! String ||
        (d['boot'] as String).isEmpty) {
      return result;
    }
    result['token'] = d['id'];
    final boot = await proc.boot();
    if (boot.isEmpty) return result;
    if (boot != d['boot']) {
      return {
        ...result,
        'stato': 'recuperabile',
        'recuperabile': true,
        'messaggio':
            'Il lavoro appartiene a un avvio precedente. Puoi riaprire la cache; verifica separatamente eventuali installazioni interrotte.',
      };
    }
    if (d['spazioPid'] != await proc.spazioPid()) return result;
    if (d['pid'] is! int || d['inizio'] is! String) return result;
    final owner = await proc.leggi(d['pid'] as int);
    if (d['rilasciato'] != true &&
        owner != null &&
        owner['inizio'] == d['inizio'] &&
        owner['stato'] != 'Z' &&
        owner['stato'] != 'X') {
      return {
        ...result,
        'stato': 'occupato',
        'messaggio': 'Il processo che ha aperto il lavoro è ancora vivo.',
      };
    }
    if (d['tipo'] != 'compilazione' ||
        d['fase'] == 'avvio-processo' ||
        !{'nessun-processo', 'processo-registrato'}.contains(d['fase']) ||
        d['processi'] is! List) {
      return {
        ...result,
        'messaggio':
            'Non posso escludere un processo non registrato o amministrativo ancora attivo. Dopo un riavvio sarà possibile riaprire la cache.',
      };
    }
    final groups = <int>{};
    for (final p in d['processi'] as List) {
      if (p is! Map ||
          p['isolato'] != true ||
          p['gruppo'] is! int ||
          (p['gruppo'] as int) <= 1) {
        return result;
      }
      groups.add(p['gruppo'] as int);
    }
    final vivi = await proc.gruppi(groups);
    if (vivi.isNotEmpty) {
      return {
        ...result,
        'stato': 'occupato',
        'processi': vivi,
        'messaggio':
            'Ci sono ancora processi del lavoro interrotto. Attendi che terminino e verifica di nuovo.',
      };
    }
    // La scansione procfs non è atomica: un processo può fare fork mentre
    // leggiamo le directory. ESRCH sul gruppo chiude quella finestra.
    for (final gruppo in groups) {
      if (await proc.gruppoEsiste(gruppo) != false) {
        return {
          ...result,
          'stato': 'occupato',
          'messaggio':
              'Un gruppo del lavoro esiste ancora o non posso verificarlo. Attendi e controlla di nuovo.',
        };
      }
    }
    return {
      ...result,
      'stato': 'recuperabile',
      'recuperabile': true,
      'messaggio':
          'Il processo principale e i gruppi di lavoro registrati sono terminati. Puoi riaprire la cache.',
    };
  }

  static Future<Map<String, dynamic>> verifica(
    String lavoro, {
    ProcessiLavoro proc = const ProcessiLavoro(),
  }) async {
    if (!await Directory(lavoro).exists()) {
      return {
        'stato': 'libero',
        'recuperabile': false,
        'messaggio': 'La cache è pronta.',
      };
    }
    ({String chiave, RandomAccessFile file})? l;
    try {
      l = await _apri(lavoro);
      return await _diagnosi(l.chiave, proc);
    } on FileSystemException catch (e) {
      return {
        'stato': l == null ? 'occupato' : 'da-verificare',
        'recuperabile': false,
        'messaggio': e.message,
      };
    } catch (_) {
      return {
        'stato': 'da-verificare',
        'recuperabile': false,
        'messaggio':
            'Non riesco a verificare il lavoro interrotto. Il segnale viene conservato.',
      };
    } finally {
      if (l != null) await _rilascia(l.chiave, l.file);
    }
  }

  static Future<Map<String, dynamic>> recupera(
    String lavoro,
    Object? token, {
    ProcessiLavoro proc = const ProcessiLavoro(),
  }) async {
    if (token is! String || token.isEmpty) {
      return {
        'ok': false,
        'errore': 'Verifica il recupero della cache prima di continuare.',
      };
    }
    final l = await _apri(lavoro);
    try {
      final stato = await _diagnosi(l.chiave, proc);
      if (stato['recuperabile'] != true || stato['token'] != token) {
        return {
          'ok': false,
          'errore':
              'Lo stato è cambiato o ci sono ancora processi attivi. Verifica di nuovo.',
          'recupero': stato,
        };
      }
      // Conservare la ricevuta e liberare il blocco con la stessa rinomina atomica.
      final ricevuta =
          '${l.chiave}/.lavoro-recuperato-${DateTime.now().microsecondsSinceEpoch}.json';
      LinuxFiles.renameNoReplace('${l.chiave}/.lavoro-attivo.json', ricevuta);
      LinuxFiles.fsyncCartella(l.chiave);
      return {
        'ok': true,
        'messaggio':
            'Cache riaperta. I sorgenti, i kernel e i log sono conservati. Il lavoro interrotto non viene considerato riuscito.',
      };
    } finally {
      await _rilascia(l.chiave, l.file);
    }
  }

  Future<void> chiudi() async {
    if (_chiuso) return;
    _chiuso = true;
    try {
      final gruppi = <int>{
        for (final p in _dati['processi'] as List)
          if (p is Map && p['gruppo'] is int) p['gruppo'] as int,
      };
      if ((await const ProcessiLavoro().gruppi(gruppi)).isNotEmpty) {
        _conserva = true;
      }
      for (final g in gruppi) {
        if (await const ProcessiLavoro().gruppoEsiste(g) != false) {
          _conserva = true;
        }
      }
      if (_conserva) {
        _dati['rilasciato'] = true;
        await _salva();
      } else {
        await _segnale.delete();
      }
    } finally {
      await _rilascia(_chiave, _file);
    }
  }
}
