"""Upload the selected FBX to the experience group; resume its recorded operation."""
import hashlib
import json
import os
from pathlib import Path
import time
import requests
import argparse

ROOT = Path(__file__).resolve().parents[2]
directory = ROOT / 'Assets/Models/WhiteBody'
path = directory / 'WhiteBody.fbx'
manifest = directory / 'upload.json'
digest = hashlib.sha256(path.read_bytes()).hexdigest()
state = json.loads(manifest.read_text()) if manifest.exists() else {}
if state.get('sha256') != digest:
    state = {'sha256': digest, 'groupId': '33977495'}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--api-key-env', default='ROBLOX_API_KEY')
args = parser.parse_args()
headers = {'x-api-key': os.environ[args.api_key_env]}
base = 'https://apis.roblox.com'
if not state.get('operation'):
    payload = {'assetType':'Model', 'displayName':'DemonShop_WhiteBody_v1',
               'description':'Curved R15 white body, shared painting UV atlas',
               'creationContext':{'creator':{'groupId':'33977495'}}}
    with path.open('rb') as f:
        response = requests.post(base+'/assets/v1/assets',headers=headers,
            files={'request':(None,json.dumps(payload),'application/json'),
                   'fileContent':(path.name,f,'model/fbx')},timeout=60)
    if response.status_code not in (200,201,202):
        print('Upload failed HTTP',response.status_code,response.text[:1200])
        raise SystemExit(1)
    state['operation'] = response.json()['path']
    manifest.write_text(json.dumps(state,indent=2))
operation = state['operation'].lstrip('/')
if operation.startswith('operations/'): operation = 'assets/v1/'+operation
for _ in range(30):
    response = requests.get(base+'/'+operation,headers=headers,timeout=30)
    response.raise_for_status()
    result = response.json()
    if result.get('done'):
        state['result'] = result
        manifest.write_text(json.dumps(state,indent=2))
        print(json.dumps(result))
        if result.get('error'): raise SystemExit(1)
        break
    time.sleep(2)
else:
    print('Pending operation recorded in',manifest)
