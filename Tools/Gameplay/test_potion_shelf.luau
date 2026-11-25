-- 药水架陈列回归：验证批量出货、动作打断、槽位复用与重同步
local Roblox = require("@lune/roblox")
local Instance, CFrame, Vector3 = Roblox.Instance, Roblox.CFrame, Roblox.Vector3
local rs = Instance.new("Folder")
local models = Instance.new("Folder")
models.Name = "Models"
models.Parent = rs
local items = Instance.new("Folder")
items.Name = "Items"
items.Parent = models
local template = Instance.new("Tool")
template.Name = "Potion"
local body = Instance.new("Part")
body.Name = "Handle"
body.Parent = template
local light = Instance.new("PointLight")
light.Brightness = 2
light.Parent = body
template.Parent = items
local Boundary = {
	ReplicatedStorage = rs,
	workspace = Instance.new("Folder"),
	PivotTo = function(model, pose)
		model.WorldPivot = pose
	end,
}

local function Run(View)
	local first, second, third = CFrame.new(3, 5, -8), CFrame.new(2, 5, -8), CFrame.new(4, 5, -8)
	local view = View.new(Vector3.new(8, 2, -5))
	local function bottle(id)
		return view.bottles[id].model
	end
	local function close(a, b)
		return (a.Position - b.Position).Magnitude < 0.001
	end

	view:Apply({ a = first }, false, 1)
	local original = bottle("a")
	assert(close(original.WorldPivot, first) and not next(view.entering), "initial stock is placed immediately")
	local handle = original.Handle
	assert(handle.Anchored and not handle.CanQuery and not handle.CanTouch and not handle.CanCollide, "display model is visual only")
	view:Apply({ a = first, b = second, c = third }, true, 2)
	assert(bottle("a") == original and view.entering.b == view.entering.c, "batch deposits animate together while existing stock stays put")
	assert(close(bottle("b").WorldPivot, second + Vector3.yAxis * 0.42), "new stock begins above its slot")
	view:Step(2.1)
	local b, c = bottle("b"), bottle("c")
	local interrupted = b.WorldPivot
	view:Apply({}, true, 2.1)
	assert(not next(view.entering) and close(view.departing.b.from, interrupted), "collection starts at the visible mid-deposit pose")
	view:Step(2.22)
	assert(b.Handle.LocalTransparencyModifier > 0 and b.Handle.PointLight.Brightness < 2, "collection fades the bottle and its light")
	view:Apply({ refill = second }, true, 2.22)
	assert(b.Parent == nil and c.Parent ~= nil, "refill removes only the departure sharing its slot")
	view:Step(2.35)
	assert(c.Parent == nil and original.Parent == nil and not next(view.departing), "departures release their instances at the end")
	view:Apply({ refill = second, extra = third }, true, 2.35)
	view:Apply({ refill = second }, false, 2.36)
	assert(close(bottle("refill").WorldPivot, second) and #view.folder:GetChildren() == 1 and not next(view.entering), "resync settles current stock and clears transients")
	view:Apply({}, true, 2.4)
	view:Apply({}, false, 2.41)
	assert(not next(view.departing) and #view.folder:GetChildren() == 0, "resync cancels an in-flight collection")
	view:Destroy()
	assert(#Boundary.workspace:GetChildren() == 0, "destroy releases the client folder")
	print("PASS: 11 potion shelf assertions (production presentation; model pivot boundary mocked)")
end

return { Boundary = Boundary, Run = Run }
