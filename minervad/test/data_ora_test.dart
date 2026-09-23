import 'dart:io';

import 'package:test/test.dart';
import 'package:minervad/services/data_ora_service.dart';

/// Un finto `timedatectl`, per non toccare l'orologio della macchina su cui
/// girano le prove. Registra ogni chiamata in un file, così si può controllare
/// non solo che cosa risponde il servizio ma anche quante volte ha lanciato un
/// processo — che è il punto della cache dei fusi.
File _finto(Directory d, {required String show, int esito = 0, String errore = ''}) {
  final f = File('${d.path}/timedatectl');
  f.writeAsStringSync('''
#!/bin/sh
echo "\$@" >> "${d.path}/chiamate.txt"
case "\$1" in
  show) cat <<'FINE'
$show
FINE
  ;;
  list-timezones) printf 'Europe/Rome\\nEurope/Paris\\nAmerica/New_York\\nUTC\\n' ;;
  *) [ -n '$errore' ] && echo '$errore' >&2 ;;
esac
exit $esito
''');
  Process.runSync('chmod', ['+x', f.path]);
  return f;
}

int _chiamate(Directory d, String cosa) {
  final f = File('${d.path}/chiamate.txt');
  if (!f.existsSync()) return 0;
  return f.readAsLinesSync().where((r) => r.startsWith(cosa)).length;
}

/// Il file QML che consuma questo stato.
File _dataOraQml() {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    final f = File('${dir.path}/minerva-shell/settings/sections/DataOra.qml');
    if (f.existsSync()) return f;
    dir = dir.parent;
  }
  fail('non trovo minerva-shell/settings/sections/DataOra.qml');
}

const _veroShow = '''
Timezone=Europe/Rome
LocalRTC=no
CanNTP=yes
NTP=yes
NTPSynchronized=yes
TimeUSec=Mon 2026-08-10 01:21:11 CEST
RTCTimeUSec=Sun 2026-08-09 23:21:11 UTC''';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('minerva-dataora'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('data e ora — lettura', () {
    test('legge l\'uscita vera di `timedatectl show`', () {
      // Copiata da questa macchina il 10 agosto 2026.
      final s = statoDaShow(_veroShow);
      expect(s['timezone'], 'Europe/Rome');
      expect(s['ntp'], isTrue);
      expect(s['ntpPossibile'], isTrue);
      expect(s['sincronizzato'], isTrue);
      expect(s['rtcLocale'], isFalse);
    });

    test('un\'uscita vuota non inventa niente', () {
      // Il pannello mostra i campi vuoti, e va bene: quello che NON deve
      // succedere è che dica «fuso: UTC» o «sincronizzato» senza saperlo.
      final s = statoDaShow('');
      expect(s['timezone'], '');
      expect(s['ntp'], isFalse);
      expect(s['sincronizzato'], isFalse);
    });

    test('le righe senza «=» si saltano invece di far cadere tutto', () {
      final s = statoDaShow('rumore\n\nTimezone=UTC\n=vuoto\nNTP=no');
      expect(s['timezone'], 'UTC');
      expect(s['ntp'], isFalse);
    });

    test('un valore che contiene «=» resta intero', () {
      // `TimeUSec` no, ma il principio conta: si spezza sul PRIMO uguale.
      final s = statoDaShow('Timezone=Europe/Rome\nX=a=b');
      expect(s['timezone'], 'Europe/Rome');
    });

    test('se `timedatectl` non esiste lo dice, e non mente sullo stato',
        () async {
      final s = await DataOraService(comando: '${tmp.path}/non-esiste').stato();
      expect(s['errore'], isNotNull);
      expect('${s['errore']}', contains('non è disponibile'));
      expect(s['ntpPossibile'], isFalse,
          reason: 'senza `timedatectl` la pagina deve poter spegnere i comandi');
    });

    test('ogni campo letto dal QML esiste davvero nello stato del demone',
        () async {
      // Stesso vincolo dello stato di sistema, e stesso guasto muto se salta:
      // `DataOra.qml` legge i campi per nome, e un nome cambiato lascerebbe la
      // pagina a mostrare per sempre i valori di partenza.
      //
      // Si guarda SOLO dentro il gestore che riceve lo stato: cercare `s.x`
      // in tutto il file pescava anche `Core.Strings.lang`, e la prova
      // falliva accusando il demone di non mandare un campo che non ha mai
      // avuto niente a che fare con l'orologio.
      final qml = _dataOraQml().readAsStringSync();
      final inizio = qml.indexOf('function onDatetimeStateReceived(s)');
      expect(inizio, greaterThan(0),
          reason: 'il gestore dello stato è sparito o si chiama in un altro modo');
      final fine = qml.indexOf('function ', inizio + 10);
      final corpo = qml.substring(inizio, fine > 0 ? fine : qml.length);
      final letti =
          RegExp(r'\bs\.(\w+)').allMatches(corpo).map((m) => m.group(1)!).toSet();
      expect(letti, isNotEmpty);

      final offerti = statoDaShow(_veroShow).keys.toSet()..add('errore');
      for (final campo in letti) {
        expect(offerti, contains(campo),
            reason: '`DataOra.qml` legge "$campo", che il demone non manda');
      }
    });
  });

  group('data e ora — l\'elenco dei fusi', () {
    test('si legge una volta sola', () async {
      final s = DataOraService(comando: _finto(tmp, show: _veroShow).path);
      expect((await s.fusi()).length, 4);
      expect((await s.fusi()).first, 'Europe/Rome');
      expect(_chiamate(tmp, 'list-timezones'), 1,
          reason: 'seicento voci che non cambiano mai: rileggerle a ogni '
              'apertura del pannello è un processo e 12 KB buttati');
    });

    test('se il comando manca l\'elenco è vuoto, non un\'eccezione', () async {
      final s = DataOraService(comando: '${tmp.path}/non-esiste');
      expect(await s.fusi(), isEmpty);
    });
  });

  group('data e ora — scrittura', () {
    test('un fuso inventato non arriva nemmeno a chiedere la password',
        () async {
      // Il controllo non è contro un\'iniezione (`Process.run` senza shell non
      // ne ha), è contro una finestrella di polkit aperta per niente.
      final s = DataOraService(comando: _finto(tmp, show: _veroShow).path);
      for (final brutto in [
        '',
        '/etc/passwd',
        '../../etc',
        'Europe/Rome; rm -rf ~',
        'Europe/Non/Esiste/Affatto',
      ]) {
        final r = await s.impostaFuso(brutto);
        expect(r['ok'], isFalse, reason: 'accettato "$brutto"');
      }
      expect(_chiamate(tmp, 'set-timezone'), 0);
    });

    test('un fuso vero passa', () async {
      final s = DataOraService(comando: _finto(tmp, show: _veroShow).path);
      expect((await s.impostaFuso('Europe/Paris'))['ok'], isTrue);
      expect(_chiamate(tmp, 'set-timezone Europe/Paris'), 1);
    });

    test('un fuso plausibile ma sconosciuto viene fermato', () async {
      final s = DataOraService(comando: _finto(tmp, show: _veroShow).path);
      final r = await s.impostaFuso('Europe/Atlantide');
      expect(r['ok'], isFalse);
      expect('${r['errore']}', contains('sconosciuto'));
    });

    test('l\'ora a mano vuole il formato giusto', () async {
      final s = DataOraService(comando: _finto(tmp, show: _veroShow).path);
      for (final brutto in ['adesso', '10/08/2026 14:30', '2026-8-10 14:30']) {
        expect((await s.impostaOra(brutto))['ok'], isFalse,
            reason: 'accettato "$brutto"');
      }
      expect(_chiamate(tmp, 'set-time'), 0);
    });

    test('con la sincronizzazione accesa l\'ora a mano si rifiuta, e spiega',
        () async {
      // `timedatectl` la rifiuterebbe comunque. Il punto è dirlo PRIMA e con
      // parole utili, invece di far comparire la richiesta della password per
      // un comando che fallirà.
      final s = DataOraService(comando: _finto(tmp, show: _veroShow).path);
      final r = await s.impostaOra('2026-08-10 14:30:00');
      expect(r['ok'], isFalse);
      expect('${r['errore']}', contains('sincronizzazione'));
      expect(_chiamate(tmp, 'set-time'), 0);
    });

    test('con la sincronizzazione spenta l\'ora a mano passa', () async {
      final s = DataOraService(
          comando: _finto(tmp, show: 'Timezone=UTC\nCanNTP=yes\nNTP=no').path);
      expect((await s.impostaOra('2026-08-10 14:30:00'))['ok'], isTrue);
      expect(_chiamate(tmp, 'set-time 2026-08-10 14:30:00'), 1);
    });

    test('un rifiuto di polkit torna con il suo perché, non come «fatto»',
        () async {
      // È il caso che capita davvero: l'utente preme «Annulla» nella
      // finestrella della password. Se qui tornasse ok, la pagina si
      // ridisegnerebbe come se il fuso fosse cambiato.
      final finto = _finto(tmp,
          show: _veroShow, esito: 1, errore: 'Interactive authentication required.');
      final s = DataOraService(comando: finto.path);
      final r = await s.impostaNtp(false);
      expect(r['ok'], isFalse);
      expect('${r['errore']}', contains('authentication'));
    });
  });
}
