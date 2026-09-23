import 'dart:io';

/// Con quale indirizzo questo computer si fa vedere da un apparecchio.
///
/// ── Perché sta in un file suo ─────────────────────────────────────────────
///
/// Perché adesso serve a due servizi — quello che presta **un file**
/// (`ServizioEffimero`) e quello che presta **un flusso**
/// (`ServizioFlusso`) — e la seconda copia di questa funzione sarebbe stata
/// la prima a divergere dalla prima. La regola che protegge non è il conto:
/// è la frase qui sotto, e va detta in un posto solo.
///
/// **Non `0.0.0.0`.** Legarsi a tutte le schede vorrebbe dire pubblicare il
/// proprio schermo, o le proprie fotografie, su OGNI rete a cui il portatile
/// è attaccato in quel momento — quella dell'ufficio, un telefono in
/// tethering, una VPN. Si sceglie la scheda che sta nella stessa rete
/// dell'apparecchio, e su quella sola.
class ReteLocale {
  /// L'indirizzo locale che sta più vicino a [versoIl], confrontando gli
  /// indirizzi byte per byte.
  ///
  /// Il primo tentativo, il 30 agosto 2026, era più furbo e sbagliato: apriva
  /// un socket verso l'apparecchio e leggeva `Socket.address`, credendo fosse
  /// l'indirizzo locale. In Dart quello è il **remoto** — quindi il servizio
  /// provava a legarsi all'indirizzo del televisore e falliva con «Cannot
  /// assign requested address». Un errore che si legge come un problema di
  /// rete, e invece era una riga di documentazione letta male.
  static Future<InternetAddress> indirizzoVerso(String versoIl) async {
    final bersaglio = _byteDi(versoIl);
    InternetAddress? migliore;
    var quantoSomiglia = -1;

    for (final i in await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLoopback: false)) {
      for (final a in i.addresses) {
        if (a.isLoopback) continue;
        final quanto = _quantiByteInComune(_byteDi(a.address), bersaglio);
        if (quanto > quantoSomiglia) {
          quantoSomiglia = quanto;
          migliore = a;
        }
      }
    }
    // Nessuna scheda nella stessa rete: meglio non farsi raggiungere da
    // nessuno che farsi raggiungere da tutti.
    return migliore ?? InternetAddress.loopbackIPv4;
  }

  static List<int> _byteDi(String ip) =>
      ip.split('.').map((p) => int.tryParse(p) ?? -1).toList();

  static int _quantiByteInComune(List<int> a, List<int> b) {
    var n = 0;
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) break;
      n++;
    }
    return n;
  }
}
