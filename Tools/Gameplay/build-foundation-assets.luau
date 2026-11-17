-- 基础框架 Edit 安装器：增量补齐网络、消息、固定窗口画布、模态遮罩与音量分组
assert(game.PlaceId == 110812537538556 and not game:GetService("RunService"):IsRunning(), "DemonShop Edit required")
local rs, ss = game:GetService("ReplicatedStorage"), game:GetService("ServerStorage")
local function Ensure(parent, name, class)
 local value = parent:FindFirstChild(name)
 if not value then value = Instance.new(class); value.Name = name; value.Parent = parent end
 assert(value.ClassName == class, "Instance class conflict: " .. name)
 return value
end
local remotes = Ensure(rs, "RemoteEvents", "Folder")
for _, name in { "FoundationRequest", "NotifyPlayerInfoInit", "NotifyPlayersOtherPlayerInfoInit", "NotifyPlayerAcquiredGamePass", "NotifyPlayerLeft", "RequestSetBGMVolume", "RequestSetSoundEffectVolume", "RequestSetVibrationsOnOffState" } do Ensure(remotes, name, "RemoteEvent") end
local messages = Ensure(rs, "BindableEvents", "Folder")
for _, name in { "CloseWindow", "OpenWindow", "LocalPlayerInfoInit", "OtherPlayerInfoInit", "LocalPlayerAcquiredGamePass" } do Ensure(messages, name, "BindableEvent") end
Ensure(Ensure(ss, "BindableEvents", "Folder"), "PlayerInfoInit", "BindableEvent")
local gui = rs.UI.GameScreenGui
if not gui:FindFirstChild("WindowCanvas") then
 local canvas = Instance.new("Frame")
 canvas.Name = "WindowCanvas"
 canvas.Size = UDim2.fromOffset(1920, 1080)
 canvas.AnchorPoint = Vector2.new(.5, .5)
 canvas.Position = UDim2.fromScale(.5, .5)
 canvas.BackgroundTransparency = 1
 canvas.Active = false
 canvas.Parent = gui
 Ensure(canvas, "UIScale", "UIScale")
end
if not gui:FindFirstChild("ModalButton") then
 local modal = Instance.new("ImageButton")
 modal.Name = "ModalButton"
 modal.Size = UDim2.fromScale(1, 1)
 modal.BackgroundColor3 = Color3.new(0, 0, 0)
 modal.BackgroundTransparency = .4
 modal.Image = ""
 modal.Modal = true
 modal.AutoButtonColor = false
 modal.Visible = false
 modal.ZIndex = 101
 modal.Parent = gui
end
local groups = Ensure(game:GetService("SoundService"), "SoundGroups", "Folder")
Ensure(groups, "BGM", "SoundGroup")
local sfx = Ensure(groups, "SoundEffects", "SoundGroup")
for _, value in rs.Models:GetDescendants() do
 if value:IsA("Sound") and not value.SoundGroup then value.SoundGroup = sfx end
end
local legacy=remotes:FindFirstChild("FoundationNotify")
if legacy then legacy:Destroy() end
local starter=game:GetService("StarterGui"):FindFirstChild("GameScreenGui")
if starter then starter:Destroy() end
return "Foundation instances verified without replacing gameplay templates"
