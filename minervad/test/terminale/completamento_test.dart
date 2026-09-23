import 'dart:io';
import 'package:minervad/terminale/completamento.dart';
import 'package:minervad/terminale/predittore.dart';
import 'package:minervad/terminale/storia.dart';
import 'package:minervad/terminale/dizionario.dart';
import 'package:minervad/terminale/guardia.dart';
import 'package:test/test.dart';

void main() {
  test('la guardia vede il comando dopo background e newline', () {
    final guardia = Guardia();
    expect(guardia.giudica('echo ok & rm -rf /')?.livello, 'blocca');
    expect(guardia.giudica('echo ok\nrm -rf /')?.livello, 'blocca');
    expect(spezzaPipeline('echo ok 2>&1 & cat <&0'), ['echo ok 2>&1', 'cat <&0']);
  });
  test('una parola, non argomenti né catene', () {
    expect(prossimaParola('git l', 'git log --oneline && echo fine'), 'git log');
    expect(prossimaParola('git', 'git log'), '');
    expect(prossimaParola('git ', 'git log'), 'git log');
    expect(prossimaParola('echo ', "echo 'due parole' altro"), "echo 'due parole'");
    expect(prossimaParola('cat c', r'cat con\ spazio.txt altro'), r'cat con\ spazio.txt');
    for (final t in ['echo \$(id)', 'echo `id`', 'echo a;id', 'echo a\nid', 'echo "\$(id)"']) {
      expect(prossimaParola('echo ', t), '', reason: t);
    }
  });
  test('nessun terminatore bracketed paste o controllo iniettato', () {
    final t = pulisciIncolla('abc\x1b[201~\ncomando\x00\x03\x9b\r\nfine');
    expect(t, 'abc[201~\ncomando\nfine');
  });
  test('percorsi ostili restano un argomento letterale nella shell', () async {
    final d = Directory.systemTemp.createTempSync('minerva-predizione-');
    addTearDown(() => d.deleteSync(recursive: true));
    final nomi = [r'con$(id)', 'con;echo', 'con`id`', "con'apice", 'con spazio', r'con\barra', 'con🌙'];
    for (final nome in nomi) { File('${d.path}/$nome').createSync(); }
    File('${d.path}/con\ninvio').createSync();
    final p = Predittore(storia: Storia(), dizionario: Dizionario.vuoto(), programmi: []);
    final risposte = p.proponi('printf con', d.path).proposte;
    expect(risposte.length, nomi.length);
    for (final r in risposte) {
      final arg = r.testo.substring('printf '.length);
      final result = await Process.run('/bin/sh', ['-c', 'set -- $arg; printf "%s\\n%s" "\$#" "\$1"'], workingDirectory: d.path);
      expect(result.exitCode, 0);
      expect(result.stdout, startsWith('1\n'));
      expect(nomi, contains((result.stdout as String).substring(2)));
    }
    expect(p.proponi(r'printf con\ s', d.path).proposte.single.testo, r'printf con\ spazio');
    expect(p.proponi('printf "con ', d.path).proposte, isEmpty);
    File('${d.path}/-rf').createSync();
    expect(p.proponi('rm ', d.path).proposte.map((p) => p.testo), contains('rm ./-rf'));
  });
}
