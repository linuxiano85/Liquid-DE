/// Git confronta le revisioni; le categorie distinguono i sorgenti del desktop
/// dai cambiamenti che non richiedono alcun aggiornamento della sessione.
class LiquidUpdateChanges {
  static String component(String path) {
    if (path.startsWith('compositore/')) return 'compositor';
    if (path.startsWith('minervad/')) return 'daemon';
    if (path.startsWith('minerva-shell/native/')) return 'native';
    if (path.startsWith('minerva-shell/')) return 'shell';
    if (path.startsWith('fucina2/')) return 'fucina';
    if (['assets/', 'config/', 'scripts/', 'desktop/'].any(path.startsWith)) {
      return 'integration';
    }
    // Una cartella nuova non diventa implicitamente un pacchetto installabile.
    if (['docs/', 'tests/', 'audit/', '.github/'].any(path.startsWith) ||
        ['README.md', 'LICENSE', '.gitignore'].contains(path)) {
      return 'repository';
    }
    return 'unclassified';
  }

  static bool safePath(dynamic path) =>
      path is String &&
      path.isNotEmpty &&
      !path.contains('\u0000') &&
      !path.contains('\\') &&
      !path
          .split('/')
          .any((part) => part.isEmpty || part == '.' || part == '..');

  static Map<String, dynamic> parse(Map<String, dynamic> response) {
    final status = response['status'];
    final total = response['total_commits'];
    final rawFiles = response['files'];
    final rawCommits = response['commits'];
    if (!['ahead', 'behind', 'identical', 'diverged'].contains(status) ||
        total is! int ||
        total < 0 ||
        rawFiles is! List ||
        rawCommits is! List) {
      throw const FormatException('compare');
    }
    final files = <Map<String, dynamic>>[];
    final counts = <String, int>{};
    final seen = <String>{};
    var patchBudget = 256 * 1024;
    for (final file in rawFiles) {
      if (file is! Map ||
          !safePath(file['filename']) ||
          !seen.add(file['filename']) ||
          ![
            'added',
            'removed',
            'modified',
            'renamed',
            'copied',
            'changed',
            'unchanged',
          ].contains(file['status']) ||
          file['additions'] is! int ||
          file['deletions'] is! int ||
          file['additions'] < 0 ||
          file['deletions'] < 0) {
        throw const FormatException('compare_file');
      }
      final previous = file['previous_filename'];
      if (previous != null && !safePath(previous)) {
        throw const FormatException('compare_previous');
      }
      final components = {
        component(file['filename']),
        if (previous != null) component(previous),
      };
      for (final name in components) {
        counts[name] = (counts[name] ?? 0) + 1;
      }
      final patch = file['patch'];
      final accepted = patch is String && patch.length <= patchBudget;
      if (accepted) patchBudget -= patch.length;
      files.add({
        'path': file['filename'],
        'previous': previous ?? '',
        'status': file['status'],
        'additions': file['additions'],
        'deletions': file['deletions'],
        'components': components.toList(),
        'patch': accepted ? patch : '',
        'patchAvailable': accepted,
      });
    }
    final commits = <Map<String, dynamic>>[];
    for (final commit in rawCommits) {
      if (commit is! Map ||
          commit['sha'] is! String ||
          !RegExp(r'^[0-9a-f]{40}$').hasMatch(commit['sha']) ||
          commit['commit'] is! Map ||
          commit['commit']['message'] is! String) {
        throw const FormatException('compare_commit');
      }
      commits.add({
        'revision': commit['sha'],
        'message': commit['commit']['message'],
      });
    }
    // L'API limita i file a 300. Sul limite non possiamo provare completezza.
    final complete = files.length < 300 && commits.length == total;
    return {
      'status': status,
      'complete': complete,
      'totalCommits': total,
      'commits': commits,
      'files': files,
      'components': counts,
      'runtimeChanged': counts.keys.any((name) => name != 'repository'),
    };
  }
}
