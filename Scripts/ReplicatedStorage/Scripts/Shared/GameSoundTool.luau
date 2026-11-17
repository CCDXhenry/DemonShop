-- 通用声音工具：模板播放、音量设置、空间音效池和退出清理
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Config = require(script.Parent.GameConfig)
local Lifecycle = require(script.Parent.LifecycleTool)
local soundsPools: { [Sound]: { Sound } } = {}
local sounds: { [Sound]: boolean } = {}
local active: { [Sound]: boolean } = {}
local attachments: { Attachment } = {}
local scope: Lifecycle.Lifecycle? = nil
local carrier: Part? = nil
local bgm: Sound? = nil
local vibrationOn = true
local Tool = {}
local function Group(name: string): SoundGroup?
 local folder = SoundService:FindFirstChild("SoundGroups")
 local value = folder and folder:FindFirstChild(name)
 return if value and value:IsA("SoundGroup") then value else nil
end
function Tool.Init(): () if not scope then scope = Lifecycle.new() end end
function Tool.GetSoundTemplate(name: string): Sound?
 local folder = ReplicatedStorage:FindFirstChild("Sounds")
 local value = folder and folder:FindFirstChild(name)
 return if value and value:IsA("Sound") and value.SoundId ~= "" then value else nil
end
local function Recycle(sound: Sound, template: Sound): ()
 if not active[sound] then return end
 active[sound] = nil
 local parent = sound.Parent
 sound.Parent = nil
 if parent and parent:IsA("Attachment") then parent.Parent = nil; table.insert(attachments, parent) end
 local pool = soundsPools[template]
 if pool then table.insert(pool, sound) else sound:Destroy(); sounds[sound] = nil end
end
local function Acquire(template: Sound): Sound
 Tool.Init()
 local pool = soundsPools[template]
 if not pool then
  pool = {}
  soundsPools[template] = pool
 end
 local recycled = table.remove(pool)
 local sound: Sound
 if recycled then
  sound = recycled
 else
  local cloned = template:Clone()
  sound = cloned
  sounds[cloned] = true
  local currentScope = scope
  assert(currentScope)
  currentScope:Connect(cloned.Ended:Connect(function(): () Recycle(cloned, template) end))
  currentScope:Connect(cloned.Stopped:Connect(function(): () Recycle(cloned, template) end))
 end
 sound.Volume, sound.PlaybackSpeed, sound.TimePosition = template.Volume, template.PlaybackSpeed, 0
 active[sound] = true
 return sound
end

function Tool.PlayGlobal(template: Sound, looped: boolean?, soundGroup: SoundGroup?): Sound?
 local sound = Acquire(template)
 sound.SoundGroup = soundGroup or Group("SoundEffects")
 sound.Looped = looped == true
 sound.Parent = SoundService
 sound:Play()
 return sound
end
function Tool.PlayLocal(template: Sound, position: Vector3, looped: boolean?, soundGroup: SoundGroup?): Sound?
 if not carrier then
  local part = Instance.new("Part")
  part.Name = "LocalSoundEffects"
  part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery, part.Transparency = true, false, false, false, 1
  part.Parent = workspace
  carrier = part
 end
 local attachment = table.remove(attachments) or Instance.new("Attachment")
 attachment.Parent = carrier
 attachment.WorldCFrame = CFrame.new(position)
 local sound = Acquire(template)
 sound.SoundGroup = soundGroup or Group("SoundEffects")
 sound.Looped = looped == true
 sound.Parent = attachment
 sound:Play()
 return sound
end
function Tool.Play(name: string, position: Vector3?, multiplier: number?): Sound?
 local template = Tool.GetSoundTemplate(name)
 if not template then return nil end
 local sound = if position then Tool.PlayLocal(template, position, false) else Tool.PlayGlobal(template, false)
 if sound then sound.Volume = template.Volume * (multiplier or 1) end
 return sound
end
function Tool.PlayBGM(): Sound?
 if bgm then return bgm end
 if Config.BGMTemplate == "" then return nil end
 local template = Tool.GetSoundTemplate(Config.BGMTemplate)
 if not template then return nil end
 bgm = Tool.PlayGlobal(template, true, Group("BGM"))
 return bgm
end
function Tool.StopBGM(): () if bgm then bgm:Stop(); bgm = nil end end
function Tool.SetBGMVolume(volume: number): () local group = Group("BGM"); if group then group.Volume = math.clamp(volume, 0, 1) end end
function Tool.SetSoundEffectVolume(volume: number): () local group = Group("SoundEffects"); if group then group.Volume = math.clamp(volume, 0, 1) end end
function Tool.SetVibrationsOnOffState(value: boolean): () vibrationOn = value end
function Tool.IsVibrationEnabled(): boolean return vibrationOn end
function Tool.Destroy(): ()
 if scope then scope:Destroy(); scope = nil end
 for sound in sounds do sound:Destroy() end
 for _, attachment in attachments do attachment:Destroy() end
 if carrier then carrier:Destroy(); carrier = nil end
 table.clear(sounds); table.clear(active); table.clear(soundsPools); table.clear(attachments)
 bgm = nil
 vibrationOn = true
end
return Tool
