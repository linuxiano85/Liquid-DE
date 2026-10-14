"""Compila un candidato distinto con il daemon reale; non installa né riavvia.

Sorveglia memoria, temperatura e tempo. Il profilo AutoFDO è solo preparato:
nessun guadagno PGO viene dichiarato finché non si registra un carico reale.
"""
import argparse
import json
import os
import re
from pathlib import Path
import time

from fucina_kernel_probe import temperatures
from prova_fucina_reale import Canale

# Gli artefatti stanno nel repository delle prove, non in questo (vedi
# audit/README.md). FUCINA_ARTEFATTI li manda altrove.
ARTEFATTI=Path(os.environ.get('FUCINA_ARTEFATTI') or
    Path(__file__).resolve().parents[2]/'Liquid_test-principale/rapporti/artefatti-2026-10/fucina2')


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--canale',required=True)
    p.add_argument('--versione',required=True)
    p.add_argument('--nome',default='opt-clang')
    p.add_argument('--deadline',type=int,default=2700)
    p.add_argument('--ripeti',action='store_true',help='Ripete solo lo stesso candidato pronto e non installato; conserva artefatti della prima build')
    p.add_argument('--campione',default='',help='Suffisso per conservare distintamente una ripetizione successiva')
    args=p.parse_args()
    if args.campione and not re.fullmatch('[a-z0-9][a-z0-9-]*',args.campione):p.error('Nome campione non valido')
    c=Canale(args.canale)
    if c.stato().get('inCorso'): raise RuntimeError('Build già attiva: non viene modificata')
    scelte=dict(versione=args.versione,nome=args.nome,sorgente='cachyos',base='in-uso',
                compilatore='clang',lto=True,nativo=True,misura=True,lavori=8,
                scorte=['chiavette','controller','filesystem'],preset=['gaming'],autofdo=True)
    release=f'{args.versione}-fucina-{args.nome}'
    out=Path.home()/'.cache/liquid-de/fucina/uscita'/release
    if out.exists():
        if not args.ripeti: raise RuntimeError('Candidato già presente: scegliere un nuovo nome')
        if os.uname().release==release or (Path('/usr/lib/modules')/release).exists():
            raise RuntimeError('Non ripeto un candidato installato o in uso')
        previous=json.loads((out/'fucina.json').read_text())
        if previous.get('rilascio')!=release or any(previous.get('scelte',{}).get(k)!=v for k,v in scelte.items()):
            raise RuntimeError('Il candidato esistente non ha la stessa ricetta')
    elif args.ripeti: raise RuntimeError('Manca il candidato pronto da ripetere')
    label=args.nome+('-ripetizione' if args.ripeti else '')
    if args.campione: label+='-'+args.campione
    if any((ARTEFATTI/f'{prefix}-{label}.{ext}').exists() for prefix,ext in [('build','log'),('esito','json')]):
        raise RuntimeError('Artefatti già presenti: non li sovrascrivo')
    c.invia(dict(action='fucina_avvia',scelte=scelte))
    r=c.aspetta('fucina_avviata',timeout=60)
    if r.get('ok') is not True: raise RuntimeError(str(r))
    started=time.monotonic();stop=None;peak=0
    while True:
        s=c.stato()
        if s.get('rilascio')!=release: raise RuntimeError('Rilascio cambiato: non fermo altre build')
        peak=max([peak]+temperatures())
        available=int(next(x.split()[1] for x in Path('/proc/meminfo').read_text().splitlines() if x.startswith('MemAvailable:')))
        print(json.dumps(dict(seconds=s.get('secondi'),step=s.get('passo'),progress=s.get('avanzamento'),
                              temperature=peak,availableMiB=available//1024,stop=stop)),flush=True)
        if not s.get('inCorso'):
            esito=s.get('esito') or {}
            home=str(Path.home())
            clean=lambda t:t.replace(home,'/home/utente')
            dest=ARTEFATTI;dest.mkdir(parents=True,exist_ok=True)
            log=Path(esito['log'])
            (dest/f'build-{label}.log').write_text(clean(log.read_text(errors='replace')))
            (dest/f'esito-{label}.json').write_text(clean(json.dumps(dict(esito=esito,peakTemperature=peak,stop=stop),ensure_ascii=False,indent=2))+'\n')
            print(json.dumps(dict(ok=esito.get('ok'),error=esito.get('errore'),seconds=esito.get('secondi'),
                                  warnings=esito.get('avvisi'),release=release),ensure_ascii=False),flush=True)
            if esito.get('ok') is not True: raise SystemExit(1)
            break
        if stop is None:
            if peak>=80: stop='temperatura >=80C'
            if available<1024*1024: stop='memoria disponibile <1GiB'
            if time.monotonic()-started>args.deadline: stop='limite temporale'
            if stop:
                c.invia(dict(action='fucina_ferma'))
                stopped=time.monotonic()
        elif time.monotonic()-stopped>30: raise RuntimeError('Arresto non confermato')
        time.sleep(2 if stop else 20)
    c.socket.close()


if __name__=='__main__': main()
