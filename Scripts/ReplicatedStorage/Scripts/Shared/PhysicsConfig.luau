-- 布娃娃物理样板参数：关节范围、阻尼、速度保护与可缩放肩部锚点
--!strict
export type Joint = { cone: number, lower: number, upper: number, friction: number }
local Presentation = table.freeze({
	-- 角度以度配置，弹簧内部使用弧度。进入/退出余量以 stud 表示。
	Contact = table.freeze({WaistDegrees=13, StrongDegrees=23, FrequencyHz=5.2, DampingRatio=0.88, DelaySeconds=0.028, EnterPad=0.32, ExitPad=0.52}),
	-- 频率 Hz，阻尼为临界阻尼比，传播延时单位为秒。
	Hit = table.freeze({FrequencyHz=3.5, DampingRatio=0.82, FirstDegrees=22, SecondDegrees=36, DelaySeconds=0.045}),
	Fall = table.freeze({PhysicsSeconds=0.65, TipSeconds=0.49, HoldSeconds=0.16, NearStuds=24, DesktopBodies=2, MobileBodies=1, JointLimit=6}),
	Carry = table.freeze({LiftSeconds = 0.28}),
	LOD = table.freeze({NearStuds = 40, FarStuds = 100}),
	-- 合成层角速度上限（rad/s）。长帧的线性权重不超过一次受控过渡。
	Limits = table.freeze({MaxStepSeconds = 1/30, AngularSpeed = 22}),
})
export type Presentation = typeof(Presentation)
local Config = {
	Presentation = Presentation,
	BodyGroup = "RagdollBodies",
	GroundRootEnabled = true,
	GroundTravel = 1.35,
	FallGroup = "LocalFallLimbs",
	SceneryGroup = "FallStaticScenery",
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
