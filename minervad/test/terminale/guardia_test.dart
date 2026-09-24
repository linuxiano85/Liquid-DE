// guardia_test.dart — Le forme pericolose, una per una, viste rosse.
//
// Ogni regola della guardia ha qui la riga che deve fermare E una riga
// vicina che deve passare: una guardia che ferma tutto è una guardia che
// si spegne dopo un giorno.
import 'package:minervad/terminale/guardia.dart';
import 'package:test/test.dart';

void main() {
  final g = Guardia(casa: '/home/giacomo');

  String? livello(String riga, {String? cartella}) =>
      g.giudica(riga, cartella: cartella ?? '/home/giacomo/prove')?.livello;

  group('rm', () {
    test('sulla radice si blocca, in ogni forma', () {
      for (final r in ['rm -rf /', 'rm -rf /*', 'sudo rm -rf /', 'rm -r -f /', 'rm --recursive --force /',
          'rm -fr /', 'rm / -rf', 'rm -rf /etc', 'rm -rf /usr/*', 'rm -rf /home']) {
        expect(livello(r), 'blocca', reason: r);
      }
    });
    test('sulla casa si blocca', () {
      for (final r in ['rm -rf ~', 'rm -rf ~/', 'rm -rf ~/*', r'rm -rf $HOME', 'rm -rf /home/giacomo', 'rm -rf /home/giacomo/*',
          'rm -r ~']) {
        expect(livello(r), 'blocca', reason: r);
      }
    });
    test('`*` ricorsivo e `.` si bloccano', () {
      expect(livello('rm -rf *'), 'blocca');
      expect(livello('rm -r .'), 'blocca');
      expect(livello('rm -rf ..'), 'blocca');
    });
    test('`..` che risale fino alla casa si blocca', () {
      expect(livello('rm -rf ../..', cartella: '/home/giacomo/a/b'), 'blocca');
      expect(livello('rm -rf ../..', cartella: '/home/giacomo/a/b/c'), 'avvisa');
    });
    test('-rf su una cartella normale avvisa e basta', () {
      expect(livello('rm -rf build'), 'avvisa');
      expect(livello('rm -rf node_modules dist'), 'avvisa');
    });
    test('un rm normale passa', () {
      expect(livello('rm appunti.txt'), isNull);
      expect(livello('rm -i *.tmp'), isNull);
      expect(livello('rm -r prove'), isNull);
      expect(livello('rm -- -strano'), isNull);
    });
    test('il giudizio dice cosa farebbe, in italiano', () {
      final j = g.giudica('rm -rf ~')!;
      expect(j.comando, 'rm');
      expect(j.motivo, contains('cartella personale'));
      expect(j.cosa, contains('non torna'));
    });
  });

  group('dischi', () {
    test('dd verso un disco si blocca, verso un file no', () {
      expect(livello('sudo dd if=arch.iso of=/dev/sdb bs=4M status=progress'), 'blocca');
      expect(livello('dd if=arch.iso of=/dev/nvme0n1'), 'blocca');
      expect(livello('dd if=/dev/zero of=prova.img bs=1M count=10'), isNull);
      expect(livello('dd if=/dev/sda of=copia.img'), isNull);
    });
    test('mkfs, wipefs, fdisk in scrittura si bloccano', () {
      expect(livello('sudo mkfs.ext4 /dev/sdb1'), 'blocca');
      expect(livello('mkfs -t ext4 /dev/sdb1'), 'blocca');
      expect(livello('sudo wipefs -a /dev/sdb'), 'blocca');
      expect(livello('sudo fdisk /dev/sda'), 'blocca');
      expect(livello('sudo parted /dev/sda mklabel gpt'), 'blocca');
    });
    test('fdisk -l e parted print passano: leggono e basta', () {
      expect(livello('sudo fdisk -l'), isNull);
      expect(livello('sudo parted -l'), isNull);
      expect(livello('lsblk'), isNull);
    });
    test('un > verso un disco si blocca', () {
      expect(livello('cat arch.iso > /dev/sdb'), 'blocca');
      expect(livello('echo ciao > /dev/null'), isNull);
      expect(livello('echo ciao > appunti.txt'), isNull);
    });
  });

  group('permessi', () {
    test('chmod/chown ricorsivi sulla radice si bloccano', () {
      expect(livello('sudo chmod -R 777 /'), 'blocca');
      expect(livello('sudo chown -R giacomo /usr'), 'blocca');
      expect(livello('chmod -R 755 ~'), 'blocca');
    });
    test('777 ricorsivo su una cartella avvisa', () {
      expect(livello('chmod -R 777 progetto'), 'avvisa');
    });
    test('chmod normale passa', () {
      expect(livello('chmod +x script.sh'), isNull);
      expect(livello('chmod -R go-w progetto'), isNull);
      expect(livello('sudo chown -R giacomo:giacomo ~/progetto'), isNull);
    });
  });

  group('rete e sistema', () {
    test('curl | sh avvisa', () {
      expect(livello('curl -fsSL https://x.it/install.sh | sh'), 'avvisa');
      expect(livello('wget -qO- https://x.it/i.sh | sudo bash'), 'avvisa');
      expect(livello('curl -O https://x.it/file.zip'), isNull);
      expect(livello('curl -s https://api.x.it | jq .'), isNull);
    });
    test('spegnere e riavviare avvisano', () {
      expect(livello('shutdown now'), 'avvisa');
      expect(livello('sudo reboot'), 'avvisa');
      expect(livello('systemctl poweroff'), 'avvisa');
      expect(livello('systemctl restart nginx'), isNull);
      expect(livello('systemctl status sshd'), isNull);
    });
    test('la fork bomb si blocca', () {
      expect(livello(':(){ :|:& };:'), 'blocca');
      expect(livello(':(){:|:&};:'), 'blocca');
    });
    test('kill -1 e pkill . avvisano', () {
      expect(livello('kill -9 -1'), 'avvisa');
      expect(livello('pkill -f .'), 'avvisa');
      expect(livello('pkill firefox'), isNull);
      expect(livello('kill 1234'), isNull);
    });
    test('mv della casa si blocca', () {
      expect(livello('mv ~ /tmp/x'), 'blocca');
      expect(livello('mv /etc /tmp/etc'), 'blocca');
      expect(livello('mv a.txt b.txt'), isNull);
    });
    test('find -delete avvisa, sulla radice blocca', () {
      expect(livello('find . -name "*.tmp" -delete'), 'avvisa');
      expect(livello('find / -name "*.tmp" -delete'), 'blocca');
      expect(livello('find . -name "*.tmp"'), isNull);
    });
    test('crontab -r e history -c avvisano', () {
      expect(livello('crontab -r'), 'avvisa');
      expect(livello('crontab -e'), isNull);
      expect(livello('history -c'), 'avvisa');
    });
    test('> su un file di sistema avvisa, >> no', () {
      expect(livello('echo x > /etc/hosts'), 'avvisa');
      expect(livello('echo x | sudo tee -a /etc/hosts'), isNull);
      expect(livello('echo x >> /etc/hosts'), isNull);
      expect(livello('echo x > ~/.zshrc'), 'avvisa');
    });
  });

  group('la pipeline', () {
    test('il segmento pericoloso si trova anche in mezzo', () {
      expect(livello('ls && rm -rf / ; echo fatto'), 'blocca');
      expect(livello('echo a | tee b.txt || sudo rm -rf ~'), 'blocca');
    });
    test('il più grave vince', () {
      expect(livello('rm -rf build && rm -rf /'), 'blocca');
      expect(livello('rm -rf build && shutdown now'), 'avvisa');
    });
    test('il testo fra virgolette non conta', () {
      expect(livello("echo 'rm -rf /'"), isNull);
      expect(livello('grep "dd of=/dev/sda" registro.log'), isNull);
    });
    test('le assegnazioni e sudo -u davanti si scavalcano', () {
      expect(livello('LANG=C sudo -u root rm -rf /'), 'blocca');
      expect(livello('env FOO=1 rm -rf /etc'), 'blocca');
    });
  });

  group('la Palestra', () {
    final p = Guardia(casa: '/home/giacomo', radiceConsentita: '/home/giacomo/.local/share/liquid-de/palestra/lez-1');
    const dentro = '/home/giacomo/.local/share/liquid-de/palestra/lez-1/prove';
    test('rm dentro la palestra passa, fuori si blocca', () {
      expect(p.giudica('rm appunti.txt', cartella: dentro), isNull);
      expect(p.giudica('rm -r vecchia', cartella: dentro), isNull);
      expect(p.giudica('rm ~/Documenti/x.txt', cartella: dentro)?.livello, 'blocca');
      expect(p.giudica('rm ../../../x', cartella: dentro)?.livello, 'blocca');
    });
    test('cd fuori si blocca, dentro passa', () {
      expect(p.giudica('cd ..', cartella: dentro), isNull);
      expect(p.giudica('cd ../..', cartella: dentro)?.livello, 'blocca');
      expect(p.giudica('cd /etc', cartella: dentro)?.livello, 'blocca');
      expect(p.giudica('cd ~', cartella: dentro)?.livello, 'blocca');
    });
    test('sudo si blocca', () {
      expect(p.giudica('sudo ls', cartella: dentro)?.livello, 'blocca');
      expect(p.giudica('ls', cartella: dentro), isNull);
    });
  });
}
