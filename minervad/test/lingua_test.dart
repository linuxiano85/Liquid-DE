import 'dart:io';

import 'package:test/test.dart';
import 'package:minervad/services/lingua_service.dart';

/// Il vero `/etc/locale.conf` di questa macchina, copiato il 10 agosto 2026.
/// Dieci righe, non una: è il fatto su cui si regge tutta questa pagina.
const _veroConf = '''
LANG=it_IT.UTF-8
LC_ADDRESS=it_IT.UTF-8
LC_IDENTIFICATION=it_IT.UTF-8
LC_MEASUREMENT=it_IT.UTF-8
LC_MONETARY=it_IT.UTF-8
LC_NAME=it_IT.UTF-8
LC_NUMERIC=it_IT.UTF-8
LC_PAPER=it_IT.UTF-8
LC_TELEPHONE=it_IT.UTF-8
LC_TIME=it_IT.UTF-8
''';

File _finto(Directory d, {int esito = 0, String errore = ''}) {
  final f = File('${d.path}/localectl');
  f.writeAsStringSync('''
#!/bin/sh
echo "\$@" >> "${d.path}/chiamate.txt"
case "\$1" in
  list-locales) printf 'C.UTF-8\\nen_US.UTF-8\\nit_IT.UTF-8\\n' ;;
  *) [ -n '$errore' ] && echo '$errore' >&2 ;;
esac
exit $esito
''');
  Process.runSync('chmod', ['+x', f.path]);
  return f;
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('minerva-lingua'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('lingua — lettura', () {
    test('legge il locale.conf vero di questa macchina', () {
      final c = localeDaConf(_veroConf);
      expect(c['LANG'], 'it_IT.UTF-8');
      expect(c.length, 10);
    });

    test('le virgolette e i commenti non finiscono nel valore', () {
      final c = localeDaConf('# la lingua\nLANG="en_US.UTF-8"\n\n');
      expect(c['LANG'], 'en_US.UTF-8');
      expect(c.length, 1);
    });

    test('le righe che non sono LANG o LC_* si ignorano', () {
      // Qualcuno ci mette dentro anche altro; una chiave estranea passata a
      // `set-locale` fa fallire tutto il comando.
      final c = localeDaConf('LANG=it_IT.UTF-8\nXKBLAYOUT=it\nPATH=/bin');
      expect(c.keys, ['LANG']);
    });

    test('un file assente non è un errore', () async {
      final s = LinguaService(
          comando: _finto(tmp).path, percorsoConf: '${tmp.path}/non-c-e');
      final st = await s.stato();
      expect(st['lang'], '');
      expect(st['disponibili'], hasLength(3));
    });
  });

  group('lingua — il cambio tocca TUTTE le chiavi già presenti', () {
    test('dieci chiavi dentro, dieci chiavi fuori', () {
      // È il difetto che questa funzione esiste per non avere: cambiando il
      // solo LANG, le nove LC_* restano in italiano, hanno la precedenza, e
      // il cambio lingua non si vede da nessuna parte.
      final a = argomentiPerCambio(localeDaConf(_veroConf), 'en_US.UTF-8');
      expect(a.first, 'set-locale');
      expect(a.length, 11);
      expect(a.where((x) => x.endsWith('it_IT.UTF-8')), isEmpty,
          reason: 'una chiave è rimasta indietro sulla lingua vecchia');
      expect(a[1], 'LANG=en_US.UTF-8', reason: 'LANG deve venire per primo');
      expect(a, contains('LC_TIME=en_US.UTF-8'));
    });

    test('senza nessuna LC_* si scrive il solo LANG', () {
      final a = argomentiPerCambio(localeDaConf('LANG=it_IT.UTF-8'), 'C.UTF-8');
      expect(a, ['set-locale', 'LANG=C.UTF-8']);
    });

    test('un file vuoto dà comunque un comando valido', () {
      expect(argomentiPerCambio(const {}, 'it_IT.UTF-8'),
          ['set-locale', 'LANG=it_IT.UTF-8']);
    });
  });

  group('lingua — scrittura', () {
    test('una lingua non installata si rifiuta prima di chiedere la password',
        () async {
      final conf = File('${tmp.path}/locale.conf')..writeAsStringSync(_veroConf);
      final s = LinguaService(comando: _finto(tmp).path, percorsoConf: conf.path);
      final r = await s.impostaLocale('ja_JP.UTF-8');
      expect(r['ok'], isFalse);
      expect('${r['errore']}', contains('non è installata'));
      expect(File('${tmp.path}/chiamate.txt').readAsLinesSync()
          .where((l) => l.startsWith('set-locale')), isEmpty);
    });

    test('una lingua installata passa, con tutte le sue chiavi', () async {
      final conf = File('${tmp.path}/locale.conf')..writeAsStringSync(_veroConf);
      final s = LinguaService(comando: _finto(tmp).path, percorsoConf: conf.path);
      expect((await s.impostaLocale('en_US.UTF-8'))['ok'], isTrue);
      final chiamata = File('${tmp.path}/chiamate.txt')
          .readAsLinesSync()
          .firstWhere((l) => l.startsWith('set-locale'));
      expect(chiamata.split(' ').length, 11);
      expect(chiamata, isNot(contains('it_IT')));
    });

    test('un rifiuto di polkit torna con il suo perché', () async {
      final conf = File('${tmp.path}/locale.conf')..writeAsStringSync(_veroConf);
      final s = LinguaService(
          comando: _finto(tmp, esito: 1, errore: 'Access denied').path,
          percorsoConf: conf.path);
      final r = await s.impostaLocale('en_US.UTF-8');
      expect(r['ok'], isFalse);
      expect('${r['errore']}', contains('Access denied'));
    });

    test('se `localectl` non c\'è, lo dice invece di cadere', () async {
      final s = LinguaService(
          comando: '${tmp.path}/non-esiste', percorsoConf: '${tmp.path}/x');
      expect(await s.disponibili(), isEmpty);
      final r = await s.impostaLocale('it_IT.UTF-8');
      expect(r['ok'], isFalse);
    });
  });
}
