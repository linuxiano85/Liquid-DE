import 'dart:io';

/// L'albero dei sorgenti letto per una domanda sola: **quale simbolo di
/// Kconfig accende un modulo**.
///
/// ── Perché serve ────────────────────────────────────────────────────────
///
/// `localmodconfig` toglie e non aggiunge: un modulo che la configurazione di
/// partenza non accende non c'è, anche se è nell'elenco. Fino al 30 settembre
/// era scritto negli avvisi e basta, e voleva dire che le scorte — «tutti i
/// filesystem, anche se oggi non c'è niente che li usi» — partendo da
/// defconfig erano una promessa vuota. Sulla macchina virtuale di prova (un
/// kernel tutto dentro, senza moduli) era peggio: il rilievo vedeva otto
/// nomi, e le scorte non diventavano niente. Trovato il 1° ottobre 2026.
///
/// Il modo di saperlo è lo stesso di `scripts/kconfig/streamline_config.pl`:
/// nei Makefile un modulo nasce da una riga `obj-$(CONFIG_X) += nome.o`. Si
/// legge quella, e si tiene il simbolo solo se è `tristate`: un modulo può
/// venire SOLO da un tristate, e senza questo filtro `kvm` risulterebbe
/// acceso da `KVM_GUEST` (un `kvm.o` dentro il kernel, che col modulo `kvm`
/// non c'entra) e `overlay` da `OF_OVERLAY`.
class MappaModuli {
  /// Nome del modulo (coi trattini già diventati `_`) → simboli tristate.
  final Map<String, Set<String>> simboli;
  const MappaModuli(this.simboli);

  /// La mappa di un albero vero. Un paio di secondi su un 7.x: si fa una
  /// volta per compilazione, nel passo che la usa.
  static Future<MappaModuli> leggi(String albero) async {
    final makefile = <String>[];
    final kconfig = <String>[];
    final radice = Directory(albero);
    await for (final e in radice
        .list(recursive: true, followLinks: false)
        .handleError((_) {})) {
      if (e is! File) continue;
      final rel = e.path.substring(albero.length + 1);
      if (_fuori(rel)) continue;
      final nome = rel.split('/').last;
      if (nome == 'Makefile' || nome == 'Kbuild') {
        makefile.add(e.path);
      } else if (nome.startsWith('Kconfig')) {
        kconfig.add(e.path);
      }
    }
    final tristate = <String>{};
    for (final k in kconfig) {
      tristate.addAll(simboliTristate(await _testo(k)));
    }
    final grezza = <String, Set<String>>{};
    for (final m in makefile) {
      simboliDaMakefile(await _testo(m)).forEach((mod, s) {
        grezza.putIfAbsent(mod, () => {}).addAll(s);
      });
    }
    return MappaModuli(filtra(grezza, tristate));
  }

  /// Le cartelle che non fanno parte del kernel che si compila: gli
  /// strumenti, la documentazione, gli esempi, e le altre architetture (che
  /// hanno i loro `kvm.o` e i loro driver col nome uguale ai nostri).
  static bool _fuori(String rel) {
    for (final c in const ['tools/', 'Documentation/', 'samples/', 'scripts/',
                           'usr/', '.git/']) {
      if (rel.startsWith(c)) return true;
    }
    if (rel.startsWith('arch/')) {
      final pezzi = rel.split('/');
      return pezzi.length > 2 && pezzi[1] != 'x86';
    }
    return false;
  }

  static Future<String> _testo(String f) async {
    try {
      return await File(f).readAsString();
    } catch (_) {
      return '';
    }
  }

  Map<String, dynamic> toJson() => {
        for (final e in simboli.entries) e.key: e.value.toList()..sort(),
      };
}

/// Da un Makefile: `obj-$(CONFIG_X) += a.o b/ c.o` → `a` e `c` accesi da `X`.
/// Le righe spezzate con `\` si uniscono prima, i commenti si tolgono, e una
/// parola che non finisce in `.o` (una cartella, una variabile) non è un
/// modulo.
Map<String, Set<String>> simboliDaMakefile(String testo) {
  final unito = testo.replaceAll(RegExp(r'\\\r?\n'), ' ');
  final fuori = <String, Set<String>>{};
  final riga = RegExp(r'^[ \t]*obj-\$\(CONFIG_([A-Za-z0-9_]+)\)[ \t]*[+:]?=(.*)$',
      multiLine: true);
  for (final m in riga.allMatches(unito)) {
    var resto = m.group(2)!;
    final commento = resto.indexOf('#');
    if (commento >= 0) resto = resto.substring(0, commento);
    for (final parola in resto.split(RegExp(r'\s+'))) {
      if (!parola.endsWith('.o') || parola.contains(r'$')) continue;
      final nome = parola
          .substring(0, parola.length - 2)
          .split('/')
          .last
          .replaceAll('-', '_');
      if (nome.isEmpty) continue;
      fuori.putIfAbsent(nome, () => {}).add(m.group(1)!);
    }
  }
  return fuori;
}

/// I simboli `tristate` (o `def_tristate`) di un file Kconfig. Il tipo è la
/// prima riga di tipo dopo `config X`: un `bool` o un `int` chiude la voce.
Set<String> simboliTristate(String testo) {
  final fuori = <String>{};
  String? voce;
  final inizio = RegExp(r'^\s*(?:menu)?config\s+([A-Za-z0-9_]+)\s*$');
  final tipo = RegExp(r'^\s*(tristate|def_tristate|bool|def_bool|int|hex|string)\b');
  for (final riga in testo.split('\n')) {
    final i = inizio.firstMatch(riga);
    if (i != null) {
      voce = i.group(1);
      continue;
    }
    if (voce == null) continue;
    final t = tipo.firstMatch(riga);
    if (t == null) continue;
    if (t.group(1)!.endsWith('tristate')) fuori.add(voce);
    voce = null;
  }
  return fuori;
}

/// Tiene, per ogni modulo, solo i simboli tristate; un modulo che resta
/// senza simboli non è un modulo (era un oggetto dentro il kernel).
Map<String, Set<String>> filtra(
    Map<String, Set<String>> grezza, Set<String> tristate) {
  final fuori = <String, Set<String>>{};
  grezza.forEach((mod, s) {
    final buoni = s.where(tristate.contains).toSet();
    if (buoni.isNotEmpty) fuori[mod] = buoni;
  });
  return fuori;
}

/// Quello che manca, fra i moduli voluti, in un `.config` letto con
/// `leggiConfig`.
///
///  · **presenti**: almeno uno dei loro simboli è `y` o `m`;
///  · **daAccendere**: nessuno lo è, e questi sono i simboli da mettere a
///    `m` (tutti: quale dei due serva lo decide Kconfig con le dipendenze);
///  · **sconosciuti**: nessun Makefile di questo albero li costruisce — un
///    nome cambiato fra una versione e l'altra, o un modulo esterno.
({List<String> mancanti, List<String> daAccendere, List<String> sconosciuti})
    confronta(Map<String, String> valori, MappaModuli mappa,
        Iterable<String> voluti) {
  final mancanti = <String>[];
  final simboli = <String>{};
  final sconosciuti = <String>[];
  for (final m in voluti.toSet().toList()..sort()) {
    final s = mappa.simboli[m];
    if (s == null) {
      sconosciuti.add(m);
      continue;
    }
    if (s.any((x) => valori[x] == 'y' || valori[x] == 'm')) continue;
    mancanti.add(m);
    simboli.addAll(s);
  }
  return (
    mancanti: mancanti,
    daAccendere: simboli.toList()..sort(),
    sconosciuti: sconosciuti,
  );
}
