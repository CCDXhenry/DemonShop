-- 世界交互回归：执行正式规则和管理器，覆盖长按失效、隔离、输入互斥及释放
local Rules=require('./WorldInteractionRules')
local Manager=require('./WorldInteractionManager')
local B=require('./WorldInteractionBoundary')
local Config=require('./GameConfig')
local Texts=require('./GameTexts')
local checks=0
local function Check(value,message) assert(value,message);checks+=1 end
local snapshot={stationVersions={Pool=1,Table=1,Altar=1,Shelf=1,Sigil=1,Chute=1,ChutePickup=1,AutoOutput=1,AutoShelf=1},pool=0,shelf=0,chuteQueue=0,autoPaintedQueue=0,autoShelfCount=0,unlockedFacilities={},items={}}
local raw={id='raw',kind='Body',stage='Raw',location='Ground',version=1,hits=0}
local painted={id='painted',kind='Body',stage='Painted',location='Ground',version=1,hits=0}
local potion={id='potion',kind='Potion',stage='Ready',location='Ground',version=1,hits=0}
local items={raw=raw,painted=painted,potion=potion}
local function Action(target,held,potions,stack) local a=Rules.Resolve(target,snapshot,items,held,potions,stack);return a and a.action end
Check(Action('Pool',nil)==nil,'empty pool hidden')
Check(Action('Pool',raw)=='StoreBody','store unfinished')
Check(Action('Pool',painted)==nil and Action('Pool',potion)==nil,'pool rejects completed or potion')
snapshot.pool=Config.PoolCapacity + 5
Check(Action('Pool',raw)=='StoreBody','unlimited pool accepts unfinished body past visible limit')
Check(Action('Pool',nil)==nil,'stocked pool has no station pickup')
Check(Action('Table',nil)=='FetchAndPaint','fetch from pool and paint')
Check(Action('Table',raw)=='PlaceBody' and Action('Table',potion)==nil,'table requires unfinished body')
snapshot.pool=0
Check(Action('Table',nil)==nil,'empty table hidden')
snapshot.tableId='raw'
Check(Action('Table',nil)=='ContinuePainting' and Action('Table',raw)=='ContinuePainting','unfinished table can be resumed while carrying batch material')
snapshot.tableId='painted'
Check(Action('Table',nil)=='CollectRuneBody','completed table pickup')
snapshot.painter=2
Check(Action('Table',nil)==nil,'busy table hidden')
snapshot.painter=nil
Check(Action('Altar',painted)=='InsertRuneBody' and Action('Altar',raw)==nil,'altar accepts completed body')
snapshot.altarId='converting'
Check(Action('Altar',painted)=='InsertRuneBody','altar still accepts another completed body')
Check(Action('Shelf',nil)==nil,'empty shelf hidden')
snapshot.shelf=1
Check(Action('Shelf',nil)=='CollectPotion' and Action('Shelf',raw)==nil,'shelf hidden while carrying a body')
Check(Action('Sigil',nil,{stored=1,equipped=true})=='PromptOffer' and Action('Sigil',raw)==nil,'offer equipped potion')
Check(Action('Sigil',nil,{stored=2,equipped=false})=='PromptOffer','offer unequipped backpack potions at sigil')
Check(Action('raw',nil)=='PromptPickUp' and Action('raw',potion)==nil,'ground pickup requires free hands')
Check(Action('potion',nil)=='PromptPickUp' and Rules.Resolve('potion',snapshot,items,nil).object=='PromptPotion','ground potion text')
local other={id='other',kind='Body',stage='Raw',location='Ground',version=2,hits=Config.StunHits}
items.other=other
Check(Action('other',raw)=='PromptPickUp','pickup another body while carrying')
Check(Action('potion',raw)==nil,'potion pickup blocked while carrying a body')
Check(Action('Pool',nil,nil,{painted,raw})=='StoreBody','pool matches a lower unfinished body')
Check(Action('Altar',nil,nil,{raw,painted})=='InsertRuneBody','altar matches a lower rune body')
Check(Action('Shelf',nil,nil,{raw})==nil,'shelf hidden while a body stack is carried')
Check(Action('Chute',raw)==nil,'chute prompt hidden until A00 unlocked')
snapshot.unlockedFacilities={[1]=true}
Check(Action('Chute',raw)=='DepositBodies' and Action('Chute',painted)==nil,'chute accepts unfinished bodies after A00 unlock')
Check(Action('Chute',nil,nil,{painted,raw})=='DepositBodies','chute matches any unfinished body in carried stack')
Check(Action('ChutePickup',nil)==nil,'empty chute pickup hidden')
snapshot.chuteQueue=1
Check(Action('ChutePickup',nil)==nil and Action('ChutePickup',raw)==nil,'stocked chute has no station pickup')
for _, location in {'Pool','Chute'} do
	raw.location=location
	potion.location=location
	local action=Rules.Resolve('raw',snapshot,items,nil)
	Check(action and action.action=='PromptPickUp' and action.instant,'cage body has instant pickup: '..location)
	Check(Action('raw',potion)==nil and Action('potion',nil)==nil,'cage allows only bodies and requires a free shoulder: '..location)
end
raw.location='Pool';raw.toss={}
Check(Action('raw',nil)==nil,'pool deposit flight does not expose a pickup')
raw.location='Ground';raw.toss=nil;potion.location='Ground'
Check(Action('AutoOutput',nil)==nil,'empty auto output hidden')
snapshot.autoPaintedQueue=1
Check(Action('AutoOutput',nil)=='TakeAutoRuneBody' and Action('AutoOutput',potion)==nil,'auto output pickup yields painted body')
Check(Action('AutoShelf',nil)==nil,'empty auto shelf hidden')
snapshot.autoShelfCount=2
Check(Action('AutoShelf',nil)=='CollectAutoPotion' and Action('AutoShelf',raw)==nil,'auto shelf hidden while carrying body')
items.other=nil
raw.location='Street';raw.hits=Config.StunHits-1
Check(Action('raw',nil)==nil,'awake body has no prompt')
raw.hits=Config.StunHits
Check(Action('raw',nil)=='PromptPickUp','stunned body pickup')
raw.holder=2
Check(Action('raw',nil)==nil,'other carrier hides item')
raw.holder=nil
Check(Rules.Resolve('raw',nil,items,nil)==nil,'no snapshot no action')
local stationPrompt = B.CreatePrompt()
stationPrompt.MaxActivationDistance = 14
local anchor = {
	Parent = {},
	FindFirstChild = function(_, name) return if name == "WorldInteractionPrompt" then stationPrompt else nil end,
}
stationPrompt.Parent = anchor
local state = {snapshot=snapshot, items=items, enabled=true}
local manager = Manager.new({Shelf=anchor}, function() return state end)
manager:Refresh();manager:Refresh()
local prompt = manager.bindings.Shelf.prompt
Check(prompt == stationPrompt and prompt.Enabled and prompt.Parent == anchor, 'station uses preset workspace prompt as single source')
Check(prompt.MaxActivationDistance==14 and prompt.HoldDuration==0.5 and prompt.RequiresLineOfSight==true,'station uses existing range, hold duration, and line-of-sight')
Check(prompt.ObjectText=='POTION SHELF','native object text translated')
prompt.Triggered:Fire()
Check(#B.requests==0,'no hold token no request')
prompt.PromptButtonHoldBegan:Fire()
Check(manager:IsInputBlocked(),'hold blocks attack input')
prompt.PromptButtonHoldEnded:Fire();B.Flush();prompt.Triggered:Fire()
Check(#B.requests==0,'released hold cannot trigger later')
prompt.PromptButtonHoldBegan:Fire();prompt.Triggered:Fire();prompt.Triggered:Fire()
Check(#B.requests==1 and B.requests[1].target=='Shelf' and B.requests[1].version==1,'one request per hold uses bound target/version')
prompt.PromptButtonHoldBegan:Fire();snapshot.stationVersions.Shelf+=1;prompt.Triggered:Fire()
Check(#B.requests==1,'version race rejected before refresh')
manager:Refresh()
Check(not prompt.Enabled,'state change disables engine hold for a frame')
manager:Refresh();prompt.PromptButtonHoldBegan:Fire();state.held=raw;prompt.Triggered:Fire()
Check(#B.requests==1,'hands changed during hold cancels')
state.held=nil;manager:Refresh();manager:Refresh();prompt.PromptButtonHoldBegan:Fire();state.enabled=false;prompt.Triggered:Fire()
Check(#B.requests==1,'disabled state rejects in-flight hold')
manager:Refresh();Check(not prompt.Enabled,'disabled state hides prompt')
state.enabled=true;manager:Refresh();manager:Refresh();prompt.PromptButtonHoldBegan:Fire();prompt.PromptHidden:Fire();prompt.Triggered:Fire()
Check(#B.requests==1,'out of range or occluded hidden prompt cancels hold')
raw.model={Parent={},PrimaryPart={Parent={}}}
manager:Refresh();manager:Refresh()
local itemPrompt=manager.bindings.raw.prompt
Check(itemPrompt.Enabled and itemPrompt.Parent==raw.model,'pickup prompt excludes the whole model from native visibility checks')
Check(itemPrompt.RequiresLineOfSight==false and itemPrompt.MaxActivationDistance==Config.InteractionRange,'body prompt clones UI template, disables line-of-sight, and keeps interaction range')
Check(itemPrompt.ActionText=='PICK UP' and itemPrompt.ObjectText=='BODY','pickup prompt has concise localized text')
Check(itemPrompt.HoldDuration==0 and manager.bindings.raw.holding==nil,'body prompt has no hold token')
itemPrompt.Triggered:Fire()
Check(#B.requests==2 and B.requests[2].target==raw.id and B.requests[2].version==raw.version,'model prompt sends the item target and version')
itemPrompt.PromptButtonHoldBegan:Fire()
raw.version+=1;itemPrompt.Triggered:Fire()
Check(#B.requests==2,'instant pickup rejects stale version before refresh')
raw.model={Parent={},PrimaryPart={Parent={}}};itemPrompt.Triggered:Fire()
Check(#B.requests==2,'replaced model rejects stale prompt before next refresh')
manager:Refresh()
Check(itemPrompt.destroyed and itemPrompt.Triggered:Count()==0 and B.translations[itemPrompt]==nil,'model replacement releases signals and translation')
local replacement=manager.bindings.raw.prompt
raw.model.PrimaryPart=nil;manager:Refresh()
Check(replacement.destroyed and manager.bindings.raw==nil,'model without a primary part releases prompt')
raw.model.PrimaryPart={Parent={}};manager:Refresh()
local restored=manager.bindings.raw.prompt
items.raw=nil;manager:Refresh()
Check(restored.destroyed and manager.bindings.raw==nil,'removed item releases prompt')
potion.model={Parent={},PrimaryPart={Parent={}}}
manager:Refresh();manager:Refresh()
local potionPrompt=manager.bindings.potion.prompt
Check(potionPrompt.Enabled and potionPrompt.HoldDuration==0.5,'ground potion retains template hold duration')
Check(potionPrompt.RequiresLineOfSight==false and potionPrompt.MaxActivationDistance==Config.InteractionRange,'ground potion disables line-of-sight and keeps interaction range')
potionPrompt.Triggered:Fire()
Check(#B.requests==2,'ground potion requires a hold token')
local getEntry=Texts.GetEntry
for _,missing in {'CollectPotion','PromptShelf'} do
	Texts.GetEntry=function(textId) return if textId==missing then nil else getEntry(textId) end
	snapshot.stationVersions.Shelf+=1
	manager:Refresh();manager:Refresh()
	Check(not prompt.Enabled,'missing action or object text stays disabled across refreshes')
	prompt.PromptButtonHoldBegan:Fire();prompt.Triggered:Fire()
	Check(#B.requests==2,'missing text cannot issue interaction requests')
end
Texts.GetEntry=getEntry
snapshot.stationVersions.Shelf+=1
manager:Refresh();manager:Refresh()
Check(prompt.Enabled,'valid text resumes on next signature change')
manager:Destroy();manager:Destroy();B.Flush()
Check(not prompt.Enabled and not prompt.destroyed and next(manager.bindings)==nil and next(B.translations)==nil,'idempotent teardown leaves station workspace prompt intact while disabling')
print('PASS: '..checks..' world interaction assertions (production rules/controller; native engine events mocked)')
