import 'package:minervad/services/fucina/alias.dart';
import 'package:test/test.dart';

// L'indice dei moduli della Fucina: chi guida quale dispositivo.
//
// Il confronto è scritto a mano (niente RegExp) e decide che cosa resta nel
// kernel: un modello che combacia per sbaglio tiene un modulo inutile, uno
// che NON combacia per sbaglio lo toglie — e quello è un dispositivo che non
// funziona più. Le prove qui sotto sono le regole di `fnmatch(3)`, una per
// una, più i casi veri presi da un `modules.alias`.
void main() {
  group('il confronto di fnmatch', () {
    test('uguale è uguale, e basta un carattere per non esserlo', () {
      expect(combacia('pci:v1', 'pci:v1'), isTrue);
      expect(combacia('pci:v1', 'pci:v2'), isFalse);
      expect(combacia('pci:v1', 'pci:v12'), isFalse);
      expect(combacia('pci:v12', 'pci:v1'), isFalse);
    });

    test('la stella mangia qualunque sequenza, anche vuota', () {
      expect(combacia('pci:*', 'pci:'), isTrue);
      expect(combacia('pci:*', 'pci:v00008086d0000A0C8'), isTrue);
      expect(combacia('*', ''), isTrue);
      expect(combacia('a*b*c', 'aXXbYYc'), isTrue);
      expect(combacia('a*b*c', 'aXXbYY'), isFalse);
      expect(combacia('**', 'x'), isTrue);
    });

    test('la stella torna indietro quando serve', () {
      // Il caso che rompe i confronti ingenui: la prima «b» non è quella
      // giusta.
      expect(combacia('*bc', 'abcbc'), isTrue);
      expect(combacia('a*bc*d', 'abcXbcYd'), isTrue);
      expect(combacia('a*bc*d', 'abcXbcY'), isFalse);
    });

    test('il punto di domanda vale un carattere, non zero', () {
      expect(combacia('usb:v?', 'usb:vA'), isTrue);
      expect(combacia('usb:v?', 'usb:v'), isFalse);
      expect(combacia('usb:v?', 'usb:vAB'), isFalse);
    });

    test('gli insiemi, gli intervalli e la negazione', () {
      expect(combacia('acpi*:PNP0C0[9ABC]:*', 'acpi:PNP0C0A:'), isTrue);
      expect(combacia('acpi*:PNP0C0[9ABC]:*', 'acpi:PNP0C0D:'), isFalse);
      expect(combacia('x[0-9]', 'x7'), isTrue);
      expect(combacia('x[0-9]', 'xa'), isFalse);
      expect(combacia('x[!0-9]', 'xa'), isTrue);
      expect(combacia('x[^0-9]', 'x5'), isFalse);
      // Una «]» subito dopo l'apertura fa parte dell'insieme.
      expect(combacia('x[]a]', 'x]'), isTrue);
    });

    test('una parentesi che non si chiude vale come carattere', () {
      expect(combacia('a[b', 'a[b'), isTrue);
      expect(combacia('a[b', 'ab'), isFalse);
    });

    test('i caratteri speciali delle espressioni regolari sono caratteri', () {
      expect(combacia('of:N*T*Cfsl,imx6q-uart', 'of:NserialTuCfsl,imx6q-uart'),
          isTrue);
      expect(combacia('a.b', 'aXb'), isFalse);
      expect(combacia('a+b', 'a+b'), isTrue);
    });

    test('un modello cattivo non fa esplodere il tempo', () {
      final modello = '${List.filled(30, 'a*').join()}b';
      final testo = List.filled(200, 'a').join();
      final t = Stopwatch()..start();
      expect(combacia(modello, testo), isFalse);
      expect(t.elapsedMilliseconds, lessThan(500));
    });
  });

  group('i nomi dei moduli', () {
    test('trattino e trattino basso sono lo stesso modulo', () {
      expect(normalizza('snd-hda-intel'), 'snd_hda_intel');
      expect(normalizza(' hid_generic '), 'hid_generic');
    });

    test('dal percorso al nome, qualunque compressione', () {
      expect(nomeDaPercorso('kernel/sound/pci/hda/snd-hda-intel.ko.zst'),
          'snd_hda_intel');
      expect(nomeDaPercorso('kernel/fs/ext4/ext4.ko'), 'ext4');
      expect(nomeDaPercorso('kernel/drivers/nvme/host/nvme.ko.xz'), 'nvme');
    });
  });

  group('l\'indice', () {
    const alias = '''
# Aliases extracted from modules themselves.
alias pci:v00008086d0000A0C8sv*sd*bc*sc*i* snd_hda_intel
alias pci:v*d*sv*sd*bc01sc08i02* nvme
alias usb:v045Ep02EAd*dc*dsc*dp*ic*isc*ip*in* xpad
alias acpi*:PNP0C0A:* battery
alias hid:b0003g*v0000054Cp00000CE6 hid-playstation
riga rotta
alias troppo lunga per essere vera
''';
    const dep = '''
kernel/sound/pci/hda/snd-hda-intel.ko.zst: kernel/sound/hda/snd-hda-core.ko.zst
kernel/drivers/nvme/host/nvme.ko.zst: kernel/drivers/nvme/host/nvme-core.ko.zst
kernel/drivers/input/joystick/xpad.ko.zst:
''';
    const incorporati = '''
kernel/fs/ext4/ext4.ko
kernel/drivers/acpi/battery.ko
''';

    final i = IndiceAlias.daTesti(
        alias: alias, dep: dep, incorporati: incorporati);

    test('trova il driver giusto per il suo bus', () {
      expect(i.moduliPer('pci:v00008086d0000A0C8sv00001043sd00001F63bc04sc03i00'),
          {'snd_hda_intel'});
      expect(i.moduliPer('pci:v0000144Dd0000A808sv0000144Dsd0000A801bc01sc08i02'),
          {'nvme'});
      expect(i.moduliPer('usb:v045Ep02EAd0408dcFFdscFFdpFFicFFisc47ip01in00'),
          {'xpad'});
    });

    test('i modelli col bus a stella valgono per tutti', () {
      expect(i.moduliPer('acpi:PNP0C0A:'), {'battery'});
    });

    test('il nome col trattino arriva col trattino basso', () {
      expect(i.moduliPer('hid:b0003g0001v0000054Cp00000CE6'),
          {'hid_playstation'});
    });

    test('un dispositivo che nessuno guida non ha moduli', () {
      expect(i.moduliPer('pci:v0000DEADd0000BEEFsv0sd0bc99sc99i99'), isEmpty);
      expect(i.moduliPer(''), isEmpty);
    });

    test('le righe che non capisce le salta, senza cadere', () {
      expect(i.regole, 5);
    });

    test('sa dove sta ogni modulo, compresi gli incorporati', () {
      expect(i.percorsi['snd_hda_intel'],
          'kernel/sound/pci/hda/snd-hda-intel.ko.zst');
      expect(i.percorsi['ext4'], 'kernel/fs/ext4/ext4.ko');
      expect(i.incorporati, {'ext4', 'battery'});
    });

    test('un kernel senza moduli caricabili è un indice vuoto, non un errore',
        () {
      final vuoto = IndiceAlias.daTesti();
      expect(vuoto.regole, 0);
      expect(vuoto.moduliPer('pci:v1'), isEmpty);
    });
  });
}

