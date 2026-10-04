import 'package:minervad/services/fucina/catalogo.dart';
import 'package:minervad/services/fucina/ricetta.dart';
import 'package:minervad/services/fucina/rilievo.dart';
import 'package:test/test.dart';

// La ricetta della Fucina: dalle scelte al piano.
//
// Qui si prova quello che decide che cosa finisce nel kernel. Le prove che
// valgono di più sono i RIFIUTI — un nome che diventerebbe un percorso in
// /boot, un essenziale tolto, un preset che toglie l'audio a chi ha scelto
// anche «gioco» — perché un piano sbagliato si vede solo dopo un'ora di
// compilazione, o al riavvio.
void main() {
  /// Un rilievo finto, con un modulo per ogni caso che conta.
  Rilievo rilievo({bool modprobed = true, String config = '/proc/config.gz',
      bool gcc = true, Map<String, dynamic> macchina = const {},
      List<Map<String, dynamic>> attrezzi = const []}) {
    VoceModulo m(String nome, String famiglia, Set<String> fonti) =>
        VoceModulo(nome, famiglia, 'kernel/x/$nome.ko', false)
          ..fonti.addAll(fonti);
    final moduli = {
      for (final v in [
        m('nvme', 'dischi', {'legato', 'caricato', 'essenziale'}),
        m('btrfs', 'filesystem', {'caricato', 'essenziale'}),
        m('snd_hda_intel', 'audio', {'legato', 'caricato'}),
        m('amdgpu', 'video', {'legato', 'caricato'}),
        m('nft_ct', 'firewall', {'caricato'}),
        m('exfat', 'filesystem', {'modprobed'}),
        m('btusb', 'bluetooth', {'candidato'}),
      ])
        v.nome: v,
    };
    return Rilievo(
      rilascio: '6.17.2-arch1-1',
      macchina: {
        'nuclei': 12,
        'attrezzi': [
          {'nome': 'make', 'indispensabile': true, 'presente': true},
          {'nome': 'gcc', 'indispensabile': false, 'presente': gcc},
          {'nome': 'clang', 'indispensabile': false, 'presente': true},
          {'nome': 'flex', 'indispensabile': true, 'presente': true},
          ...attrezzi,
        ],
        ...macchina,
      },
      dispositivi: const [],
      moduli: moduli,
      avvio: Avvio('/dev/nvme0n1p2', 'btrfs', {'nvme', 'btrfs'},
          {'nvme': 'Il controller del disco di «/».'}, const []),
      modprobed: DiarioModprobed('/casa/.config/modprobed.db',
          modprobed ? {'exfat'} : const {}),
      configPartenza: config,
      indiceRegole: 3,
      avvisi: const [],
    );
  }

  const cartelle = Cartelle(
    albero: '/cache/fucina/alberi/6.17.2-vanilla/linux-6.17.2',
    uscita: '/cache/fucina/uscita/6.17.2-fucina-prova',
    lsmod: '/cache/fucina/lsmod-prova.txt',
  );

  Scelte scelte([Map<String, dynamic> extra = const {}]) =>
      Scelte.daJson({'nome': 'prova', 'versione': '6.17.2', ...extra});

  Ricetta ricetta([Map<String, dynamic> extra = const {}, Rilievo? r]) =>
      calcola(r ?? rilievo(), scelte(extra), cartelle, nuclei: 12);

  group('le scelte che arrivano dal canale', () {
    test('un nome di kernel buono', () {
      final s = scelte();
      expect(s.localversion, '-fucina-prova');
      expect(s.rilascio, '6.17.2-fucina-prova');
    });

    test('un nome che diventerebbe un percorso si rifiuta', () {
      for (final cattivo in ['../x', 'a/b', 'Prova', '-x', 'x-', '', 'a b',
                             'a\nb', 'x' * 25, 'àè', 'a.b']) {
        expect(() => Scelte.daJson({'nome': cattivo, 'versione': '6.17.2'}),
            throwsA(isA<SceltaNonValida>()), reason: '«$cattivo»');
      }
    });

    test('solo versioni rilasciate', () {
      for (final buona in ['6.17', '6.17.2', '6.6.110', '7.0']) {
        expect(versioneValida(buona), isTrue, reason: buona);
      }
      for (final cattiva in ['6', '6.17-rc3', '6.17.2-arch1', 'v6.17', '',
                             '6.17.2 ', '06.1', '6..1']) {
        expect(versioneValida(cattiva), isFalse, reason: '«$cattiva»');
      }
    });

    test('LTO senza Clang si rifiuta con una frase che dice perché', () {
      expect(
          () => scelte({'compilatore': 'gcc', 'lto': true}),
          throwsA(isA<SceltaNonValida>().having(
              (e) => e.messaggio, 'messaggio', contains('Clang'))));
      expect(scelte({'compilatore': 'clang', 'lto': true}).lto, isTrue);
    });

    test('sorgenti, basi e compilatori sconosciuti si rifiutano', () {
      expect(() => scelte({'sorgente': 'xanmod'}), throwsA(isA<SceltaNonValida>()));
      expect(() => scelte({'base': '/etc/passwd'}), throwsA(isA<SceltaNonValida>()));
      expect(() => scelte({'compilatore': 'tcc'}), throwsA(isA<SceltaNonValida>()));
    });

    test('scorte e preset sconosciuti si lasciano cadere, non si inventano',
        () {
      final s = scelte({
        'scorte': ['filesystem', 'inventata'],
        'preset': ['gaming', 'inventato'],
        'tolti': ['snd_hda_intel', 'nome con spazi', 42],
      });
      expect(s.scorte, {'filesystem'});
      expect(s.preset, {'gaming'});
      expect(s.tolti, {'snd_hda_intel'});
    });
  });

  group('i moduli', () {
    test('di serie si tiene tutto quello che ha una ragione vera', () {
      final r = ricetta();
      expect(r.moduli, containsAll(['nvme', 'btrfs', 'snd_hda_intel', 'amdgpu',
                                    'nft_ct', 'exfat']));
      expect(r.moduli, isNot(contains('btusb')),
          reason: 'un candidato si mostra, non si tiene da solo');
    });

    test('un candidato si tiene se lo si aggiunge', () {
      expect(ricetta({'aggiunti': ['btusb']}).moduli, contains('btusb'));
    });

    test('un modulo tolto a mano esce, e si dice perché', () {
      final r = ricetta({'tolti': ['snd_hda_intel']});
      expect(r.moduli, isNot(contains('snd_hda_intel')));
      expect(r.tolti['snd_hda_intel'], 'tolto a mano');
    });

    test('un essenziale non si toglie, e lo si dice', () {
      final r = ricetta({'tolti': ['nvme']});
      expect(r.moduli, contains('nvme'));
      expect(r.avvisi.join(), contains('«nvme» serve ad avviare'));
    });

    test('le scorte aggiungono moduli che oggi nessuno usa', () {
      final r = ricetta({'scorte': ['controller']});
      expect(r.moduli, containsAll(['xpad', 'hid_playstation', 'hid_nintendo']));
      expect(r.perFamiglia['controller'], greaterThan(0));
    });

    test('un modulo tolto a mano resta fuori anche se una scorta lo vuole', () {
      final r = ricetta({'scorte': ['controller'], 'tolti': ['xpad']});
      expect(r.moduli, isNot(contains('xpad')));
    });

    test('il file per localmodconfig ha la forma di lsmod', () {
      final righe = ricetta().fileLsmod.split('\n');
      expect(righe.first, startsWith('Module'));
      expect(righe.skip(1).map((l) => l.split(RegExp(r'\s+')).first),
          orderedEquals(ricetta().moduli));
    });
  });

  group('i preset', () {
    test('il server toglie l\'audio anche se è collegato', () {
      final r = ricetta({'preset': ['server']});
      expect(r.moduli, isNot(contains('snd_hda_intel')));
      expect(r.tolti['snd_hda_intel'], contains('preset'));
    });

    test('ma non se hai scelto anche il gioco: per togliere serve l\'unanimità',
        () {
      final r = ricetta({'preset': ['server', 'gaming']});
      expect(r.moduli, contains('snd_hda_intel'));
    });

    test('un preset non toglie mai un essenziale', () {
      // Un audio essenziale è strano, ma è il caso che prova la regola: la
      // famiglia la toglierebbe, l'essenziale vince.
      final ril = rilievo();
      ril.moduli['snd_hda_intel']!.fonti.add('essenziale');
      final r = calcola(ril, scelte({'preset': ['server']}), cartelle,
          nuclei: 12);
      expect(r.moduli, contains('snd_hda_intel'));
    });

    test('per i valori vince il più reattivo', () {
      final c = combinaPreset(['server', 'ufficio'])!;
      expect(c.hz, 300);
      expect(c.prelazione, 'voluntary');
      final g = combinaPreset(['server', 'gaming'])!;
      expect(g.hz, 1000);
      expect(g.prelazione, 'full');
      expect(g.scorte, contains('controller'));
      expect(g.togliFamiglie, isEmpty);
    });

    test('nessun preset, nessun cambiamento al tick', () {
      expect(combinaPreset([]), isNull);
      final r = ricetta();
      expect(r.impostazioni.map((i) => i.simbolo), isNot(contains('HZ')));
    });

    test('un modulo aggiunto a mano vince sul preset che toglie la sua famiglia',
        () {
      final ril = rilievo();
      ril.moduli['btusb']!.fonti
        ..clear()
        ..add('candidato');
      final r = calcola(
          ril, scelte({'preset': ['server'], 'aggiunti': ['btusb']}), cartelle,
          nuclei: 12);
      expect(r.moduli, contains('btusb'));
    });

    test('nel choice della prelazione c\'è anche PREEMPT_LAZY, e si spegne', () {
      // Trovato compilando davvero il 7.2: senza nominare PREEMPT_LAZY, due
      // voci accese nello stesso choice e Kconfig teneva quella di prima.
      final v = {
        for (final i in ricetta({'preset': ['gaming']}).impostazioni)
          i.simbolo: i.valore,
      };
      expect(v['PREEMPT'], 'y');
      expect(v['PREEMPT_LAZY'], 'n');
      expect(v['TRANSPARENT_HUGEPAGE_ALWAYS'], 'n');
    });

    test('nel choice del tick se ne accende uno e si spengono gli altri', () {
      final r = ricetta({'preset': ['gaming']});
      final v = {for (final i in r.impostazioni) i.simbolo: i.valore};
      expect(v['HZ_1000'], 'y');
      expect(v['HZ_250'], 'n');
      expect(v['HZ_300'], 'n');
      expect(v['HZ_100'], 'n');
      expect(v['HZ'], '1000');
      expect(v['PREEMPT'], 'y');
      expect(v['PREEMPT_VOLUNTARY'], 'n');
    });

    test('ogni valore di ogni preset ha scritto il suo perché', () {
      for (final p in presets) {
        for (final i in [...p.extra, ...combinaPreset([p.id])!.impostazioni]) {
          expect(i.perche.trim(), isNotEmpty, reason: '${p.id}: ${i.simbolo}');
        }
      }
    });
  });

  group('il piano', () {
    test('il nome del kernel va nel .config', () {
      final v = {for (final i in ricetta().impostazioni) i.simbolo: i.valore};
      expect(v['LOCALVERSION'], '-fucina-prova');
      expect(v['LOCALVERSION_AUTO'], 'n');
    });

    test('i comandi sono elenchi di argomenti, mai righe per una shell', () {
      for (final p in ricetta({'sorgente': 'cachyos', 'preset': ['gaming']}).passi) {
        if (p.comando.isEmpty) continue;
        expect(p.comando.first, isNot(anyOf('sh', 'bash', 'env')), reason: p.id);
        expect(p.comando, isNot(contains('-c')), reason: p.id);
      }
    });

    test('CachyOS aggiunge le patch, vanilla no', () {
      expect(ricetta().passi.map((p) => p.id), isNot(contains('patch')));
      expect(ricetta({'sorgente': 'cachyos'}).passi.map((p) => p.id),
          contains('patch'));
    });

    test('Clang passa LLVM=1 a OGNI make, non solo alla compilazione', () {
      final r = ricetta({'compilatore': 'clang'});
      for (final p in r.passi.where((p) =>
          p.comando.isNotEmpty && p.comando.first == 'make')) {
        expect(p.comando, contains('LLVM=1'), reason: p.id);
      }
    });

    test('ccache entra come compilatore, se c\'è', () {
      final r = calcola(rilievo(), scelte(), cartelle, nuclei: 4, ccache: true);
      final compila = r.passi.firstWhere((p) => p.id == 'compila');
      expect(compila.comando, containsAllInOrder(['make', 'CC=ccache gcc', '-j4']));
    });

    test('localmodconfig legge il NOSTRO elenco, non lsmod', () {
      final screma = ricetta().passi.firstWhere((p) => p.id == 'screma');
      expect(screma.comando, contains('LSMOD=${cartelle.lsmod}'));
      expect(screma.comando.last, 'localmodconfig');
    });

    test('i moduli si installano nella cartella d\'uscita, non nel sistema', () {
      final m = ricetta().passi.firstWhere((p) => p.id == 'moduli');
      expect(m.comando, contains('INSTALL_MOD_PATH=${cartelle.uscita}'));
    });

    test('senza la configurazione in uso si parte da defconfig, e lo si dice',
        () {
      final r = ricetta(const {}, rilievo(config: ''));
      final base = r.passi.firstWhere((p) => p.id == 'base');
      expect(base.comando, ['make', 'defconfig']);
      expect(r.avvisi.join(), contains('defconfig'));
    });

    test('un compilatore che manca si dice prima di partire', () {
      final r = ricetta(const {}, rilievo(gcc: false));
      expect(r.avvisi.join(), contains('gcc'));
    });

    test('la prova veloce avverte che sched_ext non ci sarà', () {
      final r = ricetta({'provaVeloce': true});
      expect(r.avvisi.join(), contains('sched_ext'));
      final v = {for (final i in r.impostazioni) i.simbolo: i.valore};
      expect(v['DEBUG_INFO_NONE'], 'y');
      expect(v['DEBUG_INFO_BTF'], 'n');
    });
  });

  group('Clang: quello che non si è scelto si spegne per nome', () {
    // La configurazione di CachyOS porta ThinLTO, AutoFDO e Propeller
    // accesi: partendo da lì con Clang restavano accesi anche a chi non li
    // aveva scelti. Trovato rileggendo la catena il 1° ottobre 2026.
    Map<String, String> valori(Map<String, dynamic> extra) => {
          for (final i in ricetta(extra).impostazioni) i.simbolo: i.valore,
        };

    test('Clang senza LTO: LTO_NONE acceso, tutte le altre voci spente', () {
      final v = valori({'compilatore': 'clang'});
      expect(v['LTO_NONE'], 'y');
      expect(v['LTO_CLANG_THIN'], 'n');
      expect(v['LTO_CLANG_FULL'], 'n');
      expect(v['LTO_CLANG_THIN_DIST'], 'n');
    });

    test('Clang con LTO: THIN acceso, e anche THIN_DIST (7.x) spento', () {
      final v = valori({'compilatore': 'clang', 'lto': true});
      expect(v['LTO_CLANG_THIN'], 'y');
      expect(v['LTO_NONE'], 'n');
      expect(v['LTO_CLANG_THIN_DIST'], 'n');
    });

    test('Clang senza profilo spegne AutoFDO e Propeller', () {
      final v = valori({'compilatore': 'clang'});
      expect(v['AUTOFDO_CLANG'], 'n');
      expect(v['PROPELLER_CLANG'], 'n');
    });

    test('con GCC non si nominano: Kconfig li spegne da solo', () {
      final v = valori(const {});
      expect(v.containsKey('AUTOFDO_CLANG'), isFalse);
      expect(v.containsKey('LTO_NONE'), isFalse);
    });

    test('il choice di LTO si guarda per gruppo, THIN_DIST compreso', () {
      expect(sceltePerGruppo.any((g) => g.contains('LTO_CLANG_THIN_DIST')),
          isTrue);
    });

    test('LLVM=1 vuole anche lld e gli attrezzi di llvm: se mancano si dice',
        () {
      final r = calcola(
          rilievo(attrezzi: [
            {'nome': 'lld', 'indispensabile': false, 'presente': false},
            {'nome': 'llvm', 'indispensabile': false, 'presente': false},
          ]),
          scelte({'compilatore': 'clang'}),
          cartelle,
          nuclei: 4);
      expect(r.avvisi.join(), contains('pacman -S --needed lld llvm'));
    });

    test('senza pahole si avverte che BTF (e sched_ext) non ci sarà', () {
      final r = calcola(
          rilievo(attrezzi: [
            {'nome': 'pahole', 'indispensabile': false, 'presente': false},
          ]),
          scelte(),
          cartelle,
          nuclei: 4);
      expect(r.avvisi.join(), contains('pahole'));
      expect(r.avvisi.join(), contains('sched_ext'));
    });
  });

  group('AutoFDO: il kernel su misura del tuo uso', () {
    test('senza Clang si rifiuta, e si dice perché', () {
      expect(
          () => scelte({'autofdo': true}),
          throwsA(isA<SceltaNonValida>()
              .having((e) => e.messaggio, 'messaggio', contains('Clang'))));
    });

    test('il profilo è il NOME di un kernel nostro, mai un percorso', () {
      for (final cattivo in ['/tmp/x.prof', '../../etc/passwd',
                             '6.17.2-arch1-1', '6.17.2-fucina-a/b']) {
        expect(() => scelte({'compilatore': 'clang', 'profilo': cattivo}),
            throwsA(isA<SceltaNonValida>()), reason: cattivo);
      }
      final s = scelte({'compilatore': 'clang', 'profilo': '6.17.2-fucina-a'});
      expect(s.autofdo, isTrue, reason: 'col profilo AutoFDO è acceso');
    });

    test('il primo tempo accende AUTOFDO_CLANG e non passa nessun profilo', () {
      final r = ricetta({'compilatore': 'clang', 'lto': true, 'autofdo': true});
      final v = {for (final i in r.impostazioni) i.simbolo: i.valore};
      expect(v['AUTOFDO_CLANG'], 'y');
      for (final p in r.passi) {
        expect(p.comando.any((a) => a.startsWith('CLANG_AUTOFDO_PROFILE')),
            isFalse, reason: p.id);
      }
      expect(r.passi.firstWhere((p) => p.id == 'impacchetta').spiega,
          contains('vmlinux'));
    });

    test('il secondo tempo passa il profilo a OGNI make, identico', () {
      const c = Cartelle(
        albero: '/a',
        uscita: '/u',
        lsmod: '/l',
        profilo: '/cache/fucina/profili/6.17.2-fucina-a/autofdo.prof',
      );
      final r = calcola(rilievo(),
          scelte({'compilatore': 'clang', 'lto': true,
                  'profilo': '6.17.2-fucina-a'}),
          c, nuclei: 4, ccache: true);
      final make = r.passi
          .where((p) => p.comando.isNotEmpty && p.comando.first == 'make')
          .toList();
      expect(make, isNotEmpty);
      for (final p in make) {
        expect(p.comando,
            contains('CLANG_AUTOFDO_PROFILE=${c.profilo}'), reason: p.id);
        expect(p.comando.where((a) => a.startsWith('CC=')), isEmpty,
            reason: 'ccache non guarda il profilo: riuserebbe gli oggetti '
                'compilati senza');
      }
      // E le parti comuni sono le stesse in ogni invocazione.
      final prefissi = {
        for (final p in make)
          p.comando.where((a) => a.contains('=') && !a.startsWith('LSMOD=') &&
              !a.startsWith('INSTALL_MOD')).join(' '),
      };
      expect(prefissi, hasLength(1), reason: '$prefissi');
    });

    test('AutoFDO senza LTO avverte che rende meno', () {
      final r = ricetta({'compilatore': 'clang', 'autofdo': true});
      expect(r.avvisi.join(), contains('ThinLTO'));
    });

    test('su uno Zen 3 con BRS si accende il campionamento dei salti', () {
      final r = calcola(
          rilievo(macchina: {
            'profilo': {'possibile': true, 'tipo': 'amd-brs', 'perche': ''},
          }),
          scelte({'compilatore': 'clang', 'lto': true, 'autofdo': true}),
          cartelle,
          nuclei: 4);
      final v = {for (final i in r.impostazioni) i.simbolo: i.valore};
      expect(v['PERF_EVENTS_AMD_BRS'], 'y');
    });

    test('se qui il profilo non si può registrare, il primo tempo lo dice', () {
      final r = calcola(
          rilievo(macchina: {
            'profilo': {
              'possibile': false,
              'tipo': '',
              'perche': 'Questo AMD non ha un registro dei salti.',
            },
          }),
          scelte({'compilatore': 'clang', 'lto': true, 'autofdo': true}),
          cartelle,
          nuclei: 4);
      expect(r.avvisi.join(), contains('non si può registrare'));
      expect(r.avvisi.join(), contains('registro dei salti'));
    });
  });

  group('su misura dentro il kernel', () {
    Map<String, String> v(Map<String, dynamic> macchina) => {
          for (final i in suMisura(macchina)) i.simbolo: i.valore,
        };

    test('NR_CPUS: la potenza di due sopra i processori possibili', () {
      expect(v({'cpuPossibili': 12, 'nuclei': 12})['NR_CPUS'], '16');
      expect(v({'cpuPossibili': 16, 'nuclei': 16})['NR_CPUS'], '16');
      expect(v({'cpuPossibili': 24, 'nuclei': 16})['NR_CPUS'], '32',
          reason: 'i possibili contano anche se oggi non sono accesi');
      expect(v({'cpuPossibili': 1, 'nuclei': 1})['NR_CPUS'], '2',
          reason: 'sotto 2 Kconfig non scende');
      expect(v({'cpuPossibili': 16})['MAXSMP'], 'n',
          reason: 'con MAXSMP il numero è fisso a 8192');
    });

    test('NR_CPUS non si tocca oltre 512, né senza una misura', () {
      expect(v({'cpuPossibili': 600}).containsKey('NR_CPUS'), isFalse);
      expect(v(const {}).containsKey('NR_CPUS'), isFalse);
    });

    test('NUMA si spegne solo con un nodo misurato', () {
      expect(v({'nodiNuma': 1})['NUMA'], 'n');
      expect(v({'nodiNuma': 2}).containsKey('NUMA'), isFalse);
      expect(v({'nodiNuma': 0}).containsKey('NUMA'), isFalse,
          reason: 'zero vuol dire «non so»');
    });

    test('su Intel si spengono le funzioni che esistono solo su AMD', () {
      final x = v({'fornitore': 'GenuineIntel'});
      expect(x['AMD_IOMMU'], 'n');
      expect(x['AMD_MEM_ENCRYPT'], 'n');
      expect(x.containsKey('INTEL_IOMMU'), isFalse);
    });

    test('su AMD quelle che esistono solo su Intel', () {
      final x = v({'fornitore': 'AuthenticAMD'});
      expect(x['INTEL_IOMMU'], 'n');
      expect(x['X86_SGX'], 'n');
      expect(x.containsKey('AMD_IOMMU'), isFalse);
    });

    test('i regolatori di frequenza no: li accende SCHED_MC_PRIO', () {
      // Compilando il 7.2.8: X86_AMD_PSTATE chiesto «n» su Intel restava
      // «y» (select da SCHED_MC_PRIO), e la regola dava solo un avviso.
      for (final f in ['GenuineIntel', 'AuthenticAMD']) {
        final x = v({'fornitore': f});
        expect(x.containsKey('X86_AMD_PSTATE'), isFalse, reason: f);
        expect(x.containsKey('X86_INTEL_PSTATE'), isFalse, reason: f);
      }
    });

    test('un fornitore che non conosco non toglie niente', () {
      expect(v({'fornitore': 'HygonGenuine'}), isEmpty);
      expect(v({'fornitore': ''}), isEmpty);
    });

    test('ogni regola ha il suo perché', () {
      for (final i in suMisura({'cpuPossibili': 8, 'nodiNuma': 1,
                                'fornitore': 'AuthenticAMD'})) {
        expect(i.perche.trim(), isNotEmpty, reason: i.simbolo);
      }
    });

    test('entrano nella ricetta solo se si sceglie «su misura»', () {
      final m = {'cpuPossibili': 8, 'nodiNuma': 1, 'fornitore': 'GenuineIntel'};
      Set<String> simboli(Map<String, dynamic> extra) => {
            for (final i in calcola(rilievo(macchina: m), scelte(extra),
                    cartelle, nuclei: 8)
                .impostazioni)
              i.simbolo,
          };
      expect(simboli(const {}), isNot(contains('NR_CPUS')));
      expect(simboli({'misura': true}), containsAll(['NR_CPUS', 'NUMA']));
    });
  });

  group('completare quello che localmodconfig non aggiunge', () {
    test('il passo sta dopo la scrematura e prima del riallineamento', () {
      final id = ricetta().passi.map((p) => p.id).toList();
      expect(id.indexOf('completa'), greaterThan(id.indexOf('screma')));
      expect(id.indexOf('completa'), lessThan(id.indexOf('riallinea')));
      expect(id.indexOf('completa'), lessThan(id.indexOf('controlla')));
    });

    test('si completano essenziali, scorte scelte e aggiunti; non i tolti', () {
      final ril = rilievo();
      final r = calcola(
          ril,
          scelte({'scorte': ['controller'], 'aggiunti': ['btusb'],
                  'tolti': ['xpad']}),
          cartelle,
          nuclei: 4);
      final d = daCompletare(r, ril);
      expect(d, containsAll(['nvme', 'btrfs', 'hid_playstation', 'btusb']));
      expect(d, isNot(contains('xpad')));
      expect(d, isNot(contains('snd_hda_intel')),
          reason: 'un modulo legato si tiene, ma non si promette di '
              'accenderlo: se la configurazione non lo ha, non lo ha');
    });

    test('da un kernel senza moduli si dice che la scrematura non toglie '
        'niente', () {
      final r = calcola(rilievo(macchina: {'monolitico': true}), scelte(),
          cartelle, nuclei: 4);
      expect(r.avvisi.join(), contains('non ha moduli'));
    });
  });

  group('il controllo del .config', () {
    const chieste = [
      Impostazione('HZ_1000', 'y', ''),
      Impostazione('HZ', '1000', ''),
      Impostazione('LOCALVERSION', '-fucina-prova', ''),
      Impostazione('HZ_250', 'n', ''),
      Impostazione('X86_NATIVE_CPU', 'y', ''),
      Impostazione('LTO_CLANG_THIN', 'y', ''),
    ];

    test('quello che ha preso tace, quello che no si dice per nome', () {
      const config = '''
CONFIG_HZ_1000=y
CONFIG_HZ=1000
CONFIG_LOCALVERSION="-fucina-prova"
# CONFIG_HZ_250 is not set
# CONFIG_LTO_CLANG_THIN is not set
''';
      final righe = controllaConfig(config, chieste);
      expect(righe, hasLength(2));
      expect(righe.join('\n'), contains('X86_NATIVE_CPU'));
      expect(righe.join('\n'), contains('LTO_CLANG_THIN'));
    });

    test('un choice che non ha preso si dice in UNA riga, con quello che è '
        'rimasto', () {
      // Il 7.2 vero su x86: PREEMPT_VOLUNTARY non esiste più, resta LAZY.
      const config = '''
# CONFIG_PREEMPT is not set
CONFIG_PREEMPT_LAZY=y
''';
      final righe = controllaConfig(config, const [
        Impostazione('PREEMPT_NONE', 'n', ''),
        Impostazione('PREEMPT_VOLUNTARY', 'y', ''),
        Impostazione('PREEMPT', 'n', ''),
        Impostazione('PREEMPT_LAZY', 'n', ''),
      ]);
      expect(righe, hasLength(1));
      expect(righe.single, contains('PREEMPT_VOLUNTARY'));
      expect(righe.single, contains('è rimasto PREEMPT_LAZY'));
    });

    test('un choice che ha preso tace, anche se le altre voci erano «n»', () {
      const config = 'CONFIG_PREEMPT=y\n# CONFIG_PREEMPT_LAZY is not set\n';
      expect(controllaConfig(config, const [
        Impostazione('PREEMPT', 'y', ''),
        Impostazione('PREEMPT_LAZY', 'n', ''),
        Impostazione('PREEMPT_VOLUNTARY', 'n', ''),
      ]), isEmpty);
    });

    test('un «n» chiesto per un simbolo che non esiste è già vero', () {
      expect(controllaConfig('', const [Impostazione('HZ_250', 'n', '')]),
          isEmpty);
    });
  });
}

