-- 目标标牌管理器：管理本地目标绑定、剩余耐久血条及释放
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(script.Parent.Parent.Parent.Shared.GameConfig)
local Lifecycle = require(script.Parent.Parent.Parent.Shared.LifecycleTool)
local Manager = {}
Manager.__index = Manager
export type DisplayState = { adornee: BasePart?, visible: boolean, hits: number, touch: boolean }
export type Manager = typeof(setmetatable(
	{} :: { gui: BillboardGui?, fill: ImageLabel?, shownHits: number?, scope: Lifecycle.Lifecycle },
	Manager
))
function Manager.new(): Manager
	return setmetatable({ scope = Lifecycle.new() }, Manager)
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
	local stunned = state.hits >= Config.StunHits
	gui.Enabled = state.visible and state.adornee ~= nil and not stunned
	local fill = self.fill
	if fill and not stunned and self.shownHits ~= state.hits then
		self.shownHits = state.hits
		local total = Config.StunHits
		local remaining = if total > 0 then math.clamp((total - state.hits) / total, 0, 1) else 0
		fill.Size = UDim2.fromScale(remaining, 1)
	end
end
function Manager.Init(self: Manager): ()
	if self.gui then
		return
	end
	self.scope = Lifecycle.new()
	local gui = (ReplicatedStorage.UI:WaitForChild("TargetGui") :: BillboardGui):Clone()
	self.gui = gui
	self.fill = gui:FindFirstChild("FillImage", true) :: ImageLabel
	self.shownHits = nil
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.scope:Connect(gui.Destroying:Connect(function(): ()
		self.gui = nil
		self:Destroy()
	end))
end
function Manager.Destroy(self: Manager): ()
	self.scope:Destroy()
	local gui = self.gui
	self.gui, self.fill, self.shownHits = nil, nil, nil
	if gui then
		gui:Destroy()
	end
end
return Manager
