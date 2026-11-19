-- 类型契约：物品、画符采样、玩家请求及共享状态快照
--!strict
local GameTexts = require(script.Parent.GameTexts)
local SaveRules = require(script.Parent.SaveRules)
export type PlayerSaveInfo = SaveRules.Profile
export type PlayerSettingInfo = SaveRules.Settings
export type ClientLocalPlayerSaveInfo = SaveRules.Profile
export type PlayerConfigInfo = { gameVersion: string }
export type BodyPose = { [string]: CFrame }
export type Sample = { part: string, face: number, u: number, v: number, breakBefore: boolean?, triangle: number?, surfaceVersion: number? }
export type Stroke = { key: string, samples: { Sample } }
export type VisualSegment = { key: string, version: number, gesture: number, part: string, face: number, u0: number, v0: number, u1: number, v1: number, triangle0: number?, triangle1: number?, surfaceVersion: number? }
export type VisualState = { segments: { [string]: VisualSegment }, count: number, revision: number }
export type Request = { action: string, attackSequence: number?, target: string?, version: number?, session: string?, samples: { Sample }?, yaw: number?, pitch: number?, sequence: number?, segments: { VisualSegment }?, started: number?, bodyPose: BodyPose? }
export type GroundFall = {target: CFrame, started: number, velocity: Vector3}
export type PoolToss = { from: CFrame, target: CFrame, started: number, owner: number, collision: boolean? }
export type AltarToss = {
	from: CFrame,
	rest: CFrame,
	started: number,
	flightStarts: number,
	released: number?,
	stableSince: number?,
	recovery: { started: number, parts: { { part: BasePart, from: CFrame, target: CFrame } } }?,
}
export type CarryTransition = { kind: "Lift" | "Restack", from: CFrame, started: number, ends: number }
export type Item = {
	fall: GroundFall?,
	id: string,
	kind: string,
	stage: string,
	location: string,
	version: number,
	model: Model,
	holder: Player?,
	owner: Player?,
	quality: number?,
	stack: number?,
	hits: number,
	covered: { [string]: boolean },
	strokes: { Stroke },
	strokePoints: number,
	visualState: VisualState?,
	area: number,
	totalArea: number,
	progress: number,
	paintSeconds: number,
	poseYaw: number?,
	posePitch: number?,
	poseBody: BodyPose?,
	streetSlot: boolean,
	nextWalk: number,
	carryWeld: Weld?,
	carryTween: Tween?,
	walkTrack: AnimationTrack?,
	idleTrack: AnimationTrack?,
	motionState: string?,
	staggerEnds: number?,
	pushConnection: RBXScriptConnection?,
	carryResources: Folder?,
	carryTarget: Attachment?,
	carryErrorSince: number?,
	carryBaseOffset: CFrame?,
	carryTransition: CarryTransition?,
	carryLayer: number?,
	carryVelocity: Vector3?,
	carryUpdated: number?,
	carrySway: Vector2?,
	carryOrder: number?,
	releaseUntil: number?,
	releaseCharacter: Model?,
	poolToss: PoolToss?,
	altarToss: AltarToss?,
	poolRecoverAt: number?,
	flyEnds: number?,
	convertEnds: number?,
	altarHeld: boolean?,
}
export type ItemView =
	{ id: string, kind: string, stage: string, location: string, version: number, model: Model, hits: number, progress: number, holder: number?, visualCount: number?, fall: GroundFall?, flyEnds: number?, convertEnds: number?, toss: PoolToss?, altarTossStarted: number? }
export type Snapshot = {
	bodyPose: BodyPose?,
	revision: number,
	poseYaw: number?,
	posePitch: number?,
	stationVersions: { [string]: number },
	items: { ItemView },
	pool: number,
	shelf: number,
	shelfItems: { [string]: CFrame },
	tableId: string?,
	altarId: string?,
	altarEnds: number,
	painter: number?,
	session: string?,
}
export type Notice = { kind: string, attackSequence: number?, hit: boolean?, version: number?, hits: number?, direction: Vector3?, position: Vector3?, removed: { string }?, actor: number?, started: number?, text: string?, textId: GameTexts.TextId?, textArgs: {string}?, snapshot: Snapshot?, id: string?, cells: { string }?, session: string?, yaw: number?, pitch: number?, progress: number?, sequence: number?, stroke: Stroke?, strokes: { Stroke }?, segments: { VisualSegment }?, visualRevision: number?, bodyPose: BodyPose? }
return {}
