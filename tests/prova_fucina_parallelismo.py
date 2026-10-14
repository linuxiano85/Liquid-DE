"""Verifica Auto nel daemon; opzionalmente ripete un candidato non installato.

La ripetizione conserva tutte le scelte del manifest, cambiando soltanto lavori
in Auto. Non installa, rimuove o riavvia kernel. Produce un nuovo dossier.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import time

from fucina_kernel_probe import temperatures
from prova_fucina_reale import Canale


def verifica_parallelismo(esito, logtext):
    recipe = esito.get('ricetta', {})
    actual = recipe.get('parallelismo') or {}
    command = next((x.get('comando', []) for x in recipe.get('passi', []) if x.get('id') == 'compila'), [])
    # La ricetta da sola non prova l'esecuzione: richiede il diario del comando
    # e il suo codice di uscita, non il testo di descrizioni o avvisi.
    started = finished = False
    for line in logtext.splitlines():
        if len(line) > 1000:
            continue
        if '] comando ' in line or '] uscita-comando ' in line:
            payload = json.loads(line.split(' ', 2)[2])
            if payload.get('argomenti') == command:
                if '] comando ' in line:
                    started = True
                elif started and payload.get('codice') == 0:
                    finished = True
    return dict(comandoEseguito=command, parallelismoEseguito=actual,
                parallelismoVerificato=(actual.get('automatico') is True and
                    isinstance(actual.get('effettivi'), int) and
                    1 <= actual['effettivi'] <= actual.get('thread', 0) and
                    f"-j{actual['effettivi']}" in command and started and finished))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--canale', required=True)
    p.add_argument('--rilascio', required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--ripeti', action='store_true')
    p.add_argument('--deadline', type=int, default=600)
    args = p.parse_args()
    if not re.fullmatch(r'\d+\.\d+(?:\.\d+)?-fucina-[a-z0-9][a-z0-9-]{0,23}', args.rilascio):
        p.error('Rilascio non valido')
    if args.deadline < 30 or args.deadline > 1800:
        p.error('Deadline fra 30 e 1800 secondi')
    cache = Path.home()/'.cache/liquid-de/fucina/uscita'
    out = cache/args.rilascio
    if out.resolve() != out.absolute() or not out.is_dir():
        raise RuntimeError('Candidato assente o collegamento simbolico')
    manifest = json.loads((out/'fucina.json').read_text())
    scelte = dict(manifest['scelte'])
    if manifest['rilascio'] != args.rilascio or f"{scelte['versione']}-fucina-{scelte['nome']}" != args.rilascio:
        raise RuntimeError('Manifest non corrispondente al candidato')
    scelte['lavori'] = None
    image = out/'boot'/f'vmlinuz-{args.rilascio}'
    digest = lambda: hashlib.sha256(image.read_bytes()).hexdigest()
    before = digest()
    c = Canale(args.canale)
    try:
        if c.stato().get('inCorso'):
            raise RuntimeError('Compilazione già in corso')
        c.invia(dict(action='fucina_kernel'))
        kernels = c.aspetta('fucina_kernel')
        # Il nome cache viene scelto dal server, non dal manifest.
        rows = kernels.get('kernel', [])
        if args.ripeti and (os.uname().release == args.rilascio or
                (Path('/usr/lib/modules')/args.rilascio).exists() or
                any(k.get('rilascio') == args.rilascio and k.get('installato') for k in rows)):
            raise RuntimeError('Il candidato è installato o in uso')
        args.output.mkdir(parents=True, exist_ok=False)
        c.invia(dict(action='fucina_ricetta', scelte=scelte))
        recipe = c.aspetta('fucina_ricetta')
        if recipe.get('ok') is not True:
            raise RuntimeError(str(recipe.get('errore')))
        parallel = recipe['parallelismo']
        command = next(x['comando'] for x in recipe['passi'] if x['id'] == 'compila')
        assert parallel['automatico'] and 1 <= parallel['effettivi'] <= parallel['thread']
        assert f"-j{parallel['effettivi']}" in command
        result = dict(ok=True, preview=parallel, buildAvviata=args.ripeti,
                      azioniAmministrativeInviate=False, imageSha256Prima=before)
        if args.ripeti:
            c.invia(dict(action='fucina_avvia', scelte=scelte))
            started = c.aspetta('fucina_avviata', timeout=60)
            if started.get('ok') is not True:
                raise RuntimeError(str(started.get('errore')))
            begin = time.monotonic()
            stop = None
            peak = 0
            while True:
                state = c.stato()
                if state.get('rilascio') != args.rilascio:
                    raise RuntimeError('Rilascio cambiato: non arresto altri lavori')
                peak = max([peak] + temperatures())
                print(json.dumps(dict(secondi=state.get('secondi'),passo=state.get('passo'),temperatura=peak)),flush=True)
                if not state.get('inCorso'):
                    esito = state.get('esito') or {}
                    result.update(ok=esito.get('ok') is True, secondi=esito.get('secondi'),
                                  peakTemperature=peak, stop=stop,
                                  parallelismoEseguito=esito.get('ricetta',{}).get('parallelismo'))
                    logfile = Path(esito['log'])
                    logtext = logfile.read_text(errors='replace').replace(str(Path.home()),'/home/utente')
                    (args.output/'build.log').write_text(logtext)
                    result.update(verifica_parallelismo(esito, logtext))
                    result['ok'] = result['ok'] and result['parallelismoVerificato']
                    break
                mem = next(x.split()[1] for x in Path('/proc/meminfo').read_text().splitlines() if x.startswith('MemAvailable:'))
                if stop is None and (peak >= 80 or int(mem) < 1024 * 1024 or time.monotonic()-begin > args.deadline):
                    stop = 'soglia di temperatura, memoria o tempo'
                    c.invia(dict(action='fucina_ferma'))
                    stopped = time.monotonic()
                elif stop is not None and time.monotonic()-stopped > 30:
                    raise RuntimeError('Arresto non confermato')
                time.sleep(2 if stop else 15)
        result['imageSha256Dopo'] = digest()
        result['immagineInvariata'] = before == result['imageSha256Dopo']
        (args.output/'summary.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
        print(json.dumps(result,ensure_ascii=False),flush=True)
        if not result['ok'] or not result['immagineInvariata']:
            raise SystemExit(1)
    finally:
        c.socket.close()


if __name__ == '__main__':
    main()
