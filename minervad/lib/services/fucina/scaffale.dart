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
      r'^[1-9][0-9]?\.[0-9]{1,3}(\.[0-9]{1,4})?-fucina-[a-z0-9]([a-z0-9-]{0,22}[a-z0-9])?$');

  /// Il nome è di un kernel della Fucina? Lo stesso controllo che fa
  /// l'aiutante di root, carattere per carattere.
  static bool nostro(String rilascio) => _nostro.hasMatch(rilascio);

  Future<String> inUso() async {
    try {
      return (await File(_p('proc/sys/kernel/osrelease')).readAsString())
          .trim();
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
            });

    // Pronti: `…/uscita/<rilascio>/fucina.json`.
    try {
      await for (final d in Directory('$lavoro/uscita').list()) {
        if (d is! Directory) continue;
        final rel = d.path.split('/').last;
        if (!nostro(rel)) continue;
        final info = File('${d.path}/fucina.json');
        if (!await info.exists()) continue;
        final v = voce(rel)..['pronto'] = true;
        try {
          final j = jsonDecode(await info.readAsString()) as Map;
          v['quando'] = '${j['quando'] ?? ''}';
          v['moduli'] = j['moduli'];
          v['scelte'] = j['scelte'];
          v['provaAvvio'] = j['provaAvvio'];
        } catch (_) {}
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
          v['immagine'] =
              await File(_p('boot/vmlinuz-$rel')).exists();
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
        'spiega': 'Stai usando «$uso», che non è un kernel della Fucina. La '
            'verifica ha senso al primo avvio di un kernel nostro.',
      };
    }
    final List<dynamic> attesi;
    try {
      attesi = jsonDecode(
          await File('$statoDir/attesi-$uso.json').readAsString()) as List;
    } catch (_) {
      return {
        'ok': true,
        'applicabile': false,
        'inUso': uso,
        'spiega': 'Non trovo l\'elenco dei dispositivi di quando «$uso» è '
            'stato compilato: forse è stato compilato su un altro computer.',
      };
    }

    final orfani = <Map<String, dynamic>>[];
    final assenti = <Map<String, dynamic>>[];
    var aPosto = 0;
    for (final a in attesi) {
      if (a is! Map) continue;
      final cartella = _p('sys/devices${a['percorso']}');
      if (!await Directory(cartella).exists()) {
        assenti.add(a.cast<String, dynamic>());
        continue;
      }
      final driver = await _driver(cartella);
      if (driver == null) {
        orfani.add({...a.cast<String, dynamic>(), 'adesso': null});
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
