"""Run unchanged committed dispatcher bodies and wire validation with controlled services."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SNAP = ROOT / '.cache/daily-scan-2026-11-19'
OUT = SNAP / '.cache/ragdoll-rules'
EVIDENCE = Path(__file__).resolve().parent
PREFIX = """local B=require('./ScanInteractionBoundary')
local Config=require('./GameConfig')
local Net,workspace,Scene,Carry=B.Net,B.workspace,B.Scene,B.Carry
"""
for revision, name in [('HEAD', 'ScanCurrent'), ('HEAD^', 'ScanBaseline')]:
    source = subprocess.check_output(['git', 'show', revision + ':Scripts/ServerStorage/Scripts/ProcessingManager.luau'], cwd=ROOT).decode('utf-8')
    (OUT / (name + '.luau')).write_text(PREFIX + source[source.index('type PlayerData ='):], encoding='utf-8')
    (EVIDENCE / (name + '.luau')).write_text(source, encoding='utf-8')
boundary = """local R=require('@lune/roblox')
local B={now=100}
B.workspace={GetServerTimeNow=function() return B.now end}
B.Scene={SigilPosition=R.Vector3.zero}
for _,name in {'PoolPickup','TableInteract','Altar','Shelf'} do B.Scene[name]={Position=R.Vector3.zero} end
B.Net={FireNotify=function()end}
B.Carry={Take=function(item,player) item.holder=player;item.location='Carried';return true end}
return B
"""
test = """local R=require('@lune/roblox')
local B=require('./ScanInteractionBoundary')
local Wire=require('./VisualProtocol')
local Config=require('./GameConfig')
for _,name in {'ScanBaseline','ScanCurrent'} do
 local M=require('./'..name)
 local player={Character={}}
 local coins=0
 local record={lastRequest=0}
 local root={Position=R.Vector3.new(1000,0,0)}
 local manager=setmetatable({players={[player]=record},items={},pool={},shelf={},stationVersions={Pool=1,Sigil=1},
  Root=function()return root end,Changed=function()end,Tell=function()end,
  data={IsActive=function()return true end,CanAddCoins=function()return true end,AddCoins=function(_,amount)coins+=amount end}},M)
 local body={id='body',kind='Body',location='Pool',version=1,model={PrimaryPart={Position=R.Vector3.zero}}}
 manager.items.body=body;manager.pool={'body'}
 local function send(target)
  B.now+=1
  local request={action='Interact',target=target,version=1}
  assert(Wire.Validate(request),'actual protocol must accept request')
  manager:OnRequest(player,request)
 end
 send('Pool')
 local poolAccepted=body.holder==player
 body.holder=nil;body.location='Ground';manager.pool={}
 send('body')
 local groundAccepted=body.holder==player
 body.holder=nil
 local potion={id='potion',kind='Potion',model={Destroy=function()end}}
 manager.items.potion=potion
 manager.EquippedPotion=function()return potion end
 manager.Held=function()return potion end
 send('Sigil')
 local expected=name=='ScanCurrent'
 assert(poolAccepted==expected and groundAccepted==expected and (coins>0)==expected,'baseline/current behavior differs as expected')
 print(name..' distance=1000 range='..Config.InteractionRange..' pool='..tostring(poolAccepted)..' ground='..tostring(groundAccepted)..' coins='..coins)
end
print('PASS: actual protocol and complete manager dispatcher; storage/character/physics/network boundaries mocked')
"""
for name, content in [('ScanInteractionBoundary', boundary), ('scan_interaction', test)]:
    (OUT / (name + '.luau')).write_text(content, encoding='utf-8')
    (EVIDENCE / (name + '.luau')).write_text(content, encoding='utf-8')
p = subprocess.run(['lune', 'run', str(OUT / 'scan_interaction.luau')], cwd=SNAP, capture_output=True, timeout=30)
(EVIDENCE / 'interaction.txt').write_bytes(p.stdout + p.stderr)
print((p.stdout + p.stderr).decode('utf-8', errors='replace'))
raise SystemExit(p.returncode)
