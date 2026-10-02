import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../minervad/lib/services/app_scanner.dart';
import '../minervad/lib/services/desktop_launcher.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> rejected(Future<dynamic> action) async {
  var failed = false;
  try { await action; } catch (_) { failed = true; }
  check(failed, 'Expected rejection');
}

Future<void> main() async {
  var tests = 0;
  final scanner = AppScanner();
  final folder = await Directory.systemTemp.createTemp('liquid-launcher-test-');
  final owner = Object();
  final other = Object();
  final path = '${folder.path}/demo.desktop';
  const content = '[Desktop Entry]\nType=Application\nName=Demo\nExec=printf harmless\n';
  final file = File(path);
  DesktopLauncher guard({DateTime Function()? clock, int capacity = 64, int perClient = 8,
                        Future<DesktopSnapshot> Function(String)? reader,
                        Duration readTimeout = const Duration(seconds: 5)}) => DesktopLauncher(
    parse: (path, data) => scanner.parseContent(path, data, launcherOnly: true),
    commandFor: (app) => app.needsTerminal ? 'terminal-wrapper ${app.exec}' : app.exec,
    clock: clock, capacity: capacity, perClient: perClient, reader: reader, readTimeout: readTimeout,
  );
  Future<void> test(String name, Future<void> Function() body) async {
    await file.writeAsString(content);
    await body();
    tests++;
    stdout.writeln('PASS $name');
  }
  try {
    await test('raw path or forged token does not authorize a launch', () async {
      await rejected(guard().approve(owner, path, ''));
      await rejected(guard().approve(owner, path, 'true'));
    });
    await test('preview does not run a non-executable desktop file; only approval creates a harmless marker', () async {
      final marker = '${folder.path}/marker';
      await file.writeAsString('[Desktop Entry]\nType=Application\nName=Demo\nExec=printf ok > "$marker"\n');
      await Process.run('chmod', ['644', path]);
      final service = guard();
      final preview = await service.prepare(owner, path);
      check(!await File(marker).exists(), 'Preparing must not start a process');
      check(preview['command'] == 'printf ok > "$marker"', 'Show the actual command');
      final launch = await service.approve(owner, path, preview['token'] as String);
      final result = await Process.run('sh', ['-c', launch.command]);
      check(result.exitCode == 0 && await File(marker).readAsString() == 'ok', 'Approved marker must run');
    });
    await test('same token cannot be consumed twice', () async {
      final service = guard(); final p = await service.prepare(owner, path);
      await service.approve(owner, path, p['token'] as String);
      await rejected(service.approve(owner, path, p['token'] as String));
    });
    await test('two concurrent approvals cannot both succeed', () async {
      final service = guard(); final p = await service.prepare(owner, path);
      var successes = 0;
      Future<void> attempt() async {
        try { await service.approve(owner, path, p['token'] as String); successes++; } catch (_) {}
      }
      await Future.wait([attempt(), attempt()]);
      check(successes == 1, 'Exactly one approval');
    });
    await test('another client cannot approve or cancel a token', () async {
      final service = guard(); final p = await service.prepare(owner, path);
      await rejected(service.approve(other, path, p['token'] as String));
      check(!service.cancel(other, p['token'] as String), 'Wrong-owner cancellation');
      await service.approve(owner, path, p['token'] as String);
    });
    await test('a token is tied to its requested path', () async {
      final service = guard(); final p = await service.prepare(owner, path);
      await rejected(service.approve(owner, '$path.other', p['token'] as String));
      await service.approve(owner, path, p['token'] as String);
    });
    await test('cancel and disconnect revoke all pending approvals', () async {
      final service = guard(); final p = await service.prepare(owner, path);
      check(service.cancel(owner, p['token'] as String), 'Cancel token');
      await rejected(service.approve(owner, path, p['token'] as String));
      final p2 = await service.prepare(owner, path);
      service.forget(owner);
      check(service.pendingCount == 0, 'Forget releases pending snapshots');
      await rejected(service.approve(owner, path, p2['token'] as String));
    });
    await test('expired consent cannot launch', () async {
      var now = DateTime.utc(2026, 10, 2);
      final service = guard(clock: () => now); final p = await service.prepare(owner, path);
      now = now.add(const Duration(seconds: 60));
      await rejected(service.approve(owner, path, p['token'] as String));
      check(service.pendingCount == 0, 'Expiration releases content');
    });
    await test('editing content consumes consent without launching the new command', () async {
      final service = guard(); final p = await service.prepare(owner, path);
      await file.writeAsString(content.replaceFirst('harmless', 'changed!'));
      await rejected(service.approve(owner, path, p['token'] as String));
      check(service.pendingCount == 0, 'Changed-file token cannot be retried');
    });
    await test('retargeting a symlink to identical content still requires a new consent', () async {
      final second = File('${folder.path}/second.desktop'); await second.writeAsString(content);
      final link = Link('${folder.path}/alias.desktop'); await link.create(path);
      final service = guard(); final p = await service.prepare(owner, link.path);
      check(p['resolvedPath'] == path, 'Preview shows canonical target');
      await link.delete(); await link.create(second.path);
      await rejected(service.approve(owner, link.path, p['token'] as String));
    });
    await test('a missing, non-regular or oversized file is rejected', () async {
      await rejected(guard().prepare(owner, '${folder.path}/missing.desktop'));
      final directory = Directory('${folder.path}/directory.desktop'); await directory.create();
      await rejected(guard().prepare(owner, directory.path));
      await file.writeAsBytes(List<int>.filled(DesktopLauncher.maxBytes + 1, 65));
      await rejected(guard().prepare(owner, path));
      final fifo = '${folder.path}/fifo.desktop'; await Process.run('mkfifo', [fifo]);
      await rejected(guard().prepare(owner, fifo));
    });
    await test('invalid path and invalid UTF-8 are rejected', () async {
      await rejected(guard().prepare(owner, 'relative.desktop'));
      await rejected(guard().prepare(owner, '$path\u0000.desktop'));
      await rejected(guard().prepare(owner, '$path.txt'));
      await file.writeAsBytes([255, 254, 253]);
      await rejected(guard().prepare(owner, path));
    });
    await test('malformed, non-Application and empty-command entries cannot get consent', () async {
      for (final invalid in [content.replaceFirst('Application', 'Link'),
                             content.replaceFirst('Type=Application\n', ''),
                             content.replaceFirst('Exec=printf harmless', 'Exec='),
                             'Name=Outside entry\nExec=echo ignored\n']) {
        await file.writeAsString(invalid);
        await rejected(guard().prepare(owner, path));
      }
    });
    await test('preview and approval preserve terminal wrapping and parsed field codes', () async {
      await file.writeAsString('$content' 'Terminal=true\nExec=printf "%U"\n');
      final service = guard(); final p = await service.prepare(owner, path);
      check(p['command'] == 'terminal-wrapper printf ""', 'Effective wrapped command');
      final launch = await service.approve(owner, path, p['token'] as String);
      check(launch.command == p['command'], 'Exact command shown is the command returned');
    });
    await test('NoDisplay hides a menu item but does not prevent an explicit confirmed launch', () async {
      final hidden = '$content' 'NoDisplay=true\n';
      check(scanner.parseContent(path, hidden) == null, 'NoDisplay still hides the menu item');
      await file.writeAsString(hidden);
      final service = guard(); final p = await service.prepare(owner, path);
      await service.approve(owner, path, p['token'] as String);
    });
    await test('per-client and global limits bound pending content', () async {
      final service = guard(capacity: 2, perClient: 1);
      await service.prepare(owner, path);
      await rejected(service.prepare(owner, path));
      await service.prepare(other, path);
      await rejected(service.prepare(Object(), path));
      check(service.pendingCount == 2, 'Hard capacity');
    });
    await test('disconnect during preparation cannot produce a late consent', () async {
      final pending = Completer<DesktopSnapshot>();
      final service = guard(reader: (_) => pending.future);
      final result = rejected(service.prepare(owner, path));
      service.forget(owner);
      pending.complete(DesktopSnapshot(path, Uint8List.fromList(utf8.encode(content))));
      await result;
      check(service.pendingCount == 0, 'Late prepare cannot restore a disconnected session');
    });
    await test('timeout does not release a still-blocked OS read slot', () async {
      final pending = Completer<DesktopSnapshot>();
      final service = guard(capacity: 1, reader: (_) => pending.future,
                            readTimeout: const Duration(milliseconds: 10));
      await rejected(service.prepare(owner, path));
      await rejected(service.prepare(Object(), path));
      pending.complete(DesktopSnapshot(path, Uint8List.fromList(utf8.encode(content))));
      await Future<void>.delayed(Duration.zero);
      final preview = await service.prepare(other, path);
      check(preview['token'] is String, 'Actual completion releases slot');
    });
    stdout.writeln('DESKTOP_LAUNCHER_TESTS_PASSED=$tests');
  } finally {
    await folder.delete(recursive: true);
  }
}
