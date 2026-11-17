-- Play 服务端隔离验收：直接调用正式状态机，测试资源只存在于临时容器且不写存档
assert(game:GetService('RunService'):IsRunning())
local SS=game.ServerStorage
local RS=game.ReplicatedStorage
local Manager=require(SS.Scripts.ProcessingManager)
local Ragdoll=require(SS.Scripts.Ragdoll)
local Carry=require(SS.Scripts.Carry)
local Surface=require(game.ReplicatedStorage.Scripts.Shared.PaintSurface)
local Lifecycle=require(game.ReplicatedStorage.Scripts.Shared.LifecycleTool)
local players=game.Players:GetPlayers();assert(#players>=2)
local a,b=players[1],players[2]
local originalPose=a.Character:GetPivot()
local originalCoins=a:GetAttribute("Coins")
local testCoins=0
local data={IsActive=function() return true end,CanAddCoins=function() return true end,AddCoins=function(_,coins) testCoins+=coins;return true end}
local manager=Manager.new(data);manager.runtime.Name='GameplayIsolatedChecks';manager.runtime.Parent=workspace
manager.nextSpawn=math.huge
local checks=0
local function check(condition,label) assert(condition,label);checks+=1 end
local serial=0
local function item(kind)
 serial+=1
 local model=(if kind=='Body' then RS.Models.WhiteR15 else RS.Models.Potion):Clone()
 model.Parent=manager.runtime
 if kind=='Body' then Ragdoll.Setup(model) end
 local value={id='test-'..serial,kind=kind,stage=if kind=='Body' then 'Unpainted' else 'Ready',location='Carried',version=1,model=model,holder=a,hits=3,covered={},strokes={},strokePoints=0,area=0,totalArea=if kind=='Body' then Surface.Total(model) else 0,progress=0,paintSeconds=0,streetSlot=false,nextWalk=0}
 manager.items[value.id]=value
 return value
end
local ok,result=pcall(function()
 for _=1,8 do local body=item('Body');manager:Pool(a);check(body.location=='Pool','pool deposit') end
 local overflow=item('Body');manager:Pool(a);check(#manager.pool==8 and overflow.holder==a,'full pool preserves carried material')
 overflow.holder=nil;manager.items[overflow.id]=nil;overflow.model:Destroy()
 local oldest=manager.pool[1];manager:Pool(a);check(manager:Held(a).id==oldest and #manager.pool==7,'FIFO pickup')
 manager:Table(a);check(manager.tableId==oldest and manager.paint.player==a,'carried body enters table')
 local token=manager.paint.token;manager:Table(b);check(manager.paint.player==a,'second painter cannot seize occupied table')
 local body=manager.items[oldest];body.progress=.42
 manager:EndPaint(a);check(a.Character:FindFirstChild("Club")~=nil,"leaving paint re-equips club");manager:Table(b);check(manager.paint.player==b and body.progress==.42,'interrupted painting retains progress for handoff')
 local area=body.area;manager:Paint(a,{action='Paint',session=token,samples={}});check(body.area==area and manager.paint.player==b,'stale session rejected')
 manager:EndPaint(b);Carry.Take(body,a);manager.tableId=nil
 manager:Altar(a);check(manager.altarId==nil and body.holder==a,'unpainted altar input rejected')
 body.stage='Painted';manager:Altar(a);check(manager.altarId==body.id and body.stage=='Converting','completed body enters altar')
 for _=1,8 do local potion=item('Potion');potion.holder=nil;potion.location='Shelf';table.insert(manager.shelf,potion.id) end
 manager.altarEnds=workspace:GetServerTimeNow()-1;manager.nextUpdate=0;manager:Update()
 check(manager.altarId==body.id and #manager.shelf==8,'full shelf keeps completed conversion waiting')
 manager:Shelf(a);check(#manager.shelf==7 and manager:Held(a).kind=='Potion','shelf pickup frees one slot')
 manager.nextUpdate=0;manager:Update();check(manager.altarId==nil and #manager.shelf==8 and manager.items[body.id]==nil,'waiting conversion outputs once after slot freed')
 manager.players[a]={scope=Lifecycle.new(),lastAttack=0,lastRequest=0,lastSync=0,closing=false}
 manager:Submit(a);check(testCoins==100 and manager:Held(a)==nil,'submit consumes exactly one potion')
 manager:Submit(a);check(testCoins==100,'duplicate submit cannot reward twice')
 local extra=item('Potion')
 local Scene=require(SS.Scripts.Scene)
 a.Character:PivotTo(CFrame.new(Scene.SigilPosition+Vector3.new(0,2,2)))
 manager.players[a].lastRequest=0
 manager:OnRequest(a,{action='Interact',target='Sigil',version=manager.stationVersions.Sigil-1})
 check(manager:Held(a)==extra and testCoins==100,'stale station request preserves held material')
 manager.players[a].lastRequest=0
 manager:OnRequest(a,{action='Interact',target='Sigil',version=manager.stationVersions.Sigil})
 check(manager:Held(a)==nil and testCoins==200,'current station request accepts exactly once')
 local potion=item('Potion');Carry.Drop(potion,Vector3.new(0,-100,0));check(potion.location=='Ground' and potion.model.PrimaryPart.Position.Y>-40,'invalid ground drop recovers at shelf')
 return {checks=checks,passed=true}
end)
manager:EndPaint(a);manager:EndPaint(b)
for _,record in manager.players do record.scope:Destroy() end
manager.runtime:Destroy();manager.scope:Destroy()
a:SetAttribute("Coins",originalCoins);a.Character:PivotTo(originalPose)
assert(ok,result)
return result
