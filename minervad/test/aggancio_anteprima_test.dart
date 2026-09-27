// L'anteprima celeste dell'aggancio, e il pezzo che restava impresso.
//
// Difetto riferito da Giacomo il 12 agosto 2026: trascinando una finestra sul
// bordo destro e poi in un angolo, «rimane la parte blu sopra o sotto la
// finestra, e se rilascio rimane il blu».
//
// Allora le barre le disegnava il plugin dentro Hyprland, che doveva dichiarare
// sporco a mano il rettangolo vecchio. Nel compositore nostro l'anteprima è un
// rettangolo della scena di wlroots (`aggancio_ombra`), e la scena il vecchio
// lo ridipinge da sola quando il rettangolo si sposta o cambia misura: quella
// metà del difetto non può tornare.
//
// Resta la metà gemella, che è codice nostro: rilasciando, l'anteprima deve
// spegnersi SEMPRE, anche quando non si aggancia niente. Si prova il sorgente
// perché il difetto non è fotografabile: una cattura chiede un fotogramma
// nuovo, e i pixel rimasti spariscono nell'atto di fotografarli.
import 'dart:io';

import 'package:test/test.dart';
import 'codice_vivo.dart';

String _main() {
  for (final base in ['.', '..', '../..']) {
    final f = File('$base/compositore/src/main.c');
    if (f.existsSync()) return f.codiceVivo();
  }
  fail('non trovo compositore/src/main.c');
}

/// Il corpo di una funzione C, dalla sua firma alla prima graffa in colonna 0.
String _funzione(String sorgente, String nome) {
  final i = sorgente.indexOf('static void $nome(');
  expect(i, isNot(-1), reason: '$nome sparita da main.c');
  return sorgente.substring(i, sorgente.indexOf('\n}\n', i));
}

void main() {
  group('l\'anteprima dell\'aggancio non resta impressa', () {
    late String rilascio;
    setUpAll(() => rilascio = _funzione(_main(), 'cursore_rilasciato'));

    test('rilasciando, l\'anteprima si spegne sempre', () {
      expect(rilascio,
          contains('wlr_scene_node_set_enabled(&m->aggancio_ombra->node, false);'));
    });

    test('e si spegne PRIMA di decidere se agganciare', () {
      // Se lo spegnimento stesse dentro il ramo che aggancia, un rilascio
      // fuori da ogni zona lascerebbe il rettangolo acceso: il difetto gemello.
      final spegne = rilascio
          .indexOf('wlr_scene_node_set_enabled(&m->aggancio_ombra->node, false);');
      final decide = rilascio.indexOf('if (era_presa && f != NULL && trascinata');
      expect(decide, greaterThan(0), reason: 'il ramo dell\'aggancio è cambiato');
      expect(spegne, lessThan(decide));
    });

    test('la zona si azzera insieme all\'anteprima', () {
      // Una zona rimasta impostata riaccenderebbe l'anteprima al prossimo
      // movimento, anche senza nessuna finestra in mano.
      expect(rilascio, contains('m->aggancio_ora = ZONA_NIENTE;'));
    });
  });
}
