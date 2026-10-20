/// Annullamento cooperativo locale all’isolate: non interrompe scritture iniziate.
class CancellationToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() { _cancelled = true; }
  void throwIfCancelled() {
    if (_cancelled) throw const OperationCancelled();
  }
}

class OperationCancelled implements Exception {
  const OperationCancelled();
  @override
  String toString() => 'Operazione annullata';
}
