import 'dart:io';

/// Diagnosi in sola lettura. Non avvia pkexec o comandi amministrativi.
class RequisitiAmministrazione {
  static const percorso = '/usr/local/bin/liquid-de-radice';
  final String aiutante;
  final List<String> binari;
  const RequisitiAmministrazione({
    this.aiutante = percorso,
    this.binari = const ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],
  });

  Future<Map<String, dynamic>> verificaAiutante() async {
    Map<String, dynamic> esito(String stato, String messaggio, {int? abi}) => {
      'stato': stato,
      'compatibile': stato == 'pronto',
      'abiRichiesta': 2,
      'abiRilevata': abi,
      'messaggio': messaggio,
    };
    try {
      final f = File(aiutante);
      if (!await f.exists()) {
        return esito(
          'assente',
          'Installa i componenti amministrativi di Minerva per gestire i kernel.',
        );
      }
      final stat = await f.stat();
      if (stat.type != FileSystemEntityType.file ||
          stat.size > 2 * 1024 * 1024) {
        return esito(
          'non-verificabile',
          'Non riesco a verificare l’aiutante amministrativo. Reinstalla i componenti amministrativi di Minerva.',
        );
      }
      if (stat.mode & 0x49 == 0) {
        return esito(
          'non-eseguibile',
          'L’aiutante amministrativo non è eseguibile. Reinstalla i componenti amministrativi di Minerva.',
        );
      }
      final testo = await f.readAsString();
      final marcatori = RegExp(
        r'^# FUCINA_TRANSACTION_ABI=([0-9]+)$',
        multiLine: true,
      ).allMatches(testo).toList();
      final revisione = marcatori.length == 1
          ? int.tryParse(marcatori.single.group(1) ?? '')
          : null;
      // La versione deve essere quella supportata, non semplicemente maggiore.
      if (revisione != 2 || !testo.contains('\n# FUCINA_TRANSACTION_ABI=2\n')) {
        return esito(
          'da-aggiornare',
          'Aggiorna l’aiutante amministrativo di Minerva prima di installare o rimuovere kernel: la versione installata non è compatibile con le protezioni di recupero richieste da questa app.',
          abi: revisione,
        );
      }
      return esito(
        'pronto',
        'Aiutante amministrativo compatibile. L’autorizzazione sarà richiesta solo al momento dell’operazione.',
        abi: revisione,
      );
    } catch (_) {
      return esito(
        'non-verificabile',
        'Non riesco a verificare la versione dell’aiutante amministrativo.',
      );
    }
  }

  Future<bool> _programma(String nome) async {
    for (final base in binari) {
      try {
        final s = await File('$base/$nome').stat();
        if (s.type == FileSystemEntityType.file && s.mode & 0x49 != 0) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  Future<Map<String, dynamic>> leggi() async {
    final helper = await verificaAiutante();
    final controlli = <Map<String, dynamic>>[
      {
        'id': 'aiutante',
        'titolo': 'Componenti amministrativi',
        'ok': helper['compatibile'],
        'messaggio': helper['messaggio'],
        'necessarioPer': ['installazione', 'rimozione'],
      },
    ];
    for (final nome in ['pkexec', 'flock', 'depmod']) {
      final presente = await _programma(nome);
      controlli.add({
        'id': nome,
        'titolo': nome,
        'ok': presente,
        'messaggio': presente
            ? '$nome disponibile.'
            : 'Manca $nome nei percorsi di sistema. Installa il relativo pacchetto della distribuzione.',
        'necessarioPer': nome == 'depmod'
            ? ['installazione']
            : ['installazione', 'rimozione'],
      });
    }
    final mk = await _programma('mkinitcpio');
    final dracut = await _programma('dracut');
    controlli.add({
      'id': 'initramfs',
      'titolo': 'Generatore initramfs',
      'ok': mk || dracut,
      'messaggio': mk
          ? 'mkinitcpio disponibile.'
          : dracut
          ? 'dracut disponibile.'
          : 'Mancano mkinitcpio e dracut. Configura il generatore initramfs previsto dalla distribuzione.',
      'necessarioPer': ['installazione'],
    });
    bool possibile(String azione) => controlli.every(
      (c) => !(c['necessarioPer'] as List).contains(azione) || c['ok'] == true,
    );
    return {
      'aiutante': helper,
      'controlli': controlli,
      'installazionePossibile': possibile('installazione'),
      'rimozionePossibile': possibile('rimozione'),
      'spiega':
          'Controllo preventivo in sola lettura. Non verifica spazio libero, configurazione initramfs, firmware o avviabilità sull’hardware; l’aiutante ricontrollerà l’operazione dopo l’autorizzazione.',
    };
  }
}
