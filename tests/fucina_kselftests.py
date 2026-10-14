"""Subset esplicito dei selftest upstream, senza root o hotplug/mount.

Compilazione in OUTPUT temporaneo; nessun run_tests globale. Timeout per
process group. Un test non compilabile/non autorizzato è registrato come
bloccato, mai come passato. TAP non-ok resta un fallimento da analizzare.
"""
import argparse
import difflib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile


def run(cmd,cwd,timeout):
    p=subprocess.Popen(cmd,cwd=cwd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,start_new_session=True,text=True)
    try: out,_=p.communicate(timeout=timeout);return p.returncode,out
    except subprocess.TimeoutExpired:
        os.killpg(p.pid,signal.SIGKILL);out,_=p.communicate();return 124,out+'\nTIMEOUT\n'


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--source',type=Path,required=True)
    ap.add_argument('--output',type=Path,required=True)
    a=ap.parse_args()
    a.output.mkdir(parents=True,exist_ok=True)
    cases=[('futex/functional',n,[]) for n in ['futex_wait_timeout','futex_wait_wouldblock','futex_wait','futex_requeue','futex_requeue_pi_mismatched_ops']]
    cases += [('pidfd','pidfd_open_test',[]),('pidfd','pidfd_poll_test',[]),('memfd','memfd_test',[]),
              ('seccomp','seccomp_bpf',['-t','mode_filter_support']),
              ('seccomp','seccomp_bpf',['-t','no_new_privs_support']),
              ('landlock','base_test',[])]
    results=[]
    with tempfile.TemporaryDirectory(prefix='fucina-kselftests-') as tmp:
        headers=Path(tmp)/'headers/linux';headers.mkdir(parents=True)
        # Questa UAPI è più nuova di quella installata. Copia solo l'header
        # pubblico necessario, senza generare file nell'albero in build.
        shutil.copy2(a.source/'include/uapi/linux/landlock.h',headers/'landlock.h')
        for group,name,arguments in cases:
            cwd=a.source/'tools/testing/selftests'/group
            output=Path(tmp)/group;output.mkdir(parents=True,exist_ok=True)
            binary=output/name
            build,log=run(['make','-j2',f'OUTPUT={output}',f'KHDR_INCLUDES=-isystem {headers.parent}',str(binary)],cwd,90)
            ident=name+('-'+arguments[-1] if arguments else '')
            if build:
                result=dict(name=ident,status='build-blocked',returncode=build)
            else:
                command=['stdbuf','-oL','-eL',str(binary)]+arguments
                if group in ('memfd','landlock'):
                    # Le capability esistono solo nel nuovo user namespace.
                    # PID, mount e IPC separati proteggono proc e i semafori
                    # della sessione; nessun privilegio nell'host.
                    command=['unshare','--user','--map-root-user','--mount','--pid','--fork','--ipc','--mount-proc']+command
                code,text=run(command,output,60)
                log+='\n--- execution ---\n'+text
                skips=len(re.findall(r'^ok .*# SKIP',text,re.M|re.I))
                passed=len(re.findall(r'^ok (?!.*# SKIP)',text,re.M|re.I))
                failed=len(re.findall(r'^not ok ',text,re.M))
                if name=='memfd_test' and 'memfd: DONE' in text and code==0: passed=1
                # An empty harness selection must not look green.
                status='passed' if code==0 and not failed and passed>0 else 'skipped' if code==4 else 'failed'
                if group=='memfd' and 'open sysctl failed: Permission denied' in text:
                    status='permission-blocked'
                result=dict(name=ident,status=status,returncode=code,passed=passed,skipped=skips,failed=failed)
            log=log.replace(str(Path.home()),'/home/utente').replace(tmp,'/tmp/fucina-selftests')
            (a.output/(ident+'.log')).write_text(log)
            results.append(result);print(json.dumps(result),flush=True)
        # Un sottoinsieme esplicito mantiene tutte le prove sui seal e sulla
        # condivisione dei memfd, escludendo solo le due funzioni che scrivono
        # sysctl privilegiati. Il test completo resta registrato a parte.
        group=a.source/'tools/testing/selftests/memfd'
        original=(group/'memfd_test.c').read_text()
        modified=original.replace('\t\ttest_sysctl_simple();','\t\tprintf("SKIP: sysctl_simple richiede privilegi host\\n");').replace('\t\ttest_sysctl_nested();','\t\tprintf("SKIP: sysctl_nested richiede privilegi host\\n");')
        assert modified!=original
        codefile=Path(tmp)/'memfd_subset.c';codefile.write_text(modified)
        (a.output/'memfd-sottoinsieme.patch').write_text(''.join(difflib.unified_diff(original.splitlines(True),modified.splitlines(True),fromfile='memfd_test.c',tofile='memfd_subset.c')))
        binary=Path(tmp)/'memfd_subset'
        build,log=run(['gcc','-O2','-g','-Wall','-D_FILE_OFFSET_BITS=64','-I'+str(group),'-I'+str(group.parent),str(codefile),str(group/'common.c'),'-o',str(binary)],Path(tmp),60)
        code,text=run(['stdbuf','-oL','-eL',str(binary)],Path(tmp),60) if build==0 else (build,'Build fallita')
        status='passed' if code==0 and 'memfd: DONE' in text else 'failed'
        result=dict(name='memfd-seal-e-condivisione',status=status,returncode=code,
                    exclusions=['test_sysctl_simple','test_sysctl_nested'])
        (a.output/'memfd-seal-e-condivisione.log').write_text((log+'\n'+text).replace(str(Path.home()),'/home/utente').replace(tmp,'/tmp/fucina-selftests'))
        results.append(result);print(json.dumps(result),flush=True)
    (a.output/'summary.json').write_text(json.dumps(dict(kernel=os.uname().release,tests=results),indent=2)+'\n')
    if any(r['status']=='failed' for r in results):raise SystemExit(1)


if __name__=='__main__':main()
