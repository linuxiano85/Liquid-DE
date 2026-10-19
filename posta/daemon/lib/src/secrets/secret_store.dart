/// Il servizio dei segreti non è raggiungibile (nessun bus di sessione,
/// nessun gnome-keyring/KeePassXC/KWallet attivo).
class SecretStoreUnavailableException implements Exception {
  SecretStoreUnavailableException(this.message);
  final String message;
  @override
  String toString() => 'Portachiavi non disponibile: $message';
}

/// Il portachiavi è bloccato e l'utente non l'ha sbloccato (prompt
/// annullato o impossibile da mostrare). Diverso da "segreto mancante":
/// la password esiste, non va chiesta di nuovo.
class SecretStoreLockedException implements Exception {
  SecretStoreLockedException(this.message);
  final String message;
  @override
  String toString() => 'Portachiavi bloccato: $message';
}

/// Dove il daemon conserva le password. Il database salva solo il
/// riferimento ([ref]), mai il segreto.
abstract interface class SecretStore {
  /// Salva o sostituisce il segreto associato a [ref].
  Future<void> store(String ref, String secret, {required String label});

  /// Il segreto, o null se non esiste. Lancia [SecretStoreLockedException]
  /// o [SecretStoreUnavailableException] negli altri casi.
  Future<String?> lookup(String ref);

  /// Cancella il segreto; non fa nulla se non esiste.
  Future<void> delete(String ref);

  Future<void> close();
}

final _refPattern = RegExp(r'^[A-Za-z0-9._:-]{1,128}$');

void validateSecretArgs(String ref, [String? secret]) {
  if (!_refPattern.hasMatch(ref)) {
    throw ArgumentError.value(ref, 'ref', 'riferimento non valido');
  }
  if (secret != null && secret.isEmpty) {
    throw ArgumentError.value('', 'secret', 'una password vuota non viene salvata');
  }
}

/// Implementazione in memoria per i test del resto del daemon.
class InMemorySecretStore implements SecretStore {
  final Map<String, String> _secrets = {};
  bool unavailable = false;
  bool locked = false;

  Map<String, String> get contents => Map.unmodifiable(_secrets);

  void _check() {
    if (unavailable) throw SecretStoreUnavailableException('simulato');
    if (locked) throw SecretStoreLockedException('simulato');
  }

  @override
  Future<void> store(String ref, String secret, {required String label}) async {
    validateSecretArgs(ref, secret);
    _check();
    _secrets[ref] = secret;
  }

  @override
  Future<String?> lookup(String ref) async {
    validateSecretArgs(ref);
    _check();
    return _secrets[ref];
  }

  @override
  Future<void> delete(String ref) async {
    validateSecretArgs(ref);
    _check();
    _secrets.remove(ref);
  }

  @override
  Future<void> close() async {}
}
