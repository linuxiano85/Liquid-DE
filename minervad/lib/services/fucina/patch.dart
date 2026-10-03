/// Apply only a complete forward patch. A complete reverse dry-run proves
/// that the same changes are already present; partial/conflicting patches
/// remain errors. Neither check prompts on stdin or modifies the source tree.
Future<({bool ok, bool giaPresente})> applicaPatch({
  required String file,
  required Future<String?> Function(List<String>) esegui,
}) async {
  const common = ['patch', '--batch', '--fuzz=0', '-p1'];
  final forward = await esegui([
    ...common,
    '--forward',
    '--dry-run',
    '-i',
    file,
  ]);
  if (forward == null) {
    final applied = await esegui([...common, '--forward', '-i', file]);
    return (ok: applied == null, giaPresente: false);
  }
  final reverse = await esegui([
    ...common,
    '--reverse',
    '--force',
    '--dry-run',
    '-i',
    file,
  ]);
  return (ok: reverse == null, giaPresente: reverse == null);
}
