"""Check selected staged audio once and record the result for a later Codex turn."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re

import requests

from setup_sounds_in_studio import selected_sounds
from upload_roblox_audio import API_BASE, load_manifest

STATES = {
    'APPROVED': 'approved',
    'REJECTED': 'rejected',
    'PENDING': 'pending',
    'REVIEWING': 'pending',
    'PENDING_REVIEW': 'pending',
    'IN_REVIEW': 'pending',
}


def check_moderation(session, api_key, asset_id):
    if not re.fullmatch(r'[1-9][0-9]*', asset_id):
        raise ValueError('Invalid Roblox asset ID')
    try:
        response = session.get(
            f'{API_BASE}/assets/v1/assets/{asset_id}',
            params={'readMask': 'moderationResult'},
            headers={'x-api-key': api_key},
            timeout=20,
            allow_redirects=False,
        )
    except requests.RequestException as error:
        return {'status': 'unknown', 'error': type(error).__name__}

    if response.status_code != 200:
        return {'status': 'unknown', 'httpStatus': response.status_code}
    try:
        payload = response.json()
        raw_state = (payload.get('moderationResult') or {}).get('moderationState')
    except (ValueError, AttributeError):
        return {'status': 'unknown', 'error': 'Invalid moderation response'}
    state = raw_state.upper().removeprefix('MODERATION_STATE_') if isinstance(raw_state, str) else ''
    return {'status': STATES.get(state, 'unknown'), 'moderationState': raw_state}


def check_staged(names, sounds_dir, manifest_path, creator_type, creator_id, place_id,
                 status_path, api_key, session=None):
    if (creator_type not in ('user', 'group') or not str(creator_id).isdigit()
            or int(creator_id) <= 0 or place_id <= 0):
        raise ValueError('Valid Place and creator required')
    if not names or len(set(names)) != len(names) or 'BGM' in names:
        raise ValueError('Select unique SFX names')
    if status_path.resolve() == manifest_path.resolve():
        raise ValueError('Review status and staged manifest must be separate files')

    selected = selected_sounds(names, sounds_dir, manifest_path, creator_type, creator_id)
    manifest = load_manifest(manifest_path, creator_type, creator_id)
    previous = json.loads(status_path.read_text(encoding='utf-8')) if status_path.exists() else None
    target = {'placeId': place_id, 'creator': manifest['creator'], 'manifest': str(manifest_path.resolve())}
    if previous is not None and any(previous.get(key) != value for key, value in target.items()):
        raise ValueError('Review target differs from the saved run')
    review = {
        **target,
        'checkedAt': datetime.now(timezone.utc).isoformat(),
        'sounds': dict(previous['sounds']) if previous is not None else {},
    }

    identities = {
        name: {'assetId': entry['assetId'], 'sha256': manifest['sounds'][name]['sha256']}
        for name, entry in selected.items()
    }
    for name, identity in identities.items():
        old = review['sounds'].get(name)
        if old is not None and any(old.get(key) != value for key, value in identity.items()):
            raise ValueError('Staged audio differs from the saved review: ' + name)

    with requests.Session() as default_session:
        for name, identity in identities.items():
            review['sounds'][name] = {
                **identity,
                **check_moderation(session or default_session, api_key, identity['assetId']),
            }
    status_path.parent.mkdir(parents=True, exist_ok=True)
    temporary = status_path.with_suffix(status_path.suffix + '.tmp')
    temporary.write_text(json.dumps(review, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    temporary.replace(status_path)
    return review


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--names', nargs='+', required=True)
    parser.add_argument('--sounds-dir', type=Path, required=True)
    parser.add_argument('--staged-manifest', type=Path, required=True)
    parser.add_argument('--status-file', type=Path, required=True)
    parser.add_argument('--place-id', type=int, required=True)
    parser.add_argument('--creator-type', choices=['user', 'group'], required=True)
    parser.add_argument('--creator-id', required=True)
    parser.add_argument('--api-key-env', default='ROBLOX_API_KEY')
    args = parser.parse_args()
    key = os.environ.get(args.api_key_env)
    if not key:
        parser.error('Missing credential environment variable: ' + args.api_key_env)
    review = check_staged(args.names, args.sounds_dir, args.staged_manifest, args.creator_type,
                          args.creator_id, args.place_id, args.status_file, key)
    selected = {name: review['sounds'][name] for name in args.names}
    print(json.dumps(selected, ensure_ascii=False))
    return 0 if all(item['status'] == 'approved' for item in selected.values()) else 1


if __name__ == '__main__':
    raise SystemExit(main())
