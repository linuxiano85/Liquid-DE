#!/usr/bin/env python3
"""Real Wayland clients, input, cached GPU snapshots and workspace overview.
All processes and input use a private compositor, never the user's session.
"""
import json, os, re, signal, socket, subprocess, tempfile, time, hashlib, sys
if not os.environ.get("LIQUID_TEST_BUS"):
    os.environ["LIQUID_TEST_BUS"]="1"
    os.execvp("dbus-run-session",["dbus-run-session","--",sys.executable,*sys.argv])
from pathlib import Path
from PIL import Image,ImageStat
ROOT=Path(os.environ.get('LIQUID_DE', str(Path(__file__).resolve().parents[1])))
HERE=ROOT.parent/'Liquid_test-principale/compositore'
ART=Path(os.environ.get('MINERVA_TEST_REPORT_DIR',str(HERE.parent/'rapporti'/'windows11')))
ART.mkdir(parents=True,exist_ok=True)
checks=[];children=[];handles=[];completed=False
def source_hashes():
    paths=[p for p in (ROOT/'minerva-shell').rglob('*') if p.is_file() and (p.suffix in ('.qml','.js') or p.name=='qmldir') and not p.name.startswith('_prova')]
    paths.extend([ROOT/'minervad/lib/core/settings_api.dart', ROOT/'minervad/lib/core/desktop_profiles.dart', ROOT/'minervad/lib/ipc/websocket_server.dart', ROOT/'minervad/lib/services/liquid_update_service.dart', ROOT/'scripts/liquid-update-version.py', ROOT/'scripts/minerva-installa-radice'])
    paths.extend(ROOT/p for p in ['compositore/src/main.c','compositore/src/dialoghi.c','compositore/src/dialoghi.h','compositore/meson.build'])
    paths.append(ROOT/'config/scorciatoie.minerva')
    paths.extend(p for p in (ROOT/'minerva-shell/windows11').rglob('*') if p.is_file())
    paths = sorted(set(paths))
    return {str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}
source_snapshot=source_hashes()
def check(name,condition,detail=None):
    checks.append({'name':name,'passed':bool(condition)})
    print(('PASS ' if condition else 'FAIL ')+name,flush=True)
    assert condition,(name,detail)
def wait(fn,timeout=10):
    until=time.monotonic()+timeout
    while time.monotonic()<until:
        result=fn()
        if result:return result
        time.sleep(.08)
    raise AssertionError('timed out')
def spawn(args,env,name):
    handle=open(ART/(name+'.log'),'w');handles.append(handle)
    p=subprocess.Popen(args,env=env,stdout=handle,stderr=handle,start_new_session=True);children.append(p);return p
def luminance(color):
    values=[int(color[i:i+2],16)/255 for i in (1,3,5)]
    values=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in values]
    return sum(a*b for a,b in zip(values,(.2126,.7152,.0722)))
def contrast(first,second):
    a,b=sorted((luminance(first),luminance(second)))
    return (b+.05)/(a+.05)
tempdir=tempfile.TemporaryDirectory(prefix="minerva-tiling-windows11-")
tmp=tempdir.name
tested_hash=""
try:
 env=dict(os.environ,MINERVA_PROVA='1',WLR_BACKENDS='headless',WLR_HEADLESS_OUTPUTS='2',WLR_RENDERER='gles2',
     MINERVA_SCRIVANIA='0',MINERVA_IPC_SOCKET=tmp+'/absent',MINERVA_CONFIG_DIR=tmp+'/config',
     XDG_CONFIG_HOME=tmp+'/config',XDG_CACHE_HOME=tmp+'/cache',XDG_STATE_HOME=tmp+'/state',
     LIQUID_DE=str(ROOT),XDG_RUNTIME_DIR=tmp,MINERVA_SESSIONE='category-test',XDG_SESSION_ID='category-test',QT_QPA_PLATFORM='wayland',QT_QUICK_BACKEND='software',QT_QPA_PLATFORMTHEME='',QT_NO_XDG_DESKTOP_PORTAL='1',GTK_USE_PORTAL='0',NO_AT_BRIDGE='1')
 env['DBUS_SYSTEM_BUS_ADDRESS']=env['DBUS_SESSION_BUS_ADDRESS']
 # Il giro integrale comprende anche il mixer, che vuole il suo PipeWire
 # privato già acceso quando parte la shell. I giri mirati non lo accendono.
 GIRI_MIRATI=('AUDIO_MIXER','VOLUME_CONTEXT','MIXER_SHORTCUT','WIFI','BLUETOOTH','QUICK_TILES',
     'VOLUME_OVERDRIVE','VOLUME_WHEEL','QUICK_AUDIO','DESKTOP_SAFETY','PREVIEWS_ONLY','START_VIEWS_ONLY','START_BAR_OPTIONS','START_FOLDERS','TRAY_MENUS','APP_REFRESH')
 giro_integrale=not any(os.environ.get('MINERVA_TEST_'+g)=='1' for g in GIRI_MIRATI)
 if os.environ.get('MINERVA_TEST_AUDIO_MIXER') == '1' or giro_integrale:
     # Senza gestore sessione non si enumerano schede ALSA: questi flussi
     # restano scollegati, su un socket PipeWire esclusivamente privato.
     env['PIPEWIRE_RUNTIME_DIR']=tmp
     env['PIPEWIRE_REMOTE']='pipewire-0'
     env['PULSE_SERVER']='unix:'+tmp+'/pulse/native'
     private_audio=spawn(['pipewire'],env,'pipewire')
     wait(lambda:Path(tmp+'/pipewire-0').exists())
 # Percorsi XDG spostati con caratteri riservati, prima che Qt li legga.
 folder_paths={}
 if os.environ.get('MINERVA_TEST_START_FOLDERS') == '1':
     config_dir=Path(env['XDG_CONFIG_HOME']);config_dir.mkdir(parents=True,exist_ok=True)
     xdg=[]
     for folder,kind in [('documents','DOCUMENTS'),('downloads','DOWNLOAD'),('music','MUSIC'),('pictures','PICTURES'),('videos','VIDEOS')]:
         destination=Path(tmp)/'Raccolta #é %test'/folder
         destination.mkdir(parents=True)
         folder_paths[folder]=str(destination)
         xdg.append('XDG_'+kind+'_DIR="'+str(destination)+'"')
     (config_dir/'user-dirs.dirs').write_text('\n'.join(xdg)+'\n')
 env.pop('MINERVA_CANALE',None)
 wifi_state_file=Path(tmp)/'wifi-state.json'
 wifi_state_file.write_text(json.dumps({'radio':True,'selected':'Rete salvata','networks':[
     ['Rete salvata',95,True],['Rete protetta',85,True],['Rete aperta',75,False],['Nome:con\\barra',60,True],['__proto__',20,False]]}))
 wifi_bin=Path(tmp)/'bin';wifi_bin.mkdir()
 wifi_shim=wifi_bin/'nmcli';wifi_shim.write_bytes((ROOT/'tests/fixtures/windows11-nmcli.py').read_bytes());wifi_shim.chmod(0o700)
 env['PATH']=str(wifi_bin)+':'+env['PATH']
 env['MINERVA_WIFI_FIXTURE_STATE']=str(wifi_state_file)
 comp=spawn([str(ROOT/'compositore/build-native/minerva-wayland')],env,'compositor')
 tested_hash=hashlib.sha256(Path(f'/proc/{comp.pid}/exe').read_bytes()).hexdigest()
 def info():
     t=(ART/'compositor.log').read_text();a=re.search(r'in ascolto su (\S+)',t);b=re.search(r'canale su (\S+)',t)
     return (a[1],b[1]) if a and b else None
 display,channel=wait(info);env.update(WAYLAND_DISPLAY=str(Path(tmp)/display),MINERVA_CANALE=channel)
 def cmd(line,success=True):
     with socket.socket(socket.AF_UNIX) as s:
         s.settimeout(5);s.connect(channel);s.sendall((line+'\n').encode());out=b''
         while b'\n' not in out:
             chunk=s.recv(65536)
             if not chunk:raise RuntimeError('IPC disconnected')
             out+=chunk
     text=out.decode().strip()
     if success: assert text.startswith('ok'),(line,text)
     return text[3:] if text.startswith('ok') else text
 def windows():return json.loads(cmd('finestre'))
 def state():return json.loads(cmd('stato'))
 def item(id):return next(w for w in windows() if w['id']==id)
 def settle():time.sleep(.3)
 def key(name,mods):
     for m in mods:cmd('tasto '+m+' premi')
     cmd('tasto '+name+' premi');cmd('tasto '+name+' lascia')
     for m in reversed(mods):cmd('tasto '+m+' lascia')
     settle()
 initial=json.loads(cmd('schermi'));primary=next(o for o in initial if o['nome']=='HEADLESS-1');cmd(f"dito {primary['x']+100} {primary['y']+100}")
 cmd('tasto Shift_L premi');cmd('tasto Shift_L lascia')
 sock=tmp+'/settings.sock'
 daemon=spawn(['dart','run',str(ROOT/'minervad/test/windows11_fixture.dart'),tmp],env,'settings-api');wait(lambda:Path(sock).exists())
 channel_file=Path(tmp)/'liquid-de/sessioni/category-test/canale';channel_file.parent.mkdir(parents=True);channel_file.write_text('socket='+sock+'\nsegreto=private-category-fixture\n');channel_file.chmod(0o600)
 fixture=Path(tmp)/'windows.qml'
 (Path(tmp)/"files.qml").write_text((ROOT/"tests/fixtures/windows11-files.qml").read_text())
 fixture.write_text((ROOT/"tests/fixtures/windows11.qml").read_text().replace("@W@",(ROOT/"minerva-shell/windows11").as_uri()).replace("@CORE@",(ROOT/"minerva-shell/core").as_uri()).replace("@MENU@",(ROOT/"minerva-shell/menu").as_uri()).replace("@SETTINGS@",(ROOT/"minerva-shell/settings/sections").as_uri()).replace("@THEME@",(ROOT/"minerva-shell/theme").as_uri()).replace("@ROOT@",str(ROOT)))
 uienv=dict(env,MINERVA_SCRIVANIA='1',MINERVA_IPC_SOCKET=sock,QML_IMPORT_PATH=str(ROOT/'minerva-shell/native'))
 bluetooth_fixture=spawn(['python3',str(ROOT/'tests/fixtures/windows11-bluetooth.py'),tmp+'/bluetooth-actions.json'],env,'bluetooth')
 wait(lambda:Path(tmp+'/bluetooth-actions.json').exists())
 ui=spawn(['qs','-p',str(fixture)],uienv,'windows')
 def call(method,*args):
     # CLI11 espande gli argomenti [a,b] come liste: un oggetto protegge il JSON.
     if method=='preference':
         args=(args[0],json.dumps({'value':json.loads(args[1])},separators=(',',':')))
     r=subprocess.run(['qs','-p',str(fixture),'ipc','call','windows-test',method,*map(str,args)],env=uienv,text=True,capture_output=True,timeout=10)
     if r.returncode and 'No running instances' in r.stderr+r.stdout:return None
     assert r.returncode==0,r.stdout+r.stderr
     # Quickshell può segnalare un errore degli argomenti anche con codice zero.
     assert not r.stdout.startswith(('Too many arguments provided','Too few arguments provided','Not enough arguments provided','Target not found','Function not found')),r.stdout+r.stderr
     return r.stdout.strip()
 def ui_state():
     raw=call('status');return json.loads(raw) if raw and raw.startswith('{') else {'ready':False}
 def click(control,button=''):
     c=wait(lambda:ui_state()['controls'].get(control))
     cmd(f"dito {c['x']+ui_state()['screenX']} {c['y']+ui_state()['screenY']}")
     suffix=(' '+button) if button else ''
     cmd('dito premi'+suffix)
     cmd('dito lascia'+suffix)
     settle()
 def away():
     screen=ui_state()
     cmd(f"dito {screen['screenX']+2} {screen['screenY']+2}")
 def exercise_start_views():
     original_pins=ui_state()['settings']['launcher']['fixedApps']
     two_pins=original_pins[:2]
     pin_write=call('preference','launcher.fixedApps',json.dumps(two_pins,separators=(',',':')))
     call('preference','desktop.animations','true')
     settle()
     check('Start test preference reaches the private settings store',ui_state()['settings']['launcher']['fixedApps']==two_pins,{'expected':two_pins,'actual':ui_state()['settings']['launcher']['fixedApps'],'write':pin_write})
     call('open','start')
     settle()
     call('viewTraceBegin')
     click('windowsAllAppsButton')
     forward=json.loads(call('viewTraceStop'))
     middle=[frame for frame in forward['frames'] if 0<frame.get('progress',0)<1]
     check('Start to All apps presents intermediate frames',bool(middle),forward)
     check('outgoing pinned tiles retain their original model',all(frame['tileIds']==two_pins and frame['listCount']==12 for frame in middle),forward)
     check('only incoming All apps accepts input during navigation',all(frame['listEnabled'] and not frame['pinnedEnabled'] for frame in middle),forward)
     check('Start navigation moves content and keeps footer stable',any(frame['pinnedX']<32<frame['listX'] for frame in middle) and all(frame['footerOpacity']==1 for frame in middle),forward)
     final=forward['state']
     check('All apps settles with pinned page hidden',final['progress']==1 and final['allApps'] and not final['pinnedVisible'] and not final['animating'],final)
     screenshot('start-all-apps-light')
     call('viewTraceBegin')
     click('windowsAllAppsBack')
     backward=json.loads(call('viewTraceStop'))
     check('Back presents intermediate frames with only pinned input',any(0<frame.get('progress',0)<1 and frame['pinnedEnabled'] and not frame['listEnabled'] for frame in backward['frames']),backward)
     check('Back returns search focus and removes list page',backward['state']['inputFocus'] and backward['state']['progress']==0 and not backward['state']['listVisible'],backward)
     call('viewInterrupt','back')
     settle()
     reversed_view=json.loads(call('viewTraceStop'))
     check('navigation reversal is exercised before the previous animation ends',any(frame.get('animating') and frame.get('allApps') and 0<frame.get('progress',0)<1 for frame in reversed_view['frames']),reversed_view)
     check('navigation reversal keeps the last requested page',reversed_view['state']['progress']==0 and not reversed_view['state']['allApps'] and not reversed_view['state']['animating'],reversed_view)
     click('windowsAllAppsButton')
     key('Tab',[])
     key('Down',[])
     check('All apps Tab and arrow select the second catalog entry',ui_state()['selected']==1,ui_state())
     expected_app=ui_state()['apps'][1]
     before_actions=json.loads((Path(tmp)/'actions.json').read_text())
     before_launches=sum(action.get('action')=='launch_app' for action in before_actions)
     key('KP_Enter',[])
     def launches():
         return [action for action in json.loads((Path(tmp)/'actions.json').read_text()) if action.get('action')=='launch_app']
     actual=wait(lambda:launches() if len(launches())>before_launches else None)
     check('keypad Enter launches exactly the selected app',len(actual)==before_launches+1 and actual[-1]['id']==expected_app and ui_state()['panel']=='',actual)
     call('open','start')
     settle()
     click('windowsAllAppsButton')
     key('Escape',[])
     check('Escape returns from All apps without closing Start',ui_state()['panel']=='start' and not json.loads(call('viewStatus'))['allApps'],ui_state())
     key('b',[])
     search=json.loads(call('viewStatus'))
     check('typing switches immediately to results without navigation animation',search['query']=='b' and search['progress']==1 and not search['animating'] and search['listEnabled'] and not search['pinnedEnabled'],search)
     key('Tab',[])
     key('Escape',[])
     cleared=json.loads(call('viewStatus'))
     check('Escape clears Start search and returns input focus before closing',ui_state()['panel']=='start' and cleared['query']=='' and cleared['inputFocus'],cleared)
     call('viewInterrupt','disable')
     settle()
     disabled_view=json.loads(call('viewTraceStop'))
     check('disabling motion during navigation settles All apps',disabled_view['state']['progress']==1 and not disabled_view['state']['animating'] and disabled_view['state']['listEnabled'],disabled_view)
     call('viewTraceBegin')
     click('windowsAllAppsBack')
     instant_view=json.loads(call('viewTraceStop'))
     check('reduced motion returns to pinned without intermediate frames',instant_view['state']['progress']==0 and not any(frame.get('animating') for frame in instant_view['frames']),instant_view)
     call('preference','desktop.animations','true')
     settle()
     call('viewInterrupt','close')
     settle()
     closed_view=json.loads(call('viewTraceStop'))
     check('closing Start during navigation unloads both pages',not closed_view['state']['available'] and ui_state()['panel']=='',closed_view)
     call('open','start')
     settle()
     clean=json.loads(call('viewStatus'))
     check('reopening Start restores a clean pinned page',clean['progress']==0 and not clean['allApps'] and not clean['animating'] and clean['inputFocus'],clean)
     call('close')
     settle()
     call('preference','launcher.fixedApps',json.dumps(original_pins,separators=(',',':')))
     call('preference','desktop.animations','false')
     settle()
     away()
     (ART/'start-views-motion.json').write_text(json.dumps({'forward':forward,'backward':backward,'reversed':reversed_view,'disabled':disabled_view,'instant':instant_view,'closed':closed_view},indent=2))
 def screenshot(name,output='HEADLESS-1'):
     path=ART/(name+'.png');subprocess.run(['grim','-o',output,str(path)],env=env,check=True,timeout=10)
     with Image.open(path) as img:
         variation=ImageStat.Stat(img.convert('RGB').resize((128,72))).stddev
         check(name+' actually renders visible pixels',max(variation)>8,variation)
     return path
 def exercise_previews():
     def files_call():
         subprocess.run(['qs','-p',tmp+'/files.qml','ipc','call','windows-files-test','add'],env=env,check=True,capture_output=True,timeout=10)
     call('preference','windows11.acrylic','true');time.sleep(.7)
     # Nessuno deve togliere la trasparenza locale anche quando è salvata.
     call('preference','shell.windowOpacity','0.60')
     call('preference','windows.effettoOpacita','0.70')
     call('preference','windows.effetto',json.dumps('nessuno'));settle()
     check('None makes native window backgrounds opaque',json.loads(call('effectState'))['alpha']==1)
     call('preference','windows.effetto',json.dumps('vetro'));time.sleep(.7)
     check('Glass delegates transparency once to compositor',json.loads(call('effectState'))['alpha']==1 and abs(state()['effettoAlfa']-.7)<.01)
     call('preference','windows.effetto',json.dumps('acquerello'));settle()
     check('Watercolour receives a translucent native background',json.loads(call('effectState'))['alpha']<1)
     call('preference','windows.effetto',json.dumps('nessuno'));settle()
     check('returning to None restores full opacity',json.loads(call('effectState'))['alpha']==1)
     material=json.loads(call('effectState'))
     check('Acrylic is actually acknowledged by compositor',material['acrylic'] and material['widgetsAlpha']<material['barAlpha']<1,material)
     call('preference','windows.effettoOpacita','0.88')
     away();call('open','weather');settle()
     screenshot('widgets-acrylic')
     click('windowsWeatherForecast');settle()
     screenshot('widgets-forecast-acrylic')
     call('close');away()
     # Alacritty in XWayland, come i terminali realmente segnalati.
     xdisplay=re.search(r'XWayland su DISPLAY=(\S+)',(ART/'compositor.log').read_text())[1]
     xenv=dict(env,DISPLAY=xdisplay,WINIT_UNIX_BACKEND='x11')
     xenv.pop('WAYLAND_DISPLAY',None)
     cmd('tiling classico')
     terminals=[]
     for number in range(2):
         terminal=spawn(['alacritty','--config-file','/dev/null','--class','liquid-preview-alacritty',
             '--title','Terminale prova '+str(number),'-e','sleep','180'],xenv,'alacritty-'+str(number))
         terminals.append(terminal)
         wait(lambda:any(w['pid']==terminal.pid for w in windows()))
     settle()
     ids=[next(w['id'] for w in windows() if w['pid']==terminal.pid) for terminal in terminals]
     for selected in ids:
         cmd('riduci '+selected+' si');settle()
         group=next(g for g in ui_state()['groups'] if any(w['address']==selected for w in g['windows']))
         c=ui_state()['controls']['windowsTask-'+group['id']];screen=ui_state()
         cmd(f"dito {c['x']+screen['screenX']} {c['y']+screen['screenY']}")
         wait(lambda:ui_state()['hoverPreview'])
         click('windowsPreview-'+selected)
         wait(lambda:not item(selected)['ridotta'] and state()['fuoco']==selected)
         check('Alacritty X11 hover restores the selected terminal '+selected,ui_state()['panel']=='')
         cmd('ingrandisci '+selected+' si');settle()
         check('restored Alacritty X11 can maximize '+selected,item(selected)['ingrandita'] and item(selected)['larghezza']>1000)
         cmd('ingrandisci '+selected+' no');away()
     for terminal in terminals:
         os.killpg(terminal.pid,signal.SIGTERM)
         terminal.wait(timeout=5)
     wait(lambda:not windows())
     cmd('tiling colonne')
     files=spawn(['qs','-p',tmp+'/files.qml'],env,'files')
     wait(lambda:len(windows())==1);settle()
     for n in range(1,5):
         if n>1:files_call();wait(lambda:len(windows())==n);settle()
         groups=ui_state()['groups'];g=next(g for g in groups if g['id']=='test-files.desktop')
         check(str(n)+' same-process/same-title windows remain distinct',len(g['windows'])==n and len(set(w['address'] for w in g['windows']))==n,g)
         click('windowsTask-test-files.desktop');wait(lambda:ui_state()['panel']=='windows' if n>1 else ui_state()['panel']=='')
         if n>1:
             controls=ui_state()['controls'];check(str(n)+' cached previews have distinct addresses',sum(k.startswith('windowsPreview-') for k in controls)==n,controls)
             screenshot('file-previews-'+str(n));key('Escape',[])
         away()
     c=ui_state()['controls']['windowsTask-test-files.desktop'];screen=ui_state();cmd(f"dito {c['x']+screen['screenX']} {c['y']+screen['screenY']}")
     wait(lambda:ui_state()['hoverPreview']);check('hover opens cached previews without exclusive keyboard capture',ui_state()['panel']=='windows')
     away();wait(lambda:ui_state()['panel']=='');check('hover preview closes when pointer leaves',True)
     # Il pannello aperto al passaggio del mouse ha un percorso di input
     # diverso da quello aperto al clic: si provano tutte le finestre, non
     # soltanto la prima delegata (segnalazione Alacritty, 11 ottobre 2026).
     for selected in [w['id'] for w in windows()]:
         cmd('riduci '+selected+' si');settle()
         c=ui_state()['controls']['windowsTask-test-files.desktop'];screen=ui_state()
         cmd(f"dito {c['x']+screen['screenX']} {c['y']+screen['screenY']}")
         wait(lambda:ui_state()['hoverPreview'])
         click('windowsPreview-'+selected)
         wait(lambda:not item(selected)['ridotta'] and state()['fuoco']==selected)
         check('hover preview restores and focuses '+selected,ui_state()['panel']=='' and not item(selected)['ridotta'])
         away()
     original=windows()[0]['id'];cmd('riduci '+original+' si');settle()
     check('minimized window remains available in app group',any(w['address']==original and w['minimized'] for w in ui_state()['groups'][0]['windows']))
     click('windowsTask-test-files.desktop');click('windowsPreview-'+original);settle()
     check('clicking preview restores minimized window',not item(original)['ridotta'] and state()['fuoco']==original)
     # Cambiare titolo mentre il mouse è premuto non deve distruggere
     # la delegata e perdere il rilascio (terminali con titoli dinamici).
     cmd('riduci '+original+' si');settle()
     c=ui_state()['controls']['windowsTask-test-files.desktop'];screen=ui_state()
     cmd(f"dito {c['x']+screen['screenX']} {c['y']+screen['screenY']}")
     wait(lambda:ui_state()['hoverPreview'])
     c=ui_state()['controls']['windowsPreview-'+original]
     cmd(f"dito {c['x']+screen['screenX']} {c['y']+screen['screenY']}");cmd('dito premi')
     subprocess.run(['qs','-p',tmp+'/files.qml','ipc','call','windows-files-test','renameAll'],env=env,check=True,capture_output=True,timeout=10)
     wait(lambda:all(w['title'].startswith('Titolo aggiornato') for w in ui_state()['windows']))
     settle();cmd('dito lascia')
     wait(lambda:not item(original)['ridotta'] and state()['fuoco']==original)
     check('preview survives title updates between mouse press and release',ui_state()['panel']=='')
     return original
 wait(lambda:ui_state()['ready']);call('prepare');settle();call('preset','windows');settle()
 if os.environ.get('MINERVA_TEST_APP_REFRESH') == '1':
     wait(lambda:ui_state()['ready'])
     call('close')
     original = json.loads(call('catalog'))
     added = {'appId':'app-appena-installata.desktop','name':'App appena installata','exec':'true','icon':'application-x-executable','categories':['Utility']}
     catalog_file = Path(tmp)/'catalogo-app.json'
     def catalog():
         return json.loads(call('catalog'))
     def scans():
         actions_file = Path(tmp)/'actions.json'
         actions = json.loads(actions_file.read_text()) if actions_file.exists() else []
         return len([a for a in actions if a.get('action') == 'rescan_apps'])
     def contains_added():
         return any(a['appId'] == added['appId'] for a in catalog())
     for panel in ['start','search','liquid']:
         catalog_file.write_text(json.dumps(original + [added]))
         before = scans()
         if panel == 'liquid':
             call('liquidOpen')
         else:
             call('open',panel)
         wait(lambda:contains_added() and scans() > before)
         check(panel+' rileva una nuova app dopo l’avvio senza riavviare',contains_added())
         if panel == 'start':
             click('windowsAllAppsButton')
             wait(lambda:added['appId'] in ui_state()['apps'])
             check('Tutte le app mostra davvero il nuovo programma',added['appId'] in ui_state()['apps'])
         if panel == 'liquid':
             call('liquidClose')
         else:
             call('close')
         settle()
         catalog_file.write_text(json.dumps(original))
         if panel == 'liquid':
             call('liquidOpen')
         else:
             call('open',panel)
         wait(lambda:not contains_added())
         check(panel+' rimuove dal catalogo le app disinstallate',not contains_added())
         if panel == 'liquid':
             call('liquidClose')
         else:
             call('close')
         settle()
     before = scans()
     time.sleep(3)
     check('nessuna scansione periodica con launcher chiusi',scans() == before)
     check('sorgenti invariati durante la prova',source_hashes() == source_snapshot)
     completed=True
     raise SystemExit(0)
 if os.environ.get('MINERVA_TEST_TRAY_MENUS') == '1':
     tray=spawn([sys.executable,str(ROOT/'tests/fixtures/windows11-tray.py'),tmp+'/tray-events.json'],dict(env,LIQUID_TEST_TRAY_COMPLEX='1'),'tray')
     wait(lambda:ui_state()['trayCount']==9,15)
     def tray_state(): return json.loads(call('trayState'))
     def tray_events(): return json.loads(Path(tmp+'/tray-events.json').read_text()) if Path(tmp+'/tray-events.json').exists() else []
     def open_tray_menu():
         click('windowsTrayToggle')
         click('windowsTrayItem-Demo 1','destro')
         return wait(lambda:tray_state() if tray_state()['open'] and len(tray_state()['items'])>=8 else None)
     click('windowsTrayToggle')
     check('overflow mostra nove icone reali',sum(k.startswith('windowsTrayItem-') for k in ui_state()['controls'])==9)
     key('Home',[]);key('Down',[]);key('Right',[]);key('Return',[])
     wait(lambda:'activate-5' in tray_events())
     check('frecce della griglia e Invio attivano la quinta posizione',True)
     check('attivare una icona chiude il pannello',ui_state()['panel']=='')
     menu=open_tray_menu()
     wait(lambda:any(item.get('label')=='Modalità' and any(c.get('label')=='Normale' for c in item.get('children',[])) for item in tray_state()['items']))
     menu=tray_state()
     check('mnemoniche D-Bus rimosse e ampersand conservata',[i.get('label') for i in menu['items'] if not i.get('separator')][:4]==['Apri','Disabilitato','Modalità','Spunta & stato'],menu['items'])
     check('voce invisibile assente dal menu',all(i.get('label')!='Nascosta' for i in menu['items']))
     checked=next(i for i in menu['items'] if i.get('label')=='Spunta & stato')
     check('spunta ricevuta dal servizio',checked['checkable'] and checked['checked'] and not checked['radio'])
     radios=[i for i in menu['items'] if i.get('radio')]
     check('stati radio distinti',len(radios)==2 and [i['checked'] for i in radios]==[True,False])
     check('icona fornita dal servizio conservata',bool(next(i for i in menu['items'] if i.get('label')=='Cartella')['iconUrl']))
     icon_url=next(i for i in menu['items'] if i.get('label')=='Cartella')['iconUrl']
     (ART/'stati-menu.json').write_text(json.dumps(tray_state(),indent=2))
     wait(lambda:any(image['status']==1 and image['source']==icon_url for image in tray_state()['images']))
     check('icona D-Bus effettivamente decodificata',True)
     screenshot('tray-menu-stati')
     key('Home',[]);key('Down',[])
     check('navigazione salta la voce disabilitata',tray_state()['items'][tray_state()['selected']]['label']=='Modalità')
     key('Right',[])
     check('Destra entra nel vero sottomenu',tray_state()['subFocus'] and tray_state()['subitems'][tray_state()['subSelected']]['label']=='Normale')
     screenshot('tray-menu-sottomenu')
     key('Return',[])
     wait(lambda:'menu-4-clicked' in tray_events())
     check('Invio attiva la voce figlia e non il genitore','menu-3-clicked' not in tray_events())
     wait(lambda:tray_state()['modelReleased'])
     check('chiusura libera gli opener del menu',tray_state()['modelReleased'])
     menu=open_tray_menu()
     key('Home',[])
     for _ in range(2):key('Down',[])
     check('selezione della spunta coerente',tray_state()['items'][tray_state()['selected']]['label']=='Spunta & stato')
     key('space',[])
     wait(lambda:'menu-7-clicked' in tray_events())
     menu=open_tray_menu()
     wait(lambda:not next(i for i in tray_state()['items'] if i.get('label')=='Spunta & stato')['checked'])
     check('riapertura legge il nuovo stato dal servizio',True)
     box=tray_state()['root']
     check('menu interamente nello schermo',box['x']>=0 and box['y']>=0 and box['x']+box['width']<=tray_state()['width'] and box['y']+box['height']<=tray_state()['height']-48)
     key('Escape',[])
     click('windowsTrayToggle')
     key('Home',[]);key('Right',[])
     cmd('dito 2 2')
     key('Menu',[])
     wait(lambda:tray_state()['open'])
     check('tasto Menu apre vicino alla icona con focus e non al puntatore',tray_state()['root']['x']>tray_state()['width']/2)
     key('Escape',[])
     click('windowsTrayToggle')
     key('Home',[])
     key('F10',['Shift_L'])
     wait(lambda:tray_state()['open'])
     check('Shift F10 apre il menu della icona con focus',True)
     os.killpg(tray.pid,signal.SIGTERM);tray.wait(timeout=5)
     wait(lambda:ui_state()['trayCount']==0)
     wait(lambda:not tray_state()['open'] and tray_state()['modelReleased'])
     check('rimuovere il servizio chiude e libera il menu',True)
     call('trayCancelPointerOpen');time.sleep(.5)
     check('risposta tardiva del puntatore non riapre un menu cancellato',not tray_state()['open'])
     check('sorgenti invariati durante la prova',source_hashes()==source_snapshot)
     completed=True
     raise SystemExit(0)
 if os.environ.get('MINERVA_TEST_START_FOLDERS') == '1':
     all_folders=['settings','files','documents','downloads','music','pictures','videos','home']
     call('preference','windows11.startFolders',json.dumps(all_folders[::-1]))
     for theme in ['light','dark']:
         call('theme',theme)
         call('open','start');settle()
         controls=ui_state()['controls']
         shortcuts=[controls['windowsStartFolder-'+name] for name in all_folders]
         check('collegamenti ordinati come Windows in '+theme,all(a['x']<b['x'] for a,b in zip(shortcuts,shortcuts[1:])))
         account=controls['windowsStartAccount'];power=controls['windowsStartPower']
         check('account e collegamenti non si sovrappongono in '+theme,account['x']+account['width']/2 <= shortcuts[0]['x']-shortcuts[0]['width']/2)
         check('collegamenti separati da alimentazione in '+theme,shortcuts[-1]['x']+shortcuts[-1]['width']/2 < power['x']-power['width']/2)
         screenshot('start-cartelle-'+theme)
         call('close');settle()
     for name in all_folders:
         call('open','start');settle()
         click('windowsStartFolder-'+name)
         check(name+' chiude Start dopo il clic',ui_state()['panel']=='')
         if name=='settings':
             check('Impostazioni richiede Home Windows',ui_state()['ultimaSezione']=='w-home')
         else:
             actions=json.loads((Path(tmp)/'actions.json').read_text())
             expected=folder_paths.get(name,os.environ['HOME'])
             check(name+' invia il percorso reale senza alterarlo',actions[-1].get('action')=='open_default' and actions[-1].get('paths')==[expected],actions[-1])
     call('open','start');settle()
     check('fuoco sui collegamenti accessibile da tastiera',call('focusStartFolder','files')=='true')
     key('Tab',[])
     key('Return',[])
     check('Tab e Invio aprono Documenti',json.loads((Path(tmp)/'actions.json').read_text())[-1].get('paths')==[folder_paths['documents']])
     check('Invio chiude Start',ui_state()['panel']=='')
     call('open','start');settle()
     call('focusStartFolder','downloads')
     key('space',[])
     check('Spazio apre Download',json.loads((Path(tmp)/'actions.json').read_text())[-1].get('paths')==[folder_paths['downloads']])
     check('Spazio chiude Start',ui_state()['panel']=='')
     call('preference','windows11.startFolders','[]')
     call('open','start');settle()
     check('tutti i collegamenti possono essere nascosti',not any(k.startswith('windowsStartFolder-') for k in ui_state()['controls']))
     call('close');settle()
     check('sorgenti invariati durante la prova',source_hashes()==source_snapshot)
     completed=True
     raise SystemExit(0)
 if os.environ.get('MINERVA_TEST_START_BAR_OPTIONS') == '1':
     # La barra reale e le impostazioni reali, in un bus privato.
     for mode, width in [('hidden', None), ('icon', 40), ('label', 90), ('box', 220)]:
         call('preference', 'windows11.taskbarSearch', json.dumps(mode))
         settle()
         control = ui_state()['controls'].get('windowsSearchButton')
         check('Cerca ' + mode + ' modifica il pulsante reale', control is None if width is None else control['width'] == width, control)
         if control:
             click('windowsSearchButton')
             check('Cerca ' + mode + ' apre il pannello', ui_state()['panel'] == 'search')
             call('close')
     for keyname, control in [('taskbarTaskView','windowsOverviewButton'), ('taskbarWidgets','windowsWeatherButton'), ('taskbarShowDesktop','windowsShowDesktop')]:
         for enabled in [False, True]:
             call('preference', 'windows11.' + keyname, json.dumps(enabled))
             settle()
             check(control + ' visibilità ' + str(enabled), (control in ui_state()['controls']) == enabled)
     for alignment in ['left', 'center']:
         call('preference', 'windows11.taskbarAlignment', json.dumps(alignment))
         settle()
         band = ui_state()['controls']['windowsAppBand']
         strip = ui_state()['controls']['windowsTaskbarStrip']
         weather = ui_state()['controls']['windowsWeatherButton']
         expected = weather['x'] + weather['width']/2 + 12 + band['width']/2 if alignment == 'left' else strip['width']/2
         check('barra allineata ' + alignment, abs(band['x'] - expected) < 2, [band, expected])
     cmd('dito ' + str(primary['x'] + 400) + ' ' + str(primary['y'] + ui_state()['screenHeight'] - 24))
     cmd('dito premi destro')
     cmd('dito lascia destro')
     settle()
     call('sceltaMenu', 'taskbar-settings')
     check('menu della barra richiede la pagina Windows dedicata', ui_state()['ultimaSezione'] == 'w-barra')
     call('preference', 'windows11.taskbarAlignment', json.dumps('left'))
     for name in ['start', 'search']:
         call('open', name)
         settle()
         panel = ui_state()['controls']['windowsPanelArea']
         check(name + ' segue l’allineamento a sinistra', abs(panel['x'] - panel['width']/2 - 12) < 2, panel)
         call('close')
         settle()
     call('preference', 'windows11.taskbarAlignment', json.dumps('center'))
     call('aggiungiApp', 28)
     settle()
     call('open', 'start')
     settle()
     for layout, size, expectedY in [('pinned',24,398), ('default',18,318), ('recommended',12,238)]:
         call('preference', 'windows11.startLayout', json.dumps(layout))
         settle()
         view = json.loads(call('viewStatus'))
         check('Start ' + layout + ' mostra ' + str(size) + ' elementi', view['pageSize'] == size and len(view['tileIds']) == size, view)
         check('Start ' + layout + ' separa consigliati e griglia', view['recommendedY'] == expectedY and view['pinnedBottom'] < expectedY, view)
         key('Down', [])
         view = json.loads(call('viewStatus'))
         check('primo Giù entra nella griglia in ' + layout, view['gridFocus'] and view['selected'] == 0 and view['selectedTiles'] == [view['tileIds'][0]], view)
         key('Right', [])
         view = json.loads(call('viewStatus'))
         check('Destra evidenzia la seconda app in ' + layout, view['selected'] == 1 and view['selectedTiles'] == [view['tileIds'][1]], view)
         key('Left', [])
         for number in range(size // 6):
             key('Down', [])
         view = json.loads(call('viewStatus'))
         check('frecce passano alla seconda pagina in ' + layout, view['page'] == 1 and view['selected'] == size, view)
         check('selezione visibile sulla seconda pagina in ' + layout, view['selectedTiles'] == [view['tileIds'][0]], view)
         click('windowsStartPagePrevious')
         view = json.loads(call('viewStatus'))
         check('pagina precedente ripristina selezione e focus in ' + layout, view['page'] == 0 and view['selected'] == 0 and view['gridFocus'] and len(view['selectedTiles']) == 1, view)
         click('windowsStartPageNext')
         key('Right', [])
         view = json.loads(call('viewStatus'))
         check('frecce dopo clic pagina rimangono nella pagina scelta in ' + layout, view['page'] == 1 and view['selected'] == size + 1 and len(view['selectedTiles']) == 1, view)
         key('End', [])
         view = json.loads(call('viewStatus'))
         check('Fine seleziona l’ultima app in ' + layout, view['selected'] == 27 and view['selectedTiles'] == [view['tileIds'][-1]], view)
         key('Home', [])
         view = json.loads(call('viewStatus'))
         check('Home torna alla prima app in ' + layout, view['page'] == 0 and view['selected'] == 0 and view['selectedTiles'] == [view['tileIds'][0]], view)
         screenshot('start-layout-' + layout)
         key('b', [])
         view = json.loads(call('viewStatus'))
         check('digitare dalla griglia ritorna alla ricerca in ' + layout, view['query'] == 'b' and view['inputFocus'] and view['listMode'], view)
         key('Escape', [])
         view = json.loads(call('viewStatus'))
         check('Esc cancella ricerca senza chiudere Start in ' + layout, view['query'] == '' and not view['listMode'] and view['inputFocus'], view)
         call('close')
         settle()
         call('open', 'start')
         settle()
     call('close')
     settle()
     cmd('schermo HEADLESS-1 1280x600@60 1 0')
     call('preference', 'windows11.startLayout', json.dumps('pinned'))
     call('open', 'start')
     settle()
     key('Down', [])
     for number in range(3):
         key('Down', [])
     view = json.loads(call('viewStatus'))
     controls = ui_state()['controls']
     area = controls['windowsPinnedArea']
     selected_id = view['selectedTiles'][0]
     tile = controls['windowsPinned-' + selected_id]
     check('schermo basso scorre verso l’ultima riga', view['selected'] == 18 and view['pinnedScrollY'] > 0, view)
     check('app selezionata interamente visibile dopo scorrimento', tile['y']-tile['height']/2 >= area['y']-area['height']/2 and tile['y']+tile['height']/2 <= area['y']+area['height']/2, [tile, area])
     screenshot('start-selezione-schermo-basso')
     previous = [a for a in json.loads((Path(tmp)/'actions.json').read_text()) if a.get('action') == 'launch_app']
     key('space', [])
     def launched():
         return [a for a in json.loads((Path(tmp)/'actions.json').read_text()) if a.get('action') == 'launch_app']
     actual = wait(lambda: launched() if len(launched()) > len(previous) else None)
     check('Spazio avvia esattamente l’app evidenziata e chiude Start', len(actual) == len(previous) + 1 and actual[-1]['id'] == selected_id and ui_state()['panel'] == '', actual)
     call('preference', 'launcher.fixedApps', json.dumps([]))
     call('open', 'start')
     settle()
     key('Down', [])
     key('Return', [])
     view = json.loads(call('viewStatus'))
     check('griglia vuota conserva il focus e non avvia app', not view['gridFocus'] and view['inputFocus'] and not view['tileIds'] and len(launched()) == len(actual) and ui_state()['panel'] == 'start', view)
     check('sorgenti invariati durante la prova Start/barra', source_hashes() == source_snapshot)
     completed = True
     sys.exit(0)

 if os.environ.get('MINERVA_TEST_VOLUME_CONTEXT') == '1':
     before=json.loads(call('statusIndicators'))['rawVolume']
     def context():return json.loads(call('statusContext'))
     def right_speaker():
         c=ui_state()['controls']['windowsVolumeWheel'];screen=ui_state()
         cmd(f"dito {c['x']+screen['screenX']} {c['y']+screen['screenY']}")
         cmd('dito premi destro');cmd('dito lascia destro');settle()
     right_speaker()
     wait(lambda:context()['visible'])
     check('right speaker click offers mixer and sound settings',context()['actions']==['audio-mixer','audio-settings'],context())
     check('speaker context opens without opening Quick settings',ui_state()['panel']=='')
     strip=ui_state()['controls']['windowsTaskbarStrip']
     check('speaker context is anchored above the taskbar',context()['above'] and context()['bottom']<strip['y']-strip['height']/2,context())
     screenshot('volume-context-light')
     key('Down',[]);key('Return',[])
     wait(lambda:json.loads(call('quickState'))['page']=='audio')
     check('keyboard selects mixer from speaker context',not context()['visible'] and ui_state()['panel']=='control')
     call('close');settle();call('theme','dark');right_speaker()
     wait(lambda:context()['visible']);screenshot('volume-context-dark')
     key('Down',[]);key('Down',[]);key('Return',[])
     check('context Sound settings dispatches the real Audio section',ui_state()['ultimaSezione']=='audio' and not context()['visible'])
     right_speaker();wait(lambda:context()['visible']);key('Escape',[])
     check('Escape dismisses speaker context without opening a panel',not context()['visible'] and ui_state()['panel']=='')
     check('speaker context never changes system volume',json.loads(call('statusIndicators'))['rawVolume']==before)
     check('context sources remain unchanged during test',source_hashes()==source_snapshot)
     completed=True
     sys.exit(0)
 if os.environ.get('MINERVA_TEST_MIXER_SHORTCUT') == '1':
     os.killpg(ui.pid,signal.SIGTERM);ui.wait(timeout=5)
     runtime=Path(tmp)/'shortcut-shell.qml'
     runtime.write_text((ROOT/'tests/fixtures/windows11-shell.qml').read_text().replace('@CORE@',(ROOT/'minerva-shell/core').as_uri()).replace('@SHELL@',(ROOT/'minerva-shell/shell.qml').as_uri()))
     real=spawn(['qs','-p',str(runtime)],uienv,'shortcut-shell')
     def real_call(method,*args):
         result=subprocess.run(['qs','-p',str(runtime),'ipc','call','windows-runtime',method,*map(str,args)],env=uienv,text=True,capture_output=True,timeout=10)
         return result.stdout.strip() if result.returncode==0 else None
     def real_state():
         result=real_call('status')
         return json.loads(result) if result else {'ready':False}
     def audio_state():
         result=real_call('audioState')
         return json.loads(result) if result else {'page':'closed','audio':False}
     wait(lambda:real_state()['ready'],25)
     wait(lambda:int(cmd('scorciatoie quanti'))>50)
     key('v',['Super_L','Control_L'])
     wait(lambda:audio_state()['page']=='audio' and audio_state()['audio'])
     check('real Super Ctrl V opens the native shell audio page',real_state()['panel']=='control')
     check('mixer shortcut does not reveal Super guide',not real_state()['guide'])
     key('v',['Super_L','Control_L'])
     check('repeating mixer shortcut keeps audio page open',audio_state()['page']=='audio' and real_state()['panel']=='control')
     key('Escape',[])
     check('Escape from shortcut audio returns to main Quick settings',audio_state()['page']=='main' and real_state()['panel']=='control')
     key('Escape',[])
     wait(lambda:real_state()['panel']=='')
     key('a',['Super_L'])
     wait(lambda:real_state()['panel']=='control')
     check('normal Super A still opens the main page after mixer shortcut',audio_state()['page']=='main')
     key('v',['Super_L','Control_L'])
     wait(lambda:audio_state()['page']=='audio')
     check('shortcut switches an already open Quick settings page to audio',True)
     real_call('panel','start');settle()
     key('v',['Super_L','Control_L'])
     wait(lambda:audio_state()['page']=='audio' and real_state()['panel']=='control')
     check('shortcut replaces Start with audio without a stale page',True)
     real_call('close')
     key('v',['Super_L','Control_L'])
     wait(lambda:audio_state()['page']=='audio' and real_state()['panel']=='control')
     check('shortcut during flyout closing restores the audio page',True)
     real_call('close');settle();real_call('theme','dark')
     second_output=next(o for o in json.loads(cmd('schermi')) if o['nome']=='HEADLESS-2')
     cmd(f"dito {second_output['x']+100} {second_output['y']+100}");settle()
     key('v',['Super_L','Control_L'])
     wait(lambda:audio_state()['page']=='audio')
     check('mixer shortcut follows the active output',real_state()['screenName']=='HEADLESS-2',real_state())
     screenshot('mixer-shortcut-dark',real_state()['screenName'])
     real_call('close');settle();real_call('preset','liquid');settle()
     key('a',['Super_L'])
     check('Liquid Super A retains its own control centre',any(o['panels']['centro']['open'] for o in real_state()['islands']))
     check('shortcut source and shell stay unchanged during test',source_hashes()==source_snapshot)
     completed=True
     sys.exit(0)
 def exercise_audio_mixer():
     def mixer():return json.loads(call('mixerState'))
     def make_stream(label,media,tag,media_class='Stream/Output/Audio'):
         props={'factory.name':'support.null-audio-sink','media.class':media_class,
             'application.name':label,'media.name':media,'node.name':tag,'audio.position':['FL','FR'],'object.linger':True}
         subprocess.run(['pw-cli','create-node','adapter',json.dumps(props)],env=env,check=True,capture_output=True,timeout=5)
     call('open','control');settle();click('windowsAudioDevices')
     wait(lambda:mixer()['available'])
     check('mixer handles zero playback streams',mixer()['count']==0,mixer())
     make_stream('App di prova','Primo flusso','mixer-one')
     make_stream('App di prova','Secondo flusso','mixer-two')
     make_stream('Registrazione di prova','Non riprodurre','mixer-capture','Stream/Input/Audio')
     try:
         wait(lambda:mixer()['count']==2 and all(n['ready'] for n in mixer()['streams']))
     except AssertionError:
         print('MIXER_DIAGNOSTIC '+json.dumps(mixer()),flush=True)
         graph=subprocess.run(['pw-dump'],env=env,capture_output=True,text=True,timeout=5)
         (ART/'pipewire-graph.json').write_text(graph.stdout)
         raise
     check('same-name native streams have distinct rows',len({n['id'] for n in mixer()['streams']})==2,mixer())
     call('mixerReveal');settle()
     nodes=mixer()['streams'];selected=next(n for n in nodes if n['name']=='mixer-two');other=next(n for n in nodes if n['name']=='mixer-one')
     def server_props(identity):
         graph=json.loads(subprocess.check_output(['pw-dump'],env=env,text=True,timeout=5))
         node=next(n for n in graph if n['id']==identity)
         return node['info']['params']['Props'][0]
     wait(lambda:all(abs(n['volume']-1)<.001 for n in mixer()['streams']))
     screenshot('mixer-light')
     click('windowsAudioStreamMute-'+str(selected['id']))
     wait(lambda:any(n['id']==selected['id'] and n['muted'] for n in mixer()['streams']))
     check('mute reaches only the selected native PipeWire stream',not next(n for n in mixer()['streams'] if n['id']==other['id'])['muted'],mixer())
     check('PipeWire server confirms the selected mute',server_props(selected['id'])['mute'] and not server_props(other['id'])['mute'])
     call('mixerFocus',str(selected['id']));key('Left',[])
     wait(lambda:next(n for n in mixer()['streams'] if n['id']==selected['id'])['volume']<1)
     check('keyboard adjusts selected stream without altering another',abs(next(n for n in mixer()['streams'] if n['id']==other['id'])['volume']-1)<.001,mixer())
     check('PipeWire server confirms changed channel volumes',all(0<v<1 for v in server_props(selected['id'])['channelVolumes']) and server_props(other['id'])['channelVolumes']==[1.0,1.0])
     click('windowsAudioStreamMute-'+str(selected['id']))
     wait(lambda:not next(n for n in mixer()['streams'] if n['id']==selected['id'])['muted'])
     check('native stream unmutes explicitly',True)
     call('mixerFocus',str(selected['id']))
     subprocess.run(['pw-cli','set-param',str(selected['id']),'Props',json.dumps({'channelVolumes':[.125,.125]})],env=env,check=True,capture_output=True,timeout=5)
     wait(lambda:abs(next(n for n in mixer()['streams'] if n['id']==selected['id'])['volume']-.5)<.001)
     check('external volume updates preserve slider focus',json.loads(call('quickState'))['focus']=='windowsAudioStreamVolume-'+str(selected['id']))
     check('capture streams never enter playback mixer',all(n['name']!='mixer-capture' for n in mixer()['streams']))
     call('theme','dark');screenshot('mixer-dark')
     subprocess.run(['pw-cli','destroy',str(other['id'])],env=env,check=True,capture_output=True,timeout=5)
     wait(lambda:mixer()['count']==1)
     check('removing a native stream preserves the other identity',mixer()['streams'][0]['id']==selected['id'],mixer())
     call('close');settle()
     check('closing Quick settings destroys the stream mixer',not mixer()['available'])
     wait(lambda:mixer()['boundStreams']==0)
     check('closing mixer unbinds native playback and capture nodes',True)
     call('open','control');settle();click('windowsAudioDevices');wait(lambda:mixer()['count']==1)
     check('reopening binds the surviving stream again',mixer()['streams'][0]['id']==selected['id'],mixer())
     subprocess.run(['pw-cli','destroy',str(selected['id'])],env=env,check=True,capture_output=True,timeout=5)
     wait(lambda:mixer()['count']==0)
     check('last stream disappearing restores the empty mixer',True)
     for n in range(8):make_stream('<b>App '+str(n)+'</b>','Flusso lungo','mixer-extra-'+str(n))
     wait(lambda:mixer()['count']==8 and all(n['ready'] for n in mixer()['streams']))
     last=next(n for n in mixer()['streams'] if n['name']=='mixer-extra-7')
     call('mixerFocus',str(last['id']));settle()
     check('keyboard focus scrolls the last stream into view',json.loads(call('quickState'))['scrollY']>400)
     screenshot('mixer-long')
     call('close')
 if os.environ.get('MINERVA_TEST_AUDIO_MIXER') == '1':
     exercise_audio_mixer()
     check('UI sources remain unchanged throughout mixer test',source_hashes()==source_snapshot)
     completed=True
     sys.exit(0)
 def exercise_wifi():
     def wifi():
         return json.loads(call('wifiState'))
     def wifi_click(ssid):
         call('wifiFocus',ssid);settle()
         if 'windowsWifiConnect-'+ssid not in ui_state()['controls']:
             click('windowsWifiNetwork-'+ssid)
         if ssid not in wifi()['active']:
             click('windowsWifiConnect-'+ssid)
     def actions():
         path=Path(tmp)/'wifi-actions.json'
         return json.loads(path.read_text()) if path.exists() else []
     call('open','control');settle();click('windowsQuickArrow-wifi')
     wait(lambda:wifi().get('count')==5)
     check('Wi-Fi arrow opens an inline list with the confirmed active network',wifi()['active']==['Rete salvata'] and ui_state()['panel']=='control',wifi())
     check('Wi-Fi safely renders literal colon, backslash and prototype-like SSIDs',all(name in wifi()['ssids'] for name in ('Nome:con\\barra','__proto__')),wifi())
     check('opening the Wi-Fi list reads cache without starting a scan',not any('rescan' in a['argv'] and 'no' not in a['argv'] for a in actions()),actions())
     check('Wi-Fi tooltip explicitly renders SSIDs as plain text',wifi()['plainTooltip'],wifi())
     screenshot('wifi-light')
     wifi_click('Rete salvata')
     check('click on active network exposes Disconnect without disconnecting',wifi()['active']==['Rete salvata'] and 'windowsWifiDisconnect-Rete salvata' in ui_state()['controls'])
     call('wifiFocus','Rete aperta');settle();click('windowsWifiNetwork-Rete aperta')
     check('choosing a network exposes Connect without changing the connection',wifi()['active']==['Rete salvata'] and 'windowsWifiConnect-Rete aperta' in ui_state()['controls'])
     click('windowsWifiConnect-Rete aperta')
     wait(lambda:wifi()['active']==['Rete aperta'])
     check('open network connects without a password dialog',wifi()['passwordSsid']=='')
     wifi_click('Rete salvata')
     wait(lambda:wifi()['active']==['Rete salvata'])
     check('saved secure network connects without asking again',wifi()['passwordSsid']=='')
     wifi_click('Rete protetta')
     wait(lambda:wifi()['passwordSsid']=='Rete protetta')
     check('unknown secure network asks for a masked password',wifi()['masked'] and wifi()['focus']=='windowsWifiPassword',wifi())
     screenshot('wifi-password')
     call('wifiType','wrong-password');key('Return',[])
     wait(lambda:bool(wifi()['error']) and wifi()['connecting']=='')
     check('wrong password preserves confirmed connection and clears pending secret',wifi()['active']==['Rete salvata'] and wifi()['secretEmpty'] and wifi()['inputEmpty'],wifi())
     wifi_click('Rete protetta');wait(lambda:wifi()['passwordSsid']=='Rete protetta')
     call('wifiType','audit-test-password');key('Return',[])
     wait(lambda:wifi()['active']==['Rete protetta'])
     check('password submission connects and removes local secret copies',wifi()['secretEmpty'] and wifi()['inputEmpty'],wifi())
     check('password never appears in argv or environment',all(not a['secret_in_argv'] and not a['secret_in_environment'] for a in actions()),actions())
     wifi_click('Nome:con\\barra');wait(lambda:wifi()['passwordSsid']=='Nome:con\\barra')
     call('wifiType','audit-test-password');key('Escape',[])
     check('Escape cancels only the password form and clears input',ui_state()['panel']=='control' and wifi()['passwordSsid']=='' and wifi()['inputEmpty'],wifi())
     key('Escape',[])
     check('second Escape returns from Wi-Fi to its arrow',json.loads(call('quickState'))['page']=='main' and json.loads(call('quickState'))['focus']=='windowsQuickArrow-wifi')
     key('Escape',[])
     call('theme','dark');call('open','control');settle();click('windowsQuickArrow-wifi');wait(lambda:wifi().get('count')==5)
     screenshot('wifi-dark')
     click('windowsWifiRefresh');wait(lambda:any('rescan' in a['argv'] and 'no' not in a['argv'] for a in actions()))
     check('Refresh explicitly requests a Wi-Fi rescan',True)
     click('windowsWifiSettings')
     check('More Wi-Fi settings opens the existing Network section',ui_state()['ultimaSezione']=='network' and ui_state()['panel']=='')
     call('theme','light');call('open','control');settle();click('windowsQuickArrow-wifi');wait(lambda:wifi().get('count')==5)
     wifi_click('Nome:con\\barra');wait(lambda:wifi()['passwordSsid']=='Nome:con\\barra')
     call('wifiType','audit-test-password');call('close');settle()
     check('closing Wi-Fi destroys the pending password form',not wifi()['available'])
 if os.environ.get('MINERVA_TEST_WIFI') == '1':
     exercise_wifi()
     check('UI sources remain unchanged throughout Wi-Fi test',source_hashes()==source_snapshot)
     completed=True
     sys.exit(0)
 def exercise_bluetooth():
     first='/org/bluez/hci0/dev_00_00_00_00_00_01'
     second='/org/bluez/hci1/dev_00_00_00_00_00_01'
     def bluetooth():
         return json.loads(call('bluetoothState'))
     def control(**values):
         subprocess.run(['python3',str(ROOT/'tests/fixtures/windows11-bluetooth.py'),'control',json.dumps(values)],env=env,check=True,capture_output=True,timeout=10)
         settle()
     def actions():
         return json.loads(Path(tmp+'/bluetooth-actions.json').read_text())
     call('open','control');settle();click('windowsQuickArrow-bluetooth')
     wait(lambda:bluetooth().get('count')==3)
     check('Bluetooth arrow opens an inline page with paired devices only',ui_state()['panel']=='control' and bluetooth()['count']==3,bluetooth())
     check('same MAC on two adapters produces distinct rows',all('windowsBluetoothDevice-'+p in ui_state()['controls'] for p in (first,second)))
     check('connected device battery is visible',bluetooth()['batteries'].get('/org/bluez/hci0/dev_00_00_00_00_00_02')==65,bluetooth())
     screenshot('bluetooth-light')
     click('windowsBluetoothDevice-'+first)
     wait(lambda:bluetooth()['connected'].get(first)==True and bluetooth()['pending']=='')
     check('click connects the selected adapter device through native BlueZ',{'action':'connect','path':first} in actions() and not bluetooth()['connected'][second],actions())
     click('windowsBluetoothDevice-'+first)
     check('opening a connected device card does not disconnect it',bluetooth()['connected'][first] and 'windowsBluetoothDisconnect-'+first in ui_state()['controls'])
     click('windowsBluetoothDisconnect-'+first)
     wait(lambda:bluetooth()['connected'].get(first)==False)
     check('click on connected device disconnects only that identity',actions()[-1]=={'action':'disconnect','path':first},actions())
     control(action='fail')
     click('windowsBluetoothDevice-'+first)
     wait(lambda:bool(bluetooth()['notice']) and bluetooth()['pending']=='')
     check('BlueZ failure leaves device disconnected and permits retry',not bluetooth()['connected'][first],bluetooth())
     screenshot('bluetooth-failed')
     click('windowsBluetoothDevice-'+first)
     wait(lambda:bluetooth()['connected'].get(first)==True and bluetooth()['pending']=='')
     check('retry recovers after a native BlueZ error',bluetooth()['notice']=='',bluetooth())
     control(action='mutate',path=first,interface='org.bluez.Battery1',values={'Percentage':42})
     wait(lambda:bluetooth()['batteries'].get(first)==42)
     check('battery changes update without polling',True)
     call('bluetoothFocus',first);settle();key('Return',[])
     key('Tab',[])
     check('keyboard reaches the explicit Disconnect action',bluetooth()['focus']=='windowsBluetoothDisconnect-'+first,bluetooth())
     key('Return',[])
     wait(lambda:not bluetooth()['connected'][first] and bluetooth()['pending']=='')
     check('keyboard connection action restores focus to the same device',bluetooth()['focus']=='windowsBluetoothDevice-'+first,bluetooth())
     key('Down',[])
     check('keyboard can move to the next device after connection completes',bluetooth()['focus']=='windowsBluetoothDevice-'+second,bluetooth())
     call('bluetoothMockPower')
     click('windowsBluetoothPower')
     wait(lambda:not bluetooth()['powered'])
     check('power control reads the adapter confirmed state',not bluetooth()['powered'])
     click('windowsBluetoothPower');wait(lambda:bluetooth()['powered'])
     check('power control can enable the adapters again',True)
     key('Escape',[])
     check('Escape returns to main and restores Bluetooth arrow focus',ui_state()['panel']=='control' and json.loads(call('quickState'))['focus']=='windowsQuickArrow-bluetooth')
     key('Escape',[]);check('second Escape closes Quick settings',ui_state()['panel']=='')
     call('theme','dark');call('open','control');settle();click('windowsQuickArrow-bluetooth');screenshot('bluetooth-dark')
     click('windowsBluetoothSettings')
     check('More Bluetooth settings opens the existing section',ui_state()['ultimaSezione']=='bluetooth' and ui_state()['panel']=='')
     call('theme','light');call('open','control');settle();click('windowsQuickArrow-bluetooth')
     control(action='remove',path=first);wait(lambda:bluetooth()['count']==2)
     check('removed device disappears without disturbing another adapter',bluetooth()['connected'].get(second)==False and first not in bluetooth()['connected'],bluetooth())
     control(action='many');wait(lambda:bluetooth()['count']==22)
     check('long Bluetooth list exposes a draggable scrollbar','windowsBluetoothScrollBar' in ui_state()['controls'])
     call('close');settle()
     check('Bluetooth page never launches discovery scans',not any(a.get('key')=='Discovering' for a in actions()))
     check('native Bluetooth fixture has not written outside its private bus',env['DBUS_SYSTEM_BUS_ADDRESS']==env['DBUS_SESSION_BUS_ADDRESS'])
 if os.environ.get('MINERVA_TEST_BLUETOOTH') == '1':
     exercise_bluetooth()
     check('UI sources remain unchanged throughout Bluetooth test',source_hashes()==source_snapshot)
     completed=True
     sys.exit(0)
 def exercise_quick_tiles():
     saved=json.loads(call('quickRadios'))
     for theme in ('light','dark'):
         call('close');call('theme',theme);settle();call('open','control');settle()
         for on in (False,True):
             call('quickTileState',str(on).lower(),str(on).lower());settle()
             controls=ui_state()['controls']
             for name in ('wifi','bluetooth'):
                 button=controls['windowsQuick-'+name]
                 arrow=controls['windowsQuickArrow-'+name]
                 top=button['y']-button['height']/2
                 bottom=button['y']+button['height']/2
                 check(theme+' '+name+' '+str(on)+' arrow stays inside the button border',arrow['y']-arrow['height']/2>top and arrow['y']+arrow['height']/2<bottom and arrow['x']+arrow['width']/2<button['x']+button['width']/2,{'button':button,'arrow':arrow})
             screenshot('quick-tiles-'+theme+'-'+str(on))
         for name,section in (('wifi','network'),('bluetooth','bluetooth')):
             call('close');call('open','control');settle()
             before=json.loads(call('quickRadios'))
             click('windowsQuickArrow-'+name)
             routed=ui_state()['panel']=='control' and (json.loads(call('wifiState'))['available'] if name=='wifi' else json.loads(call('bluetoothState'))['available'])
             check(theme+' '+name+' arrow opens its destination without toggling radio',routed and json.loads(call('quickRadios'))==before)
     call('quickTileState',str(saved['wifi']).lower(),str(saved['bluetooth']).lower())
     call('close');call('theme','light');settle()
 if os.environ.get('MINERVA_TEST_QUICK_TILES') == '1':
     exercise_quick_tiles()
     check('UI sources remain unchanged throughout quick tiles test',source_hashes()==source_snapshot)
     completed=True
     sys.exit(0)
 def exercise_volume_overdrive():
     hardware=json.loads(call('statusIndicators'))['rawVolume']
     def volume():
         return json.loads(call('volumeState'))
     for theme in ('light','dark'):
         call('close');call('theme',theme);settle()
         call('open','control');settle()
         call('volumeSetup',75,100)
         st=volume()
         check(theme+' normal volume has no extra range',not st['amplified'] and not st['rangeVisible'] and not st['extraVisible'] and st['text']=='75%',st)
         call('volumeSetup',100,150)
         st=volume()
         check(theme+' 100 percent marks the start of amplification',abs(st['normalFraction']-2/3)<.001 and st['rangeVisible'] and not st['extraVisible'],st)
         call('volumeSetup',125,150)
         st=volume()
         check(theme+' amplification fills only the extra segment in red',st['amplified'] and 0<st['extraWidth']<st['rangeWidth'] and st['handleColor']==st['extraColor']==st['textColor'] and st['text']=='125%',st)
         check(theme+' screen reader announces amplification','amplificazione' in st['accessible'],st)
         screenshot('volume-amplification-'+theme)
         call('volumeSetup',150,150)
         st=volume()
         check(theme+' configured maximum fills the entire extra range',abs(st['extraWidth']-st['rangeWidth'])<.01 and st['text']=='150%',st)
         call('volumePress',.5)
         st=volume()
         check(theme+' click below threshold removes amplification highlight',not st['amplified'] and not st['extraVisible'] and 65<st['value']<85 and bool(st['requests']),st)
         call('volumePress',.9)
         st=volume()
         check(theme+' click above threshold requests amplified volume',st['amplified'] and 125<st['value']<145 and st['requests'][-1]==st['value'],st)
         call('volumeSetup',100,100)
         call('volumePress',1)
         check(theme+' disabling amplification limits the slider to 100',volume()['value']<=100 and not volume()['rangeVisible'])
         check(theme+' click at slider edge does not dismiss the flyout',ui_state()['panel']=='control')
         click('windowsVolumePercent')
         check(theme+' click on passive panel text stays inside the flyout',ui_state()['panel']=='control')
     screen=ui_state()
     cmd(f"dito {screen['screenX']+2} {screen['screenY']+2}");cmd('dito premi');cmd('dito lascia');settle()
     check('click outside the flyout still dismisses it',ui_state()['panel']=='')
     call('theme','light');settle()
     check('overdrive tests never change actual PipeWire volume',json.loads(call('statusIndicators'))['rawVolume']==hardware)
 if os.environ.get('MINERVA_TEST_VOLUME_OVERDRIVE') == '1':
     exercise_volume_overdrive()
     check('UI sources remain unchanged throughout overdrive test',source_hashes()==source_snapshot)
     completed=True
     sys.exit(0)
 def exercise_volume_wheel():
     call('close');settle()
     def wheel(where,dy,dx=0):
         call('wheelInputAt',where,dx,dy)
         return json.loads(call('wheelState'))
     def setup(value,muted=False):
         call('wheelSetup',value,str(muted).lower())
     hardware=json.loads(call('statusIndicators'))['rawVolume']
     setup(50)
     st=wheel('windowsVolumeIcon',120)
     check('wheel up over volume raises by two points',st['volume']==52,st)
     check('wheel down lowers volume without opening Quick settings',wheel('windowsVolumeIcon',-120)['volume']==50 and ui_state()['panel']=='')
     check('three wheel notches retain their magnitude',wheel('windowsVolumeIcon',360)['volume']==56)
     before=json.loads(call('wheelState'))
     check('scroll over network leaves volume untouched',wheel('windowsNetworkIcon',120)==before)
     check('horizontal scroll leaves volume untouched',wheel('windowsVolumeIcon',0,120)==before)
     setup(99)
     check('wheel volume never exceeds 100 percent',wheel('windowsVolumeIcon',120)['volume']==100)
     setup(1)
     check('wheel volume never goes below zero',wheel('windowsVolumeIcon',-120)['volume']==0)
     setup(50,True)
     st=wheel('windowsVolumeIcon',120)
     check('raising muted volume requests the existing unmute behaviour',st['volume']==52 and not st['muted'],st)
     setup(50)
     for _ in range(3):
         st=wheel('windowsVolumeIcon',30)
     check('partial wheel notches do not multiply volume changes',st['volume']==50 and not st['requests'],st)
     check('four partial wheel events become one notch',wheel('windowsVolumeIcon',30)['volume']==52)
     wheel('windowsVolumeIcon',30)
     wheel('windowsNetworkIcon',120)
     for _ in range(3):
         st=wheel('windowsVolumeIcon',30)
     check('leaving the speaker clears an incomplete wheel notch',st['volume']==52,st)
     click('windowsVolumeIcon')
     check('wheel hit area preserves left click to open Quick settings',ui_state()['panel']=='control')
     call('close');settle()
     call('systemState',json.dumps({'batteryPercent':75}))
     setup(50)
     check('scroll over battery leaves volume untouched',wheel('windowsBatteryIcon',120)['volume']==50)
     check('speaker wheel still works when battery changes the cluster width',wheel('windowsVolumeIcon',120)['volume']==52)
     call('systemState','{}')
     check('wheel tests never change actual PipeWire volume',json.loads(call('statusIndicators'))['rawVolume']==hardware)
 if os.environ.get('MINERVA_TEST_VOLUME_WHEEL') == '1':
     exercise_volume_wheel()
     check('UI sources remain unchanged throughout wheel test',source_hashes()==source_snapshot)
     completed=True
     sys.exit(0)
 def exercise_quick_audio():
     def quick():
         return json.loads(call('quickState'))
     def actions():
         path=Path(tmp)/'actions.json'
         return json.loads(path.read_text()) if path.exists() else []
     def audio_actions(action):
         return [a for a in actions() if a['action']==action]
     def inject(**values):
         with socket.socket(socket.AF_UNIX) as client:
             client.settimeout(5)
             client.connect(sock)
             client.sendall((json.dumps({'action':'fixture_audio',**values})+'\n').encode())
             client.recv(65536)
         settle()
     before=len(audio_actions('subscribe_audio'))
     call('open','control');settle()
     check('Quick settings main page has no audio subscription',len(audio_actions('subscribe_audio'))==before)
     old_section=ui_state()['ultimaSezione']
     click('windowsAudioDevices')
     wait(lambda:quick()['count']==3 and not quick()['loading'])
     check('audio arrow opens an inline page without launching Settings',quick()['page']=='audio' and ui_state()['ultimaSezione']==old_section)
     check('audio subscribes only once on opening',len(audio_actions('subscribe_audio'))==before+1)
     check('output selector shows the system confirmed device',quick()['defaultSink']=='speakers')
     screenshot('quick-audio-light')
     key('Tab',[])
     check('Tab reaches first output',quick()['focus']=='windowsAudioSink-speakers',quick())
     key('Down',[])
     check('Down focuses the next output',quick()['focus']=='windowsAudioSink-headphones',quick())
     key('Return',[])
     wait(lambda:quick()['defaultSink']=='headphones')
     check('Enter selects the focused output through IPC',audio_actions('system_audio_select')[-1]=={'action':'system_audio_select','kind':'sink','name':'headphones'})
     count=len(audio_actions('system_audio_select'))
     click('windowsAudioSink-headphones')
     check('clicking the current output does not issue redundant changes',len(audio_actions('system_audio_select'))==count)
     inject(state={'ok':True,'defaultSink':'headphones','sinks':[{'name':'speakers','description':'Altoparlanti'},{'name':'headphones','description':'Cuffie USB aggiornate'},{'name':'hdmi','description':'Monitor HDMI'}]})
     check('device description updates preserve keyboard focus',quick()['focus']=='windowsAudioSink-headphones',quick())
     inject(stall=True)
     click('windowsAudioSink-hdmi')
     check('pending output change leaves the confirmed mark in place',quick()['selecting'] and quick()['defaultSink']=='headphones',quick())
     wait(lambda:not quick()['selecting'] and bool(quick()['error']),timeout=13)
     check('unanswered change times out and restores controls',quick()['defaultSink']=='headphones' and 'windowsAudioRetry' in ui_state()['controls'],quick())
     inject(fail=True)
     click('windowsAudioSink-hdmi')
     wait(lambda:bool(quick()['error']))
     check('a failed switch preserves confirmed output and enables retry',quick()['defaultSink']=='headphones' and not quick()['selecting'] and 'windowsAudioRetry' in ui_state()['controls'],quick())
     screenshot('quick-audio-failure')
     click('windowsAudioRetry')
     wait(lambda:not quick()['loading'])
     check('retry clears the error after a successful read',quick()['error']=='',quick())
     inject(state={'ok':True,'defaultSink':'speakers','sinks':[{'name':'speakers','description':'Altoparlanti aggiornati'}]})
     check('hotplug removes missing outputs without retaining stale selection',quick()['count']==1 and quick()['defaultSink']=='speakers' and 'windowsAudioSink-hdmi' not in ui_state()['controls'],quick())
     inject(state={'ok':True,'defaultSink':'','sinks':[]})
     check('zero outputs is handled as an empty state',quick()['count']==0 and not quick()['loading'],quick())
     many=[{'name':'output-'+str(n),'description':'Uscita audio '+str(n)} for n in range(20)]
     inject(state={'ok':True,'defaultSink':'output-0','sinks':many})
     check('many outputs expose a draggable scrollbar','windowsAudioScrollBar' in ui_state()['controls'],ui_state()['controls'])
     click('windowsAudioSink-output-0')
     for _ in range(19):
         key('Down',[])
     check('keyboard reaches the last output and scrolls it into view',quick()['focus']=='windowsAudioSink-output-19',quick())
     screenshot('quick-audio-scrolled')
     for _ in range(19):
         key('Up',[])
     check('Up returns to the first output',quick()['focus']=='windowsAudioSink-output-0',quick())
     c=ui_state()['controls']['windowsAudioScrollBar'];screen=ui_state()
     top=c['y']-c['height']/2+16
     bottom=c['y']+c['height']/2-16
     cmd(f"dito {c['x']+screen['screenX']} {top+screen['screenY']}")
     cmd('dito premi')
     cmd(f"dito {c['x']+screen['screenX']} {bottom+screen['screenY']}")
     cmd('dito lascia');settle()
     check('dragging the audio scrollbar reaches the bottom',quick()['scrollY']>=quick()['scrollMaximum']-2,quick())
     key('Escape',[])
     wait(lambda:quick()['page']=='main')
     check('Escape returns from audio and keeps Quick settings open',ui_state()['panel']=='control' and quick()['focus']=='windowsAudioDevices',quick())
     wait(lambda:len(audio_actions('unsubscribe_audio'))==before+1)
     check('returning from audio unsubscribes immediately',True)
     key('Escape',[])
     check('second Escape closes Quick settings',ui_state()['panel']=='')
     inject(state={'ok':True,'defaultSink':'speakers','sinks':[{'name':'speakers','description':'Altoparlanti'}]})
     call('theme','dark');call('open','control');settle();click('windowsAudioDevices')
     wait(lambda:quick()['count']==1)
     screenshot('quick-audio-dark')
     call('close');settle()
     check('closing the flyout also releases audio subscription',len(audio_actions('unsubscribe_audio'))==before+2)
     call('theme','light')
     call('open','control');settle();click('windowsAudioDevices');click('windowsAudioSettings')
     check('More sound settings opens the existing Audio page and closes flyout',ui_state()['ultimaSezione']=='audio' and ui_state()['panel']=='')
     check('audio page has no polling while closed',len(audio_actions('subscribe_audio'))==before+3 and len(audio_actions('unsubscribe_audio'))==before+3)
 if os.environ.get('MINERVA_TEST_QUICK_AUDIO') == '1':
     exercise_quick_audio()
     check('UI sources remain unchanged throughout audio test',source_hashes()==source_snapshot)
     completed=True
     sys.exit(0)
 if os.environ.get('MINERVA_TEST_DESKTOP_SAFETY') == '1':
     original = exercise_previews()
     call('preference', 'windows11.desktops', json.dumps([1, 2, 3]))
     call('open', 'overview');settle()
     click('windowsTaskViewWindow-' + original, 'destro')
     click('windowsTaskViewMoveTo-3');settle()
     check('a real menu moves the addressed window to desktop 3', item(original)['scrivania'] == 3)
     click('windowsDesktop-3', 'destro')
     click('windowsDesktopMenu-close')
     wait(lambda: item(original)['scrivania'] == 2 and 3 not in ui_state()['desktops'])
     check('closing an occupied inactive desktop moves its window and closes no app', len(windows()) == 4 and state()['scrivania'] == 1)
     click('windowsDesktop-2');wait(lambda:state()['scrivania']==2)
     click('windowsDesktop-2', 'destro');click('windowsDesktopMenu-close')
     wait(lambda:state()['scrivania']==1 and item(original)['scrivania']==1 and ui_state()['desktops']==[1])
     check('closing an occupied active desktop restores its windows on the neighbour', len(windows())==4)
     screenshot('overview-desktop-recovered')
     check('UI sources remain unchanged throughout desktop safety test', source_hashes()==source_snapshot)
     completed=True
     sys.exit(0)
 if os.environ.get('MINERVA_TEST_PREVIEWS_ONLY')=='1':
     exercise_previews()
     check('UI source files remain unchanged throughout preview test',source_hashes()==source_snapshot)
     completed=True
     sys.exit(0)
 check('fresh Windows does not inherit Liquid watercolor',ui_state()['settings']['windows']['effetto']=='nessuno')
 check('fresh Windows has no inherited hot corners',all(v=='niente' for v in ui_state()['settings']['riva']['angoli'].values()))
 call('prepare');settle()
 call('preset','liquid');settle()
 call('preference','windows.effetto','"acquerello"');call('preference','riva.angoli.altoDx','"stanze"');call('preference','desktop.animations','false');call('preference','dock.iconSize','61');call('preference','windows.tilingGap','17');settle()
 call('preset','windows');settle()
 check('UI switches to Windows with its own effect and corners',ui_state()['settings']['windows']['effetto']=='nessuno' and ui_state()['settings']['riva']['angoli']['altoDx']=='niente')
 check('UI preserves Windows dock and tiling preferences',ui_state()['settings']['dock']['iconSize']==48 and ui_state()['settings']['windows']['tilingGap']==8)
 call('preference','windows.effetto','"acquerello"');call('preset','liquid');settle()
 check('watercolor can independently be enabled in both presets',ui_state()['settings']['windows']['effetto']=='acquerello')
 check('UI restores customized Liquid layout and behavior',ui_state()['settings']['dock']['iconSize']==61 and ui_state()['settings']['windows']['tilingGap']==17 and ui_state()['settings']['riva']['angoli']['altoDx']=='stanze')
 call('preset','windows');settle()
 check('Windows retains its own newly enabled watercolor',ui_state()['settings']['windows']['effetto']=='acquerello')
 call('preference','windows.effetto','"nessuno"');settle()
 subprocess.run(['tests/compila-shell.sh'],cwd=ROOT,env=uienv,check=True,timeout=180,stdout=open(ART/'qml-compile.log','w'))
 check('all QML components compile on real Wayland backend',True)
 def indicators():
     return json.loads(call('statusIndicators'))
 # Gli ingressi sono copie del renderer: nessun comando audio/rete reale.
 sensor_before=indicators()
 for volume,muted,icon in [(0,False,'volumeZero'),(1,False,'volumeLow'),(33,False,'volumeLow'),(34,False,'volume'),(150,False,'volume'),(75,True,'muted')]:
     call('systemState',json.dumps({'volume':volume,'muted':muted}));settle()
     check('taskbar volume '+str(volume)+' muted '+str(muted)+' has proper Fluent icon',indicators()['volume']==icon,indicators())
 for wired,connected,strength,icon in [(False,False,0,'globe'),(True,True,100,'network'),(False,True,10,'wifiWeak'),(False,True,50,'wifiMedium'),(False,True,90,'wifi')]:
     call('systemState',json.dumps({'wired':wired,'connected':connected,'strength':strength}));settle()
     check('taskbar network state uses '+icon,indicators()['network']==icon,indicators())
 batteries=[(-1,False,False,'absent',0),(0,False,False,'critical',0),(5,False,True,'critical',.05),(6,False,False,'normal',.06),(20,False,False,'normal',.2),(75,False,True,'saving',.75),(100,False,False,'normal',1),(150,False,False,'normal',1),(2,True,True,'charging',.02)]
 for percent,charging,saving,name,fraction in batteries:
     call('systemState',json.dumps({'batteryPercent':percent,'batteryCharging':charging,'energySaving':saving}));settle()
     actual=indicators()
     check('taskbar battery '+str(percent)+' charging '+str(charging)+' saving '+str(saving),actual['battery']==name and abs(actual['fraction']-fraction)<.001 and actual['hasBattery']==(percent>=0),actual)
 call('systemState',json.dumps({'batteryPercent':62,'batteryCharging':False,'energySaving':False,'volume':25,'muted':False,'wired':False,'connected':True,'strength':50}));settle()
 no_charge_width=indicators()['statusWidth']
 for theme in ['light','dark']:
     call('theme',theme);settle()
     for charging,saving,percent in [(False,False,62),(True,False,62),(False,True,62),(False,False,3)]:
         call('systemState',json.dumps({'batteryPercent':percent,'batteryCharging':charging,'energySaving':saving}));settle()
         actual=indicators();colors=ui_state()['colors']
         check(theme+' battery '+actual['battery']+' remains readable',contrast(actual['batteryColor'],colors['taskbar'])>=2.99,(actual,colors))
         screenshot('taskbar-'+theme+'-'+actual['battery'])
 call('systemState',json.dumps({'batteryPercent':62,'batteryCharging':True,'energySaving':False}));settle()
 check('charging overlay adds space without hiding battery fill',indicators()['statusWidth']>no_charge_width,indicators())
 fixed_clock={'date':'2026-10-11T13:05:00','locale':'it_IT','format24':True,'unread':0,'quiet':False}
 call('clockState',json.dumps(fixed_clock));settle()
 check('taskbar uses Italian short date and 24-hour time',indicators()['date']=='11/10/2026' and indicators()['time']=='13:05',indicators())
 call('clockState',json.dumps({'locale':'en_US','format24':False}));settle()
 check('taskbar date follows locale and 12-hour preference',indicators()['date'].startswith('10/11/') and indicators()['time']=='1:05 PM',indicators())
 for unread,quiet,icon in [(0,False,'bell'),(3,False,'bellFilled'),(0,True,'bellSnooze'),(3,True,'bellSnooze')]:
     call('clockState',json.dumps({'unread':unread,'quiet':quiet}));settle()
     check('taskbar notification unread '+str(unread)+' quiet '+str(quiet),indicators()['notification']==icon,indicators())
     check('notification indicator fits its clock button',ui_state()['controls']['windowsNotificationIcon']['x']+8 <= ui_state()['controls']['windowsClockButton']['x']+ui_state()['controls']['windowsClockButton']['width']/2,ui_state()['controls'])
 call('systemState','{}');call('clockState','{}');call('theme','light');settle()
 actual=indicators()
 check('status rendering tests did not change shared hardware state',actual['rawVolume']==sensor_before['rawVolume'] and actual['rawMuted']==sensor_before['rawMuted'] and actual['rawBattery']==sensor_before['rawBattery'],(sensor_before,actual))
 exercise_quick_tiles()
 exercise_volume_wheel()
 exercise_volume_overdrive()
 exercise_quick_audio()
 exercise_wifi()
 exercise_bluetooth()
 exercise_audio_mixer()
 call('theme','light');settle()
 click('windowsStatusButton');check('status block opens Quick settings with real click',ui_state()['panel']=='control',ui_state());key('Escape',[])
 click('windowsClockButton');check('clock block opens calendar with real click',ui_state()['panel']=='calendar',ui_state());key('Escape',[])
 (ART/'status-indicators.json').write_text(json.dumps(actual,indent=2))
 exercise_start_views()
 if os.environ.get('MINERVA_TEST_START_VIEWS_ONLY')=='1':
     check('UI source files remain unchanged throughout test',source_hashes()==source_snapshot)
     completed=True
     sys.exit(0)
 # Un fondale chiaro sintetico isola l'ombra senza dipendere da Bloom
 # (asset Microsoft non distribuibile). Sul fallback scuro una vera ombra
 # nera non produce il contrasto richiesto: era un falso negativo del banco.
 shadow_backdrop=Path(tmp)/'shadow-backdrop.png'
 backdrop=Image.new('RGB',(1280,720),(210,220,230))
 from PIL import ImageDraw
 draw=ImageDraw.Draw(backdrop)
 for y in range(0,720,160):
     for x in range(0,1280,160):
         if (x//160+y//160)%2:
             draw.rectangle((x,y,x+159,y+159),fill=(160,175,190))
 backdrop.save(shadow_backdrop)
 call('preference','desktop.wallpaper',json.dumps(str(shadow_backdrop)))
 call('preference','desktop.wallpaperMode','"image"')
 call('preference','windows11.wallpaper','"current"');time.sleep(1.3)
 # Il blur cambia i pixel dello sfondo: si isola l'ombra, poi si prova
 # separatamente il materiale Acrylic col compositore che lo conferma.
 call('preference','windows11.acrylic','false');time.sleep(.7)
 for theme in ('light','dark'):
     call('close');call('theme',theme);settle()
     background=screenshot('shadow-background-'+theme)
     call('open','control');settle()
     foreground=screenshot('shadow-control-'+theme)
     area=ui_state()['controls']['windowsPanelArea']
     left=round(area['x']-area['width']/2);center=round(area['y'])
     with Image.open(background) as before,Image.open(foreground) as after:
         before=before.convert('RGB');after=after.convert('RGB')
         attenuation=[]
         for distance in (2,8,28):
             x=left-distance
             differences=[sum(before.getpixel((x,y)))-sum(after.getpixel((x,y))) for y in range(center-12,center+13)]
             attenuation.append(sum(differences)/(len(differences)*3))
     check(theme+' shadow renders outside panel with a soft gradient',attenuation[0]>2 and attenuation[0]>attenuation[1]>attenuation[2] and attenuation[2]<1,attenuation)
     call('close');settle()
     removed=screenshot('shadow-closed-'+theme)
     with Image.open(background) as before,Image.open(removed) as after:
         bounds=(left-30,center-12,left-1,center+13)
         check(theme+' shadow leaves no stale pixels after closing',before.crop(bounds).tobytes()==after.crop(bounds).tobytes())
 call('theme','light');call('preference','windows11.wallpaper','"auto"');settle()
 # Actual rendered frames, rather than waiting until after the animation and
 # treating the correct final state as proof that a transition occurred.
 call('preference','desktop.animations','true');settle()
 for name in ('start','search','control','calendar','weather','overview'):
     call('motionBegin',name);settle()
     opening=json.loads(call('motionStop'))
     check(name+' entrance renders intermediate frames',any(0<f['progress']<1 and f['animating'] and f['loaded'] for f in opening['frames']),opening)
     check(name+' entrance settles without ongoing animation',opening['state']['presented'] and opening['state']['progress']==1 and not opening['state']['animating'],opening)
     call('motionBegin',name);settle()
     closing=json.loads(call('motionStop'))
     first=closing['frames'][0]
     check(name+' exit releases input immediately and retains its image',first['panel']=='' and not first['enabled'] and not first['keyboard'] and first['loaded'] and first['presented'],closing)
     check(name+' exit renders fade frames then unloads',any(0<f['progress']<1 and f['loaded'] for f in closing['frames']) and not closing['state']['loaded'] and not closing['state']['presented'] and not closing['state']['animating'],closing)
 call('motionBegin','start');time.sleep(.04);call('motionClose');time.sleep(.02);call('open','start');settle()
 reopened=json.loads(call('motionStop'))
 check('reopening during exit cancels obsolete dismissal',reopened['state']['panel']=='start' and reopened['state']['loaded'] and reopened['state']['progress']==1,reopened)
 call('motionBegin','control');settle();switching=json.loads(call('motionStop'))
 check('switching an open flyout animates only the new panel',switching['state']['panel']=='control' and switching['state']['rendered']=='control' and any(0<f['progress']<1 for f in switching['frames']),switching)
 call('motionBurst','start');settle();burst=json.loads(call('motionStop'))
 check('rapid repeated toggles preserve the final requested panel',burst['state']['panel']=='start' and burst['state']['loaded'] and burst['state']['progress']==1,burst)
 call('motionImmediateClose');immediate=json.loads(call('motionStop'))
 check('lock and preset removal erase flyout without an exit image',not immediate['state']['presented'] and not immediate['state']['loaded'] and not immediate['state']['animating'],immediate)
 call('motionBegin','start');call('preference','desktop.animations','false');settle();disabled=json.loads(call('motionStop'))
 check('disabling animations mid-transition settles the visible panel',disabled['state']['progress']==1 and disabled['state']['loaded'] and not disabled['state']['animating'],disabled)
 call('motionBegin','start');instant=json.loads(call('motionStop'))
 check('disabled animations close and unload immediately',not instant['frames'][0]['presented'] and not instant['frames'][0]['loaded'] and not instant['state']['animating'],instant)
 (ART/'motion.json').write_text(json.dumps({'opening':opening,'closing':closing,'reopened':reopened,'switching':switching,'burst':burst,'immediate':immediate,'disabled':disabled,'instant':instant},indent=2))
 for name in ['start','search','control','calendar','weather','screenshot','overview']:
     call('open',name);settle();check(name+' panel opens',ui_state()['panel']==name)
     screenshot(name+'-light')
     key('Escape',[]);check(name+' closes with real Escape',ui_state()['panel']=='')
 call('theme','dark');wait(lambda:ui_state()['theme']);time.sleep(1.3);call('open','start');settle()
 screenshot('start-dark')
 check('dark theme applied without restart',ui_state()['theme'])
 liquid_accent=ui_state()['settings']['shell']['accent']
 call('close');call('preference','windows11.wallpaper','"light"')
 for theme in ('light','dark'):
     call('theme',theme);call('preference','windows11.accentOnStart','true');call('open','control');settle()
     for color in ('#000000','#FFFFFF','#FFFF00','#00FF00','#FF0000','#8764B8','#C239B3','#777777','#0067C0','#123456'):
         call('preference','windows11.accent',json.dumps(color))
         settle()
         colors=wait(lambda:ui_state()['colors'] if ui_state()['colors']['chosen'].lower()==color.lower() else None)
         check(theme+' '+color+' filled controls use readable ink',contrast(colors['accent'],colors['onAccent'])>=4.5 and colors['wifiGlyph']==colors['onAccent'],colors)
         check(theme+' '+color+' accent text and indicator remain visible',contrast(colors['ink'],colors['field'])>=4.5 and contrast(colors['indicator'],colors['taskbar'])>=3,colors)
         if theme=='dark':
             # Come Windows: Start e flyout prendono Dark1, la barra Dark2 (AccentAcrylic…Default/Base),
             # quindi i due toni sono diversi; il testo bianco deve reggere su tutti e due (Claude, 11 ottobre 2026).
             check(theme+' '+color+' tinted surface keeps text readable',colors['tinted'] and colors['start']!=colors['surface'] and contrast('#ffffff',colors['start'])>=4.5 and contrast('#ffffff',colors['taskbar'])>=4.5 and contrast(colors['muted'],colors['start'])>=4.5,colors)
         else:
             check(theme+' '+color+' light mode retains neutral surfaces',not colors['tinted'] and colors['start']==colors['surface'] and len(set(colors['taskbar'][1:3*2+1][i:i+2] for i in (0,2,4)))==1,colors)
     call('close')
 check('Windows color changes preserve Liquid accent',ui_state()['settings']['shell']['accent']==liquid_accent)
 call('theme','dark');call('preference','windows11.accent','"#8764B8"');call('open','start');settle()
 check('Start renders the selected tinted surface',ui_state()['colors']['actualStart']==ui_state()['colors']['start'])
 screenshot('start-accent-purple');call('close')
 call('preference','windows11.accentOnStart','false');call('preference','windows11.accent','"auto"');call('theme','light');call('preference','windows11.wallpaper','"auto"');settle()

 # ── Niente quadrato sull'ultima cosa cliccata (Claude, 11 ottobre 2026) ──
 # Il contorno del fuoco si vede solo arrivandoci con la tastiera.
 call('close');settle();click('windowsSearchButton')
 f=ui_state()['focoBarra']['windowsSearchButton']
 check('a mouse click leaves no focus square on the taskbar button',f and not f['contorno'],f)
 call('close');settle()

 # ── Le notizie nei Widget (Claude, 11 ottobre 2026) ──
 # Il demone di prova risponde con due notizie per interesse, senza rete.
 call('close');call('open','weather')
 c=wait(lambda:(lambda k:k if 'windowsNewsCard-0' in k else None)(ui_state()['controls']))
 schede=[k for k in ui_state()['controls'] if k.startswith('windowsNewsCard-')]
 check('Widgets show a news card per article under weather and calendar',len(schede)==12 and c['windowsNewsCard-0']['y']>c['windowsWeatherCard']['y'],len(schede))
 images=wait(lambda:(lambda entries:entries if len(entries)==6 and all(i['status']==1 for i in entries) else None)(json.loads(call('newsImages'))))
 check('every supplied news image reaches Image.Ready',len(images)==6,images)
 screenshot('widgets-notizie')
 scroll=json.loads(call('scrollState','windowsWidgetsScrollBar'))
 check('Widgets exposes a visible draggable scrollbar',scroll.get('visible') and scroll['maxY']>200,scroll)
 c=ui_state()['controls']['windowsWidgetsScrollBar'];screen=ui_state()
 x=c['x']+screen['screenX'];top=c['y']-c['height']/2+screen['screenY']
 cmd(f"dito {x} {top+12}");cmd('dito premi')
 cmd(f"dito {x} {top+c['height']-12}");cmd('dito lascia');settle()
 scroll=json.loads(call('scrollState','windowsWidgetsScrollBar'))
 check('dragging Widgets scrollbar reaches lower news',scroll['y']>scroll['maxY']*.8,scroll)
 screenshot('widgets-notizie-scroll')
 call('scrollTo','windowsWidgetsScrollBar','windowsNewsCustomise');settle()
 click('windowsNewsCustomise')
 st=ui_state();check('Personalise interests opens the Preset settings page',st['ultimaSezione']=='preset' and st['panel']=='',(st['ultimaSezione'],st['panel']))
 call('preference','notizie.interessi',json.dumps(['sport']));settle()
 call('open','weather')
 wait(lambda:(lambda k:k if 'windowsNewsCard-0' in k and 'windowsNewsCard-2' not in k else None)(ui_state()['controls']))
 check('only the chosen interests are shown',len([k for k in ui_state()['controls'] if k.startswith('windowsNewsCard-')])==2)
 call('preference','notizie.interessi',json.dumps(['attualita','tecnologia','scienza','economia','sport','cultura']));call('close');settle()

 # ── Il piede dello Start come Windows 11 (Claude, 11 ottobre 2026) ──
 # Il pulsante di alimentazione apre il suo menu SOPRA di sé, un clic esegue;
 # il nome apre il menu dell'account. Niente pannello a destra, niente
 # secondo clic di conferma.
 call('close');call('open','start');settle()
 click('windowsStartPower')
 st=ui_state();c=st['controls'];m=c.get('windowsStartPowerMenu');b=c['windowsStartPower']
 check('Start power opens its menu above the button',m is not None and m['y']+m['height']/2<=b['y']-b['height']/2+1 and st['panel']=='start',(m,b,st['panel']))
 check('Start power menu lists Windows actions',all(('windowsStartPower-'+n) in c for n in ('accesso','sospendi','spegni','riavvia')),sorted(k for k in c if k.startswith('windowsStartPower')))
 click('windowsStartPower-sospendi')
 st=ui_state();check('one click on Sleep runs it and closes Start',st['ultimaAzione']=='sospendi' and st['panel']=='',(st['ultimaAzione'],st['panel']))
 call('open','start');settle();click('windowsStartAccount')
 c=ui_state()['controls'];check('account button opens its menu',all(('windowsStartPower-'+n) in c for n in ('utente','blocca','esci')),sorted(k for k in c if k.startswith('windowsStartPower')))
 key('Escape',[]);settle();st=ui_state()
 check('Escape closes the small menu and keeps Start open','windowsStartPowerMenu' not in st['controls'] and st['panel']=='start',st['panel'])
 click('windowsStartAccount');click('windowsStartPower-blocca')
 st=ui_state();check('one click on Lock runs it',st['ultimaAzione']=='blocca' and st['panel']=='',(st['ultimaAzione'],st['panel']))
 # Il nome di chi usa il computer, non «Account locale» (il manutentore, 12 ottobre 2026).
 call('open','start');settle()
 conto=json.loads(call('startAccount'))
 check('Start footer shows the user name with a portrait',conto and conto['avatar'] and conto['testo'] not in ('','Account locale','Local account'),conto)
 call('close');settle()
 # Win+X › «Arresta o disconnetti»: un clic esegue, come nello Start.
 call('startContext')
 menu_x=wait(lambda:(lambda m:m if m['items'] else None)(json.loads(call('menuX'))))
 sotto=next((i for i in menu_x['items'] if i['children']),None)
 check('Win+X Shut down or sign out offers the four Windows actions',sotto and [c['action'] for c in sotto['children']]==['esci','sospendi','spegni','riavvia'],menu_x)
 check('Win+X power labels match the Start power menu',sotto and [c['label'] for c in sotto['children']]==['Disconnetti','Sospendi','Arresta il sistema','Riavvia il sistema'],sotto)
 for azione in ('esci','sospendi','spegni','riavvia'):
     call('sceltaMenu',azione);settle()
     st=ui_state();check('Win+X '+azione+' runs with a single choice and opens no panel',st['ultimaAzione']==azione and st['panel']=='',(st['ultimaAzione'],st['panel']))
 call('open','start');settle();click('windowsStartPower');click('windowsStartPower-accesso')
 st=ui_state();check('Sign-in options opens the Login settings',st['ultimaSezione']=='accesso' and st['panel']=='',(st['ultimaSezione'],st['panel']))
 call('close');call('menu','liquid');settle()
 # Aperto dallo Start, col clic vero: deve aprirsi subito, senza il
 # periscopio nell'angolo in basso a sinistra (il manutentore, 11 ottobre 2026).
 inizio=time.monotonic();click('windowsStartButton')
 visti=[]
 while time.monotonic()-inizio<1.5:
     lm=ui_state()['liquidMenu'];visti.append((round(time.monotonic()-inizio,3),lm and lm['periscopio'],lm and lm['emerso']))
     if lm and lm['emerso'] and lm['salita']>=1: break
 check('Liquid menu from Start never shows the corner periscope',not any(p for _,p,_ in visti),visti)
 ms=wait(lambda:ui_state()['liquidMenu']['ms'] if ui_state()['liquidMenu']['ms']>=0 else None)
 check('Liquid menu from Start is in place within 300 ms of the request',0<=ms<=300,ms)
 check('Liquid alternative retains categories',ui_state()['liquid'])
 lm=wait(lambda:ui_state()['liquidMenu']);time.sleep(1.0);lm=ui_state()['liquidMenu']
 check('Liquid menu opens centred above the Start button',lm and (abs(lm['centro']-lm['start'])<2 or lm['larghezza']>=ui_state()['screenWidth']-40),lm)
 check('Liquid menu inside Windows offers power buttons',lm and lm['alimentazione'],lm)
 key('Escape',[]);call('menu','windows11');settle()
 call('preset','windows');wait(lambda:ui_state()['style']=='windows');st=ui_state();check('Windows preset selects dedicated taskbar',st['settings']['bar']['stile']=='windows11')
 call('preset','libero');wait(lambda:ui_state()['style']=='libero');check('custom layout restored',ui_state()['settings']['bar']['stile']=='isola')
 call('preset','windows');call('theme','light');settle()
 call('settingsOpen','true');wait(lambda:len(windows())==1);settle()
 def settings_click(name):
     query='Stile della scrivania' if name.startswith('desktopStyleChoice') else ('Menu Start' if name.startswith('windowsMenuChoice') else ('Sfondo Windows' if name.startswith('windowsAccent-') or name=='windowsAccentCustom' else ("Mostra il colore d'accento" if name=='windowsAccentOnStart' else 'Tema del desktop Windows')))
     call('settingsReveal',query);settle()
     c=wait(lambda:ui_state()['settingsControls'].get(name));w=next(w for w in windows() if w['titolo']=='Aspetto di prova')
     cmd(f"dito {w['x']+c['x']} {w['y']+c['y']}");cmd('dito premi');cmd('dito lascia');settle()
 screenshot('appearance-before')
 settings_click('desktopStyleChoice-liquid');check('Appearance mouse switches to Liquid and restores its preferences',ui_state()['style']=='liquid' and ui_state()['settings']['dock']['iconSize']==61 and ui_state()['settings']['riva']['angoli']['altoDx']=='stanze')
 settings_click('desktopStyleChoice-windows');check('Appearance mouse switches back to Windows without restoring factory preferences',ui_state()['style']=='windows' and ui_state()['settings']['windows']['tilingMode']=='colonne' and ui_state()['settings']['windows']['effetto']=='nessuno')
 (ART/'appearance-controls.json').write_text(json.dumps({'ui':ui_state()['settingsControls'],'windows':windows()},indent=2))
 settings_click('windowsMenuChoice-liquid');screenshot('appearance-click');check('Appearance mouse selects Liquid Start',ui_state()['settings']['windows11']['menu']=='liquid')
 settings_click('windowsMenuChoice-windows11');check('Appearance mouse selects Windows Start',ui_state()['settings']['windows11']['menu']=='windows11')
 settings_click('windowsThemeChoice-dark');check('Appearance mouse selects dark desktop',ui_state()['theme'])
 settings_click('windowsThemeChoice-light');check('Appearance mouse selects light desktop',not ui_state()['theme'])
 call('settingsReveal','Sfondo Windows');settle();away()
 c=ui_state()['settingsControls']['windowsAccentCustom'];w=next(w for w in windows() if w['titolo']=='Aspetto di prova')
 custom_image=screenshot('appearance-custom-label')
 with Image.open(custom_image) as shot:
     screen=ui_state()
     pixel=(round(w['x']-screen['screenX']+c['x']-c['width']/2+3),round(w['y']-screen['screenY']+c['y']))
     rgb=shot.convert('RGB').getpixel(pixel)
     actual_background='#%02x%02x%02x'%rgb
 check('custom color label is readable against rendered Settings background',contrast(ui_state()['colors']['customLabel'],actual_background)>=4.5,(ui_state()['colors'],actual_background))
 settings_click('windowsAccentCustom');check('custom color picker opens with mouse',ui_state()['colors']['customOpen'])
 key('space',[]);check('custom color picker closes with keyboard',not ui_state()['colors']['customOpen'])
 settings_click('windowsAccent-8764B8');check('Appearance mouse selects Windows accent',ui_state()['settings']['windows11']['accent']=='#8764B8')
 key('Tab',[]);key('space',[]);check('Windows accent palette supports Tab and Space',ui_state()['settings']['windows11']['accent']=='#C239B3')
 settings_click('windowsThemeChoice-dark');check('Appearance remains dark before tint click',ui_state()['theme'],ui_state());screenshot('appearance-accent-before');settings_click('windowsAccentOnStart');screenshot('appearance-accent-after');check('Appearance enables tinted Start with mouse',ui_state()['colors']['tinted'],ui_state())
 settings_click('windowsThemeChoice-light');settings_click('windowsAccentOnStart');check('light mode disables tint toggle without losing saved choice',ui_state()['settings']['windows11']['accentOnStart'] and not ui_state()['colors']['tinted'])
 settings_click('windowsAccent-auto');call('preference','windows11.accentOnStart','false')
 call('settingsOpen','false');wait(lambda:len(windows())==0);away()
 def files_call():
     subprocess.run(['qs','-p',tmp+'/files.qml','ipc','call','windows-files-test','add'],env=env,check=True,capture_output=True,timeout=10)
 original=exercise_previews()
 away();call('open','overview');settle()
 check('Task view shows all four surfaces',sum(k.startswith('windowsTaskViewWindow-') for k in ui_state()['controls'])==4)
 screenshot('overview-windows')
 key('Right',[]);check('Task view arrows move window selection',ui_state()['selectedWindow']==1)
 before=[(w['id'],w['x'],w['y'],w['larghezza'],w['altezza']) for w in windows()]
 key('Right',['Super_L']);check('Super arrows in Task view leave underlying tiling unchanged',before==[(w['id'],w['x'],w['y'],w['larghezza'],w['altezza']) for w in windows()])
 key('Tab',[]);check('Task view Tab selects desktop strip',ui_state()['desktopsFocus'])
 click('windowsNewDesktop');wait(lambda:state()['scrivania']==2);settle()
 check('new desktop persists without losing first desktop windows',ui_state()['desktops']==[1,2] and len(windows())==4)
 cmd('scrivania 1');settle();call('close');call('open','overview');settle()
 tile=ui_state()['controls']['windowsTaskViewWindow-'+original];dest=ui_state()['controls']['windowsDesktop-2']
 screen=ui_state()
 for point in [tile,dest]:
     point['x']+=screen['screenX'];point['y']+=screen['screenY']
 cmd(f"dito {tile['x']} {tile['y']}");cmd('dito premi')
 for i in range(1,16):
     cmd(f"dito {tile['x']+(dest['x']-tile['x'])*i/15} {tile['y']+(dest['y']-tile['y'])*i/15}");time.sleep(.04)
     if i == 7:
         subprocess.run(['qs','-p',tmp+'/files.qml','ipc','call','windows-files-test','renameAll'],env=env,check=True,capture_output=True,timeout=10)
         settle()
 cmd('dito lascia');settle()
 check('real drag moves only addressed surface to desktop 2',item(original)['scrivania']==2 and sum(w['scrivania']==1 for w in windows())==3,windows())
 check('desktop drag keeps source desktop active',state()['scrivania']==1,state())
 check('title polling during drag preserves the drag handler', item(original)['scrivania']==2)
 # ── «Sposta in» col tasto destro, come Windows 11 (Claude, 11 ottobre 2026) ──
 call('close');call('open','overview');settle()
 altra=next(w for w in windows() if w['scrivania']==1)
 click('windowsTaskViewWindow-'+altra['id'],'destro')
 c=ui_state()['controls'];check('right click on a Task view window opens Move to',('windowsTaskViewMoveTo-2' in c) and ('windowsTaskViewMoveToNew' in c) and ('windowsTaskViewMoveTo-1' not in c),sorted(k for k in c if 'Move' in k))
 key('Escape',[]);settle();check('Escape closes Move to and keeps Task view open','windowsTaskViewMoveMenu' not in ui_state()['controls'] and ui_state()['panel']=='overview',ui_state()['panel'])
 click('windowsTaskViewWindow-'+altra['id'],'destro');click('windowsTaskViewMoveTo-2')
 check('Move to sends only that window to desktop 2',item(altra['id'])['scrivania']==2 and state()['scrivania']==1 and sum(w['scrivania']==2 for w in windows())==2,windows())
 # Torna dov'era: i controlli che seguono contano le finestre del desktop 2.
 cmd(f"portaascrivania address:{altra['id']} 1 si");settle()
 check('the moved window goes back to desktop 1',item(altra['id'])['scrivania']==1,windows())
 # ── Rinominare un desktop dalla sua miniatura, come Windows 11 ──
 call('close');call('open','overview');settle()
 def doppio(nome):
     c=wait(lambda:ui_state()['controls'].get(nome));s=ui_state()
     cmd(f"dito {c['x']+s['screenX']} {c['y']+s['screenY']}")
     for _ in range(2):
         cmd('dito premi');cmd('dito lascia');time.sleep(.05)
     settle()
 def scrivi(testo):
     for lettera in testo:
         cmd(f'tasto {lettera} premi');cmd(f'tasto {lettera} lascia')
     settle()
 doppio('windowsDesktopName-2')
 check('double click on a desktop name starts renaming','windowsDesktopRename-2' in ui_state()['controls'])
 scrivi('lavoro');key('Return',[]);settle()
 check('Enter saves the desktop name',ui_state()['settings']['windows']['workspaceNames'][1]=='lavoro',ui_state()['settings']['windows']['workspaceNames'])
 doppio('windowsDesktopName-2');scrivi('xyz');key('Escape',[]);settle()
 st=ui_state()
 check('Escape leaves the name as it was and keeps Task view open',st['settings']['windows']['workspaceNames'][1]=='lavoro' and st['panel']=='overview',(st['settings']['windows']['workspaceNames'],st['panel']))
 call('preference','windows.workspaceNames',json.dumps(['']*10));settle()
 click('windowsDesktop-2','destro')
 check('desktop context menu offers Rename and Close', all(k in ui_state()['controls'] for k in ('windowsDesktopMenu-rename','windowsDesktopMenu-close')))
 click('windowsDesktopMenu-rename')
 scrivi('ufficio');key('Return',[])
 check('desktop context Rename saves the selected desktop name', ui_state()['settings']['windows']['workspaceNames'][1]=='ufficio')
 call('preference','windows.workspaceNames',json.dumps(['']*10));settle()
 call('preference','windows11.desktops',json.dumps(list(range(1,11))));settle()
 check('ten desktops preserve all windows and disable New desktop', len(ui_state()['desktops'])==10 and len(windows())==4)
 key('Tab',[])
 for _ in range(9): key('Right',[])
 desktop_choice=ui_state()['selectedDesktop'];time.sleep(1)
 check('desktop selection survives compositor polling', ui_state()['selectedDesktop']==desktop_choice==9)
 screenshot('overview-ten-desktops')
 key('Return',[]);wait(lambda:state()['scrivania']==10)
 check('keyboard reaches the last desktop beyond the visible strip', state()['scrivania']==10)
 click('windowsDesktop-10','destro');click('windowsDesktopMenu-close')
 wait(lambda:state()['scrivania']==9)
 check('closing an empty desktop keeps every application alive', len(windows())==4 and 10 not in ui_state()['desktops'])
 cmd('scrivania 1');call('preference','windows11.desktops',json.dumps([1,2]));settle()
 call('close');cmd('scrivania 2');settle()
 check('workspace-local taskbar lists one window',sum(len(g['windows']) for g in ui_state()['groups'])==1,ui_state()['groups'])
 click('windowsTask-test-files.desktop','centrale');wait(lambda:len(windows())==5,20);settle()
 check('middle click opens fresh window on current desktop',sum(w['scrivania']==2 for w in windows())==2,windows())
 call('open','start');settle();click('windowsPinned-test-files.desktop');wait(lambda:len(windows())==6,20);settle()
 check('Start launches another window without activating other desktop',sum(w['scrivania']==2 for w in windows())==3 and state()['scrivania']==2,windows())
 # Cerca come l'ultima Windows 11 (settembre 2026): a campo vuoto solo le
 # ricerche recenti, l'ingranaggio in alto, risultati con etichetta e
 # anteprima a destra (Claude, 11 ottobre 2026; prima la pagina aveva app
 # principali e «Ricerca rapida», che su uno schermo vero uscivano dal fondo).
 call('preference','windows11.ricercheRecenti',json.dumps([]));call('open','search');settle()
 c=ui_state()['controls']
 check('Search landing has no top apps or quick searches like current Windows',not any(k.startswith('windowsSearchFeatured-') for k in c) and 'windowsSearchHistoryEmpty' in c,sorted(k for k in c if k.startswith('windowsSearch')))
 panel=c['windowsPanelArea'];gear=c['windowsSearchSettings']
 check('search settings gear sits inside the panel',panel['y']-panel['height']/2<=gear['y']-gear['height']/2 and gear['y']+gear['height']/2<=panel['y']+panel['height']/2 and gear['x']+gear['width']/2<=panel['x']+panel['width']/2,(panel,gear))
 before=len(windows());key('Return',[]);check('empty Search Enter does not launch unrelated app',len(windows())==before)
 for name in ['p','r','o']:key(name,[])
 wait(lambda:len(ui_state()['fileResults'])>0)
 check('search returns matching real daemon file result',ui_state()['fileResults'][0]['name']=='Progetto.txt')
 c=wait(lambda:ui_state()['controls'] if 'windowsSearchPreview' in ui_state()['controls'] else None)
 labels=[v['text'] for k,v in c.items() if k.startswith('windowsSearchLabel-')]
 check('each result carries its source label and a preview pane opens',labels and all(t.startswith(('App','File','Cartella')) for t in labels),labels)
 click('windowsSearchFilter-documents');wait(lambda:len(ui_state()['fileResults'])>0);check('Document filter excludes app results',ui_state()['apps']==[])
 c=wait(lambda:ui_state()['controls'] if 'windowsSearchAction-copia' in ui_state()['controls'] else None)
 check('a file preview offers Open and Copy path',all(k in c for k in ('windowsSearchAction-apri','windowsSearchAction-copia')),sorted(k for k in c if k.startswith('windowsSearchAction')))
 screenshot('search-documents')
 click('windowsSearchFilter-apps');wait(lambda:ui_state()['fileResults']==[]);check('App filter cancels file search',True)
 key('Escape',[]);settle()
 call('preference','windows11.ricercheRecenti',json.dumps(['progetto']));call('open','search');settle()
 click('windowsSearchHistory-0');wait(lambda:len(ui_state()['fileResults'])>0)
 check('a recent search runs again with one click',ui_state()['fileResults'][0]['name']=='Progetto.txt')
 key('Escape',[]);settle();call('open','search');settle()
 click('windowsSearchSettings');settle()
 check('the gear opens the search settings (Preset page)',ui_state()['ultimaSezione']=='preset' and ui_state()['panel']=='',(ui_state()['ultimaSezione'],ui_state()['panel']))
 call('toast');wait(lambda:ui_state()['toastCount']==1);screenshot('notification')
 check('real notification makes the taskbar bell filled',indicators()['notification']=='bellFilled' and indicators()['unread']>0,indicators())
 call('preference','notifications.doNotDisturb','true');settle();call('toast');settle()
 check('Do Not Disturb suppresses additional toast',ui_state()['toastCount']==1)
 check('real Do Not Disturb changes taskbar bell to snooze',indicators()['notification']=='bellSnooze' and indicators()['quiet'],indicators())
 call('preference','notifications.doNotDisturb','false')
 settle();click('windowsClockButton');settle()
 check('reading calendar removes unread state without clearing notifications',indicators()['unread']==0 and indicators()['notification']=='bell',indicators())
 key('Escape',[])
 tray=spawn([sys.executable,str(ROOT/'tests/fixtures/windows11-tray.py'),tmp+'/tray-events.json'],env,'tray')
 wait(lambda:ui_state()['trayCount']==9,15);settle();click('windowsTrayToggle')
 check('nine real tray items appear in overflow',sum(k.startswith('windowsTrayItem-') for k in ui_state()['controls'])==9,ui_state())
 screenshot('tray-overflow');click('windowsTrayItem-Demo 0')
 wait(lambda:Path(tmp+'/tray-events.json').exists())
 check('tray left click calls StatusNotifierItem Activate',json.loads(Path(tmp+'/tray-events.json').read_text())==['activate-0'])
 click('windowsTrayToggle');click('windowsTrayItem-Demo 1','destro');wait(lambda:ui_state()['trayMenuOpen'])
 check('tray context menu loads real DBusMenu entries',ui_state()['trayMenuCount']==2,ui_state())
 key('Down',[]);key('Return',[]);wait(lambda:any(event.startswith('menu-1-clicked') for event in json.loads(Path(tmp+'/tray-events.json').read_text())))
 check('tray menu keyboard activates real DBusMenu action',True)
 os.killpg(tray.pid,signal.SIGTERM);tray.wait(timeout=5);wait(lambda:ui_state()['trayCount']==0)
 check('removed tray services disappear immediately',ui_state()['trayCount']==0)
 timings=[]
 for i in range(12):
     call('open','start');settle();timings.append(ui_state()['openMs']);key('Escape',[])
 check('all Start openings produce a measured frame',all(t>=0 for t in timings),timings)
 check('preview refresh stops with all panels closed',not ui_state()['cacheActive'])
 for resolution,scale in [('1366x768',1),('1920x1080',1),('1920x1080',1.25),('2560x1440',1.5),('3840x2160',2)]:
     cmd(f'schermo HEADLESS-1 {resolution}@60 {scale} 0');settle();call('open','start');settle()
     outputs=json.loads(cmd('schermi'));actual=next(o for o in outputs if o['nome']=='HEADLESS-1')
     expected=list(map(int,resolution.split('x')));check(resolution+' mode actually applied',[actual['modoLarghezza'],actual['modoAltezza']]==expected,actual)
     check(resolution+' logical scale actually applied',abs(actual['scala']-scale)<0.001 and abs(actual['larghezza']-expected[0]/scale)<2 and abs(actual['altezza']-expected[1]/scale)<2,actual)
     controls=ui_state()['controls'];area=controls['windowsPanelArea'];strip=controls['windowsTaskbarStrip']
     check(resolution+' @ '+str(scale)+' panel fits above taskbar',area['x']-area['width']/2>=0 and area['y']-area['height']/2>=0 and area['y']+area['height']/2<=strip['y']-strip['height']/2,controls)
     screenshot('start-'+resolution+'-'+str(scale));key('Escape',[])
 check('private daemon is alive after settings and window actions',daemon.poll() is None)
 (ART/'timings.json').write_text(json.dumps({'start_frame_ms':timings},indent=2))
 os.killpg(ui.pid,signal.SIGTERM);ui.wait(timeout=5)
 runtime=Path(tmp)/'runtime-shell.qml'
 runtime.write_text((ROOT/'tests/fixtures/windows11-shell.qml').read_text().replace('@CORE@',(ROOT/'minerva-shell/core').as_uri()).replace('@SHELL@',(ROOT/'minerva-shell/shell.qml').as_uri()))
 real=spawn(['qs','-p',str(runtime)],uienv,'full-shell')
 def real_call(method,*args):
     r=subprocess.run(['qs','-p',str(runtime),'ipc','call','windows-runtime',method,*map(str,args)],env=uienv,text=True,capture_output=True,timeout=10)
     return r.stdout.strip() if r.returncode==0 else None
 def real_state():
     raw=real_call('status');return json.loads(raw) if raw else {'ready':False}
 wait(lambda:real_state()['ready'],25);settle()
 check('actual shell registers dedicated Windows taskbar',real_state()['windowsMode'] and real_state()['bar'],real_state())
 check('actual shell resolves Bloom to existing filesystem asset',Path(real_state()['wallpaper']).is_file(),real_state())
 # La barra nascosta non basta: bordi, IPC, Super e cambio stanza erano ingressi separati.
 def no_islands(st):
     return (not st['rivaEnabled'] and not st['guide'] and not st['consent']
         and all(not output['peek'] and not output['barVisible'] and not output['barRevealed']
             and all(not panel['open'] and not panel['visible'] for panel in output['panels'].values())
             for output in st['islands']))
 windows_riva_prefs=real_state()['rivaPrefs']
 windows_island_prefs=real_state()['islandPrefs']
 check('Windows starts without Liquid islands on either output',no_islands(real_state()),real_state())
 for kind,values in [('bordo',['alto','basso','sinistra','destra']),
                     ('angolo',['alto-sx','alto-dx','basso-sx','basso-dx']),
                     ('diretta',['centro','cassetto','isola','stanze','attivita','barra','notifiche']),
                     ('panoramica',['']),('guida',['apri','chiudi'])]:
     for value in values:
         real_call('riva',kind,value);settle()
         check('Windows rejects Liquid island entry '+kind+' '+value,no_islands(real_state()) and real_state()['panel']=='',real_state())
 for method in ['appunti','isola','stanze','attivita']:
     result=subprocess.run(['qs','-p',str(runtime),'ipc','call','minerva',method,'apri'],env=uienv,text=True,capture_output=True,timeout=10)
     check('legacy '+method+' IPC executes in actual shell',result.returncode==0,result.stdout+result.stderr)
     settle();check('legacy '+method+' IPC cannot open islands in Windows',no_islands(real_state()),real_state())
 cmd('tasto Super_L premi');time.sleep(1.1)
 check('holding real Super in Windows reveals neither guide nor islands',no_islands(real_state()),real_state())
 cmd('tasto Super_L lascia');settle();key('Escape',[])
 workspace_before=state()['scrivania']
 target_workspace=2 if workspace_before!=2 else 1
 key(str(target_workspace),['Super_L'])
 wait(lambda:state()['scrivania']==target_workspace)
 check('real workspace shortcut changes the actual compositor desktop',state()['scrivania']!=workspace_before,state())
 check('workspace change cannot reveal Liquid room strip in Windows',no_islands(real_state()),real_state())
 real_call('preset','liquid');wait(lambda:real_state()['rivaEnabled']);settle()
 liquid_prefs=(real_state()['rivaPrefs'],real_state()['islandPrefs'])
 for panel in ['centro','cassetto','isola','stanze','attivita']:
     real_call('riva','diretta',panel);settle()
     check('Liquid still opens '+panel,any(o['panels'][panel]['open'] and o['panels'][panel]['visible'] for o in real_state()['islands']),real_state())
     real_call('preset','windows');wait(lambda:not real_state()['rivaEnabled']);settle()
     check('switching from open '+panel+' to Windows closes every island',no_islands(real_state()),real_state())
     check('Windows retains saved Riva and island preferences',real_state()['rivaPrefs']==windows_riva_prefs and real_state()['islandPrefs']==windows_island_prefs,real_state())
     real_call('preset','liquid');wait(lambda:real_state()['rivaEnabled']);settle()
     check('Liquid retains saved Riva and island preferences',(real_state()['rivaPrefs'],real_state()['islandPrefs'])==liquid_prefs,real_state())
 real_call('preset','windows');wait(lambda:not real_state()['rivaEnabled']);settle()
 for name in ['start','control','calendar','weather','overview']:
     real_call('panel',name);settle();check('actual shell routes '+name+' to Windows panel',real_state()['panel']==name,real_state());key('Escape',[])
 key('Super_L',[]);check('actual Super key opens Windows Start',real_state()['panel']=='start',real_state());key('Escape',[])
 real_call('menu','liquid');settle();real_call('panel','start');settle();check('actual shell routes optional Liquid Start',real_state()['liquid'] and real_state()['panel']=='',real_state());key('Escape',[])
 real_call('preset','libero');settle();check('switching preset removes Windows surface',not real_state()['windowsMode'] and not real_state()['bar'],real_state())
 real_call('preset','windows');real_call('menu','windows11');settle();real_call('panel','start');settle();check('re-entering Windows preset re-registers taskbar',real_state()['bar'] and real_state()['panel']=='start',real_state())
 screenshot('full-shell-start',real_state()['screenName']);key('Escape',[])
 check('actual shell creates one taskbar per output',len(real_state()['outputs'])==2,real_state())
 cmd('prova-monitor-rimuovi HEADLESS-2');wait(lambda:len(real_state()['outputs'])==1);settle()
 real_call('panel','start');settle();check('taskbar routing survives output removal',real_state()['panel']=='start' and real.poll() is None,real_state());key('Escape',[])
 # ── «Con che cosa lo apro?» per un link, come da Chrome (Claude, 11 ottobre 2026) ──
 # Chrome chiede un link `minecraft:` che nessuno sa aprire; «Lascia perdere»
 # deve chiudere davvero, e la stessa richiesta ripetuta subito dopo non deve
 # riaprire la finestrella.
 def real_minerva(method,*args):
     r=subprocess.run(['qs','-p',str(runtime),'ipc','call','minerva',method,*map(str,args)],env=uienv,text=True,capture_output=True,timeout=10)
     return r.stdout.strip() if r.returncode==0 else None
 def apricon():
     raw=real_minerva('apriConStato');return json.loads(raw) if raw and raw.startswith('{') else {}
 real_minerva('apriConPerConto','prova-1','','x-scheme-handler/minecraft','{"scelte":[]}')
 s=wait(lambda:(lambda x:x if x.get('visibile') and x.get('lasciaPerdere') else None)(apricon()))
 check('a link request shows the dialog as a link, not a file',s['schema']=='minecraft' and s['perConto'] and s['portale']=='prova-1',s)
 schermo=next(o for o in json.loads(cmd('schermi')) if o['nome']==real_state()['screenName'])
 cmd(f"dito {schermo['x']+s['lasciaPerdere']['x']} {schermo['y']+s['lasciaPerdere']['y']}");cmd('dito premi');cmd('dito lascia');settle()
 s=apricon();check('a real click on Never mind closes the dialog',not s['visibile'] and s['portale']=='',s)
 real_minerva('apriConPerConto','prova-2','','x-scheme-handler/minecraft','{"scelte":[]}');settle()
 s=apricon();check('the same link asked again right away does not reopen the dialog',not s['visibile'] and s['portale']!='prova-2',s)
 real_minerva('apriConPerConto','prova-3','','x-scheme-handler/steam','{"scelte":[]}')
 s=wait(lambda:(lambda x:x if x.get('visibile') else None)(apricon()))
 check('a different link still asks',s['schema']=='steam' and s['portale']=='prova-3',s)
 key('Escape',[]);settle();s=apricon();check('Escape closes the link dialog too',not s['visibile'],s)
 check('UI source files remain unchanged throughout test',source_hashes()==source_snapshot)
 completed=True
finally:
 wifi_log=Path(tmp)/'wifi-actions.json'
 if wifi_log.exists():
     (ART/'wifi-actions.json').write_bytes(wifi_log.read_bytes())
 bluetooth_log=Path(tmp)/'bluetooth-actions.json'
 if bluetooth_log.exists():
     (ART/'bluetooth-actions.json').write_bytes(bluetooth_log.read_bytes())
 tray_events_file=Path(tmp)/'tray-events.json'
 if tray_events_file.exists():
     (ART/'tray-events.json').write_bytes(tray_events_file.read_bytes())
 action_log=Path(tmp)/'actions.json'
 if action_log.exists():
     (ART/'actions.json').write_bytes(action_log.read_bytes())
 for p in reversed(children):
    try:os.killpg(p.pid,signal.SIGTERM)
    except ProcessLookupError:pass
 for p in children:
    try:p.wait(timeout=5)
    except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait()
 tempdir.cleanup()
 for h in handles:h.close()
 logs=[p.read_text() for name in ['windows','full-shell','settings-api','tray'] if (p:=ART/(name+'.log')).exists()]
 errors=[line for log in logs for line in log.splitlines() if any(x in line for x in ['TypeError','ReferenceError','Binding loop','Cannot assign','Unable to assign','Error loading QML','Failed to load configuration','is not a function'])]
 if errors:print('UI ERRORS',*errors,sep='\n')
 (ART/'verifica.json').write_text(json.dumps({'completed':completed,'checks':checks,'qmlErrors':errors,'binary_sha256':tested_hash,'verified_sources':source_snapshot},indent=2))
 if errors:raise AssertionError(errors)
