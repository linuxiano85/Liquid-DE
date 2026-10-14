import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

void main() {
  test(
    'stderr grande e UTF8 malformato non blocca o abbatte il servizio',
    () async {
      final tmp = Directory.systemTemp.createTempSync('fucina-root-log-');
      try {
        final stub = File('${tmp.path}/pkexec')
          ..writeAsString('''#!/usr/bin/python3
import sys
sys.stderr.buffer.write(b'X' * (4 * 1024 * 1024))
sys.stderr.buffer.write(b'\\xff\\xfe\\nERRORE-FINALE\\n')
sys.exit(1)
''');
        await Process.run('chmod', ['755', stub.path]);
        final probe = File('${tmp.path}/probe.dart')
          ..writeAsString('''
import 'dart:convert';
import 'package:minervad/services/radice_service.dart';
class Fixture extends RadiceService {
  @override Future<bool> disponibile() async => true;
}
Future<void> main() async {
  print(jsonEncode(await Fixture().chiedi('permesso', [])));
}
''');
        final result = await Process.run(
          Platform.resolvedExecutable,
          [
            '--packages=${File('.dart_tool/package_config.json').absolute.path}',
            probe.path,
          ],
          environment: {'PATH': '${tmp.path}:/usr/bin:/bin'},
        ).timeout(const Duration(seconds: 20));
        expect(result.exitCode, 0, reason: '${result.stderr}');
        final r = jsonDecode('${result.stdout}') as Map;
        expect(r['ok'], isFalse);
        expect(r['error'], contains('ERRORE-FINALE'));
        expect((r['error'] as String).length, lessThanOrEqualTo(64 * 1024));
      } finally {
        tmp.deleteSync(recursive: true);
      }
    },
  );
}
