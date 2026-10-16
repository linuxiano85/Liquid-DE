#!/usr/bin/env python3
"""Scanner JSON bridge: discover, inspect, acquire and cancel private jobs."""
from contextlib import redirect_stdout
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time
from uuid import uuid4


def module(name):
    spec=importlib.util.spec_from_file_location(name,Path(__file__).with_name(name+'.py'))
    result=importlib.util.module_from_spec(spec);spec.loader.exec_module(result);return result


def root():
    path=Path(os.environ.get('XDG_CACHE_HOME') or Path.home()/'.cache')/'liquid-de/scanning'
    path.mkdir(parents=True,exist_ok=True,mode=0o700)
    return path


def write(path,data):
    temporary=path.with_name(path.name+'.new')
    temporary.write_text(json.dumps(data));os.chmod(temporary,0o600);os.replace(temporary,path)


def job(token):
    if not isinstance(token,str) or not re.fullmatch('[0-9a-f]{32}',token):raise ValueError('invalid-scan-job')
    path=root()/token
    if path.is_symlink() or not path.is_dir() or (path/'job.json').is_symlink():raise ValueError('unknown-scan-job')
    data=json.loads((path/'job.json').read_text())
    if data.get('kind')!='liquid-scan-job-1':raise ValueError('invalid-scan-job')
    return path,data


def process_start(pid):
    try:return Path('/proc',str(pid),'stat').read_text().rsplit(')',1)[1].split()[19]
    except (OSError,IndexError):return None


def discover():
    sane=module('liquid_sane');grouping=module('liquid_scan_discovery')
    with sane.Sane() as api:devices=api.devices()
    advertised=[]
    binary=shutil.which('airscan-discover')
    if binary:
        try:
            result=subprocess.run([binary],capture_output=True,text=True,timeout=8,check=False)
            if result.returncode==0:advertised=grouping.services(result.stdout)
        except subprocess.TimeoutExpired:pass
    return {'devices':grouping.group(devices,advertised)}


def cancel(token):
    path,data=job(token)
    (path/'cancel-requested').touch(mode=0o600)
    pid=data.get('pid')
    if type(pid) is int and pid>1 and data.get('start') and process_start(pid)==data['start']:
        try:os.kill(pid,signal.SIGTERM)
        except ProcessLookupError:pass
    return {'token':token,'status':'cancel-requested'}


def feeder(value):
    return isinstance(value,str) and bool(re.match(r'^(ADF\b|Automatic Document Feeder\b|Document Feeder\b)',value,re.I))


def capture(request):
    path,data=job(request.get('token'))
    if data.get('status')!='created':raise ValueError('scan-job-already-started')
    selected=request.get('options',{})
    if not isinstance(selected,dict):raise ValueError('unsupported-scan-option')
    batch=request.get('batch',False)
    if type(batch) is not bool or batch and not feeder(selected.get('source')):raise ValueError('invalid-scan-batch')
    limit=request.get('limit',100)
    if type(limit) is not int or not 1<=limit<=100:raise ValueError('invalid-scan-limit')
    device=request.get('device')
    try:lock=os.open(path/'capture.lock',os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    except FileExistsError as error:raise ValueError('scan-job-already-started') from error
    os.close(lock)
    cancelled=False;active=None
    def interrupt(signum,frame):
        nonlocal cancelled
        cancelled=True
        if active and active.poll() is None:
            try:active.terminate()
            except ProcessLookupError:pass
    previous=signal.signal(signal.SIGTERM,interrupt)
    data.update(pid=os.getpid(),start=process_start(os.getpid()),status='validating')
    write(path/'job.json',data)
    try:
        if (path/'cancel-requested').exists():cancelled=True
        if cancelled:return {'token':path.name,'status':'cancelled','pages':[]}
        # Keep the controller responsive while a backend is opening a device.
        validation={'action':'capabilities','device':device,'options':selected}
        active=subprocess.Popen([sys.executable,'-I',str(Path(__file__).resolve()),json.dumps(validation)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        try:out,errors=active.communicate(timeout=25)
        except subprocess.TimeoutExpired:
            active.kill();active.communicate();raise RuntimeError('scanner-open-timeout')
        if cancelled:return {'token':path.name,'status':'cancelled','pages':[]}
        caps=json.loads(out)
        if not caps.get('ok'):raise RuntimeError(caps.get('message','scanner-options-failed'))
        applied=caps['applied']
        if batch and not feeder(applied.get('source')):raise ValueError('invalid-scan-batch')
        binary=shutil.which('scanimage')
        if not binary:raise RuntimeError('sane-support-missing')
        args=[binary,'--device-name='+device,'--format=png']
        for key in ('source','mode','resolution','depth'):
            if key in applied:
                value=applied[key]
                if value is None:raise RuntimeError('scanner-options-failed')
                args.append('--'+key+'='+str(value))
        geometry={row['name']:row['value'] for row in caps['options'] if row['active'] and row['name'] in ('tl-x','tl-y','br-x','br-y')}
        if not selected.keys()&geometry.keys():geometry={}
        for short,left,right in [('l','tl-x',None),('t','tl-y',None),('x','br-x','tl-x'),('y','br-y','tl-y')]:
            if left in geometry:
                if type(geometry[left]) not in (int,float) or right and type(geometry.get(right)) not in (int,float):raise ValueError('invalid-scan-area')
                value=geometry[left]-(geometry.get(right,0) if right else 0)
                if right and value<=0:raise ValueError('invalid-scan-area')
                args.extend(['-'+short,str(value)])
        if batch:args.extend(['--batch='+str(path/'page-%04d.png'),'--batch-count='+str(limit),'--batch-start=1'])
        else:args.append('--output-file='+str(path/'page-0001.png'))
        if cancelled or (path/'cancel-requested').exists():return {'token':path.name,'status':'cancelled','pages':[]}
        data['status']='scanning';write(path/'job.json',data)
        environment=dict(os.environ,LC_ALL='C',LANG='C')
        with (path/'backend.log').open('wb') as log:
            os.chmod(path/'backend.log',0o600)
            active=subprocess.Popen(args,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=log,env=environment)
            timed_out=False;deadline=time.monotonic()+600;cancel_deadline=None
            while active.poll() is None:
                if cancelled and cancel_deadline is None:
                    active.terminate();cancel_deadline=time.monotonic()+5
                if cancel_deadline is not None and time.monotonic()>=cancel_deadline:
                    active.kill();active.wait();break
                if time.monotonic()>=deadline:
                    timed_out=True;active.terminate()
                    try:active.wait(timeout=5)
                    except subprocess.TimeoutExpired:active.kill();active.wait()
                    break
                try:active.wait(timeout=0.2)
                except subprocess.TimeoutExpired:pass
            code=active.returncode
        pages=[]
        for image in sorted(path.glob('page-*.png')):
            if image.is_symlink():raise ValueError('invalid-scan-output')
            with image.open('rb') as stream:
                signature=stream.read(8);stream.seek(max(0,image.stat().st_size-12));ending=stream.read()
            if signature==b'\x89PNG\r\n\x1a\n' and ending==b'\0\0\0\0IEND\xaeB`\x82':
                os.chmod(image,0o600);pages.append({'path':str(image),'url':image.as_uri()})
            else:image.unlink()
        status='cancelled' if cancelled else 'timeout' if timed_out else 'complete' if code==0 or (code==7 and pages) else 'no-documents' if code==7 else 'sane-status-'+str(code)
        data.update(status=status,pages=pages);write(path/'job.json',data)
        return {'token':path.name,'status':status,'pages':pages,'applied':applied,'pageLimitReached':batch and len(pages)==limit and code==0}
    finally:
        if active and active.poll() is None:
            active.kill();active.wait()
        data.pop('pid',None);data.pop('start',None)
        if data.get('status') in ('validating','scanning'):data['status']='cancelled' if cancelled else 'interrupted'
        write(path/'job.json',data)
        (path/'capture.lock').unlink(missing_ok=True)
        signal.signal(signal.SIGTERM,previous)


def main(request):
    action=request.get('action')
    if action=='discover':return discover()
    if action=='capabilities':return module('liquid_sane').capabilities(request.get('device'),request.get('options'))
    if action=='create-job':
        directory=root()/uuid4().hex;directory.mkdir(mode=0o700)
        write(directory/'job.json',{'kind':'liquid-scan-job-1','status':'created','created':time.time()})
        return {'token':directory.name}
    if action=='capture':return capture(request)
    if action=='cancel':return cancel(request.get('token'))
    if action=='release':
        directory,data=job(request.get('token'))
        if (directory/'capture.lock').exists() and not data.get('pid'):raise ValueError('scan-job-active')
        if data.get('pid') and process_start(data['pid'])==data.get('start'):raise ValueError('scan-job-active')
        shutil.rmtree(directory);return {}
    raise ValueError('unknown-scan-action')


if __name__=='__main__':
    request={}
    try:
        request=json.loads(sys.argv[1])
        if not isinstance(request,dict):request={};raise ValueError('invalid-request')
        with redirect_stdout(sys.stderr):result=main(request)
        result.update(ok=True)
    except Exception as error:result={'ok':False,'message':str(error)}
    result.update(action=request.get('action'),generation=request.get('generation'))
    print(json.dumps(result,ensure_ascii=False))
