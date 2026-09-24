import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

/// Un programma del compositore compilato: in `build-native`, che è dove lo
/// mette `compositore/costruisci.sh`, o in `build` se qualcuno l'ha fatto a mano.
String _compilato(String nome) {
  for (final cartella in ['build-native', 'build']) {
    final f = File('../compositore/$cartella/$nome');
    if (f.existsSync()) return f.absolute.path;
  }
  return File('../compositore/build-native/$nome').absolute.path;
}

void main() {
  for (final shell in ['zsh', 'bash']) {
  test('$shell reale: automatici, false, OSC falso, password e shell figlia', () async {
    final processo = await Process.start(Platform.resolvedExecutable, [
      'run', 'bin/terminale.dart', '--pty', _compilato('minerva-pty'),
      '--shell', '/usr/bin/$shell', '--integrazione', Directory('../config/terminale').absolute.path,
    ], environment: {'ZDOTDIR': Directory('test/terminale/fixtures/zsh').absolute.path,
      'HISTFILE': '/dev/null'});
    final eventi = <Map<String, dynamic>>[];
    final errori = <String>[];
    final sub = processo.stdout.transform(utf8.decoder).transform(const LineSplitter())
        .listen((s) => eventi.add(jsonDecode(s) as Map<String, dynamic>));
    final err = processo.stderr.transform(utf8.decoder).listen(errori.add);
    addTearDown(() async {
      processo.stdin.writeln('{"t":"chiudi"}'); await processo.stdin.flush();
      await processo.exitCode.timeout(const Duration(seconds: 5), onTimeout: () {
        processo.kill(ProcessSignal.sigkill); return -1;
      });
      await sub.cancel(); await err.cancel();
    });
    Future<void> aspetta(bool Function() ok) async {
      final fine = DateTime.now().add(const Duration(seconds: 10));
      while (!ok() && DateTime.now().isBefore(fine)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(ok(), true, reason: '${errori.join()}\n${eventi.where((e) => e['t'] == 'bloccoAutomatico').toList()}');
    }
    List<Map<String, dynamic>> finiti() => eventi.where((e) => e['t'] == 'bloccoAutomatico' && e['stato'] == 'finito').toList();
    Future<Map<String, dynamic>> comando(String riga) async {
      final n = finiti().length;
      processo.stdin.writeln(jsonEncode({'t': 'comando', 'riga': riga}));
      await processo.stdin.flush();
      await aspetta(() => finiti().length > n);
      return finiti().last;
    }
    await aspetta(() => eventi.any((e) => e['t'] == 'blocco' && e['tipo'] == 'B'));
    var b = await comando(r"printf 'MINERVA_ONE\n'");
    expect(b['comando'], r"printf 'MINERVA_ONE\n'"); expect(b['uscita'], 'MINERVA_ONE'); expect(b['codice'], 0);
    b = await comando('false'); expect(b['codice'], 1);
    b = await comando(r"printf '\033]133;D;0\007'; false"); expect(b['codice'], 1);
    b = await comando("sh -c 'test -z \"\${MINERVA_BLOCCHI_CHIAVE-}\"'");
    expect(b['codice'], 0, reason: 'il segreto non è esportato ai figli');
    final n = finiti().length;
    processo.stdin.writeln(jsonEncode({'t': 'comando', 'riga': shell == 'zsh'
        ? "read -s 'segreto?PASSWORD_TEST: '" : "read -s -p 'PASSWORD_TEST: ' segreto"}));
    await processo.stdin.flush();
    await aspetta(() => eventi.any((e) => e['t'] == 'bloccoAutomatico' && e['stato'] == 'corsa' && (e['comando'] as String).startsWith('read -s')));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    processo.stdin.writeln(jsonEncode({'t': 'tasto', 'testo': 'SEGRETO_NON_ARCHIVIARE'}));
    processo.stdin.writeln('{"t":"tasto","k":"Return"}'); await processo.stdin.flush();
    await aspetta(() => finiti().length > n);
    expect(jsonEncode(eventi.where((e) => e['t'] == 'bloccoAutomatico').toList()), isNot(contains('SEGRETO_NON_ARCHIVIARE')));
  }, timeout: const Timeout(Duration(seconds: 40)));
  }
}
