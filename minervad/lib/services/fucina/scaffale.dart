import 'dart:convert';
import 'dart:io';

/// Lo scaffale: i kernel della Fucina, quelli pronti e quelli installati, e
/// la verifica al primo avvio.
///
/// ── Solo i nostri ───────────────────────────────────────────────────────
///
/// Si elencano soltanto i kernel che nel nome portano `-fucina-`. Il kernel
/// della distribuzione non compare, e non per pudore: è quello che ti riporta
/// a casa quando il nostro non parte, e un elenco in cui lo si può togliere
/// con un clic è un elenco in cui prima o poi qualcuno lo toglie. In Minerva
/// Forge, la cancellazione di più kernel insieme era già stata segnata come
/// il difetto più pericoloso di tutto il programma.
class Scaffale {
  final String radice;
  final String lavoro;
  final String statoDir;

  Scaffale({this.radice = '/', required this.lavoro, required this.statoDir});

  String _p(String rel) => '$radice$rel';

  static final RegExp _nostro = RegExp(
    r'^[1-9][0-9]?\.[0-9]{1,3}(\.[0-9]{1,4})?-fucina-[a-z0-9]([a-z0-9-]{0,22}[a-z0-9])?$',
  );

  /// Il nome è di un kernel della Fucina? Lo stesso controllo che fa
  /// l'aiutante di root, carattere per carattere.
  static bool nostro(String rilascio) => _nostro.hasMatch(rilascio);

  Future<String> inUso() async {
    try {
      return (await File(
        _p('proc/sys/kernel/osrelease'),
      ).readAsString()).trim();
    } catch (_) {
      return '';
    }
  }

  /// Tutti i kernel della Fucina: quelli pronti in uscita (compilati, non
  /// ancora installati) e quelli installati nel sistema.
  Future<Map<String, dynamic>> elenco() async {
    final uso = await inUso();
    final voci = <String, Map<String, dynamic>>{};

    Map<String, dynamic> voce(String rel) => voci.putIfAbsent(
      rel,
      () => {
        'rilascio': rel,
        'pronto': false,
        'installato': false,
        'inUso': rel == uso,
        'immagine': false,
        'quando': '',
      },
    );

    // Pronti: `…/uscita/<rilascio>/fucina.json`.
    try {
      await for (final d in Directory('$lavoro/uscita').list()) {
        if (d is! Directory) continue;
        final rel = d.path.split('/').last;
        if (!nostro(rel)) continue;
        final info = File('${d.path}/fucina.json');
        if (!await info.exists()) continue;
        final v = voce(rel);
        final blocchi = <String>[];
        final avvisi = <String>[];
        try {
          if (await FileSystemEntity.type(info.path, followLinks: false) !=
                  FileSystemEntityType.file ||
              await info.length() > 2 * 1024 * 1024) {
            throw const FormatException(
              'Manifest non regolare o troppo grande',
            );
          }
          final j = jsonDecode(await info.readAsString()) as Map;
          if (j['rilascio'] != rel) {
            blocchi.add(
              'Il manifest non corrisponde al rilascio. Ricompila questo kernel.',
            );
          }
          v['quando'] = '${j['quando'] ?? ''}';
          v['moduli'] = j['moduli'];
          final secondi = j['secondiPreparazione'];
          if (secondi is int && secondi >= 0) {
            v['secondiPreparazione'] = secondi;
          }
          v['scelte'] = j['scelte'];
          v['provaAvvio'] = j['provaAvvio'];
          v['log'] = j['log'];
          final prova = j['provaAvvio'];
          if (prova is Map && prova['ok'] == false) {
            blocchi.add(
              'La prova QEMU non è riuscita. Consulta il log e ripeti la prova prima di installare.',
            );
          } else if (prova is! Map || prova['ok'] != true) {
            avvisi.add(
              'Prova QEMU non superata o non registrata: l’avvio non è stato verificato.',
            );
          }
        } catch (_) {
          blocchi.add(
            'Manifest illeggibile o non valido. Ricompila questo kernel; i file esistenti sono conservati.',
          );
        }
        for (final parte in [
          'boot',
          'lib',
          'lib/modules',
          'lib/modules/$rel',
        ]) {
          if (await FileSystemEntity.type(
                '${d.path}/$parte',
                followLinks: false,
              ) !=
              FileSystemEntityType.directory) {
            blocchi.add(
              'Cartella $parte mancante o non regolare. Ricompila questo kernel.',
            );
          }
        }
        for (final parte in ['boot/vmlinuz-$rel', 'boot/config-$rel']) {
          final f = File('${d.path}/$parte');
          try {
            if (await FileSystemEntity.type(f.path, followLinks: false) !=
                    FileSystemEntityType.file ||
                await f.length() == 0) {
              blocchi.add(
                '$parte mancante, vuoto o non regolare. Ricompila questo kernel.',
              );
            }
          } catch (_) {
            blocchi.add(
              'Non riesco a verificare $parte. Controlla i permessi della cache.',
            );
          }
        }
        v['pronto'] = blocchi.isEmpty;
        v['preparazione'] = {
          'ok': blocchi.isEmpty,
          'blocchi': blocchi,
          'avvisi': avvisi,
        };
      }
    } catch (_) {}

    // Installati: una cartella in `/usr/lib/modules`, e l'immagine in /boot.
    for (final base in const ['usr/lib/modules', 'lib/modules']) {
      try {
        await for (final d in Directory(_p(base)).list()) {
          if (d is! Directory) continue;
          final rel = d.path.split('/').last;
          if (!nostro(rel)) continue;
          final v = voce(rel)..['installato'] = true;
          v['immagine'] = await File(_p('boot/vmlinuz-$rel')).exists();
        }
        break;
      } catch (_) {
        continue;
      }
    }

    // ── AutoFDO: chi è pronto al profilo, e chi ce l'ha ─────────────────
    //
    // Un kernel è «pronto al profilo» se il suo vmlinux è stato messo da
    // parte quando lo si è compilato (`profili/<rilascio>/vmlinux`): è quello
    // che serve per convertire quello che registra perf. Il profilo
    // convertito sta accanto.
    for (final v in voci.values) {
      final p = '$lavoro/profili/${v['rilascio']}';
      v['prontoAlProfilo'] = await File('$p/vmlinux').exists();
      v['profilo'] = await File('$p/autofdo.prof').exists();
      final s = v['scelte'];
      v['colProfiloDi'] = s is Map ? '${s['profilo'] ?? ''}' : '';
    }

    final elenco = voci.values.toList()
      ..sort((a, b) => '${b['rilascio']}'.compareTo('${a['rilascio']}'));
    return {'inUso': uso, 'kernel': elenco};
  }

  /// La verifica al primo avvio.
  ///
  /// Quando si è compilato, la Fucina si è segnata quali dispositivi avevano
  /// un driver (`attesi-<rilascio>.json`). Adesso, avviati sul kernel nuovo,
  /// si rilegge `/sys`: un dispositivo che c'è ancora ma è rimasto senza
  /// driver è un modulo che la scrematura ha tolto e che serviva.
  ///
  /// Un dispositivo che non c'è più non è un errore: è una chiavetta
  /// scollegata. Si dice a parte.
  Future<Map<String, dynamic>> verifica() async {
    final uso = await inUso();
    if (!nostro(uso)) {
      return {
        'ok': true,
        'applicabile': false,
        'inUso': uso,
        'spiega':
            'Stai usando «$uso», che non è un kernel della Fucina. La '
            'verifica ha senso al primo avvio di un kernel nostro.',
      };
    }
    final List<dynamic> attesi;
    try {
      attesi =
          jsonDecode(await File('$statoDir/attesi-$uso.json').readAsString())
              as List;
    } catch (_) {
      return {
        'ok': true,
        'applicabile': false,
        'inUso': uso,
        'spiega':
            'Non trovo l\'elenco dei dispositivi di quando «$uso» è '
            'stato compilato: forse è stato compilato su un altro computer.',
      };
    }

    final orfani = <Map<String, dynamic>>[];
    final assenti = <Map<String, dynamic>>[];
    final ricollocati = <Map<String, dynamic>>[];
    final ambigui = <Map<String, dynamic>>[];
    final usati = <String>{};
    final mancanti = <Map<String, dynamic>>[];
    var aPosto = 0;
    for (final a in attesi) {
      if (a is! Map || a['percorso'] is! String) continue;
      final percorso = a['percorso'] as String;
      if (!percorso.startsWith('/') ||
          percorso.contains(RegExp(r'[\x00-\x1f]')) ||
          percorso.split('/').any((s) => s == '..' || s == '.')) {
        continue;
      }
      final voce = Map<String, dynamic>.from(a);
      final cartella = _p('sys/devices$percorso');
      String? alias;
      try {
        alias = (await File('$cartella/modalias').readAsString()).trim();
      } catch (_) {}
      if (!await Directory(cartella).exists() ||
          (alias != null && alias != a['modalias'])) {
        mancanti.add(voce);
        continue;
      }
      if (!usati.add(cartella)) continue;
      final driver = await _driver(cartella);
      if (driver == null) {
        orfani.add({...a.cast<String, dynamic>(), 'adesso': null});
      } else {
        aPosto++;
      }
    }
    // Un dispositivo corrente non può coprire due attesi. Per alias
    // duplicati non inventiamo identità individuali.
    final perAlias = <String, List<String>>{};
    if (mancanti.isNotEmpty) {
      try {
        await for (final f in Directory(
          _p('sys/devices'),
        ).list(recursive: true, followLinks: false)) {
          if (f is! File || !f.path.endsWith('/modalias')) continue;
          final cartella = f.parent.path;
          if (usati.contains(cartella)) continue;
          try {
            final alias = (await f.readAsString()).trim();
            perAlias.putIfAbsent(alias, () => []).add(cartella);
          } catch (_) {}
        }
      } catch (_) {}
    }
    for (final a in mancanti) {
      final alias = a['modalias'];
      final candidati = alias is String && alias.isNotEmpty
          ? perAlias[alias] ?? <String>[]
          : <String>[];
      final quantiAttesi = mancanti.where((v) => v['modalias'] == alias).length;
      if (candidati.length != 1 || quantiAttesi != 1) {
        assenti.add(a);
        if (candidati.isNotEmpty) {
          ambigui.add({...a, 'candidati': candidati.length});
        }
        continue;
      }
      final cartella = candidati.single;
      if (!usati.add(cartella)) {
        assenti.add(a);
        continue;
      }
      final driver = await _driver(cartella);
      final voce = {
        ...a,
        'percorsoAttuale': cartella.substring(_p('sys/devices').length),
        'driverAttuale': driver,
        'metodo': 'modalias-univoco',
      };
      ricollocati.add(voce);
      if (driver == null) {
        orfani.add({...voce, 'adesso': null});
      } else {
        aPosto++;
      }
    }
    return {
      'ok': true,
      'applicabile': true,
      'inUso': uso,
      'aPosto': aPosto,
      'orfani': orfani,
      'assenti': assenti,
      'ricollocati': ricollocati,
      'ambigui': ambigui,
      'limiteIdentita':
          'Il modalias identifica il modello, non il seriale della singola periferica.',
    };
  }

  Future<String?> _driver(String cartella) async {
    try {
      final t = await Link('$cartella/driver').target();
      return t.split('/').last;
    } catch (_) {
      return null;
    }
  }
}
