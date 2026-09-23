// predittore_test.dart — La stessa storia dà le stesse proposte, nell'ordine
// dichiarato; una cartella nuova non eredita i comandi sbagliati.
import 'dart:io';

import 'package:minervad/terminale/dizionario.dart';
import 'package:minervad/terminale/predittore.dart';
import 'package:minervad/terminale/storia.dart';
import 'package:test/test.dart';

const _giorno = 86400000;
const _adesso = 1_757_900_000_000;

VoceStoria _v(String comando, {String cartella = '/casa', int codice = 0, int giorniFa = 0}) =>
    VoceStoria(quando: _adesso - giorniFa * _giorno, cartella: cartella, comando: comando, codice: codice, durata: 10);

Dizionario _diz() => Dizionario.daJson('''
{"comandi":[
 {"comando":"git","descrizione":"Il controllo di versione.","categoria":"sviluppo","livello":5,"pericolo":1,
  "opzioni":[{"flag":"status","spiegazione":"cosa è cambiato"},{"flag":"log --oneline","spiegazione":"la storia"}],
  "esempi":[{"comando":"git status","spiegazione":"il punto della situazione"},{"comando":"git log --oneline -10","spiegazione":"gli ultimi dieci"}]},
 {"comando":"ls","descrizione":"Elenca i file.","categoria":"file","livello":1,"pericolo":0,
  "opzioni":[{"flag":"-l","spiegazione":"una riga per file"},{"flag":"-a","spiegazione":"anche i nascosti"},{"flag":"-A N / -B N","spiegazione":"contesto"}],
  "esempi":[{"comando":"ls -la","spiegazione":"tutto"}]},
 {"comando":"grep","descrizione":"Cerca un testo.","categoria":"testo","livello":2,"pericolo":0,
  "opzioni":[{"flag":"-i","spiegazione":"ignora maiuscole"},{"flag":"-r","spiegazione":"ricorsivo"},{"flag":"--include='*.py'","spiegazione":"solo questi"}],
  "esempi":[{"comando":"grep -rn 'TODO' src/","spiegazione":"in src"}]}
]}''');

void main() {
  group('la storia', () {
    test('la stessa storia dà le stesse proposte, nello stesso ordine', () {
      final s = Storia()
        ..aggiungi(_v('git status'))
        ..aggiungi(_v('git push'))
        ..aggiungi(_v('git status'));
      final p = Predittore(storia: s, dizionario: Dizionario.vuoto(), programmi: const [], leggiCartelle: false);
      final a = p.proponi('git ', '/casa', adessoMs: _adesso);
      final b = p.proponi('git ', '/casa', adessoMs: _adesso);
      expect(a.proposte.map((x) => x.testo).toList(), ['git status', 'git push']);
      expect(b.proposte.map((x) => x.testo).toList(), a.proposte.map((x) => x.testo).toList());
      expect(a.fantasma, 'git status');
    });

    test('la cartella di adesso pesa tre volte le altre', () {
      final s = Storia()
        ..aggiungi(_v('make test', cartella: '/altra'))
        ..aggiungi(_v('make test', cartella: '/altra'))
        ..aggiungi(_v('make build', cartella: '/qui'));
      final p = Predittore(storia: s, dizionario: Dizionario.vuoto(), programmi: const [], leggiCartelle: false);
      expect(p.proponi('make ', '/qui', adessoMs: _adesso).fantasma, 'make build');
      expect(p.proponi('make ', '/altra', adessoMs: _adesso).fantasma, 'make test');
    });

    test('un comando fallito pesa un terzo: una cartella nuova non eredita gli sbagli', () {
      final s = Storia()
        ..aggiungi(_v('rm -rf build', cartella: '/altra', codice: 1))
        ..aggiungi(_v('rm -rf build', cartella: '/altra', codice: 1))
        ..aggiungi(_v('rm -i vecchio.txt', cartella: '/altra', codice: 0));
      final p = Predittore(storia: s, dizionario: Dizionario.vuoto(), programmi: const [], leggiCartelle: false);
      expect(p.proponi('rm ', '/nuova', adessoMs: _adesso).fantasma, 'rm -i');
    });

    test('ieri pesa più di un mese fa', () {
      final s = Storia()
        ..aggiungi(_v('ssh vecchio', giorniFa: 40))
        ..aggiungi(_v('ssh vecchio', giorniFa: 40))
        ..aggiungi(_v('ssh vecchio', giorniFa: 40))
        ..aggiungi(_v('ssh nuovo', giorniFa: 1));
      final p = Predittore(storia: s, dizionario: Dizionario.vuoto(), programmi: const [], leggiCartelle: false);
      expect(p.proponi('ssh ', '/casa', adessoMs: _adesso).fantasma, 'ssh nuovo');
    });

    test('quello che hai già scritto per intero non si propone', () {
      final s = Storia()..aggiungi(_v('ls'));
      final p = Predittore(storia: s, dizionario: Dizionario.vuoto(), programmi: const [], leggiCartelle: false);
      final r = p.proponi('ls', '/casa', adessoMs: _adesso);
      expect(r.proposte, isEmpty);
      expect(r.fantasma, '');
    });

    test('la spiegazione dice quante volte, e cos\'è se il dizionario lo sa', () {
      final s = Storia()..aggiungi(_v('git status'))..aggiungi(_v('git status'));
      final p = Predittore(storia: s, dizionario: _diz(), programmi: const [], leggiCartelle: false);
      final r = p.proponi('git s', '/casa', adessoMs: _adesso);
      expect(r.proposte.first.spiegazione, 'Il controllo di versione. · usato 2 volte');
    });
  });

  group('il dizionario', () {
    test('gli esempi arrivano con la spiegazione', () {
      final p = Predittore(storia: Storia(), dizionario: _diz(), programmi: const [], leggiCartelle: false);
      final r = p.proponi('git l', '/casa', adessoMs: _adesso);
      expect(r.fantasma, 'git log');
      expect(r.proposte.first.tipo, 'esempio');
      expect(r.proposte.first.spiegazione, 'gli ultimi dieci');
    });

    test('sulla prima parola si propongono i comandi con la descrizione', () {
      final p = Predittore(storia: Storia(), dizionario: _diz(), programmi: const ['grep', 'groups', 'ls'], leggiCartelle: false);
      final r = p.proponi('gr', '/casa', adessoMs: _adesso);
      final tipi = {for (final x in r.proposte) x.testo: x.tipo};
      expect(tipi['grep'], 'comando');
      expect(tipi['groups'], 'programma');
      expect(r.proposte.firstWhere((x) => x.testo == 'grep').spiegazione, 'Cerca un testo.');
      // Anche dagli esempi si accetta soltanto la parola in corso.
      expect(r.fantasma, 'grep');
    });

    test('la storia vince sugli esempi a parità di prefisso', () {
      final s = Storia()..aggiungi(_v('git stash'))..aggiungi(_v('git stash'));
      final p = Predittore(storia: s, dizionario: _diz(), programmi: const [], leggiCartelle: false);
      expect(p.proponi('git st', '/casa', adessoMs: _adesso).fantasma, 'git stash');
    });
  });

  group('i percorsi', () {
    late Directory d;
    setUp(() {
      d = Directory.systemTemp.createTempSync('predittore');
      Directory('${d.path}/Documenti').createSync();
      Directory('${d.path}/Download').createSync();
      File('${d.path}/appunti.txt').writeAsStringSync('x');
      File('${d.path}/con spazio.txt').writeAsStringSync('x');
      File('${d.path}/.nascosto').writeAsStringSync('x');
    });
    tearDown(() => d.deleteSync(recursive: true));

    test('la seconda parola si completa coi file della cartella', () {
      final p = Predittore(storia: Storia(), dizionario: Dizionario.vuoto(), programmi: const []);
      final r = p.proponi('cd Do', d.path, adessoMs: _adesso);
      expect(r.proposte.map((x) => x.testo).toList(), ['cd Documenti/', 'cd Download/']);
      expect(r.proposte.first.tipo, 'cartella');
    });

    test('gli spazi nei nomi si proteggono, i nascosti solo se chiesti', () {
      final p = Predittore(storia: Storia(), dizionario: Dizionario.vuoto(), programmi: const []);
      final r = p.proponi('cat c', d.path, adessoMs: _adesso);
      expect(r.proposte.map((x) => x.testo).toList(), [r'cat con\ spazio.txt']);
      final n = p.proponi('cat .', d.path, adessoMs: _adesso);
      expect(n.proposte.map((x) => x.testo).toList(), ['cat .nascosto']);
      final tutti = p.proponi('cat ', d.path, adessoMs: _adesso);
      expect(tutti.proposte.map((x) => x.testo), isNot(contains('cat .nascosto')));
    });

    test('un percorso con la barra si completa dentro', () {
      File('${d.path}/Documenti/tesi.md').writeAsStringSync('x');
      final p = Predittore(storia: Storia(), dizionario: Dizionario.vuoto(), programmi: const []);
      final r = p.proponi('vim Documenti/t', d.path, adessoMs: _adesso);
      expect(r.proposte.map((x) => x.testo).toList(), ['vim Documenti/tesi.md']);
    });
  });

  group('la storia su disco', () {
    test('si scrive una riga per comando e si rilegge', () {
      final d = Directory.systemTemp.createTempSync('storia');
      final f = '${d.path}/a/b/storia.jsonl';
      final s = Storia(percorso: f)..carica();
      expect(s.aggiungi(_v('ls -la')), isTrue);
      expect(s.aggiungi(_v(' segreto --token=x')), isFalse, reason: 'uno spazio davanti: non si salva');
      expect(s.aggiungi(_v('')), isFalse);
      final righe = File(f).readAsLinesSync();
      expect(righe.length, 1);
      expect(righe.first, contains('"comando":"ls -la"'));
      final s2 = Storia(percorso: f)..carica();
      expect(s2.voci.length, 1);
      expect(s2.voci.first.cartella, '/casa');
      d.deleteSync(recursive: true);
    });

    test('una riga rotta non toglie il resto', () {
      final d = Directory.systemTemp.createTempSync('storia');
      final f = File('${d.path}/storia.jsonl')
        ..writeAsStringSync('{"comando":"uno","quando":1}\nquesta non è json\n{"comando":"due","quando":2}\n');
      final s = Storia(percorso: f.path)..carica();
      expect(s.voci.map((v) => v.comando).toList(), ['uno', 'due']);
      d.deleteSync(recursive: true);
    });

    test('cerca: dalla più recente, senza doppioni, per prefisso o dentro', () {
      final s = Storia()..aggiungi(_v('git status'))..aggiungi(_v('git push'))..aggiungi(_v('git status'));
      expect(s.cerca('git').map((v) => v.comando).toList(), ['git status', 'git push']);
      expect(s.cerca('push', contiene: true).map((v) => v.comando).toList(), ['git push']);
      expect(s.cerca('push'), isEmpty);
    });
  });
}
