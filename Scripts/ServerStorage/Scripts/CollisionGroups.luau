-- 统一注册加工物理碰撞组及其碰撞矩阵
--!strict
local PhysicsService = game:GetService("PhysicsService")
local Physics = require(game:GetService("ReplicatedStorage").Scripts.Shared.PhysicsConfig)
local CollisionGroups = {}
local Body, Contained = Physics.BodyGroup, Physics.CageContainedGroup
local Cage, Baffle = Physics.CageWallGroup, Physics.ChuteBaffleGroup
local Fall, Scenery = Physics.FallGroup, Physics.SceneryGroup
local Walking = Physics.WalkingNpcGroup

function CollisionGroups.Init(): ()
	for _, name in { Body, Contained, Cage, Baffle, Fall, Scenery, Walking } do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	PhysicsService:CollisionGroupSetCollidable(Body, Body, true)
	PhysicsService:CollisionGroupSetCollidable(Contained, Contained, true)
	PhysicsService:CollisionGroupSetCollidable(Walking, Walking, false)
	for _, group in PhysicsService:GetRegisteredCollisionGroups() do
		local name = group.name
		if name ~= Contained and name ~= Cage and name ~= Baffle and name ~= Fall and name ~= Scenery and name ~= Walking then
			PhysicsService:CollisionGroupSetCollidable(Contained, name, PhysicsService:CollisionGroupsAreCollidable(Body, name))
			PhysicsService:CollisionGroupSetCollidable(Scenery, name, PhysicsService:CollisionGroupsAreCollidable("Default", name))
			PhysicsService:CollisionGroupSetCollidable(Walking, name, PhysicsService:CollisionGroupsAreCollidable(Body, name))
		end
		PhysicsService:CollisionGroupSetCollidable(Cage, name, false)
		PhysicsService:CollisionGroupSetCollidable(Baffle, name, name == Body or name == Contained)
		PhysicsService:CollisionGroupSetCollidable(Fall, name, name == Scenery)
	end
	PhysicsService:CollisionGroupSetCollidable(Walking, Body, false)
	PhysicsService:CollisionGroupSetCollidable(Walking, Contained, false)
	PhysicsService:CollisionGroupSetCollidable(Walking, Cage, false)
	PhysicsService:CollisionGroupSetCollidable(Walking, Baffle, false)
	PhysicsService:CollisionGroupSetCollidable(Walking, Fall, false)
	PhysicsService:CollisionGroupSetCollidable(Walking, Scenery, PhysicsService:CollisionGroupsAreCollidable(Body, Scenery))
	PhysicsService:CollisionGroupSetCollidable(Scenery, Contained, PhysicsService:CollisionGroupsAreCollidable(Scenery, Body))
	PhysicsService:CollisionGroupSetCollidable(Scenery, Scenery, PhysicsService:CollisionGroupsAreCollidable("Default", Scenery))
end

return CollisionGroups
