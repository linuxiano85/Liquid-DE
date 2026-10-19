import 'dart:math';

/// Quante volte una parola è comparsa in pubblicità ([ad]) e in email
/// normali ([ham]).
typedef TokenCounts = ({int ad, int ham});

/// Classificatore bayesiano con il metodo di Robinson e la combinazione di
/// Fisher (chi quadro): lo stesso schema di SpamBayes e del filtro della
/// posta indesiderata di Thunderbird.
///
/// Perché questo e non un semplice "conta le parole": la combinazione di
/// Fisher dà un risultato netto (vicino a 0 o a 1) solo quando le parole
/// sono d'accordo tra loro, e resta vicino a 0,5 quando si contraddicono.
/// Un "non so" è esattamente ciò che serve per non spostare nel Cestino
/// un'email personale che parla di offerte.
abstract final class Bayes {
  /// Forza dell'ipotesi iniziale (Robinson): una parola vista una volta sola
  /// conta poco, una vista cento volte conta quasi per intero.
  static const strength = 1.0;

  /// Ipotesi iniziale per una parola mai vista: né pubblicità né no.
  static const unknownProbability = 0.5;

  /// Solo le parole che si allontanano almeno così da 0,5 entrano nel calcolo.
  static const minDeviation = 0.1;

  /// Al massimo queste parole, le più decise.
  static const maxTokens = 150;

  /// Probabilità che un'email con questa parola sia pubblicità.
  static double tokenProbability(TokenCounts c, int totalAds, int totalHams) {
    final adRatio = totalAds == 0 ? 0.0 : c.ad / totalAds;
    final hamRatio = totalHams == 0 ? 0.0 : c.ham / totalHams;
    final n = c.ad + c.ham;
    final p = adRatio + hamRatio == 0 ? unknownProbability : adRatio / (adRatio + hamRatio);
    return (strength * unknownProbability + n * p) / (strength + n);
  }

  /// Probabilità (0..1) che l'email con queste parole sia pubblicità.
  static double score(Map<String, TokenCounts> counts, int totalAds, int totalHams) {
    final probs = [
      for (final c in counts.values)
        tokenProbability(c, totalAds, totalHams).clamp(0.01, 0.99),
    ].where((p) => (p - 0.5).abs() >= minDeviation).toList()
      ..sort((a, b) => (b - 0.5).abs().compareTo((a - 0.5).abs()));
    final used = probs.take(maxTokens).toList();
    if (used.isEmpty) return 0.5;
    var lnAd = 0.0;
    var lnHam = 0.0;
    for (final p in used) {
      lnAd += log(1 - p);
      lnHam += log(p);
    }
    final s = 1 - chi2Q(-2 * lnAd, 2 * used.length);
    final h = 1 - chi2Q(-2 * lnHam, 2 * used.length);
    return ((s - h + 1) / 2).clamp(0.0, 1.0);
  }

  /// Probabilità che una variabile chi quadro con [v] gradi di libertà
  /// (pari) superi [x2]. Forma chiusa per gradi pari, come in SpamBayes.
  static double chi2Q(double x2, int v) {
    assert(v.isEven && v > 0);
    final m = x2 / 2;
    var term = exp(-m);
    var sum = term;
    for (var i = 1; i < v ~/ 2; i++) {
      term *= m / i;
      sum += term;
    }
    return min(sum, 1.0);
  }
}
