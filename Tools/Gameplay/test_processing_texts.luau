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
	{nil,nil,"StunNpc"}, {nil,potion,"TakePotion"}, {nil,painted,"TakeRuneBody"}, {nil,raw,"TakeBody"},
	{Snapshot({shelf=1,altarId="a",tableId="t",pool=1}),nil,"PotionReady"},
	{Snapshot({altarId="a",tableId="t",pool=1}),nil,"AltarWorking"},
	{Snapshot({tableId="t",pool=1}),nil,"ReturnTable"}, {Snapshot({pool=1}),nil,"FetchPool"},
} do Check(Hints.Next(case[1],case[2]).textId,case[3]) end
for _,case in {
	{"Pool",nil,potion,"PoolUnfinishedOnly"},{"Pool",nil,painted,"PoolUnfinishedOnly"},
	{"Pool",nil,raw,"StoreBody"},{"Pool",Snapshot({pool=1}),nil,"TakeSharedBody"},{"Pool",nil,nil,"PoolEmpty"},
	{"Table",Snapshot({painter=2}),raw,"TableOtherPainter"},{"Table",Snapshot({painter=1}),raw,"PlaceBody"},
	{"Table",Snapshot({tableId="t"}),raw,"TableOccupied"},{"Table",nil,potion,"TableNeedsBody"},
	{"Table",Snapshot({tableId="t",items={{id="t",stage="Painted"}}}),nil,"CollectRuneBody"},
	{"Table",Snapshot({tableId="t",items={{id="t",stage="Painting"}}}),nil,"ContinuePainting"},
	{"Table",Snapshot({tableId="missing",pool=1}),nil,"FetchAndPaint"},{"Table",nil,nil,"TableEmpty"},
	{"Altar",Snapshot({altarId="a",shelf=13}),nil,"ShelfFull"},
	{"Altar",Snapshot({altarId="a",shelf=12}),nil,"AltarBusy"},
	{"Altar",nil,painted,"InsertRuneBody"},{"Altar",nil,raw,"AltarNeedsRuneBody"},
	{"Shelf",Snapshot({shelf=1}),raw,"HandsFullHint"},{"Shelf",Snapshot({shelf=1}),nil,"CollectPotion"},
	{"Shelf",nil,nil,"NoPotion"},{"Sigil",nil,potion,"OfferPotion"},{"Sigil",nil,nil,"BringPotion"},
	{"item-id",nil,nil,"CarryBody"},
} do Check(Hints.Action(case[1],case[2],case[3],1).textId,case[4]) end
Check(Hints.Next(nil,potion).args[1],"237")
Check(Hints.Action("Sigil",nil,potion,1).args[1],"237")
Check(Hints.Next(nil,nil).args[1],"5")
Check(Translation.FormatByKey(Texts.Entries.Stock.source,Texts.Entries.Stock.key,{"2","11","4","13"}),"POOL 2/11  |  POTIONS 4/13")
local keys = {}
for _,entry in Texts.Entries do
	Check(string.match(entry.source,"[^%z\1-\127]"),nil)
	if string.find(entry.source,"{",1,true) then
		assert(entry.key ~= "" and not keys[entry.key]); keys[entry.key]=true
	else Check(entry.key,"") end
end
local label, changed = B.Label()
local tool = Tool.new()
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
local billboard = B.Label({})
local target = Tool.new(); local before=B.fits
target:Bind(billboard,{textId="HitCount",args={"2","5"}})
Check(B.fits,before); target:Destroy()

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
Check(root.HintKeyText.Text,"E"); Check(root.HintKeyText.AutoLocalize,false)
Check(root.InteractButton.LabelText.Text,"INTERACT"); Check(root.InteractButton.LabelText.AutoLocalize,true)
Check(root.DropButton.KeyText.Text,"Q"); Check(root.DropButton.LabelText.AutoLocalize,false)
for _,name in {"TouchLandscapeFrame","TouchPortraitFrame","TouchPaintFrame"} do
	for _,value in gui[name]:GetDescendants() do if value:IsA('TextLabel') then Check(value.AutoLocalize,value.Parent.Name ~= 'DropButton') end end
end
Check(assets.TargetGui.ContentFrame.CountText.AutoLocalize,false)
Check(assets.TargetGui.ContentFrame.KeyText.AutoLocalize,false)
for _,value in gui:GetDescendants() do
	if value:IsA('TextLabel') then
		Check(value.TextScaled,false); Check(value.TextWrapped,false)
		assert(value:GetAttribute('DesignTextSize'))
	elseif value:IsA('UIStroke') then Check(value.StrokeSizingMode,R.Enum.StrokeSizingMode.ScaledSize) end
end
print("Processing localization passed:",count,"checks")
