local R=require('@lune/roblox')
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
