import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:minervad/services/fucina/officina.dart';
import 'package:minervad/services/fucina/ricetta.dart';
import 'package:minervad/services/fucina/rilievo.dart';
import 'package:minervad/services/fucina/sorgenti.dart';
import 'package:test/test.dart';

// L'officina della Fucina, dall'inizio alla fine, senza un kernel vero.
//
// ── Come si prova una compilazione di un'ora in un secondo ────────────────
//
// I comandi della ricetta partono davvero — processi veri, con `setsid`
// vero — ma sono piccoli copioni di shell che fanno quello che farebbe il
// comando vero ai file che contano: `tar` crea l'albero, `make bzImage`
// lascia un'immagine e scrive le righe `CC`, `modules_install` crea la
// cartella dei moduli con il suo collegamento `build`. La rete è finta.
//
// Quello che si prova è l'officina, non `make`: l'ordine dei passi, il
// racconto, il salto dei passi già fatti, i rifiuti, e che cosa resta nella
// cartella d'uscita.
void main() {
  late Directory tana;
  late String lavoro;
  late String statoDir;
  late List<List<String>> lanciati;
  late int scaricamenti;
  late List<String> scaricati;
  var baseCachyosEsiste = false;
  late int verifiche;
  String? firmaRisposta;
  var rilascioDetto = '6.17.2-fucina-prova';
  var sommaPubblicata = '';
  var compilaDorme = false;
  // Kconfig finto: `olddefconfig` rimette a «n» quello che dipende da
  // qualcosa che manca. Qui, se vero, btrfs.
  var kconfigTogleBtrfs = false;
  // Come va la prova d'avvio: «parte», «panico», «manca» (QEMU non c'è).
  var qemu = 'parte';
  late List<String> qemuArgomenti;

  const contenuto = 'ARCHIVIO FINTO';

  setUpAll(() {
    final r = Process.runSync('sh', ['-c', 'printf "$contenuto" | sha256sum']);
    sommaPubblicata = '${r.stdout}'.split(' ').first;
  });

  setUp(() {
    tana = Directory.systemTemp.createTempSync('fucina-officina-');
    lavoro = '${tana.path}/lavoro';
    statoDir = '${tana.path}/stato';
    lanciati = [];
    scaricamenti = 0;
    scaricati = [];
    baseCachyosEsiste = false;
    verifiche = 0;
    firmaRisposta = null;
    rilascioDetto = '6.17.2-fucina-prova';
    compilaDorme = false;
    kconfigTogleBtrfs = false;
    qemu = 'parte';
    qemuArgomenti = [];
    // La configurazione di partenza, compressa come /proc/config.gz.
    File('${tana.path}/proc/config.gz')
      ..createSync(recursive: true)
      ..writeAsBytesSync(gzip.encode('CONFIG_HZ_300=y\nCONFIG_HZ=300\n'.codeUnits));
  });

  tearDown(() => tana.deleteSync(recursive: true));

  /// Il copione per ogni comando. `$@` sono gli argomenti veri.
  String copione(String eseguibile, List<String> a) {
    if (eseguibile == 'tar') {
      // Un albero piccolo ma vero dove conta: i Makefile e i Kconfig da cui
      // il passo «completa» ricava quale simbolo costruisce un modulo.
      final t = '${a[3]}/linux-6.17.2';
      return 'mkdir -p "$t/scripts" "$t/fs/fat" "$t/fs/btrfs" && '
          'echo "VERSION = 6" > "$t/Makefile" && '
          'printf "obj-\\\$(CONFIG_VFAT_FS) += vfat.o\\n" > "$t/fs/fat/Makefile" && '
          'printf "config VFAT_FS\\n\\ttristate \\"VFAT\\"\\n" > "$t/fs/fat/Kconfig" && '
          'printf "obj-\\\$(CONFIG_BTRFS_FS) := btrfs.o\\n" > "$t/fs/btrfs/Makefile" && '
          'printf "config BTRFS_FS\\n\\ttristate \\"Btrfs\\"\\n" > "$t/fs/btrfs/Kconfig"';
    }
    if (eseguibile.endsWith('/scripts/config')) {
      // Solo «--module»: è quello che scrive il passo «completa». Gli altri
      // verbi non scrivono niente, e la prova del controllo se ne accorge.
      final righe = [
        for (var i = 0; i + 1 < a.length; i++)
          if (a[i] == '--module') 'echo "CONFIG_${a[i + 1]}=m" >> .config',
      ];
      return righe.isEmpty ? 'exit 0' : righe.join(' && ');
    }
    if (eseguibile == 'qemu-system-x86_64') {
      qemuArgomenti = a;
      return switch (qemu) {
        'parte' => 'echo "Run /init as init process"; echo; '
            'echo FUCINA-AVVIO-OK; exit 99',
        'panico' => 'echo "Kernel panic - not syncing: No working init found."; '
            'exit 0',
        _ => 'echo "setsid: failed to execute qemu-system-x86_64" >&2; exit 127',
      };
    }
    if (eseguibile == 'cp') return 'cp -- "${a[a.length - 2]}" "${a.last}"';
    if (eseguibile == 'patch') return 'exit 0';
    if (eseguibile == 'make') {
      if (a.contains('kernelrelease')) return 'echo "$rilascioDetto"';
      if (a.contains('olddefconfig') && kconfigTogleBtrfs) {
        return 'sed -i "/CONFIG_BTRFS_FS=m/d" .config';
      }
      if (a.contains('defconfig')) {
        return 'printf "CONFIG_MODULES=y\\n" > .config';
      }
      if (a.contains('bzImage')) {
        return '${compilaDorme ? 'sleep 30; ' : ''}'
            'echo "  CC      kernel/fork.o"; echo "  CC [M]  drivers/x.o"; '
            'echo "  LD      vmlinux" ; echo VMLINUX > vmlinux; '
            'mkdir -p arch/x86/boot && echo IMMAGINE > arch/x86/boot/bzImage';
      }
      if (a.contains('modules_install')) {
        final dove = a.firstWhere((x) => x.startsWith('INSTALL_MOD_PATH='))
            .substring('INSTALL_MOD_PATH='.length);
        return 'mkdir -p "$dove/lib/modules/$rilascioDetto/kernel" && '
            'ln -s /da/qualche/parte "$dove/lib/modules/$rilascioDetto/build"';
      }
      return 'exit 0';
    }
    return 'echo "comando inatteso: $eseguibile" >&2; exit 1';
  }

  Officina officina() => Officina(
        lavoro: lavoro,
        statoDir: statoDir,
        radice: '${tana.path}/',
        spazioMinimo: 0,
        sorgenti: Sorgenti(
          testo: (u) async => u.host == 'github.com'
              ? '003f${'a' * 40} refs/heads/master\n0000'
              : '$sommaPubblicata  linux-6.17.2.tar.xz\n',
          esiste: (u) async =>
              u.path.contains('/sched/') || baseCachyosEsiste,
        ),
        scarica: (u, f, {progresso, annullato}) async {
          scaricamenti++;
          scaricati.add(u.pathSegments.last);
          await f.parent.create(recursive: true);
          await f.writeAsString(contenuto);
          progresso?.call(contenuto.length, contenuto.length);
          return null;
        },
        // La firma finta: quella vera va in rete e chiede gpg. La vera è
        // provata a parte, su un archivio vero, prima di questa PR.
        verificaFirma: (versione, archivio) async {
          verifiche++;
          return firmaRisposta;
        },
        conKvm: () async => false,
        lancia: (e, a, {workingDirectory}) {
          var eseguibile = e;
          var argomenti = a;
          if (e == 'setsid') {
            eseguibile = a.first;
            argomenti = a.sublist(1);
          }
          lanciati.add([eseguibile, ...argomenti]);
          final sh = ['sh', '-c', copione(eseguibile, argomenti)];
          // `setsid` vero, se lo chiede l'officina: è lui che rende possibile
          // fermare il gruppo intero, ed è quello che la prova di «ferma»
          // deve mettere alla prova.
          return e == 'setsid'
              ? Process.start('setsid', sh, workingDirectory: workingDirectory)
              : Process.start(sh.first, sh.sublist(1),
                  workingDirectory: workingDirectory);
        },
      );

  Rilievo rilievo({Set<String> essenziali = const {}}) => Rilievo(
        rilascio: '6.17.2-arch1-1',
        macchina: const {'nuclei': 4, 'attrezzi': []},
        dispositivi: const [
          Dispositivo(
              percorso: '/pci0000:00/0000:00:1b.0',
              modalias: 'pci:v1',
              bus: 'pci',
              driver: 'snd_hda_intel',
              modulo: 'snd_hda_intel'),
          Dispositivo(percorso: '/usb1/1-7', modalias: 'usb:v2', bus: 'usb'),
        ],
        moduli: {
          'snd_hda_intel': VoceModulo('snd_hda_intel', 'audio', null, false)
            ..fonti.add('legato'),
          for (final e in essenziali)
            e: VoceModulo(e, 'altro', null, false)..fonti.add('essenziale'),
        },
        avvio: Avvio('', '', essenziali, const {}, const []),
        modprobed: const DiarioModprobed('', {}),
        configPartenza: '/proc/config.gz',
        indiceRegole: 0,
        avvisi: const [],
      );

  Ricetta ricetta([Map<String, dynamic> extra = const {}]) {
    final s = Scelte.daJson({'nome': 'prova', 'versione': '6.17.2', ...extra});
    return calcola(rilievo(), s, Officina.cartellePer(s, lavoro), nuclei: 4);
  }

  /// Avvia e aspetta la fine, raccogliendo il racconto.
  Future<({Map<String, dynamic> fatto, List<Map<String, dynamic>> passi,
          List<String> righe})> gira(Officina o, Ricetta r) async {
    final fine = Completer<Map<String, dynamic>>();
    final passi = <Map<String, dynamic>>[];
    final righe = <String>[];
    o.ascolta(#prova, (tipo, dati) {
      if (tipo == 'passo') passi.add(dati);
      if (tipo == 'righe') righe.addAll((dati['righe'] as List).cast());
      if (tipo == 'fatto' && !fine.isCompleted) fine.complete(dati);
    });
    final avvio = o.avvia(r, rilievo());
    expect(avvio['ok'], isTrue, reason: '$avvio');
    final fatto = await fine.future.timeout(const Duration(seconds: 30));
    return (fatto: fatto, passi: passi, righe: righe);
  }

  test('una compilazione intera lascia un kernel pronto da installare',
      () async {
    final o = officina();
    final r = ricetta();
    final g = await gira(o, r);
    expect(g.fatto['ok'], isTrue, reason: '${g.fatto}');
    expect(g.fatto['rilascio'], '6.17.2-fucina-prova');

    final uscita = '$lavoro/uscita/6.17.2-fucina-prova';
    expect(File('$uscita/boot/vmlinuz-6.17.2-fucina-prova').readAsStringSync(),
        'IMMAGINE\n');
    expect(File('$uscita/boot/config-6.17.2-fucina-prova').existsSync(), isTrue);
    expect(File('$uscita/fucina.json').existsSync(), isTrue);
    expect(Link('$uscita/lib/modules/6.17.2-fucina-prova/build').existsSync(),
        isFalse,
        reason: 'l\'aiutante di root rifiuta i collegamenti: non devono '
            'arrivargli');

    // Ogni passo è partito ed è finito, nell'ordine della ricetta.
    final finiti = [
      for (final p in g.passi)
        if (p['stato'] == 'fatto') p['id'],
    ];
    expect(finiti, orderedEquals(r.passi.map((p) => p.id)));
  });

  test('la configurazione di partenza è quella del kernel in uso, scompattata',
      () async {
    final o = officina();
    await gira(o, ricetta());
    final config = File(
            '$lavoro/alberi/6.17.2-vanilla/linux-6.17.2/.config')
        .readAsStringSync();
    expect(config, contains('CONFIG_HZ=300'));
  });

  test('localmodconfig riceve il nostro elenco, in un file', () async {
    final o = officina();
    await gira(o, ricetta());
    final lsmod = File('$lavoro/lsmod-prova.txt').readAsStringSync();
    expect(lsmod, startsWith('Module'));
    expect(lsmod, contains('snd_hda_intel'));
    final screma = lanciati.firstWhere((c) => c.contains('localmodconfig'));
    expect(screma, contains('LSMOD=$lavoro/lsmod-prova.txt'));
  });

  test('un valore che non ha preso nel .config diventa un avviso', () async {
    // Il `scripts/config` finto non scrive niente: il nome del kernel non è
    // nel .config, e il controllo se ne deve accorgere.
    final o = officina();
    final g = await gira(o, ricetta());
    expect((g.fatto['avvisi'] as List).join('\n'), contains('LOCALVERSION'));
  });

  test('la seconda volta non riscarica e non riestrae', () async {
    final o = officina();
    await gira(o, ricetta());
    expect(scaricamenti, 1);
    lanciati.clear();
    final g = await gira(o, ricetta());
    expect(g.fatto['ok'], isTrue);
    expect(scaricamenti, 1, reason: 'l\'albero è pronto: niente da scaricare');
    expect(lanciati.where((c) => c.first == 'tar'), isEmpty);
    final saltati = [
      for (final p in g.passi)
        if (p['stato'] == 'saltato') p['id'],
    ];
    expect(saltati, ['scarica', 'estrai']);
  });

  test('CachyOS senza serie base: si applica solo BORE, e lo si dice',
      () async {
    final o = officina();
    final g = await gira(o, ricetta({'sorgente': 'cachyos'}));
    expect(g.fatto['ok'], isTrue, reason: '${g.fatto}');
    expect(scaricati, ['linux-6.17.2.tar.xz', '0001-bore-cachy.patch']);
    final patch = lanciati.where((c) => c.first == 'patch').toList();
    expect(patch, hasLength(2), reason: 'a secco e poi davvero');
    expect(patch.first, contains('--dry-run'));
    expect(g.righe.join('\n'), contains('solo lo scheduler BORE'));
  });

  test('le patch si scaricano da un commit preciso, e il commit resta scritto',
      () async {
    final o = officina();
    final g = await gira(o, ricetta({'sorgente': 'cachyos'}));
    expect(g.fatto['ok'], isTrue, reason: '${g.fatto}');
    final info = File('$lavoro/uscita/6.17.2-fucina-prova/fucina.json')
        .readAsStringSync();
    expect(info, contains('"commit": "${'a' * 40}"'));
    expect(info, contains('0001-bore-cachy.patch'));
  });

  test('CachyOS con la serie base: prima la base, poi BORE', () async {
    baseCachyosEsiste = true;
    final o = officina();
    final g = await gira(o, ricetta({'sorgente': 'cachyos'}));
    expect(g.fatto['ok'], isTrue, reason: '${g.fatto}');
    expect(scaricati.skip(1),
        ['0001-cachyos-base-all.patch', '0001-bore-cachy.patch']);
  });

  test('una firma che non torna ferma tutto e butta l\'archivio', () async {
    firmaRisposta = 'La firma di linux-6.17.2 non torna.';
    final o = officina();
    final g = await gira(o, ricetta());
    expect(g.fatto['ok'], isFalse);
    expect(g.fatto['errore'], contains('firma'));
    expect(File('$lavoro/archivi/linux-6.17.2.tar.xz').existsSync(), isFalse);
    expect(lanciati.where((c) => c.first == 'tar'), isEmpty,
        reason: 'un archivio non firmato non si apre');
  });

  test('la firma si verifica una volta per archivio, non a ogni compilazione',
      () async {
    final o = officina();
    await gira(o, ricetta());
    expect(verifiche, 1);
    // Albero da rifare (segno di «pronto» tolto), archivio già verificato.
    File('$lavoro/alberi/6.17.2-vanilla/.fucina-pronto').deleteSync();
    await gira(o, ricetta());
    expect(scaricamenti, 1);
    expect(verifiche, 1, reason: 'stesso archivio, stessa somma: già fatto');
  });

  test('chi riapre a metà vede i passi già fatti e la barra', () async {
    compilaDorme = true;
    final o = officina();
    final fine = Completer<void>();
    final a = Completer<void>();
    o.ascolta(#prova, (tipo, dati) {
      if (tipo == 'passo' && dati['id'] == 'compila' && dati['stato'] == 'via' &&
          !a.isCompleted) {
        a.complete();
      }
      if (tipo == 'fatto' && !fine.isCompleted) fine.complete();
    });
    o.avvia(ricetta(), rilievo());
    await a.future.timeout(const Duration(seconds: 20));
    final s = o.stato();
    expect(s['inCorso'], isTrue);
    expect((s['passi'] as Map)['screma'], 'fatto');
    expect((s['passi'] as Map)['compila'], 'via');
    expect(s['passo'], 'Compila');
    await o.ferma();
    await fine.future.timeout(const Duration(seconds: 15));
  });

  test('le righe CC si contano, e la misura si ricorda', () async {
    final o = officina();
    await gira(o, ricetta());
    final misure = File('$statoDir/misure.json').readAsStringSync();
    expect(misure, contains('"oggetti":2'));
  });

  test('i dispositivi attesi al primo avvio sono quelli con un driver',
      () async {
    final o = officina();
    await gira(o, ricetta());
    final attesi =
        File('$statoDir/attesi-6.17.2-fucina-prova.json').readAsStringSync();
    expect(attesi, contains('snd_hda_intel'));
    expect(attesi, isNot(contains('usb:v2')));
  });

  test('un kernel con un altro nome si ferma prima di impacchettare',
      () async {
    rilascioDetto = '6.17.2-fucina-prova-dirty';
    final o = officina();
    final g = await gira(o, ricetta());
    expect(g.fatto['ok'], isFalse);
    expect(g.fatto['errore'], contains('si chiama'));
    expect(Directory('$lavoro/uscita/6.17.2-fucina-prova').existsSync(),
        isFalse);
  });

  test('un archivio che non torna con la somma si butta', () async {
    final vera = sommaPubblicata;
    sommaPubblicata = '0' * 64;
    try {
      final o = officina();
      final g = await gira(o, ricetta());
      expect(g.fatto['ok'], isFalse);
      expect(g.fatto['errore'], contains('somma'));
      expect(File('$lavoro/archivi/linux-6.17.2.tar.xz').existsSync(), isFalse);
      expect(lanciati.where((c) => c.first == 'tar'), isEmpty,
          reason: 'un archivio che non torna non si apre');
    } finally {
      sommaPubblicata = vera;
    }
  });

  test('una seconda compilazione mentre ce n\'è una si rifiuta', () async {
    compilaDorme = true;
    final o = officina();
    final fine = Completer<void>();
    o.ascolta(#prova, (tipo, _) {
      if (tipo == 'fatto' && !fine.isCompleted) fine.complete();
    });
    expect(o.avvia(ricetta(), rilievo())['ok'], isTrue);
    final seconda = o.avvia(ricetta(), rilievo());
    expect(seconda['ok'], isFalse);
    expect(seconda['errore'], contains('6.17.2-fucina-prova'));
    await o.ferma();
    await fine.future.timeout(const Duration(seconds: 15));
  });

  test('fermare ferma davvero, anche nel mezzo di make', () async {
    compilaDorme = true;
    final o = officina();
    final fine = Completer<Map<String, dynamic>>();
    o.ascolta(#prova, (tipo, dati) {
      if (tipo == 'passo' && dati['id'] == 'compila' && dati['stato'] == 'via') {
        // Un attimo perché il processo parta davvero.
        Timer(const Duration(milliseconds: 300), o.ferma);
      }
      if (tipo == 'fatto' && !fine.isCompleted) fine.complete(dati);
    });
    final t = Stopwatch()..start();
    o.avvia(ricetta(), rilievo());
    final fatto = await fine.future.timeout(const Duration(seconds: 20));
    expect(fatto['ok'], isFalse);
    expect(fatto['annullato'], isTrue);
    expect(t.elapsed.inSeconds, lessThan(15),
        reason: 'make dormiva trenta secondi: fermare deve fermarlo');
    expect(o.inCorso, isFalse);
  });

  test('chi arriva a metà riceve le ultime righe', () async {
    final o = officina();
    await gira(o, ricetta());
    final s = o.stato();
    expect(s['inCorso'], isFalse);
    expect((s['righe'] as List).join('\n'), contains('kernel/fork.o'));
    expect((s['esito'] as Map)['ok'], isTrue);
  });

  test('senza spazio non si comincia nemmeno, e si dice quanto ne serve',
      () async {
    final o = Officina(
      lavoro: lavoro,
      statoDir: statoDir,
      radice: '${tana.path}/',
      // Più di quanto un disco abbia: il controllo deve dire di no.
      spazioMinimo: 1 << 62,
      scarica: (u, f, {progresso, annullato}) async {
        scaricamenti++;
        return null;
      },
      lancia: (e, a, {workingDirectory}) =>
          Process.start('sh', ['-c', 'exit 0']),
    );
    final g = await gira(o, ricetta());
    expect(g.fatto['ok'], isFalse);
    expect(g.fatto['errore'], contains('GB liberi'));
    expect(scaricamenti, 0, reason: 'lo si dice PRIMA di scaricare');
    expect(g.passi, isEmpty);
  });

  group('completare quello che localmodconfig non aggiunge', () {
    test('le scorte che la configurazione non ha si accendono dai Makefile',
        () async {
      final o = officina();
      final g = await gira(o, ricetta({'scorte': ['filesystem']}));
      expect(g.fatto['ok'], isTrue, reason: '${g.fatto}');
      final config = File('$lavoro/alberi/6.17.2-vanilla/linux-6.17.2/.config')
          .readAsStringSync();
      expect(config, contains('CONFIG_VFAT_FS=m'));
      expect(config, contains('CONFIG_BTRFS_FS=m'));
      final completa = lanciati.firstWhere((c) => c.contains('--module'));
      expect(completa, containsAllInOrder(['--module', 'BTRFS_FS']));
      expect(g.righe.join('\n'), contains('Da accendere'));
      // Gli altri filesystem della scorta non sono in questo albero
      // piccolo: si nominano, non si inventano.
      expect(g.righe.join('\n'), contains('Non trovo nei sorgenti'));
    });

    test('quello che Kconfig rimette a «n» si dice, per nome di modulo',
        () async {
      kconfigTogleBtrfs = true;
      final o = officina();
      final g = await gira(o, ricetta({'scorte': ['filesystem']}));
      expect(g.fatto['ok'], isTrue, reason: '${g.fatto}');
      final avvisi = (g.fatto['avvisi'] as List).join('\n');
      expect(avvisi, contains('Non sono entrati'));
      expect(avvisi, contains('btrfs'));
      expect(avvisi, isNot(contains('vfat,')));
    });

    test('anche gli essenziali: un disco d\'avvio su Btrfs con defconfig',
        () async {
      final o = officina();
      final s = Scelte.daJson(
          {'nome': 'prova', 'versione': '6.17.2', 'base': 'defconfig'});
      final ril = rilievo(essenziali: {'btrfs'});
      final r = calcola(ril, s, Officina.cartellePer(s, lavoro), nuclei: 4);
      final fine = Completer<Map<String, dynamic>>();
      o.ascolta(#e, (t, d) {
        if (t == 'fatto' && !fine.isCompleted) fine.complete(d);
      });
      o.avvia(r, ril);
      final fatto = await fine.future.timeout(const Duration(seconds: 30));
      expect(fatto['ok'], isTrue, reason: '$fatto');
      expect(File('$lavoro/alberi/6.17.2-vanilla/linux-6.17.2/.config')
          .readAsStringSync(), contains('CONFIG_BTRFS_FS=m'));
    });
  });

  group('la configurazione di partenza viaggia col kernel', () {
    test('accanto ai moduli, per ripartire da lei e non da quella scremata',
        () async {
      final o = officina();
      await gira(o, ricetta());
      final f = File('$lavoro/uscita/6.17.2-fucina-prova/lib/modules/'
          '6.17.2-fucina-prova/fucina-partenza.config');
      expect(f.readAsStringSync(), contains('CONFIG_HZ=300'));
    });

    test('da defconfig non c\'è, e quella di prima non resta a mentire',
        () async {
      final o = officina();
      await gira(o, ricetta());
      await gira(o, ricetta({'base': 'defconfig'}));
      expect(File('$lavoro/uscita/6.17.2-fucina-prova/lib/modules/'
              '6.17.2-fucina-prova/fucina-partenza.config')
          .existsSync(), isFalse);
    });
  });

  group('AutoFDO', () {
    test('il primo tempo mette da parte vmlinux e configurazione', () async {
      final o = officina();
      final g = await gira(
          o, ricetta({'compilatore': 'clang', 'lto': true, 'autofdo': true}));
      expect(g.fatto['ok'], isTrue, reason: '${g.fatto}');
      final p = '$lavoro/profili/6.17.2-fucina-prova';
      expect(File('$p/vmlinux').readAsStringSync(), 'VMLINUX\n');
      expect(File('$p/config').existsSync(), isTrue);
    });

    test('il secondo tempo senza profilo non comincia nemmeno', () async {
      final o = officina();
      final g = await gira(o, ricetta({
        'compilatore': 'clang', 'lto': true, 'profilo': '6.17.2-fucina-a',
        'nome': 'prova-afdo',
      }));
      expect(g.fatto['ok'], isFalse);
      expect(g.fatto['errore'], contains('Non trovo il profilo'));
      expect(scaricamenti, 0);
    });

    test('col profilo, make lo riceve e fucina.json ne scrive la somma',
        () async {
      final prof = File('$lavoro/profili/6.17.2-fucina-a/autofdo.prof')
        ..createSync(recursive: true)
        ..writeAsStringSync('PROFILO');
      rilascioDetto = '6.17.2-fucina-prova-afdo';
      final o = officina();
      final g = await gira(o, ricetta({
        'compilatore': 'clang', 'lto': true, 'profilo': '6.17.2-fucina-a',
        'nome': 'prova-afdo',
      }));
      expect(g.fatto['ok'], isTrue, reason: '${g.fatto}');
      final compila = lanciati.firstWhere((c) => c.contains('bzImage'));
      expect(compila, contains('CLANG_AUTOFDO_PROFILE=${prof.path}'));
      final info = File('$lavoro/uscita/6.17.2-fucina-prova-afdo/fucina.json')
          .readAsStringSync();
      expect(info, contains('"da": "6.17.2-fucina-a"'));
    });
  });

  group('la prova d\'avvio in QEMU', () {
    Map<String, dynamic> provaScritta() => (jsonDecode(
            File('$lavoro/uscita/6.17.2-fucina-prova/fucina.json')
                .readAsStringSync()) as Map)['provaAvvio'] as Map<String, dynamic>;

    test('un kernel che arriva a /init è «partito», e lo resta scritto',
        () async {
      final o = officina();
      final g = await gira(o, ricetta({'provaAvvio': true}));
      expect(g.fatto['ok'], isTrue, reason: '${g.fatto}');
      expect(g.passi.last['id'], 'avvia');
      expect(qemuArgomenti, containsAllInOrder([
        '-kernel', '$lavoro/uscita/6.17.2-fucina-prova/boot/vmlinuz-6.17.2-fucina-prova',
        '-initrd', '$lavoro/prova-avvio.cpio',
      ]));
      expect(qemuArgomenti, containsAllInOrder(['-accel', 'tcg']));
      expect(provaScritta()['ok'], isTrue);
      expect(File('$lavoro/prova-avvio.cpio').existsSync(), isTrue);
    });

    test('un kernel in panico ferma tutto e resta segnato «non partito»',
        () async {
      qemu = 'panico';
      final o = officina();
      final g = await gira(o, ricetta({'provaAvvio': true}));
      expect(g.fatto['ok'], isFalse);
      expect(g.fatto['errore'], contains('non arriva allo spazio utente'));
      expect(g.fatto['errore'], contains('No working init'));
      expect(provaScritta()['ok'], isFalse);
    });

    test('senza QEMU la prova non si fa, e lo si dice: non è un fallimento',
        () async {
      qemu = 'manca';
      final o = officina();
      final g = await gira(o, ricetta({'provaAvvio': true}));
      expect(g.fatto['ok'], isTrue, reason: '${g.fatto}');
      expect((g.fatto['avvisi'] as List).join(), contains('manca QEMU'));
      expect(provaScritta()['ok'], isNull);
    });

    test('un kernel per questo processore, senza KVM: un fallimento non dice '
        'niente', () async {
      qemu = 'panico';
      final o = officina();
      final g = await gira(o, ricetta({'provaAvvio': true, 'nativo': true}));
      expect(g.fatto['ok'], isTrue, reason: '${g.fatto}');
      expect(provaScritta()['ok'], isNull);
      expect((g.fatto['avvisi'] as List).join(), contains('KVM'));
    });

    test('senza la scelta, nessuna prova', () async {
      final o = officina();
      await gira(o, ricetta());
      expect(lanciati.where((c) => c.first == 'qemu-system-x86_64'), isEmpty);
    });
  });

  test('un ascoltatore che se ne va non riceve più niente', () async {
    final o = officina();
    var ricevuti = 0;
    o.ascolta(#andato, (_, _) => ricevuti++);
    o.smetti(#andato);
    await gira(o, ricetta());
    expect(ricevuti, 0);
  });
}

