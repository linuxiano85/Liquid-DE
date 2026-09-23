import 'dart:convert';
import 'dart:io';

/// Segreti — quello che non deve entrare nella storia.
///
/// ── Perché si controlla PRIMA di salvare, e non prima di mandare fuori ─────
///
/// Perché dopo il salvataggio è **irreparabile**. Una chiave entrata nella
/// storia ci resta anche se la si cancella il minuto dopo: il salvataggio
/// vecchio la contiene ancora, e per toglierla davvero bisogna riscrivere ogni
/// salvataggio successivo — cioè fare a mano la cosa più difficile di git,
/// esattamente quando si è nel panico.
///
/// L'invio è troppo tardi per un secondo motivo, meno ovvio: fra il salvataggio
/// e l'invio possono passare settimane. Chi riceve l'avviso in quel momento non
/// si ricorda più cosa aveva aggiunto, e la scelta più facile diventa
/// «mandalo lo stesso».
///
/// ── Cosa si guarda, e cosa NON si guarda ───────────────────────────────────
///
/// Si guardano **i nomi dei file** e **l'inizio del contenuto** dei file di
/// testo che stanno per entrare. Non si guarda dentro i binari, non si scansiona
/// tutta la storia, non si prova a essere un antivirus.
///
/// Il criterio di ogni riga qui sotto è uno solo: **quanto costa sbagliarsi.**
/// Un falso allarme costa un clic su «salvalo lo stesso». Una chiave privata
/// finita su GitHub costa cambiare ogni chiave che quella apriva. Con questo
/// rapporto, si è larghi.
class Segreti {
  const Segreti();

  /// Quanto si legge di ogni file. Una chiave privata, un `.env` o un file di
  /// configurazione dichiarano quello che sono nelle prime righe; un video di
  /// 4 GB non ha niente da dire e non va letto.
  static const int _quantoLeggo = 64 * 1024;

  /// I nomi che sono un segreto per definizione, qualunque cosa contengano.
  ///
  /// `id_rsa` vuoto è comunque un file che non deve stare in un progetto: se è
  /// lì, o è una chiave o è un errore, e in tutti e due i casi vale fermarsi.
  static const List<String> nomiSospetti = [
    'id_rsa', 'id_dsa', 'id_ecdsa', 'id_ed25519',
    '.env', '.env.local', '.env.production',
    'secrets.json', 'credentials.json', 'service-account.json',
    '.netrc', '.pgpass', '.npmrc', '.pypirc',
    'shadow', 'htpasswd',
  ];

  static const List<String> cartelleSospette = [
    '.ssh/', '.gnupg/', '.aws/', '.config/gh/',
  ];

  static const List<String> estensioniSospette = [
    '.pem', '.key', '.p12', '.pfx', '.jks', '.keystore', '.kdbx', '.asc',
  ];

  /// Quello che si riconosce dentro un file di testo.
  ///
  /// Sono forme **precise**, non parole generiche. `password` da sola
  /// squalificherebbe metà del codice di questo progetto — a partire dai
  /// commenti che spiegano perché una password non va scritta nei file.
  static final List<_Segno> _segni = [
    _Segno('una chiave privata',
        RegExp(r'-----BEGIN [A-Z ]*PRIVATE KEY-----')),
    _Segno('un gettone di GitHub',
        RegExp(r'\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}')),
    _Segno('un gettone di GitHub',
        RegExp(r'\bgithub_pat_[A-Za-z0-9_]{20,}')),
    _Segno('una chiave di Amazon', RegExp(r'\b(AKIA|ASIA)[0-9A-Z]{16}\b')),
    _Segno('una chiave di Google', RegExp(r'\bAIza[0-9A-Za-z_-]{35}\b')),
    _Segno('un gettone di Slack',
        RegExp(r'\bxox[abposr]-[0-9A-Za-z-]{10,}')),
    _Segno('una chiave di Stripe', RegExp(r'\b[sr]k_live_[0-9A-Za-z]{20,}')),
    _Segno('un gettone di Telegram',
        RegExp(r'\b\d{8,10}:AA[0-9A-Za-z_-]{33}\b')),
    _Segno('una password dentro un indirizzo',
        RegExp(r'://[^/\s:@]+:[^/\s:@]{4,}@')),
  ];

  /// Guarda i file che stanno per entrare nella storia.
  ///
  /// `percorsi` sono relativi a `cartella`. Torna un avviso per ognuno, vuoto
  /// se non c'è niente da dire.
  Future<List<Avviso>> guarda(String cartella, List<String> percorsi) async {
    final fuori = <Avviso>[];
    for (final p in percorsi) {
      final perNome = _dalNome(p);
      if (perNome != null) {
        fuori.add(Avviso(percorso: p, perche: perNome));
        continue;
      }
      final dentro = await _dalContenuto('$cartella/$p');
      if (dentro != null) fuori.add(Avviso(percorso: p, perche: dentro));
    }
    return fuori;
  }

  /// Pura, e quindi provabile senza toccare il disco.
  static String? _dalNome(String percorso) {
    final basso = percorso.toLowerCase();
    final nome = basso.split('/').last;

    for (final c in cartelleSospette) {
      if (basso.contains(c)) return 'sta in una cartella di chiavi ($c)';
    }
    for (final n in nomiSospetti) {
      if (nome == n) return 'si chiama «$n»';
    }
    for (final e in estensioniSospette) {
      if (nome.endsWith(e)) return 'è un file «$e», che di solito è una chiave';
    }
    // `qualcosa.key.esempio` non è un esempio: è ancora un `.key`.
    if (RegExp(r'\.(pem|key|p12|pfx)\.').hasMatch(nome)) {
      return 'ha «.key» o «.pem» nel nome';
    }
    return null;
  }

  Future<String?> _dalContenuto(String percorso) async {
    try {
      final f = File(percorso);
      if (!await f.exists()) return null;
      final quanto = await f.length();
      if (quanto == 0) return null;

      final crudi = await f
          .openRead(0, quanto < _quantoLeggo ? quanto : _quantoLeggo)
          .expand((x) => x)
          .toList();

      // Un NUL nei primi byte vuol dire binario: dentro non si guarda, e non
      // per prudenza — le forme qui sotto darebbero falsi allarmi a caso su
      // dati compressi, e un allarme che scatta a caso si impara a ignorare.
      if (crudi.take(1024).contains(0)) return null;

      final testo = utf8.decode(crudi, allowMalformed: true);
      for (final s in _segni) {
        if (s.forma.hasMatch(testo)) return 'contiene ${s.nome}';
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

class _Segno {
  const _Segno(this.nome, this.forma);
  final String nome;
  final RegExp forma;
}

class Avviso {
  const Avviso({required this.percorso, required this.perche});

  final String percorso;
  final String perche;

  Map<String, dynamic> toJson() => {'percorso': percorso, 'perche': perche};
}
