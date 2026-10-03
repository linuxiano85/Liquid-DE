import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ricetta.dart';

/// Da dove vengono i sorgenti del kernel, e come si scaricano senza fidarsi
/// della strada.
///
/// ── Le due sorgenti ─────────────────────────────────────────────────────
///
/// Giacomo usava «sia i repository di Linux che quelli di CachyOS». Qui non
/// sono due alberi separati: è **un albero solo** — l'archivio ufficiale da
/// kernel.org — e, se si sceglie CachyOS, le loro patch applicate sopra: lo
/// scheduler BORE sempre, la serie base dove CachyOS la pubblica ancora
/// (fino alla 6.17). Una sola strada da scaricare, controllare e
/// ricompilare.
///
/// ── Due controlli, e che cosa garantisce ognuno ─────────────────────────
///
/// 1. **La somma SHA-256** di `sha256sums.asc`: protegge da un download
///    troncato o rovinato, che è il caso vero di tutti i giorni. Viene dallo
///    stesso posto dell'archivio, quindi da sola non protegge da un
///    kernel.org compromesso.
/// 2. **La firma dello sviluppatore** (`linux-X.Y.Z.tar.sign`), verificata
///    con gpg contro le impronte scritte QUI SOTTO, copiate dalla pagina
///    ufficiale https://www.kernel.org/signature.html il 30 settembre 2026.
///    Le chiavi si scaricano dal repository `pgpkeys` di kernel.org, ma si
///    accettano solo se la loro impronta primaria è una di queste quattro:
///    chi sostituisse la chiave sul server non otterrebbe la stessa impronta.
///
/// Le patch di CachyOS NON sono firmate: si prendono dal loro repository così
/// come sono, e nel kernel pronto resta scritta la somma di ognuna. Chi sceglie
/// CachyOS si fida di CachyOS, esattamente come chi installa il loro kernel.
///
/// (Trovato da una revisione automatica della PR il 30 settembre: la prima
/// versione si fermava alla somma, e lo diceva, ma non bastava.)
class Sorgenti {
  /// Scarica un testo. Si sostituisce nelle prove: una prova che va in rete
  /// misura la rete di chi la lancia.
  final Future<String?> Function(Uri) testo;

  /// Dice se un indirizzo esiste (una richiesta HEAD).
  final Future<bool> Function(Uri) esiste;

  Sorgenti({
    Future<String?> Function(Uri)? testo,
    Future<bool> Function(Uri)? esiste,
  })  : testo = testo ?? _testoVero,
        esiste = esiste ?? _esisteVero;

  static final Uri rilasci = Uri.parse('https://www.kernel.org/releases.json');

  static Uri archivio(String versione) => Uri.parse(
      'https://cdn.kernel.org/pub/linux/kernel/v${versione.split('.').first}.x/'
      'linux-$versione.tar.xz');

  /// La firma dello sviluppatore: è sull'archivio `.tar`, non sul `.xz`,
  /// quindi si verifica decomprimendo.
  static Uri firma(String versione) => Uri.parse(
      'https://cdn.kernel.org/pub/linux/kernel/v${versione.split('.').first}.x/'
      'linux-$versione.tar.sign');

  /// Chi firma i rilasci del kernel, per impronta primaria. Dalla pagina
  /// https://www.kernel.org/signature.html, sezione «Important fingerprints».
  static const Map<String, String> firmatari = {
    'ABAF11C65A2970B130ABE3C479BE3E4300411886': 'Linus Torvalds',
    '647F28654894E3BD457199BE38DBBDC86092693E': 'Greg Kroah-Hartman',
    'E27E5D8A3403A2EF66873BBCDEA66FF797772CDC': 'Sasha Levin',
    'AC2B29BD34A6AFDDB3F68F35E7BFC8EC95861109': 'Ben Hutchings',
  };

  /// La chiave pubblica di un firmatario, dal repository `pgpkeys` di
  /// kernel.org. Il nome del file sono gli ultimi sedici caratteri
  /// dell'impronta.
  static Uri chiave(String impronta) => Uri.parse(
      'https://git.kernel.org/pub/scm/docs/kernel/pgpkeys.git/plain/keys/'
      '${impronta.substring(impronta.length - 16)}.asc');

  /// Dall'uscita `--status-fd` di gpg: l'impronta primaria di una firma
  /// valida, o `null`. La riga è `[GNUPG:] VALIDSIG` seguita
  /// dall'impronta della sottochiave, da altri campi e, in fondo,
  /// dall'impronta primaria: conta l'ultima.
  static String? firmataDa(String stato) {
    if (RegExp(r'^\[GNUPG:\] (BADSIG|ERRSIG|EXPKEYSIG|REVKEYSIG) ', multiLine: true)
        .hasMatch(stato)) {
      return null;
    }
    final m = RegExp(r'^\[GNUPG:\] VALIDSIG (.+)$', multiLine: true)
        .firstMatch(stato);
    if (m == null) return null;
    return m.group(1)!.trim().split(RegExp(r'\s+')).last.toUpperCase();
  }

  static Uri somme(String versione) => Uri.parse(
      'https://cdn.kernel.org/pub/linux/kernel/v${versione.split('.').first}.x/'
      'sha256sums.asc');

  /// La serie base di CachyOS per una serie del kernel. **Può non
  /// esserci**: fino alla 6.17 CachyOS la pubblicava in
  /// `kernel-patches/<serie>/all/`, dalla 6.18 in quella cartella non c'è più
  /// (trovato il 30 settembre 2026 guardando il loro repository, dopo che la
  /// prima versione della Fucina la dava per scontata).
  static Uri baseCachyos(String serie, [String rif = 'master']) => Uri.parse(
      'https://raw.githubusercontent.com/CachyOS/kernel-patches/$rif/'
      '$serie/all/0001-cachyos-base-all.patch');

  /// Lo scheduler BORE nella versione di CachyOS: c'è per tutte le serie, ed
  /// è quello del loro kernel di serie.
  static Uri boreCachyos(String serie, [String rif = 'master']) => Uri.parse(
      'https://raw.githubusercontent.com/CachyOS/kernel-patches/$rif/'
      '$serie/sched/0001-bore-cachy.patch');

  /// Dove si chiede a che commit è `master` delle patch di CachyOS: il
  /// protocollo HTTP di git, lo stesso di `git ls-remote`, che non passa
  /// dall'API di GitHub e dai suoi limiti.
  static final Uri refsCachyos = Uri.parse(
      'https://github.com/CachyOS/kernel-patches/info/refs?service=git-upload-pack');

  /// Il commit di `master` dalla risposta di [refsCachyos], o `null`.
  static String? commitDaRefs(String risposta) => RegExp(
          r'([0-9a-f]{40}) refs/heads/master\b')
      .firstMatch(risposta)
      ?.group(1);

  /// Le versioni che si possono scegliere, con quale sorgente ha ognuna.
  ///
  /// Solo `stable` e `longterm`: le candidate di `mainline` non stanno su
  /// cdn.kernel.org con le altre e non hanno una somma pubblicata, e
  /// `linux-next` non è un rilascio. Per ogni serie si chiede anche se
  /// CachyOS ha le sue patch: una richiesta HEAD per serie, in parallelo.
  Future<Map<String, dynamic>> versioni() async {
    final t = await testo(rilasci);
    if (t == null) {
      return {
        'ok': false,
        'errore': 'Non riesco a leggere l\'elenco da kernel.org. Sei in rete?',
        'versioni': <dynamic>[],
      };
    }
    final List<Map<String, dynamic>> fuori;
    try {
      fuori = leggiRilasci(t);
    } catch (e) {
      return {
        'ok': false,
        'errore': 'kernel.org ha risposto con qualcosa che non capisco.',
        'versioni': <dynamic>[],
      };
    }
    // Due domande per serie, in parallelo: BORE (senza, «CachyOS» non vuol
    // dire niente) e la serie base (che dalla 6.18 non si trova più lì).
    await Future.wait([
      for (final v in fuori) ...[
        esiste(boreCachyos(serieDi('${v['versione']}')))
            .then((si) => v['cachyos'] = si)
            .catchError((_) => v['cachyos'] = false),
        esiste(baseCachyos(serieDi('${v['versione']}')))
            .then((si) => v['cachyosBase'] = si)
            .catchError((_) => v['cachyosBase'] = false),
      ],
    ]);
    return {'ok': true, 'versioni': fuori};
  }

  /// La parte pura di [versioni]: da `releases.json` all'elenco.
  static List<Map<String, dynamic>> leggiRilasci(String json) {
    final dati = jsonDecode(json) as Map<String, dynamic>;
    final fuori = <Map<String, dynamic>>[];
    for (final r in (dati['releases'] as List)) {
      if (r is! Map) continue;
      final tipo = '${r['moniker']}';
      final versione = '${r['version']}';
      if (tipo != 'stable' && tipo != 'longterm') continue;
      if (!versioneValida(versione)) continue;
      fuori.add({
        'versione': versione,
        'tipo': tipo,
        'finita': r['iseol'] == true,
        'data': (r['released'] is Map) ? '${r['released']['isodate']}' : '',
        'cachyos': false,
        'cachyosBase': false,
      });
    }
    return fuori;
  }

  /// La somma di un archivio dentro `sha256sums.asc`. Il file è firmato in
  /// chiaro: le righe utili sono `<somma>  <nome>`, e tutto il resto (la
  /// firma, le intestazioni) non combacia con la forma e si salta.
  static String? sommaDi(String somme, String nomeFile) {
    final nome = RegExp.escape(nomeFile);
    final m = RegExp('^([0-9a-f]{64})\\s+\\*?$nome\\s*\$', multiLine: true)
        .firstMatch(somme);
    return m?.group(1);
  }

  static Future<String?> _testoVero(Uri u) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await c.getUrl(u);
      final res = await req.close().timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
      return await res.transform(utf8.decoder).join();
    } catch (_) {
      return null;
    } finally {
      c.close(force: true);
    }
  }

  static Future<bool> _esisteVero(Uri u) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await c.headUrl(u);
      final res = await req.close().timeout(const Duration(seconds: 15));
      await res.drain<void>();
      return res.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      c.close(force: true);
    }
  }
}

/// Scarica un file grande su disco, raccontando quanto manca.
///
/// Si scrive in `<nome>.parte` e si rinomina solo alla fine: un archivio
/// mezzo scaricato con il nome giusto è un archivio che la volta dopo
/// sembra già pronto. Restituisce `null` se è andata, o la frase da dire.
Future<String?> scaricaFile(
  Uri da,
  File a, {
  void Function(int ricevuti, int totale)? progresso,
  bool Function()? annullato,
}) async {
  final parte = File('${a.path}.parte');
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  IOSink? scrittura;
  try {
    await a.parent.create(recursive: true);
    final req = await c.getUrl(da);
    final res = await req.close();
    if (res.statusCode != 200) {
      await res.drain<void>();
      return '${da.host} ha risposto ${res.statusCode} per ${da.path}.';
    }
    final totale = res.contentLength;
    var ricevuti = 0;
    var ultimo = DateTime.fromMillisecondsSinceEpoch(0);
    final w = parte.openWrite();
    scrittura = w;
    await for (final pezzo in res) {
      if (annullato?.call() == true) {
        await w.close();
        scrittura = null;
        await _togli(parte);
        return 'Annullato.';
      }
      w.add(pezzo);
      ricevuti += pezzo.length;
      // Non più di quattro volte al secondo: ogni racconto è un messaggio
      // sul canale, e un archivio da 150 MB arriva in decine di migliaia di
      // pezzi.
      final ora = DateTime.now();
      if (ora.difference(ultimo).inMilliseconds >= 250) {
        ultimo = ora;
        progresso?.call(ricevuti, totale);
      }
    }
    await w.flush();
    await w.close();
    scrittura = null;
    if (totale > 0 && ricevuti != totale) {
      await _togli(parte);
      return 'Il download si è interrotto a metà ($ricevuti di $totale byte).';
    }
    progresso?.call(ricevuti, totale);
    await parte.rename(a.path);
    return null;
  } catch (e) {
    try {
      await scrittura?.close();
    } catch (_) {}
    await _togli(parte);
    return 'Download non riuscito: $e';
  } finally {
    c.close(force: true);
  }
}

Future<void> _togli(File f) async {
  try {
    if (await f.exists()) await f.delete();
  } catch (_) {}
}

/// La verifica vera: la firma da cdn.kernel.org, le chiavi dal repository
/// `pgpkeys` di kernel.org in un portachiavi tutto nostro (non quello di
/// chi usa il computer), e gpg sull'archivio decompresso. Si accetta solo
/// una firma valida la cui impronta primaria è fra `Sorgenti.firmatari`.
Future<String?> verificaArchivio({
required String versione,
required File archivio,
required String portachiavi,
required Sorgenti sorgenti,
required Future<String?> Function(Uri, File) scarica,
void Function(String)? racconta,
}) async {
  final firma = File('${archivio.path.replaceAll('.tar.xz', '')}.tar.sign');
  final e = await scarica(Sorgenti.firma(versione), firma);
  if (e != null) return 'Non riesco a scaricare la firma: $e';

  final casa = Directory(portachiavi);
  await casa.create(recursive: true);
  try {
    await Process.run('chmod', ['700', casa.path]);
  } catch (_) {}
  for (final impronta in Sorgenti.firmatari.keys) {
    final chiave = await sorgenti.testo(Sorgenti.chiave(impronta));
    if (chiave == null) continue;
    try {
      final p = await Process.start(
          'gpg', ['--homedir', casa.path, '--batch', '--quiet', '--import']);
      p.stdin.write(chiave);
      await p.stdin.close();
      await p.stdout.drain<void>();
      await p.stderr.drain<void>();
      await p.exitCode;
    } on ProcessException {
      return 'Manca gpg (pacchetto gnupg): senza, la firma del kernel non si '
          'può verificare, e non compilo un archivio non verificato.';
    }
  }

  final Process xz;
  final Process gpg;
  try {
    xz = await Process.start('xz', ['-dc', archivio.path]);
    gpg = await Process.start('gpg', [
      '--homedir', casa.path, '--batch', '--status-fd', '1',
      '--verify', firma.path, '-',
    ]);
  } on ProcessException catch (e) {
    return 'Non riesco ad avviare «${e.executable}»: serve per verificare '
        'la firma.';
  }
  final stato = StringBuffer();
  final letto = gpg.stdout.transform(utf8.decoder).listen(stato.write)
      .asFuture<void>();
  final errori = gpg.stderr.drain<void>();
  try {
    await xz.stdout.pipe(gpg.stdin);
  } catch (_) {
    // gpg può chiudere l'ingresso prima della fine (una firma rotta): il
    // verdetto lo dice lui, qui sotto.
  }
  await xz.stderr.drain<void>();
  await xz.exitCode;
  await gpg.exitCode;
  await letto;
  await errori;

  final chi = Sorgenti.firmataDa(stato.toString());
  if (chi == null || !Sorgenti.firmatari.containsKey(chi)) {
    return 'La firma di linux-$versione non torna, o non è di uno dei '
        'firmatari di kernel.org: ho cancellato l\'archivio. Se succede '
        'ancora, non fidarti della rete che stai usando.';
  }
  racconta?.call('Firmato da ${Sorgenti.firmatari[chi]} ($chi): la firma torna.');
  return null;
}
