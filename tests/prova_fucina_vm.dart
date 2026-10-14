/// Boot reale in KVM senza dischi o rete. Usa il medesimo initramfs dell'app.
/// dart tests/prova_fucina_vm.dart ROOT_QEMU KERNEL CARTELLA_RISULTATI
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../minervad/lib/services/fucina/prova_avvio.dart';

Future<void> main(List<String> args) async {
  if (args.length != 3) {
    stderr.writeln(
      'Servono root QEMU estratto, kernel e cartella risultati nuova.',
    );
    exitCode = 2;
    return;
  }
  final root = Directory(args[0]).absolute.path;
  for (final firmware in ['bios-256k.bin', 'linuxboot_dma.bin', 'kvmvapic.bin']) {
    if (!File('$root/usr/share/qemu/$firmware').existsSync()) {
      throw StateError('Fixture QEMU incompleta: manca $firmware.');
    }
  }
  final kernel = File(args[1]).absolute;
  final dest = Directory(args[2]);
  if (dest.existsSync() || !kernel.existsSync() || kernel.lengthSync() == 0) {
    throw StateError('Risultati già presenti o kernel assente/vuoto.');
  }
  final kvm = await Process.run('test', [
    '-r',
    '/dev/kvm',
    '-a',
    '-w',
    '/dev/kvm',
  ]);
  if (kvm.exitCode != 0)
    throw StateError('KVM non accessibile: nessun ripiego TCG per native.');
  await dest.create(recursive: true);
  final initrd = File('${dest.absolute.path}/prova-avvio.cpio');
  await initrd.writeAsBytes(initramfsMinimo());
  final command = comandoQemu(
    kernel: kernel.path,
    initramfs: initrd.path,
    kvm: true,
  );
  final watch = Stopwatch()..start();
  final process = await Process.start(
    '$root/usr/bin/qemu-system-x86_64',
    [...command.skip(1), '-nic', 'none', '-L', '$root/usr/share/qemu'],
    environment: {'LD_LIBRARY_PATH': '$root/usr/lib'},
  );
  final home = Platform.environment['HOME'] ?? '';
  String clean(String s) =>
      home.isEmpty ? s : s.replaceAll(home, '/home/utente');
  final journal = File('${dest.path}/console.log').openWrite();
  String record(String s) {
    journal.write(clean(s));
    return s;
  }

  var timeout = false;
  final timer = Timer(const Duration(seconds: 120), () {
    timeout = true;
    process.kill(ProcessSignal.sigkill); // solo QEMU creato da questa prova
  });
  final out = process.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .map(record)
      .join();
  final err = process.stderr
      .transform(const Utf8Decoder(allowMalformed: true))
      .map(record)
      .join();
  final code = await process.exitCode;
  timer.cancel();
  watch.stop();
  final log = clean('${await out}\n${await err}');
  await journal.flush();
  await journal.close();
  final result = {
    'ok': !timeout && riuscita(code, log.split('\n')),
    'returncode': code,
    'timeout': timeout,
    'seconds': watch.elapsedMilliseconds / 1000,
    'marker': log.contains(segno),
    'kernel': kernel.uri.pathSegments.last,
    'kvm': true,
    'disks': false,
    'network': false,
    'scope': 'decompressione, inizializzazione virtuale, esecuzione /init; non hardware reale o initramfs distro',
  };
  await File('${dest.path}/summary.json')
      .writeAsString('${const JsonEncoder.withIndent('  ').convert(result)}\n');
  stdout.writeln(jsonEncode(result));
  if (result['ok'] != true) exitCode = 1;
}
