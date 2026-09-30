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
/// kernel.org — e, se si sceglie CachyOS, la loro serie di patch applicata
/// sopra. È esattamente come costruisce il proprio kernel CachyOS nel suo
/// PKGBUILD, e vuol dire una sola strada da scaricare, controllare e
/// ricompilare.
///
/// ── Che cosa garantisce la somma di controllo, e che cosa no ────────────
///
/// L'archivio si confronta con la somma SHA-256 che kernel.org pubblica
/// accanto (`sha256sums.asc`), scaricata anche lei in HTTPS. Protegge da un
/// download troncato o rovinato, che è il caso vero di tutti i giorni. NON
/// protegge da un kernel.org compromesso: per quello servirebbe verificare
/// la firma PGP del file delle somme, e oggi non lo facciamo. È scritto qui
/// perché nessuno creda il contrario.
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

  static Uri somme(String versione) => Uri.parse(
      'https://cdn.kernel.org/pub/linux/kernel/v${versione.split('.').first}.x/'
      'sha256sums.asc');

  /// Le patch di CachyOS per una serie, nell'ordine in cui si applicano: la
  /// serie base (che contiene già i loro miglioramenti di sistema) e lo
  /// scheduler BORE, che è quello del loro kernel di serie.
  static List<Uri> patchCachyos(String serie) => [
        Uri.parse('https://raw.githubusercontent.com/CachyOS/kernel-patches/'
            'master/$serie/all/0001-cachyos-base-all.patch'),
        Uri.parse('https://raw.githubusercontent.com/CachyOS/kernel-patches/'
            'master/$serie/sched/0001-bore-cachy.patch'),
      ];

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
    await Future.wait([
      for (final v in fuori)
        esiste(patchCachyos(serieDi('${v['versione']}')).first)
            .then((si) => v['cachyos'] = si)
            .catchError((_) => v['cachyos'] = false),
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
