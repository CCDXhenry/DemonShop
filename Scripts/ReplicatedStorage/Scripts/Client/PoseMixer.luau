-- 在父关节局部轴合成动画、接触与冲击，按运动学掩码一次提交。
--!strict
local Adapter = require(script.Parent.JointAdapter)
local Spring = require(script.Parent.Spring)
local Contact = require(script.Parent.SoftContact)
local Mixer = {}
local order={"Root","Waist","Neck","LeftShoulder","RightShoulder","LeftElbow","RightElbow","LeftWrist","RightWrist",
	"LeftHip","RightHip","LeftKnee","RightKnee","LeftAnkle","RightAnkle"}
local function Rotation(v: Vector3): CFrame
	local angle=v.Magnitude
	return if angle>0.000001 then CFrame.fromAxisAngle(v/angle,angle) else CFrame.identity
end
function Mixer.Offset(space: CFrame, contact: Vector3, impact: Vector3, shift: Vector3, joint: Adapter.Joint): CFrame
	local rotation=Rotation(space:VectorToWorldSpace(contact))*Rotation(space:VectorToWorldSpace(impact))
	local axis,angle=rotation:ToAxisAngle()
	local vector=axis*angle
	local limit=joint.limit
	-- 球窝附件的 X 为扭转轴；限制旋转向量的扭转与摆动，最后再限制合成角。
	if limit then
		local swing=Spring.Limit(Vector3.new(0,vector.Y,vector.Z),math.rad(limit.cone))
		vector=Spring.Limit(swing+Vector3.xAxis*math.clamp(vector.X,math.rad(limit.lower),math.rad(limit.upper)),math.rad(limit.cone))
	else
		vector=Spring.Limit(vector,math.rad(18))
	end
	return CFrame.new(space:VectorToWorldSpace(Spring.Limit(shift,0.14)))*Rotation(vector)
end
function Mixer.Commit(joints: Adapter.Map, sources: Adapter.Map, mask: {[string]: boolean}, root: CFrame,
	contact: Contact.State?, impacts: {[string]: Vector3}?, shift: Vector3, legacy: ((string)->CFrame?)?, step: number,
	history: {[string]: CFrame}, dt: number, speedLimit: number)
	for _,name in order do
		local source,joint=sources[name],joints[name]
		mask[name]=not Adapter.IsKinematic(source)
		if mask[name] then joint.submissions=0; history[name]=nil; continue end
		local spring=contact and contact.springs[name]
		local hit=impacts and impacts[name]
		local offset=if legacy then legacy(name) else nil
		if spring or hit or (name=="Root" and shift.Magnitude>0) then
			local space=(source.parent.CFrame*source.c0):ToObjectSpace(root)
			local mixed=Mixer.Offset(space,if spring then spring.Position else Vector3.zero,hit or Vector3.zero,
				if name=="Root" then shift else Vector3.zero,joint)
			offset=if offset then mixed*offset else mixed
		end
		if not legacy and (offset or history[name]) then
			local previous=history[name] or CFrame.identity
			local target=offset or CFrame.identity
			local _,angle=(previous.Rotation:Inverse()*target.Rotation):ToAxisAngle()
			local fraction=math.min(1,speedLimit*math.clamp(dt,0,0.1)/math.max(angle,0.000001))
			offset=if fraction<1 then CFrame.new(target.Position)*previous.Rotation:Lerp(target.Rotation,fraction) else offset
			if offset then history[name]=offset else history[name]=nil end
		end
		Adapter.Commit(joint,Adapter.Read(source),offset,step)
	end
end
return Mixer
