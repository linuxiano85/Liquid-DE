// guardia.dart — La guardia: le forme che fanno danno, riconosciute PRIMA.
//
// Un terminale esegue quello che gli dici. Questo lo fa lo stesso — ma per
// un elenco chiuso di forme che non tornano indietro dice prima COSA
// farebbe, in italiano, e chiede. Non è un filtro «intelligente»: è una
// lista di regole scritte, provate una per una, e chi vuole passare passa
// (`forza`). Una guardia che indovina è una guardia di cui non ci si fida.
//
// Due livelli:
//
//     blocca   cancella o sovrascrive cose che non tornano (la radice, la
//              casa, un disco intero): si chiede una conferma esplicita
//     avvisa   fa una cosa grossa ma normale (`rm -rf` di una cartella,
//              spegnere, eseguire uno script dalla rete): si dice, e si
//              passa con un Invio in più
//
// La riga si spezza in segmenti (pipe, `&&`, `;`) e ogni segmento si
// giudica da solo, senza `sudo` davanti: `sudo rm -rf /` è `rm -rf /`.
//
// In Palestra (tappa 3) le regole sono più strette: `rm` solo dentro la
// palestra, `sudo` rifiutato, `cd` fuori rifiutato — via `radiceConsentita`.
library;

import 'dizionario.dart';

class Giudizio {
  const Giudizio(this.livello, this.comando, this.motivo, this.cosa);
  /// `blocca` o `avvisa`.
  final String livello;
  /// Il comando che ha fatto scattare la regola.
  final String comando;
  /// Perché, in una riga.
  final String motivo;
  /// Cosa farebbe, per esteso.
  final String cosa;

  Map<String, dynamic> aMappa() => {
        'livello': livello,
        'comando': comando,
        'motivo': motivo,
        'cosa': cosa,
      };
}

class Guardia {
  Guardia({this.radiceConsentita, this.casa});

  /// In Palestra: la sola cartella in cui si può cancellare e da cui non si
  /// può uscire. Null fuori dalla Palestra.
  final String? radiceConsentita;
  /// `$HOME`, per riconoscere `~` e `/home/x` come la casa.
  final String? casa;

  static const _trasparenti = {'sudo', 'doas', 'env', 'time', 'nohup', 'exec', 'command', 'builtin', 'nice', 'ionice'};
  static final _assegnazione = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*=');
  static final _dispositivo = RegExp(r'^/dev/(sd[a-z]|nvme\d+n\d+|mmcblk\d+|vd[a-z]|hd[a-z]|disk/|mapper/|md\d+)');

  /// Il giudizio più grave sulla riga, o null se passa.
  Giudizio? giudica(String riga, {String? cartella}) {
    Giudizio? peggiore;
    for (final segmento in spezzaPipeline(riga)) {
      final g = _segmento(segmento, riga, cartella);
      if (g == null) continue;
      if (peggiore == null || (g.livello == 'blocca' && peggiore.livello != 'blocca')) {
        peggiore = g;
      }
    }
    // La forma della fork bomb non passa dalla pipeline: `:(){ :|:& };:`.
    if (RegExp(r':\(\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;\s*:').hasMatch(riga.replaceAll(' ', ''))
        || riga.replaceAll(' ', '').contains(':(){:|:&};:')) {
      return const Giudizio('blocca', ':()', 'È una fork bomb.',
          'Lancia copie di sé stessa senza fine finché il computer non risponde più. Non fa niente di utile.');
    }
    return peggiore;
  }

  Giudizio? _segmento(String segmento, String riga, String? cartella) {
    final parole = spezzaParole(segmento);
    if (parole.isEmpty) return null;
    var i = 0;
    var conSudo = false;
    while (i < parole.length &&
        (_trasparenti.contains(parole[i]) || _assegnazione.hasMatch(parole[i]) ||
            (i > 0 && _trasparenti.contains(parole[i - 1]) && parole[i].startsWith('-')) ||
            (i > 1 && _trasparenti.contains(parole[i - 2]) && const {'-u', '-g', '-C', '-D'}.contains(parole[i - 1])))) {
      if (parole[i] == 'sudo' || parole[i] == 'doas') conSudo = true;
      i++;
    }
    if (i >= parole.length) return null;
    final nome = parole[i].split('/').last;
    final args = parole.sublist(i + 1);
    final opzioni = args.where((a) => a.startsWith('-') && a != '-').toList();
    final bersagli = args.where((a) => !a.startsWith('-') || a == '-').toList();

    // I reindirizzamenti verso un disco: `> /dev/sda`, `>/dev/nvme0n1`.
    final red = RegExp(r'>\s*(/dev/\S+)').firstMatch(segmento);
    if (red != null && _dispositivo.hasMatch(red.group(1)!)) {
      return Giudizio('blocca', nome, 'Scrive direttamente sul disco ${red.group(1)}.',
          'Un `>` verso un dispositivo a blocchi sovrascrive il disco dall\'inizio: la tabella delle partizioni e tutto quello che c\'è. Non torna.');
    }

    // ── La Palestra: sudo e cd fuori ─────────────────────────────────────
    final radice = radiceConsentita;
    if (radice != null) {
      if (conSudo) {
        return const Giudizio('blocca', 'sudo', 'In Palestra non si usa sudo.',
            'Gli esercizi stanno tutti nella cartella della Palestra, dove non serve nessun permesso in più. Un comando con sudo lì dentro non ha ragione di esistere.');
      }
      if (nome == 'cd' && bersagli.isNotEmpty) {
        final dest = _assoluto(bersagli.first, cartella ?? radice);
        if (!_dentro(dest, radice)) {
          return Giudizio('blocca', 'cd', 'In Palestra si resta nella palestra.',
              'La cartella $dest sta fuori da $radice. Gli esercizi si fanno lì dentro, dove niente di quello che fai può toccare i tuoi file veri.');
        }
      }
    }

    switch (nome) {
      case 'rm':
        return _rm(opzioni, bersagli, cartella);
      case 'dd':
        for (final a in args) {
          if (a.startsWith('of=') && _dispositivo.hasMatch(a.substring(3))) {
            return Giudizio('blocca', 'dd', 'Sovrascrive il disco ${a.substring(3)} byte per byte.',
                'dd copia byte grezzi senza chiedere. Con `of=` su un disco cancella tutto quello che c\'è sopra — partizioni, sistema, dati. Se è una chiavetta da rendere avviabile, verifica PRIMA con `lsblk` che ${a.substring(3)} sia lei e non il disco interno.');
          }
        }
        return null;
      case 'mkfs':
      case 'wipefs':
      case 'fdisk':
      case 'sfdisk':
      case 'cfdisk':
      case 'parted':
      case 'gdisk':
      case 'mkswap':
        if (nome == 'fdisk' && opzioni.contains('-l') && bersagli.isEmpty) return null;
        if (nome == 'parted' && (args.contains('print') || args.contains('-l'))) return null;
        final dove = bersagli.isNotEmpty ? bersagli.first : 'un disco';
        return Giudizio('blocca', nome,
            nome == 'mkfs' ? 'Formatta $dove: cancella tutto quello che contiene.'
                : 'Modifica le partizioni di $dove.',
            '$nome scrive sulla struttura del disco. Quello che c\'era sopra non si recupera con un comando. Vale la pena guardare `lsblk` e leggere due volte il nome del dispositivo.');
      default:
        break;
    }
    if (nome.startsWith('mkfs.')) {
      final dove = bersagli.isNotEmpty ? bersagli.first : 'un disco';
      return Giudizio('blocca', nome, 'Formatta $dove: cancella tutto quello che contiene.',
          'Crea un filesystem nuovo e vuoto al posto di quello che c\'è. Non torna. Verifica con `lsblk` che $dove sia proprio la partizione che intendi.');
    }

    switch (nome) {
      case 'chmod':
      case 'chown':
      case 'chgrp':
        final ricorsivo = opzioni.any((o) => o == '-R' || o == '--recursive' || RegExp(r'^-[a-zA-Z]*R').hasMatch(o));
        if (ricorsivo) {
          for (final b in bersagli.skip(1)) {
            if (_critico(b, cartella)) {
              return Giudizio('blocca', nome, 'Cambia i permessi di $b e di tutto quello che contiene.',
                  '$nome -R su ${_nomeDi(b)} riscrive i permessi di ogni file del sistema: dopo, programmi che devono girare come root non partono più e l\'accesso può smettere di funzionare. Non c\'è un modo semplice di rimetterli com\'erano.');
            }
          }
          if (nome == 'chmod' && bersagli.isNotEmpty && RegExp(r'^[0-7]?777$').hasMatch(bersagli.first)) {
            return Giudizio('avvisa', 'chmod', 'Dà a tutti il permesso di leggere, scrivere ed eseguire tutto in ${bersagli.length > 1 ? bersagli[1] : "questa cartella"}.',
                '777 vuol dire che chiunque sulla macchina può modificare o cancellare quei file. Quasi mai è quello che serve: di solito basta 755 per le cartelle e 644 per i file.');
          }
        }
        return null;
      case 'mv':
        for (final b in bersagli) {
          if (_critico(b, cartella) && bersagli.indexOf(b) < bersagli.length - 1) {
            return Giudizio('blocca', 'mv', 'Sposta ${_nomeDi(b)} da un\'altra parte.',
                'Spostare $b vuol dire che il sistema (o la tua casa) non è più dove tutto se lo aspetta. Alla prossima cosa che fai, molto smette di funzionare.');
          }
        }
        return null;
      case 'curl':
      case 'wget':
        if (RegExp(r'\|\s*(sudo\s+)?(sh|bash|zsh|fish|dash|python3?|perl)\b').hasMatch(riga)) {
          return Giudizio('avvisa', nome, 'Scarica uno script dalla rete e lo esegue senza guardarlo.',
              'Quello che gira è quello che il sito manda in QUESTO momento, e non lo vedi passare. Se ti fidi del sito va bene; altrimenti scaricalo prima (`$nome -O`), leggilo, e poi lancialo.');
        }
        return null;
      case 'shutdown':
      case 'poweroff':
      case 'halt':
      case 'reboot':
        return Giudizio('avvisa', nome,
            nome == 'reboot' ? 'Riavvia il computer adesso.' : 'Spegne il computer adesso.',
            'Le finestre aperte si chiudono e quello che non è salvato si perde. Se è quello che vuoi, avanti.');
      case 'systemctl':
        if (args.any((a) => const {'poweroff', 'reboot', 'halt', 'kexec'}.contains(a))) {
          return Giudizio('avvisa', 'systemctl', args.contains('reboot') ? 'Riavvia il computer adesso.' : 'Spegne il computer adesso.',
              'Le finestre aperte si chiudono e quello che non è salvato si perde. Se è quello che vuoi, avanti.');
        }
        return null;
      case 'init':
      case 'telinit':
        if (bersagli.contains('0') || bersagli.contains('6')) {
          return const Giudizio('avvisa', 'init', 'Spegne o riavvia il computer adesso.', 'Le finestre aperte si chiudono e quello che non è salvato si perde.');
        }
        return null;
      case 'kill':
        if (args.contains('-1')) {
          return const Giudizio('avvisa', 'kill', 'Manda il segnale a TUTTI i tuoi processi.',
              '`kill -1` (meno uno) vuol dire tutti i processi che puoi toccare: la scrivania compresa. Ti ritrovi fuori dalla sessione.');
        }
        return null;
      case 'pkill':
      case 'killall':
        if (bersagli.any((b) => b == '.' || b == '' || b == '*') || (nome == 'pkill' && opzioni.contains('-f') && bersagli.any((b) => b == '.'))) {
          return Giudizio('avvisa', nome, 'Termina tutti i processi che riesce a raggiungere.',
              'Un motivo come `.` corrisponde a qualunque nome: la scrivania, il terminale, tutto. Meglio un nome preciso.');
        }
        if (bersagli.contains('minerva-wayland') || bersagli.contains('minervad') || bersagli.contains('qs')) {
          return Giudizio('avvisa', nome, 'Chiude un pezzo della scrivania di Minerva.',
              'Terminare ${bersagli.firstWhere((b) => b.startsWith('minerva') || b == 'qs')} chiude la sessione o la shell: le finestre spariscono. Se stai provando qualcosa, da un\'altra console.');
        }
        return null;
      case 'shred':
        for (final b in bersagli) {
          if (_critico(b, cartella) || _dispositivo.hasMatch(_assoluto(b, cartella ?? '/'))) {
            return Giudizio('blocca', 'shred', 'Sovrascrive $b più volte: non si recupera in nessun modo.',
                'shred esiste apposta perché quello che tocca non torni. Su un disco o una cartella di sistema è la fine di tutto quello che c\'è.');
          }
        }
        return Giudizio('avvisa', 'shred', 'Sovrascrive i file più volte prima di cancellarli.',
            'Nessun programma di recupero li rimette insieme dopo. È quello che shred serve a fare — basta che sia voluto.');
      case 'crontab':
        if (opzioni.contains('-r')) {
          return const Giudizio('avvisa', 'crontab', 'Cancella TUTTA la tua tabella dei comandi a orario, senza chiedere.',
              '`crontab -r` non chiede conferma (ed è a un tasto da `-e`). Per vederla prima: `crontab -l`.');
        }
        return null;
      case 'history':
        if (opzioni.contains('-c')) {
          return const Giudizio('avvisa', 'history', 'Cancella la storia dei comandi della shell.',
              'Quello che hai scritto finora non si ritrova più con ↑ né con Ctrl+R.');
        }
        return null;
      case 'find':
        if (args.contains('-delete')) {
          final dove = bersagli.isNotEmpty ? bersagli.first : '.';
          if (_critico(dove, cartella)) {
            return Giudizio('blocca', 'find', 'Cancella i file trovati sotto ${_nomeDi(dove)}.',
                '`find … -delete` toglie ogni file che corrisponde, e da $dove in giù vuol dire il sistema. Prima si guarda cosa trova, SENZA -delete.');
          }
          return Giudizio('avvisa', 'find', 'Cancella tutti i file che trova, senza chiedere.',
              'Il modo giusto è lanciare lo stesso comando senza `-delete`, guardare l\'elenco, e poi rimetterlo. Anche una `-name` scritta male qui cancella quello che non doveva.');
        }
        return null;
      case 'truncate':
      case 'cat':
        // `> file` su un file critico
        break;
    }
    // `> /etc/passwd`, `> ~/.zshrc` per sbaglio.
    final redFile = RegExp(r'(?<![>&\d])>\s*(?!>)(\S+)').firstMatch(segmento);
    if (redFile != null) {
      final dest = redFile.group(1)!;
      if (!dest.startsWith('/dev/') && _fileDiSistema(dest)) {
        return Giudizio('avvisa', nome, 'Sovrascrive $dest.',
            'Un `>` singolo svuota il file e ci scrive sopra. Per aggiungere in fondo si usa `>>`. Su un file di sistema, prima una copia: `sudo cp $dest $dest.bak`.');
      }
    }
    return null;
  }

  Giudizio? _rm(List<String> opzioni, List<String> bersagli, String? cartella) {
    final ricorsivo = opzioni.any((o) => o == '-r' || o == '-R' || o == '--recursive' ||
        RegExp(r'^-[a-zA-Z]*[rR]').hasMatch(o));
    final forza = opzioni.any((o) => o == '-f' || o == '--force' || RegExp(r'^-[a-zA-Z]*f').hasMatch(o));
    final radice = radiceConsentita;
    for (final b in bersagli) {
      if (radice != null) {
        final dest = _assoluto(b, cartella ?? radice);
        if (!_dentro(dest, radice)) {
          return Giudizio('blocca', 'rm', 'In Palestra si cancella solo dentro la palestra.',
              '$b sta fuori da $radice. Gli esercizi non toccano mai i tuoi file veri: è per questo che si può sbagliare senza paura.');
        }
      }
      if (_critico(b, cartella)) {
        return Giudizio('blocca', 'rm',
            'Cancella ${_nomeDi(b)}${ricorsivo ? ' e tutto quello che contiene' : ''}.',
            b == '/' || b == '/*'
                ? 'È il sistema intero: dopo non si riavvia. `rm` non passa dal cestino e non chiede due volte.'
                : 'È ${_nomeDi(b)}: i tuoi documenti, le foto, la configurazione di ogni programma. `rm` non passa dal cestino: quello che togli non torna.');
      }
      if (ricorsivo && (b == '*' || b == '.*' || b == './*')) {
        return Giudizio('blocca', 'rm', 'Cancella TUTTO in ${cartella ?? "questa cartella"}, ricorsivamente.',
            '`*` si espande a ogni file e cartella qui dentro. Con -r sparisce tutto, sottocartelle comprese, senza chiedere. Se è la cartella giusta, avanti; se sei in casa tua, no.');
      }
      if (ricorsivo && (b == '.' || b == '..')) {
        return Giudizio('blocca', 'rm', 'Cancella ${b == '.' ? 'questa cartella' : 'la cartella sopra'} con tutto quello che contiene.',
            'Sei in ${cartella ?? "una cartella"}: `rm -r $b` la toglie intera. Meglio dirla per nome, da fuori.');
      }
    }
    if (ricorsivo && forza && bersagli.isNotEmpty) {
      return Giudizio('avvisa', 'rm', 'Cancella ${bersagli.join(', ')} con tutto quello che contiene, senza chiedere.',
          '`-r` scende in ogni sottocartella, `-f` non chiede e non protesta. Non passa dal cestino. Se è una cartella di lavoro (build, node_modules) va benissimo; se ci sono cose tue dentro, no.');
    }
    return null;
  }

  // ── I percorsi ───────────────────────────────────────────────────────

  static const _radiciCritiche = {'/', '/*', '/etc', '/usr', '/bin', '/sbin', '/lib', '/lib64', '/boot', '/var', '/home', '/root', '/opt', '/sys', '/proc', '/dev', '/run', '/srv'};

  bool _critico(String b, String? cartella) {
    var p = b;
    if (p.endsWith('/') && p.length > 1) p = p.substring(0, p.length - 1);
    if (_radiciCritiche.contains(p)) return true;
    if (p == '~' || p == '~/' || p == '~/*' || p == r'$HOME' || p == r'$HOME/' || p == r'${HOME}') return true;
    final c = casa;
    if (c != null && (p == c || p == '$c/' || p == '$c/*')) return true;
    if (RegExp(r'^/home/[^/]+$').hasMatch(p) || RegExp(r'^/home/[^/]+/\*$').hasMatch(p)) return true;
    if (RegExp(r'^/(etc|usr|bin|lib|boot|var)/\*$').hasMatch(p)) return true;
    // `..` che risale fino alla radice: `../../../..`
    if (cartella != null && RegExp(r'^(\.\./)+\.\.?/?$').hasMatch(p)) {
      final dest = _assoluto(p, cartella);
      if (_radiciCritiche.contains(dest) || (c != null && dest == c)) return true;
    }
    return false;
  }

  bool _fileDiSistema(String dest) {
    return dest.startsWith('/etc/') || dest.startsWith('/boot/') || dest.startsWith('/usr/') ||
        RegExp(r'^~?/?(\.zshrc|\.bashrc|\.profile|\.zshenv|\.config/fish/config\.fish)$').hasMatch(dest) ||
        (casa != null && (dest == '$casa/.zshrc' || dest == '$casa/.bashrc'));
  }

  String _nomeDi(String b) {
    if (b == '/' || b == '/*') return 'la radice del sistema';
    if (b == '~' || b == '~/' || b == '~/*' || b == r'$HOME' || (casa != null && b.startsWith(casa!) && b.length <= casa!.length + 2)) {
      return 'la tua cartella personale';
    }
    if (RegExp(r'^/home/[^/]+/?\*?$').hasMatch(b)) return 'una cartella personale';
    return b;
  }

  String _assoluto(String p, String cartella) {
    var x = p;
    if (x.startsWith('~')) x = (casa ?? '') + x.substring(1);
    if (!x.startsWith('/')) x = '$cartella/$x';
    final parti = <String>[];
    for (final s in x.split('/')) {
      if (s.isEmpty || s == '.') continue;
      if (s == '..') {
        if (parti.isNotEmpty) parti.removeLast();
        continue;
      }
      parti.add(s);
    }
    return '/${parti.join('/')}';
  }

  bool _dentro(String p, String radice) {
    final r = radice.endsWith('/') ? radice.substring(0, radice.length - 1) : radice;
    return p == r || p.startsWith('$r/');
  }
}
