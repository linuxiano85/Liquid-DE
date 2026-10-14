"""Verifica i target CPU dichiarati dal daemon, senza compilare kernel.

Il rilievo può aggiornare lo storico locale delle periferiche come nell'app.
Non invia azioni root, di compilazione, installazione o rimozione.
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
        p.error('Rilascio non valido')
    c = Canale(args.canale)
    try:
        assert not c.stato().get('inCorso'), 'Attendi la conclusione della build'
        c.invia({'action':'fucina_kernel'})
        cache = Path(c.aspetta('fucina_kernel')['cache']['percorso'])
        image = cache / f'uscita/{args.rilascio}/boot/vmlinuz-{args.rilascio}' if args.rilascio else None
        sha = lambda: hashlib.sha256(image.read_bytes()).hexdigest() if image else None
        before = sha()
        c.invia({'action':'fucina_rileva'})
        info = c.aspetta('fucina_rilievo')
        machine = info['macchina']
        targets = info['targetCompilatori']
        assert all(type(machine[k]) is bool for k in ['flagsCpuCompleti','flagsCpuUniformi'])
        assert {t['compilatore'] for t in targets} == {'gcc','clang'} or not targets
        for t in targets:
            assert type(t['rilevato']) is bool
            if t['rilevato']:
                assert t['cpu']!='native' and re.fullmatch(r'[a-zA-Z0-9_+.-]{1,80}',t['cpu'])
        assert before == sha()
        result = dict(ok=True,livelloX86=machine['livelloX86'],
                      cpuConFlags=machine['cpuConFlags'],
                      flagsCompleti=machine['flagsCpuCompleti'],
                      flagsUniformi=machine['flagsCpuUniformi'],
                      targetCompilatori=targets,
                      immagineConfrontata=args.rilascio,imageSha256=before,
                      immagineInvariata=bool(image) and before==sha(),
                      kernelMutationActionsSent=False,storicoLocaleAggiornabile=True)
        if args.output:
            with Path(args.output).open('x') as f:
                json.dump(result,f,indent=2,ensure_ascii=False);f.write('\n')
        print(json.dumps(result,ensure_ascii=False))
    finally:
        c.socket.close()


if __name__=='__main__':
    main()
