"""Upload explicitly selected audio; persist successful hashes atomically.

API reference: https://create.roblox.com/docs/cloud/guides/usage-assets
Credentials are read only from the selected environment variable.
"""
import argparse
import hashlib
import json
import mimetypes
import os
import re
import time
from datetime import datetime, timezone
from pathlib import Path
import requests

API_BASE = 'https://apis.roblox.com'


def load_manifest(path, creator_type, creator_id):
    creator = {creator_type + 'Id': str(creator_id)}
    if not path.exists():
        return {'kind': 'roblox_audio_manifest', 'creator': creator, 'sounds': {}}
    data = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(data, dict) or not isinstance(data.get('sounds'), dict):
        raise ValueError('Invalid audio manifest')
    if data.get('creator') != creator:
        raise ValueError('Manifest creator mismatch; migrate explicitly before upload')
    for name, item in data['sounds'].items():
        if not isinstance(item, dict) or not re.fullmatch(r'[1-9][0-9]*', str(item.get('assetId', ''))):
            raise ValueError('Invalid manifest entry: ' + name)
    return data


def save_manifest(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    data['updatedAt'] = datetime.now(timezone.utc).isoformat()
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    temporary.replace(path)


def upload_single_audio(session, api_key, name, file_path, creator_type, creator_id, prefix):
    payload = {'assetType': 'Audio', 'displayName': (prefix + name)[:50],
               'description': 'Project audio: ' + name,
               'creationContext': {'creator': {creator_type + 'Id': str(creator_id)}, 'expectedPrice': 0}}
    headers = {'x-api-key': api_key}
    response = session.post(API_BASE + '/assets/v1/assets', headers=headers,
                            files={'request': (None, json.dumps(payload), 'application/json'),
                                   'fileContent': (file_path.name, file_path.read_bytes(),
                                                   mimetypes.guess_type(file_path.name)[0] or 'application/octet-stream')},
                            timeout=60)
    if response.status_code not in (200, 201, 202):
        raise RuntimeError('Create asset HTTP ' + str(response.status_code))
    operation = response.json().get('path', '').lstrip('/')
    if operation.startswith('operations/'):
        operation = 'assets/v1/' + operation
    if not re.fullmatch(r'assets/v1/operations/[A-Za-z0-9_-]+', operation):
        raise ValueError('Invalid operation path')
    deadline, interval = time.monotonic() + 90, 1.0
    while time.monotonic() < deadline:
        response = session.get(API_BASE + '/' + operation, headers=headers, timeout=30)
        if response.status_code == 429:
            time.sleep(interval)
            interval = min(interval * 2, 5)
            continue
        if response.status_code != 200:
            raise RuntimeError('Poll operation HTTP ' + str(response.status_code))
        data = response.json()
        if data.get('done'):
            if data.get('error'):
                raise RuntimeError('Asset operation failed')
            asset_id = str(data.get('response', {}).get('assetId', ''))
            if not re.fullmatch(r'[1-9][0-9]*', asset_id):
                raise ValueError('Operation missing assetId')
            return asset_id
        time.sleep(interval)
        interval = min(interval * 1.5, 5)
    raise TimeoutError('Asset operation timed out')


def upload_selected(names, sounds_dir, manifest_path, creator_type, creator_id, prefix, api_key,
                    session=None, uploader=upload_single_audio):
    if creator_type not in ('user', 'group') or not str(creator_id).isdigit() or int(creator_id) <= 0:
        raise ValueError('Invalid creator')
    if not names or len(set(names)) != len(names):
        raise ValueError('Select unique sound names')
    manifest = load_manifest(manifest_path, creator_type, creator_id)
    sounds_dir = sounds_dir.resolve()
    files = {}
    # Preflight the entire selected set before external mutation.
    for name in names:
        if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_-]*', name):
            raise ValueError('Invalid sound name: ' + name)
        old = manifest['sounds'].get(name, {})
        path = (sounds_dir / old.get('file', name + '.mp3')).resolve()
        if not path.is_relative_to(sounds_dir) or not path.is_file():
            raise ValueError('Missing or invalid file: ' + name)
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if old and not old.get('sha256'):
            raise ValueError('Unknown legacy hash; establish baseline explicitly: ' + name)
        files[name] = (path, digest)
    failures = []
    session = session or requests.Session()
    for name, (path, digest) in files.items():
        old = manifest['sounds'].get(name)
        if old and old.get('sha256') == digest:
            continue
        try:
            asset_id = uploader(session, api_key, name, path, creator_type, creator_id, prefix)
        except Exception as error:
            failures.append((name, type(error).__name__))
            continue
        history = list((old or {}).get('history', []))
        if old:
            history.append({key: value for key, value in old.items() if key != 'history'})
        manifest['sounds'][name] = {'name': name, 'assetId': asset_id, 'rbxassetid': 'rbxassetid://' + asset_id,
                                    'file': path.relative_to(sounds_dir).as_posix(), 'fileSize': path.stat().st_size, 'sha256': digest,
                                    'uploadedAt': datetime.now(timezone.utc).isoformat(), 'history': history}
        save_manifest(manifest_path, manifest)
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--names', nargs='+', required=True)
    parser.add_argument('--sounds-dir', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--creator-type', choices=['user', 'group'], required=True)
    parser.add_argument('--creator-id', required=True)
    parser.add_argument('--prefix', required=True)
    parser.add_argument('--api-key-env', default='ROBLOX_API_KEY')
    args = parser.parse_args()
    key = os.environ.get(args.api_key_env)
    if not key:
        parser.error('Missing credential environment variable: ' + args.api_key_env)
    failures = upload_selected(args.names, args.sounds_dir, args.manifest, args.creator_type,
                               args.creator_id, args.prefix, key)
    for name, error in failures:
        print(name + ': ' + error)
    return 1 if failures else 0


if __name__ == '__main__':
    raise SystemExit(main())
