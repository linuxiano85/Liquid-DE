import 'dart:convert';
import 'dart:io';
import 'package:minervad/services/fucina/requisiti_amministrazione.dart';
import 'package:minervad/services/fucina/scaffale.dart';
import 'package:minervad/services/fucina_service.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  const rel = '7.2.9-fucina-prova';
  late String lavoro;
  late String out;
  late int chiamateRoot;
  void scrivi(String path, String testo) {
    final f = File(path)..createSync(recursive: true);
    f.writeAsStringSync(testo);
  }

  Future<void> programma(String path, String testo) async {
    scrivi(path, testo);
    expect((await Process.run('chmod', ['755', path])).exitCode, 0);
  }

  RequisitiAmministrazione requisiti() => RequisitiAmministrazione(
    aiutante: '${tmp.path}/helper',
    binari: ['${tmp.path}/bin'],
  );
  Scaffale scaffale() => Scaffale(
    radice: '${tmp.path}/',
    lavoro: lavoro,
    statoDir: '${tmp.path}/stato',
  );
  FucinaService servizio({Future<Map<String, dynamic>> Function()? diagnosi}) =>
      FucinaService(
        lavoro: lavoro,
        statoDir: '${tmp.path}/stato',
        scaffale: scaffale(),
        statoAmministrazione: diagnosi,
        radice: (_, _) async {
          chiamateRoot++;
          return {'ok': true, 'uscita': <int>[]};
        },
      );
  Future<Map> voce() async =>
      ((await scaffale().elenco())['kernel'] as List).single as Map;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('fucina-prerequisiti-');
    lavoro = '${tmp.path}/cache';
    out = '$lavoro/uscita/$rel';
    chiamateRoot = 0;
    scrivi('${tmp.path}/proc/sys/kernel/osrelease', '7.2.9-distro\n');
    scrivi('$out/fucina.json', jsonEncode({'rilascio': rel}));
    scrivi('$out/boot/vmlinuz-$rel', 'immagine');
    scrivi('$out/boot/config-$rel', 'CONFIG_MODULES=y\n');
    Directory('$out/lib/modules/$rel').createSync(recursive: true);
    await programma(
      '${tmp.path}/helper',
      '#!/bin/sh\n# FUCINA_TRANSACTION_ABI=2\nexit 0\n',
    );
    for (final name in ['pkexec', 'flock', 'depmod', 'mkinitcpio']) {
      await programma(
        '${tmp.path}/bin/$name',
        '#!/bin/sh\ntouch "${tmp.path}/comando-eseguito"\nexit 1\n',
      );
    }
  });
  tearDown(() async => tmp.delete(recursive: true));

  test(
    'diagnosi completa non esegue helper o programmi e distingue i requisiti',
    () async {
      final info = await requisiti().leggi();
      expect(info['installazionePossibile'], isTrue);
      expect(info['rimozionePossibile'], isTrue);
      expect(File('${tmp.path}/comando-eseguito').existsSync(), isFalse);
      File('${tmp.path}/bin/depmod').deleteSync();
      final senzaDepmod = await requisiti().leggi();
      expect(senzaDepmod['installazionePossibile'], isFalse);
      expect(senzaDepmod['rimozionePossibile'], isTrue);
      File('${tmp.path}/bin/mkinitcpio').deleteSync();
      expect((await requisiti().leggi())['installazionePossibile'], isFalse);
      await programma('${tmp.path}/bin/dracut', '#!/bin/sh\nexit 1\n');
      await programma('${tmp.path}/bin/depmod', '#!/bin/sh\nexit 1\n');
      expect((await requisiti().leggi())['installazionePossibile'], isTrue);
    },
  );

  test(
    'helper assente, non eseguibile, vecchio e ABI futura non abilitano mutazioni',
    () async {
      for (final testo in [
        '#!/bin/sh\n',
        '#!/bin/sh\n# FUCINA_TRANSACTION_ABI=1\n',
        '#!/bin/sh\n# FUCINA_TRANSACTION_ABI=3\n',
        '#!/bin/sh\n# FUCINA_TRANSACTION_ABI=1\n# FUCINA_TRANSACTION_ABI=2\n',
      ]) {
        scrivi('${tmp.path}/helper', testo);
        final i = await requisiti().leggi();
        expect(i['installazionePossibile'], isFalse);
        expect(i['rimozionePossibile'], isFalse);
        expect((i['aiutante'] as Map)['stato'], 'da-aggiornare');
      }
      File('${tmp.path}/helper').deleteSync();
      expect((await requisiti().verificaAiutante())['stato'], 'assente');
      scrivi('${tmp.path}/helper', '#!/bin/sh\n# FUCINA_TRANSACTION_ABI=2\n');
      expect((await requisiti().verificaAiutante())['stato'], 'non-eseguibile');
    },
  );

  test(
    'servizio espone la diagnosi e ricontrolla prima di chiamare root',
    () async {
      final s = servizio(diagnosi: requisiti().leggi);
      expect(
        ((await s.kernel())['amministrazione']
            as Map)['installazionePossibile'],
        isTrue,
      );
      File('${tmp.path}/bin/pkexec').deleteSync();
      final r = await s.installa(rel);
      expect(r['ok'], isFalse);
      expect(r['errore'], contains('pkexec'));
      expect(chiamateRoot, 0);
      expect(File('$lavoro/.lavoro-attivo.json').existsSync(), isFalse);
      Directory('${tmp.path}/usr/lib/modules/$rel').createSync(recursive: true);
      expect((await s.togli(rel))['ok'], isFalse);
      expect(chiamateRoot, 0);
      expect(File('$out/boot/vmlinuz-$rel').readAsStringSync(), 'immagine');
    },
  );

  test('diagnosi in errore impedisce la richiesta root', () async {
    final s = servizio(
      diagnosi: () async => throw const FileSystemException('errore'),
    );
    expect((await s.installa(rel))['ok'], isFalse);
    expect(chiamateRoot, 0);
  });

  test(
    'manifest corrotto, rilascio diverso e symlink non sono pronti',
    () async {
      for (final testo in [
        '{',
        '[]',
        jsonEncode({'rilascio': '7.2.9-fucina-altro'}),
      ]) {
        scrivi('$out/fucina.json', testo);
        final k = await voce();
        expect(k['pronto'], isFalse);
        expect((k['preparazione'] as Map)['blocchi'], isNotEmpty);
        expect((await servizio().installa(rel))['ok'], isFalse);
        expect(chiamateRoot, 0);
      }
      File('$out/fucina.json').deleteSync();
      scrivi('${tmp.path}/manifest-esterno', jsonEncode({'rilascio': rel}));
      Link('$out/fucina.json').createSync('${tmp.path}/manifest-esterno');
      expect((await voce())['pronto'], isFalse);
      expect(
        File('${tmp.path}/manifest-esterno').readAsStringSync(),
        contains(rel),
      );
    },
  );

  test(
    'file vuoti o mancanti e cartella moduli symlink impediscono installazione',
    () async {
      for (final part in ['boot/vmlinuz-$rel', 'boot/config-$rel']) {
        final f = File('$out/$part');
        final original = f.readAsStringSync();
        f.writeAsStringSync('');
        expect((await voce())['pronto'], isFalse);
        expect((await servizio().installa(rel))['ok'], isFalse);
        f.deleteSync();
        expect((await voce())['pronto'], isFalse);
        f.writeAsStringSync(original);
      }
      Directory('$out/lib/modules/$rel').deleteSync();
      Directory('${tmp.path}/moduli-esterni').createSync();
      Link('$out/lib/modules/$rel').createSync('${tmp.path}/moduli-esterni');
      expect((await voce())['pronto'], isFalse);
      expect((await servizio().installa(rel))['ok'], isFalse);
      expect(chiamateRoot, 0);
    },
  );

  test(
    'QEMU assente è un avviso esplicito, fallito blocca, riuscito abilita',
    () async {
      var k = await voce();
      expect(k['pronto'], isTrue);
      expect((k['preparazione'] as Map)['avvisi'], isNotEmpty);
      for (final ok in [false, true]) {
        scrivi(
          '$out/fucina.json',
          jsonEncode({
            'rilascio': rel,
            'provaAvvio': {'ok': ok},
          }),
        );
        k = await voce();
        expect(k['pronto'], ok);
        expect((k['preparazione'] as Map)['avvisi'], isEmpty);
      }
    },
  );

  test('non reinstalla il kernel in uso prima della password', () async {
    scrivi('${tmp.path}/proc/sys/kernel/osrelease', '$rel\n');
    expect((await servizio().installa(rel))['ok'], isFalse);
    expect(chiamateRoot, 0);
  });
}
