-- Play 服务端隔离验收：直接调用正式状态机，测试资源只存在于临时容器且不写存档
assert(game:GetService('RunService'):IsRunning())
local SS=game.ServerStorage
local RS=game.ReplicatedStorage
local Manager=require(SS.Scripts.ProcessingManager)
local Ragdoll=require(SS.Scripts.Ragdoll)
local Carry=require(SS.Scripts.Carry)
local Surface=require(game.ReplicatedStorage.Scripts.Shared.PaintSurface)
local Lifecycle=require(game.ReplicatedStorage.Scripts.Shared.LifecycleTool)
local Config=require(RS.Scripts.Shared.GameConfig)
local players=game.Players:GetPlayers();assert(#players>=2)
local a,b=players[1],players[2]
local originalPose=a.Character:GetPivot()
local originalCoins=a:GetAttribute("Coins")
local testCoins=0
local credited={}
local data={IsActive=function() return true end,CanAddCoins=function() return true end,AddCoins=function(player,coins) credited[player]=(credited[player] or 0)+coins;testCoins+=coins;return true end}
local function saleTotal()
 local total=0
 for _,player in game.Players:GetPlayers() do
  if data.IsActive(player) and data.CanAddCoins(player,Config.PotionReward) then total+=Config.PotionReward end
 end
 return total
end
local manager=Manager.new(data);manager.runtime.Name='GameplayIsolatedChecks';manager.runtime.Parent=workspace
manager.nextSpawn=math.huge
local checks=0
local function check(condition,label) assert(condition,label);checks+=1 end
local serial=0
local function item(kind)
 serial+=1
 local model=(if kind=='Body' then RS.Models.Characters.WhiteR15 else RS.Models.Items.Potion):Clone()
 model.Parent=manager.runtime
 if kind=='Body' then Ragdoll.Setup(model) end
 local value={id='test-'..serial,kind=kind,stage=if kind=='Body' then 'Unpainted' else 'Ready',location='Carried',version=1,model=model,holder=a,hits=3,covered={},strokes={},strokePoints=0,area=0,totalArea=if kind=='Body' then Surface.Total(model) else 0,progress=0,paintSeconds=0,streetSlot=false,nextWalk=0}
 manager.items[value.id]=value
 return value
end
local function equipSale(owner)
 local potion=item('Potion');potion.holder=nil;potion.location='Toolbar';potion.owner=owner
 potion.model:SetAttribute("ItemId", potion.id);potion.model:SetAttribute("OwnerUserId", owner.UserId)
 local backpack=owner:FindFirstChildOfClass("Backpack");potion.model.Parent=backpack or owner.Character
 local humanoid=owner.Character:FindFirstChildOfClass("Humanoid");humanoid:EquipTool(potion.model)
 return potion
end
local ok,result=pcall(function()
 for _=1,8 do local body=item('Body');manager:Pool(a);check(body.location=='Pool','pool deposit') end
 local oldest=manager.pool[1]
 check(not manager:Pool(a) and #manager.pool==8 and manager:Held(a)==nil,'pool anchor only accepts deposits')
 manager:Table(a);check(manager.tableId==oldest and manager.paint.player==a and #manager.pool==7,'table can still fetch the first pooled body')
 local token=manager.paint.token;manager:Table(b);check(manager.paint.player==a,'second painter cannot seize occupied table')
 local body=manager.items[oldest];body.progress=.42
 manager:EndPaint(a);check(a.Character:FindFirstChild("W01_RustyPan")~=nil,"leaving paint re-equips initial weapon");manager:Table(b);check(manager.paint.player==b and body.progress==.42,'interrupted painting retains progress for handoff')
 local area=body.area;manager:Paint(a,{action='Paint',session=token,samples={}});check(body.area==area and manager.paint.player==b,'stale session rejected')
 manager:EndPaint(b);Carry.Take(body,a);manager.tableId=nil
 manager:Altar(a);check(manager.altarId==nil and body.holder==a,'unpainted altar input rejected')
 body.stage='Painted';manager:Altar(a);check(manager.altarId==body.id and body.stage=='Converting','completed body enters altar')
 local full=Config.ShelfCapacity
 for _=1,full do local potion=item('Potion');potion.holder=nil;potion.location='Shelf';table.insert(manager.shelf,potion.id) end
 manager.altarEnds=workspace:GetServerTimeNow()-1;manager.nextUpdate=0;manager:Update()
 check(manager.altarId==body.id and #manager.shelf==full,'full shelf keeps completed conversion waiting')
 manager:Shelf(a)
 local equipped=a.Character and a.Character:FindFirstChild("Potion")
 check(#manager.shelf==full-1 and manager:Held(a)==nil and equipped~=nil and equipped:IsA("Tool") and equipped.Parent==a.Character,'shelf pickup equips one potion')
 manager.nextUpdate=0;manager:Update();check(manager.altarId==nil and #manager.shelf==full and manager.items[body.id]==nil,'waiting conversion outputs once after slot freed')
 manager.players[a]={scope=Lifecycle.new(),lastAttack=0,lastRequest=0,lastSync=0,closing=false}
 local firstSale=saleTotal()
 manager:Submit(a);check(testCoins==firstSale and a.Character:FindFirstChild("Potion")==nil,'submit consumes the equipped potion')
 manager:Submit(a);check(testCoins==firstSale,'duplicate submit cannot reward twice')
 local extra=item('Potion');extra.holder=nil;extra.location='Toolbar';extra.owner=a
 extra.model:SetAttribute("ItemId", extra.id);extra.model:SetAttribute("OwnerUserId", a.UserId)
 local backpack=a:FindFirstChildOfClass("Backpack");extra.model.Parent=backpack or a.Character
 local Scene=require(SS.Scripts.Scene)
 a.Character:PivotTo(CFrame.new(Scene.SigilPosition+Vector3.new(0,2,2)))
 manager.players[a].lastRequest=0
 manager:OnRequest(a,{action='Interact',target='Sigil',version=manager.stationVersions.Sigil-1})
 check(extra.model.Parent~=nil and testCoins==firstSale,'stale station request preserves the backpack potion')
 local humanoid=a.Character:FindFirstChildOfClass("Humanoid");humanoid:EquipTool(extra.model)
 manager.players[a].lastRequest=0
 local secondSale=saleTotal()
 manager:OnRequest(a,{action='Interact',target='Sigil',version=manager.stationVersions.Sigil})
 check(manager.items[extra.id]==nil and testCoins==firstSale+secondSale,'equipped potion sells exactly once')
 local present=game.Players:GetPlayers()
 local before={}
 for _,player in present do before[player]=credited[player] or 0 end
 data.CanAddCoins=function(player) return player~=b end
 local partial=equipSale(a)
 manager:Submit(a)
 local shared=manager.items[partial.id]==nil and partial.model.Parent==nil
 for _,player in present do
  local gained=(credited[player] or 0)-before[player]
  shared=shared and gained==(if player==b then 0 else Config.PotionReward)
 end
 check(shared,'capped player is skipped while others receive the full reward')
 data.CanAddCoins=function() return false end
 local blockedPotion=equipSale(a)
 local frozen=testCoins
 manager:Submit(a)
 check(manager.items[blockedPotion.id]~=nil and blockedPotion.model.Parent~=nil and testCoins==frozen,'unsellable when nobody can receive coins')
 local potion=item('Potion');Carry.Drop(potion,Vector3.new(0,-100,0));check(potion.location=='Ground' and potion.model.PrimaryPart.Position.Y>-40,'invalid ground drop recovers at shelf')
 return {checks=checks,passed=true}
end)
manager:EndPaint(a);manager:EndPaint(b)
for _,record in manager.players do record.scope:Destroy() end
manager.runtime:Destroy();manager.scope:Destroy()
a:SetAttribute("Coins",originalCoins);a.Character:PivotTo(originalPose)
assert(ok,result)
return result
