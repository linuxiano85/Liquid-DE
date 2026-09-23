import 'dart:io';
import 'package:test/test.dart';
import 'package:minervad/services/file_service.dart';

/// Chi c'è già in destinazione.
///
/// Prima di questa domanda il gestore file copiava e basta: se in
/// destinazione c'era un nome uguale, il demone ne inventava un altro
/// («prova (1).txt») senza dire niente. Non si perdeva nulla — ed è per
/// questo che è passato inosservato per mesi — ma nessuno aveva deciso.
void main() {
  late Directory radice;
  late FileService fs;

  setUp(() {
    radice = Directory.systemTemp.createTempSync('minerva-conflitti');
    fs = FileService();
  });
  tearDown(() => radice.deleteSync(recursive: true));

  String scrivi(String dove, String nome, [String testo = 'x']) {
    final d = Directory('${radice.path}/$dove')..createSync(recursive: true);
    final f = File('${d.path}/$nome')..writeAsStringSync(testo);
    return f.path;
  }

  test('dice solo i nomi che ci sono davvero', () {
    final uno = scrivi('a', 'prova.txt');
    final due = scrivi('a', 'solo.txt');
    scrivi('b', 'prova.txt');

    expect(fs.conflitti([uno, due], '${radice.path}/b'), ['prova.txt']);
  });

  test('destinazione vuota: nessun conflitto', () {
    final uno = scrivi('a', 'prova.txt');
    Directory('${radice.path}/vuota').createSync();
    expect(fs.conflitti([uno], '${radice.path}/vuota'), isEmpty);
  });

  test('un file non è in conflitto con sé stesso', () {
    // Capita trascinando dentro la cartella in cui si è già: senza questa
    // riga si chiederebbe «sostituisco prova.txt con prova.txt?».
    final uno = scrivi('a', 'prova.txt');
    expect(fs.conflitti([uno], '${radice.path}/a'), isEmpty);
  });

  test('anche le cartelle contano', () {
    Directory('${radice.path}/a/foto').createSync(recursive: true);
    Directory('${radice.path}/b/foto').createSync(recursive: true);
    expect(fs.conflitti(['${radice.path}/a/foto'], '${radice.path}/b'),
        ['foto']);
  });
}
