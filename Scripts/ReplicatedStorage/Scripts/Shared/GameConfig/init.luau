-- 游戏基础配置：保留参考框架结构，末尾扩展恶魔商店参数
--!strict
local GameConfig = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local DateTimeExtension = require(coreSharedScripts:FindFirstChild("DateTimeExtension"))

--游戏版本
GameConfig.GameVersion = "1.0.0"
--本次AB测试版本
GameConfig.ABTestVersion = "1.0.0"
--玩家存档数据版本
GameConfig.PlayerSaveInfoDataVersion = 0 -- 首次上线，沿用基础框架初始版本，不启用历史迁移
--正式版游戏id
GameConfig.GameId = 0000 -- 本项目正式体验 ID
if game.GameId == GameConfig.GameId then
	--游戏场景
	GameConfig.GamePlaceId = 0
	--清除玩家数据场景
	GameConfig.ClearDataStorePlaceId = 0
else
	--游戏场景
	GameConfig.GamePlaceId = 110812537538556
	--清除玩家数据场景
	GameConfig.ClearDataStorePlaceId = 0
end

--通行证id
GameConfig.GamePassId = {} :: { [string]: number }

--通行证价格
GameConfig.GamePassPrice = {} :: { [number]: number }

--玩家设置信息
export type SettingInfo = {
	--背景音乐音量
	bgmVolume: number,
	--音效音量
	soundEffectVolume: number,
	--是否开启振动
	vibrationOn: boolean,
}
export type DateTimeTable = DateTimeExtension.DateTimeTable

--玩家配置信息
export type PlayerConfigInfo = { [string]: string | number | boolean }
export type PlayerSaveInfo = {
	coins: number, -- 本项目金币扩展
	--数据版本
	dataVersion: number,
	--首次进入游戏的时间
	firstEnterTime: number,
	--首次进入游戏的版本
	firstEnterVersion: string,
	--玩家累计游戏时间
	gameTime: number,
	--玩家累计登录天数
	loginDays: number,
	--玩家最后在线日期时间戳
	lastOnlineDateUTC: number,
	--设置信息
	settingInfo: SettingInfo,
	--已拥有的通行证列表
	ownedGamePassList: { number },
}
export type PlayerInfo = PlayerSaveInfo & {
	--玩家信息是否发生变化
	playerInfoChanged: boolean,
	--本次上线时间
	timeOfThisLogin: number,
	--玩家的国家/地区
	countryRegion: string,
	--玩家最后在线日期
	lastOnlineDate: DateTimeExtension.DateTimeTable,
	--已拥有的通行证映射
	ownedGamePassMap: { [number]: boolean },
	--玩家配置信息
	playerConfigInfo: PlayerConfigInfo,
}

--内购订单信息
export type ReceiptInfo = {
	PurchaseId: string,
	PlayerId: number,
	ProductId: number,
	PlaceIdWherePurchased: number,
	CurrencySpent: number,
	CurrencyType: Enum.CurrencyType,
}

--默认玩家存档
function GameConfig.CreateDefaultPlayerSaveInfo(now: number?): PlayerSaveInfo
	local timestamp = math.floor(now or os.time())
	local nowDate: DateTimeExtension.DateTimeTable = DateTimeExtension.GetDate(DateTime.fromUnixTimestamp(timestamp))
	return {
		dataVersion = GameConfig.PlayerSaveInfoDataVersion,
		coins = 0, -- 新玩家默认金币，非负整数
		firstEnterTime = timestamp,
		firstEnterVersion = GameConfig.GameVersion,
		gameTime = 0,
		loginDays = 1,
		lastOnlineDateUTC = DateTime.fromUniversalTime(nowDate.Year, nowDate.Month, nowDate.Day).UnixTimestamp,
		settingInfo = {
			bgmVolume = 1,
			soundEffectVolume = 1,
			vibrationOn = true,
		},
		ownedGamePassList = {},
	}
end

--客户端自己的玩家信息
export type ClientLocalPlayerSaveInfo = {
	coins: number, -- 本地金币展示扩展
	--设置信息
	settingInfo: SettingInfo,
	--已拥有的通行证列表
	ownedGamePassList: { number },
}
export type ClientLocalPlayerInfo = ClientLocalPlayerSaveInfo & {
	--已拥有的通行证映射
	ownedGamePassMap: { [number]: boolean },
	--玩家配置信息
	playerConfigInfo: PlayerConfigInfo,
}

--客户端其他玩家信息
export type ClientOtherPlayerSaveInfo = {}
export type ClientOtherPlayerSyncInfo = ClientOtherPlayerSaveInfo & {}
export type ClientOtherPlayerInfo = ClientOtherPlayerSyncInfo & {}

GameConfig.AnalyticsFlushInterval = 8 -- 自定义统计批量发送及失败重试间隔，秒
GameConfig.FoundationShutdownSeconds = 25 -- 基础存档和统计共用的关服预算，秒

-- 本项目扩展参数：保持基础定义及类型顺序，业务参数在此追加。
GameConfig.RemoteConfigEnabled = false -- 默认不调用 ConfigService
GameConfig.DefaultPlayerConfig = {} :: PlayerConfigInfo -- 未启用或获取配置失败时使用
GameConfig.SettingRequestInterval = 0.12 -- 每玩家设置/资料请求最小间隔，秒
GameConfig.BGMTemplate = "BGM" -- 启用背景音乐，读取 Sounds 中的模板
GameConfig.GameAnalyticsEnabled = false -- 独立 GA 开关；需服务端配置本项目密钥
GameConfig.AnalyticsEnabled = false -- 外部统计默认关闭，需本项目有效配置
GameConfig.AnalyticsEndpoint = "" -- 未配置不发送 HTTP 请求
GameConfig.AnalyticsProjectId = "" -- 外部统计项目标识，不使用旧项目值
GameConfig.MaximumBodies = 60 -- 同服身体总量保护，避免反复丢弃后无限堆积
GameConfig.StreetPopulation = 18 -- 街道闲逛或晕倒的目标总数，具
GameConfig.SpawnInterval = 2 -- 捕获后补充间隔，秒
GameConfig.WeaponSourceAsset = 47433 -- 历史经典剑参考资产（Assets/Models/ClassicSword.rbxm）
GameConfig.WeaponSlashAnimation = "rbxassetid://18297503195" -- 武器 Tool 未挂 Slash 时的回退挥击，自动化店员共用
GameConfig.WeaponSlashSound = "rbxassetid://12222216" -- 武器 Tool 未挂 SlashSound 时的回退挥击音效
GameConfig.WeaponAnimationFade = 0.05
GameConfig.BodyCarryAnimation = "rbxassetid://99312106507906" -- 玩家肩扛身体动画资产
GameConfig.CarryAnimationFade = 0.15 -- 拾取肩扛动作淡入淡出时间，秒
GameConfig.AttackRange = 7 -- 近战命中距离，studs
GameConfig.AttackServerRange = 14 -- 服务端攻击校验的宽松距离上限，覆盖移动与网络延迟差，studs
GameConfig.AttackServerRangeBuffer = 12 -- 服务端宽松距离兜底缓冲（在武器 range 基础上叠加，仅防全图秒杀），studs
GameConfig.DebugAttackLog = false -- 攻击链路双端诊断 print 开关，排查完毕后可设为 false
GameConfig.AttackCooldown = 0.6 -- 单武器配置以武器表为准，此处仅作空值回退默认值
GameConfig.AttackCooldownTolerance = 0.06 -- 服务端冷却的网络抖动宽限，秒
GameConfig.AttackWindup = 0.16 -- 前摇后进行一次服务端空间命中校验
GameConfig.AttackComboSeconds = 1.4 -- 连续挥击保持有效范围内的同一目标
GameConfig.NpcStrollSpeed = 4.5
GameConfig.NpcFleeSpeed = 15.5
GameConfig.NpcFleeDuration = 4.5
GameConfig.NpcFleeReplanSeconds = 0.3
GameConfig.NpcLookAroundChance = 0.45
GameConfig.NpcLookAroundDurationMin = 1.5
GameConfig.NpcLookAroundDurationMax = 3.0
GameConfig.IdleAnimation = "rbxassetid://507766666"
GameConfig.WalkEnterSpeed = 0.65
GameConfig.WalkExitSpeed = 0.25
GameConfig.MotionFadeSeconds = 0.16
GameConfig.HitPosePeakSeconds = 0.05
GameConfig.HitPoseSeconds = 0.35
GameConfig.HitSecondPoseSeconds = 0.45
GameConfig.HitHealthSeconds = 1.5 -- 受击白膜头顶血条显示时长，秒
GameConfig.HitPoseAngle = math.rad(24)
GameConfig.HitSecondPoseAngle = math.rad(32)
GameConfig.HitTwistAngle = math.rad(12)
GameConfig.HitHeadScale = 0.65
GameConfig.HitArmScale = 1.2
GameConfig.HitLimbDelay = 0.025
GameConfig.HitEffectSeconds = 0.18
GameConfig.HitFinalEffectSeconds = 0.28
GameConfig.HitEffectPoolSize = 12
GameConfig.HitEffectDistance = 80
GameConfig.HitEffectRayCount = 8
GameConfig.HitEffectRingSegments = 16
GameConfig.HitEffectRadius = 1.25
GameConfig.HitFinalEffectScale = 1.45
GameConfig.HitEffectThickness = 0.065
GameConfig.HitRayLengthScale = 0.65
GameConfig.HitRayStartRadius = 0.3
GameConfig.HitRingStartRadius = 0.25
GameConfig.HitCameraVerticalScale = 0.5
GameConfig.HitCameraRollScale = 0.5
GameConfig.HitFlashColor = Color3.fromRGB(255, 249, 224)
GameConfig.HitRayColor = Color3.fromRGB(255, 194, 66)
GameConfig.HitStopSeconds = 0.045
GameConfig.HitFinalStopSeconds = 0.07
GameConfig.HitFeedbackWindow = 0.5
GameConfig.HitPredictionLifetime = 2
GameConfig.HitCameraSeconds = 0.12
GameConfig.HitFinalCameraSeconds = 0.18
GameConfig.HitCameraAngle = math.rad(0.6)
GameConfig.HitFinalCameraAngle = math.rad(1)
GameConfig.HitCameraOffset = 0.06
GameConfig.HitFinalCameraOffset = 0.10
GameConfig.HitCameraFrequency = 32
GameConfig.HitPushDistance = 1.03 -- 普通击退的最大水平路程（stud），沿用开放街道实测中值。
GameConfig.PaintActiveTextureSize = 1024
GameConfig.PaintObserverTextureSize = 512
GameConfig.PaintTextureResidentLimit = 8
GameConfig.PaintTextureViewDistance = 80
GameConfig.PaintRasterBudgetSeconds = 0.004
GameConfig.PaintActiveRasterBudgetSeconds = 0.010 -- 活跃操作者画布优先帧预算，秒
GameConfig.NpcHitStaggerSeconds = 0.12 -- 击退在短暂停步内完成，随后开始逃跑
GameConfig.StunImpulseSpeed = 3 -- 最后一击的受控水平倒地冲量，studs/s
GameConfig.StreetNpcMaxHp = 30
GameConfig.BruteDamage = 10
GameConfig.StunHits = 3 -- 累计命中次数，无自动苏醒
GameConfig.InteractionRange = 8 -- 工位与物品交互距离，studs
GameConfig.PickupServerRangeBuffer = 3 -- 服务端物品拾取距离同步容差（叠加在 InteractionRange 上，覆盖移动与布娃娃同步延迟），studs
GameConfig.PoolCapacity = 8 -- 兼容旧字段：渲染上限以 PoolVisibleLimit 为准，逻辑容量无限
GameConfig.ShelfCapacity = 6 -- 兼容旧字段：渲染上限以 ShelfVisibleLimit 为准，逻辑容量无限
GameConfig.DefaultPotionQuality = 1 -- 当前唯一品质；点位序号与品质相同，第 1 档用排序后的第一个点
GameConfig.PotionIcon = "rbxassetid://123588533133210" -- 工具栏药水槽图标
GameConfig.ToolbarSlotLimit = 9 -- 底部工具栏可见槽位数
GameConfig.ConversionSeconds = 10 -- 单具身体转化时间，秒
GameConfig.AltarClimaxSeconds = 1.5 -- 炉口聚能收束时长，秒
GameConfig.AltarStrokeHighlight = Color3.fromRGB(255, 28, 198) -- 已画笔迹在完成闪烁及献祭中加亮到的高饱和霓虹品红
GameConfig.PotionReward = 100 -- 每瓶售出时，当前服务器每位资料已就绪的玩家各得的金币
GameConfig.PaintTarget = 0.4 -- 可涂表面面积的目标比例
GameConfig.PaintFlatTarget = 0.6 -- 非旋转躺平模式的覆盖目标比例
GameConfig.RuneGlyphCount = 3 -- AI 符文字形数量
GameConfig.RuneStampSpacing = 0.27 -- 连续拖动时的表面落印间距，studs
GameConfig.RuneStampSize = 0.38 -- 单枚符文标准落印宽度，studs
GameConfig.RuneMinScale = 0.38 -- 边缘处允许等比缩小的最小比例
GameConfig.RuneBaseColor = Color3.fromRGB(148, 36, 245) -- 符文普通状态浓郁魔力紫
GameConfig.RuneAppearHighlightColor = Color3.fromRGB(255, 28, 198) -- 新符文落印瞬间的高饱和霓虹品红高亮色
GameConfig.RuneAppearSeconds = 0.28 -- 新符文高亮渐隐至常规紫的时长，秒
GameConfig.RuneCompleteFlashSeconds = 0.32 -- 达成 100% 时全身体符文高亮闪烁时长，秒
GameConfig.PaintGrid = 8 -- 每个外露面划分为 8×8 个覆盖单元
GameConfig.BrushRadius = 0.18 -- 笔迹物理半径，studs
GameConfig.PaintSliceHemisphereMinDot = -0.45 -- 旋转横截面采样允许落墨的镜头侧半球下限，双端共用
GameConfig.PaintBatchInterval = 0.08 -- 客户端笔迹上报间隔，秒
GameConfig.PaintStrokePointBudget = 2048 -- 单身体连续笔划点预算，覆盖数据独立保留
GameConfig.PaintPreviewPoolBudget = 256
GameConfig.PaintLocalSegmentBudget = 8192 -- 单身体本地连续笔迹预算，直线合并后计数
GameConfig.PaintVisualBatchSize = 64
GameConfig.PaintVisualPacketsPerTick = 4
GameConfig.PaintVisualPacketsPerSecond = 80
GameConfig.PaintVisualRetrySeconds = 1
GameConfig.PaintCoverageRetrySeconds = 0.25 -- 覆盖进度包未确认时的快速重发间隔，秒
GameConfig.PaintVisualSamplePixels = 3 -- 每帧屏幕路径补采样，不跟随网络频率
GameConfig.PaintVisualSamplesPerFrame = 256
GameConfig.PaintVisualWidth = GameConfig.BrushRadius * 2 -- 显示与覆盖共用笔刷直径
GameConfig.PaintCoverageBatchSize = 128
GameConfig.PaintEllipsoidScale = 0.96 -- 旋转绘画 3D 椭圆体限制区域相对白膜半尺寸的缩放比例
GameConfig.PaintSurfacePixels = 128 -- 每 stud 的表面画布像素
GameConfig.PaintDeadzonePixels = 1.5 -- 1080 像素短边下，相对本次按下点的死区
GameConfig.PaintAngularSpeed = 10 -- 本地展示最大角速度，服务端不以回包节奏限制旋转
GameConfig.PaintRotationResponse = 30 -- 更快趋近输入角速度；松手直接清零
GameConfig.PaintCameraSeconds = 0.22
GameConfig.SaveInterval = 30 -- 保存及续租间隔，秒
GameConfig.LeaseSeconds = 120 -- 存档会话有效期，秒
GameConfig.MaximumCoins = 9007199254740000 -- 保持整数精确的金币上限
GameConfig.NpcRunAnimation = "rbxassetid://507767714" -- 标准 R15 跑步动画
GameConfig.WalkAnimation = "rbxassetid://507777826" -- Roblox 标准 R15 行走动画
GameConfig.PaintLiePitch = math.pi / 2 -- 仰卧绕 X 轴的转角，面朝上、头朝世界 +Z
GameConfig.PaintCameraHeight = 10.5 -- 绘制镜头到台面锚点的距离，studs
GameConfig.PaintMediumBatchCameraHeight = 13.5
GameConfig.PaintLargeBatchCameraHeight = 15.5
GameConfig.PaintCameraTilt = math.rad(35) -- 相对正上方朝牌子一侧（世界 -Z）低下的角度
GameConfig.PaintCameraOffset = Vector3.new(0, math.cos(GameConfig.PaintCameraTilt), -math.sin(GameConfig.PaintCameraTilt)) -- 相对台面锚点的单位偏移，再乘对应距离
GameConfig.PaintCameraRight = Vector3.new(-1, 0, 0) -- 画面右侧的世界朝向（脚在右、头在左）
GameConfig.PaintCameraUp = Vector3.new(0, math.sin(GameConfig.PaintCameraTilt), math.cos(GameConfig.PaintCameraTilt)) -- 画面上方的世界朝向（台子远处、牌子在画面下方）
GameConfig.PaintFlySeconds = 1.2 -- 画完后飞向祭坛的时长，秒
GameConfig.PaintFlyHeight = 6 -- 飞向祭坛的弧线抬升，studs
GameConfig.PaintRotationEnabled = false -- 绘画台白膜旋转开关；关闭时保持仰卧躺平朝向不旋转
GameConfig.PaintPhysicsEnabled = false -- 绘画台白膜物理开关；关闭时全身锚定固定身躯与四肢
GameConfig.PaintAutoFlipProgress = 0.5 -- 躺平绘制模式触发自动翻面的总进度阈值
GameConfig.PaintFlipSeconds = 0.55 -- 自动翻面动画时长，秒
GameConfig.PaintFlipLiftHeight = 0.85 -- 自动翻面过程中的垂直抬升峰值，studs
GameConfig.PaintFlipFlashSeconds = 0.24 -- 自动翻面时已画符文轻度高亮闪烁时长，秒
GameConfig.PaintFlipFlashBrightness = 0.65 -- 自动翻面闪烁峰值亮度（0~1）
GameConfig.SessionOnlyEconomy = true -- 本局化经济：进服金币归零，写库时金币固定归零
GameConfig.PoolVisibleLimit = 8 -- 兼容旧字段：SoulHoldingPool 实体白膜现已取消渲染上限
GameConfig.ShelfVisibleLimit = 6 -- 手动药水架每档瓶身实体渲染上限，逻辑容量无限
GameConfig.AutoRuneSeconds = 2.0 -- A03 自动符文台单具画符节拍，秒
GameConfig.AutoChuteSettleSpeed = 3.0 -- 落料池判定落稳的速度上限，studs/s
GameConfig.AutoChuteDwellSeconds = 0.65 -- 落稳后在落料池停留展示的最短时长，秒
GameConfig.AutoChuteMaxSettleWaitSeconds = 2.0 -- 落料池防堆叠卡死的兜底等待上限，秒
GameConfig.AutoRuneIntakeSeconds = 0.50 -- 落料池滑入绘画床的牵引过渡时长（包含在 2.0s 周期前段），秒
GameConfig.AutoRampToOutputSeconds = 0.85 -- 绘画床沿斜坡爬升至摆放平台的过渡时长，秒
GameConfig.AutoOutputShiftSeconds = 0.30 -- 摆放平台排队前移补位的滑移时长，秒
GameConfig.AutoTransferToPassSeconds = 1.0 -- 画符台到通过装置
GameConfig.AutoTransferAlignSeconds = 0.3 -- 通过装置上的排队白膜就地对齐入炉方向
GameConfig.AutoTransferLightSeconds = 0.35 -- 通过装置亮灯时间
GameConfig.AutoTransferLightBrightness = 1.6 -- 柔化后的检测灯亮度
GameConfig.AutoTransferLightRange = 9.0 -- 柔化后的检测灯照射半径，studs
GameConfig.AutoTransferLightColor = Color3.fromRGB(165, 110, 255) -- 柔化后的检测灯霓虹紫色调
GameConfig.AutoTransferToFurnaceSeconds = 0.9 -- 通过装置到炉内
GameConfig.AutoSmelterSeconds = 2.5 -- A04 自动炼化台单具炼化节拍，秒
GameConfig.AutoSoundMaxDistance = 48 -- 自动化空间音效触发距离上限，studs
GameConfig.AutoQueueVisibleLimit = 6 -- 自动线符文出料垫/自动药水架场景实体渲染上限（FastChuteLanding 已取消渲染上限）
GameConfig.UnlockPadTriggerRadius = 2.4 -- 踩踏解锁底盘水平判定半径，studs
GameConfig.UnlockPadHeightTolerance = 5.5 -- 踩踏解锁底盘垂直高度容差，studs
GameConfig.AutoPaintedColor = Color3.fromRGB(196, 152, 255) -- 保留的自动符文色值；白膜本身不再整身染色，符文由落印笔段显示
GameConfig.BruteWalkSpeed = 8 -- A01/A02 地狱打手巡逻与搬运移动速度（studs/s）
GameConfig.BruteHitInterval = 0.65 -- A01/A02 地狱打手近战击打节拍，秒
GameConfig.BruteHitRange = 6.5 -- A01/A02 地狱打手近战攻击距离，studs
GameConfig.BrutePickupRange = 3.2 -- A01/A02 地狱打手靠近至可伸手拾取白膜的距离，studs
GameConfig.BruteLiftDuration = 0.62 -- A01/A02 地狱打手俯身提起白膜并落肩的过渡时长，秒
GameConfig.BruteDropDuration = 0.3 -- A01/A02 地狱打手向快速通道井口投料时长，秒
GameConfig.AutoClerkWalkSpeed = 8 -- A05 自动售货员搬运移动速度（studs/s）
GameConfig.AutoClerkPickupRange = 4.0 -- A05 自动售货员在自动药水架取货距离，studs
GameConfig.AutoClerkSubmitRange = 5.0 -- A05 自动售货员在召唤法阵提交距离，studs
GameConfig.AgentRootHeight = 3.01 -- R15 AI 代理根节点相对地面的标准站立高度，studs

GameConfig.CarryVisibleLimit = 8
GameConfig.ExpandedStreet = { population = 18, spawnInterval = 2, maximumBodies = 60, citizenHP = 30 }
GameConfig.Sprint = {
	stamina = 100,
	drainPerSecond = 25,
	recoverPerSecond = 20,
	recoverDelay = 0.6,
	restartStamina = 20,
	replicationInterval = 0.1,
	speedCheckInterval = 0.2,
	speedTolerance = 3,
	distanceTolerance = 7,
}

GameConfig.NpcRvoRadius = 1.8
GameConfig.NpcRvoTimeHorizon = 1.6
GameConfig.NpcRvoMaxNeighbours = 10
GameConfig.NpcRvoSymmetryBias = 0.15
GameConfig.NpcDynamicObstacleRadius = 2.0
GameConfig.NpcDownedBodyRadius = 2.2
GameConfig.NpcTargetMinSpacing = 7.0
GameConfig.NpcTargetCandidateCount = 10
GameConfig.NpcStrollMinDistance = 12.0
GameConfig.NpcPoiChance = 0.30
GameConfig.NpcPoiDurationMin = 2.5
GameConfig.NpcPoiDurationMax = 4.5
GameConfig.NpcPoiCooldownSeconds = 10.0
GameConfig.NpcPanicRadius = 16.0
GameConfig.NpcPanicSpeed = 11.0
GameConfig.NpcPanicDurationMin = 2.2
GameConfig.NpcPanicDurationMax = 3.0
GameConfig.NpcStuckSeconds = 1.2
GameConfig.NpcCrowdStepInterval = 0.05

GameConfig.NpcFaceHitSeconds = 0.6 -- 白膜 NPC 受击瞬间痛苦表情持续时长，秒
GameConfig.NpcFaceTextures = {
	Normal = "rbxassetid://78350979935544",
	Panic = "rbxassetid://139784704663645",
	Hit = "rbxassetid://109580485818132",
	Stunned = "rbxassetid://77684885960227",
	Painting = "rbxassetid://131720148652101",
}

return GameConfig
