import 'dart:io';

import 'archive_service.dart';

/// Installare un set di icone preso da fuori.
///
/// ── Perché SOLO le icone, e perché adesso ─────────────────────────────────
///
/// Giacomo, 19 agosto 2026: «vorrei anche poter installare set di icone e temi
/// allo stesso modo».
///
/// I due casi si somigliano solo da fuori. I temi di **icone** sono già file,
/// e uno standard che non abbiamo inventato noi: una cartella con dentro
/// `index.theme` e le immagini, in `~/.local/share/icons`, che
/// `services/icon_resolver.dart` legge già. Installarne uno vuol dire
/// spacchettare nel posto giusto.
///
/// I temi di **colore** di Minerva no: vivono dentro `theme/Colors.qml`, che è
/// codice. Installarne uno da uno zip non è una funzione da aggiungere — è un
/// cambio di architettura, e ha già il suo posto nella tabella di marcia.
/// Prometterlo qui vorrebbe dire prometterlo a metà.
///
/// ── Un tema è DATI, e questa è la regola che conta ────────────────────────
///
/// Un archivio che arriva da internet e finisce dentro `~/.local/share` è il
/// posto classico in cui «installa questo tema» diventa «esegui questo». Qui
/// dentro si accettano immagini e file di testo; **eseguibili, script e
/// `.desktop` fanno rifiutare l'intero archivio**, dicendo quale file e
/// perché.
///
/// Non è una precauzione teorica: `.desktop` è un file di testo che dice al
/// sistema quale comando lanciare, e un tema di icone non ha nessun motivo di
/// portarne uno.
///
/// Lo *zip slip* — il membro chiamato `../../.bashrc` — lo ferma già
/// `ArchiveService`, e non per fiducia: c'è una prova che costruisce un
/// archivio cattivo apposta e verifica che non esca (`archive_service_test`).
class TemaIconeService {
  const TemaIconeService();

  /// Dove finiscono i temi installati da qui. È la cartella dell'utente, non
  /// quella di sistema: installare un tema non deve chiedere una password, e
  /// soprattutto non deve poter rompere l'installazione di tutti.
  static String cartellaUtente(String home) => '$home/.local/share/icons';

  /// I temi nella cartella dell'utente, cioè quelli che `disinstalla` può
  /// togliere: `{nome, cartella}`, in ordine di nome. I temi di sistema non
  /// ci sono, di proposito — vedi `disinstalla`.
  /// Cartelle che stanno in `~/.local/share/icons` ma non sono temi da
  /// togliere: `hicolor` è dove le APP installano le proprie icone (Steam, i
  /// giochi, i Flatpak), e toglierla le lascerebbe tutte senza icona.
  static const _intoccabili = {'hicolor', 'default', 'locolor'};

  static List<Map<String, String>> installati(String home) {
    final d = Directory(cartellaUtente(home));
    if (!d.existsSync()) return const [];
    final fuori = <Map<String, String>>[];
    for (final e in d.listSync(followLinks: false)) {
      if (e is! Directory) continue;
      if (_intoccabili.contains(e.path.split('/').last)) continue;
      if (!File('${e.path}/index.theme').existsSync()) continue;
      fuori.add({'nome': e.path.split('/').last, 'cartella': e.path});
    }
    fuori.sort((a, b) =>
        a['nome']!.toLowerCase().compareTo(b['nome']!.toLowerCase()));
    return fuori;
  }

  /// Quello che un tema di icone può contenere.
  static const Set<String> _estensioniBuone = {
    '.png', '.svg', '.svgz', '.xpm', '.jpg', '.jpeg', '.gif', '.webp',
    '.theme', '.txt', '.md', '.license', '.cache', '.icon',
  };

  /// Quello che fa rifiutare tutto, col motivo che si legge.
  static const Map<String, String> _estensioniVietate = {
    '.desktop': 'dice al sistema quale comando lanciare',
    '.sh': 'è uno script',
    '.bash': 'è uno script',
    '.zsh': 'è uno script',
    '.py': 'è uno script',
    '.pl': 'è uno script',
    '.rb': 'è uno script',
    '.so': 'è codice compilato',
    '.appimage': 'è un programma',
    '.run': 'è un programma',
    '.bin': 'è un programma',
  };

  /// Il nome del tema, se questa cartella ne è uno.
  ///
  /// Lo dice `index.theme`: senza, non è un tema di icone ma una cartella di
  /// immagini, e metterla lì dentro non servirebbe a niente.
  static Future<String?> nomeDelTema(Directory dir) async {
    final indice = File('${dir.path}/index.theme');
    if (!await indice.exists()) return null;
    for (final r in await indice.readAsLines()) {
      final t = r.trim();
      if (t.startsWith('Name=')) {
        final n = t.substring(5).trim();
        if (n.isNotEmpty) return n;
      }
    }
    // Un `index.theme` senza `Name=` è raro ma non è un errore: vale il nome
    // della cartella, che è quello che i programmi usano comunque.
    return dir.path.split('/').last;
  }

  /// La cartella che contiene davvero il tema.
  ///
  /// Un archivio scaricato può avere il tema in cima, oppure dentro una
  /// cartella sola (`Papirus-1.2/Papirus/`), che è il caso normale. Si cerca
  /// `index.theme` scendendo, ma **non a fondo**: due livelli bastano, e più
  /// giù si rischia di prendere una sottocartella di misure (`48x48/`) per un
  /// tema.
  static Future<Directory?> radiceDelTema(Directory dentro) async {
    if (await File('${dentro.path}/index.theme').exists()) return dentro;
    for (var livello = 0; livello < 2; livello++) {
      final figlie = <Directory>[];
      for (final v in dentro.listSync()) {
        if (v is Directory) figlie.add(v);
      }
      for (final f in figlie) {
        if (await File('${f.path}/index.theme').exists()) return f;
      }
      if (figlie.length != 1) break;
      dentro = figlie.first;
    }
    return null;
  }

  /// Guarda dentro e dice di no se trova qualcosa che non è un'icona.
  ///
  /// Torna `null` se va bene, altrimenti il motivo, scritto per chi legge.
  static Future<String?> controllaContenuto(Directory dir) async {
    await for (final v in dir.list(recursive: true, followLinks: false)) {
      if (v is! File) continue;
      final nome = v.path.split('/').last;
      final punto = nome.lastIndexOf('.');
      final est = punto <= 0 ? '' : nome.substring(punto).toLowerCase();

      final vietato = _estensioniVietate[est];
      if (vietato != null) {
        return 'Contiene «$nome», che $vietato. Un tema di icone sono '
            'immagini: questo non lo è, e non lo installo.';
      }

      // Il permesso di esecuzione conta quanto il nome: un file senza
      // estensione ma eseguibile è la forma più vecchia dello stesso trucco.
      final stat = await v.stat();
      if (stat.mode & 0x49 != 0) {
        return 'Contiene «$nome», che è marcato come eseguibile. Un tema di '
            'icone non ha niente da eseguire.';
      }

      if (est.isNotEmpty && !_estensioniBuone.contains(est)) {
        return 'Contiene «$nome», che non è un\'immagine né un file di testo. '
            'Nel dubbio non lo installo.';
      }
    }
    return null;
  }

  /// Installa un tema da un archivio o da una cartella già scompattata.
  Future<Map<String, dynamic>> installa(String percorso, String home) async {
    final sorgente = File(percorso);
    final cartella = Directory(percorso);
    final eCartella = await cartella.exists();
    if (!eCartella && !await sorgente.exists()) {
      return {'ok': false, 'error': 'Non trovo «${percorso.split('/').last}».'};
    }

    // Gli archivi si aprono in un posto temporaneo: si guarda cosa c'è dentro
    // PRIMA di metterlo fra i temi. Al contrario, un archivio cattivo avrebbe
    // già scritto dove voleva quando ce ne accorgiamo.
    Directory? temporanea;
    Directory dentro;
    try {
      if (eCartella) {
        dentro = cartella;
      } else {
        temporanea = await Directory.systemTemp.createTemp('minerva-icone-');
        final estratto =
            await const ArchiveService().estrai(percorso, dove: temporanea.path);
        if (estratto['ok'] != true) {
          return {
            'ok': false,
            'error': 'Non sono riuscito ad aprire l\'archivio: '
                '${estratto['error'] ?? 'motivo sconosciuto'}',
          };
        }
        dentro = Directory(estratto['cartella'] as String? ?? temporanea.path);
      }

      final radice = await radiceDelTema(dentro);
      if (radice == null) {
        return {
          'ok': false,
          'error': 'Non è un tema di icone: manca «index.theme», il file che '
              'dice come si chiama il tema e come è fatto.',
        };
      }

      final problema = await controllaContenuto(radice);
      if (problema != null) return {'ok': false, 'error': problema};

      final nome = await nomeDelTema(radice) ?? radice.path.split('/').last;
      final destinazione =
          Directory('${cartellaUtente(home)}/${radice.path.split('/').last}');

      if (await destinazione.exists()) {
        return {
          'ok': false,
          'error': '«$nome» è già installato. Toglilo prima, se vuoi '
              'rimetterlo: sovrascrivere un tema mentre lo stai usando lo '
              'lascerebbe a metà.',
        };
      }

      await destinazione.parent.create(recursive: true);
      await _copiaCartella(radice, destinazione);

      return {
        'ok': true,
        'nome': nome,
        'cartella': destinazione.path,
        'messaggio': '«$nome» installato in ${destinazione.path}',
      };
    } catch (e) {
      return {'ok': false, 'error': 'Non è andata: $e'};
    } finally {
      if (temporanea != null && await temporanea.exists()) {
        await temporanea.delete(recursive: true);
      }
    }
  }

  /// Toglie un tema installato **da qui**.
  ///
  /// Solo da `~/.local/share/icons`: i temi di sistema non sono nostri, e
  /// cancellarli romperebbe la scrivania di chiunque altro usi il computer.
  Future<Map<String, dynamic>> disinstalla(String cartella, String home) async {
    final base = cartellaUtente(home);
    final d = Directory(cartella);
    // Confronto sul percorso RISOLTO: un collegamento simbolico che punta
    // altrove passerebbe un controllo fatto sulla stringa.
    final vero = await d.exists() ? d.resolveSymbolicLinksSync() : cartella;
    if (_intoccabili.contains(vero.split('/').last)) {
      return {
        'ok': false,
        'error': 'Quella cartella non è un tema: ci sono le icone dei '
            'programmi installati, e non la tocco.',
      };
    }
    if (!vero.startsWith('$base/')) {
      return {
        'ok': false,
        'error': 'Quel tema non l\'ha installato Minerva: sta fuori dalla tua '
            'cartella dei temi, e non lo tocco.',
      };
    }
    if (!await d.exists()) {
      return {'ok': false, 'error': 'Quel tema non c\'è più.'};
    }
    await d.delete(recursive: true);
    return {'ok': true, 'messaggio': 'Tema tolto.'};
  }

  Future<void> _copiaCartella(Directory da, Directory a,
      {String? radice}) async {
    final cima = radice ?? _normale(da.absolute.path);
    await a.create(recursive: true);
    await for (final v in da.list(recursive: false, followLinks: false)) {
      final nome = v.path.split('/').last;
      if (v is Directory) {
        await _copiaCartella(v, Directory('${a.path}/$nome'), radice: cima);
      } else if (v is File) {
        await v.copy('${a.path}/$nome');
      } else if (v is Link) {
        // ── I collegamenti si tengono, se restano dentro il tema ─────────
        //
        // Si saltavano tutti, per paura di ricrearli puntati fuori. Ma i
        // temi grandi SONO fatti di collegamenti — in Papirus e Breeze metà
        // delle icone sono alias di un'altra, e a volte un'intera cartella
        // di misura (`@2x`) è un collegamento — e il tema installato usciva
        // pieno di buchi (30 settembre 2026). Si ricrea uguale un
        // collegamento RELATIVO che, risolto, resta dentro il tema; quelli
        // assoluti o che escono si saltano ancora.
        final bersaglio = await v.target();
        if (bersaglio.startsWith('/')) continue;
        final dove = _normale('${_normale(da.absolute.path)}/$bersaglio');
        if (dove != cima && !dove.startsWith('$cima/')) continue;
        await Link('${a.path}/$nome').create(bersaglio);
      }
    }
  }

  /// Il percorso senza `.` e `..`, senza toccare il disco.
  static String _normale(String percorso) =>
      Uri.file(percorso).normalizePath().toFilePath();
}
