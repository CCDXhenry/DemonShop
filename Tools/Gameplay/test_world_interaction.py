"""Execute production world interaction rules and prompt controller with Lune engine boundaries."""
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / '.cache' / 'world-interaction'
OUT.mkdir(parents=True, exist_ok=True)
SHARED = ROOT / 'Scripts/ReplicatedStorage/Scripts/Shared'
for name in ('GameTexts', 'WorldInteractionRules', 'LifecycleTool'):
    source = (SHARED / f'{name}.luau').read_text(encoding='utf-8')
    source = re.sub(r'require\(script.Parent.(\w+)\)', r"require('./\1')", source)
    (OUT / f'{name}.luau').write_text(source, encoding='utf-8')
(OUT / 'GameTypes.luau').write_text('return {}', encoding='utf-8')
(OUT / 'GameConfig.luau').write_text('return {InteractionRange=8,StunHits=3,PoolCapacity=6}', encoding='utf-8')
source = (ROOT / 'Scripts/ReplicatedStorage/Scripts/Client/WorldInteractionManager.luau').read_text(encoding='utf-8')
start, end = source.index('local ReplicatedStorage ='), source.index('local InputReleaseGraceSeconds =')
prefix = """local B=require('./WorldInteractionBoundary')
local ReplicatedStorage,Net,TranslationTool,task,os=B.ReplicatedStorage,B.Net,B.TranslationTool,B.task,B.os
local Rules=require('./WorldInteractionRules')
local GameTexts=require('./GameTexts')
local Config=require('./GameConfig')
local Lifecycle=require('./LifecycleTool')
"""
(OUT / 'WorldInteractionManager.luau').write_text(source[:start]+prefix+source[end:], encoding='utf-8')
for name in ('WorldInteractionBoundary', 'test_world_interaction'):
    (OUT / f'{name}.luau').write_text((ROOT / f'Tools/Gameplay/{name}.luau').read_text(encoding='utf-8'), encoding='utf-8')
subprocess.run(['lune', 'run', str(OUT / 'test_world_interaction.luau')], cwd=ROOT, check=True)
