import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ricetta.dart';

/// Da dove vengono i sorgenti del kernel, e come si scaricano senza fidarsi
/// della strada.
///
/// ── Le due sorgenti ─────────────────────────────────────────────────────
///
/// Giacomo usava «sia i repository di Linux che quelli di CachyOS».
///
/// * **Linux**: l'archivio ufficiale da kernel.org.
/// * **CachyOS, dalla 6.17**: l'archivio di CachyOS stesso
///   (`github.com/CachyOS/linux`, etichetta `cachyos-<versione>-<n>`), che è
///   già il loro kernel con le loro patch e lo scheduler BORE dentro — quello
///   che scarica il loro PKGBUILD. Firmato da due sviluppatori di CachyOS.
/// * **CachyOS prima della 6.17**: l'archivio di kernel.org con la loro serie
///   base e BORE applicati sopra, come faceva il loro PKGBUILD allora.
///
/// Fino al 4 ottobre 2026 la Fucina faceva la terza cosa per TUTTE le serie.
/// Dalla 6.18 la serie base non c'è più, e la patch BORE è scritta per il
/// LORO albero, non per quello di kernel.org: sul 7.2.9 falliva 9 blocchi su
/// 22. Giacomo: «cerca di applicare delle patch e fallisce quando il kernel
/// cachy ha già tante patch».
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
/// L'archivio di CachyOS si verifica come quello di kernel.org: firma `.asc`
/// accanto all'archivio, chiavi accettate solo per impronta
/// ([firmatariCachyos], dai `validpgpkeys` del loro PKGBUILD). Le patch della
/// strada vecchia invece NON sono firmate: nel kernel pronto resta scritta la
/// somma di ognuna.
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

  /// Le etichette dell'albero di CachyOS, dallo stesso protocollo di git.
  static final Uri refsLinuxCachyos = Uri.parse(
      'https://github.com/CachyOS/linux/info/refs?service=git-upload-pack');

  /// L'etichetta di CachyOS per una versione di kernel.org: la più recente
  /// (`cachyos-7.2.9-2` batte `cachyos-7.2.9-1`), o `null` se non c'è.
  static String? etichettaCachyos(String refs, String versione) {
    final v = RegExp.escape(versione);
    var meglio = -1;
    for (final m in RegExp('refs/tags/cachyos-$v-(\\d+)(?![\\d.^])')
        .allMatches(refs)) {
      final n = int.parse(m.group(1)!);
      if (n > meglio) meglio = n;
    }
    return meglio < 0 ? null : 'cachyos-$versione-$meglio';
  }

  static Uri archivioCachyos(String etichetta) => Uri.parse(
      'https://github.com/CachyOS/linux/releases/download/$etichetta/'
      '$etichetta.tar.gz');

  /// La firma è sull'archivio `.tar.gz` così com'è.
  static Uri firmaCachyos(String etichetta) => Uri.parse(
      'https://github.com/CachyOS/linux/releases/download/$etichetta/'
      '$etichetta.tar.gz.asc');

  /// Chi firma gli archivi di CachyOS: i `validpgpkeys` del PKGBUILD di
  /// `linux-cachyos`, copiati il 4 ottobre 2026.
  static const Map<String, String> firmatariCachyos = {
    'E18447AC260021D31F3FF6C4C8A2A4774B8B63C4': 'Eric Naim',
    'E8B9AA39F054E30E8290D492C3C4820857F654FE': 'Peter Jung',
  };

  /// La chiave pubblica di un firmatario di CachyOS per impronta, da
  /// keys.openpgp.org. Si accetta comunque solo se l'impronta della firma è
  /// fra [firmatariCachyos].
  static Uri chiaveCachyos(String impronta) =>
      Uri.parse('https://keys.openpgp.org/vks/v1/by-fingerprint/$impronta');

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
    // CachyOS c'è per una versione se ha il suo archivio (dalla 6.17), o
    // altrimenti se pubblica ancora la serie base da applicare sopra quello
    // di kernel.org. BORE da solo sopra kernel.org NON è «CachyOS»: è una
    // patch scritta per un altro albero.
    final refs = await testo(refsLinuxCachyos);
    await Future.wait([
      for (final v in fuori)
        () async {
          final versione = '${v['versione']}';
          final etichetta =
              refs == null ? null : etichettaCachyos(refs, versione);
          if (etichetta != null) {
            v['cachyos'] = true;
            v['cachyosEtichetta'] = etichetta;
            return;
          }
          final base = await esiste(baseCachyos(serieDi(versione)))
              .catchError((_) => false);
          v['cachyosBase'] = base;
          v['cachyos'] = base;
        }(),
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

/// La verifica dell'archivio di CachyOS: la firma `.asc` accanto all'archivio,
/// le chiavi dei due firmatari da keys.openpgp.org nello stesso portachiavi
/// nostro, e gpg direttamente sul `.tar.gz` (la firma è su quello). Si accetta
/// solo una firma valida la cui impronta primaria è fra
/// `Sorgenti.firmatariCachyos`.
Future<String?> verificaArchivioCachyos({
  required String etichetta,
  required File archivio,
  required String portachiavi,
  required Sorgenti sorgenti,
  required Future<String?> Function(Uri, File) scarica,
  void Function(String)? racconta,
}) async {
  final firma = File('${archivio.path}.asc');
  final e = await scarica(Sorgenti.firmaCachyos(etichetta), firma);
  if (e != null) return 'Non riesco a scaricare la firma di CachyOS: $e';

  final casa = Directory(portachiavi);
  await casa.create(recursive: true);
  try {
    await Process.run('chmod', ['700', casa.path]);
  } catch (_) {}
  for (final impronta in Sorgenti.firmatariCachyos.keys) {
    final chiave = await sorgenti.testo(Sorgenti.chiaveCachyos(impronta));
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
      return 'Manca gpg (pacchetto gnupg): senza, la firma di CachyOS non si '
          'può verificare, e non compilo un archivio non verificato.';
    }
  }

  final ProcessResult r;
  try {
    r = await Process.run('gpg', [
      '--homedir', casa.path, '--batch', '--status-fd', '1',
      '--verify', firma.path, archivio.path,
    ]);
  } on ProcessException {
    return 'Manca gpg (pacchetto gnupg): senza, la firma di CachyOS non si '
        'può verificare.';
  }
  final chi = Sorgenti.firmataDa('${r.stdout}');
  if (chi == null || !Sorgenti.firmatariCachyos.containsKey(chi)) {
    return 'La firma di $etichetta non torna, o non è di uno dei firmatari di '
        'CachyOS: ho cancellato l\'archivio. Se succede ancora, non fidarti '
        'della rete che stai usando.';
  }
  racconta?.call(
      'Firmato da ${Sorgenti.firmatariCachyos[chi]} ($chi): la firma torna.');
  return null;
}
