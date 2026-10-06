import 'dart:io';

/// I file aperti di recente, nello stesso posto dove li tengono tutti:
/// `~/.local/share/recently-used.xbel` (la specifica «Desktop Bookmark» di
/// freedesktop, che scrivono GTK, Chrome e KDE).
///
/// ── Perché esiste ────────────────────────────────────────────────────────
///
/// Due mancanze dello stesso giro (6 ottobre 2026). Il gestore file non
/// aveva «Recenti»: per ritrovare il PDF aperto un'ora fa bisognava
/// ricordarsi dove stava. E i file aperti DA Minerva non finivano nell'elenco,
/// quindi nemmeno i «Recenti» degli altri programmi li vedevano.
///
/// ── Scrivere senza rompere quello degli altri ────────────────────────────
///
/// Il file è di tutti: GTK lo riscrive intero ogni volta. Qui si tocca il
/// minimo — si aggiorna la data di una voce che c'è, o se ne aggiunge una
/// prima di `</xbel>` — e si scrive accanto e poi si rinomina, così chi lo
/// legge in quel momento trova il vecchio o il nuovo, mai metà.
class RecentiService {
  RecentiService({String? percorso})
      : _file = File(percorso ??
            '${Platform.environment['XDG_DATA_HOME'] ?? '${Platform.environment['HOME']}/.local/share'}'
                '/recently-used.xbel');

  final File _file;

  /// Quanti se ne mostrano: oltre, è un archivio e non «di recente».
  static const massimo = 200;

  /// Le voci per il gestore file, dalla più recente; solo file locali che
  /// esistono ancora.
  Future<List<Map<String, dynamic>>> leggi() async {
    String testo;
    try {
      testo = await _file.readAsString();
    } catch (_) {
      return [];
    }
    final voci = <({String percorso, String quando})>[];
    final segnalibro = RegExp(r'<bookmark\b([^>]*)>');
    for (final m in segnalibro.allMatches(testo)) {
      final attributi = m.group(1)!;
      final href = _attributo(attributi, 'href');
      if (href == null || !href.startsWith('file://')) continue;
      String percorso;
      try {
        percorso = Uri.parse(_disfaEntita(href)).toFilePath();
      } catch (_) {
        continue;
      }
      final quando = _attributo(attributi, 'visited') ??
          _attributo(attributi, 'modified') ??
          _attributo(attributi, 'added') ??
          '';
      voci.add((percorso: percorso, quando: quando));
    }
    // Le date ISO 8601 si ordinano come stringhe.
    voci.sort((a, b) => b.quando.compareTo(a.quando));

    final fuori = <Map<String, dynamic>>[];
    final visti = <String>{};
    for (final v in voci) {
      if (fuori.length >= massimo) break;
      if (!visti.add(v.percorso)) continue;
      final tipo = FileSystemEntity.typeSync(v.percorso);
      if (tipo == FileSystemEntityType.notFound) continue;
      final nome = v.percorso.split('/').last;
      fuori.add({
        'name': nome,
        'path': v.percorso,
        'isDir': tipo == FileSystemEntityType.directory,
        'dove': v.percorso.substring(0, v.percorso.length - nome.length - 1),
      });
    }
    return fuori;
  }

  /// Segna `percorso` come aperto adesso, con `programma` (il nome del
  /// `.desktop`, per esempio `minerva-viewer.desktop`).
  Future<void> aggiungi(String percorso, {String mime = '', String programma = ''}) async {
    if (!percorso.startsWith('/')) return;
    final adesso = DateTime.now().toUtc().toIso8601String();
    final href = _scappa(Uri.file(percorso).toString());
    String testo;
    try {
      testo = await _file.readAsString();
    } on FileSystemException {
      testo = '<?xml version="1.0" encoding="UTF-8"?>\n'
          '<xbel version="1.0"\n'
          '      xmlns:bookmark="http://www.freedesktop.org/standards/desktop-bookmarks"\n'
          '      xmlns:mime="http://www.freedesktop.org/standards/shared-mime-info"\n'
          '>\n</xbel>\n';
    }
    final fine = testo.lastIndexOf('</xbel>');
    if (fine < 0) return; // non è un file che sappiamo leggere: non si tocca

    final gia = RegExp('<bookmark\\b[^>]*href="${RegExp.escape(href)}"[^>]*>');
    final m = gia.firstMatch(testo);
    if (m != null) {
      var apertura = m.group(0)!;
      apertura = _conAttributo(apertura, 'modified', adesso);
      apertura = _conAttributo(apertura, 'visited', adesso);
      testo = testo.replaceRange(m.start, m.end, apertura);
    } else {
      final app = programma.endsWith('.desktop')
          ? programma.substring(0, programma.length - 8)
          : programma;
      final voce = StringBuffer()
        ..write('  <bookmark href="$href" added="$adesso" modified="$adesso" visited="$adesso">\n')
        ..write('    <info>\n')
        ..write('      <metadata owner="http://freedesktop.org">\n');
      if (mime.isNotEmpty) voce.write('        <mime:mime-type type="${_scappa(mime)}"/>\n');
      if (app.isNotEmpty) {
        voce
          ..write('        <bookmark:applications>\n')
          ..write('          <bookmark:application name="${_scappa(app)}" '
              'exec="&apos;${_scappa(app)} %u&apos;" modified="$adesso" count="1"/>\n')
          ..write('        </bookmark:applications>\n');
      }
      voce
        ..write('      </metadata>\n')
        ..write('    </info>\n')
        ..write('  </bookmark>\n');
      testo = testo.replaceRange(fine, fine, voce.toString());
    }

    final provvisorio = File('${_file.path}.minerva-$pid');
    try {
      await _file.parent.create(recursive: true);
      await provvisorio.writeAsString(testo, flush: true);
      // Il file dice cosa hai aperto: solo tuo, come lo crea GTK.
      await Process.run('chmod', ['600', provvisorio.path]);
      await provvisorio.rename(_file.path);
    } catch (_) {
      try {
        await provvisorio.delete();
      } catch (_) {}
    }
  }

  static String? _attributo(String attributi, String nome) {
    final m = RegExp('\\b$nome="([^"]*)"').firstMatch(attributi);
    return m?.group(1);
  }

  static String _conAttributo(String apertura, String nome, String valore) {
    final re = RegExp('\\b$nome="[^"]*"');
    if (re.hasMatch(apertura)) return apertura.replaceFirst(re, '$nome="$valore"');
    return apertura.replaceFirst(RegExp(r'>$'), ' $nome="$valore">');
  }

  static String _scappa(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll("'", '&apos;');

  static String _disfaEntita(String s) => s
      .replaceAll('&quot;', '"')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}
