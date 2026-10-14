"""Verifica in sola lettura la diagnosi del daemon Fucina installato.

Non invia azioni di compilazione, installazione, rimozione o recupero.
Con --rilascio confronta anche l'immagine nella cache prima/dopo la richiesta.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
from prova_fucina_reale import Canale


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--canale', required=True)
    p.add_argument('--rilascio')
    p.add_argument('--output')
    args = p.parse_args()
    if args.output and Path(args.output).exists():
        p.error('Il file di output deve essere nuovo')
    if args.rilascio and not re.fullmatch(r'[1-9][0-9]?\.[0-9]{1,3}(\.[0-9]{1,4})?-fucina-[a-z0-9]([a-z0-9-]{0,22}[a-z0-9])?', args.rilascio):
        p.error('Rilascio Fucina non valido')
    c = Canale(args.canale)
    try:
        assert not c.stato().get('inCorso'), 'Attendi la conclusione della build'
        c.invia({'action': 'fucina_kernel'})
        first = c.aspetta('fucina_kernel')
        cache = Path(first['cache']['percorso'])
        image = cache / f'uscita/{args.rilascio}/boot/vmlinuz-{args.rilascio}' if args.rilascio else None
        sha = lambda: hashlib.sha256(image.read_bytes()).hexdigest() if image else None
        before = sha()
        c.invia({'action': 'fucina_kernel'})
        info = c.aspetta('fucina_kernel')
        admin = info['amministrazione']
        checks = admin['controlli']
        assert {x['id'] for x in checks} == {'aiutante', 'pkexec', 'flock', 'depmod', 'initramfs'}
        assert all(type(x['ok']) is bool for x in checks)
        for action in ('installazione', 'rimozione'):
            expected = all(x['ok'] for x in checks if action in x['necessarioPer'])
            assert admin[action+'Possibile'] is expected
        assert next(x['ok'] for x in checks if x['id']=='aiutante') is admin['aiutante']['compatibile']
        ready = [x for x in info['kernel'] if x['pronto']]
        for k in ready:
            assert k['preparazione']['ok'] is True and not k['preparazione']['blocchi']
            assert (k.get('provaAvvio') or {}).get('ok') is not False
        if args.rilascio:
            k = next(x for x in info['kernel'] if x['rilascio']==args.rilascio)
            assert k['pronto'] is True
        after = sha()
        assert before == after
        result = dict(ok=True, helperStatus=admin['aiutante']['stato'],
                      helperCompatible=admin['aiutante']['compatibile'],
                      installazionePossibile=admin['installazionePossibile'],
                      rimozionePossibile=admin['rimozionePossibile'],
                      controlli={x['id']:x['ok'] for x in checks},
                      kernelProntiVerificati=len(ready),
                      immagineConfrontata=args.rilascio, imageSha256=after,
                      immagineInvariata=bool(image) and before==after,
                      azioniInviate=['fucina_stato','fucina_kernel','fucina_kernel'],
                      kernelMutationActionsSent=False)
        if args.output:
            with Path(args.output).open('x') as output:
                json.dump(result, output, indent=2)
                output.write('\n')
        print(json.dumps(result))
    finally:
        c.socket.close()


if __name__ == '__main__':
    main()
