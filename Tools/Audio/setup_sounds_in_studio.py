"""Validate selected audio and emit Luau for explicit execution through Studio MCP."""
import argparse
import hashlib
import json
from pathlib import Path
from upload_roblox_audio import load_manifest


def build_setup_code(sounds, creator_type, creator_id):
    payload = json.dumps(json.dumps(sounds, ensure_ascii=True))
    enum = 'Group' if creator_type == 'group' else 'User'
    return f'''assert(not game:GetService("RunService"):IsRunning(), "Edit mode required")
assert(game.CreatorType == Enum.CreatorType.{enum} and game.CreatorId == {int(creator_id)}, "Creator mismatch")
local sounds = game:GetService("HttpService"):JSONDecode({payload})
local storage = game:GetService("ReplicatedStorage")
local service = game:GetService("SoundService")
local folder = storage:FindFirstChild("Sounds")
assert(not folder or folder:IsA("Folder"), "Sounds must be a Folder")
for name, item in pairs(sounds) do
    local parent = if name == "BGM" then service else folder
    local existing = if parent then parent:FindFirstChild(name) else nil
    assert(not existing or existing:IsA("Sound"), "Invalid Sound template: " .. name)
    assert(item.assetId:match("^%d+$"), "Invalid asset ID")
end
if not folder then
    folder = Instance.new("Folder")
    folder.Name = "Sounds"
    folder.Parent = storage
end
for name, item in pairs(sounds) do
    local parent = if name == "BGM" then service else folder
    local sound = parent:FindFirstChild(name)
    if not sound then
        sound = Instance.new("Sound")
        sound.Name = name
        sound.Looped = name == "BGM"
        sound.Parent = parent
    end
    sound.SoundId = "rbxassetid://" .. item.assetId
end
return "Selected Sound templates updated; tuning preserved"
'''


def selected_sounds(names, sounds_dir, manifest_path, creator_type, creator_id):
    manifest = load_manifest(manifest_path, creator_type, creator_id)
    result = {}
    base = sounds_dir.resolve()
    for name in names:
        item = manifest['sounds'][name]
        path = (base / item['file']).resolve()
        if not path.is_relative_to(base) or not item.get('sha256'):
            raise ValueError('Invalid file or missing hash: ' + name)
        if hashlib.sha256(path.read_bytes()).hexdigest() != item['sha256']:
            raise ValueError('Local audio changed since upload: ' + name)
        result[name] = {'assetId': str(item['assetId'])}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--names', nargs='+', required=True)
    parser.add_argument('--sounds-dir', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--creator-type', choices=['user', 'group'], required=True)
    parser.add_argument('--creator-id', required=True, type=int)
    parser.add_argument('--emit-code', required=True, action='store_true')
    args = parser.parse_args()
    if args.creator_id <= 0:
        parser.error('creator-id must be positive')
    sounds = selected_sounds(args.names, args.sounds_dir, args.manifest, args.creator_type, args.creator_id)
    print(build_setup_code(sounds, args.creator_type, args.creator_id))


if __name__ == '__main__':
    main()
