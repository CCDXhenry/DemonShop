-- 目标标牌管理器：管理本地目标绑定、命中提示、翻译及释放
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(script.Parent.Parent.Parent.Shared.GameConfig)
local ProcessingText = require(script.Parent.Parent.ProcessingTextTool)
local Lifecycle = require(script.Parent.Parent.Parent.Shared.LifecycleTool)
local Manager = {}
Manager.__index = Manager
export type DisplayState = { adornee: BasePart?, visible: boolean, hits: number, touch: boolean }
export type Manager = typeof(setmetatable(
	{} :: { gui: BillboardGui?, count: TextLabel?, key: TextLabel?, texts: ProcessingText.Controller, scope: Lifecycle.Lifecycle },
	Manager
))
function Manager.new(): Manager
	return setmetatable({ texts = ProcessingText.new(), scope = Lifecycle.new() }, Manager)
end
function Manager.Refresh(self: Manager, state: DisplayState): ()
	self:Init()
	local gui = self.gui
	if not gui then
		return
	end
	if state.adornee then
		gui.Adornee = state.adornee
	else
		gui:ResetPropertyToDefault("Adornee")
	end
	gui.Enabled = state.visible and state.adornee ~= nil
	local count, key = self.count, self.key
	if count then
		self.texts:Bind(
			count,
			if state.hits >= Config.StunHits
				then { textId = "TargetStunned" }
				else { textId = "HitCount", args = { tostring(state.hits), tostring(Config.StunHits) } }
		)
	end
	if key then
		key.Visible = state.hits >= Config.StunHits and not state.touch
	end
end
function Manager.Init(self: Manager): ()
	if self.gui then
		return
	end
	self.scope = Lifecycle.new()
	local gui = (ReplicatedStorage.UI:WaitForChild("TargetGui") :: BillboardGui):Clone()
	self.gui = gui
	self.count = gui:FindFirstChild("CountText", true) :: TextLabel
	self.key = gui:FindFirstChild("KeyText", true) :: TextLabel
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.scope:Connect(gui.Destroying:Connect(function(): ()
		self.gui = nil
		self:Destroy()
	end))
end
function Manager.Destroy(self: Manager): ()
	self.scope:Destroy()
	self.texts:Destroy()
	local gui = self.gui
	self.gui, self.count, self.key = nil, nil, nil
	if gui then
		gui:Destroy()
	end
end
return Manager
