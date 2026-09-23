import 'dart:io';

import 'package:minervad/services/custodia/segreti.dart';
import 'package:test/test.dart';

/// Prove sul controllo dei segreti.
///
/// ── Il rapporto che decide ogni riga di queste prove ───────────────────────
///
/// Un **falso allarme** costa un clic su «salvalo lo stesso». Una **chiave
/// finita nella storia** costa cambiare ogni chiave che quella apriva, e
/// riscrivere ogni salvataggio successivo per toglierla.
///
/// Con questo rapporto si è larghi: meglio dieci allarmi in più che uno in
/// meno. Ma non *arbitrari* — un allarme che scatta a caso si impara a
/// ignorare, e allora non serve più a niente. Da qui le due metà di queste
/// prove: quello che **deve** far scattare l'allarme, e quello che **non deve**.
// ── I finti segreti si compongono a pezzi ──────────────────────────────────
//
// Un file di prova per un controllo sui segreti contiene, per forza, le cose
// che il controllo cerca — e quindi fa scattare il controllo su sé stesso.
// Misurato: sui 156 file di Minerva pronti per il primo salvataggio, l'unica
// cosa che si fermava era **questo file**.
//
// La risposta sbagliata sarebbe indebolire il controllo, o tenere un elenco di
// file da saltare (che poi marcisce). Quella giusta è comporre le stringhe:
// quello che finisce nella variabile è identico a quello vero — e quindi la
// prova prova ancora quello che deve — ma il sorgente non lo contiene.
//
// Se non si facesse, ogni salvataggio futuro del progetto chiederebbe
// «salvalo lo stesso», e in un mese quel pulsante si premerebbe senza leggere.

const _capo = '-----BEGIN ';
const _coda = 'PRIVATE KEY-----';
final _chiavePrivata = '${_capo}OPENSSH $_coda';
final _gettoneGitHub = 'gh' 'p_${'A' * 36}';
final _gettoneNuovo = 'github' '_pat_${'a' * 30}';
final _chiaveAmazon = 'AK' 'IAIOSFODNN7EXAMPLE';
final _chiaveGoogle = 'AI' 'za${'B' * 35}';
final _indirizzoConPassword = 'postgres://tizio:' 'segretissima' '@casa/db';

void main() {
  late Directory temp;
  const guardia = Segreti();

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('minerva-segreti-');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<void> scrivi(String nome, String cosa) async {
    final f = File('${temp.path}/$nome');
    await f.parent.create(recursive: true);
    await f.writeAsString(cosa);
  }

  Future<List<Avviso>> su(List<String> percorsi) =>
      guardia.guarda(temp.path, percorsi);

  // ── Quello che deve fermarsi ───────────────────────────────────────────

  group('dal nome', () {
    test('una chiave ssh', () async {
      await scrivi('id_rsa', 'qualsiasi cosa');
      final a = await su(['id_rsa']);
      expect(a.single.perche, contains('id_rsa'));
    });

    test('anche vuota: se è lì, o è una chiave o è un errore', () async {
      await scrivi('id_ed25519', '');
      expect((await su(['id_ed25519'])).length, 1);
    });

    test('un .env', () async {
      await scrivi('.env', 'CIAO=1');
      expect((await su(['.env'])).single.perche, contains('.env'));
    });

    test('qualunque cosa dentro una cartella di chiavi', () async {
      await scrivi('roba/.ssh/appunti.txt', 'niente di che');
      final a = await su(['roba/.ssh/appunti.txt']);
      expect(a.single.perche, contains('cartella di chiavi'));
    });

    test('le estensioni delle chiavi', () async {
      for (final n in ['server.pem', 'privata.key', 'store.p12', 'x.kdbx']) {
        await scrivi(n, 'x');
        expect((await su([n])).length, 1, reason: n);
      }
    });

    test('«.key.esempio» è ancora una chiave', () async {
      await scrivi('config.key.esempio', 'x');
      expect((await su(['config.key.esempio'])).length, 1);
    });
  });

  group('dal contenuto', () {
    test('una chiave privata, comunque si chiami il file', () async {
      await scrivi('appunti.txt', '$_chiavePrivata\nb3Blb\n');
      expect((await su(['appunti.txt'])).single.perche,
          contains('chiave privata'));
    });

    test('un gettone di GitHub', () async {
      await scrivi('note.md', 'il mio gettone: $_gettoneGitHub\n');
      expect((await su(['note.md'])).single.perche, contains('GitHub'));
    });

    test('un gettone di GitHub della forma nuova', () async {
      await scrivi('note.md', '$_gettoneNuovo\n');
      expect((await su(['note.md'])).single.perche, contains('GitHub'));
    });

    test('una chiave di Amazon e una di Google', () async {
      await scrivi('a.txt', _chiaveAmazon);
      await scrivi('g.txt', _chiaveGoogle);
      expect((await su(['a.txt'])).single.perche, contains('Amazon'));
      expect((await su(['g.txt'])).single.perche, contains('Google'));
    });

    test('una password dentro un indirizzo', () async {
      await scrivi('config.ini', 'db=$_indirizzoConPassword\n');
      expect((await su(['config.ini'])).single.perche, contains('indirizzo'));
    });
  });

  // ── Quello che NON deve fermarsi ───────────────────────────────────────
  //
  // Metà importante quanto l'altra: questo programma vive dentro un progetto
  // che parla di password, chiavi e polkit in ogni terzo commento. Se questi
  // scattassero, il controllo verrebbe spento il primo giorno.

  group('i falsi allarmi che non devono scattare', () {
    test('un commento che PARLA di password', () async {
      await scrivi('spiegazione.dart',
          '/// Il segreto sta in un file leggibile solo dal proprietario, e la\n'
          '/// password non si scrive mai qui dentro. Vedi canale_segreto.dart.\n');
      expect(await su(['spiegazione.dart']), isEmpty);
    });

    test('una regola di polkit che nomina «auth_admin»', () async {
      await scrivi('org.minerva.radice.policy',
          '<allow_active>auth_admin_keep</allow_active>\n');
      expect(await su(['org.minerva.radice.policy']), isEmpty);
    });

    test('un indirizzo normale, senza password', () async {
      await scrivi('README.md',
          'Si scarica da https://github.com/tizio/roba.git\n'
          'e la documentazione sta su http://esempio.it/doc\n');
      expect(await su(['README.md']), isEmpty);
    });

    test('una stringa che somiglia a un gettone ma è corta', () async {
      await scrivi('note.md', 'gh' 'p_corto\nAK' 'IA123\n');
      expect(await su(['note.md']), isEmpty);
    });

    test('un file binario non si guarda dentro', () async {
      // Dentro dati compressi le forme scattano a caso, e un allarme che
      // scatta a caso si impara a ignorare.
      final f = File('${temp.path}/immagine.png');
      await f.writeAsBytes([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0,
        ...List.generate(4000, (i) => (i * 37) % 256),
      ]);
      expect(await su(['immagine.png']), isEmpty);
    });

    test('un file che non esiste più non è un allarme', () async {
      expect(await su(['sparito.txt']), isEmpty);
    });

    test('«monkey.pem.md», che parla di pem ma è un documento', () async {
      // Questo SCATTA, ed è voluto: «.pem.» nel nome basta. È il tipo di falso
      // allarme che si accetta — costa un clic, e la regola che lo eviterebbe
      // lascerebbe passare `chiave.pem.backup`.
      await scrivi('monkey.pem.md', 'parliamo di certificati');
      expect((await su(['monkey.pem.md'])).length, 1);
    });
  });

  // ── L'insieme ──────────────────────────────────────────────────────────

  test('dice PERCHÉ, non solo che c\'è qualcosa', () async {
    // Il perché è quello che permette di decidere in un secondo se è un falso
    // allarme, invece di premere «salvalo lo stesso» per abitudine.
    await scrivi('id_rsa', 'x');
    final a = await su(['id_rsa']);
    expect(a.single.perche, isNotEmpty);
    expect(a.single.toJson()['perche'], isNotEmpty);
    expect(a.single.toJson()['percorso'], 'id_rsa');
  });

  test('su cento file normali non dice niente', () async {
    final tutti = <String>[];
    for (var i = 0; i < 100; i++) {
      final n = 'src/file$i.dart';
      await scrivi(n, 'void main() { print("ciao $i"); }\n');
      tutti.add(n);
    }
    expect(await su(tutti), isEmpty);
  });
}
