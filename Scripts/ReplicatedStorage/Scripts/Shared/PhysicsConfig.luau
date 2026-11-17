-- 布娃娃物理样板参数：关节范围、阻尼、速度保护与可缩放肩部锚点
--!strict
export type Joint = { cone: number, lower: number, upper: number, friction: number }
local Config = {
	BodyGroup = "RagdollBodies",
	MaximumLinearSpeed = 40,
	MaximumAngularSpeed = 9,
	CarrySwingScale = 0.55,
	TableJointFrictionScale = 0.25,
	TableNeckAngle = 45,
	TableJointPositionTolerance = 0.22,
	TableJointAngleTolerance = math.rad(12),
	TableObserverResponse = 18,
	-- 锚点以玩家 UpperTorso 局部坐标表达；身体 UpperTorso 对齐该点。
	ShoulderOffset = Vector3.new(0.65, 0.85, 0.65),
	CarryLiftSeconds = 0.28,
	CarryResponsiveness = 200,
	CarryOrientationResponsiveness = 100,
	CarryMaxVelocity = 150,
	CarryMaxAngularVelocity = 30,
	CarryForcePerMass = 50000,
	CarryTorquePerMass = 50000,
	CarrySwayRadians = math.rad(10),
	CarrySwayAccelerationScale = 0.002,
	CarrySwayResponse = 8,
	CarryRecoveryDistance = 3,
	CarryRecoveryGraceSeconds = 0.35,
	DropMaximumSpeed = 12,
	ReleaseGraceSeconds = 0.45,
	ShoulderRotation = CFrame.Angles(0, 0, math.pi / 2),
	Joints = {
		Neck = { cone = 28, lower = -35, upper = 35, friction = 18 },
		Waist = { cone = 25, lower = -20, upper = 20, friction = 45 },
		Shoulder = { cone = 75, lower = -55, upper = 55, friction = 20 },
		Elbow = { cone = 55, lower = -8, upper = 8, friction = 12 },
		Wrist = { cone = 20, lower = -15, upper = 15, friction = 8 },
		Hip = { cone = 45, lower = -25, upper = 25, friction = 35 },
		Knee = { cone = 50, lower = -6, upper = 6, friction = 18 },
		Ankle = { cone = 18, lower = -12, upper = 12, friction = 10 },
	} :: { [string]: Joint },
}
return table.freeze(Config)
