// blocchi_test.dart — Dai marcatori ai blocchi, e il dizionario che spiega.
import 'package:minervad/terminale/blocchi.dart';
import 'package:minervad/terminale/dizionario.dart';
import 'package:test/test.dart';

void main() {
  String nessunTesto(int a, int b) => '';

  group('i blocchi', () {
    test('A B C D: un blocco con comando, esito e durata', () {
      final b = Blocchi();
      expect(b.marcatore('A', 10, -1, '', '/casa', 1000, nessunTesto).map((x) => x.stato), ['prompt']);
      b.marcatore('B', 10, -1, '', '/casa', 1000, nessunTesto);
      expect(b.alPrompt, isTrue);
      b.rigaMandata('ls -la');
      final c = b.marcatore('C', 11, -1, '', '/casa', 1000, nessunTesto);
      expect(c.single.stato, 'corsa');
      expect(c.single.comando, 'ls -la');
      expect(c.single.nostro, isTrue);
      expect(b.inCorsa, isTrue);
      final d = b.marcatore('D', 15, 0, '', '/casa', 1250, nessunTesto);
      expect(d.single.stato, 'finito');
      expect(d.single.codice, 0);
      expect(d.single.durata, 250);
      expect(d.single.rigaA, 10);
      expect(d.single.rigaC, 11);
      expect(d.single.rigaD, 15);
      expect(b.inCorsa, isFalse);
    });

    test('senza la riga nostra, il comando si legge dall\'eco e si pulisce', () {
      final b = Blocchi();
      b.marcatore('A', 0, -1, '', '/casa', 0, nessunTesto);
      b.marcatore('B', 0, -1, '', '/casa', 0, nessunTesto);
      final c = b.marcatore('C', 1, -1, '', '/casa', 0, (da, a) => '❯ git status                    at 05:42:33');
      expect(c.single.comando, 'git status');
      expect(c.single.nostro, isFalse);
    });

    test('un Invio a vuoto (A B A) non lascia un blocco', () {
      final b = Blocchi();
      b.marcatore('A', 0, -1, '', '/casa', 0, nessunTesto);
      b.marcatore('B', 0, -1, '', '/casa', 0, nessunTesto);
      b.marcatore('A', 1, -1, '', '/casa', 0, nessunTesto);
      expect(b.tutti.length, 1);
      expect(b.tutti.single.rigaA, 1);
    });

    test('D senza C (fish su un Invio vuoto) non è un comando', () {
      final b = Blocchi();
      b.marcatore('A', 0, -1, '', '/casa', 0, nessunTesto);
      b.marcatore('D', 1, 0, '', '/casa', 0, nessunTesto);
      expect(b.tutti, isEmpty);
    });

    test('una C senza D seguita da A si chiude com\'è', () {
      final b = Blocchi();
      b.marcatore('A', 0, -1, '', '/casa', 0, nessunTesto);
      b.rigaMandata('zsh');
      b.marcatore('C', 1, -1, '', '/casa', 0, nessunTesto);
      final a = b.marcatore('A', 5, -1, '', '/casa', 0, nessunTesto);
      expect(a.first.stato, 'finito');
      expect(a.first.codice, -1);
      expect(a.last.stato, 'prompt');
    });

    test('a(riga) trova il blocco giusto', () {
      final b = Blocchi();
      b.marcatore('A', 0, -1, '', '/casa', 0, nessunTesto);
      b.rigaMandata('uno');
      b.marcatore('C', 1, -1, '', '/casa', 0, nessunTesto);
      b.marcatore('D', 4, 0, '', '/casa', 0, nessunTesto);
      b.marcatore('A', 4, -1, '', '/casa', 0, nessunTesto);
      b.rigaMandata('due');
      b.marcatore('C', 5, -1, '', '/casa', 0, nessunTesto);
      expect(b.a(2)!.comando, 'uno');
      expect(b.a(4)!.comando, 'due');
      expect(b.a(100)!.comando, 'due', reason: 'il blocco aperto contiene tutto quello che segue');
    });

    test('un marcatore falso dentro l\'uscita non chiude il blocco di qualcun altro', () {
      // `cat` di un file con dentro `\e]133;D;0\a`: il motore vede D. Non è
      // il D della shell, ma il registro non lo può sapere: quello che deve
      // garantire è che il PROSSIMO A/C ricostruisca lo stato giusto e che
      // il comando resti quello mandato.
      final b = Blocchi();
      b.marcatore('A', 0, -1, '', '/casa', 0, nessunTesto);
      b.rigaMandata('cat trappola.txt');
      b.marcatore('C', 1, -1, '', '/casa', 0, nessunTesto);
      b.marcatore('D', 2, 0, '', '/casa', 0, nessunTesto); // falso
      b.marcatore('D', 3, 0, '', '/casa', 0, nessunTesto); // vero: ignorato, nessun blocco aperto
      expect(b.tutti.length, 1);
      expect(b.tutti.single.comando, 'cat trappola.txt');
      final a = b.marcatore('A', 3, -1, '', '/casa', 0, nessunTesto);
      expect(a.single.stato, 'prompt');
      expect(b.alPrompt, isTrue);
    });

    test('il registro non cresce oltre il massimo', () {
      final b = Blocchi(massimo: 3);
      for (var i = 0; i < 10; i++) {
        b.marcatore('A', i * 2, -1, '', '/casa', 0, nessunTesto);
        b.rigaMandata('c$i');
        b.marcatore('C', i * 2, -1, '', '/casa', 0, nessunTesto);
        b.marcatore('D', i * 2 + 1, 0, '', '/casa', 0, nessunTesto);
      }
      expect(b.tutti.length, 3);
      expect(b.tutti.last.comando, 'c9');
    });
  });

  group('il dizionario spiega', () {
    late Dizionario d;
    setUpAll(() {
      d = Dizionario.daFile('${_radice()}/config/dizionario-comandi.json');
    });

    test('il dizionario vero si carica, ed è grande', () {
      expect(d.voci.length, greaterThan(150));
      expect(d.trova('ls')!.descrizione, isNotEmpty);
    });

    test('ogni voce è descritta e gli esempi riguardano il suo argomento', () {
      // Alcune voci insegnano una famiglia o una sintassi, non un eseguibile.
      const correlati = {
        '&&': ["ping -c1 8.8.8.8 || echo 'niente rete'"],
        'jobs': ['fg %1', 'bg %1'],
        'crontab': ['0 3 * * * /home/giacomo/backup.sh'],
        'function': ['saluta() { echo "ciao \$1"; }', 'saluta Giacomo'],
        'test': ["[ \$# -eq 0 ] && echo 'manca un argomento'"],
        'source': ['. venv/bin/activate'],
        'pushd': ['popd', 'dirs'],
      };
      final colpe = <String>[];
      for (final v in d.voci) {
        if (v.descrizione.trim().isEmpty) colpe.add('${v.comando}: senza descrizione');
        if (v.livello < 1 || v.livello > 5) colpe.add('${v.comando}: livello ${v.livello}');
        if (v.pericolo < 0 || v.pericolo > 3) colpe.add('${v.comando}: pericolo ${v.pericolo}');
        for (final o in v.opzioni) {
          if (o.spiegazione.trim().isEmpty) colpe.add('${v.comando} ${o.flag}: senza spiegazione');
        }
        for (final e in v.esempi) {
          if (e.spiegazione.trim().isEmpty) colpe.add('${v.comando} «${e.comando}»: senza spiegazione');
          final parole = spezzaParole(e.comando);
          final prima = parole.isEmpty ? '' : parole.first;
          final ok = e.comando.contains(v.comando) || prima == 'sudo' ||
              v.comando.startsWith('-') ||
              (correlati[v.comando]?.contains(e.comando) ?? false);
          if (!ok) colpe.add('${v.comando} «${e.comando}»: non usa il comando');
        }
        for (final s in v.vedi) {
          if (s.trim().isEmpty) colpe.add('${v.comando}: un «vedi» vuoto');
        }
      }
      expect(colpe, isEmpty, reason: colpe.join('\n'));
    });

    test('«ls -la» si spiega opzione per opzione', () {
      final s = d.spiega('ls -la').single;
      expect(s.comando, 'ls');
      expect(s.conosciuto, isTrue);
      expect(s.opzioni.map((o) => o[0]).toList(), ['-l', '-a']);
      expect(s.sconosciute, isEmpty);
    });

    test('una pipeline si spiega pezzo per pezzo, sudo e assegnazioni scavalcati', () {
      final parti = d.spiega("LANG=C sudo grep -rn 'x' src/ | sort -u | head -n 5");
      expect(parti.map((p) => p.comando).toList(), ['grep', 'sort', 'head']);
      expect(parti[0].opzioni.map((o) => o[0]).toList(), ['-r', '-n']);
      expect(parti[0].argomenti, ['x', 'src/']);
      expect(parti[2].opzioni.first[0], '-n');
    });

    test('un comando sconosciuto lo dice, un\'opzione sconosciuta pure', () {
      final s = d.spiega('pippo -q --zzz').single;
      expect(s.conosciuto, isFalse);
      expect(s.sconosciute, ['-q', '--zzz']);
      final g = d.spiega('git status --porcelain').single;
      expect(g.opzioni.first[0], 'status');
      expect(g.sconosciute, ['--porcelain']);
    });

    test('le opzioni con l\'uguale e le sottoparole', () {
      final g = d.spiega("grep --include='*.py' -i x").single;
      // La shell rimuove le virgolette: il valore dell'argomento è *.py.
      expect(g.opzioni.map((o) => o[0]).toList(), ['--include=*.py', '-i']);
      final s = d.spiega('systemctl restart nginx').single;
      expect(s.opzioni.first[1], contains('riavvia'));
      expect(s.argomenti, ['nginx']);
    });

    test('-- termina le opzioni anche davanti a nomi che sembrano comandi', () {
      final s = d.spiega('git -- status --help -rf').single;
      expect(s.opzioni, isEmpty);
      expect(s.sconosciute, isEmpty);
      expect(s.argomenti, ['status', '--help', '-rf']);
    });
  });

  group('spezzare', () {
    test('la pipeline rispetta le virgolette e i reindirizzamenti', () {
      expect(spezzaPipeline("echo 'a | b' | grep x && ls; false || true"),
          ["echo 'a | b'", 'grep x', 'ls', 'false', 'true']);
      expect(spezzaPipeline('cmd 2>&1 | less'), ['cmd 2>&1', 'less']);
      expect(spezzaPipeline('sleep 5 &'), ['sleep 5']);
      expect(spezzaPipeline('sleep 5 & echo fine'), ['sleep 5', 'echo fine']);
    });
    test('le parole rispettano virgolette e barre', () {
      expect(spezzaParole(r'cp "un file.txt" altro\ file.txt'), ['cp', 'un file.txt', 'altro file.txt']);
      expect(spezzaParole("echo ''"), ['echo', '']);
    });
  });
}

String _radice() {
  var d = Uri.base.toFilePath();
  while (!d.endsWith('/minervad') && !d.endsWith('/minervad/')) {
    final i = d.lastIndexOf('/', d.length - 2);
    if (i <= 0) break;
    d = d.substring(0, i + 1);
  }
  return d.replaceAll(RegExp(r'/minervad/?$'), '');
}
