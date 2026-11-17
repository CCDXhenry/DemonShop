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
export type Request = { action: string, target: string?, version: number?, session: string?, samples: { Sample }?, yaw: number?, pitch: number?, sequence: number?, segments: { VisualSegment }?, started: number?, bodyPose: BodyPose? }
export type Item = {
	id: string,
	kind: string,
	stage: string,
	location: string,
	version: number,
	model: Model,
	holder: Player?,
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
	hitDirection: Vector3?,
	hitVelocity: LinearVelocity?,
	hitJoints: { { joint: Motor6D, base: CFrame } }?,
	carryResources: Folder?,
	carryTarget: Attachment?,
	carryErrorSince: number?,
	carryBaseOffset: CFrame?,
	carryVelocity: Vector3?,
	carryUpdated: number?,
	carrySway: Vector2?,
	releaseUntil: number?,
	releaseCharacter: Model?,
}
export type ItemView =
	{ id: string, kind: string, stage: string, location: string, version: number, model: Model, hits: number, progress: number, holder: number?, visualCount: number? }
export type Snapshot = {
	bodyPose: BodyPose?,
	revision: number,
	poseYaw: number?,
	posePitch: number?,
	stationVersions: { [string]: number },
	items: { ItemView },
	pool: number,
	shelf: number,
	tableId: string?,
	altarId: string?,
	altarEnds: number,
	painter: number?,
	session: string?,
}
export type Notice = { kind: string, removed: { string }?, actor: number?, started: number?, text: string?, textId: GameTexts.TextId?, textArgs: {string}?, snapshot: Snapshot?, id: string?, cells: { string }?, session: string?, yaw: number?, pitch: number?, progress: number?, sequence: number?, stroke: Stroke?, strokes: { Stroke }?, segments: { VisualSegment }?, visualRevision: number?, bodyPose: BodyPose? }
return {}
