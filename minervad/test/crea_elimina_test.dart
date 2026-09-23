import 'dart:io';
import 'package:test/test.dart';
import 'package:minervad/services/file_service.dart';

/// Creare un documento vuoto, e cancellare senza cestino.
///
/// Due cose che c'erano in ogni gestore file del mondo tranne che nel nostro.
/// La seconda era peggio della prima: Maiusc+Canc non faceva NIENTE, e chi la
/// premeva credeva di aver cancellato.
void main() {
  late Directory radice;
  late FileService fs;

  setUp(() {
    radice = Directory.systemTemp.createTempSync('minerva-crea');
    fs = FileService();
  });
  tearDown(() => radice.deleteSync(recursive: true));

  test('crea un file vuoto', () async {
    final r = await fs.creaFile('${radice.path}/appunto.txt');
    expect(r['ok'], isTrue);
    expect(File('${radice.path}/appunto.txt').existsSync(), isTrue);
    expect(File('${radice.path}/appunto.txt').lengthSync(), 0);
  });

  test('non scrive sopra un nome già preso', () async {
    File('${radice.path}/c.txt').writeAsStringSync('roba importante');
    final r = await fs.creaFile('${radice.path}/c.txt');
    expect(r['ok'], isFalse);
    // La ragione vera per cui questa prova esiste: `File.create` non si
    // lamenta se il file c'è, e un «fatto» avrebbe lasciato credere di avere
    // un file nuovo mentre si guardava quello vecchio.
    expect(File('${radice.path}/c.txt').readAsStringSync(), 'roba importante');
  });

  test('elimina file e cartelle, e conta quel che ha fatto', () async {
    File('${radice.path}/a.txt').writeAsStringSync('x');
    Directory('${radice.path}/dentro').createSync();
    File('${radice.path}/dentro/b.txt').writeAsStringSync('y');

    final r = await fs.eliminaDefinitivamente(
        ['${radice.path}/a.txt', '${radice.path}/dentro']);
    expect(r['ok'], isTrue);
    expect(r['eliminati'], 2);
    expect(radice.listSync(), isEmpty);
  });

  test('quel che non c\'è non è un errore', () async {
    // Capita: due comandi sullo stesso file, o una cartella già sparita.
    // Trattarlo come errore riempirebbe lo schermo di allarmi per niente.
    final r = await fs.eliminaDefinitivamente(['${radice.path}/mai-esistito']);
    expect(r['ok'], isTrue);
    expect(r['eliminati'], 0);
  });
}
