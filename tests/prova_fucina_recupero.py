"""Diagnosi IPC, oppure prova controllata del recupero con --esegui.

La prova crea solo un segnale di lavoro e un processo sleep nella cache reale.
Non compila, installa o rimuove kernel. Termina solo il proprio processo,
verifica il rifiuto del recupero mentre è vivo e confronta i file sentinella.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
from prova_fucina_reale import Canale

ROOT = Path(__file__).resolve().parents[1]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--canale', required=True)
    p.add_argument('--esegui', action='store_true')
    p.add_argument('--output')
    args = p.parse_args()
    if args.esegui and (not args.output or Path(args.output).exists()):
        p.error('--esegui richiede un output nuovo')
    c = Canale(args.canale)
    def kernel():
        c.invia({'action': 'fucina_kernel'})
        return c.aspetta('fucina_kernel')
    def recover(token):
        c.invia({'action': 'fucina_cache_recupera', 'token': token})
        return c.aspetta('fucina_cache_recuperata')
    info = kernel()
    cache = Path(info['cache']['percorso'])
    marker = cache / '.lavoro-attivo.json'
    if not args.esegui:
        print(json.dumps({'recupero': info['cache']['recupero']}, ensure_ascii=False))
        return
    if c.stato().get('inCorso') or marker.exists():
        raise RuntimeError('Lavoro presente: la prova non lo modifica')
    sentinels = [x for x in cache.glob('uscita/*/boot/vmlinuz-*')]
    sentinels += list(cache.glob('uscita/*/fucina.json'))
    sentinels += list(cache.glob('alberi/*/linux-*/.config'))
    sentinels += list(cache.glob('alberi/*/.fucina-pronto'))
    sums = lambda: {str(x.relative_to(cache)): hashlib.sha256(x.read_bytes()).hexdigest() for x in sentinels}
    before = sums()
    child = None
    birth = None
    def stop_fixture():
        if child is None: return
        try:
            s = Path(f'/proc/{child}/stat').read_text()
            fields = s[s.rfind(')') + 2:].split()
            if fields[19] == birth and os.getpgid(child) == child:
                os.killpg(child, signal.SIGTERM)
        except (FileNotFoundError, ProcessLookupError): pass
    try:
        with tempfile.TemporaryDirectory(prefix='fucina-ipc-recupero-') as d:
            worker = Path(d) / 'worker.dart'
            uri = (ROOT / 'minervad/lib/services/fucina/blocco_lavoro.dart').as_uri()
            worker.write_text("import 'dart:io';\nimport 'dart:convert';\nimport '" + uri + "';\n" + """
Future<void> main(List<String> a) async {
 final l=await BloccoLavoro.prendi(a[0],tipo:'compilazione',dettagli:{'verificaRecupero':true});
 await l.preparaProcesso();
 final p=await Process.start('setsid',['sleep','60']);
 await l.registraProcesso(p.pid,conSetsid:true);
 print(jsonEncode({'pid':p.pid}));
 exit(0);
}
""")
            r = subprocess.run(['dart', str(worker), str(cache)], capture_output=True, text=True, check=True, timeout=15)
            child = json.loads(r.stdout)['pid']
            data = json.loads(marker.read_text())
            entry = next(x for x in data['processi'] if x['pid'] == child)
            birth = entry['inizio']
            assert data['dettagli']['verificaRecupero'] and entry['isolato'] and birth
        active = kernel()['cache']['recupero']
        assert active['stato'] == 'occupato' and any(x['pid'] == child for x in active['processi'])
        refused = recover(active['token'])
        assert refused['ok'] is False and marker.exists()
        stop_fixture()
        end = time.monotonic() + 10
        while time.monotonic() < end:
            ready = kernel()['cache']['recupero']
            if ready.get('recuperabile'): break
            time.sleep(.2)
        else: raise RuntimeError('Figlio terminato, ma recupero non verificato')
        done = recover(ready['token'])
        assert done['ok'] is True and not marker.exists()
        assert before == sums(), 'Sentinella modificata'
        result = {'ok': True, 'rejectedWhileChildAlive': True, 'recoveredAfterChildExit': True,
                  'sentinelsUnchanged': len(before), 'stateAfter': kernel()['cache']['recupero']['stato'],
                  'kernelRunning': os.uname().release, 'kernelMutationActionsSent': False}
        Path(args.output).parent.mkdir(parents=True, exist_ok=True)
        Path(args.output).write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(result))
    finally:
        stop_fixture()
        # Non cancellare il segnale a mano se una verifica fallisce.
        c.socket.close()


if __name__ == '__main__': main()
