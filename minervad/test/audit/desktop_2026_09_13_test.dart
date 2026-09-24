// Tre garanzie del compositore, provate in una sessione senza schermo
// (Codex, 13 settembre 2026): i modi FISICI dello schermo e non la geometria
// logica, il ritorno indietro degli schermi che sopravvive alla chiusura del
// pannello, e il canale che non si ferma più dietro un cliente che non legge
// (era C02: 203 ms di attesa; adesso una decina).
//
// Avvia un compositore vero con `WLR_BACKENDS=headless` e `MINERVA_PROVA=1`:
// non tocca la sessione viva.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:minervad/core/linux_files.dart';

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
  test('headless: physical modes, rollback without UI, nonblocking IPC', () async {
    final temp = LinuxFiles.privateTemp(Directory.systemTemp, 'minerva-desktop-fix-');
    Process? compositor;
    addTearDown(() async {
      if (compositor != null) {
        compositor.kill();
        try { await compositor.exitCode.timeout(const Duration(seconds: 3)); }
        on TimeoutException { compositor.kill(ProcessSignal.sigkill); await compositor.exitCode; }
      }
      await temp.delete(recursive: true);
    });
    final binary = _compilato('minerva-wayland');
    final ready = Completer<String>();
    compositor = await Process.start(binary, [], environment: {
      'MINERVA_PROVA': '1', 'MINERVA_SESSIONE': 'audit-fix',
      'WLR_BACKENDS': 'headless', 'WLR_HEADLESS_OUTPUTS': '2',
      'XDG_RUNTIME_DIR': temp.path, 'MINERVA_CONFIG_DIR': '${temp.path}/config',
      'XDG_CONFIG_HOME': '${temp.path}/config', 'HYPRLAND_INSTANCE_SIGNATURE': '',
    });
    compositor.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      if (line.startsWith('minerva-wayland: canale su ') && !ready.isCompleted) {
        ready.complete(line.substring('minerva-wayland: canale su '.length));
      }
    });
    final errors = <String>[];
    compositor.stderr.transform(utf8.decoder).listen((s) { if (errors.length < 50) errors.add(s); });
    final socket = await ready.future.timeout(const Duration(seconds: 10),
        onTimeout: () => throw StateError(errors.join()));
    Future<String> query(String command) async {
      final client = await Socket.connect(InternetAddress(socket, type: InternetAddressType.unix), 0);
      try {
        client.write('$command\n');
        return await client.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).first
            .timeout(const Duration(seconds: 3));
      } finally { client.destroy(); }
    }
    Future<Map<String, dynamic>> screen() async =>
        (jsonDecode((await query('schermi')).substring(3)) as List).first as Map<String, dynamic>;
    final before = await screen();
    final name = before['nome'];
    expect(await query('schermo-prova audit $name preferito 2'), 'ok');
    final scaled = await screen();
    expect(scaled['scala'], 2);
    expect(scaled['modoLarghezza'], before['modoLarghezza']);
    expect(scaled['larghezza'], (before['modoLarghezza'] as int) ~/ 2);
    expect(await query('schermo-conferma other $name'), startsWith('no '));
    // Ogni query chiude il proprio client: nessuna UI sopravvive alla richiesta.
    await Future<void>.delayed(const Duration(seconds: 16));
    expect((await screen())['scala'], before['scala']);
    expect(await query('schermo-conferma audit $name'), startsWith('no '));
    expect(await query('schermo-prova next $name preferito 2'), 'ok');
    expect(await query('schermo-conferma next $name'), 'ok');
    expect((await screen())['scala'], 2);
    expect(await query('schermo-prova undo $name preferito 1'), 'ok');
    expect(await query('schermo-annulla undo $name'), 'ok');
    expect((await screen())['scala'], 2);
    final slow = await Socket.connect(InternetAddress(socket, type: InternetAddressType.unix), 0);
    addTearDown(slow.destroy);
    slow.write(List.filled(1500, 'schermi\n').join());
    try { await slow.flush(); } catch (_) {}
    final time = Stopwatch()..start();
    expect(await query('schermi'), startsWith('ok ['));
    time.stop();
    print('IPC con lettore fermo: ${time.elapsedMilliseconds} ms');
    expect(time.elapsedMilliseconds, lessThan(150));
  }, timeout: const Timeout(Duration(seconds: 40)));
}
