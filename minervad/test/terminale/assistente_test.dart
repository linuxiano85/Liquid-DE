import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:minervad/terminale/motore.dart';
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
  test('protocollo: anteprima, annullamento, conferma e controlli', () async {
    final controller = StreamController<List<int>>();
    final sink = IOSink(controller.sink);
    final eventi = <Map<String, dynamic>>[];
    final sub = controller.stream.transform(utf8.decoder)
        .transform(const LineSplitter()).listen((s) => eventi.add(jsonDecode(s) as Map<String, dynamic>));
    final motore = Motore(percorsoPty: '/assente', fuori: sink);
    Future<void> manda(Map<String, dynamic> m) async {
      motore.dallaFinestra(jsonEncode(m));
      await sink.flush();
      await Future<void>.delayed(Duration.zero);
    }
    await manda({'t': 'incolla', 'testo': 'echo uno\necho due'});
    expect(eventi.last['t'], 'confermaIncolla');
    expect(eventi.where((e) => e['t'] == 'incollato'), isEmpty);
    await manda({'t': 'annullaIncolla'});
    await manda({'t': 'confermaIncolla'});
    expect(eventi.where((e) => e['t'] == 'incollato'), isEmpty);
    await manda({'t': 'incolla', 'testo': 'abc\x1b[201~\nxyz'});
    expect(eventi.last['testo'], 'abc[201~\nxyz');
    await manda({'t': 'confermaIncolla'});
    expect(eventi.last['t'], 'incollato');
    final n = eventi.length;
    await manda({'t': 'confermaIncolla'});
    expect(eventi.length, n, reason: 'conferma consumabile una sola volta');
    await manda({'t': 'prepara', 'testo': 'echo ok\nfalse'});
    expect(eventi.last['t'], 'erroreIncolla');
    await manda({'t': 'prepara', 'testo': 'rm -rf /'});
    expect(eventi.last['t'], 'confermaIncolla');
    await manda({'t': 'prepara', 'testo': 'git status'});
    expect(eventi.last['t'], 'incollato');
    await manda({'t': 'misura', 'c': 'non un numero', 'r': 24});
    motore.dallaFinestra('{"t":"scorri","di":1e309}');
    await manda({'t': 'prepara', 'testo': 'x' * 4097});
    expect(eventi.last['t'], 'erroreIncolla');
    await sink.close();
    await sub.cancel();
  });

  test('PTY reale: predizione e inserimento senza Invio implicito', () async {
    final pty = _compilato('minerva-pty');
    final processo = await Process.start(Platform.resolvedExecutable, [
      'run', 'bin/terminale.dart', '--pty', pty,
      '--esegui', 'stty -echo; printf PRONTO; cat',
      '--dizionario', '../config/dizionario-comandi.json',
    ]);
    final eventi = <Map<String, dynamic>>[];
    final errori = <String>[];
    final sub = processo.stdout.transform(utf8.decoder).transform(const LineSplitter())
        .listen((s) => eventi.add(jsonDecode(s) as Map<String, dynamic>));
    final err = processo.stderr.transform(utf8.decoder).listen(errori.add);
    addTearDown(() async {
      processo.stdin.writeln('{"t":"chiudi"}');
      await processo.stdin.flush();
      await processo.exitCode.timeout(const Duration(seconds: 5), onTimeout: () {
        processo.kill(ProcessSignal.sigkill); return -1;
      });
      await sub.cancel(); await err.cancel();
    });
    Future<void> aspetta(bool Function() condizione) async {
      final fine = DateTime.now().add(const Duration(seconds: 10));
      while (!condizione() && DateTime.now().isBefore(fine)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(condizione(), isTrue, reason: errori.join());
    }
    String schermo() => eventi.where((e) => e['t'] == 'righe').map((e) => jsonEncode(e)).join();
    await aspetta(() => schermo().contains('PRONTO'));
    processo.stdin.writeln(jsonEncode({'t': 'predici', 'testo': 'git l'}));
    await processo.stdin.flush();
    await aspetta(() => eventi.any((e) => e['t'] == 'predizione'));
    expect(eventi.lastWhere((e) => e['t'] == 'predizione')['fantasma'], 'git log');
    processo.stdin.writeln(jsonEncode({'t': 'prepara', 'testo': 'MINERVA_PROVA_TESTO'}));
    await processo.stdin.flush();
    await aspetta(() => eventi.any((e) => e['t'] == 'incollato'));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(schermo(), isNot(contains('MINERVA_PROVA_TESTO')));
    processo.stdin.writeln('{"t":"tasto","k":"Return"}');
    await processo.stdin.flush();
    await aspetta(() => schermo().contains('MINERVA_PROVA_TESTO'));
  }, timeout: const Timeout(Duration(seconds: 30)));
}
