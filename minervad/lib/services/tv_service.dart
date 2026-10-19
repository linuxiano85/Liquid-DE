import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../util/sha256.dart';

/// Catalogo Free-TV, lo stesso provider predefinito di Hypnotix.
///
/// Privacy: parte una richiesta HTTPS al catalogo solo su domanda del client.
/// Non si contattano i canali, i loghi o gli EPG navigando nell'elenco.
/// La riproduzione contatterà invece il fornitore dello stream scelto.
/// Nessuna direttiva M3U viene eseguita; sono accettati solo URL HTTP(S).
class TvService {
  TvService({
    this.cartellaCache,
    Future<TvRisposta> Function(String? etag)? scarica,
    DateTime Function()? adesso,
  }) : _scaricaProva = scarica,
       _adesso = adesso ?? DateTime.now;

  static const fonte =
      'https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8';
  static const massimoByte = 4 * 1024 * 1024;
  static const validita = Duration(hours: 24);
  final String? cartellaCache;
  final Future<TvRisposta> Function(String? etag)? _scaricaProva;
  final DateTime Function() _adesso;
  List<Map<String, dynamic>> _canali = [];
  DateTime? _aggiornato;
  DateTime? _riprova;
  String? _etag;
  bool _lettoDisco = false;
  bool _chiuso = false;
  bool _obsoleto = false;
  Future<void>? _caricamento;
  HttpClient? _http;

  Future<Map<String, dynamic>> cerca({
    String testo = '',
    String paese = '',
    int inizio = 0,
    int limite = 100,
    bool aggiorna = false,
  }) async {
    final p = paese.trim().toUpperCase();
    if (testo.length > 200 ||
        (p.isNotEmpty && !RegExp(r'^[A-Z]{2,3}$').hasMatch(p)) ||
        inizio < 0 ||
        inizio > 10000 ||
        limite < 1 ||
        limite > 200) {
      throw ArgumentError('ricerca TV');
    }
    if (_chiuso) return {'error': 'media-closed', 'canali': [], 'paesi': []};
    await _assicurati(aggiorna);
    if (_chiuso) return {'error': 'media-closed', 'canali': [], 'paesi': []};
    final paesi = <String, Map<String, dynamic>>{};
    for (final c in _canali) {
      final code = c['paese'] as String;
      final group = paesi.putIfAbsent(
        code,
        () => {'codice': code, 'nome': c['nazione'], 'canali': 0},
      );
      group['canali'] = (group['canali'] as int) + 1;
    }
    final t = testo.trim().toLowerCase();
    final filtrati = _canali
        .where(
          (c) =>
              (p.isEmpty || c['paese'] == p) &&
              (t.isEmpty || (c['nome'] as String).toLowerCase().contains(t)),
        )
        .toList();
    return {
      'error': _canali.isEmpty ? 'tv-catalog-unavailable' : '',
      'warning': _obsoleto ? 'tv-catalog-stale' : '',
      'fonte': 'Free-TV',
      'aggiornato': _aggiornato?.toUtc().toIso8601String() ?? '',
      'paesi': paesi.values.toList()
        ..sort((a, b) => (a['nome'] as String).compareTo(b['nome'] as String)),
      'totale': filtrati.length,
      'inizio': inizio,
      'canali': filtrati.skip(inizio).take(limite).map(_copia).toList(),
      'altri': inizio + limite < filtrati.length,
    };
  }

  /// La UI risolve un ID del catalogo; non può far aprire URL arbitrari al servizio.
  Future<Map<String, dynamic>?> canale(String id) async {
    if (id.length > 80 || _chiuso) return null;
    await _assicurati(false);
    if (_chiuso) return null;
    for (final c in _canali) {
      if (c['id'] == id) return _copia(c);
    }
    return null;
  }

  static Map<String, dynamic> _copia(Map<String, dynamic> c) => {
    ...c,
    'sorgenti': List<String>.of(c['sorgenti'] as List<String>),
  };

  Future<void> _assicurati(bool forza) {
    final attivo = _caricamento;
    if (attivo != null) return attivo;
    final task = _carica(forza);
    _caricamento = task;
    return task.whenComplete(() {
      _caricamento = null;
    });
  }

  Future<void> _carica(bool forza) async {
    if (!_lettoDisco) {
      _lettoDisco = true;
      await _leggiCache();
    }
    if (_chiuso) return;
    final ora = _adesso();
    if (!forza &&
        _aggiornato != null &&
        ora.difference(_aggiornato!) < validita) {
      return;
    }
    if (!forza && _riprova != null && ora.isBefore(_riprova!)) return;
    try {
      final risposta = await (_scaricaProva?.call(_etag) ?? _scarica());
      if (_chiuso) return;
      if (risposta.stato == 304 && _canali.isNotEmpty) {
        _aggiornato = ora;
      } else if (risposta.stato == 200) {
        final parsed = leggiM3u(risposta.corpo);
        if (parsed.isEmpty) throw const FormatException('Catalogo vuoto');
        _canali = parsed;
        _corpo = risposta.corpo;
        _aggiornato = ora;
        _etag = etagValido(risposta.etag) ? risposta.etag : null;
      } else {
        throw HttpException('Catalogo HTTP ${risposta.stato}');
      }
      _obsoleto = false;
      _riprova = null;
      await _scriviCache();
    } catch (_) {
      // Un aggiornamento fallito conserva la copia precedente e lo dichiara.
      _obsoleto = _canali.isNotEmpty;
      _riprova = ora.add(const Duration(minutes: 5));
    }
  }

  static bool etagValido(String? value) =>
      value != null &&
      value.length <= 512 &&
      !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value);

  Future<TvRisposta> _scarica() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    _http = client;
    try {
      return await (() async {
        final request = await client.getUrl(Uri.parse(fonte));
        request.followRedirects = false;
        request.headers.set(HttpHeaders.userAgentHeader, 'LiquidDE Media');
        if (_etag != null) {
          request.headers.set(HttpHeaders.ifNoneMatchHeader, _etag!);
        }
        final response = await request.close();
        if (response.statusCode == 304) return const TvRisposta(304, '');
        if (response.statusCode != 200 ||
            response.contentLength > massimoByte) {
          throw const HttpException('Risposta catalogo non valida');
        }
        final bytes = <int>[];
        await for (final block in response) {
          if (bytes.length + block.length > massimoByte) {
            throw const FormatException('Catalogo troppo grande');
          }
          bytes.addAll(block);
        }
        return TvRisposta(
          200,
          utf8.decode(bytes),
          etag: response.headers.value(HttpHeaders.etagHeader),
        );
      })().timeout(const Duration(seconds: 25));
    } finally {
      client.close(force: true);
      if (identical(_http, client)) _http = null;
    }
  }

  Future<void> _leggiCache() async {
    if (cartellaCache == null) return;
    try {
      final file = File('$cartellaCache/free-tv-v1.json');
      if (await file.length() > massimoByte * 2) {
        return;
      }
      final data = jsonDecode(await file.readAsString());
      if (data is! Map ||
          data['versione'] != 1 ||
          data['fonte'] != fonte ||
          data['corpo'] is! String ||
          data['quando'] is! String) {
        return;
      }
      final quando = DateTime.tryParse(data['quando'] as String);
      if (quando == null ||
          quando.isAfter(_adesso().add(const Duration(minutes: 5))) ||
          _adesso().difference(quando) > const Duration(days: 30)) {
        return;
      }
      final parsed = leggiM3u(data['corpo'] as String);
      if (parsed.isEmpty) return;
      _canali = parsed;
      _aggiornato = quando;
      _corpo = data['corpo'] as String;
      if (data['etag'] is String && etagValido(data['etag'] as String)) {
        _etag = data['etag'] as String;
      }
    } on FileSystemException {
      return;
    } on FormatException {
      return;
    }
  }

  String _corpo = '';
  Future<void> _scriviCache() async {
    if (cartellaCache == null || _chiuso || _corpo.isEmpty) return;
    Directory? staging;
    try {
      await Directory(cartellaCache!).create(recursive: true);
      staging = await Directory(cartellaCache!).createTemp('.free-tv-');
      final file = File('${staging.path}/cache.json');
      await file.writeAsString(
        jsonEncode({
          'versione': 1,
          'fonte': fonte,
          'quando': _aggiornato!.toUtc().toIso8601String(),
          'etag': _etag,
          'corpo': _corpo,
        }),
        flush: true,
      );
      await file.rename('$cartellaCache/free-tv-v1.json');
    } on FileSystemException {
      /* La cache non è necessaria per vedere il catalogo. */
    } finally {
      if (staging != null) await staging.delete().catchError((_) => staging!);
    }
  }

  Future<void> chiudi() async {
    _chiuso = true;
    _http?.close(force: true);
    await _caricamento;
  }

  static bool urlValido(String value) {
    if (value.length > 8192 || RegExp(r'[\s\x00-\x1f\x7f|]').hasMatch(value)) {
      return false;
    }
    final uri = Uri.tryParse(value);
    return uri != null &&
        const {'http', 'https'}.contains(uri.scheme) &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  /// Parser limitato: ignora EXTHTTP, EXTVLCOPT, logo ed EPG; conserva le alternative.
  static List<Map<String, dynamic>> leggiM3u(String raw) {
    if (utf8.encode(raw).length > massimoByte) {
      throw const FormatException('Catalogo troppo grande');
    }
    final lines = const LineSplitter().convert(raw.replaceFirst('\ufeff', ''));
    if (lines.isEmpty || !lines.first.trim().startsWith('#EXTM3U')) {
      throw const FormatException('Catalogo M3U non valido');
    }
    final channels = <String, Map<String, dynamic>>{};
    Map<String, String>? attrs;
    var name = '';
    final attribute = RegExp(r'''([\w-]+)="([^"]*)"''');
    for (final sourceLine in lines.skip(1)) {
      final line = sourceLine.trim();
      if (line.length > 16384) {
        attrs = null;
        continue;
      }
      if (line.startsWith('#EXTINF:')) {
        attrs = {for (final m in attribute.allMatches(line)) m[1]!: m[2]!};
        // The delimiter comma can occur inside a quoted attribute.
        var quoted = false;
        var comma = -1;
        for (var i = 0; i < line.length; i++) {
          if (line[i] == '"') quoted = !quoted;
          if (line[i] == ',' && !quoted) {
            comma = i;
            break;
          }
        }
        name = (comma < 0 ? '' : line.substring(comma + 1))
            .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
            .trim();
      } else if (line.isNotEmpty && !line.startsWith('#')) {
        final a = attrs;
        attrs = null;
        if (a == null || name.isEmpty || name.length > 512 || !urlValido(line)) {
          continue;
        }
        final country = (a['tvg-country'] ?? '').toUpperCase();
        final code = RegExp(r'^[A-Z]{2,3}$').hasMatch(country) ? country : 'ZZ';
        final group = a['group-title'] ?? code;
        final baseId = a['tvg-id'];
        final key = '$code|${baseId == null || baseId.isEmpty ? name : baseId}';
        final channel = channels.putIfAbsent(
          key,
          () => {
            'id': 'tv-${Sha256.esa(utf8.encode(key)).substring(0, 24)}',
            'nome': name,
            'paese': code,
            'nazione': group.length <= 128 ? group : code,
            'url': line,
            'sorgenti': <String>[],
          },
        );
        final streams = channel['sorgenti'] as List<String>;
        if (streams.length < 8 && !streams.contains(line)) streams.add(line);
        if (channels.length > 10000) {
          throw const FormatException('Troppi canali');
        }
      }
    }
    return channels.values.toList()
      ..sort((a, b) => (a['nome'] as String).compareTo(b['nome'] as String));
  }
}

class TvRisposta {
  const TvRisposta(this.stato, this.corpo, {this.etag});
  final int stato;
  final String corpo;
  final String? etag;
}
