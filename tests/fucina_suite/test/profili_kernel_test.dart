import 'dart:convert';
import 'dart:io';

import 'package:minervad/services/fucina/profili_kernel.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporanea;
  late ProfiliKernel archivio;

  setUp(() {
    temporanea = Directory.systemTemp.createTempSync('fucina-profili-');
    archivio = ProfiliKernel(statoDir: temporanea.path);
  });

  tearDown(() => temporanea.deleteSync(recursive: true));

  Map<String, dynamic> dati({String cpu = 'CPU di prova'}) => {
    'nome': 'Gaming',
    'scelte': {
      'preset': ['gaming'],
      'scorte': ['filesystem'],
      'aggiunti': ['xpad'],
    },
    'hardware': {
      'cpu': cpu,
      'fornitore': 'GenuineIntel',
      'livelloX86': 'v3',
      'seriale': 'non deve essere salvato',
    },
    'evidenze': {
      'dispositivi': 12,
      'moduli': 40,
      'dispositiviStorici': 3,
      'filesystemMontati': ['btrfs', 'tmpfs'],
      'lsmAttivi': ['landlock', 'yama'],
      'percorsoPrivato': '/home/utente',
    },
  };

  Future<Map<String, dynamic>> salva({
    String nome = 'Gaming',
    String cpu = 'CPU di prova',
  }) => archivio.salva(
    nome: nome,
    scelte: Map<String, dynamic>.from(dati(cpu: cpu)['scelte'] as Map),
    hardware: Map<String, dynamic>.from(dati(cpu: cpu)['hardware'] as Map),
    evidenze: Map<String, dynamic>.from(dati(cpu: cpu)['evidenze'] as Map),
  );

  test(
    'salva e ricarica preferenze con impronta ed evidenze consentite',
    () async {
      final salvato = await salva();
      final caricato = await archivio.carica(salvato['id']);

      expect(caricato?['scelte'], {
        'preset': ['gaming'],
        'scorte': ['filesystem'],
        'aggiunti': ['xpad'],
      });
      expect(caricato?['hardware'], {
        'cpu': 'CPU di prova',
        'fornitore': 'GenuineIntel',
        'livelloX86': 'v3',
      });
      expect(
        caricato?['evidenze'],
        containsPair('filesystemMontati', ['btrfs', 'tmpfs']),
      );
      final contenuto = File(
        '${temporanea.path}/profili-kernel.json',
      ).readAsStringSync();
      expect(contenuto, isNot(contains('seriale')));
      expect(contenuto, isNot(contains('/home/utente')));
    },
  );

  test(
    'aggiorna il nome senza duplicare il profilo o cambiare id e creazione',
    () async {
      final primo = await salva();
      final secondo = await salva(nome: 'gAMING', cpu: 'CPU aggiornata');

      expect(secondo['id'], primo['id']);
      expect(secondo['creato'], primo['creato']);
      expect(secondo['hardware']['cpu'], 'CPU aggiornata');
      expect(await archivio.elenco(), hasLength(1));
    },
  );

  test('limita l’archivio a venti profili e rifiuta nomi non validi', () async {
    for (var i = 0; i < ProfiliKernel.massimo; i++) {
      await salva(nome: 'Profilo $i');
    }
    await expectLater(
      salva(nome: 'Profilo oltre limite'),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(
      salva(nome: 'nome\nnon valido'),
      throwsA(isA<FormatException>()),
    );
  });

  test('scritture concorrenti e cancellazioni non perdono profili', () async {
    await Future.wait([
      salva(nome: 'Profilo uno'),
      salva(nome: 'Profilo due'),
      salva(nome: 'Profilo tre'),
    ]);
    final profili = await archivio.elenco();
    expect(profili, hasLength(3));

    final eliminato = await archivio.elimina(profili.first['id']);
    expect(eliminato, isTrue);
    expect(await archivio.elenco(), hasLength(2));
    expect(await archivio.elimina('00000000000000000000'), isFalse);
  });

  test(
    'indice JSON danneggiato non blocca la ricreazione dell’archivio',
    () async {
      await File(
        '${temporanea.path}/profili-kernel.json',
      ).writeAsString('{rotto');
      expect(await archivio.elenco(), isEmpty);
      await salva();
      final json =
          jsonDecode(
                File(
                  '${temporanea.path}/profili-kernel.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(json['profili'], hasLength(1));
    },
  );
}
