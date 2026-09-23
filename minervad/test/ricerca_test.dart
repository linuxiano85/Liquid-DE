import 'dart:io';

import 'package:minervad/services/ricerca_service.dart';
import 'package:test/test.dart';

/// La ricerca è il posto in cui un gestore file si gioca la reputazione: se
/// non trova, non serve; se blocca la finestra mentre cerca, non si usa.
void main() {
  late Directory radice;
  late RicercaService r;

  setUp(() {
    radice = Directory.systemTemp.createTempSync('minerva-ricerca-');
    r = RicercaService();
    // Un alberello con qualche trappola dentro.
    Directory('${radice.path}/documenti/lavoro').createSync(recursive: true);
    Directory('${radice.path}/foto/2024').createSync(recursive: true);
    Directory('${radice.path}/.nascosta').createSync();
    File('${radice.path}/documenti/fattura-marzo.pdf').writeAsStringSync('x');
    File('${radice.path}/documenti/lavoro/fattura-aprile.pdf').writeAsStringSync('x');
    File('${radice.path}/foto/2024/gita.jpg').writeAsStringSync('x');
    File('${radice.path}/.nascosta/fattura-segreta.pdf').writeAsStringSync('x');
    Directory('${radice.path}/fatture').createSync();
    File('${radice.path}/fatture/riepilogo.txt').writeAsStringSync('x');
  });

  tearDown(() => radice.deleteSync(recursive: true));

  Future<List<Map<String, dynamic>>> tutti(Stream<Map<String, dynamic>> s) async {
    final out = <Map<String, dynamic>>[];
    await for (final m in s) {
      if (m['voci'] != null) {
        out.addAll((m['voci'] as List).cast<Map<String, dynamic>>());
      }
    }
    return out;
  }

  group('ricerca nelle sottocartelle', () {
    test('trova anche quello che sta in fondo a un ramo', () async {
      final v = await tutti(r.cerca('a', radice.path, 'fattura'));
      final nomi = v.map((e) => e['name']).toSet();
      expect(nomi, contains('fattura-marzo.pdf'));
      expect(nomi, contains('fattura-aprile.pdf'));
    });

    // Chi cerca «fattura» non vuole tutto quello che sta DENTRO una cartella
    // chiamata «fatture»: vuole le cose che si chiamano così.
    test('guarda il nome, non il percorso', () async {
      // «fattur» prende sia i file sia la cartella che si chiama «fatture».
      final v = await tutti(r.cerca('b', radice.path, 'fattur'));
      final nomi = v.map((e) => e['name']).toSet();
      // La cartella si chiama così: giusto trovarla.
      expect(nomi, contains('fatture'));
      // Quello che ci sta DENTRO no: non si chiama «fattura» e chi cerca non
      // sta chiedendo «tutto quello che sta nelle fatture».
      expect(nomi, isNot(contains('riepilogo.txt')));
    });

    test('le cartelle nascoste restano nascoste', () async {
      final v = await tutti(r.cerca('c', radice.path, 'fattura'));
      expect(v.map((e) => e['name']), isNot(contains('fattura-segreta.pdf')));
    });

    test('e si vedono se le si chiede', () async {
      final v = await tutti(
          r.cerca('d', radice.path, 'fattura', ancheNascosti: true));
      expect(v.map((e) => e['name']), contains('fattura-segreta.pdf'));
    });

    // In una ricerca il percorso conta quanto il nome: tre file chiamati
    // «appunti.txt» si distinguono solo da dove stanno.
    test('ogni risultato dice anche dove sta', () async {
      final v = await tutti(r.cerca('e', radice.path, 'fattura-aprile'));
      expect(v.single['dove'], '${radice.path}/documenti/lavoro');
    });

    test('cercare il nulla non cerca niente', () async {
      final v = await tutti(r.cerca('f', radice.path, '   '));
      expect(v, isEmpty);
    });

    test('la fine si annuncia, con quanti ne ha trovati', () async {
      Map<String, dynamic>? ultimo;
      await for (final m in r.cerca('g', radice.path, 'fattura')) {
        if (m['fine'] == true) ultimo = m;
      }
      expect(ultimo, isNotNull);
      expect(ultimo!['trovati'], 2);
      expect(ultimo['fermata'], isFalse);
    });

    // Chi ha trovato quello che cercava non deve aspettare la fine.
    test('si può fermare a metà', () async {
      final s = r.cerca('h', radice.path, 'fattura');
      final letti = <Map<String, dynamic>>[];
      await for (final m in s) {
        letti.add(m);
        r.ferma('h');
      }
      expect(letti.last['fine'], isTrue);
    });

    // `/proc` contiene una cartella per ogni processo e cambia mentre la si
    // legge: scendendoci, una ricerca in `/` non finisce più.
    test('le cartelle del sistema non si attraversano', () async {
      Map<String, dynamic>? ultimo;
      await for (final m in r.cerca('i', '/proc', 'qualcosa')) {
        if (m['fine'] == true) ultimo = m;
      }
      expect(ultimo!['trovati'], 0);
    });
  });
}
