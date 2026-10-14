import 'dart:io';
import '../../core/linux_files.dart';

/// Identità e gruppi da procfs, senza usare solo il PID (che può essere riusato).
/// I campi non includono command line, seriali o dati delle applicazioni.
class ProcessiLavoro {
  final String proc;
  const ProcessiLavoro({this.proc = '/proc'});

  Future<bool?> gruppoEsiste(int gruppo) async =>
      LinuxFiles.gruppoProcessiEsiste(gruppo);

  Future<String> boot() async =>
      (await File('$proc/sys/kernel/random/boot_id').readAsString()).trim();

  Future<String> spazioPid() => Link('$proc/self/ns/pid').target();

  Future<Map<String, dynamic>?> leggi(int numero) async {
    final f = File('$proc/$numero/stat');
    try {
      final s = await f.readAsString();
      final inizio = s.indexOf('(');
      final fine = s.lastIndexOf(')');
      if (inizio < 1 ||
          fine < inizio ||
          int.tryParse(s.substring(0, inizio).trim()) != numero) {
        throw const FormatException('Identità procfs non valida');
      }
      final campi = s.substring(fine + 2).trim().split(RegExp(r'\s+'));
      if (fine < 0 || campi.length < 20) {
        throw const FormatException('stat incompleto');
      }
      return {
        'pid': numero,
        'nome': s.substring(s.indexOf('(') + 1, fine),
        'stato': campi[0],
        'gruppo': int.parse(campi[2]),
        'sessione': int.parse(campi[3]),
        'inizio': campi[19],
      };
    } on FileSystemException {
      if (!await Directory('$proc/$numero').exists()) return null;
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> gruppi(Set<int> gruppi) async {
    if (gruppi.isEmpty) return [];
    final vivi = <Map<String, dynamic>>[];
    await for (final d in Directory(proc).list(followLinks: false)) {
      final n = int.tryParse(d.path.split('/').last);
      if (n == null) continue;
      final p = await leggi(n);
      if (p != null &&
          gruppi.contains(p['gruppo']) &&
          p['stato'] != 'Z' &&
          p['stato'] != 'X') {
        vivi.add(p);
      }
    }
    return vivi;
  }
}
