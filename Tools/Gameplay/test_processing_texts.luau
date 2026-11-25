-- 加工文案回归：生产规则分支、参数、英文回退、延迟刷新及释放
local Hints = require('./Hints')
local Texts = require('./GameTexts')
local B = require('./Boundary')
local Tool = require('./ProcessingTextTool')
local Translation = require('./TranslationTool')
local count = 0
local function Check(value, expected)
	assert(value == expected, tostring(value) .. " ~= " .. tostring(expected)); count += 1
end
local function Snapshot(values)
	local snapshot = {pool=0,shelf=0,items={},altarEnds=0,stationVersions={}}
	for key,value in values or {} do snapshot[key]=value end
	return snapshot
end
local raw = {kind="Body",stage="Raw"}
local painted = {kind="Body",stage="Painted"}
local potion = {kind="Potion"}
for _,case in {
	{nil,nil,"StunNpc"}, {nil,painted,"ThrowAim"}, {nil,raw,"ThrowAim"},
	{Snapshot({shelf=1,altarId="a",tableId="t",pool=1}),nil,"PotionReady"},
	{Snapshot({altarId="a",tableId="t",pool=1}),nil,"AltarWorking"},
	{Snapshot({tableId="t",pool=1}),nil,"ReturnTable"}, {Snapshot({pool=1}),nil,"FetchPool"},
} do Check(Hints.Next(case[1],case[2]).textId,case[3]) end
local equippedPotions = {stored=1, equipped=true}
local storedPotions = {stored=1, equipped=false}
Check(Hints.Next(nil, nil, equippedPotions).textId, "TakePotion")
Check(Hints.Next(nil, raw, equippedPotions).textId, "ThrowAim")
Check(Hints.Next(nil, nil, storedPotions).textId, "TakePotion")
for _,case in {
	{"Pool",Snapshot({pool=20}),raw,"StoreBody"},
	{"Pool",nil,potion,"PoolUnfinishedOnly"},{"Pool",nil,painted,"PoolUnfinishedOnly"},
	{"Pool",nil,raw,"StoreBody"},{"Pool",Snapshot({pool=1}),nil,"TakeSharedBody"},{"Pool",nil,nil,"PoolEmpty"},
	{"Table",Snapshot({painter=2}),raw,"TableOtherPainter"},{"Table",Snapshot({painter=1}),raw,"PlaceBody"},
	{"Table",Snapshot({tableId="t",items={{id="t",stage="Painted"}}}),raw,"TableOccupied"},{"Table",nil,potion,"TableNeedsBody"},
	{"Table",Snapshot({tableId="t",items={{id="t",stage="Painting"}}}),raw,"ContinuePainting"},
	{"Table",Snapshot({tableId="t",items={{id="t",stage="Painted"}}}),nil,"CollectRuneBody"},
	{"Table",Snapshot({tableId="t",items={{id="t",stage="Painting"}}}),nil,"ContinuePainting"},
	{"Table",Snapshot({tableId="missing",pool=1}),nil,"FetchAndPaint"},{"Table",nil,nil,"TableEmpty"},
	{"Altar",Snapshot({altarId="a",shelf=13}),nil,"AltarBusy"},
	{"Altar",Snapshot({altarId="a",shelf=12}),nil,"AltarBusy"},
	{"Altar",nil,painted,"InsertRuneBody"},{"Altar",nil,raw,"AltarNeedsRuneBody"},
	{"Shelf",Snapshot({shelf=1}),raw,"HandsFullHint"},{"Shelf",Snapshot({shelf=1}),nil,"CollectPotion"},
	{"Shelf",nil,nil,"NoPotion"},{"Sigil",nil,nil,"OfferPotion",equippedPotions},{"Sigil",nil,nil,"OfferPotion",storedPotions},{"Sigil",nil,nil,"BringPotion"},
	{"Chute",Snapshot({}),raw,"ChuteLocked"},
	{"Chute",Snapshot({unlockedFacilities={[1]=true}}),raw,"DepositBodies"},
	{"Chute",Snapshot({unlockedFacilities={[1]=true}}),painted,"ChuteUnfinishedOnly"},
	{"Chute",Snapshot({unlockedFacilities={[1]=true}}),nil,"ChuteNeedsBody"},
	{"ChutePickup",Snapshot({chuteQueue=1}),nil,"TakeChuteBody"},
	{"ChutePickup",Snapshot({chuteQueue=0}),nil,"ChuteEmpty"},
	{"AutoOutput",Snapshot({autoPaintedQueue=1}),nil,"TakeAutoRuneBody"},
	{"AutoOutput",Snapshot({autoPaintedQueue=0}),nil,"AutoOutputEmpty"},
	{"AutoShelf",Snapshot({autoShelfCount=2}),nil,"CollectAutoPotion"},
	{"AutoShelf",Snapshot({autoShelfCount=0}),nil,"NoAutoPotion"},
	{"item-id",nil,nil,"CarryBody"},
} do Check(Hints.Action(case[1],case[2],case[3],1,case[5]).textId,case[4]) end
Check(Hints.Next(Snapshot({autoShelfCount=3}),nil).textId,"CollectAutoPotion")
Check(Hints.Action("Pool",nil,nil,1,nil,{painted,raw}).textId,"StoreBody")
Check(Hints.Action("Altar",nil,raw,1,nil,{raw,painted}).textId,"InsertRuneBody")
Check(Hints.Next(nil,nil,nil,{painted,raw}).textId,"ThrowAim")
Check(Hints.Next(nil,nil,equippedPotions).args[1],"237")
Check(Hints.Action("Sigil",nil,nil,1,equippedPotions).args[1],"237")
Check(Hints.Next(nil,nil).args,nil)
Check(Translation.FormatByKey(Texts.Hud.Stock.source,Texts.Hud.Stock.key,{"2","4"}),"POOL 2  |  POTIONS 4")
Check(Translation.FormatByKey(Texts.Hud.CarryingBodies.source,Texts.Hud.CarryingBodies.key,{"12","30"}),"CARRYING 12 / 30 BODIES")
Check(Texts.Entries,nil)
Check(Texts.GetEntry("UnknownId"),nil)
local expected, ordered, seen = {}, {}, {}
local groups = {Texts.Prompts,Texts.Guidance,Texts.Interactions,Texts.Hud,Texts.Combat,Texts.Notices,Texts.Automation,Texts.PersonalShop}
for _, group in groups do
	local names = {}
	for textId, entry in group do
		assert(not expected[textId]); expected[textId] = entry
		Check(Texts.GetEntry(textId),entry)
		table.insert(names,textId)
	end
	table.sort(names)
	for _, textId in names do table.insert(ordered,textId) end
end
Check(#ordered,141)
Check(Texts.GetEntry("ShopW01"),nil)
Check(Texts.GetEntry("ShopT0"),nil)
Check(Texts.GetEntry("PadNameA00"),nil)
Check(Texts.GetEntry("PadDescA00"),nil)
Check(Texts.GetEntry("ShopPendingCarry"),nil)
Check(Texts.Hud.ToolbarPotion.key,"Processing.ToolbarPotion")
Check(Texts.PersonalShop.ShopWeaponSlam.source,"SLAM AND PULL")
local index = 0
-- Match LocalizationExtension's generalized iteration, including nested independent cursors.
for key, entry in Texts do
	index += 1
	local textId = ordered[index]
	Check(typeof(entry.key),"string"); Check(typeof(entry.source),"string")
	Check(entry,expected[textId]); Check(seen[entry],nil); seen[entry] = true
	Check(key,if entry.key ~= "" then entry.key else textId)
	local innerCount = 0
	for _, inner in Texts do assert(typeof(inner.source)=="string"); innerCount += 1 end
	Check(innerCount,#ordered)
end
Check(index,#ordered)
index = 0
for _, entry in Texts do index += 1; Check(entry,expected[ordered[index]]) end
Check(index,#ordered)
-- Execute the unmodified production source as the plugin does, outside Roblox's module loader.
local source = require('@lune/fs').readFile('Scripts/ReplicatedStorage/Scripts/Shared/GameTexts.luau')
local captureTexts = require('@lune/luau').load(source)()
local capturedCount = 0
for key, keySource in captureTexts do
	capturedCount += 1
	local textId = ordered[capturedCount]
	Check(keySource.source,expected[textId].source)
	Check(keySource.key,expected[textId].key)
	Check(key,if keySource.key ~= "" then keySource.key else textId)
end
Check(capturedCount,#ordered)
for textId, entry in expected do
	if not string.find(entry.source,"{",1,true) then
		Check(Texts.ResolveLegacy(entry.source).textId,textId)
	else
		Check(Texts.ResolveLegacy(entry.source),nil)
	end
end
Check(Texts.ResolveLegacy("+123 COINS").args[1],"123")
Check(Texts.ResolveLegacy("HIT 2/5").textId,"HitCount")
Check(Texts.ResolveLegacy("HIT 2/5").args[2],"5")
Check(Texts.ResolveLegacy("STUNNED - E TO CARRY").textId,"StunnedCarry")
Check(Texts.ResolveLegacy("not-a-known-message"),nil)
local keys = {}
for _,entry in Texts do
	Check(string.match(entry.source,"[^%z\1-\127]"),nil)
	if string.find(entry.source,"{",1,true) then
		assert(entry.key ~= "" and not keys[entry.key]); keys[entry.key]=true
	else Check(entry.key,"") end
end
local label, changed = B.Label()
local tool = Tool.new()
tool:Bind(label,{textId="UnknownId",args={"ignored"}})
Check(label.Text,Texts.Notices.UnknownNotice.source)
tool:Bind(label,{textId="Coins",args={"237"}})
Check(label.Text,"COINS  237")
Check(label.AutoLocalize,false)
local fits = B.fits
tool:Bind(label,{textId="Coins",args={"237"}})
Check(B.fits,fits)
assert(coroutine.resume(B.pending,B.translator))
Check(label.Text,"en:Processing.Coins:237")
assert(B.fits > fits)
local translations = B.translations
tool:Bind(label,{textId="Coins",args={"237"}})
Check(B.translations,translations)
tool:Bind(label,{textId="Coins",args={"238"}})
Check(label.Text,"en:Processing.Coins:238")
B.locale="fr"; B.localeChanged.Fire()
Check(label.Text,"fr:Processing.Coins:238")
tool:Notice(label,nil,nil,"+123 COINS")
Check(label.Text,"fr:Processing.CoinsAwarded:123")
tool:Notice(label,nil,nil,"not-a-known-message")
Check(label.Text,"fr:Unable to complete this action. Please try again.")
tool:Clear(label)
B.localeChanged.Fire(); Check(label.Text,"")
tool:Bind(label,{textId="HandsEmpty"})
tool:Destroy()
Check(changed.Count(),0)
local old=label.Text
B.localeChanged.Fire(); Check(label.Text,old)
local billboard, billboardChanged = B.Label({})
local target = Tool.new(); local before=B.fits
target:Bind(billboard,{textId="HitCount",args={"2","5"}})
Check(B.fits,before); target:Destroy()

local padCtrl = Tool.new()
local titleLbl, titleChanged = B.Label({})
local prereqLbl, prereqChanged = B.Label({})
local priceLbl, priceChanged = B.Label({})
local noticeLbl = B.Label(nil)
padCtrl:BindSource(titleLbl, "FAST DROP CHUTE")
Check(titleLbl.AutoLocalize, false)
Check(titleLbl.Text, "fr:FAST DROP CHUTE")
padCtrl:Bind(prereqLbl, {textId="PadPrereqRequires", args={"FAST DROP CHUTE"}, argSources={[1]="FAST DROP CHUTE"}})
Check(prereqLbl.AutoLocalize, false)
Check(prereqLbl.Text, "fr:Processing.PadPrereqRequires:fr:FAST DROP CHUTE")
padCtrl:Bind(priceLbl, {textId="PadPrice", args={"250"}})
Check(priceLbl.Text, "fr:Processing.PadPrice:250")
padCtrl:Notice(noticeLbl, "FacilityUnlocked", {"Alice", "FAST DROP CHUTE"})
Check(noticeLbl.Text, "fr:Processing.FacilityUnlocked:Alice,fr:FAST DROP CHUTE")
B.locale = "de"; B.localeChanged.Fire()
Check(titleLbl.Text, "de:FAST DROP CHUTE")
Check(prereqLbl.Text, "de:Processing.PadPrereqRequires:de:FAST DROP CHUTE")
Check(priceLbl.Text, "de:Processing.PadPrice:250")
Check(noticeLbl.Text, "de:Processing.FacilityUnlocked:Alice,de:FAST DROP CHUTE")
Check(B.fits > before, true)
local fitsAfterScreen = B.fits
padCtrl:Bind(prereqLbl, {textId="PadPrereqUnlocked"})
Check(prereqLbl.Text, "de:PRE-REQ: UNLOCKED")
Check(B.fits, fitsAfterScreen)
padCtrl:Destroy()
Check(titleChanged.Count(), 0)
Check(prereqChanged.Count(), 0)
Check(priceChanged.Count(), 0)
Check(billboardChanged.Count(), 0)

-- Actual fitting code must measure localized ContentText while retaining the English source Text.
local R = require('@lune/roblox')
local Fitting = require('./TextFitting')
local static = {
	Text="SHORT",ContentText="A MUCH LONGER LOCALIZED SENTENCE",AutoLocalize=true,RichText=false,
	Size=R.UDim2.fromOffset(200,48),AbsoluteSize=R.Vector2.new(200,48),
	AutomaticSize=R.Enum.AutomaticSize.None,Font=R.Enum.Font.GothamBold,TextSize=32,
	GetAttribute=function() return 32 end,FindFirstChildOfClass=function() return nil end,
}
local translatedSize=Fitting.FitTextLabel(static)
static.AutoLocalize=false
local sourceSize=Fitting.FitTextLabel(static)
assert(translatedSize < sourceSize); Check(sourceSize,32)

-- Deserialize the saved recovery asset, so template changes are checked independently of Studio.
local roots = R.deserializeModel(require('@lune/fs').readFile('Assets/UI/ProjectTemplates.rbxm'))
local assets = {}; for _,asset in roots do assets[asset.Name]=asset end
local gui=assets.GameScreenGui
local root=gui.CenterFrame
Check(root.StatusFrame.TitleText.AutoLocalize,true)
Check(root.PaintFrame.TitleText.AutoLocalize,true)
Check(root.StatusFrame.CoinsText.AutoLocalize,false)
Check(root.HintText.AutoLocalize,false)
Check(root.BottomButtonsFrame.ToolButton.ToolNameText.AutoLocalize,false)
Check(root.BottomButtonsFrame.ToolButton.ToolLvText.AutoLocalize,false)
Check(root.BottomButtonsFrame.ToolButton.KeyCodeText.AutoLocalize,false)
Check(root:FindFirstChild("HintKeyText"),nil)
Check(root:FindFirstChild("InteractButton"),nil)
Check(assets.WorldInteractionPrompt.HoldDuration,0.5)
Check(assets.WorldInteractionPrompt.ClickablePrompt,true)
Check(assets.WorldInteractionPrompt.RequiresLineOfSight,true)
Check(assets.WorldInteractionPrompt.Enabled,false)
Check(assets.WorldInteractionPrompt.Style,R.Enum.ProximityPromptStyle.Default)
Check(assets.WorldInteractionPrompt.KeyboardKeyCode,R.Enum.KeyCode.E)
Check(assets.WorldInteractionPrompt.GamepadKeyCode,R.Enum.KeyCode.ButtonX)
Check(assets.WorldInteractionPrompt.Exclusivity,R.Enum.ProximityPromptExclusivity.OnePerButton)
Check(assets.WorldInteractionPrompt.MaxActivationDistance,8)
Check(root:FindFirstChild("DropButton"),nil)
Check(root:FindFirstChild("AttackButton"),nil)
Check(gui:FindFirstChild("TouchLandscapeFrame"),nil)
Check(gui:FindFirstChild("TouchPortraitFrame"),nil)
Check(gui:FindFirstChild("TouchPaintFrame"),nil)
Check(assets.TouchAttackFrame,nil)
Check(assets.ThrowStick,nil)
Check(assets.TouchSprintFrame,nil)
local tc = root.TouchControlsFrame
local attack = tc.TouchAttackFrame
Check(attack.Visible,true)
Check(attack:GetAttribute("MinimumTouchSize"),nil)
Check(attack:GetAttribute("JumpGap"),nil)
Check(attack:GetAttribute("JumpSizeRatio"),nil)
Check(attack.AttackButton:GetAttribute("AttackImage"),"rbxassetid://110366066946567")
Check(tostring(attack.AttackButton.ImageContent),tostring(R.Content.fromUri("rbxassetid://110366066946567")))
Check(attack.AttackButton.ImageRectOffset,R.Vector2.zero)
Check(attack.AttackButton.ActionText.Text,"ATTACK")
Check(attack.AttackButton.ActionText.AutoLocalize,true)
Check(attack.AttackButton.ActionText:GetAttribute("DesignTextSize"),26)
Check(attack.AttackButton.ActionText.UIStroke.StrokeSizingMode,R.Enum.StrokeSizingMode.ScaledSize)
Check(math.abs(attack.AttackButton.ActionText.UIStroke.Thickness - 0.05) < 1e-5, true)
local jump = tc.TouchJumpFrame
Check(jump.JumpButton.ActionText.Text,"JUMP")
Check(jump.JumpButton.ActionText.AutoLocalize,true)
Check(jump.JumpButton.ActionText:GetAttribute("DesignTextSize"),26)
local sprint = tc.TouchSprintFrame
Check(sprint.SprintButton.ActionText.Text,"SPRINT")
Check(sprint.SprintButton.ActionText.AutoLocalize,true)
Check(sprint.SprintButton.ActionText:GetAttribute("DesignTextSize"),24)
Check(assets.TargetGui.Size.X.Offset,0)
Check(assets.TargetGui.Size.Y.Offset,0)
Check(assets.TargetGui.Size.X.Scale > 0 and assets.TargetGui.Size.Y.Scale > 0, true)
Check(assets.TargetGui.ContentFrame.Size,R.UDim2.fromScale(1,1))
Check(assets.TargetGui.ContentFrame.UIScale.Scale,1)
Check(assets.TargetGui.ContentFrame:FindFirstChild("CountText"),nil)
Check(assets.TargetGui.ContentFrame:FindFirstChild("KeyText"),nil)
Check(tostring(assets.TargetGui.ContentFrame.FrameImage.ImageContent),tostring(R.Content.fromUri("rbxassetid://70702135277728")))
Check(tostring(assets.TargetGui.ContentFrame.ClipFrame.FillImage.ImageContent),tostring(R.Content.fromUri("rbxassetid://88599892799863")))
for _,value in gui:GetDescendants() do
	assert(value.Name ~= 'InteractButton' and value.Name ~= 'HintKeyText')
	if value:IsA('TextLabel') then
		Check(value.TextScaled,false); Check(value.TextWrapped,false)
		assert(value:GetAttribute('DesignTextSize'))
	elseif value:IsA('UIStroke') then Check(value.StrokeSizingMode,R.Enum.StrokeSizingMode.ScaledSize) end
end
print("Processing localization passed:",count,"checks")
