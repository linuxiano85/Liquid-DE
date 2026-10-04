import 'package:minervad/services/fucina/sorgenti.dart';
import 'package:test/test.dart';

// Le sorgenti della Fucina: l'elenco da kernel.org e le somme di controllo.
//
// La rete è finta: una prova che va su kernel.org misura la rete di chi la
// lancia, e il giorno che esce un kernel nuovo diventerebbe rossa da sola.
void main() {
  const rilasci = '''
{
  "latest_stable": {"version": "6.17.2"},
  "releases": [
    {"iseol": false, "version": "6.18-rc3", "moniker": "mainline",
     "released": {"isodate": "2026-09-28"}},
    {"iseol": false, "version": "6.17.2", "moniker": "stable",
     "released": {"isodate": "2026-09-25"}},
    {"iseol": true, "version": "6.16.12", "moniker": "stable",
     "released": {"isodate": "2026-09-20"}},
    {"iseol": false, "version": "6.12.50", "moniker": "longterm",
     "released": {"isodate": "2026-09-24"}},
    {"iseol": false, "version": "next-20260929", "moniker": "linux-next",
     "released": {"isodate": "2026-09-29"}}
  ]
}''';

  group('l\'elenco delle versioni', () {
    test('solo stable e longterm: niente candidate, niente linux-next', () {
      final v = Sorgenti.leggiRilasci(rilasci);
      expect(v.map((x) => x['versione']), ['6.17.2', '6.16.12', '6.12.50']);
      expect(v[1]['finita'], isTrue);
      expect(v[2]['tipo'], 'longterm');
    });

    test('CachyOS: BORE e serie base si chiedono per ogni serie, separati',
        () async {
      // Com'è davvero il loro repository il 30 settembre 2026: BORE c'è
      // per tutte le serie, la serie base solo fino alla 6.17.
      final chiesti = <Uri>[];
      final s = Sorgenti(
        testo: (u) async => rilasci,
        esiste: (u) async {
          chiesti.add(u);
          if (u.path.contains('/sched/')) return !u.path.contains('/6.12/');
          return u.path.contains('/6.16/');
        },
      );
      final r = await s.versioni();
      expect(r['ok'], isTrue);
      final v = {for (final x in r['versioni'] as List) x['versione']: x};
      expect(v['6.17.2']['cachyos'], isTrue);
      expect(v['6.17.2']['cachyosBase'], isFalse);
      expect(v['6.16.12']['cachyosBase'], isTrue);
      expect(v['6.12.50']['cachyos'], isFalse);
      expect(chiesti.every((u) => u.host == 'raw.githubusercontent.com'), isTrue);
    });

    test('senza rete lo dice, invece di dare un elenco vuoto muto', () async {
      final s = Sorgenti(testo: (_) async => null, esiste: (_) async => false);
      final r = await s.versioni();
      expect(r['ok'], isFalse);
      expect(r['errore'], contains('kernel.org'));
    });

    test('una risposta che non capisce non fa cadere niente', () async {
      final s = Sorgenti(testo: (_) async => '<html>', esiste: (_) async => false);
      expect((await s.versioni())['ok'], isFalse);
    });
  });

  group('gli indirizzi', () {
    test('archivio e somme stanno nella cartella della versione maggiore', () {
      expect(Sorgenti.archivio('6.17.2').toString(),
          'https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.17.2.tar.xz');
      expect(Sorgenti.somme('7.0').toString(),
          'https://cdn.kernel.org/pub/linux/kernel/v7.x/sha256sums.asc');
    });

    test('il commit di master dalla risposta di git, e l\'indirizzo che lo usa',
        () {
      const risposta = '001e# service=git-upload-pack\n0000'
          '0155f75f06e54586f4004199385b4a9a7473955c7810 HEAD\u0000multi_ack\n'
          '003ff75f06e54586f4004199385b4a9a7473955c7810 refs/heads/master\n'
          '003f1111111111111111111111111111111111111111 refs/heads/master-old\n0000';
      expect(Sorgenti.commitDaRefs(risposta),
          'f75f06e54586f4004199385b4a9a7473955c7810');
      expect(Sorgenti.commitDaRefs('niente'), isNull);
      expect(Sorgenti.boreCachyos('7.2', 'abc').path,
          '/CachyOS/kernel-patches/abc/7.2/sched/0001-bore-cachy.patch');
    });

    test('le patch di CachyOS: la serie base e BORE', () {
      expect(Sorgenti.baseCachyos('6.17').path,
          endsWith('/6.17/all/0001-cachyos-base-all.patch'));
      expect(Sorgenti.boreCachyos('7.2').path,
          endsWith('/7.2/sched/0001-bore-cachy.patch'));
    });
  });

  group('la firma dello sviluppatore', () {
    test('i firmatari sono i quattro di kernel.org, per impronta intera', () {
      expect(Sorgenti.firmatari.keys, hasLength(4));
      for (final f in Sorgenti.firmatari.keys) {
        expect(f, matches(RegExp(r'^[0-9A-F]{40}$')), reason: f);
      }
      expect(Sorgenti.firmatari['647F28654894E3BD457199BE38DBBDC86092693E'],
          'Greg Kroah-Hartman');
    });

    test('la chiave si chiede per gli ultimi sedici caratteri', () {
      expect(Sorgenti.chiave('647F28654894E3BD457199BE38DBBDC86092693E').path,
          endsWith('/keys/38DBBDC86092693E.asc'));
    });

    test('la firma è sul .tar, accanto all\'archivio', () {
      expect(Sorgenti.firma('7.2.8').toString(),
          'https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.8.tar.sign');
    });

    test('da gpg conta l\'impronta PRIMARIA, l\'ultima di VALIDSIG', () {
      // L'uscita vera di gpg sul 7.2.8, il 30 settembre 2026.
      const buona = '''
[GNUPG:] NEWSIG
[GNUPG:] GOODSIG 38DBBDC86092693E Greg Kroah-Hartman <greg@kroah.com>
[GNUPG:] VALIDSIG 647F28654894E3BD457199BE38DBBDC86092693E 2026-09-25 1790347225 0 4 0 1 10 00 647F28654894E3BD457199BE38DBBDC86092693E
''';
      expect(Sorgenti.firmataDa(buona),
          '647F28654894E3BD457199BE38DBBDC86092693E');
    });

    test('una firma cattiva, o senza chiave, non è di nessuno', () {
      expect(Sorgenti.firmataDa('[GNUPG:] BADSIG 38DBBDC86092693E Greg\n'), isNull);
      expect(Sorgenti.firmataDa('[GNUPG:] ERRSIG 38DBBDC86092693E 1 10 00 1 9 X\n'
          '[GNUPG:] NO_PUBKEY 38DBBDC86092693E\n'), isNull);
      expect(Sorgenti.firmataDa(''), isNull);
      // Una VALIDSIG accanto a una BADSIG non salva niente.
      expect(Sorgenti.firmataDa('[GNUPG:] BADSIG A b\n[GNUPG:] VALIDSIG X 1 2 3 Y\n'),
          isNull);
    });
  });

  group('la somma di controllo', () {
    const somme = '''
-----BEGIN PGP SIGNED MESSAGE-----
Hash: SHA256

1111111111111111111111111111111111111111111111111111111111111111  linux-6.17.2.tar.gz
2222222222222222222222222222222222222222222222222222222222222222  linux-6.17.2.tar.xz
3333333333333333333333333333333333333333333333333333333333333333  linux-6.17.20.tar.xz
4444444444444444444444444444444444444444444444444444444444444444  patch-6.17.2.xz
-----BEGIN PGP SIGNATURE-----
iQIzBAEBCAAdFiEE
-----END PGP SIGNATURE-----
''';

    test('prende la riga del file giusto, e solo quella', () {
      expect(Sorgenti.sommaDi(somme, 'linux-6.17.2.tar.xz'), '2' * 64);
      expect(Sorgenti.sommaDi(somme, 'linux-6.17.20.tar.xz'), '3' * 64);
    });

    test('un nome che è l\'inizio di un altro non combacia', () {
      expect(Sorgenti.sommaDi(somme, 'linux-6.17.tar.xz'), isNull);
    });

    test('il punto del nome è un punto, non «qualunque carattere»', () {
      expect(Sorgenti.sommaDi('${'5' * 64}  linux-6X17X2.tar.xz\n',
          'linux-6.17.2.tar.xz'), isNull);
    });
  });
}

