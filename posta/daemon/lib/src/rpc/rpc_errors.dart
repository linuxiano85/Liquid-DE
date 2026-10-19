/// Codici di errore JSON-RPC 2.0 usati dal daemon.
///
/// I codici da -32700 a -32600 sono quelli standard della specifica;
/// quelli da -32001 in giù sono specifici di Liquid Mail.
abstract final class RpcErrorCode {
  static const parseError = -32700;
  static const invalidRequest = -32600;
  static const methodNotFound = -32601;
  static const invalidParams = -32602;
  static const internalError = -32603;

  /// Richiesta prima dell'autenticazione o token errato.
  static const unauthorized = -32001;

  /// Operazione fallita lato server di posta (rete, login, protocollo).
  static const mailServerError = -32002;

  /// Operazione sugli account fallita; `data.reason` dice perché.
  static const accountError = -32003;

  /// Operazione sulla posta non riuscita: il motivo è in `data.reason`.
  static const mailError = -32004;
}

/// Eccezione che un handler può lanciare per restituire un errore
/// JSON-RPC preciso al client invece di un generico internalError.
class RpcException implements Exception {
  RpcException(this.code, this.message, [this.data]);

  final int code;
  final String message;
  final Object? data;

  Map<String, Object?> toJson() => {
        'code': code,
        'message': message,
        if (data != null) 'data': data,
      };

  @override
  String toString() => 'RpcException($code, $message)';
}
