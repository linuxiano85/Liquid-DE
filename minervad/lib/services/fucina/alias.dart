/// L'indice dei moduli di un kernel: chi guida quale dispositivo, dove sta
/// ogni modulo nell'albero, e quali sono già compilati dentro.
///
/// ── Perché lo leggiamo da soli, e non con `modprobe -R` ─────────────────
///
/// `modprobe -R <alias>` risponde alla stessa domanda, un alias alla volta.
/// Su questa macchina i `modalias` in `/sys` sono qualche centinaio: qualche
/// centinaio di processi lanciati uno dopo l'altro, e il demone ha un filo
/// solo. Il file che `modprobe` legge — `modules.alias` — è testo, una riga
/// per regola, e leggerlo una volta costa meno di dieci processi.
///
/// C'è anche una ragione di prova: un indice che si costruisce da tre
/// stringhe si prova con tre stringhe, senza un kernel vero sotto.
///
/// ── I nomi, con il trattino basso ───────────────────────────────────────
///
/// Lo stesso modulo si scrive in due modi: `snd-hda-intel` nel nome del file
/// (`modules.dep`), `snd_hda_intel` in `/proc/modules`, in `modules.alias` e
/// in `modprobed.db`. Il kernel li considera uguali. Qui dentro si usa sempre
/// la forma col trattino basso ([normalizza]): due forme dello stesso nome
/// sono due voci diverse in un insieme, e un modulo tenuto «due volte» è un
/// modulo che scompare quando se ne toglie una.
library;

/// La forma unica del nome di un modulo.
String normalizza(String nome) => nome.trim().replaceAll('-', '_');

/// Il nome di un modulo a partire dal suo percorso in `modules.dep`:
/// `kernel/sound/pci/hda/snd-hda-intel.ko.zst` → `snd_hda_intel`.
String nomeDaPercorso(String percorso) {
  var base = percorso.split('/').last;
  final ko = base.indexOf('.ko');
  if (ko > 0) base = base.substring(0, ko);
  return normalizza(base);
}

class IndiceAlias {
  /// Le regole divise per il pezzo che precede i due punti (`pci`, `usb`,
  /// `acpi`, …). Senza questa divisione ogni `modalias` si confronterebbe
  /// con tutte le trentamila regole: così solo con quelle del suo bus.
  final Map<String, List<_Regola>> _perBus = {};

  /// Le regole il cui bus è esso stesso un modello (`acpi*:PNP0C0A:*`):
  /// sono poche, e si provano sempre.
  final List<_Regola> _jolly = [];

  /// Dove sta ogni modulo, dal `modules.dep`. Serve a dargli una famiglia.
  final Map<String, String> percorsi = {};

  /// I moduli compilati dentro il kernel che ha scritto questi file.
  final Set<String> incorporati = {};

  int get regole =>
      _jolly.length + _perBus.values.fold(0, (s, l) => s + l.length);

  IndiceAlias();

  /// Costruito dai tre file di `/usr/lib/modules/<rilascio>/`. Uno che manca
  /// è una stringa vuota, non un errore: un kernel senza moduli caricabili
  /// (`CONFIG_MODULES=n`) non li ha, e non è un kernel rotto.
  ///
  /// `soloBus`: se c'è, si tengono solo le regole di quei bus (e i jolly).
  /// Le regole sono trentasettemila per tutti i dispositivi immaginabili, e
  /// tenerle tutte costava al demone 32 MB per un computer che di bus con un
  /// dispositivo senza driver ne ha due o tre (misurato il 4 ottobre 2026).
  factory IndiceAlias.daTesti({
    String alias = '',
    String dep = '',
    String incorporati = '',
    Set<String>? soloBus,
  }) {
    final i = IndiceAlias();
    // Riga per riga con `indexOf`, senza `split`: un elenco di trentamila
    // stringhe solo per scorrerle era metà del picco.
    var da = 0;
    while (da < alias.length) {
      var a = alias.indexOf('\n', da);
      if (a < 0) a = alias.length;
      i._aggiungiRiga(alias.substring(da, a), soloBus);
      da = a + 1;
    }
    for (final riga in dep.split('\n')) {
      final due = riga.indexOf(':');
      if (due <= 0) continue;
      final p = riga.substring(0, due).trim();
      i.percorsi[nomeDaPercorso(p)] = p;
    }
    for (final riga in incorporati.split('\n')) {
      final p = riga.trim();
      if (p.isEmpty) continue;
      final nome = nomeDaPercorso(p);
      i.incorporati.add(nome);
      i.percorsi.putIfAbsent(nome, () => p);
    }
    return i;
  }

  static final RegExp _spazi = RegExp(r'\s+');

  void _aggiungiRiga(String riga, [Set<String>? soloBus]) {
    // `alias <modello> <modulo>`, separati da spazi. Il modello non contiene
    // spazi: se una riga ne ha più di tre pezzi, non è una riga che capiamo.
    final pezzi = riga.trim().split(_spazi);
    if (pezzi.length != 3 || pezzi[0] != 'alias') return;
    final modello = pezzi[1];
    final bus = _bus(modello);
    if (bus != null && soloBus != null && !soloBus.contains(bus)) return;
    final r = _Regola(modello, normalizza(pezzi[2]));
    if (bus == null) {
      _jolly.add(r);
    } else {
      _perBus.putIfAbsent(bus, () => []).add(r);
    }
  }

  /// Il bus di un `modalias` (`pci:v…` → `pci`), o `null`.
  static String? busDi(String modalias) => _bus(modalias.trim());

  /// Il pezzo prima dei due punti, se è una parola e non un modello.
  /// `null` vuol dire «può valere per più bus»: va fra i jolly.
  static String? _bus(String s) {
    final due = s.indexOf(':');
    if (due <= 0) return null;
    final b = s.substring(0, due);
    if (b.contains('*') || b.contains('?') || b.contains('[')) return null;
    return b;
  }

  /// I moduli che dichiarano di saper guidare un dispositivo con questo
  /// `modalias`. Possono essere più d'uno — un driver specifico e uno
  /// generico — e si restituiscono tutti: scegliere fra loro è il mestiere
  /// del kernel, non il nostro.
  Set<String> moduliPer(String modalias) {
    final m = modalias.trim();
    if (m.isEmpty) return const {};
    final fuori = <String>{};
    final bus = _bus(m);
    final candidati = [
      if (bus != null) ...?_perBus[bus],
      ..._jolly,
    ];
    for (final r in candidati) {
      if (combacia(r.modello, m)) fuori.add(r.modulo);
    }
    return fuori;
  }
}

class _Regola {
  final String modello;
  final String modulo;
  const _Regola(this.modello, this.modulo);
}

/// Il confronto di `fnmatch(3)` senza opzioni, che è quello che usa
/// `modprobe`: `*` qualunque sequenza, `?` un carattere, `[…]` un insieme
/// (con `!` o `^` in testa per negarlo, e `a-z` per un intervallo).
///
/// Scritto a mano perché `RegExp` vorrebbe dire tradurre ogni modello in
/// un'espressione e compilarla — trentamila volte — e perché un modello con
/// dentro un carattere speciale delle espressioni (`.`, `+`, `(`) andrebbe
/// scappato, che è il genere di dettaglio che si sbaglia una volta su mille.
///
/// Il ritorno indietro è quello classico e lineare: ci si ricorda l'ultimo
/// `*` visto e, se più avanti qualcosa non combacia, gli si fa mangiare un
/// carattere in più. Niente ricorsione, quindi nessun modello cattivo può
/// far esplodere il tempo.
bool combacia(String modello, String testo) {
  var p = 0, t = 0;
  var stellaP = -1, stellaT = 0;
  while (t < testo.length) {
    if (p < modello.length) {
      final c = modello[p];
      if (c == '*') {
        stellaP = p++;
        stellaT = t;
        continue;
      }
      if (c == '?') {
        p++;
        t++;
        continue;
      }
      if (c == '[') {
        final fine = _fineInsieme(modello, p);
        if (fine > 0) {
          if (_nellInsieme(modello.substring(p + 1, fine), testo[t])) {
            p = fine + 1;
            t++;
            continue;
          }
        } else if (testo[t] == '[') {
          // Una `[` senza chiusura vale come carattere normale, come in
          // `fnmatch`.
          p++;
          t++;
          continue;
        }
      } else if (c == testo[t]) {
        p++;
        t++;
        continue;
      }
    }
    if (stellaP >= 0) {
      p = stellaP + 1;
      t = ++stellaT;
      continue;
    }
    return false;
  }
  while (p < modello.length && modello[p] == '*') {
    p++;
  }
  return p == modello.length;
}

/// Dove si chiude l'insieme che si apre in `inizio`, o -1 se non si chiude.
/// Una `]` subito dopo l'apertura (o dopo la negazione) fa parte
/// dell'insieme, come in `fnmatch`.
int _fineInsieme(String m, int inizio) {
  var i = inizio + 1;
  if (i < m.length && (m[i] == '!' || m[i] == '^')) i++;
  if (i < m.length && m[i] == ']') i++;
  while (i < m.length) {
    if (m[i] == ']') return i;
    i++;
  }
  return -1;
}

bool _nellInsieme(String dentro, String c) {
  var nega = false;
  var i = 0;
  if (dentro.isNotEmpty && (dentro[0] == '!' || dentro[0] == '^')) {
    nega = true;
    i = 1;
  }
  var trovato = false;
  final u = c.codeUnitAt(0);
  while (i < dentro.length) {
    if (i + 2 < dentro.length && dentro[i + 1] == '-') {
      final a = dentro.codeUnitAt(i), b = dentro.codeUnitAt(i + 2);
      if (u >= a && u <= b) trovato = true;
      i += 3;
    } else {
      if (dentro[i] == c) trovato = true;
      i++;
    }
  }
  return trovato != nega;
}
