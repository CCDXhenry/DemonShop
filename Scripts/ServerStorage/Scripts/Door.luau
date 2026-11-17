-- 楼梯自动门：沿用现有门轴和双向开门规则，由唯一服务端入口释放连接
--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lifecycle = require(ReplicatedStorage.Scripts.Shared.LifecycleTool)
local Door = {}
function Door.Init(scope: Lifecycle.Lifecycle): ()
	local house = workspace.NeonContractDistrict:FindFirstChild("StairEntranceHouse")
	if not house then
		return
	end
	local leaf = house:FindFirstChild("AutoDoor")
	local center = house:GetAttribute("DoorCenter")
	if not leaf or not leaf:IsA("Model") or typeof(center) ~= "Vector3" then
		return
	end
	local closed = leaf:GetAttribute("ClosedPivot")
	if typeof(closed) ~= "CFrame" then
		return
	end
	local panel = leaf:FindFirstChild("DoorPanel")
	local angle, side, lastSeen, elapsed = 0, 0, 0, 0
	scope:Connect(RunService.Heartbeat:Connect(function(dt: number): ()
		elapsed += dt
		local nearest: Vector3? = nil
		local distance = math.huge
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local hum = character and character:FindFirstChildOfClass("Humanoid")
			if root and root:IsA("BasePart") and hum and hum.Health > 0 then
				local p = root.Position
				if math.abs(p.X - center.X) < 7 and math.abs(p.Z - center.Z) < 10 and math.abs(p.Y - center.Y) < 7 then
					local d = (p - center).Magnitude
					if d < distance then
						nearest = p
						distance = d
					end
				end
			end
		end
		local target = 0
		if nearest then
			lastSeen = elapsed
			if side == 0 then
				side = if nearest.Z >= center.Z then 1 else -1
			end
		end
		if nearest or elapsed - lastSeen <= 1.5 then
			target = side * math.rad(95)
		end
		local step = math.rad(135) * math.min(dt, 0.1)
		angle += math.clamp(target - angle, -step, step)
		leaf:PivotTo(closed * CFrame.Angles(0, angle, 0))
		local shut = math.abs(angle) < 0.005 and target == 0
		if panel and panel:IsA("BasePart") then
			panel.CanCollide = shut
		end
		if shut then
			side = 0
		end
	end))
end
return Door
