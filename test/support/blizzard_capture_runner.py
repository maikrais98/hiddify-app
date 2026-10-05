#!/usr/bin/env python3
"""Capture raw fixture PNGs from the isolated, uniquely named iOS test host."""
import argparse,hashlib,json,os,re,subprocess,sys,threading
from pathlib import Path
root=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser()
parser.add_argument('pattern')
parser.add_argument('folder')
parser.add_argument('--visuals',choices=['true','false','default'],default='true')
args=parser.parse_args()
if not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,79}',args.folder): raise SystemExit('Expected a short lowercase evidence-folder name')
sys.path.insert(0,str(root/'scripts'))
from ui_test_simulator_id import select_device
inventory=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json'],text=True))
selected=select_device(inventory)
device=next(d for ds in inventory['devices'].values() for d in ds if d['udid']==selected)
if device['state']!='Booted': subprocess.run(['xcrun','simctl','boot',selected],check=True,capture_output=True)
subprocess.run(['xcrun','simctl','bootstatus',selected,'-b'],check=True,capture_output=True)
pattern=args.pattern
folder=root/'docs/verification/blizzard'/args.folder
if folder.exists(): raise SystemExit('Evidence folder exists; choose a fresh name')
folder.mkdir(parents=True,exist_ok=True)
log=root/'docs/verification/blizzard'/f'{folder.name}.log'
def source_receipt():
    paths=subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard'],cwd=root,text=True).splitlines()
    files={p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in paths if p.endswith('.dart') and p.startswith(('lib/','test/','integration_test/')) and (root/p).is_file()}
    return {'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),'dartTreeSha256':hashlib.sha256(json.dumps(files,sort_keys=True).encode()).hexdigest()}
start_source=source_receipt()
stop=threading.Event()
def copy_frames():
    while not stop.is_set():
        query=subprocess.run(['xcrun','simctl','get_app_container',selected,'dev.blizzardharness.hiddify','data'],capture_output=True,text=True)
        if query.returncode==0:
            source=Path(query.stdout.strip())/'tmp'/'blizzard-captures'
            if source.exists():
                for frame in source.glob('*.png'):
                    target=folder/frame.name
                    if target.exists(): continue
                    try:
                        data=frame.read_bytes()
                        if data.endswith(b'\x00\x00\x00\x00IEND\xaeB`\x82'): target.write_bytes(data)
                    except FileNotFoundError: pass
        stop.wait(.3)
thread=threading.Thread(target=copy_frames,daemon=True);thread.start()
command=['/private/tmp/wir-baseline-tools/flutter-3.38.5/bin/flutter','--suppress-analytics','test','integration_test/blizzard_preservation_test.dart','--no-pub','--reporter','expanded','-d',selected,'--name',pattern,'--dart-define=BLIZZARD_STORAGE_PHASE=write','--dart-define=BLIZZARD_VISUAL_CHECKS=true','--dart-define=BLIZZARD_CAPTURE=true']
if args.visuals!='default': command.append(f'--dart-define=BLIZZARD_VISUALS={args.visuals}')
try:
    with log.open('w') as output:
        try:
            result=subprocess.run(command,cwd='/private/tmp/blizzard-ios-test-host',env=dict(os.environ,PUB_CACHE='/private/tmp/wir-baseline-tools/pub-cache'),stdout=output,stderr=subprocess.STDOUT,timeout=900)
        except subprocess.TimeoutExpired:
            result=subprocess.CompletedProcess(command,124)
finally:
    stop.set();thread.join(timeout=5)
s=log.read_text().replace(selected,'<selected-simulator>');s=re.sub(r'\b[0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}\b|\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}\b','<device-id>',s);s=re.sub(r'iPhone \([^)]*\)','<physical-device>',s);log.write_text(s)
frames=[{'file':f.name,'bytes':f.stat().st_size,'sha256':hashlib.sha256(f.read_bytes()).hexdigest()} for f in sorted(folder.glob('*.png'))]
(folder/'manifest.json').write_text(json.dumps({'source':start_source['head'],'sourceAtStart':start_source,'sourceAtEnd':source_receipt(),'changedDuringRun':start_source!=source_receipt(),'requestedVisualSwitch':args.visuals,'syntheticData':True,'host':'isolated actual iOS test host','testExit':result.returncode,'frames':frames},indent=2)+'\n')
print(f'iOS pilot exit={result.returncode}, exported={len(frames)} PNG; log={log.name}',flush=True)
raise SystemExit(result.returncode)
