import 'dart:io';

/// Una sessione che si può avviare dalla schermata di accesso.
class Sessione {
  /// Il nome del file senza estensione (`minerva`, `hyprland`, `plasma`).
  final String id;

  /// Come si chiama per chi guarda.
  final String nome;
  final String descrizione;

  /// La riga da passare a greetd. Resta una STRINGA e non un elenco: è la riga
  /// del file `.desktop`, e chi la eseguirà è `sh`, come fa ogni gestore di
  /// accessi. Spezzarla qui sugli spazi romperebbe ogni sessione installata in
  /// una cartella con uno spazio nel nome — e questo progetto vive proprio in
  /// una di quelle.
  final String comando;

  /// `wayland` o `x11`. Non è decorazione: serve a mostrare quale si sta per
  /// avviare quando ce ne sono due con lo stesso nome.
  final String tipo;

  /// Il campo `DesktopNames` del `.desktop`, che diventerà `XDG_CURRENT_DESKTOP`
  /// nella sessione avviata. Vuoto se il file non lo dichiara.
  ///
  /// Non è un dettaglio: è la variabile con cui una scrivania riconosce sé
  /// stessa e con cui i portali xdg scelgono il proprio backend. Senza,
  /// `plasma.desktop` e `hyprland.desktop` partono senza sapere di essere KDE
  /// e Hyprland. Fino al 17 agosto 2026 questa riga non veniva letta da
  /// nessuno, e la schermata di accesso avviava OGNI sessione con il solo
  /// `XDG_SESSION_DESKTOP`.
  ///
  /// Resta la stringa com'è scritta nel file — `KDE`, `Hyprland`,
  /// `Minerva;Hyprland;` — perché è già il formato che la variabile vuole:
  /// nomi separati da punto e virgola.
  final String nomiScrivania;

  const Sessione({
    required this.id,
    required this.nome,
    required this.descrizione,
    required this.comando,
    required this.tipo,
    this.nomiScrivania = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'nome': nome,
        'descrizione': descrizione,
        'comando': comando,
        'tipo': tipo,
        'nomiScrivania': nomiScrivania,
      };
}

/// Un utente che può accedere.
class Utente {
  final String nome;

  /// Il nome per esteso, dal campo GECOS. Vuoto se non c'è: si mostra `nome`.
  final String nomeCompleto;
  final int uid;
  final String casa;

  /// Il ritratto, se ce n'è uno. Vuoto se non c'è — e la schermata disegna
  /// un'iniziale, che è meglio di un riquadro vuoto.
  final String ritratto;

  const Utente({
    required this.nome,
    required this.nomeCompleto,
    required this.uid,
    required this.casa,
    required this.ritratto,
  });

  Map<String, dynamic> toJson() => {
        'nome': nome,
        'nomeCompleto': nomeCompleto,
        'uid': uid,
        'casa': casa,
        'ritratto': ritratto,
      };
}

/// Chi può entrare, e in cosa.
///
/// ── Perché legge i file invece di chiedere a qualcuno ──────────────────────
///
/// Un greeter gira PRIMA che ci sia una sessione: non c'è un bus utente, non
/// c'è AccountsService avviato per forza, e l'utente `greeter` non ha
/// nemmeno una casa propria da leggere. Restano i file di sistema, che ci
/// sono sempre. È anche il motivo per cui ogni lettura qui dentro sopporta di
/// non trovare niente: su un computer diverso da questo, mezze di queste
/// cartelle non esistono.
class AccessoService {
  /// Dove stanno le sessioni. Parametri e non costanti perché è l'unico modo
  /// di provarli senza scriverli in `/usr/share`.
  final List<String> cartelleWayland;
  final List<String> cartelleX11;

  /// Da dove si leggono gli utenti.
  final String filePasswd;

  /// Dove il sistema tiene i ritratti (AccountsService). Si guarda anche in
  /// `~/.face`, che è la convenzione più vecchia e ancora diffusa.
  final String cartellaRitratti;

  const AccessoService({
    this.cartelleWayland = const ['/usr/share/wayland-sessions'],
    this.cartelleX11 = const ['/usr/share/xsessions'],
    this.filePasswd = '/etc/passwd',
    this.cartellaRitratti = '/var/lib/AccountsService/icons',
  });

  // ── Chi avvia la sessione ────────────────────────────────────────────────
  //
  // `scripts/minerva-avvia-sessione`, che l'installatore del greeter copia
  // qui. Non avvia niente di suo: esegue il comando della sessione e lascia
  // scritto nel registro dell'utente che cosa ha avviato, con quale ambiente,
  // e quanto è durata.
  //
  // Esiste perché una sessione che muore in un secondo non lasciava NIENTE —
  // e da fuori è indistinguibile da una password sbagliata. Il file racconta
  // la storia per esteso.
  //
  // Si dice alla schermata se c'è, e se non c'è la schermata avvia come
  // prima (`sh -lc`). **Niente di quello che aggiungiamo può diventare un
  // motivo per non entrare**: un registro in più vale molto meno di un
  // computer che si apre.
  static const String percorsoAvviatore =
      '/usr/local/lib/minerva/minerva-avvia-sessione';

  static Future<bool> avviatoreDisponibile({String? percorso}) async {
    try {
      final f = File(percorso ?? percorsoAvviatore);
      if (!await f.exists()) return false;
      // Esiste non basta: dev'essere eseguibile, o greetd fallirebbe l'avvio
      // e il difetto sarebbe peggiore di quello che si sta curando.
      return (await f.stat()).mode & 0x49 != 0; // 0o111
    } catch (_) {
      return false;
    }
  }

  // ── Le sessioni ──────────────────────────────────────────────────────────

  /// L'id della via di scorta. Non viene da nessun file: la mettiamo noi.
  static const String idConsole = 'console';

  /// Un accesso che non ha bisogno di nessuna scrivania.
  ///
  /// ── Perché c'è ───────────────────────────────────────────────────────────
  ///
  /// Giacomo, 23 agosto 2026: «magari aggiungere un accesso con solo il
  /// terminale in caso ci siano errori con il desktop environment, per non
  /// rimanere esclusi in caso non ci sia un desktop environment o si rompa».
  ///
  /// Ha ragione, e questo progetto ne ha già le prove: fino a ieri KDE non
  /// entrava, e per due volte una sessione morta ha lasciato Giacomo davanti a
  /// uno schermo nero. Una schermata di accesso che sa aprire SOLO scrivanie è
  /// una porta con una serratura sola.
  ///
  /// `${SHELL:-/bin/sh}` e non una shell scritta a mano: è la shell vera della
  /// persona che entra — qui `fish` — e la sostituisce la shell di greetd, che
  /// a quel punto ha già l'ambiente di PAM. Se `SHELL` non c'è si ripiega su
  /// `/bin/sh`, che su un sistema Linux c'è per definizione.
  ///
  /// Non apre niente a nessuno: PAM chiede la password come per ogni altra
  /// voce, ed è lo stesso identico accesso che si otterrebbe con Ctrl+Alt+F3.
  /// Vedi [[minerva-console-fn]] — su questa tastiera quel tasto è dietro Fn,
  /// e non è detto che a mente fredda ci si arrivi.
  static const Sessione console = Sessione(
    id: idConsole,
    nome: 'Riga di comando',
    descrizione: 'Nessuna scrivania: solo un terminale, per rimettere a posto '
        'le cose quando il resto non parte',
    comando: r'exec ${SHELL:-/bin/sh} -l',
    tipo: 'tty',
    nomiScrivania: '',
  );

  Future<List<Sessione>> sessioni() async {
    final fuori = <Sessione>[];
    final visti = <String>{};

    Future<void> guarda(List<String> cartelle, String tipo) async {
      for (final c in cartelle) {
        final d = Directory(c);
        if (!await d.exists()) continue;

        final voci = await d.list().toList();
        voci.sort((a, b) => a.path.compareTo(b.path));

        for (final v in voci) {
          if (v is! File || !v.path.endsWith('.desktop')) continue;

          final s = await _leggiSessione(v, tipo);
          if (s == null) continue;

          // Una sessione con lo stesso id in due cartelle è la stessa
          // sessione: vince la prima cartella dell'elenco, che è la più
          // specifica. Mostrarla due volte farebbe scegliere a caso.
          if (!visti.add('$tipo/${s.id}')) continue;
          fuori.add(s);
        }
      }
    }

    await guarda(cartelleWayland, 'wayland');
    await guarda(cartelleX11, 'x11');

    // Ultima, sempre, e mai la prima: è una via di scorta, non una scelta di
    // tutti i giorni. Sta in fondo anche perché la schermata preseleziona per
    // id, e se un giorno sparissero tutte le scrivanie questa resterebbe
    // l'unica — che è esattamente il caso per cui esiste.
    // (A meno che una scrivania non si chiami davvero `console.desktop`: la
    // sua è vera, la nostra è di scorta, e due voci con lo stesso id
    // farebbero scegliere a caso.)
    if (!fuori.any((s) => s.id == idConsole)) fuori.add(console);
    return fuori;
  }

  Future<Sessione?> _leggiSessione(File f, String tipo) async {
    try {
      final righe = await f.readAsLines();

      String nome = '';
      String descrizione = '';
      String comando = '';
      String tryExec = '';
      String nomiScrivania = '';
      bool nascosta = false;
      bool dentroLaVoce = false;

      for (final grezza in righe) {
        final r = grezza.trim();
        if (r.isEmpty || r.startsWith('#')) continue;

        // Un `.desktop` può avere più sezioni (`[Desktop Action …]`), e le
        // altre hanno anche loro un `Name=` e un `Exec=`. Senza questo
        // controllo si finisce per mostrare il nome di un'azione al posto di
        // quello della sessione.
        if (r.startsWith('[')) {
          dentroLaVoce = r == '[Desktop Entry]';
          continue;
        }
        if (!dentroLaVoce) continue;

        final i = r.indexOf('=');
        if (i <= 0) continue;
        final chiave = r.substring(0, i).trim();
        final valore = r.substring(i + 1).trim();

        // Si prende solo la chiave senza lingua (`Name=`, non `Name[it]=`):
        // tradurre la schermata di accesso è compito nostro, e prendere la
        // prima traduzione che capita darebbe un elenco in tre lingue diverse.
        switch (chiave) {
          case 'Name':
            nome = valore;
            break;
          case 'Comment':
            descrizione = valore;
            break;
          case 'Exec':
            comando = valore;
            break;
          case 'TryExec':
            tryExec = valore;
            break;
          case 'DesktopNames':
            nomiScrivania = valore;
            break;
          case 'Hidden':
          case 'NoDisplay':
            if (valore.toLowerCase() == 'true') nascosta = true;
            break;
        }
      }

      if (nascosta || comando.isEmpty) return null;

      // `TryExec` esiste apposta per questo: se il programma non c'è, la voce
      // non va mostrata. Una sessione che non parte è peggio di una sessione
      // che manca — la scegli, lo schermo si spegne, e torni qui senza sapere
      // perché.
      if (tryExec.isNotEmpty && !await _eseguibile(tryExec)) return null;

      final id = f.uri.pathSegments.last.replaceAll('.desktop', '');
      return Sessione(
        id: id,
        nome: nome.isEmpty ? id : nome,
        descrizione: descrizione,
        comando: comando,
        tipo: tipo,
        // Se il file non lo dichiara si ripiega sul nome: è meglio di niente,
        // e per le scrivanie che contano il campo c'è sempre.
        nomiScrivania: nomiScrivania.isNotEmpty
            ? nomiScrivania
            : (nome.isEmpty ? id : nome),
      );
    } catch (_) {
      // Un `.desktop` illeggibile non deve far sparire gli altri.
      return null;
    }
  }

  Future<bool> _eseguibile(String comando) async {
    if (comando.contains('/')) return File(comando).exists();
    for (final d in (Platform.environment['PATH'] ?? '/usr/bin:/bin').split(':')) {
      if (d.isEmpty) continue;
      if (await File('$d/$comando').exists()) return true;
    }
    return false;
  }

  // ── Gli utenti ───────────────────────────────────────────────────────────

  /// Le persone, distinte dagli account di servizio.
  ///
  /// Il confine è l'UID: sotto `uidMinimo` ci sono `root`, `daemon`, `nobody` e
  /// le decine di account che i pacchetti creano per i loro servizi. Mostrarli
  /// in una schermata di accesso non serve a nessuno e regala a chi guarda
  /// l'elenco dei servizi installati.
  Future<List<Utente>> utenti({int uidMinimo = 1000, int uidMassimo = 60000}) async {
    final f = File(filePasswd);
    if (!await f.exists()) return [];

    final fuori = <Utente>[];
    for (final riga in await f.readAsLines()) {
      final c = riga.split(':');
      if (c.length < 7) continue;

      final uid = int.tryParse(c[2]);
      if (uid == null || uid < uidMinimo || uid > uidMassimo) continue;

      // Una shell che non è una shell vuol dire un account che non entra:
      // `nobody`, `nologin`, e gli account bloccati.
      final shell = c[6];
      if (shell.endsWith('/nologin') || shell.endsWith('/false')) continue;

      final nome = c[0];
      final casa = c[5];

      // Il campo GECOS è «Nome Cognome,ufficio,telefono,…»: interessa solo il
      // primo pezzo.
      final gecos = c[4].split(',').first.trim();

      fuori.add(Utente(
        nome: nome,
        nomeCompleto: gecos,
        uid: uid,
        casa: casa,
        ritratto: await _ritratto(nome, casa),
      ));
    }

    fuori.sort((a, b) => a.uid.compareTo(b.uid));
    return fuori;
  }

  Future<String> _ritratto(String nome, String casa) async {
    for (final p in [
      '$cartellaRitratti/$nome',
      '$casa/.face',
      '$casa/.face.icon',
    ]) {
      // Il greeter gira come utente `greeter`: la casa di qualcun altro può
      // benissimo non essere leggibile, e chiedere se un file esiste dentro
      // una cartella vietata solleva. Vale come «non c'è».
      try {
        if (await File(p).exists()) return p;
      } catch (_) {}
    }
    return '';
  }
}
