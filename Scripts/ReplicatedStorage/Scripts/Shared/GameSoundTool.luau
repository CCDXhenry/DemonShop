-- 通用声音工具：模板播放、音量设置、空间音效池和退出清理
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Config = require(script.Parent.GameConfig)
local Lifecycle = require(script.Parent.LifecycleTool)
local soundsPools: { [Sound]: { Sound } } = {}
local sounds: { [Sound]: boolean } = {}
local active: { [Sound]: boolean } = {}
local tokens: { [Sound]: number } = {}
local unpooled: { [Sound]: boolean } = {}
local dynamicTemplates: { [string]: Sound } = {}
local attachments: { Attachment } = {}
local scope: Lifecycle.Lifecycle? = nil
local carrier: Part? = nil
local bgm: Sound? = nil
local vibrationOn = true
local Tool = {}
export type SoundHandle = {
 Stop: (self: SoundHandle) -> (),
 IsPlaying: (self: SoundHandle) -> boolean,
}
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
 if bgm == sound then bgm = nil end
 local parent = sound.Parent
 sound.Parent = nil
 if parent and parent:IsA("Attachment") then parent.Parent = nil; table.insert(attachments, parent) end
 if unpooled[sound] then
  unpooled[sound] = nil
  sounds[sound] = nil
  tokens[sound] = nil
  sound:Destroy()
  return
 end
 sound.Looped = false
 local pool = soundsPools[template]
 if pool then table.insert(pool, sound) else sound:Destroy(); sounds[sound] = nil; tokens[sound] = nil end
end
local function Acquire(template: Sound, poolable: boolean?): Sound
 Tool.Init()
 local allowPool = poolable ~= false
 local pool = soundsPools[template]
 if allowPool and not pool then
  pool = {}
  soundsPools[template] = pool
 end
 local recycled = if allowPool and pool then table.remove(pool) else nil
 local sound: Sound
 if recycled then
  sound = recycled
 else
  local cloned = template:Clone()
  sound = cloned
  sounds[cloned] = true
  if not allowPool then
   unpooled[cloned] = true
  end
  local currentScope = scope
  assert(currentScope)
  currentScope:Connect(cloned.Ended:Connect(function(): () Recycle(cloned, template) end))
  currentScope:Connect(cloned.Stopped:Connect(function(): () Recycle(cloned, template) end))
 end
 tokens[sound] = (tokens[sound] or 0) + 1
 sound.Volume, sound.PlaybackSpeed, sound.TimePosition = template.Volume, template.PlaybackSpeed, 0
 active[sound] = true
 return sound
end

function Tool.PlayGlobal(template: Sound, looped: boolean?, soundGroup: SoundGroup?): Sound?
 local isLooped = looped == true
 local sound = Acquire(template, not isLooped)
 sound.SoundGroup = soundGroup or Group("SoundEffects")
 sound.Looped = isLooped
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
 local isLooped = looped == true
 local sound = Acquire(template, not isLooped)
 sound.SoundGroup = soundGroup or Group("SoundEffects")
 sound.Looped = isLooped
 sound.Parent = attachment
 sound:Play()
 return sound
end
function Tool.Play(name: string, position: Vector3?, multiplier: number?, looped: boolean?): Sound?
 local template = Tool.GetSoundTemplate(name)
 if not template then return nil end
 local isLooped = if looped ~= nil then looped else template.Looped
 local sound = if position then Tool.PlayLocal(template, position, isLooped) else Tool.PlayGlobal(template, isLooped)
 if sound then sound.Volume = template.Volume * (multiplier or 1) end
 return sound
end
function Tool.PlaySoundId(soundId: string, position: Vector3?, templateName: string?, multiplier: number?, looped: boolean?): Sound?
 local baseName = templateName or "AttackSwing"
 if soundId == "" then
  return Tool.Play(baseName, position, multiplier, looped)
 end
 local baseTemplate = Tool.GetSoundTemplate(baseName)
 if baseTemplate and baseTemplate.SoundId == soundId then
  return Tool.Play(baseName, position, multiplier, looped)
 end
 local cacheKey = baseName .. "\0" .. soundId
 local cached = dynamicTemplates[cacheKey]
 local template: Sound
 if cached then
  template = cached
 else
  local created: Sound = if baseTemplate then baseTemplate:Clone() else Instance.new("Sound")
  created.Name = baseName .. "_Dynamic"
  created.SoundId = soundId
  dynamicTemplates[cacheKey] = created
  template = created
 end
 local isLooped = if looped ~= nil then looped else template.Looped
 local sound = if position then Tool.PlayLocal(template, position, isLooped) else Tool.PlayGlobal(template, isLooped)
 if sound then sound.Volume = template.Volume * (multiplier or 1) end
 return sound
end
function Tool.Stop(sound: Sound?): ()
 if sound and active[sound] then
  sound:Stop()
 end
end
function Tool.PlayHandle(name: string, position: Vector3?, multiplier: number?, looped: boolean?): SoundHandle?
 local sound = Tool.Play(name, position, multiplier, looped)
 if not sound then return nil end
 local token = tokens[sound]
 local released = false
 return {
  Stop = function(_self: SoundHandle): ()
   if released then return end
   released = true
   if active[sound] and tokens[sound] == token then
    sound:Stop()
   end
  end,
  IsPlaying = function(_self: SoundHandle): boolean
   return not released and active[sound] == true and tokens[sound] == token and sound.IsPlaying
  end,
 }
end
function Tool.PlayBGM(): Sound?
 if bgm then return bgm end
 if Config.BGMTemplate == "" then return nil end
 local template = Tool.GetSoundTemplate(Config.BGMTemplate)
 if not template then return nil end
 bgm = Tool.PlayGlobal(template, true, Group("BGM"))
 return bgm
end
function Tool.StopBGM(): ()
 local current = bgm
 bgm = nil
 if current and active[current] then current:Stop() end
end
function Tool.SetBGMVolume(volume: number): () local group = Group("BGM"); if group then group.Volume = math.clamp(volume, 0, 1) end end
function Tool.SetSoundEffectVolume(volume: number): () local group = Group("SoundEffects"); if group then group.Volume = math.clamp(volume, 0, 1) end end
function Tool.SetVibrationsOnOffState(value: boolean): () vibrationOn = value end
function Tool.IsVibrationEnabled(): boolean return vibrationOn end
function Tool.Destroy(): ()
 if scope then scope:Destroy(); scope = nil end
 for sound in sounds do sound:Destroy() end
 for _, template in dynamicTemplates do template:Destroy() end
 for _, attachment in attachments do attachment:Destroy() end
 if carrier then carrier:Destroy(); carrier = nil end
 table.clear(sounds); table.clear(active); table.clear(tokens); table.clear(unpooled); table.clear(dynamicTemplates); table.clear(soundsPools); table.clear(attachments)
 bgm = nil
 vibrationOn = true
end
return Tool
