import 'package:test/test.dart';
import 'package:minervad/services/schermi_esterni.dart';

// Le prove della scoperta dei televisori.
//
// ── Che cosa si prova qui, e che cosa no ─────────────────────────────────
//
// Non si prova la RETE: una prova che ha bisogno di un televisore acceso è
// una prova che fallisce quando qualcuno lo spegne, e una prova che fallisce
// per ragioni sue smette di dire qualcosa. Si prova la **lettura**: le righe
// di `avahi-browse` sono un formato, e il formato si può provare con una
// stringa.
//
// Le righe qui sotto sono copiate parola per parola dall'uscita vera del
// 30 agosto 2026 sulla rete di casa — comprese le due dello stesso televisore
// in IPv4 e IPv6, che è il caso che conta.
void main() {
  group('i nomi dei televisori', () {
    test('il nome è quello che ha dato l\'utente, non quello del servizio', () {
      // `fn=TV cameretta` è il nome scelto col telecomando. Il nome del
      // servizio è `AI-PONT-cf6bacd1cbcc48531667d8890e49312c`, che non
      // significa niente per nessuno — ed era quello che si sarebbe visto nel
      // menù senza questa scelta.
      final txt = SchermiEsterni.leggiTxt(
          '"id=cf6bacd1cbcc48531667d8890e49312c" "md=AI PONT" '
          '"fn=TV cameretta" "ca=264709"');
      expect(txt['fn'], 'TV cameretta');
      expect(txt['md'], 'AI PONT');
      expect(txt['id'], 'cf6bacd1cbcc48531667d8890e49312c');
    });

    test('un campo senza «=» non diventa una chiave vuota', () {
      final txt = SchermiEsterni.leggiTxt('"rs=" "=strano" "ve=05"');
      expect(txt['rs'], '');
      expect(txt.containsKey(''), isFalse);
      expect(txt['ve'], '05');
    });

    test('gli spazi arrivano come \\032 e vanno sciolti', () {
      // `avahi-browse` scrive «TV cameretta» come «TV\\032cameretta». Senza
      // scioglierlo, il nome mostrato avrebbe dei numeri in mezzo.
      expect(SchermiEsterni.sciogliFuga(r'TV\032cameretta'), 'TV cameretta');
      expect(SchermiEsterni.sciogliFuga('Cucina'), 'Cucina');
    });
  });

  group('le righe di avahi-browse', () {
    // Le righe vere del 30 agosto 2026. Le prime due sono LO STESSO
    // televisore, annunciato in IPv6 e in IPv4.
    const uscita = '''
+;wlan0;IPv4;AI-PONT-cf6b;_googlecast._tcp;local
=;wlan0;IPv6;AI-PONT-cf6b;_googlecast._tcp;local;cf6b.local;2001:b07:647d::1;8009;"id=cf6b" "md=AI PONT" "fn=TV cameretta"
=;wlan0;IPv4;AI-PONT-cf6b;_googlecast._tcp;local;cf6b.local;192.168.1.55;8009;"id=cf6b" "md=AI PONT" "fn=TV cameretta"
''';

    test('si leggono solo le righe risolte', () {
      // Le righe che cominciano con `+` sono «ho visto qualcosa» e non portano
      // né indirizzo né porta: prenderle vorrebbe dire un televisore
      // nell'elenco a cui non si sa dove scrivere.
      final s = SchermiEsterni.leggiUscita(uscita, 'cast');
      expect(s.length, 2, reason: 'la riga «+» non doveva entrare');
    });

    test('lo stesso televisore non compare due volte', () {
      // IPv6 e IPv4 sono lo stesso apparecchio. Senza raggrupparli per `id`,
      // nel menù comparirebbe due volte con lo stesso nome, e chi lo vede
      // pensa di avere due televisori.
      final uniti = SchermiEsterni.unisci(
          SchermiEsterni.leggiUscita(uscita, 'cast'));
      expect(uniti.length, 1);
      expect(uniti.first.nome, 'TV cameretta');
    });

    test('e di quelle due si tiene l\'IPv4', () {
      // Il servizio che dovrà passare la fotografia al televisore si fa
      // raggiungere su IPv4: su una rete di casa è quello che funziona
      // sempre. Tenere l'IPv6 vorrebbe dire un indirizzo giusto e una
      // trasmissione che non parte.
      final uniti = SchermiEsterni.unisci(
          SchermiEsterni.leggiUscita(uscita, 'cast'));
      expect(uniti.first.indirizzo, '192.168.1.55');
      expect(uniti.first.porta, 8009);
    });

    test('una riga storta si salta invece di rompere tutto', () {
      // Un elenco di televisori che va in eccezione perché una riga è corta
      // vorrebbe dire nessun televisore, non uno in meno.
      final s = SchermiEsterni.leggiUscita('=;wlan0;IPv4;corta\n\n', 'cast');
      expect(s, isEmpty);
    });

    test('senza «fn» si ripiega sul nome del servizio, senza la coda esadecimale', () {
      // Non tutti i televisori dichiarano il nome amichevole. Meglio
      // «AI-PONT» che «AI-PONT-cf6bacd1cbcc48531667d8890e49312c».
      const senzaFn = '=;wlan0;IPv4;AI-PONT-cf6bacd1cbcc48531667d8890e49312c;'
          '_googlecast._tcp;local;x.local;192.168.1.55;8009;"ve=05"';
      final s = SchermiEsterni.leggiUscita(senzaFn, 'cast');
      expect(s.single.nome, 'AI-PONT');
    });
  });
}
