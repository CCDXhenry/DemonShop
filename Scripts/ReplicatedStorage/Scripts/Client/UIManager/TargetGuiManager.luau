-- 目标标牌管理器：管理本地目标绑定、剩余耐久血条及释放
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(script.Parent.Parent.Parent.Shared.GameConfig)
local Lifecycle = require(script.Parent.Parent.Parent.Shared.LifecycleTool)
local Manager = {}
Manager.__index = Manager
export type DisplayState = { id: string?, adornee: BasePart?, visible: boolean, hits: number, hp: number?, maxHp: number?, touch: boolean }
type HitBar = { gui: BillboardGui, fill: ImageLabel, version: number, expiresAt: number, bound: boolean }
export type Manager = typeof(setmetatable(
	{} :: {
		gui: BillboardGui?, fill: ImageLabel?, shownFraction: number?, scope: Lifecycle.Lifecycle,
		hitBars: { [string]: HitBar }, stunnedUntil: { [string]: number },
	},
	Manager
))
function Manager.new(): Manager
	return setmetatable({ scope = Lifecycle.new(), hitBars = {}, stunnedUntil = {} }, Manager)
end
local function Remaining(hits: number, hp: number?, maxHp: number?): number
	if hp ~= nil and maxHp and maxHp > 0 then return math.clamp(hp / maxHp, 0, 1) end
	return math.clamp((Config.StunHits - hits) / Config.StunHits, 0, 1)
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
	local id = state.id or ""
	gui.Enabled = state.visible and state.adornee ~= nil and not stunned and self.hitBars[id] == nil and self.stunnedUntil[id] == nil
	local fill = self.fill
	local fraction = Remaining(state.hits, state.hp, state.maxHp)
	if fill and not stunned and self.shownFraction ~= fraction then
		self.shownFraction = fraction
		fill.Size = UDim2.fromScale(fraction, 1)
	end
end
function Manager.RemoveHit(self: Manager, id: string): ()
	local bar = self.hitBars[id]
	if bar then
		self.hitBars[id] = nil
		bar.gui:Destroy()
	end
end
local function CreateHitBar(version: number, expiresAt: number): HitBar
	local gui = (ReplicatedStorage.UI:WaitForChild("TargetGui") :: BillboardGui):Clone()
	gui.ResetOnSpawn = false
	return { gui = gui, fill = gui:FindFirstChild("FillImage", true) :: ImageLabel, version = version, expiresAt = expiresAt, bound = false }
end
function Manager.ShowHit(self: Manager, id: string, version: number, hits: number, started: number, head: BasePart?, hp: number?, maxHp: number?): ()
	if self.stunnedUntil[id] then return end
	local existing = self.hitBars[id]
	if existing and version <= existing.version then return end
	local expiresAt = started + Config.HitHealthSeconds
	if hits >= Config.StunHits then
		self.stunnedUntil[id] = expiresAt
		self:RemoveHit(id)
		local focus = self.gui
		if focus and focus.Adornee == head then focus.Enabled = false end
		return
	end
	local bar = existing or CreateHitBar(version, expiresAt)
	bar.version = version
	bar.expiresAt = expiresAt
	bar.fill.Size = UDim2.fromScale(Remaining(hits, hp, maxHp), 1)
	if head then
		bar.bound = true
		bar.gui.Adornee = head
		local focus = self.gui
		if focus and focus.Adornee == head then focus.Enabled = false end
	end
	bar.gui.Enabled = head ~= nil
	if not existing then
		self.hitBars[id] = bar
		bar.gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	end
end
function Manager.RefreshHits(self: Manager, now: number, resolveHead: (string) -> BasePart?): ()
	for id, expiresAt in self.stunnedUntil do
		if now >= expiresAt then self.stunnedUntil[id] = nil end
	end
	for id, bar in self.hitBars do
		local head = if now < bar.expiresAt then resolveHead(id) else nil
		if head then
			bar.bound = true
			if bar.gui.Adornee ~= head then bar.gui.Adornee = head end
			bar.gui.Enabled = true
		elseif bar.bound or now >= bar.expiresAt then
			self:RemoveHit(id)
		end
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
	self.shownFraction = nil
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.scope:Connect(gui.Destroying:Connect(function(): ()
		self.gui = nil
		self:Destroy()
	end))
end
function Manager.Destroy(self: Manager): ()
	self.scope:Destroy()
	for id in self.hitBars do self:RemoveHit(id) end
	table.clear(self.stunnedUntil)
	local gui = self.gui
	self.gui, self.fill, self.shownFraction = nil, nil, nil
	if gui then
		gui:Destroy()
	end
end
return Manager
