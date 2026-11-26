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
GameConfig.GameId = 10776291771 -- 本项目正式体验 ID，已从目标 Studio 核对
if game.GameId == GameConfig.GameId then
	--游戏场景
	GameConfig.GamePlaceId = 110812537538556
	--清除玩家数据场景
	GameConfig.ClearDataStorePlaceId = 0 -- 未配置本项目清档场景时禁用
else
	--游戏场景
	GameConfig.GamePlaceId = 110812537538556
	--清除玩家数据场景
	GameConfig.ClearDataStorePlaceId = 0 -- 未配置本项目清档场景时禁用
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
GameConfig.BGMTemplate = "" -- 空名称不播放 BGM；配置后读取 Sounds 中的模板
GameConfig.GameAnalyticsEnabled = false -- 独立 GA 开关；需服务端配置本项目密钥
GameConfig.AnalyticsEnabled = false -- 外部统计默认关闭，需本项目有效配置
GameConfig.AnalyticsEndpoint = "" -- 未配置不发送 HTTP 请求
GameConfig.AnalyticsProjectId = "" -- 外部统计项目标识，不使用旧项目值
GameConfig.MaximumBodies = 32 -- 同服身体总量保护，避免反复丢弃后无限堆积
GameConfig.StreetPopulation = 6 -- 街道闲逛或晕倒的目标总数，具
GameConfig.SpawnInterval = 5 -- 捕获后补充间隔，秒
GameConfig.WeaponSourceAsset = 47433 -- Roblox 官方经典剑；Edit 模板保留内部名 Club
GameConfig.WeaponSlashAnimation = "rbxassetid://522635514" -- Roblox 标准 R15 toolslash
GameConfig.WeaponSlashSound = "rbxassetid://12222216" -- 官方经典剑 SwordSlash
GameConfig.WeaponAnimationFade = 0.05
GameConfig.AttackRange = 7 -- 近战命中距离，studs
GameConfig.AttackCooldown = 0.6 -- 两次有效挥击的最小间隔，秒
GameConfig.AttackWindup = 0.16 -- 前摇后进行一次服务端空间命中校验
GameConfig.AttackComboSeconds = 1.4 -- 连续挥击保持有效范围内的同一目标
GameConfig.WalkPauseChance = 0.35 -- 闲逛选择下一步时短暂停顿的概率
GameConfig.IdleAnimation = "rbxassetid://507766666"
GameConfig.WalkEnterSpeed = 0.65
GameConfig.WalkExitSpeed = 0.25
GameConfig.MotionFadeSeconds = 0.16
GameConfig.HitImpulseSpeed = 4
GameConfig.HitLeanRadians = 0.28
GameConfig.HitPushSeconds = 0.2
GameConfig.HitLeanRiseSeconds = 0.22
GameConfig.PaintActiveTextureSize = 1024
GameConfig.PaintObserverTextureSize = 512
GameConfig.PaintTextureResidentLimit = 8
GameConfig.PaintTextureViewDistance = 80
GameConfig.PaintRasterBudgetSeconds = 0.004
GameConfig.HitStaggerSeconds = 0.75 -- 命中后短暂停步，让连续三击可读且可追击
GameConfig.StunImpulseSpeed = 3 -- 最后一击的受控水平倒地冲量，studs/s
GameConfig.StunHits = 3 -- 累计命中次数，无自动苏醒
GameConfig.InteractionRange = 8 -- 工位与物品交互距离，studs
GameConfig.PoolCapacity = 8 -- 共享池容量，具
GameConfig.ShelfCapacity = 8 -- 药水架容量，瓶
GameConfig.ConversionSeconds = 10 -- 单具身体转化时间，秒
GameConfig.PotionReward = 100 -- 每瓶提交奖励，金币
GameConfig.PaintTarget = 0.6 -- 可涂表面面积的目标比例
GameConfig.PaintGrid = 8 -- 每个外露面划分为 8×8 个覆盖单元
GameConfig.BrushRadius = 0.32 -- 笔迹物理半径，studs
GameConfig.PaintBatchInterval = 0.08 -- 客户端笔迹上报间隔，秒
GameConfig.PaintStrokePointBudget = 2048 -- 单身体连续笔划点预算，覆盖数据独立保留
GameConfig.PaintPreviewPoolBudget = 256
GameConfig.PaintLocalSegmentBudget = 8192 -- 单身体本地连续笔迹预算，直线合并后计数
GameConfig.PaintVisualBatchSize = 64
GameConfig.PaintVisualPacketsPerTick = 4
GameConfig.PaintVisualPacketsPerSecond = 80
GameConfig.PaintVisualRetrySeconds = 1
GameConfig.PaintVisualSamplePixels = 3 -- 每帧屏幕路径补采样，不跟随网络频率
GameConfig.PaintVisualSamplesPerFrame = 256
GameConfig.PaintVisualWidth = 0.16 -- 连续线条宽度与覆盖半径独立，保留白底
GameConfig.PaintSurfacePixels = 128 -- 每 stud 的表面画布像素
GameConfig.PaintDeadzonePixels = 1.5 -- 过滤指针微抖
GameConfig.PaintAngularSpeed = 10 -- 本地展示最大角速度，服务端不以回包节奏限制旋转
GameConfig.PaintRotationResponse = 30 -- 更快趋近输入角速度；松手直接清零
GameConfig.PaintSensitivity = 0.018 -- 客户端拖画转角；按再次偏慢反馈提高约 2.57 倍
GameConfig.PaintPitchLimit = 1.2
GameConfig.PaintCameraSeconds = 0.22
GameConfig.SaveInterval = 30 -- 保存及续租间隔，秒
GameConfig.LeaseSeconds = 120 -- 存档会话有效期，秒
GameConfig.MaximumCoins = 9007199254740000 -- 保持整数精确的金币上限
GameConfig.WalkAnimation = "rbxassetid://507777826" -- Roblox 标准 R15 行走动画

return GameConfig
