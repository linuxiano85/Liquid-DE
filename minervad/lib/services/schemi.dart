/// Quali temi di Minerva sono CHIARI.
///
/// ── Perché il demone deve saperlo ──────────────────────────────────────────
///
/// Non per disegnare: i colori li sceglie `minerva-shell/theme/Colors.qml`, e
/// resta l'unico posto in cui si sceglie un colore. Il demone ha bisogno di
/// una cosa sola, ed è un bit: **su che fondo staranno le icone**.
///
/// I temi di icone sono installati in due varianti, e la desinenza dice per
/// quale sfondo sono fatte: «Colloid-Dark» ha icone CHIARE, da mettere su un
/// fondo scuro. Scegliendo la variante sbagliata le icone monocromatiche
/// spariscono — è già successo, con l'ingranaggio di «Animazioni» grigio scuro
/// su fondo scuro (vedi `icon_resolver.dart`).
///
/// ── Perché è una lista e non un calcolo ────────────────────────────────────
///
/// Il demone non legge QML e non sa cosa sia `#EDF0F7`. Duplicare un bit per
/// tema è il prezzo di avere due linguaggi; quello che NON si può accettare è
/// che le due copie divergano in silenzio, e infatti non possono:
/// `test/schemi_test.dart` legge `Colors.qml` e pretende che i due elenchi
/// dicano la stessa cosa.
class Schemi {
  /// I nomi dei temi chiari, come stanno in `Colors.qml`.
  static const Set<String> chiari = {'giorno', 'rosa', 'verde'};

  /// Il tema predefinito, quando non ne è stato scelto nessuno.
  static const String predefinito = 'notte';

  /// Il settimo tema, quello scelto a mano. Vedi `theme/Colors.qml`.
  static const String personale = 'personale';

  /// Vero se il tema in uso ha il fondo scuro.
  ///
  /// ── Il tema personale non sta nell'elenco, e non può starci ─────────────
  ///
  /// Per i sei temi nostri il verso è un dato: «rosa» è chiaro e lo sarà
  /// sempre. Per «personale» è una SCELTA di adesso — `shell.versoPersonale` —
  /// e metterlo in `chiari` vorrebbe dire indovinarla una volta per tutte.
  ///
  /// Sbagliarla non dà nessun errore: le icone monocromatiche del tema di
  /// sistema verrebbero prese nella variante fatta per l'altro fondo, cioè
  /// grigio scuro su scuro. Ci sono e non si vedono, che è il difetto più
  /// difficile da riconoscere di tutti — già capitato con l'ingranaggio di
  /// «Animazioni» il 29 luglio 2026.
  ///
  /// Per questo `personaleScuro` non ha un valore di ripiego comodo: chi
  /// chiama deve andarselo a prendere dalle impostazioni, e se se ne dimentica
  /// il tema personale chiaro prende le icone sbagliate — ma il compilatore
  /// glielo ricorda, perché è un argomento con nome e senza scusa.
  static bool eScuro(String scheme, {bool personaleScuro = true}) {
    final s = scheme.trim().isEmpty ? predefinito : scheme.trim();
    if (s == personale) return personaleScuro;
    return !chiari.contains(s);
  }
}
