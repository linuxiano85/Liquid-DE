import 'dart:io';

/// Un gestore di accessi installato su questo computer.
class GestoreAccesso {
  /// Il nome dell'unità systemd: `greetd.service`, `plasmalogin.service`.
  /// È anche l'identificatore che si passa allo script, ed è l'unica cosa
  /// che va convalidata prima di arrivare a `systemctl`.
  final String unita;

  /// Come si chiama per chi guarda.
  final String nome;

  /// Vero per quello acceso adesso.
  final bool attuale;

  /// Vero per il nostro. Non è vanità: la schermata di Minerva ha bisogno di
  /// una configurazione scritta in `/etc/greetd` che gli altri non hanno, e
  /// chi accende deve saperlo.
  final bool nostro;

  const GestoreAccesso({
    required this.unita,
    required this.nome,
    required this.attuale,
    required this.nostro,
  });

  Map<String, dynamic> toJson() => {
        'unita': unita,
        'nome': nome,
        'attuale': attuale,
        'nostro': nostro,
      };
}

/// Chi ti apre la porta all'accensione.
///
/// ── Perché esiste ──────────────────────────────────────────────────────────
///
/// Giacomo, 23 agosto 2026: «nelle impostazioni voglio aggiungere
/// un'impostazione per impostare il login manager predefinito, nel caso in cui
/// io voglia quello di kde o cosmic o gnome o altri».
///
/// Ha ragione due volte. La prima è ovvia: è casa sua. La seconda conta di
/// più — la nostra schermata di accesso è il pezzo che, sbagliato, chiude
/// fuori dal computer, e finora l'unico modo di tornare indietro era ricordarsi
/// `sudo minerva-greetd indietro` da una console testuale. Una levetta nelle
/// Impostazioni è anche una via di ritorno.
///
/// ── Come si riconosce un gestore di accessi ────────────────────────────────
///
/// Non da un elenco di nomi scritto a mano: da `Alias=display-manager.service`
/// dentro l'unità. È la riga con cui systemd sa che quel servizio È il gestore
/// di accessi, ed è la stessa che rende `/etc/systemd/system/
/// display-manager.service` un collegamento a lui. Chi installa un gestore che
/// non conosciamo compare lo stesso; chi ne disinstalla uno sparisce da solo.
///
/// I nomi per esteso sono un abbellimento e basta: se un'unità non è nella
/// tabella si mostra il suo nome così com'è, che è meglio di non mostrarla.
class GestoriAccessoService {
  const GestoriAccessoService({
    this.cartelleUnita = const [
      '/etc/systemd/system',
      '/usr/lib/systemd/system',
      '/lib/systemd/system',
    ],
    this.collegamentoAttuale = '/etc/systemd/system/display-manager.service',
  });

  final List<String> cartelleUnita;

  /// Il collegamento che systemd fa puntare al gestore acceso.
  final String collegamentoAttuale;

  /// La riga che dichiara «io sono il gestore di accessi».
  static const String _alias = 'Alias=display-manager.service';

  /// Il nostro.
  static const String unitaNostra = 'greetd.service';

  /// Solo per far leggere meglio l'elenco. Chi manca si mostra col suo nome.
  static const Map<String, String> _nomiBelli = {
    'greetd.service': 'Minerva',
    'sddm.service': 'SDDM (KDE)',
    'plasmalogin.service': 'KDE Plasma',
    'gdm.service': 'GNOME',
    'lightdm.service': 'LightDM',
    'cosmic-greeter.service': 'COSMIC',
    'ly.service': 'Ly',
    'emptty.service': 'emptty',
    'lxdm.service': 'LXDM',
    'xdm.service': 'XDM',
  };

  /// Un nome di unità che si può passare a `systemctl` senza pentirsene.
  ///
  /// Questo controllo è la metà che conta di tutta la funzione: il nome
  /// arriva da una finestra e finisce dentro un comando eseguito da root.
  /// Senza, «abilita il gestore di accessi» diventa «abilita qualunque
  /// servizio», e con un po' di fantasia «esegui qualunque cosa».
  ///
  /// La stessa regola sta anche in `scripts/minerva-greetd`, e deve starci:
  /// quello script si può lanciare a mano, e un controllo che vive solo
  /// nell'interfaccia non è un controllo.
  static final RegExp _nomeLecito = RegExp(r'^[A-Za-z0-9@._-]{1,64}\.service$');

  static bool nomeAccettabile(String unita) {
    if (!_nomeLecito.hasMatch(unita)) return false;
    // Nessuna risalita, per quanto il modello sopra già la escluda: due
    // controlli che dicono la stessa cosa costano niente, e questo è il punto
    // in cui un errore si paga caro.
    if (unita.contains('..') || unita.contains('/')) return false;
    return true;
  }

  Future<List<GestoreAccesso>> elenco() async {
    final attuale = await unitaAttuale();
    final visti = <String>{};
    final fuori = <GestoreAccesso>[];

    for (final c in cartelleUnita) {
      final d = Directory(c);
      if (!await d.exists()) continue;

      List<FileSystemEntity> voci;
      try {
        voci = await d.list(followLinks: false).toList();
      } catch (_) {
        continue;
      }
      voci.sort((a, b) => a.path.compareTo(b.path));

      for (final v in voci) {
        if (v is! File || !v.path.endsWith('.service')) continue;
        final unita = v.path.split('/').last;
        if (!nomeAccettabile(unita)) continue;
        // La prima cartella dell'elenco vince: `/etc` sovrascrive `/usr/lib`,
        // che è esattamente l'ordine con cui systemd le legge.
        if (visti.contains(unita)) continue;

        String testo;
        try {
          testo = await v.readAsString();
        } catch (_) {
          continue;
        }
        if (!testo.contains(_alias)) continue;

        visti.add(unita);
        fuori.add(GestoreAccesso(
          unita: unita,
          nome: _nomiBelli[unita] ?? unita.replaceAll('.service', ''),
          attuale: unita == attuale,
          nostro: unita == unitaNostra,
        ));
      }
    }

    fuori.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
    return fuori;
  }

  /// Quello acceso adesso, o vuoto se non lo è nessuno.
  ///
  /// Si legge dal collegamento e non da `systemctl is-enabled`: il
  /// collegamento è quello che systemd guarda davvero all'avvio, e leggerlo
  /// costa una chiamata invece di un processo.
  Future<String> unitaAttuale() async {
    try {
      final l = Link(collegamentoAttuale);
      if (await l.exists()) {
        return (await l.target()).split('/').last;
      }
    } catch (_) {}
    return '';
  }
}
