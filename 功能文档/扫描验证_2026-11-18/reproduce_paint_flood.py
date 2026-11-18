from pathlib import Path
import subprocess,sys
root=Path(sys.argv[1]).resolve()
subprocess.run([sys.executable,str(root/'Tools/Gameplay/test_rules.py')],cwd=root,check=True)
out=root/'.cache/ragdoll-rules'
s=(root/'Scripts/ServerStorage/Scripts/ProcessingManager.luau').read_text(encoding='utf-8')
prefix="local Config=require('./GameConfig')\nlocal Painting=require('./Painting')\nlocal B=require('./ScanPaintBoundary')\nlocal Net,workspace=B.Net,B.workspace\nlocal Scene={TablePose=function() return nil end,CameraPose=function() return {Position=nil} end}\n"
(out/'ScanProcessingManager.luau').write_text(prefix+s[s.index('type PlayerData ='):],encoding='utf-8')
for name in ('ScanPaintBoundary.luau','scan_paint_flood.luau'):
 (out/name).write_text((Path(__file__).parent/name).read_text(encoding='utf-8'),encoding='utf-8')
subprocess.run(['lune','run',str(out/'scan_paint_flood.luau')],cwd=root,check=True)
