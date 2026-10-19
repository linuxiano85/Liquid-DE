import '../rpc/rpc_errors.dart';
import '../rpc/rpc_server.dart';
import 'ad_features.dart';
import 'ad_filter.dart';
import 'filter_store.dart';

/// Metodi JSON-RPC del filtro delle pubblicità.
///
/// `filter.classify` è anche il punto d'aggancio per un'IA esterna (quella
/// di sistema di Liquid DE, quando ci sarà): chiede il parere del filtro su
/// un'email salvata o su un testo qualsiasi, con punteggio e motivi.
void registerFilterMethods(RpcServer rpc, AdFilter filter) {
  final store = filter.store;

  rpc.register('filter.status', (_, __) {
    final today = DateTime.now();
    final summary = store.summarySince(DateTime(today.year, today.month, today.day));
    return {
      'mode': store.mode.name,
      'trained': filter.trained,
      'trainedAds': store.totalAds,
      'trainedNotAds': store.totalHams,
      'minTrainedPerClass': filter.minTrainedPerClass,
      'today': {'marked': summary.marked, 'moved': summary.moved},
    };
  });

  rpc.register('filter.setMode', (p, _) {
    final mode = FilterMode.values.asNameMap()[p['mode']];
    if (mode == null) {
      throw RpcException(RpcErrorCode.invalidParams, 'mode deve essere "off", "mark" o "move"');
    }
    store.mode = mode;
    return {'ok': true};
  });

  rpc.register('filter.train', (p, _) {
    final id = p['messageId'];
    final isAd = p['isAd'];
    if (id is! int) throw RpcException(RpcErrorCode.invalidParams, 'messageId deve essere un intero');
    if (isAd is! bool) throw RpcException(RpcErrorCode.invalidParams, 'isAd deve essere vero o falso');
    final stored = store.storedMessage(id);
    if (stored == null) throw RpcException(RpcErrorCode.invalidParams, 'Messaggio inesistente');
    // Le parole viste al momento del giudizio (intestazioni comprese); per
    // un'email mai giudicata, quelle ricostruibili dal database.
    final tokens = store.tokensOf(id) ??
        MessageFeatures(
          subject: stored.subject,
          fromAddress: stored.fromAddress,
          bodyText: stored.bodyText,
        ).tokens();
    filter.learn(stored.key, tokens, isAd: isAd);
    // L'etichetta "Pubblicità?" nella lista segue il giudizio dell'utente.
    store.database.db.execute('UPDATE messages SET ad_marked = ? WHERE id = ?', [isAd ? 1 : 0, id]);
    return {'ok': true, 'trained': filter.trained};
  });

  rpc.register('filter.classify', (p, _) {
    final id = p['messageId'];
    final MessageFeatures features;
    if (id != null) {
      if (id is! int) throw RpcException(RpcErrorCode.invalidParams, 'messageId deve essere un intero');
      final stored = store.storedMessage(id);
      if (stored == null) throw RpcException(RpcErrorCode.invalidParams, 'Messaggio inesistente');
      features = MessageFeatures(
          subject: stored.subject, fromAddress: stored.fromAddress, bodyText: stored.bodyText);
    } else {
      String? optional(String key) {
        final v = p[key];
        if (v != null && v is! String) {
          throw RpcException(RpcErrorCode.invalidParams, '$key deve essere una stringa');
        }
        return v as String?;
      }

      final headers = p['headers'];
      if (headers != null &&
          (headers is! Map<String, Object?> || headers.values.any((v) => v is! String))) {
        throw RpcException(RpcErrorCode.invalidParams, 'headers deve essere un oggetto di stringhe');
      }
      features = MessageFeatures(
        subject: optional('subject') ?? '',
        fromAddress: optional('fromAddress'),
        bodyText: optional('bodyText') ?? '',
        headers: headers == null ? const {} : (headers as Map<String, Object?>).cast<String, String>(),
      );
    }
    return filter.judge(features).toJson();
  });
}
