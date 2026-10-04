/// La prova d'avvio: il kernel appena compilato parte in QEMU, prima di
/// toccare /boot, e deve arrivare allo spazio utente.
///
/// ── Che cosa prova, e che cosa no ───────────────────────────────────────
///
/// Prova che il kernel si decomprime, inizializza memoria, processori,
/// interrupt e console, apre l'initramfs ed esegue il primo programma: cioè
/// che una configurazione scremata non ha tolto qualcosa senza cui il kernel
/// non arriva nemmeno a `/init`. È la metà dei «non parte».
///
/// Non prova i TUOI dischi: la macchina virtuale non ha il tuo NVMe, e
/// l'initramfs è il nostro, non quello di mkinitcpio. Che il disco d'avvio
/// abbia i suoi driver lo garantiscono gli essenziali del rilievo e il passo
/// «completa»; che il resto ci sia lo dice la verifica al primo avvio.
///
/// ── Perché un /init scritto a mano ──────────────────────────────────────
///
/// Un initramfs di prova vuole un programma da eseguire. Busybox statico non
/// c'è su ogni Arch, e un programma compilato al momento vorrebbe un
/// compilatore C configurato per il collegamento statico. Quello che serve è
/// così poco — scrivere una riga e spegnere — che si scrive direttamente in
/// codice macchina x86-64: un ELF di poco più di duecento byte, sempre
/// uguale, che non dipende da niente.
///
/// Fa tre cose:
///  1. scrive [segno] sulla console (la seriale di QEMU);
///  2. chiede il permesso sulla porta 0xf4 (`ioperm`) e ci scrive 0x31: è il
///     dispositivo `isa-debug-exit` di QEMU, che esce subito col codice
///     (0x31 << 1) | 1 = 99 — un codice che un kernel in panico non può dare;
///  3. se è ancora vivo, spegne (`reboot(POWER_OFF)`).
///
/// Un kernel che non arriva a /init va in panico, `panic=-1` lo fa
/// ripartire e `-no-reboot` chiude QEMU col codice 0, senza il segno.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Quello che /init scrive sulla console.
const String segno = 'FUCINA-AVVIO-OK';

/// Il codice d'uscita di QEMU quando /init ha scritto su `isa-debug-exit`.
const int codiceRiuscita = (0x31 << 1) | 1;

/// L'ELF di /init. Vedi il commento della libreria.
Uint8List initMinimo() {
  final messaggio = utf8.encode('\n$segno\n');
  final codice = <int>[
    0xb8, 0x01, 0x00, 0x00, 0x00, //       mov eax, 1        ; write
    0xbf, 0x01, 0x00, 0x00, 0x00, //       mov edi, 1        ; stdout = console
    0x48, 0x8d, 0x35, 0, 0, 0, 0, //       lea rsi, [rip+messaggio]
    0xba, messaggio.length, 0x00, 0x00, 0x00, // mov edx, lunghezza
    0x0f, 0x05, //                         syscall
    0xb8, 0xad, 0x00, 0x00, 0x00, //       mov eax, 173      ; ioperm
    0xbf, 0xf4, 0x00, 0x00, 0x00, //       mov edi, 0xf4
    0xbe, 0x01, 0x00, 0x00, 0x00, //       mov esi, 1
    0xba, 0x01, 0x00, 0x00, 0x00, //       mov edx, 1
    0x0f, 0x05, //                         syscall
    0xb0, 0x31, //                         mov al, 0x31
    0xe6, 0xf4, //                         out 0xf4, al      ; isa-debug-exit
    0xb8, 0xa9, 0x00, 0x00, 0x00, //       mov eax, 169      ; reboot
    0xbf, 0xad, 0xde, 0xe1, 0xfe, //       mov edi, 0xfee1dead
    0xbe, 0x69, 0x19, 0x12, 0x28, //       mov esi, 672274793
    0xba, 0xdc, 0xfe, 0x21, 0x43, //       mov edx, 0x4321fedc ; POWER_OFF
    0x45, 0x31, 0xd2, //                   xor r10d, r10d
    0x0f, 0x05, //                         syscall
    0xeb, 0xfe, //                         jmp $             ; non si torna
  ];
  // Lo spostamento di `lea`: dal byte dopo l'istruzione (offset 17) al
  // messaggio, che sta subito dopo il codice.
  final spostamento = codice.length - 17;
  codice.setRange(13, 17, _le32(spostamento));

  const intestazione = 64, programma = 56;
  const base = 0x400000;
  final tutto = intestazione + programma + codice.length + messaggio.length;
  final b = BytesBuilder();
  b.add([0x7f, 0x45, 0x4c, 0x46, 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
  b.add(_le16(2)); //                   ET_EXEC
  b.add(_le16(0x3e)); //                EM_X86_64
  b.add(_le32(1));
  b.add(_le64(base + intestazione + programma)); // l'ingresso
  b.add(_le64(intestazione)); //        e_phoff
  b.add(_le64(0)); //                   e_shoff
  b.add(_le32(0));
  b.add(_le16(intestazione));
  b.add(_le16(programma));
  b.add(_le16(1)); //                   un segmento
  b.add(_le16(0));
  b.add(_le16(0));
  b.add(_le16(0));
  // Un solo segmento, leggibile ed eseguibile, che è tutto il file.
  b.add(_le32(1)); //                   PT_LOAD
  b.add(_le32(5)); //                   R + X
  b.add(_le64(0));
  b.add(_le64(base));
  b.add(_le64(base));
  b.add(_le64(tutto));
  b.add(_le64(tutto));
  b.add(_le64(0x1000));
  b.add(codice);
  b.add(messaggio);
  return b.toBytes();
}

/// Una voce dell'archivio: cartella, file o dispositivo a caratteri.
class VoceCpio {
  final String nome;
  final int modo;
  final List<int> dati;
  final int maggiore;
  final int minore;
  const VoceCpio(this.nome, this.modo,
      {this.dati = const [], this.maggiore = 0, this.minore = 0});
}

/// L'archivio `cpio` nel formato «newc», quello che il kernel apre come
/// initramfs (Documentation/driver-api/early-userspace/buffer-format.rst).
Uint8List cpio(List<VoceCpio> voci) {
  final b = BytesBuilder();
  var ino = 1;
  void voce(String nome, int modo, List<int> dati, int mag, int min) {
    final n = utf8.encode(nome);
    String h(int v) => v.toRadixString(16).padLeft(8, '0');
    b.add(ascii.encode('070701${h(ino++)}${h(modo)}${h(0)}${h(0)}'
        '${h(modo & 0xF000 == 0x4000 ? 2 : 1)}${h(0)}${h(dati.length)}'
        '${h(0)}${h(0)}${h(mag)}${h(min)}${h(n.length + 1)}${h(0)}'));
    b.add(n);
    b.addByte(0);
    while (b.length % 4 != 0) {
      b.addByte(0);
    }
    b.add(dati);
    while (b.length % 4 != 0) {
      b.addByte(0);
    }
  }

  for (final v in voci) {
    voce(v.nome, v.modo, v.dati, v.maggiore, v.minore);
  }
  voce('TRAILER!!!', 0, const [], 0, 0);
  return b.toBytes();
}

/// L'initramfs della prova: `/dev/console` (anche se di solito il kernel ne
/// ha già uno suo, incorporato) e `/init`.
Uint8List initramfsMinimo() => cpio([
      const VoceCpio('dev', 0x4000 | 0x1ed),
      const VoceCpio('dev/console', 0x2000 | 0x180, maggiore: 5, minore: 1),
      VoceCpio('init', 0x8000 | 0x1ed, dati: initMinimo()),
    ]);

/// La riga di QEMU. Con KVM il processore vero (`-cpu host`): un kernel
/// compilato per QUESTO processore usa istruzioni che l'emulazione può non
/// avere. Senza, `-cpu max`: tutto quello che l'emulatore sa fare.
List<String> comandoQemu(
        {required String kernel,
        required String initramfs,
        required bool kvm}) =>
    [
      'qemu-system-x86_64',
      '-nodefaults',
      '-display', 'none',
      '-serial', 'stdio',
      '-no-reboot',
      '-m', '1024',
      '-smp', '2',
      if (kvm) ...['-accel', 'kvm', '-cpu', 'host']
      else ...['-accel', 'tcg', '-cpu', 'max'],
      '-device', 'isa-debug-exit,iobase=0xf4,iosize=0x04',
      '-kernel', kernel,
      '-initrd', initramfs,
      '-append', 'console=ttyS0 panic=-1 rdinit=/init',
    ];

/// Com'è andata, dal codice d'uscita di QEMU e da quello che ha scritto la
/// console. Il codice 99 lo dà solo /init; il segno sulla console vale anche
/// se `ioperm` non c'è (un kernel senza `X86_IOPL_IOPERM`).
bool riuscita(int codice, Iterable<String> righe) =>
    codice == codiceRiuscita || righe.any((r) => r.contains(segno));

List<int> _le16(int v) => [v & 0xff, (v >> 8) & 0xff];
List<int> _le32(int v) => [for (var i = 0; i < 4; i++) (v >> (8 * i)) & 0xff];
List<int> _le64(int v) => [for (var i = 0; i < 8; i++) (v >> (8 * i)) & 0xff];
