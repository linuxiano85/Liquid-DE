import 'ad_features.dart';
import 'bayes.dart';
import 'filter_store.dart';

/// Cosa fare di un'email giudicata.
enum FilterAction { none, mark, move }

/// Giudizio su un'email: lo restituisce anche `filter.classify`, il punto
/// in cui un'IA esterna (quella di sistema, in futuro) può leggere il
/// parere del filtro e i suoi motivi.
class Verdict {
  Verdict({
    required this.score,
    required this.action,
    required this.reasons,
    required this.learned,
    this.protectedBy,
  });

  /// 0..100: probabilità che sia pubblicità.
  final int score;
  final FilterAction action;

  /// Perché, in parole che la UI può mostrare.
  final List<String> reasons;

  /// Il punteggio viene dal modello addestrato (true) o dalle sole regole
  /// sulle intestazioni (false, finché il filtro non ha imparato abbastanza).
  final bool learned;

  /// Se valorizzato, l'email è protetta: non verrà mai spostata.
  final String? protectedBy;

  Map<String, Object?> toJson() => {
        'score': score,
        'action': action.name,
        'reasons': reasons,
        'learned': learned,
        if (protectedBy != null) 'protectedBy': protectedBy,
      };
}

/// Filtro delle pubblicità. Regole di sicurezza, nell'ordine:
///
/// 1. **Protezioni prima di tutto.** Persone a cui l'utente ha scritto o che
///    ha in rubrica, risposte a email dell'utente, oggetti "transazionali"
///    (fatture, ordini, banca, codici di verifica): mai spostate, qualunque
///    sia il punteggio. Sbagliare qui costa una bolletta persa.
/// 2. **Spostare richiede il modo `move`**, scelto dall'utente, e un modello
///    che abbia imparato almeno [minTrainedPerClass] esempi per tipo, oppure
///    il giudizio del provider (categoria Promozioni di Gmail).
/// 3. **Le sole regole sulle intestazioni non spostano mai**: arrivano al
///    massimo a [ruleScoreCap], sotto la soglia di spostamento.
/// 4. Nessuna cancellazione: "spostare" vuol dire Cestino, con Annulla.
class AdFilter {
  AdFilter(this.store, {this.markThreshold = 80, this.moveThreshold = 90, this.minTrainedPerClass = 20});

  final FilterStore store;
  final int markThreshold;
  final int moveThreshold;
  final int minTrainedPerClass;

  static const ruleScoreCap = 85;

  bool get trained =>
      store.totalAds >= minTrainedPerClass && store.totalHams >= minTrainedPerClass;

  /// Parole nell'oggetto che indicano un'email da non perdere. Volutamente
  /// larghe: un falso allarme lascia una pubblicità nella posta in arrivo,
  /// un errore nell'altro senso nasconde una scadenza.
  static final _transactional = RegExp(
      r'fattur|ricevut|scontrin|ordine|conferma|spedizion|spedit|consegn|traccia|tracking|'
      r'codice|otp|verific|password|accesso|login|sicurezza|bonific|pagament|addebit|'
      r'estratto conto|rata|scadenz|bollett|appuntament|prenotazion|bigliett|'
      r'invoice|receipt|order|shipped|shipping|delivery|payment|statement|verification|'
      r'security|sign[- ]?in|booking|reservation|appointment|ticket|refund|rimborso',
      caseSensitive: false);

  /// "Codice sconto" e simili sono pubblicità, non codici di verifica: si
  /// tolgono dall'oggetto prima di cercare le parole transazionali.
  static final _promoCode = RegExp(
      r'codic[ei] (sconto|promo\w*|coupon|regalo)|(promo|discount|coupon) codes?|buono sconto',
      caseSensitive: false);

  String? _protection(MessageFeatures f) {
    final from = f.fromAddress;
    if (from != null && store.isKnownCorrespondent(from)) {
      return 'Mittente a cui hai scritto o in rubrica';
    }
    final replyTo = f.headers['in-reply-to']?.trim();
    if (replyTo != null && replyTo.isNotEmpty && store.isOwnMessage(replyTo)) {
      return 'Risposta a una tua email';
    }
    if (_transactional.hasMatch(f.subject.replaceAll(_promoCode, ' '))) {
      return 'Sembra una comunicazione importante (ordine, pagamento, accesso…)';
    }
    return null;
  }

  Verdict judge(MessageFeatures f) {
    final reasons = <String>[];
    final tokens = f.tokens();
    var score = 0;
    final learned = trained;
    if (learned) {
      score = (Bayes.score(store.counts(tokens), store.totalAds, store.totalHams) * 100).round();
      reasons.add('Giudizio imparato dalle tue scelte: $score%');
    } else {
      // Avvio a freddo: le intestazioni delle spedizioni di massa.
      score = 30;
      if (f.hasListUnsubscribe) {
        score += 30;
        reasons.add('Ha il collegamento per disiscriversi');
      }
      if (f.isBulk) {
        score += 15;
        reasons.add('Spedita come invio di massa');
      }
      final platform = f.bulkPlatform;
      if (platform != null) {
        score += 20;
        reasons.add('Inviata con una piattaforma di newsletter ($platform)');
      }
      if (f.trackersRemoved > 0) {
        score += 10;
        reasons.add('Conteneva pixel spia');
      }
      if (score > ruleScoreCap) score = ruleScoreCap;
    }
    if (f.providerSaysPromotion) {
      if (score < 95) score = 95;
      reasons.add('Il provider la classifica tra le Promozioni');
    }

    final protectedBy = _protection(f);
    var action = FilterAction.none;
    final mode = store.mode;
    if (protectedBy == null && mode != FilterMode.off) {
      final canMove = mode == FilterMode.move && (learned || f.providerSaysPromotion);
      if (score >= moveThreshold && canMove) {
        action = FilterAction.move;
      } else if (score >= markThreshold) {
        action = FilterAction.mark;
      }
    }
    return Verdict(
      score: score,
      action: action,
      reasons: reasons,
      learned: learned,
      protectedBy: protectedBy,
    );
  }

  /// Giudica un'email appena sincronizzata, ricorda le sue parole per
  /// l'addestramento e registra l'azione decisa.
  Verdict process({
    required int accountId,
    required int messageRowId,
    required String messageKey,
    required MessageFeatures features,
  }) {
    final v = judge(features);
    store.rememberTokens(messageRowId, features.tokens(), v.score);
    if (v.action != FilterAction.none) {
      store.recordAction(
        accountId: accountId,
        messageKey: messageKey,
        subject: features.subject,
        fromAddress: features.fromAddress,
        score: v.score,
        action: v.action == FilterAction.move ? 'moved' : 'marked',
      );
    }
    return v;
  }

  /// L'utente ha detto cosa è: "è pubblicità" (spostata nel Cestino, o
  /// segnata a mano) oppure "non lo è" (ripristinata, o tolta l'etichetta).
  void learn(String messageKey, Set<String> tokens, {required bool isAd}) =>
      store.train(messageKey, tokens, isAd ? FilterLabel.ad : FilterLabel.ham);
}
