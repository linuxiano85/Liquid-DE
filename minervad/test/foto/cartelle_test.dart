import 'dart:convert';
import 'dart:io';

import 'package:minervad/services/foto/cartelle.dart';
import 'package:test/test.dart';

void main() {
  late Directory tana;
  late Directory casa;
  late Cartelle c;

  setUp(() {
    tana = Directory.systemTemp.createTempSync('minerva-cartelle-');
    casa = Directory('${tana.path}/casa')..createSync();
    c = Cartelle(
        percorso: '${tana.path}/config/foto/cartelle.json', casa: casa.path);
  });
  tearDown(() => tana.deleteSync(recursive: true));

  Directory fai(String dentro) =>
      Directory('${casa.path}/$dentro')..createSync(recursive: true);

  void foto(String dove, int quante, {String coda = '.jpg'}) {
    final d = fai(dove);
    for (var i = 0; i < quante; i++) {
      File('${d.path}/f$i$coda').writeAsStringSync('x');
    }
  }

  group('lo stato di partenza', () {
    test('nessuna cartella, e le esclusioni di serie già accese', () {
      final s = c.leggi();
      expect(s['cartelle'], isEmpty);
      expect((s['escludi'] as List), contains('${casa.path}/Documenti/Progetti'));
      expect(s['mostraSchermate'], isTrue);
    });

    test('una configurazione rotta non fa esplodere niente', () {
      File(c.percorso)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{ questo non è json');
      expect(c.leggi()['cartelle'], isEmpty);
    });

    test('si scrive intero o non si scrive', () {
      c.aggiungi(fai('Immagini').path);
      final scritto = jsonDecode(File(c.percorso).readAsStringSync());
      expect(scritto['cartelle'], hasLength(1));
      expect(File('${c.percorso}.nuovo').existsSync(), isFalse,
          reason: 'il temporaneo non deve restare in giro');
    });
  });

  group('aggiungere e togliere', () {
    test('una cartella vera entra', () {
      final r = c.aggiungi(fai('Immagini').path);
      expect(r['ok'], isTrue);
      expect(c.leggi()['cartelle'], ['${casa.path}/Immagini']);
    });

    test('la barra finale non fa una cartella diversa', () {
      c.aggiungi('${fai('Immagini').path}/');
      expect(c.leggi()['cartelle'], ['${casa.path}/Immagini']);
    });

    test('togliere', () {
      final p = fai('Immagini').path;
      c.aggiungi(p);
      expect(c.togli(p)['ok'], isTrue);
      expect(c.leggi()['cartelle'], isEmpty);
    });

    test('le schermate si possono nascondere', () {
      expect(c.schermate(false)['ok'], isTrue);
      expect(c.leggi()['mostraSchermate'], isFalse);
    });
  });

  group('i rifiuti', () {
    test('un percorso non completo', () {
      expect(c.aggiungi('Immagini')['ok'], isFalse);
    });

    test('una cartella che non c è', () {
      expect(c.aggiungi('${casa.path}/mai-esistita')['ok'], isFalse);
    });

    test('tutto il disco', () {
      final r = c.aggiungi('/');
      expect(r['ok'], isFalse);
      expect(r['error'], contains('file di sistema'));
    });

    test('due volte la stessa', () {
      final p = fai('Immagini').path;
      c.aggiungi(p);
      expect(c.aggiungi(p)['error'], contains('c\'è già'));
    });

    test('una dentro l altra: le fotografie comparirebbero due volte', () {
      final madre = fai('Foto').path;
      final figlia = fai('Foto/2019').path;
      c.aggiungi(madre);
      final r = c.aggiungi(figlia);
      expect(r['ok'], isFalse);
      expect(r['error'], contains('sta già dentro'));
    });

    test('e anche nel verso opposto', () {
      final figlia = fai('Foto/2019').path;
      c.aggiungi(figlia);
      final r = c.aggiungi(fai('Foto').path);
      expect(r['ok'], isFalse);
      expect(r['error'], contains('toglila prima'));
    });

    test('togliere una che non c è', () {
      expect(c.togli('${casa.path}/x')['ok'], isFalse);
    });
  });

  group('dove non si entra', () {
    test('le cartelle di sistema dei programmi non si guardano mai', () {
      for (final n in ['node_modules', '.git', '.cache', 'build']) {
        expect(Cartelle.siGuarda('${casa.path}/x/$n', {}), isFalse, reason: n);
      }
    });

    test('una cartella nascosta non si guarda', () {
      expect(Cartelle.siGuarda('${casa.path}/.nascosta', {}), isFalse);
    });

    test('escludere una cartella esclude anche quello che ha dentro', () {
      final fuori = {'${casa.path}/Scaricati'};
      expect(Cartelle.siGuarda('${casa.path}/Scaricati', fuori), isFalse);
      expect(Cartelle.siGuarda('${casa.path}/Scaricati/DCIM', fuori), isFalse);
      expect(Cartelle.siGuarda('${casa.path}/Immagini', fuori), isTrue);
    });

    test('escludere «Scaricati» non esclude ogni cartella con quel nome', () {
      // L'esclusione è un percorso, non un nome: chi ha una cartella
      // «Scaricati» dentro le foto delle vacanze non deve perderla.
      final fuori = {'${casa.path}/Scaricati'};
      expect(
          Cartelle.siGuarda('${casa.path}/Foto/Vacanze/Scaricati', fuori),
          isTrue);
    });
  });

  group('la proposta: trovare dove sono davvero', () {
    test('propone la cartella che le contiene, col conteggio', () {
      foto('Scaricati/DCIM/Camera', 40);
      final p = c.proposte();
      final trovata = p.firstWhere((x) => x['percorso'] == '${casa.path}/Scaricati',
          orElse: () => {});
      expect(trovata['quante'], 40);
    });

    test('propone la più in alto, non le tre di sotto', () {
      // Chi ha il backup del telefono vuole spuntare una riga, non tre.
      foto('backup/DCIM/Camera', 30);
      foto('backup/DCIM/Snapchat', 25);
      foto('backup/DCIM/Screenshots', 25);
      final p = c.proposte();
      final percorsi = p.map((x) => x['percorso']).toList();
      expect(percorsi, contains('${casa.path}/backup'));
      expect(percorsi, isNot(contains('${casa.path}/backup/DCIM')));
      expect(p.firstWhere((x) => x['percorso'] == '${casa.path}/backup')['quante'],
          80);
    });

    test('non propone le icone dei programmi', () {
      // È il caso vero: 64.115 PNG dentro Documenti/Progetti. Se comparissero
      // nella proposta, la proposta sarebbe inutile.
      foto('Documenti/Progetti/roba/assets', 500, coda: '.png');
      foto('Immagini', 30);
      final percorsi = c.proposte().map((x) => x['percorso']).toList();
      expect(percorsi, isNot(contains('${casa.path}/Documenti/Progetti')));
      expect(percorsi, isNot(contains('${casa.path}/Documenti')));
      expect(percorsi, contains('${casa.path}/Immagini'));
    });

    test('poche fotografie non fanno una cartella da proporre', () {
      foto('roba', 3);
      final percorsi = c.proposte().map((x) => x['percorso']).toList();
      expect(percorsi, isNot(contains('${casa.path}/roba')));
    });

    test('le cartelle di sistema si propongono sempre, anche vuote', () {
      fai('Immagini');
      fai('Video');
      final p = c.proposte();
      expect(p.where((x) => x['consigliata'] == true).map((x) => x['percorso']),
          containsAll(['${casa.path}/Immagini', '${casa.path}/Video']));
      expect(p.first['quante'], 0);
    });

    test('quello che è escluso non si propone', () {
      foto('Scaricati/DCIM', 50);
      final p = c.proposte(escluse: {'${casa.path}/Scaricati'});
      expect(p.map((x) => x['percorso']),
          isNot(contains('${casa.path}/Scaricati')));
    });
  });
}
