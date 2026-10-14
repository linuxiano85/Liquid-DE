import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../minervad/lib/services/liquid_update_changes.dart';
import '../minervad/lib/services/liquid_update_service.dart';

var passed = 0;
void verify(bool value, String description) {
  if (!value) throw StateError(description);
  passed++;
  stdout.writeln('PASS $description');
}

Map<String, dynamic> comparison(List<Map<String, dynamic>> files) => {
  'status': 'ahead',
  'total_commits': 1,
  'commits': [
    {
      'sha': '2' * 40,
      'commit': {'message': 'Correzione\nDettaglio'},
    },
  ],
  'files': files,
};
Map<String, dynamic> file(String path, {String? previous}) => {
  'filename': path,
  'status': previous == null ? 'modified' : 'renamed',
  'additions': 1,
  'deletions': 1,
  'patch': '@@ -1 +1 @@\n-old\n+new',
  if (previous != null) 'previous_filename': previous,
};
Future<void> main() async {
  for (final entry in {
    'compositore/src/main.c': 'compositor',
    'minervad/lib/main.dart': 'daemon',
    'minerva-shell/files/File.qml': 'shell',
    'minerva-shell/native/main.cpp': 'native',
    'assets/icon.svg': 'integration',
    'docs/new.md': 'repository',
    '.github/workflows/build.yml': 'repository',
    'new-project/file': 'unclassified',
  }.entries) {
    verify(
      LiquidUpdateChanges.component(entry.key) == entry.value,
      'categoria ${entry.key}',
    );
  }
  final renamed = LiquidUpdateChanges.parse(
    comparison([file('minerva-shell/a.qml', previous: 'docs/a.md')]),
  );
  verify(
    renamed['components'].length == 2,
    'rinomina tra componenti coinvolge origine e destinazione',
  );
  verify(
    renamed['commits'][0]['message'].contains('\nDettaglio'),
    'messaggio completo del commit',
  );
  final incomplete = comparison(List.generate(300, (i) => file('docs/$i.md')));
  verify(
    LiquidUpdateChanges.parse(incomplete)['complete'] == false,
    'limite 300 file dichiarato incompleto',
  );
  final truncated = comparison([file('docs/a.md')])..['total_commits'] = 2;
  verify(
    LiquidUpdateChanges.parse(truncated)['complete'] == false,
    'commit mancanti dichiarati incompleti',
  );
  for (final path in ['../a', '/a', 'a//b', 'a/./b', 'a\\b', 'a\u0000b']) {
    var rejected = false;
    try {
      LiquidUpdateChanges.parse(comparison([file(path)]));
    } on FormatException {
      rejected = true;
    }
    verify(rejected, 'percorso rifiutato ${jsonEncode(path)}');
  }
  final large = file('docs/a.md')..['patch'] = 'x' * (256 * 1024 + 1);
  verify(
    LiquidUpdateChanges.parse(
          comparison([large]),
        )['files'][0]['patchAvailable'] ==
        false,
    'patch troppo grande esplicitamente indisponibile',
  );
  final tmp = await Directory.systemTemp.createTemp('liquid-update-timer-');
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var calls = 0;
  final listener = server.listen((request) async {
    calls++;
    request.response.write(
      jsonEncode(
        request.uri.path.contains('/commits/')
            ? {
                'sha': '2' * 40,
                'commit': {
                  'message': 'Timer',
                  'committer': {'date': ''},
                },
              }
            : {
                'full_name': LiquidUpdateService.repository,
                'default_branch': 'principale',
              },
      ),
    );
    await request.response.close();
  });
  final uri = Uri.parse('http://127.0.0.1:${server.port}/');
  final service = LiquidUpdateService(
    root: tmp.path,
    state: '${tmp.path}/state.json',
    directory: '${tmp.path}/downloads',
    api: uri,
    archive: uri,
    test: true,
    interval: const Duration(milliseconds: 600),
    delay: const Duration(milliseconds: 50),
  );
  try {
    await service.init();
    await service.check();
    service.startAutomatic();
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await service.check();
    final before = calls;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    verify(
      calls > before,
      'la verifica manuale non salta il successivo controllo periodico',
    );
    await service.pause(7);
    final paused = calls;
    await Future<void>.delayed(const Duration(milliseconds: 650));
    verify(calls == paused, 'nessuna richiesta automatica durante la pausa');
    await service.pause(0);
    await Future<void>.delayed(const Duration(milliseconds: 650));
    verify(calls > paused, 'la ripresa riattiva il controllo periodico');
    await service.close();
    final closed = calls;
    await Future<void>.delayed(const Duration(milliseconds: 650));
    verify(calls == closed, 'chiusura ferma i timer');
  } finally {
    await service.close();
    await listener.cancel();
    await server.close(force: true);
    await tmp.delete(recursive: true);
  }
  stdout.writeln('FINE $passed controlli passati');
}
