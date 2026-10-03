import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:minervad/services/fucina/prova_avvio.dart';
import 'package:test/test.dart';

// La prova d'avvio in QEMU: l'initramfs minimo e la riga di QEMU.
//
// Che /init parta davvero lo si è visto il 1° ottobre 2026, su un 7.2.8
// tinyconfig in QEMU senza KVM: codice 99 e «FUCINA-AVVIO-OK» sulla seriale
// in un secondo e mezzo. Qui si prova che i byte siano quelli: un ELF che
// il kernel accetta, un cpio che il kernel sa aprire.
void main() {
  group('/init', () {
    final elf = initMinimo();
    int u16(int o) => ByteData.sublistView(elf).getUint16(o, Endian.little);
    int u32(int o) => ByteData.sublistView(elf).getUint32(o, Endian.little);
    int u64(int o) => ByteData.sublistView(elf).getUint64(o, Endian.little);

    test('è un ELF64 eseguibile per x86-64, con un solo segmento', () {
      expect(elf.sublist(0, 4), [0x7f, 0x45, 0x4c, 0x46]);
      expect(elf[4], 2, reason: '64 bit');
      expect(elf[5], 1, reason: 'little endian');
      expect(u16(16), 2, reason: 'ET_EXEC');
      expect(u16(18), 0x3e, reason: 'EM_X86_64');
      expect(u16(56), 1, reason: 'un segmento');
      expect(u32(64), 1, reason: 'PT_LOAD');
      expect(u32(68), 5, reason: 'leggibile ed eseguibile, non scrivibile');
      expect(u64(96), elf.length, reason: 'il segmento è tutto il file');
    });

    test('l\'ingresso è subito dopo le intestazioni', () {
      expect(u64(24), 0x400000 + 64 + 56);
    });

    test('lea punta al messaggio, che dice il segno', () {
      final codice = 64 + 56;
      final spostamento = ByteData.sublistView(elf)
          .getInt32(codice + 13, Endian.little);
      final messaggio = codice + 17 + spostamento;
      expect(utf8.decode(elf.sublist(messaggio)), '\n$segno\n');
    });

    test('scrive sulla porta di isa-debug-exit il valore che dà 99', () {
      // out 0xf4, al con al = 0x31: (0x31 << 1) | 1 = 99.
      final s = elf.toList();
      final i = List.generate(s.length - 3, (k) => k).firstWhere((k) =>
          s[k] == 0xb0 && s[k + 1] == 0x31 && s[k + 2] == 0xe6 &&
          s[k + 3] == 0xf4);
      expect(i, greaterThan(64 + 56));
      expect(codiceRiuscita, 99);
    });
  });

  group('l\'initramfs', () {
    test('è un cpio «newc» che cpio sa leggere', () async {
      if (Process.runSync('sh', ['-c', 'command -v cpio']).exitCode != 0) {
        markTestSkipped('manca cpio');
        return;
      }
      final d = Directory.systemTemp.createTempSync('fucina-cpio-');
      try {
        final f = File('${d.path}/prova.cpio')
          ..writeAsBytesSync(initramfsMinimo());
        final r = await Process.run('sh', ['-c', 'cpio -itv < "${f.path}"']);
        expect(r.exitCode, 0, reason: '${r.stderr}');
        final righe = '${r.stdout}';
        expect(righe, contains('dev/console'));
        expect(righe, matches(RegExp(r'^c.* 5,\s+1 .*dev/console$', multiLine: true)));
        expect(righe, matches(RegExp(r'^-rwxr-xr-x .* init$', multiLine: true)));
      } finally {
        d.deleteSync(recursive: true);
      }
    });

    test('ogni voce è allineata a quattro byte, e finisce con TRAILER', () {
      final b = initramfsMinimo();
      expect(b.length % 4, 0);
      expect(ascii.decode(b.sublist(0, 6)), '070701');
      expect(latin1.decode(b), contains('TRAILER!!!'));
    });
  });

  group('QEMU', () {
    test('con KVM il processore vero, senza l\'emulazione più larga', () {
      final con = comandoQemu(kernel: '/k', initramfs: '/i', kvm: true);
      expect(con, containsAllInOrder(['-accel', 'kvm', '-cpu', 'host']));
      final senza = comandoQemu(kernel: '/k', initramfs: '/i', kvm: false);
      expect(senza, containsAllInOrder(['-accel', 'tcg', '-cpu', 'max']));
    });

    test('non riparte, e ha la porta per uscire', () {
      final c = comandoQemu(kernel: '/k', initramfs: '/i', kvm: false);
      expect(c, contains('-no-reboot'));
      expect(c, contains('isa-debug-exit,iobase=0xf4,iosize=0x04'));
      expect(c.last, contains('panic=-1'));
      expect(c.last, contains('rdinit=/init'));
    });

    test('riuscita: il codice 99, o il segno sulla console', () {
      expect(riuscita(99, const []), isTrue);
      expect(riuscita(0, const ['Run /init', segno]), isTrue);
      expect(riuscita(0, const ['Kernel panic - not syncing: No working init']),
          isFalse, reason: 'panic=-1 e -no-reboot: QEMU esce con 0');
      expect(riuscita(1, const []), isFalse);
    });
  });
}

