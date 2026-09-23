import 'dart:io';

import 'package:minervad/services/tema_icone_service.dart';
import 'package:test/test.dart';

/// Prove sull'installazione di un set di icone preso da fuori.
///
/// **Le prove che contano qui sono i RIFIUTI.** Che un tema buono si installi
/// è la parte facile e la si vede subito; che uno cattivo NON si installi è
/// quella che protegge, e non si vede mai — finché non serve.
///
/// Un archivio che arriva da internet e finisce dentro `~/.local/share` è il
/// posto classico in cui «installa questo tema» diventa «esegui questo».
void main() {
  late Directory temp;
  late Directory casa;
  const servizio = TemaIconeService();

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('minerva-icone-prova-');
    casa = Directory('${temp.path}/casa')..createSync(recursive: true);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  /// Un tema di icone finto, ma con la forma di uno vero.
  Future<Directory> temaBuono(String nome) async {
    final d = Directory('${temp.path}/$nome')..createSync(recursive: true);
    File('${d.path}/index.theme').writeAsStringSync(
        '[Icon Theme]\nName=$nome\nComment=finto\nDirectories=48x48\n');
    Directory('${d.path}/48x48').createSync();
    File('${d.path}/48x48/folder.png').writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);
    return d;
  }

  group('quello che si accetta', () {
    test('una cartella con index.theme si installa', () async {
      final t = await temaBuono('Verdino');
      final r = await servizio.installa(t.path, casa.path);

      expect(r['ok'], isTrue, reason: '${r['error']}');
      expect(r['nome'], 'Verdino');
      expect(
          await File('${casa.path}/.local/share/icons/Verdino/index.theme')
              .exists(),
          isTrue);
    });

    test('il nome viene da index.theme, non dalla cartella', () async {
      // I temi scaricati stanno spesso in cartelle chiamate come il pacchetto
      // (`papirus-icon-theme-20240101`), e mostrare quello vorrebbe dire
      // mostrare un nome che l'autore non ha scelto.
      final d = Directory('${temp.path}/pacchetto-1.2.3')
        ..createSync(recursive: true);
      File('${d.path}/index.theme')
          .writeAsStringSync('[Icon Theme]\nName=Aurora Scura\n');

      final r = await servizio.installa(d.path, casa.path);
      expect(r['ok'], isTrue, reason: '${r['error']}');
      expect(r['nome'], 'Aurora Scura');
    });

    test('un tema dentro una cartella sola viene trovato lo stesso', () async {
      // È il caso normale di un archivio scaricato: `Roba-1.2/Roba/index.theme`.
      final fuori = Directory('${temp.path}/Roba-1.2')..createSync();
      final dentro = Directory('${fuori.path}/Roba')..createSync();
      File('${dentro.path}/index.theme')
          .writeAsStringSync('[Icon Theme]\nName=Roba\n');

      final r = await servizio.installa(fuori.path, casa.path);
      expect(r['ok'], isTrue, reason: '${r['error']}');
      expect(r['nome'], 'Roba');
    });
  });

  group('quello che si RIFIUTA, ed è il motivo per cui esiste questo file', () {
    test('senza index.theme non è un tema', () async {
      final d = Directory('${temp.path}/immagini')..createSync();
      File('${d.path}/una.png').writeAsBytesSync([1, 2, 3]);

      final r = await servizio.installa(d.path, casa.path);
      expect(r['ok'], isFalse);
      expect(r['error'], contains('index.theme'));
    });

    test('un .desktop dentro fa rifiutare TUTTO', () async {
      // `.desktop` è un file di testo che dice al sistema quale comando
      // lanciare. Un tema di icone non ha nessun motivo di portarne uno, e
      // «installa questo tema» non deve poter voler dire «esegui questo».
      final t = await temaBuono('Cattivo');
      File('${t.path}/48x48/innocuo.desktop')
          .writeAsStringSync('[Desktop Entry]\nExec=rm -rf ~\n');

      final r = await servizio.installa(t.path, casa.path);
      expect(r['ok'], isFalse);
      expect(r['error'], contains('innocuo.desktop'));
      expect(await Directory('${casa.path}/.local/share/icons/Cattivo').exists(),
          isFalse,
          reason: 'rifiutato ma installato lo stesso: il controllo deve venire '
              'PRIMA di scrivere fra i temi');
    });

    test('e così uno script', () async {
      final t = await temaBuono('ConScript');
      File('${t.path}/installa.sh').writeAsStringSync('#!/bin/sh\necho ciao\n');

      final r = await servizio.installa(t.path, casa.path);
      expect(r['ok'], isFalse);
      expect(r['error'], contains('installa.sh'));
    });

    test('un file eseguibile SENZA estensione non sfugge', () async {
      // È la forma più vecchia dello stesso trucco: niente estensione da
      // riconoscere, solo il bit di esecuzione. Guardare solo il nome
      // lascerebbe passare proprio questo.
      final t = await temaBuono('ConBinario');
      final f = File('${t.path}/aggiorna')..writeAsStringSync('roba');
      await Process.run('chmod', ['+x', f.path]);

      final r = await servizio.installa(t.path, casa.path);
      expect(r['ok'], isFalse);
      expect(r['error'], contains('aggiorna'));
      expect(r['error'], contains('eseguibile'));
    });

    test('non sovrascrive un tema già installato', () async {
      final t = await temaBuono('Doppio');
      final primo = await servizio.installa(t.path, casa.path);
      expect(primo['ok'], isTrue, reason: '${primo['error']}');

      final secondo = await servizio.installa(t.path, casa.path);
      expect(secondo['ok'], isFalse);
      expect(secondo['error'], contains('già installato'));
    });
  });

  group('togliere un tema', () {
    test('si toglie quello installato da qui', () async {
      final t = await temaBuono('DaTogliere');
      final messo = await servizio.installa(t.path, casa.path);
      expect(messo['ok'], isTrue, reason: '${messo['error']}');

      final r = await servizio.disinstalla(messo['cartella'] as String, casa.path);
      expect(r['ok'], isTrue, reason: '${r['error']}');
      expect(await Directory(messo['cartella'] as String).exists(), isFalse);
    });

    test('NON si tocca un tema di sistema', () async {
      // I temi di sistema non sono nostri: cancellarli romperebbe la scrivania
      // di chiunque altro usi il computer, e servirebbe comunque una password.
      final r = await servizio.disinstalla('/usr/share/icons/hicolor', casa.path);
      expect(r['ok'], isFalse);
      expect(r['error'], contains('fuori'));
      expect(await Directory('/usr/share/icons/hicolor').exists(), isTrue,
          reason: 'IL TEMA DI SISTEMA È STATO TOCCATO');
    });

    test('né qualcosa fuori dalla cartella dei temi', () async {
      final altrove = Directory('${temp.path}/altrove')..createSync();
      final r = await servizio.disinstalla(altrove.path, casa.path);
      expect(r['ok'], isFalse);
      expect(await altrove.exists(), isTrue);
    });
  });

  // ── Scompattato una cartella troppo in fondo ────────────────────────────
  //
  // Giacomo, 6 settembre 2026: «in .local/share/icons ho messo vari temi icone
  // ma non compaiono nei set icone in impostazioni».
  //
  // Tre su cinque non comparivano, e non era la ricerca a sbagliare: erano
  // dentro una cartella in più —
  // `~/.local/share/icons/Fluent-purple/Fluent-purple/index.theme` — che è
  // quello che succede estraendo un archivio dentro una cartella che ha già
  // il suo nome. L'errore più comune che ci sia con i temi.
  //
  // Si poteva rispondere «rimettili a posto». Ma un tema installato che non
  // compare, senza che niente lo dica, è il difetto che questo progetto si è
  // messo per iscritto di non commettere.
  group('un tema scompattato una cartella troppo in fondo si trova lo stesso',
      () {
    test('il codice scende di un livello, e di uno solo', () {
      var dir = Directory.current;
      File? f;
      for (var i = 0; i < 4 && f == null; i++) {
        for (final base in [
          'lib/services/icon_resolver.dart',
          'minervad/lib/services/icon_resolver.dart'
        ]) {
          final c = File('${dir.path}/$base');
          if (c.existsSync()) f = c;
        }
        dir = dir.parent;
      }
      expect(f, isNotNull, reason: 'non trovo icon_resolver.dart');
      final t = f!.readAsStringSync();

      expect(t, contains('_radiciAnnidate'),
          reason: 'senza, un tema estratto dentro una cartella del proprio '
              'nome non compare e nessuno dice perché');
      final i = t.indexOf('List<String> _radiciAnnidate()');
      expect(i, greaterThan(0));
      final corpo = t.substring(i, i + 1200);

      // Le due condizioni che tengono stretta la regola: si scende SOLO in
      // una cartella che non è già un tema, e SOLO se contiene un tema.
      // Senza, si andrebbe a pescare in qualunque cartella di icone.
      expect(corpo, contains("index.theme').existsSync()) continue"),
          reason: 'in una cartella che è già un tema non si scende');
      expect(corpo, contains('contieneUnTema'),
          reason: 'e non si scende dove non c\'è nessun tema');
      expect(corpo, isNot(contains('recursive: true')),
          reason: 'un livello, non l\'albero intero: la cartella delle icone '
              'di un sistema ne contiene migliaia');
    });
  });
}
