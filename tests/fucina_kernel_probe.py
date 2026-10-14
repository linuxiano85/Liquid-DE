"""Baseline locale ripetibile: nessun root, sysctl, driver o file utente modificato.

Sonda syscall, IPC, futex, memoria (128 MiB) e piccoli file temporanei con
verifica dei dati. Limite termico e timeout; non certifica la stabilità.
Usare lo stesso binario e condizioni confrontabili dopo il prossimo boot.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    try: return Path(path).read_text().strip()
    except OSError: return None


def temperatures():
    sensors = list(Path('/sys/class/thermal').glob('thermal_zone*/temp'))
    for d in Path('/sys/class/hwmon').glob('hwmon*'):
        if read(d/'name') == 'coretemp': sensors += list(d.glob('temp*_input'))
    return [int(x)/1000 for p in sensors if (x:=read(p)) and x.isdecimal() and 0<int(x)<130000]


def inventory():
    prefix=Path('/sys/devices/system/cpu/cpu0/cpufreq')
    return dict(kernel=os.uname().release, taint=read('/proc/sys/kernel/tainted'),
        cpu={k:read(prefix/k) for k in ['scaling_driver','scaling_governor','scaling_min_freq','scaling_max_freq']},
        thp=read('/sys/kernel/mm/transparent_hugepage/enabled'),
        vulnerabilities={p.name:read(p) for p in Path('/sys/devices/system/cpu/vulnerabilities').glob('*')},
        load=read('/proc/loadavg'), temperatures=temperatures())


def run(args, timeout, max_temp):
    p=subprocess.Popen(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
    start=time.monotonic(); peak=0
    while p.poll() is None:
        peak=max([peak]+temperatures())
        if peak >= max_temp or time.monotonic()-start>timeout:
            import signal
            os.killpg(p.pid,signal.SIGTERM)
            try: p.communicate(timeout=2)
            except subprocess.TimeoutExpired: os.killpg(p.pid,signal.SIGKILL);p.communicate()
            raise RuntimeError(f'Probe fermata: temperatura {peak} °C oppure timeout {timeout}s')
        time.sleep(.05)
    out,err=p.communicate()
    if p.returncode: raise RuntimeError(f'Comando fallito ({p.returncode}): {err.decode(errors="replace")[:500]}')
    return out.decode().strip(),peak


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',required=True)
    parser.add_argument('--repeat',type=int,default=7)
    parser.add_argument('--max-temp',type=int,default=80)
    args=parser.parse_args()
    if not 1<=args.repeat<=30 or not 40<=args.max_temp<=90: parser.error('Limiti non validi')
    dest=Path(args.output)
    if dest.exists(): parser.error('Output già presente; scegliere un nuovo nome')
    before=inventory(); started=int(time.time()); result=dict(before=before,samples={},limits={
        'repeat':args.repeat,'maxTemp':args.max_temp,'memoryMiB':128,'caseTimeoutSeconds':30,
        'interpretation':'microbenchmark locale, nessun confronto tra kernel finché il candidato non viene avviato'})
    peak=0
    with tempfile.TemporaryDirectory(prefix='fucina-kernel-probe-',dir=Path.home()/'.cache') as tmp:
        binary=Path(tmp)/'probe'
        run(['gcc','-O2','-Wall','-Wextra','-Werror','-pthread',str(ROOT/'tests/fixtures/fucina_probe.c'),'-o',str(binary)],30,args.max_temp)
        result['binarySha256']=hashlib.sha256(binary.read_bytes()).hexdigest()
        # Ruota l'ordine per ridurre l'effetto del riscaldamento progressivo.
        modes=['syscall','pipe','futex','memory','fsync']
        raw={mode:[] for mode in modes}
        for i in range(args.repeat):
            for mode in modes[i%len(modes):]+modes[:i%len(modes)]:
                value,temp=run([str(binary),mode,tmp],30,args.max_temp)
                peak=max(peak,temp);raw[mode].append(float(value))
            print(json.dumps({'round':i+1,'peakTemperature':peak}),flush=True)
        result['samples']={k:dict(seconds=v,median=statistics.median(v),min=min(v),max=max(v)) for k,v in raw.items()}
    result['peakTemperature']=peak;result['after']=inventory()
    journal=subprocess.run(['journalctl','-b','-k','--since',f'@{started}','--no-pager','-o','cat'],capture_output=True,text=True)
    # Conserva solo contatori: il journal grezzo può contenere dati personali.
    result['journalReadable']=journal.returncode==0
    result['kernelEvents']={name:len(re.findall(pattern,journal.stdout,re.I)) for name,pattern in {
        'oops':r'\bOops:', 'panic':r'Kernel panic','lockup':r'(?:soft|hard) lockup',
        'hungTask':r'blocked for more than','oom':r'Out of memory:|oom-kill:',
        'gpuReset':r'GPU reset|ring .* timeout','machineCheck':r'Machine check|Hardware Error'}.items()}
    result['ok']=result['after']['taint']==before['taint'] and not any(result['kernelEvents'].values())
    dest.parent.mkdir(parents=True,exist_ok=True)
    dest.write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n')
    print(json.dumps({'ok':result['ok'],'output':str(dest),'kernel':before['kernel'],'peakTemperature':peak}))
    if not result['ok']: raise SystemExit(1)


if __name__=='__main__': main()
