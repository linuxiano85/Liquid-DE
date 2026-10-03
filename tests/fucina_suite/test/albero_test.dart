import 'dart:io';

import 'package:minervad/services/fucina/albero.dart';
import 'package:minervad/services/fucina/ricetta.dart';
import 'package:test/test.dart';

// L'albero dei sorgenti letto per sapere quale simbolo costruisce un modulo.
//
// È quello che permette alle scorte di essere vere anche partendo da
// defconfig, o da un kernel senza moduli: senza, localmodconfig toglie e
// non aggiunge, e «tutti i filesystem» diventava «quelli che c'erano già».
// Trovato sulla macchina virtuale di prova il 1° ottobre 2026.
//
// I Makefile e i Kconfig qui sotto sono pezzi veri del 7.2.8, accorciati.
void main() {
  group('i Makefile', () {
    test('obj-\$(CONFIG_X) += nome.o, anche con := e coi trattini', () {
      final m = simboliDaMakefile('''
obj-\$(CONFIG_VFAT_FS) += vfat.o
obj-\$(CONFIG_BTRFS_FS) := btrfs.o
obj-\$(CONFIG_USB_STORAGE)	+= usb-storage.o
''');
      expect(m['vfat'], {'VFAT_FS'});
      expect(m['btrfs'], {'BTRFS_FS'}, reason: 'fs/btrfs usa «:=»');
      expect(m['usb_storage'], {'USB_STORAGE'},
          reason: 'il nome del modulo ha i trattini già diventati «_»');
    });

    test('le righe spezzate, i commenti e le cartelle', () {
      final m = simboliDaMakefile('''
obj-\$(CONFIG_SND_HDA_INTEL) += snd-hda-intel.o \\
\tsnd-hda-extra.o # un commento: finto.o
obj-\$(CONFIG_FAT_FS) += fat/
obj-\$(CONFIG_X) += \$(altri-y)
''');
      expect(m['snd_hda_intel'], {'SND_HDA_INTEL'});
      expect(m['snd_hda_extra'], {'SND_HDA_INTEL'},
          reason: 'la riga continua dopo la barra');
      expect(m.containsKey('finto'), isFalse, reason: 'è nel commento');
      expect(m.keys, isNot(contains('fat')),
          reason: 'una cartella non è un modulo');
    });
  });

  group('i Kconfig', () {
    test('si tengono solo i tristate', () {
      final t = simboliTristate('''
config KVM_GUEST
\tbool "KVM Guest support (including kvmclock)"
\tdepends on PARAVIRT

config KVM_X86
\tdef_tristate KVM if (KVM_INTEL != n || KVM_AMD != n)

menuconfig BT
\ttristate "Bluetooth subsystem support"

config NR_CPUS
\tint "Maximum number of CPUs" if SMP && !MAXSMP
''');
      expect(t, {'KVM_X86', 'BT'});
    });

    test('kvm non è KVM_GUEST: un modulo viene solo da un tristate', () {
      // arch/x86/kernel/Makefile ha un kvm.o dentro il kernel, acceso da
      // KVM_GUEST (bool); arch/x86/kvm/Makefile ha il modulo kvm.
      final grezza = simboliDaMakefile('''
obj-\$(CONFIG_KVM_GUEST) += kvm.o kvmclock.o
obj-\$(CONFIG_KVM_X86) += kvm.o
''');
      expect(grezza['kvm'], {'KVM_GUEST', 'KVM_X86'});
      final buona = filtra(grezza, {'KVM_X86'});
      expect(buona['kvm'], {'KVM_X86'});
      expect(buona.containsKey('kvmclock'), isFalse);
    });
  });

  group('il confronto con il .config', () {
    const mappa = MappaModuli({
      'vfat': {'VFAT_FS'},
      'btrfs': {'BTRFS_FS'},
      'ext4': {'EXT4_FS'},
      'btintel': {'BT_INTEL', 'BT_INTEL_PCIE'},
    });

    test('presente se un simbolo è y o m, da accendere se nessuno lo è', () {
      final e = confronta(
          leggiConfig('CONFIG_EXT4_FS=y\nCONFIG_VFAT_FS=m\n'
              '# CONFIG_BTRFS_FS is not set\n'),
          mappa,
          ['ext4', 'vfat', 'btrfs', 'btintel', 'nvidia']);
      expect(e.mancanti, ['btintel', 'btrfs']);
      expect(e.daAccendere, ['BTRFS_FS', 'BT_INTEL', 'BT_INTEL_PCIE']);
      expect(e.sconosciuti, ['nvidia'],
          reason: 'un modulo esterno non lo costruisce nessun Makefile');
    });

    test('niente da fare se c\'è tutto', () {
      final e = confronta(leggiConfig('CONFIG_EXT4_FS=y\n'), mappa, ['ext4']);
      expect(e.mancanti, isEmpty);
      expect(e.daAccendere, isEmpty);
    });
  });

  group('un albero vero, in piccolo', () {
    late Directory tana;
    setUp(() => tana = Directory.systemTemp.createTempSync('fucina-albero-'));
    tearDown(() => tana.deleteSync(recursive: true));

    void scrivi(String rel, String testo) => File('${tana.path}/$rel')
      ..createSync(recursive: true)
      ..writeAsStringSync(testo);

    test('legge Makefile e Kconfig, e salta strumenti e altre architetture',
        () async {
      scrivi('fs/fat/Makefile', 'obj-\$(CONFIG_VFAT_FS) += vfat.o\n');
      scrivi('fs/fat/Kconfig', 'config VFAT_FS\n\ttristate "VFAT"\n');
      scrivi('arch/x86/kvm/Makefile', 'obj-\$(CONFIG_KVM_X86) += kvm.o\n');
      scrivi('arch/x86/kvm/Kconfig', 'config KVM_X86\n\tdef_tristate y\n');
      // Le altre architetture hanno moduli col nome uguale ai nostri.
      scrivi('arch/arm64/kvm/Makefile', 'obj-\$(CONFIG_KVM_ARM) += kvm.o\n');
      scrivi('arch/arm64/kvm/Kconfig', 'config KVM_ARM\n\ttristate "x"\n');
      scrivi('tools/qualcosa/Makefile', 'obj-\$(CONFIG_FINTO) += vfat.o\n');
      scrivi('arch/Kconfig', 'config FINTO\n\ttristate "x"\n');
      final m = await MappaModuli.leggi(tana.path);
      expect(m.simboli['vfat'], {'VFAT_FS'});
      expect(m.simboli['kvm'], {'KVM_X86'});
    });
  });
}

