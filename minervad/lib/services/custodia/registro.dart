import 'dart:convert';
import 'dart:io';
import '../../core/minerva_paths.dart';

/// Registro — quali cartelle la Custodia tiene d'occhio.
///
/// ── Perché un registro, e non «apri una cartella» ──────────────────────────
///
/// Perché Giacomo ha **quattordici** cartelle in `~/Documenti/Progetti`, e di
/// quelle tre sole sono in git. Un programma che si apre su un progetto per
/// volta gli farebbe fare quattordici volte la stessa fatica, e soprattutto non
/// gli direbbe mai la cosa che vuole sapere davvero: *quali dei miei progetti
/// non sono al sicuro adesso.*
///
/// Quindi la Custodia si apre su una griglia, e questo file è l'elenco che ci
/// sta sotto.
///
/// ── Il file si scrive per intero o non si scrive ───────────────────────────
///
/// Si scrive accanto e si rinomina. Non è pignoleria: in questo progetto è già
/// successo che un file di stato si svuotasse a ogni scrittura e che il difetto
/// restasse appiccicato finché non si ricaricava tutto (vedi il cartello della
/// luce notturna). Un registro mezzo scritto qui vorrebbe dire un progetto che
/// sparisce dalla griglia, e con lui la sua storia.
class Registro {
  Registro({String? percorso}) : percorso = percorso ?? _predefinito();

  final String percorso;
  final List<Progetto> progetti = [];

  static String _predefinito() {
    return '${MinervaPaths.config()}/custodia/progetti.json';
  }

  // ── Leggere e scrivere ─────────────────────────────────────────────────

  Future<void> carica() async {
    progetti.clear();
    final f = File(percorso);
    if (!await f.exists()) return;
    try {
      final d = jsonDecode(await f.readAsString());
      if (d is! Map || d['progetti'] is! List) return;
      for (final v in (d['progetti'] as List)) {
        if (v is Map<String, dynamic>) {
          final p = Progetto.daJson(v);
          if (p != null) progetti.add(p);
        }
      }
    } catch (_) {
      // Un registro illeggibile non è un motivo per non partire: si riparte da
      // vuoto, e il file resta lì da guardare. Cancellarlo sarebbe buttare via
      // l'unica copia di quello che l'utente aveva scelto.
      progetti.clear();
    }
  }

  Future<void> salva() async {
    final f = File(percorso);
    await f.parent.create(recursive: true);
    final testo = const JsonEncoder.withIndent('  ').convert({
      'versione': 1,
      'progetti': [for (final p in progetti) p.toJson()],
    });
    final tmp = File('$percorso.nuovo');
    await tmp.writeAsString('$testo\n', flush: true);
    await tmp.rename(percorso);
  }

  // ── Aggiungere ─────────────────────────────────────────────────────────

  /// Le cartelle che non si registrano mai, per quanto uno insista.
  ///
  /// Non è una lista di posti «di sistema»: è la lista dei posti in cui
  /// **tornare indietro sarebbe una catastrofe**. Registrare `~` vorrebbe dire
  /// che un giorno qualcuno preme «torna a ieri» e si riprende indietro la
  /// posta, la cronologia del browser e le chiavi. Il punto di ritorno
  /// funzionerebbe benissimo: è proprio questo il problema.
  static bool vietata(String percorso) {
    // Vuoto e non un percorso finto: un percorso finto è un percorso scritto
    // a mano, e la guardia di `minerva_paths_test` lo trova — giustamente,
    // perché un giorno qualcuno lo confronterebbe con qualcosa.
    final casa = Platform.environment['HOME'] ?? '';
    const sistema = {
      '/', '/etc', '/usr', '/var', '/boot', '/opt', '/srv',
      '/home', '/root', '/tmp', '/proc', '/sys', '/dev', '/run',
    };
    final p = percorso.endsWith('/') && percorso.length > 1
        ? percorso.substring(0, percorso.length - 1)
        : percorso;
    if (sistema.contains(p)) return true;
    if (casa.isNotEmpty && p == casa) return true;
    // Le cartelle standard della home: Documenti intera sono 310 GB, e
    // «torna a ieri» su Immagini è una richiesta che nessuno voleva fare.
    if (casa.isEmpty) return false;
    for (final n in const [
      'Documenti', 'Documents', 'Immagini', 'Pictures', 'Video', 'Videos',
      'Musica', 'Music', 'Scaricati', 'Downloads', 'Scrivania', 'Desktop',
      '.config', '.local', '.cache', '.ssh', '.gnupg',
    ]) {
      if (p == '$casa/$n') return true;
    }
    return false;
  }

  /// Aggiunge una cartella al registro.
  ///
  /// I rifiuti contano più delle riuscite, e quello che conta di più è
  /// l'**annidamento**: due progetti uno dentro l'altro vorrebbero dire che un
  /// punto di ritorno del padre contiene il figlio, e che tornare indietro sul
  /// padre riporta indietro anche il figlio — di nascosto, senza che nessuno
  /// l'abbia chiesto.
  EsitoRegistro aggiungi(
    String cartella, {
    String? nome,
    String? motore,
  }) {
    if (!cartella.startsWith('/')) {
      return EsitoRegistro.no('Serve il percorso completo della cartella.');
    }
    final p = _normalizza(cartella);
    if (vietata(p)) {
      return EsitoRegistro.no(
        'Questa cartella è troppo grande e troppo importante per essere un '
        'progetto: «torna indietro» qui riporterebbe indietro tutto. Scegli '
        'una cartella dentro, non questa.',
      );
    }
    final d = Directory(p);
    if (!d.existsSync()) {
      return EsitoRegistro.no('La cartella «$p» non esiste.');
    }
    if (FileSystemEntity.isFileSync(p)) {
      return EsitoRegistro.no('«$p» è un file, non una cartella.');
    }
    for (final g in progetti) {
      if (g.percorso == p) {
        return EsitoRegistro.no('«${g.nome}» è già nell\'elenco.');
      }
      if (p.startsWith('${g.percorso}/')) {
        return EsitoRegistro.no(
          'Questa cartella sta dentro «${g.nome}», che è già un progetto. '
          'Tornare indietro su uno dei due si porterebbe dietro l\'altro '
          'senza dirlo.',
        );
      }
      if (g.percorso.startsWith('$p/')) {
        return EsitoRegistro.no(
          '«${g.nome}» sta dentro questa cartella, ed è già un progetto. '
          'Tornare indietro su uno dei due si porterebbe dietro l\'altro '
          'senza dirlo.',
        );
      }
    }

    final pr = Progetto(
      nome: (nome != null && nome.trim().isNotEmpty)
          ? nome.trim()
          : p.split('/').last,
      percorso: p,
      motore: motore ?? suggerisciMotore(p),
    );
    progetti.add(pr);
    return EsitoRegistro.si(pr);
  }

  EsitoRegistro togli(String percorso) {
    final p = _normalizza(percorso);
    final i = progetti.indexWhere((g) => g.percorso == p);
    if (i < 0) return EsitoRegistro.no('Quel progetto non è nell\'elenco.');
    final via = progetti.removeAt(i);
    // Togliere dall'elenco NON tocca i punti di ritorno: chi toglie un progetto
    // per sbaglio non deve perderne la storia insieme.
    return EsitoRegistro.si(via);
  }

  Progetto? cerca(String percorso) {
    final p = _normalizza(percorso);
    for (final g in progetti) {
      if (g.percorso == p) return g;
    }
    return null;
  }

  static String _normalizza(String p) {
    var s = p.trim();
    while (s.length > 1 && s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  // ── Come tiene la storia, questa cartella? ─────────────────────────────
  //
  // `git` per il codice e i testi: ogni versione per sempre, e vale la pena.
  // `copia` per tutto il resto: una foto ritoccata cinque volte, in git,
  // diventa cinque copie intere che si riscaricano a ogni clone. Non è un
  // limite da aggirare — è lo strumento sbagliato per quel contenuto.
  //
  // È un **suggerimento**, non una sentenza: si mostra all'utente e si può
  // cambiare. Per questo la scansione è a profondità due e si ferma presto:
  // deve rispondere in un istante, non avere ragione sempre. `Ruby` sono
  // 286 GB, e nessuno vuole aspettare che li si conti.

  static const int _grosso = 100 * 1024 * 1024; // il limite di GitHub

  static String suggerisciMotore(String cartella) {
    if (Directory('$cartella/.git').existsSync()) return 'git';
    var pesanti = 0;
    var visti = 0;
    try {
      for (final e in Directory(cartella).listSync(followLinks: false)) {
        if (++visti > 400) break;
        if (e is File) {
          if (_pesante(e)) pesanti++;
        } else if (e is Directory) {
          try {
            for (final f in e.listSync(followLinks: false)) {
              if (++visti > 400) break;
              if (f is File && _pesante(f)) pesanti++;
            }
          } catch (_) {}
        }
        if (pesanti > 0) return 'copia';
      }
    } catch (_) {}
    return 'git';
  }

  static bool _pesante(File f) {
    const estensioni = {
      '.img', '.iso', '.bin', '.raw', '.vdi', '.qcow2', '.dmg',
      '.mp4', '.mkv', '.mov', '.avi', '.zst', '.xz', '.gz', '.tgz', '.7z',
    };
    final n = f.path.toLowerCase();
    for (final e in estensioni) {
      if (n.endsWith(e)) return true;
    }
    try {
      return f.lengthSync() > _grosso;
    } catch (_) {
      return false;
    }
  }

  // ── Trovare i progetti già presenti ────────────────────────────────────
  //
  // Alla prima apertura la Custodia **propone**, non fa. Guarda dentro le
  // cartelle dove di solito la gente tiene i progetti e mostra cosa ha trovato,
  // col motore suggerito accanto a ognuno. Adottarli è un clic; ignorarli è
  // non fare niente.

  static List<Progetto> scopri(String padre) {
    final fuori = <Progetto>[];
    final d = Directory(padre);
    if (!d.existsSync()) return fuori;
    try {
      for (final e in d.listSync(followLinks: false)) {
        if (e is! Directory) continue;
        final nome = e.path.split('/').last;
        if (nome.startsWith('.')) continue;
        if (vietata(e.path)) continue;
        fuori.add(Progetto(
          nome: nome,
          percorso: e.path,
          motore: suggerisciMotore(e.path),
        ));
      }
    } catch (_) {}
    fuori.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
    return fuori;
  }
}

/// Un progetto: una cartella di cui la Custodia tiene la storia.
class Progetto {
  Progetto({
    required this.nome,
    required this.percorso,
    String? chiave,
    this.motore = 'git',
    List<Destinazione>? destinazioni,
    List<String>? escludi,
    this.ultimoPunto,
    this.ultimoInvio,
  })  : chiave = chiave ?? chiaveDa(percorso),
        destinazioni = destinazioni ?? [],
        escludi = escludi ?? [];

  static String chiaveDa(String percorso) {
    // FNV-1a: sei caratteri bastano a tenere distinti due progetti che si
    // chiamano uguale, ed è tutto quello che serve. Non è una firma e non
    // protegge da niente — usare `crypto` per questo vorrebbe dire una
    // dipendenza in più per un uso che non è crittografico.
    var h = 0x811c9dc5;
    for (final b in utf8.encode(percorso)) {
      h = ((h ^ b) * 0x01000193) & 0xffffffff;
    }
    final impronta = h.toRadixString(16).padLeft(8, '0').substring(0, 6);
    final nome =
        percorso.split('/').where((s) => s.isNotEmpty).lastOrNull ?? 'progetto';
    final pulito = nome.replaceAll(RegExp(r'[^a-zA-Z0-9àèéìòùÀÈÉÌÒÙ._-]'), '-');
    return '$pulito-$impronta';
  }

  String nome;
  final String percorso;

  /// Sotto quale nome stanno i punti di ritorno di questo progetto.
  ///
  /// ── Perché non basta il nome, e nemmeno il percorso ──────────────────
  ///
  /// Il **nome** è un'etichetta che l'utente cambia quando vuole: usarlo come
  /// chiave vorrebbe dire che rinominare un progetto ne perde tutta la storia,
  /// che è la cosa che questo programma esiste per non fare. Il **percorso**
  /// cambia se si sposta la cartella, e per giunta è pieno di barre.
  ///
  /// Quindi: il nome della cartella per leggibilità — così `punti/` si guarda
  /// anche da terminale — più sei caratteri di impronta del percorso, che
  /// tengono distinti due progetti che si chiamano uguale.
  ///
  /// Nasce una volta e si scrive nel registro. Da lì in poi non cambia più,
  /// nemmeno se cambia il percorso: è una chiave, non una descrizione.
  final String chiave;

  /// `git` (ogni versione per sempre) oppure `copia` (l'ultima versione, e i
  /// punti di ritorno per le precedenti).
  String motore;

  /// Dove va al sicuro. Plurale, e scelto al momento dell'invio: sono parole
  /// di Giacomo — «vorrei poter scegliere in fase di caricamento quale opzione
  /// voglio».
  final List<Destinazione> destinazioni;

  final List<String> escludi;
  DateTime? ultimoPunto;
  DateTime? ultimoInvio;

  bool get esiste => Directory(percorso).existsSync();

  static Progetto? daJson(Map<String, dynamic> j) {
    final p = j['percorso'];
    if (p is! String || !p.startsWith('/')) return null;
    return Progetto(
      nome: j['nome'] is String && (j['nome'] as String).isNotEmpty
          ? j['nome'] as String
          : p.split('/').last,
      percorso: p,
      chiave: j['chiave'] is String && (j['chiave'] as String).isNotEmpty
          ? j['chiave'] as String
          : null,
      motore: j['motore'] == 'copia' ? 'copia' : 'git',
      destinazioni: [
        for (final d in (j['destinazioni'] as List? ?? const []))
          if (d is Map<String, dynamic>) Destinazione.daJson(d),
      ],
      escludi: [
        for (final e in (j['escludi'] as List? ?? const []))
          if (e is String) e,
      ],
      ultimoPunto: DateTime.tryParse('${j['ultimoPunto']}'),
      ultimoInvio: DateTime.tryParse('${j['ultimoInvio']}'),
    );
  }

  Map<String, dynamic> toJson() => {
        'nome': nome,
        'percorso': percorso,
        'chiave': chiave,
        'motore': motore,
        'destinazioni': [for (final d in destinazioni) d.toJson()],
        'escludi': escludi,
        if (ultimoPunto != null) 'ultimoPunto': ultimoPunto!.toIso8601String(),
        if (ultimoInvio != null) 'ultimoInvio': ultimoInvio!.toIso8601String(),
      };
}

/// Un posto dove un progetto va al sicuro.
///
/// Non c'è nessuna parola d'ordine e nessun gettone qui dentro, e non è una
/// dimenticanza: questo file finisce in chiaro in `~/.config`. Il gettone di
/// GitHub sta nel portachiavi, e qui c'è solo il nome con cui chiederglielo.
class Destinazione {
  Destinazione({
    required this.tipo,
    required this.nome,
    required this.dove,
    this.privato = true,
  });

  /// `github` | `cartella` | `rete`
  final String tipo;
  final String nome;
  final String dove;
  final bool privato;

  static Destinazione daJson(Map<String, dynamic> j) => Destinazione(
        tipo: '${j['tipo']}',
        nome: '${j['nome']}',
        dove: '${j['dove']}',
        privato: j['privato'] != false,
      );

  Map<String, dynamic> toJson() => {
        'tipo': tipo,
        'nome': nome,
        'dove': dove,
        'privato': privato,
      };
}

class EsitoRegistro {
  const EsitoRegistro.si(this.progetto)
      : riuscito = true,
        errore = null;
  const EsitoRegistro.no(this.errore)
      : riuscito = false,
        progetto = null;

  final bool riuscito;
  final String? errore;
  final Progetto? progetto;

  Map<String, dynamic> toJson() => {
        'ok': riuscito,
        if (errore != null) 'errore': errore,
        if (progetto != null) 'progetto': progetto!.toJson(),
      };
}
