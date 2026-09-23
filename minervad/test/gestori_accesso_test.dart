import 'dart:io';

import 'package:test/test.dart';
import 'package:minervad/services/gestori_accesso_service.dart';

// Le prove si costruiscono le loro cartelle di unità systemd: nessuna dipende
// da quali gestori di accessi ci sono su QUESTO computer, che è il modo più
// facile di scrivere una prova che passa oggi e non vuol dire niente domani.
//
// La prova che conta più di tutte è l'ultima: il nome dell'unità arriva da una
// finestra e finisce dentro un comando eseguito da root. Se quel controllo
// cede, «cambia gestore di accessi» diventa «abilita qualunque servizio».

const _unitaDM = '''
[Unit]
Description=Un gestore di accessi

[Install]
Alias=display-manager.service
''';

const _unitaNormale = '''
[Unit]
Description=Un servizio qualunque

[Install]
WantedBy=multi-user.target
''';

void main() {
  late Directory tana;
  late Directory etc;
  late Directory lib;

  setUp(() async {
    tana = await Directory.systemTemp.createTemp('minerva-gestori-');
    etc = await Directory('${tana.path}/etc').create();
    lib = await Directory('${tana.path}/lib').create();
  });

  tearDown(() async => tana.delete(recursive: true));

  GestoriAccessoService servizio() => GestoriAccessoService(
        cartelleUnita: [etc.path, lib.path],
        collegamentoAttuale: '${etc.path}/display-manager.service',
      );

  Future<void> unita(Directory d, String nome, String testo) =>
      File('${d.path}/$nome').writeAsString(testo);

  group('Chi apre la porta', () {
    test('trova solo chi si dichiara gestore di accessi', () async {
      await unita(lib, 'greetd.service', _unitaDM);
      await unita(lib, 'plasmalogin.service', _unitaDM);
      await unita(lib, 'bluetooth.service', _unitaNormale);

      final g = await servizio().elenco();
      expect(g.map((x) => x.unita),
          unorderedEquals(['greetd.service', 'plasmalogin.service']));
    });

    test('un gestore che non conosciamo compare lo stesso', () async {
      // L'elenco non è scritto a mano: chi installa qualcosa di nuovo lo vede,
      // e chi disinstalla lo vede sparire. Un elenco a mano è un elenco che
      // invecchia il giorno dopo.
      await unita(lib, 'sconosciuto.service', _unitaDM);

      final g = await servizio().elenco();
      expect(g.single.unita, 'sconosciuto.service');
      expect(g.single.nome, 'sconosciuto');
    });

    test('i nomi noti si mostrano per esteso', () async {
      await unita(lib, 'greetd.service', _unitaDM);
      final g = await servizio().elenco();
      expect(g.single.nome, 'Minerva');
      expect(g.single.nostro, isTrue);
    });

    test('sa quale è acceso adesso, leggendo il collegamento', () async {
      await unita(lib, 'greetd.service', _unitaDM);
      await unita(lib, 'gdm.service', _unitaDM);
      await Link('${etc.path}/display-manager.service')
          .create('${lib.path}/gdm.service');

      final g = await servizio().elenco();
      expect(g.firstWhere((x) => x.unita == 'gdm.service').attuale, isTrue);
      expect(g.firstWhere((x) => x.unita == 'greetd.service').attuale, isFalse);
    });

    test('senza collegamento nessuno risulta acceso', () async {
      await unita(lib, 'greetd.service', _unitaDM);
      final g = await servizio().elenco();
      expect(g.single.attuale, isFalse);
      expect(await servizio().unitaAttuale(), isEmpty);
    });

    test('/etc vince su /usr/lib, come per systemd', () async {
      // Una copia in `/etc` sostituisce quella di sistema: mostrarle tutte e
      // due farebbe scegliere due volte la stessa cosa.
      await unita(lib, 'greetd.service', _unitaDM);
      await unita(etc, 'greetd.service', _unitaDM);

      final g = await servizio().elenco();
      expect(g, hasLength(1));
    });

    test('una cartella che non esiste non fa cadere il resto', () async {
      final s = GestoriAccessoService(
        cartelleUnita: ['${tana.path}/non-c-e', lib.path],
        collegamentoAttuale: '${etc.path}/display-manager.service',
      );
      await unita(lib, 'greetd.service', _unitaDM);
      expect((await s.elenco()).single.unita, 'greetd.service');
    });
  });

  // ── Il controllo che vale per due ────────────────────────────────────────
  //
  // Questo nome finisce dentro `systemctl enable …` eseguito da root. È il
  // punto in cui una svista non dà un difetto: dà una scalata di privilegi.
  group('il nome dell\'unità', () {
    test('accetta i nomi veri', () {
      for (final n in [
        'greetd.service',
        'plasmalogin.service',
        'cosmic-greeter.service',
        'getty@tty1.service',
        'x_11.service',
      ]) {
        expect(GestoriAccessoService.nomeAccettabile(n), isTrue, reason: n);
      }
    });

    test('rifiuta tutto il resto', () {
      for (final n in [
        '',
        'greetd',                          // senza .service
        '../../../etc/passwd.service',     // risalita
        '/usr/lib/systemd/system/x.service',
        'greetd.service; rm -rf ~',        // due comandi in uno
        r'greetd.service$(id)',
        'greetd.service `id`',
        'greetd.service\nplasmalogin.service',
        'greetd.socket',
        'a b.service',
      ]) {
        expect(GestoriAccessoService.nomeAccettabile(n), isFalse,
            reason: 'doveva rifiutare «$n»');
      }
    });

    test('un nome lunghissimo non passa', () {
      expect(
          GestoriAccessoService.nomeAccettabile('${'a' * 200}.service'), isFalse);
    });

    test('un file con un nome storto non entra nemmeno nell\'elenco', () async {
      // Anche se qualcuno riuscisse a creare un file così in una cartella di
      // unità, non deve arrivare all'interfaccia: da lì tornerebbe indietro
      // come scelta dell'utente, e sarebbe già dentro.
      await unita(lib, 'strano nome.service', _unitaDM);
      expect(await servizio().elenco(), isEmpty);
    });
  });
}
