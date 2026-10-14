import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../minervad/lib/services/liquid_update_service.dart';

var checks = 0;
void check(bool condition, String name) {
  if (!condition) throw StateError(name);
  checks++;
  stdout.writeln('PASS $name');
}

const oldRevision = '1111111111111111111111111111111111111111';
const newRevision = '2222222222222222222222222222222222222222';
Future<void> main(List<String> args) async {
  final folder = await Directory.systemTemp.createTemp('liquid-update-test-');
  final archive = File('${folder.path}/fixture.zip');
  await Process.run('python3', [
    '-I',
    '-c',
    'import zipfile,sys\nwith zipfile.ZipFile(sys.argv[1],"w") as z:\n z.writestr("Liquid-DE/test.txt","contenuto di prova")\n z.writestr("../NON_ESTRARRE","mai eseguire o estrarre")',
    archive.path,
  ]);
  final bytes = await archive.readAsBytes();
  final manifest = File('${folder.path}/install/liquid-build.json');
  await manifest.parent.create();
  await manifest.writeAsString(
    jsonEncode({
      'repository': LiquidUpdateService.repository,
      'revision': oldRevision,
      'version': '1.0.0',
      'dirty': true,
    }),
  );
  var apiCalls = 0;
  var archiveCalls = 0;
  var status = 200;
  var invalidRevision = false;
  var invalidArchive = false;
  var slow = false;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final subscription = server.listen((request) async {
    try {
      if (request.uri.path.endsWith('/zip/$newRevision')) {
        archiveCalls++;
        check(
          request.uri.path.contains(LiquidUpdateService.repository),
          'download dal repository fisso',
        );
        request.response.contentLength = invalidArchive ? 4 : bytes.length;
        if (invalidArchive) {
          request.response.add([1, 2, 3, 4]);
        } else if (slow) {
          request.response.add(bytes.sublist(0, 8));
          await request.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 800));
          request.response.add(bytes.sublist(8));
        } else {
          request.response.add(bytes);
        }
      } else {
        apiCalls++;
        if (status != 200) {
          request.response.statusCode = status;
          request.response.headers.set('x-ratelimit-reset', '2000000000');
        } else if (request.headers.value('if-none-match') != null &&
            !invalidRevision) {
          request.response.statusCode = 304;
        } else {
          request.response.headers.set('etag', '"fixture"');
          final data = request.uri.path.contains('/compare/')
              ? {
                  'status': 'ahead',
                  'total_commits': 1,
                  'commits': [
                    {
                      'sha': newRevision,
                      'commit': {'message': 'Solo CI'},
                    },
                  ],
                  'files': [
                    {
                      'filename': '.github/workflows/test.yml',
                      'status': 'removed',
                      'additions': 0,
                      'deletions': 1,
                      'patch': '@@ -1 +0 @@\n-test',
                    },
                  ],
                }
              : request.uri.path.endsWith('/commits/principale')
              ? {
                  'sha': invalidRevision ? '../fuori' : newRevision,
                  'commit': {
                    'message': '<b>Nuova revisione</b>\nDettaglio',
                    'committer': {'date': '2026-10-13T12:00:00Z'},
                  },
                }
              : {
                  'full_name': LiquidUpdateService.repository,
                  'default_branch': 'principale',
                };
          request.response.write(jsonEncode(data));
        }
      }
      await request.response.close();
    } catch (_) {
      // Annullare il client è una parte intenzionale della prova lenta.
    }
  });
  final uri = Uri.parse('http://127.0.0.1:${server.port}/');
  LiquidUpdateService create() => LiquidUpdateService(
    root: '${folder.path}/install',
    directory: '${folder.path}/downloads',
    state: '${folder.path}/state.json',
    api: uri,
    archive: uri,
    test: true,
  );
  final service = create();
  try {
    await service.init();
    await Future.wait([service.check(), service.check()]);
    check(
      apiCalls == 3,
      'verifiche concorrenti condividono tre sole richieste',
    );
    check(
      service.state['updateAvailable'] == true,
      'revisioni diverse indicano un aggiornamento',
    );
    check(
      service.state['installed']['dirty'] == true,
      'la build locale modificata rimane dichiarata',
    );
    check(
      service.state['latest']['message'] == '<b>Nuova revisione</b>',
      'il messaggio non è HTML interpretato dal servizio',
    );
    await service.check();
    check(
      service.state['phase'] == 'checked',
      'ETag 304 conserva metadati verificati',
    );
    check(
      service.state['comparison']['complete'] == true &&
          service.state['comparison']['runtimeChanged'] == false,
      'una modifica CI non diventa aggiornamento del desktop',
    );
    check(
      service.state['comparison']['files'][0]['patch'] == '@@ -1 +0 @@\n-test',
      'differenza reale del file disponibile nel changelog',
    );
    final before = archiveCalls;
    await service.download('../fuori');
    await service.download(oldRevision);
    check(archiveCalls == before, 'rifiuta revisioni arbitrarie e vecchie');
    await Future.wait([
      service.download(newRevision),
      service.download(newRevision),
    ]);
    check(
      archiveCalls == before + 1,
      'un solo download per richieste concorrenti',
    );
    final downloaded = File(
      '${folder.path}/downloads/Liquid-DE-$newRevision.zip',
    );
    check(
      service.state['phase'] == 'ready' && await downloaded.exists(),
      'archivio realmente salvato dopo verifica',
    );
    check(
      !await File('${folder.path}/NON_ESTRARRE').exists(),
      'nessun contenuto dell’archivio viene estratto',
    );
    check(
      service.state['history'].length == 1 &&
          service.state['history'][0]['sha256'].length == 64,
      'cronologia con SHA-256 e dimensione',
    );
    await service.download(newRevision);
    check(
      archiveCalls == before + 1,
      'riusa lo ZIP già verificato senza scaricarlo di nuovo',
    );
    await downloaded.writeAsString('cache danneggiata');
    await service.download(newRevision);
    check(
      archiveCalls == before + 2 && service.state['phase'] == 'ready',
      'ripara una cache danneggiata scaricando nuovamente',
    );
    await service.pause(7);
    check(
      service.state['paused'] == true,
      'pausa persistente di una settimana',
    );
    await service.check();
    check(
      service.state['phase'] == 'checked',
      'la verifica manuale funziona anche durante la pausa',
    );
    await service.pause(0);
    check(service.state['paused'] == false, 'ripresa degli aggiornamenti');
    status = 429;
    await service.check();
    check(
      service.state['error'] == 'http_429' &&
          service.state['retryAt'].isNotEmpty,
      'limite GitHub distinto da nessun aggiornamento',
    );
    check(
      service.state['latest']['revision'] == newRevision,
      'un errore di rete non cancella la revisione precedente',
    );
    status = 200;
    invalidRevision = true;
    await service.check();
    check(
      service.state['phase'] == 'error' &&
          service.state['latest']['revision'] == newRevision,
      'metadati malformati non sostituiscono il catalogo',
    );
    invalidRevision = false;
    await service.check();
    await downloaded.delete();
    invalidArchive = true;
    await service.download(newRevision);
    check(
      service.state['phase'] == 'error' && !await downloaded.exists(),
      'un archivio non ZIP non diventa pronto',
    );
    check(
      !await File('${downloaded.path}.part').exists(),
      'un download fallito non lascia file parziali',
    );
    invalidArchive = false;
    slow = true;
    final transfer = service.download(newRevision);
    for (var i = 0; i < 100 && service.state['received'] == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    check(
      service.state['received'] > 0,
      'annullamento durante un trasferimento reale',
    );
    service.cancel();
    await transfer;
    check(
      service.state['phase'] == 'cancelled' && !await downloaded.exists(),
      'annullamento non pubblica uno ZIP incompleto',
    );
    slow = false;
    await service.download(newRevision);
    check(
      service.state['phase'] == 'ready',
      'un nuovo download riesce dopo l’annullamento',
    );
    final restored = create();
    await restored.init();
    check(
      restored.state['history'].length == 1 &&
          restored.state['downloaded'] == true,
      'stato e cronologia sopravvivono al riavvio del servizio',
    );
    await restored.close();
    await manifest.delete();
    await service.check();
    check(
      service.state['installed'].isEmpty &&
          service.state['updateAvailable'] == false,
      'installazione non registrata non è dichiarata aggiornata',
    );
    await service.close();
    if (args.contains('--network')) {
      final real = LiquidUpdateService(
        root: folder.path,
        directory: '${folder.path}/real',
        state: '${folder.path}/real-state.json',
      );
      await real.init();
      await real.check();
      stdout.writeln('LIVE STATE ${jsonEncode(real.state)}');
      check(
        real.state['phase'] == 'checked',
        'API GitHub reale risponde con la revisione principale',
      );
      final revision = real.state['latest']['revision'] as String;
      await real.download(revision);
      check(
        real.state['phase'] == 'ready',
        'ZIP del repository reale scaricato e verificato',
      );
      stdout.writeln('GITHUB ${jsonEncode(real.state['latest'])}');
      stdout.writeln('ARCHIVIO ${jsonEncode(real.state['history'])}');
      final again = real.state['history'][0]['sha256'];
      await real.download(revision);
      check(
        real.state['phase'] == 'ready' &&
            real.state['history'][0]['sha256'] == again,
        'cache dell’archivio GitHub reale riutilizzata',
      );
      await real.close();
    }
    stdout.writeln('FINE $checks controlli passati');
  } finally {
    await service.close();
    await subscription.cancel();
    await server.close(force: true);
    await folder.delete(recursive: true);
  }
}
