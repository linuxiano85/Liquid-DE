import 'dart:io';

import 'inventario.dart';

/// Come è andata per una voce sola.
class Tolta {
  const Tolta(this.id, this.byte, this.ok, [this.perche = '']);

  final String id;

  /// Quanti byte quella voce pesava **prima**. Non è quanto si è liberato:
  /// quello lo dice l'inventario rifatto dopo, ed è la sola misura che non si
  /// possa raccontare male.
  final int byte;

  final bool ok;

  /// Perché non si è potuto, in italiano e già scritto. Vuota quando è andata.
  final String perche;

  Map<String, dynamic> toJson() =>
      {'id': id, 'byte': byte, 'ok': ok, if (perche.isNotEmpty) 'perche': perche};
}

/// Toglie **soltanto** quello che l'inventario ha mostrato.
///
/// ── La regola che tiene in piedi tutto il resto ────────────────────────────
///
/// Chi chiede una pulizia manda degli **identificativi**, mai dei percorsi. I
/// percorsi li ricava questo file rifacendo l'inventario da capo, un istante
/// prima di cancellare.
///
/// Non è pignoleria. Un verbo `pulisci <percorso>` sarebbe la stessa riga di
/// codice con dentro un buco: chiunque parli col demone potrebbe cancellare
/// qualunque cosa passando da noi. È la stessa scelta scritta in cima a
/// `scripts/minerva-radice`, che ha un elenco chiuso di verbi e nessun verbo
/// generico.
///
/// E rifare l'inventario adesso serve anche a una seconda cosa: fra il momento
/// in cui hai guardato l'elenco e il momento in cui premi, possono essere
/// passati minuti. Quello che si cancella è quello che c'è **ora**.
///
/// ── E il secondo cancello, che è di posto e non di nome ────────────────────
///
/// Anche avendo l'identificativo giusto, un percorso viene toccato solo se sta
/// dentro uno dei tre posti qui sotto. Se un giorno l'inventario imparasse a
/// mostrare una cartella nuova, questo file **non** la cancellerebbe finché
/// qualcuno non l'ha scritta qui — e questa è la parte che si vuole
/// scomoda.
class Pulitore {
  Pulitore({
    this.inventario,
    String? casa,
    Future<void> Function(String percorso)? togli,
    Future<DateTime?> Function(String percorso)? quandoToccato,
    Future<List<String>> Function(String percorso)? figliDa,
    this.radice,
    this.racconta,
  })  : _casa = casa ?? (Platform.environment['HOME'] ?? '/root'),
        _togli = togli ?? _togliDavvero,
        _quando = quandoToccato ?? _quandoDavvero,
        _figliDa = figliDa ?? _figliDavvero;

  final String _casa;
  /// Sostituibile per le prove, come `esegui` in `Inventario`: una prova che
  /// misura il disco vero è verde stamattina e rossa stasera.
  final Inventario? inventario;
  final Future<void> Function(String) _togli;
  final Future<DateTime?> Function(String) _quando;

  /// I figli di un contenitore, già scremati. Sostituibile per le prove, come
  /// `togli`: senza, una prova sul cestino dovrebbe creare cartelle vere — e
  /// creandole sotto `/tmp` finirebbe per provare la cosa sbagliata, perché
  /// `/tmp` è già un posto permesso. È successo il 9 settembre 2026.
  final Future<List<String>> Function(String) _figliDa;
  final void Function(String fase, String testo, int fatte, int quante)?
      racconta;

  /// ── Chi sa chiedere la password ──────────────────────────────────────
  ///
  /// Quello che sta fuori dalla tua cartella — la cache dei pacchetti, le
  /// lingue, il registro — non lo tocca questo file: lo chiede all'aiutante
  /// di root, che ha un elenco chiuso di verbi e ricontrolla tutto da capo.
  ///
  /// Qui dentro non si sa nemmeno cosa sia `pkexec`: arriva una funzione, e
  /// nelle prove ne arriva una finta. Un pulitore che sa chiedere la password
  /// è un pulitore che nelle prove non si può far girare.
  ///
  /// Se manca — ed è il caso di tutte le prove che non la passano — le voci
  /// di sistema si rifiutano con la loro ragione scritta, come prima.
  final Future<Map<String, dynamic>> Function(
      String operazione, List<String> argomenti)? radice;

  static Future<void> _togliDavvero(String percorso) async {
    final t = FileSystemEntity.typeSync(percorso, followLinks: false);
    if (t == FileSystemEntityType.directory) {
      await Directory(percorso).delete(recursive: true);
    } else if (t != FileSystemEntityType.notFound) {
      await File(percorso).delete();
    }
  }

  /// I figli di una cartella, senza collegamenti, prese e tubi: quelli non
  /// occupano niente e possono essere il canale con cui due programmi si
  /// parlano adesso.
  static Future<List<String>> _figliDavvero(String percorso) async {
    final fuori = <String>[];
    await for (final v in Directory(percorso).list(followLinks: false)) {
      final tipo = FileSystemEntity.typeSync(v.path, followLinks: false);
      if (tipo == FileSystemEntityType.file ||
          tipo == FileSystemEntityType.directory) {
        fuori.add(v.path);
      }
    }
    return fuori;
  }

  static Future<DateTime?> _quandoDavvero(String percorso) async {
    try {
      return FileStat.statSync(percorso).modified;
    } catch (_) {
      return null;
    }
  }

  /// I tre posti da cui si può togliere senza la password. Fuori di qui non si
  /// tocca niente, nemmeno sbagliando.
  List<String> get _postiPermessi => [
        '$_casa/.cache/',
        '$_casa/.local/share/Trash/',
        '/tmp/',
      ];

  /// ── I due che si SVUOTANO, e quindi valgono anche per intero ─────────
  ///
  /// Il cestino e `/tmp` sono contenitori: quello che si cancella sono i
  /// figli, non la cartella. Per loro il percorso esatto è permesso — e deve
  /// esserlo, perché è esattamente quello che l'inventario mostra.
  ///
  /// Mancavano, e il difetto è passato inosservato per un motivo che vale la
  /// pena scrivere: le prove usavano voci come `/casa/.cache/mozilla`, cioè
  /// sempre roba DENTRO un posto permesso. Nessuna provava a togliere un
  /// contenitore intero, che è invece il caso di due voci su otto.
  ///
  /// Giacomo l'ha trovato usandolo: il cestino restava pieno. Nel registro
  /// c'era scritto perché — «Non è in un posto da cui Minerva tolga
  /// qualcosa» — ma una riga giusta su un rifiuto sbagliato resta un rifiuto
  /// sbagliato.
  List<String> get _contenitori => [
        '$_casa/.local/share/Trash',
        '/tmp',
      ];

  bool _permesso(String percorso) {
    if (percorso.contains('/../') || percorso.endsWith('/..')) return false;
    if (_contenitori.contains(percorso)) return true;
    for (final p in _postiPermessi) {
      // Per tutto il resto il percorso deve stare DENTRO, non essere il posto
      // stesso: `$HOME/.cache` per intero è un'altra cosa da
      // `$HOME/.cache/mozilla`, e cancellarla porterebbe via anche quello che
      // non si è mostrato — le briciole sotto i dieci mega, che nell'elenco
      // non compaiono nemmeno.
      if (percorso.startsWith(p) && percorso.length > p.length) return true;
    }
    return false;
  }

  /// Toglie le voci chieste, e risponde com'è andata **voce per voce**.
  ///
  /// Un «fatto» solo in fondo non basta: se tre cartelle su ventidue non si
  /// sono potute togliere, chi guarda deve poter sapere quali e perché,
  /// altrimenti il numero che resta sullo schermo sembra un errore del conto.
  Future<Map<String, dynamic>> pulisci(List<String> ids) async {
    if (ids.isEmpty) {
      return {'ok': false, 'errore': 'Non hai spuntato niente.'};
    }

    racconta?.call('pulizia', 'Rileggo cosa c\'è, un istante prima di togliere',
        0, ids.length + 1);
    final quali = inventario ?? Inventario(casa: _casa);
    final tutto = await quali.tutto();
    final voci = <String, Map<String, dynamic>>{
      for (final v in (tutto['voci'] as List).cast<Map<String, dynamic>>())
        v['id'] as String: v,
    };

    final fatte = <Tolta>[];
    var i = 0;
    for (final id in ids) {
      i++;
      final v = voci[id];
      if (v == null) {
        // Non c'è più: qualcuno l'ha tolta, o si è svuotata da sola fra il
        // momento in cui hai guardato e adesso. Non è un errore.
        fatte.add(Tolta(id, 0, true, 'Non c\'era più.'));
        racconta?.call('pulizia', '$id: non c\'era più', i, ids.length + 1);
        continue;
      }
      final dove = v['dove'] as String;
      final byte = (v['byte'] as num).toInt();

      if (v['vuoleLaPassword'] == true) {
        final esito = await _perLaRadice(id, v, byte, i, ids.length + 1);
        fatte.add(esito);
        continue;
      }

      // L'età della cartella /tmp non dice se i suoi discendenti siano in
      // uso: una directory vecchia può contenere socket o file appena creati.
      // Lasciare la pulizia globale alla politica di systemd-tmpfiles.
      if (id == 'temporanei') {
        fatte.add(Tolta(id, byte, false,
            'I temporanei di sistema sono gestiti da systemd-tmpfiles; non vengono cancellati dalla pulizia manuale.'));
        continue;
      }

      if (!_permesso(dove)) {
        fatte.add(Tolta(id, byte, false,
            'Non è in un posto da cui Minerva tolga qualcosa.'));
        racconta?.call('pulizia', '$dove: fuori dai posti permessi', i,
            ids.length + 1);
        continue;
      }

      try {
        final quanti = await _svuota(dove, id);
        fatte.add(Tolta(id, byte, true));
        racconta?.call(
            'pulizia',
            'Tolto ${v['nome']} — ${_inParole(byte)}'
                '${quanti > 0 ? ' ($quanti cose)' : ''}',
            i,
            ids.length + 1);
      } catch (e) {
        fatte.add(Tolta(id, byte, false, _perche(e)));
        racconta?.call(
            'pulizia', '${v['nome']}: ${_perche(e)}', i, ids.length + 1);
      }
    }

    final tolte = fatte.where((t) => t.ok).fold<int>(0, (s, t) => s + t.byte);
    racconta?.call('pulizia', 'Tolti ${_inParole(tolte)}. Ricontrollo.',
        ids.length + 1, ids.length + 1);

    return {
      'ok': true,
      'liberati': tolte,
      'fatte': [for (final t in fatte) t.toJson()],
      'quante': fatte.where((t) => t.ok).length,
      'nonRiuscite': fatte.where((t) => !t.ok).length,
    };
  }

  /// ── Quello che sta fuori dalla tua cartella ──────────────────────────────
  ///
  /// Non si tocca da qui: si chiede un VERBO all'aiutante di root, e il verbo
  /// dice cosa fare, non dove. `pulisci-cache-pacchetti` non prende nemmeno
  /// un argomento; `pulisci-lingue` prende quelle da **tenere** — se un
  /// domani quell'elenco arrivasse storto, il peggio che può succedere è che
  /// non si tolga niente.
  ///
  /// Gli orfani non passano di qui: non si misurano in byte e non stanno
  /// nell'elenco delle voci. Hanno il loro verbo e la loro strada.
  Future<Tolta> _perLaRadice(String id, Map<String, dynamic> v, int byte,
      int fatte, int quante) async {
    final chiedi = radice;
    if (chiedi == null) {
      racconta?.call('pulizia',
          '${v['nome']}: serve la password, lasciata dov\'è', fatte, quante);
      return Tolta(id, byte, false,
          'Sta fuori dalla tua cartella: serve la password, e passa '
          'dall\'aiutante di root.');
    }

    final (verbo, argomenti) = switch (id) {
      'cache-pacchetti' => ('pulisci-cache-pacchetti', <String>[]),
      // Le lingue da tenere: la tua e l'inglese, più `C`, che non è una
      // lingua ma il ripiego di ogni programma che non trova la sua.
      'lingue' => ('pulisci-lingue', _lingueDaTenere()),
      'registro' => ('pulisci-registro', <String>[]),
      _ => ('', <String>[]),
    };
    if (verbo.isEmpty) {
      return Tolta(id, byte, false,
          'Non so togliere questa, e non provo a indovinare.');
    }

    racconta?.call('pulizia',
        '${v['nome']}: chiedo la password…', fatte - 1, quante);
    final r = await chiedi(verbo, argomenti);
    if (r['ok'] == true) {
      racconta?.call(
          'pulizia', 'Tolto ${v['nome']} — ${_inParole(byte)}', fatte, quante);
      return Tolta(id, byte, true);
    }
    // «Annullato» non è un guasto: è una risposta, ed è la tua.
    final perche = r['annullato'] == true
        ? 'Hai annullato la richiesta della password.'
        : '${r['error'] ?? r['errore'] ?? 'Non ci sono riuscito.'}';
    racconta?.call('pulizia', '${v['nome']}: $perche', fatte, quante);
    return Tolta(id, byte, false, perche);
  }

  /// Le lingue che restano installate.
  ///
  /// **L'inglese c'è sempre**, e non è una comodità: è la lingua in cui parla
  /// mezzo software del mondo quando la tua non c'è. Senza, i programmi che
  /// non sono tradotti in italiano non tornano in italiano — tornano in una
  /// lingua a caso o in nessuna. Con lui `C`, che non è una lingua ma il
  /// ripiego di chi non ne trova nessuna.
  ///
  /// Poi la tua, letta dall'ambiente e non indovinata.
  ///
  /// La stessa garanzia è ripetuta dentro `scripts/minerva-radice`, che è
  /// l'ultimo a decidere: se questo conto sbagliasse, o se qualcuno chiamasse
  /// quel verbo a mano, l'inglese e la tua lingua resterebbero lo stesso.
  /// Due controlli per la stessa cosa, e qui è giusto così — sbagliare
  /// costa una macchina in una lingua che non capisci.
  List<String> _lingueDaTenere() {
    final fuori = <String>{'en', 'C'};
    for (final chiave in ['LANG', 'LC_ALL', 'LC_MESSAGES']) {
      final v = Platform.environment[chiave];
      if (v == null || v.isEmpty) continue;
      final corta = v.split(RegExp(r'[._@]')).first;
      if (RegExp(r'^[A-Za-z][A-Za-z0-9]*$').hasMatch(corta)) fuori.add(corta);
    }
    return fuori.toList()..sort();
  }

  /// ── Come si toglie, che dipende da cosa ──────────────────────────────────
  ///
  /// Una cartella di cache si toglie intera: il programma se la rifà. Il
  /// cestino e `/tmp` no — quelli sono **contenitori**, e cancellarli come
  /// cartella vorrebbe dire togliere il cestino invece che svuotarlo.
  ///
  /// E `/tmp` ha una regola in più, perché è l'unico posto dove può esserci
  /// roba **in uso adesso**: si toccano solo i file più vecchi di un giorno.
  /// Un programma aperto da un'ora ci tiene dentro cose che gli servono, e
  /// togliergliele sotto vuol dire farlo cadere. Si svuota comunque al
  /// riavvio, quindi la fretta qui non serve a niente.
  Future<int> _svuota(String dove, String id) async {
    final contenitore = id == 'cestino' || id == 'temporanei';
    if (!contenitore) {
      await _togli(dove);
      return 0;
    }

    final ieri = DateTime.now().subtract(const Duration(days: 1));
    var quanti = 0;
    for (final figlio in await _figliDa(dove)) {
      if (id == 'temporanei') {
        final quando = await _quando(figlio);
        if (quando == null || quando.isAfter(ieri)) continue;
      }
      try {
        await _togli(figlio);
        quanti++;
      } catch (_) {
        // Un file che non si lascia togliere non ferma gli altri: è quasi
        // sempre roba di un programma acceso, e la prossima volta non ci sarà.
      }
    }
    return quanti;
  }

  static String _perche(Object e) {
    if (e is PathAccessException) return 'Non ho il permesso di toccarla.';
    if (e is PathNotFoundException) return 'Non c\'era più.';
    return 'Non ci sono riuscito.';
  }

  static String _inParole(int byte) {
    if (byte < 1000) return '$byte B';
    if (byte < 1000000) return '${(byte / 1000).round()} KB';
    if (byte < 1000000000) return '${(byte / 1000000).round()} MB';
    return '${(byte / 1000000000).toStringAsFixed(2).replaceAll('.', ',')} GB';
  }
}
