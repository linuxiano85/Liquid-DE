import 'dart:async';
import 'dart:io';
import '../minervad/lib/services/file_service.dart';

// Ogni contenuto e anche il cestino sono privati. Le prove controllano
// i byte conservati nelle operazioni, non soltanto l'esito dichiarato.
Future<void> main() async {
  final base = await Directory.systemTemp.createTemp('liquid-file-operazioni-');
  final files = FileService(cestinoDiProva: '${base.path}/trash');
  var checks = 0;
  void check(String name, bool condition) {
    if (!condition) throw StateError(name);
    checks++;
    print('PASS $name');
  }
  Future<Map<String, dynamic>> transfer(String source, String destination,
      {bool move = false, String conflict = 'entrambi'}) async {
    final finished = files.progress.firstWhere((event) =>
        ['done', 'failed', 'cancelled'].contains(event['state']));
    await files.startTransfer(sources: [source], destination: destination,
        move: move, conflitto: conflict);
    return finished.timeout(const Duration(seconds: 10));
  }
  try {
    final source = await Directory('${base.path}/source').create();
    final destination = await Directory('${base.path}/destination').create();
    final original = File('${source.path}/nota.txt');
    await original.writeAsString('originale');
    var result = await transfer(original.path, destination.path);
    final copy = File('${destination.path}/nota.txt');
    check('copia conserva sorgente e contenuto', result['state'] == 'done' &&
        await original.readAsString() == 'originale' && await copy.readAsString() == 'originale');
    await copy.writeAsString('precedente');
    result = await transfer(original.path, destination.path, conflict: 'salta');
    check('conflitto Salta conserva il file destinazione', result['state'] == 'done' && await copy.readAsString() == 'precedente');
    result = await transfer(original.path, destination.path);
    final contents = await destination.list().where((entry) => entry is File)
        .asyncMap((entry) => File(entry.path).readAsString()).toList();
    check('conflitto Entrambi conserva entrambi i contenuti', result['state'] == 'done' && contents.contains('precedente') && contents.contains('originale'));
    result = await transfer(original.path, destination.path, conflict: 'sostituisci');
    check('conflitto Sostituisci sostituisce solo la destinazione', result['state'] == 'done' && await copy.readAsString() == 'originale' && await original.exists());
    final moved = File('${source.path}/sposta.txt');
    await moved.writeAsString('da spostare');
    result = await transfer(moved.path, destination.path, move: true);
    check('spostamento rimuove la sorgente dopo aver conservato i byte', result['state'] == 'done' && !await moved.exists() && await File('${destination.path}/sposta.txt').readAsString() == 'da spostare');
    final occupied = File('${source.path}/occupato.txt');
    await occupied.writeAsString('non sovrascrivere');
    result = await files.rename(original.path, occupied.path);
    check('rinomina su nome occupato conserva tutti i file', result['ok'] == false && await original.readAsString() == 'originale' && await occupied.readAsString() == 'non sovrascrivere');
    result = await files.trash([original.path]);
    final trashed = List<String>.from(result['nelCestino'] as List);
    check('cestino conserva i byte e rimuove soltanto la sorgente', result['ok'] == true && !await original.exists() && await File(trashed.single).readAsString() == 'originale');
    result = await files.restoreFromTrash(trashed);
    check('ripristino recupera contenuto e posizione', result['ok'] == true && await original.readAsString() == 'originale');
    result = await files.trash([original.path]);
    final collision = List<String>.from(result['nelCestino'] as List);
    await original.writeAsString('nuovo contenuto');
    result = await files.restoreFromTrash(collision);
    check('ripristino con conflitto conserva il nuovo contenuto', await original.readAsString() == 'nuovo contenuto');
    final big = File('${source.path}/grande.bin');
    await big.writeAsBytes(List<int>.generate(16 * 1024 * 1024, (index) => index % 251));
    final finished = files.progress.firstWhere((event) =>
        ['done', 'failed', 'cancelled'].contains(event['state']));
    final id = await files.startTransfer(sources: [big.path], destination: destination.path, move: false);
    files.pause(id);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    check('pausa mantiene il trasferimento disponibile', files.jobsJson().any((job) => job['id'] == id && job['state'] == 'paused'));
    files.cancel(id);
    result = await finished.timeout(const Duration(seconds: 10));
    check('annullamento da pausa conserva la sorgente e non pubblica copie parziali', result['state'] == 'cancelled' && await big.length() == 16 * 1024 * 1024 && !await File('${destination.path}/grande.bin').exists());
    final resumed = files.progress.firstWhere((event) =>
        ['done', 'failed', 'cancelled'].contains(event['state']));
    final resumeId = await files.startTransfer(sources: [big.path], destination: destination.path, move: false);
    files.pause(resumeId);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    files.resume(resumeId);
    result = await resumed.timeout(const Duration(seconds: 10));
    final expected = await big.readAsBytes();
    final actual = await File('${destination.path}/grande.bin').readAsBytes();
    check('ripresa completa tutti i byte senza duplicarli', result['state'] == 'done' &&
        actual.length == expected.length && List<int>.generate(actual.length, (index) => index)
            .every((index) => actual[index] == expected[index]));
    final denied = await Directory('${base.path}/non-scrivibile').create();
    await Process.run('chmod', ['a-w', denied.path]);
    try {
      result = await transfer(original.path, denied.path, move: true);
      check('permessi negati non rimuovono la sorgente dello spostamento', result['state'] == 'failed' && await original.readAsString() == 'nuovo contenuto');
    } finally {
      await Process.run('chmod', ['u+w', denied.path]);
    }
    result = await transfer('${source.path}/assente', destination.path);
    check('sorgente scomparsa restituisce errore e conserva gli altri file', result['state'] == 'failed' && await copy.readAsString() == 'originale');
    print('operazioni file: $checks controlli superati');
  } finally {
    files.dispose();
    await base.delete(recursive: true);
  }
}
