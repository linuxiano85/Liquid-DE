import 'dart:io';

/// Fotografia in sola lettura della memoria disponibile al daemon e ai figli.
/// Nessun percorso letto da procfs viene incluso nel risultato pubblico.
class RisorseCompilazione {
  final String radice;
  const RisorseCompilazione({this.radice = '/'});

  Future<String?> _leggi(String assoluto) async {
    try {
      final f = File('${radice.replaceFirst(RegExp(r'/+$'), '')}$assoluto');
      if (await f.length() > 256 * 1024) return null;
      return await f.readAsString();
    } catch (_) {
      return null;
    }
  }

  static int? _numero(String? s) {
    final t = s?.trim() ?? '';
    if (!RegExp(r'^\d{1,19}$').hasMatch(t)) return null;
    final n = int.tryParse(t);
    return n != null && n >= 0 ? n : null;
  }

  static String? _percorso(String s) {
    final p = s.replaceAllMapped(
      RegExp(r'\\([0-7]{3})'),
      (m) => String.fromCharCode(int.parse(m[1]!, radix: 8)),
    );
    if (!p.startsWith('/') ||
        p.contains(RegExp(r'[\x00-\x1f]')) ||
        p.split('/').any((s) => s == '.' || s == '..')) {
      return null;
    }
    return p == '/' ? p : p.replaceFirst(RegExp(r'/+$'), '');
  }

  Future<Map<String, dynamic>> leggi() async {
    final avvisi = <String>[];
    final mem = await _leggi('/proc/meminfo') ?? '';
    int? campo(String nome) {
      final n = _numero(
        RegExp(
          '^$nome:[ \\t]*(\\d+)[ \\t]+kB[ \\t]*\$',
          multiLine: true,
        ).firstMatch(mem)?.group(1),
      );
      return n != null && n <= 9007199254740991 ~/ 1024 ? n * 1024 : null;
    }

    final totale = campo('MemTotal'), disponibile = campo('MemAvailable');
    int? effettiva = totale != null && totale > 0 && disponibile != null
        ? (disponibile < totale ? disponibile : totale)
        : null;
    if (effettiva == null) avvisi.add('MemAvailable non verificabile.');

    final cgroup = await _leggi('/proc/self/cgroup');
    final mountinfo = await _leggi('/proc/self/mountinfo');
    final righe =
        cgroup?.split('\n').where((s) => s.startsWith('0::')).toList() ?? [];
    var verificato = false, limitato = false;
    int? margine;
    if (righe.length == 1 && mountinfo != null) {
      final gruppo = _percorso(righe.single.substring(3));
      final montaggi = <({String base, String mount, String device})>[];
      for (final r in mountinfo.split('\n')) {
        final parti = r.split(' '), separatore = r.split(' ').indexOf('-');
        if (parti.length < 10 ||
            separatore < 6 ||
            separatore + 1 >= parti.length ||
            parti[separatore + 1] != 'cgroup2') {
          continue;
        }
        final base = _percorso(parti[3]), mount = _percorso(parti[4]);
        if (base != null &&
            mount != null &&
            RegExp(r'^\d+:\d+$').hasMatch(parti[2]) &&
            gruppo != null &&
            (base == '/' || gruppo == base || gruppo.startsWith('$base/'))) {
          montaggi.add((base: base, mount: mount, device: parti[2]));
        }
      }
      // Bind mount della stessa gerarchia sono normali (ad esempio bpftune).
      // Sceglie il mount che espone più antenati, mantenendo il controllo
      // conservativo quando i filesystem descritti non coincidono.
      if (gruppo != null &&
          montaggi.isNotEmpty &&
          montaggi.map((m) => m.device).toSet().length == 1) {
        montaggi.sort((a, b) {
          final profondita = a.base.length.compareTo(b.base.length);
          if (profondita != 0) return profondita;
          if (a.mount == b.mount) return 0;
          if (a.mount == '/sys/fs/cgroup') return -1;
          if (b.mount == '/sys/fs/cgroup') return 1;
          return a.mount.compareTo(b.mount);
        });
        final m = montaggi.first;
        final relativo = m.base == '/'
            ? gruppo
            : gruppo.substring(m.base.length);
        var dir =
            '${m.mount == '/' ? '' : m.mount}${relativo == '/' ? '' : relativo}';
        if (dir.isEmpty) dir = '/';
        verificato = true;
        var livelli = 0;
        while (true) {
          if (++livelli > 256) {
            verificato = false;
            break;
          }
          final max = (await _leggi('$dir/memory.max'))?.trim();
          final current = await _leggi('$dir/memory.current');
          // La radice globale non ha i file del controller memoria.
          if (!(dir == m.mount &&
              m.base == '/' &&
              max == null &&
              current == null)) {
            final uso = _numero(current);
            final limite = _numero(max);
            if (uso == null || (max != 'max' && limite == null)) {
              verificato = false;
              break;
            }
            if (limite != null) {
              limitato = true;
              final spazio = (limite - uso).clamp(0, limite);
              margine = margine == null || spazio < margine ? spazio : margine;
            }
          }
          if (dir == m.mount) break;
          final indice = dir.lastIndexOf('/');
          dir = indice == 0 ? '/' : dir.substring(0, indice);
        }
      }
    }
    if (!verificato) {
      effettiva = null;
      avvisi.add(
        'Limiti di memoria cgroup non verificabili (v1 o gerarchia incompleta).',
      );
    } else if (effettiva != null && margine != null && margine < effettiva) {
      effettiva = margine;
    }
    return {
      'memoriaDisponibileBytes': disponibile,
      'memoriaEffettivaBytes': effettiva,
      'cgroupV2Verificato': verificato,
      'cgroupLimitato': limitato,
      'avvisi': avvisi,
    };
  }
}

/// Euristica esplicita, non una previsione del picco di ogni compilatore.
Map<String, dynamic> scegliParallelismo({
  required int thread,
  required int? richiesti,
  required bool thinLto,
  required Map<String, dynamic> risorse,
}) {
  const mib = 1024 * 1024;
  final massimi = thread.clamp(1, 512);
  final raw = risorse['memoriaEffettivaBytes'];
  final memoria =
      raw is int && raw >= 0 && risorse['cgroupV2Verificato'] == true
      ? raw
      : null;
  final perLavoro = (thinLto ? 768 : 512) * mib;
  final riserva = memoria == null
      ? 0
      : (memoria ~/ 5).clamp(256 * mib, 2 * 1024 * mib);
  final consigliati = memoria == null
      ? 1
      : ((memoria - riserva).clamp(0, memoria) ~/ perLavoro).clamp(1, massimi);
  final effettivi = richiesti == null
      ? consigliati
      : richiesti.clamp(1, massimi);
  final motivo = memoria == null
      ? 'Memoria disponibile non verificabile: Auto propone un lavoro. Puoi impostare un limite manuale.'
      : 'Auto propone $consigliati lavori su $massimi thread: ${(memoria / (1024 * mib)).toStringAsFixed(1)} GiB disponibili'
            '${risorse['cgroupLimitato'] == true ? ' entro i limiti cgroup' : ''}, '
            '${(riserva / mib).round()} MiB di margine e ${(perLavoro / mib).round()} MiB stimati per lavoro.';
  return {
    'automatico': richiesti == null,
    'consigliati': consigliati,
    'effettivi': effettivi,
    'thread': massimi,
    'memoriaEffettivaBytes': memoria,
    'riservaBytes': riserva,
    'stimaPerLavoroBytes': perLavoro,
    'manualeOltreConsiglio': richiesti != null && effettivi > consigliati,
    'motivo': motivo,
    'limite':
        'Stima prudente, non garantisce di evitare OOM. '
        '${thinLto ? 'ThinLTO usa anche thread propri nel linker, non limitati da make -j. ' : ''}'
        'La memoria viene riletta quando si avvia la compilazione.',
  };
}
