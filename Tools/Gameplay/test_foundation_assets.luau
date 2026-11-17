-- 恢复资产契约：离线重新反序列化正式导出，核验模板和基础事件可恢复
local fs=require('@lune/fs')
local R=require('@lune/roblox')
local count=0
local function check(value,label)assert(value,label);count+=1 end
local function load(path)
 local map={}
 for _,node in R.deserializeModel(fs.readFile(path)) do check(map[node.Name]==nil,'no duplicate exported root');map[node.Name]=node end
 return map
end
local ui=load('Assets/UI/ProjectTemplates.rbxm')
check(ui.GameScreenGui and ui.PaintFaceGui and ui.PaintCellFrame and ui.TargetGui,'all gameplay UI roots restored')
for _,name in {'CenterFrame','WindowCanvas'} do
 local frame=ui.GameScreenGui:FindFirstChild(name)
 check(frame and frame.Size==R.UDim2.fromOffset(1920,1080) and frame.AnchorPoint==R.Vector2.new(.5,.5),'fixed root canvas restored')
 check(frame:FindFirstChildOfClass('UIScale')~=nil,'canvas scale template restored')
end
check(ui.GameScreenGui.ModalButton:IsA('ImageButton') and not ui.GameScreenGui.ModalButton.Visible,'global backdrop restored')
local rs=load('Assets/Foundation/ReplicatedStorage.rbxm')
for _,name in {'NotifyPlayerInfoInit','NotifyPlayersOtherPlayerInfoInit','NotifyPlayerAcquiredGamePass','NotifyPlayerLeft','RequestSetBGMVolume','RequestSetSoundEffectVolume','RequestSetVibrationsOnOffState','FoundationRequest','GameRequest','GameNotify'} do
 check(rs.RemoteEvents:FindFirstChild(name) and rs.RemoteEvents[name]:IsA('RemoteEvent'),'remote restored: '..name)
end
check(rs.RemoteEvents:FindFirstChild('FoundationNotify')==nil,'retired remote excluded from recovery')
for _,name in {'CloseWindow','OpenWindow','LocalPlayerInfoInit','OtherPlayerInfoInit','LocalPlayerAcquiredGamePass'} do
 check(rs.BindableEvents:FindFirstChild(name)~=nil,'client message restored: '..name)
end
local ss=load('Assets/Foundation/ServerStorage.rbxm')
check(ss.BindableEvents.PlayerInfoInit:IsA('BindableEvent'),'server message restored')
local sounds=load('Assets/Foundation/SoundService.rbxm')
check(sounds.SoundGroups.BGM:IsA('SoundGroup') and sounds.SoundGroups.SoundEffects:IsA('SoundGroup'),'sound groups restored')
for _,roots in {ui,rs,ss,sounds} do
 for _,root in roots do for _,node in root:GetDescendants() do check(not node:IsA('LuaSourceContainer'),'recovery resources contain no script source') end end
end
print(string.format('PASS: %d restored asset assertions (actual RBXM deserialize)',count))
