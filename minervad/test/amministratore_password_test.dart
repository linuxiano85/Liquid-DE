// La modalità amministratore chiede la password ALL'INGRESSO.
//
// ── Il difetto che queste prove tengono fermo ──────────────────────────────
//
// Giacomo, 2 settembre 2026: «non chiede una password per entrare in modalità
// amministratore».
//
// Era vero. `accendiAmministratore()` metteva `amministratore = true` e basta:
// la password la chiedeva la PRIMA operazione, tramite `pkexec`. Il difetto non
// è che mancasse una protezione — polkit c'era e faceva il suo — ma che lo
// SCHERMO diceva una cosa e il sistema ne pensava un'altra: la scritta
// «modalità amministratore» compariva subito, e nell'intervallo fra quella
// scritta e il primo `pkexec` c'era un clic che non avrebbe fatto quello che
// sembrava.
//
// E il messaggio diceva «ogni operazione chiede la password», che è falso: la
// regola polkit è `auth_admin_keep`, quindi vale per qualche minuto. Una
// promessa di sicurezza più forte del vero è peggio di nessuna promessa.
//
// Si prova leggendo il sorgente e non facendo girare la finestra, per una
// ragione precisa: il giro vero passa da `pkexec`, cioè da una finestrella
// della password che si aprirebbe sullo schermo di chi sta lavorando. Il
// rifiuto vero lo prova `scripts/prova-radice.sh`, che gira sull'aiutante
// senza root.
import 'dart:io';

import 'package:test/test.dart';

import 'package:minervad/services/radice_service.dart';

String _leggi(String rel) {
  final f = File('${Directory.current.parent.path}/$rel');
  expect(f.existsSync(), isTrue, reason: 'manca $rel');
  return f.readAsStringSync();
}

void main() {
  test('il verbo che non fa niente è nell\'elenco chiuso, e nell\'aiutante',
      () {
    expect(RadiceService.operazioni, contains('permesso'));
    final aiutante = _leggi('scripts/minerva-radice');
    expect(aiutante, contains('\n    permesso)'),
        reason: 'il demone conosce «permesso» ma l\'aiutante no: '
            'la modalità amministratore non si accenderebbe più');
    // Non fa niente e non stampa niente: quello che stampa un processo di root
    // lo legge chiunque.
    final corpo = aiutante.split('\n    permesso)')[1].split(';;')[0];
    expect(corpo, isNot(contains('rm ')));
    expect(corpo, isNot(contains('chmod')));
    expect(corpo, contains('exit 0'));
  });

  test('accendere la modalità passa dalla richiesta di permesso', () {
    final fm = _leggi('minerva-shell/files/FileManager.qml');

    final accendi = fm.split('function accendiAmministratore()')[1];
    final corpo = accendi.split('\n    }')[0];

    // La cosa che conta: la funzione che risponde al clic NON accende.
    expect(corpo, isNot(contains('amministratore = true')),
        reason: 'accendiAmministratore() accende da sé: la scritta comparirebbe '
            'prima della password, come prima del 3 settembre 2026');
    expect(corpo, contains('radiceChiediPermesso()'));

    // E si accende in un posto solo, quello che ha in mano l'esito.
    expect(RegExp(r'manager\.amministratore = true').allMatches(fm).length, 1,
        reason: 'più di un punto accende la modalità: uno dei due prima o poi '
            'lo farà senza password');
    final davvero = fm.split('function accendiDavvero()')[1].split('\n    }')[0];
    expect(davvero, contains('amministratore = true'));

    // Chi la accende deve essere raggiunto solo dall'esito positivo.
    final esito = fm.split('function onRadicePermesso(info)')[1]
        .split('\n        }')[0];
    expect(esito, contains('info.ok === true'));
    expect(esito, contains('accendiDavvero()'));
  });

  test('il messaggio non promette più di quel che polkit mantiene', () {
    final fm = _leggi('minerva-shell/files/FileManager.qml');
    expect(fm, isNot(contains('Ogni operazione chiede la ')),
        reason: 'la regola è auth_admin_keep: la password NON si ripete a ogni '
            'operazione, e dirlo è una promessa di sicurezza falsa');

    // E la regola che rende falsa quella frase è ancora quella.
    final policy = _leggi('config/polkit/org.minerva.radice.policy');
    expect(policy, contains('auth_admin_keep'),
        reason: 'se un giorno diventa auth_admin, il messaggio va riscritto: '
            'allora la password la chiederebbe davvero ogni volta');
  });

  test('due clic di fila non aprono due finestrelle', () {
    final fm = _leggi('minerva-shell/files/FileManager.qml');
    final corpo = fm.split('function accendiAmministratore()')[1]
        .split('\n    }')[0];
    expect(corpo, contains('inAttesaDiPermesso'));
  });
}
