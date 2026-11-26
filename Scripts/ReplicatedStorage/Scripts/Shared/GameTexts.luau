-- 加工多语言文案：业务分组、TextId 查询、插件扁平采集及旧通知解析
--!strict
export type TextId = "ShopTitle" | "ShopAbilities" | "ShopTools" | "ShopMove" | "ShopRunes" | "ShopSales" | "ShopSprint" | "ShopStamina" | "ShopEquipped" | "ShopMax" | "ShopPrice" | "ShopMoveCompare" | "ShopMoveUnlimitedCompare" | "ShopMoveUnlimitedValue" | "ShopRuneCompare" | "ShopRuneValue" | "ShopSellCompare" | "ShopSellValue" | "ShopCurrentWeapon" | "ShopNextWeapon" | "ShopCurrentCarry" | "ShopNextCarry" | "ShopWeaponSingle" | "ShopWeaponCone" | "ShopWeaponSpin" | "ShopWeaponLine" | "ShopWeaponSlam" | "ToolbarPotion" | "PromptPickUp" | "PromptPool" | "PromptTable" | "PromptAltar" | "PromptShelf" | "PromptSigil" | "PromptBody" | "PromptPotion" | "PromptOffer" | "PromptChute" | "PromptChuteLanding" | "PromptAutoOutput" | "PromptAutoShelf" | "DepositBodies" | "TakeChuteBody" | "TakeAutoRuneBody" | "CollectAutoPotion" | "TakePotion" | "TakeRuneBody" | "TakeBody" | "PotionReady" | "AltarWorking" | "ReturnTable" | "FetchPool" | "StunNpc" | "PoolUnfinishedOnly" | "StoreBody" | "TakeSharedBody" | "PoolEmpty" | "TableOtherPainter" | "TableOccupied" | "PlaceBody" | "TableNeedsBody" | "CollectRuneBody" | "ContinuePainting" | "FetchAndPaint" | "TableEmpty" | "ShelfFull" | "AltarBusy" | "InsertRuneBody" | "AltarNeedsRuneBody" | "HandsFullHint" | "CollectPotion" | "NoPotion" | "OfferPotion" | "EquipPotion" | "BringPotion" | "CarryBody" | "ChuteLocked" | "ChuteUnfinishedOnly" | "ChuteNeedsBody" | "ChuteEmpty" | "AutoOutputEmpty" | "NoAutoPotion" | "TableInUse" | "StoreUnfinished" | "PoolFull" | "PoolIsEmpty" | "TableIsOccupied" | "BringUnfinished" | "BringStunned" | "AltarOccupied" | "AltarNeedsCompleted" | "HandsFull" | "PotionsNotReady" | "BringPotionSigil" | "CoinLimit" | "RuneComplete" | "StationChanged" | "StationTooFar" | "ItemChanged" | "ItemUnavailable" | "PaintOutOfSequence" | "PaintRateExceeded" | "InvalidPaintPart" | "PaintVersionMismatch" | "PaintRejected" | "InvalidVisualSegment" | "DuplicateVisualSegment" | "SegmentOriginChanged" | "PaintBudgetReached" | "Coins" | "Stock" | "AltarCountdown" | "AltarShelfFull" | "CarryingPotion" | "CarryingRuneBody" | "CarryingBody" | "CarryingBodies" | "HandsEmpty" | "Painting" | "PaintingFlat" | "PaintFlipped" | "TakeTableBody" | "ThrowAim" | "TargetStunned" | "HitCount" | "StunnedCarry" | "CoinsAwarded" | "FacilityUnlocked" | "PaintSyncFailed" | "PaintSurfaceUnavailable" | "PaintSegmentLimit" | "UnknownNotice" | "PadPrereqNone" | "PadPrereqUnlocked" | "PadPrereqRequires" | "PadPrice"
export type Description = { textId: TextId, args: {string}?, argTextIds: {[number]: TextId}?, argSources: {[number]: string}? }
export type Entry = { source: string, key: string }

-- UI 路径以 ReplicatedStorage.UI 唯一模板为准；屏幕界面和目标标牌运行时克隆至本地 PlayerGui。
-- WorldInteractionPrompt 为 ProximityPrompt 模板，运行时克隆到工位锚点或物品模型，使用 Roblox 原生提示界面。
local GameTexts = {
	Prompts = {
		PromptPickUp = { source = "PICK UP", key = "" }, -- 用途：拾取地面物品或已击晕布娃娃的动作；UI：ReplicatedStorage.UI.WorldInteractionPrompt.ActionText
		PromptPool = { source = "HOLDING POOL", key = "" }, -- 用途：存放池的交互对象名称；UI：ReplicatedStorage.UI.WorldInteractionPrompt.ObjectText
		PromptTable = { source = "RUNE TABLE", key = "" }, -- 用途：画符工作台的交互对象名称；UI：ReplicatedStorage.UI.WorldInteractionPrompt.ObjectText
		PromptAltar = { source = "CONVERSION ALTAR", key = "" }, -- 用途：转化祭坛的交互对象名称；UI：ReplicatedStorage.UI.WorldInteractionPrompt.ObjectText
		PromptShelf = { source = "POTION SHELF", key = "" }, -- 用途：药水架的交互对象名称；UI：ReplicatedStorage.UI.WorldInteractionPrompt.ObjectText
		PromptSigil = { source = "SUMMONING SIGIL", key = "" }, -- 用途：召唤法阵的交互对象名称；UI：ReplicatedStorage.UI.WorldInteractionPrompt.ObjectText
		PromptBody = { source = "BODY", key = "" }, -- 用途：可搬运布娃娃的对象名称；UI：ReplicatedStorage.UI.WorldInteractionPrompt.ObjectText
		PromptPotion = { source = "POTION", key = "" }, -- 用途：可拾取药水的对象名称；UI：ReplicatedStorage.UI.WorldInteractionPrompt.ObjectText
		PromptOffer = { source = "OFFER POTION", key = "" }, -- 用途：向召唤法阵提交药水的动作；UI：ReplicatedStorage.UI.WorldInteractionPrompt.ActionText
		PromptChute = { source = "FAST CHUTE", key = "" }, -- 用途：快速通道井口的对象名称；UI：ReplicatedStorage.UI.WorldInteractionPrompt.ObjectText
		PromptChuteLanding = { source = "CHUTE LANDING", key = "" }, -- 用途：地下快速通道缓冲垫的对象名称；UI：ReplicatedStorage.UI.WorldInteractionPrompt.ObjectText
		PromptAutoOutput = { source = "AUTO RUNE PAD", key = "" }, -- 用途：自动符文台出料断点垫的对象名称；UI：ReplicatedStorage.UI.WorldInteractionPrompt.ObjectText
		PromptAutoShelf = { source = "AUTO POTION RACK", key = "" }, -- 用途：自动药水暂存架的对象名称；UI：ReplicatedStorage.UI.WorldInteractionPrompt.ObjectText
		DepositBodies = { source = "DEPOSIT UNFINISHED BODIES", key = "" }, -- 用途：向快速通道井口整批倒入未画符白膜的动作；UI：ReplicatedStorage.UI.WorldInteractionPrompt.ActionText
		TakeChuteBody = { source = "TAKE CHUTE BODY", key = "" }, -- 用途：从快速通道缓冲垫取走白膜的动作；UI：ReplicatedStorage.UI.WorldInteractionPrompt.ActionText
		TakeAutoRuneBody = { source = "TAKE AUTO RUNE BODY", key = "" }, -- 用途：从自动符文台出料断点垫取走已画符白膜的动作；UI：ReplicatedStorage.UI.WorldInteractionPrompt.ActionText
		CollectAutoPotion = { source = "COLLECT AUTO POTIONS", key = "" }, -- 用途：从自动药水架领走全部自动药水的动作；UI：ReplicatedStorage.UI.WorldInteractionPrompt.ActionText
	},
	Guidance = {
		TakePotion = { source = "TAKE THE POTION TO THE SUMMONING SIGIL  (+{1} COINS)", key = "Processing.TakePotion" }, -- 用途：携带药水时引导前往召唤法阵；{1} 为提交奖励金币；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
		TakeRuneBody = { source = "TAKE THE RUNE BODY TO THE CONVERSION ALTAR", key = "" }, -- 用途：携带完成画符的布娃娃时引导前往祭坛；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
		TakeBody = { source = "TAKE THE BODY DOWNSTAIRS TO THE RUNE TABLE OR HOLDING POOL", key = "" }, -- 用途：携带未完成布娃娃时引导前往楼下工作台或存放池；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
		ThrowAim = { source = "HOLD LEFT CLICK TO AIM AND THROW", key = "" }, -- 用途：肩扛白膜时提示按住左键瞄准后松手丢出；移动端使用同位置的丢置摇杆；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
		PotionReady = { source = "A POTION IS READY - COLLECT IT FROM THE SHELF", key = "" }, -- 用途：成品架有药水时引导领取；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
		AltarWorking = { source = "THE ALTAR IS WORKING - CHECK THE COUNTDOWN", key = "" }, -- 用途：祭坛转化中引导查看倒计时；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
		ReturnTable = { source = "RETURN TO THE RUNE TABLE TO CONTINUE OR COLLECT THE BODY", key = "" }, -- 用途：工作台有布娃娃时引导返回继续绘制或取走；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
		FetchPool = { source = "THE RUNE TABLE CAN FETCH A BODY FROM THE SHARED POOL", key = "" }, -- 用途：共享池有库存时提示通过工作台取出布娃娃；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
		StunNpc = { source = "STUN A WHITE NPC", key = "" }, -- 引导玩家用当前武器击晕白色 NPC
	},
	Interactions = {
		PoolUnfinishedOnly = { source = "POOL ACCEPTS UNFINISHED BODIES ONLY", key = "" }, -- 用途：解释存放池仅接收未完成布娃娃；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
		StoreBody = { source = "STORE UNFINISHED BODY", key = "" }, -- 用途：提示将未完成布娃娃存入共享池；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText、ReplicatedStorage.UI.WorldInteractionPrompt.ActionText
		TakeSharedBody = { source = "TAKE FIRST SHARED BODY", key = "" }, -- 用途：提示取出共享池中的首个布娃娃；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText、ReplicatedStorage.UI.WorldInteractionPrompt.ActionText
		PoolEmpty = { source = "POOL EMPTY - BRING A BODY", key = "" }, -- 用途：共享池为空时引导先带来布娃娃；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
		TableOtherPainter = { source = "TABLE IN USE - ANOTHER PLAYER IS PAINTING", key = "" }, -- 用途：其他玩家正在绘制时说明工作台被占用；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
		TableOccupied = { source = "TABLE OCCUPIED - PUT DOWN YOUR ITEM FIRST", key = "" }, -- 用途：携物靠近已占用工作台时提示先放下物品；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
		PlaceBody = { source = "PLACE BODY ON RUNE TABLE", key = "" }, -- 用途：提示将未完成布娃娃放到工作台；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText、ReplicatedStorage.UI.WorldInteractionPrompt.ActionText
		TableNeedsBody = { source = "TABLE NEEDS AN UNFINISHED BODY", key = "" }, -- 用途：说明工作台需要未完成布娃娃；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
		CollectRuneBody = { source = "COLLECT COMPLETED RUNE BODY", key = "" }, -- 用途：提示从工作台领取完成画符的布娃娃；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText、ReplicatedStorage.UI.WorldInteractionPrompt.ActionText
		ContinuePainting = { source = "CONTINUE PAINTING THE BODY", key = "" }, -- 用途：提示继续绘制工作台上的布娃娃；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText、ReplicatedStorage.UI.WorldInteractionPrompt.ActionText
		FetchAndPaint = { source = "FETCH SHARED BODY AND PAINT", key = "" }, -- 用途：工作台空闲且池有库存时提示取出并绘制；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText、ReplicatedStorage.UI.WorldInteractionPrompt.ActionText
		TableEmpty = { source = "TABLE EMPTY - BRING A BODY", key = "" }, -- 用途：工作台及共享池均无布娃娃时引导带来布娃娃；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
		ShelfFull = { source = "POTION SHELF FULL - COLLECT A POTION", key = "" }, -- 用途：祭坛占用且药水架已满时引导领取药水；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
		AltarBusy = { source = "ALTAR BUSY - WAIT FOR CONVERSION", key = "" }, -- 用途：祭坛转化中提示等待；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
		InsertRuneBody = { source = "INSERT COMPLETED RUNE BODY", key = "" }, -- 用途：提示将完成画符的布娃娃投入祭坛；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText、ReplicatedStorage.UI.WorldInteractionPrompt.ActionText
		AltarNeedsRuneBody = { source = "ALTAR NEEDS A COMPLETED RUNE BODY", key = "" }, -- 用途：解释祭坛需要完成画符的布娃娃；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
		HandsFullHint = { source = "HANDS FULL - PUT DOWN YOUR ITEM", key = "" }, -- 用途：携物靠近药水架时提示先腾出双手；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
		CollectPotion = { source = "COLLECT READY POTION", key = "" }, -- 用途：提示从药水架领取成品药水；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText、ReplicatedStorage.UI.WorldInteractionPrompt.ActionText
		NoPotion = { source = "NO POTION READY - USE THE ALTAR FIRST", key = "" }, -- 用途：药水架为空时引导先使用祭坛；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
		OfferPotion = { source = "OFFER POTION  (+{1} COINS)", key = "Processing.OfferPotion" }, -- 用途：提交药水的收益提示；{1} 为奖励金币；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
		EquipPotion = { source = "EQUIP A POTION TO OFFER", key = "" }, -- 用途：提交药水前提示先装备药水；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
		BringPotion = { source = "BRING A POTION TO OFFER", key = "" }, -- 用途：未携药水靠近召唤法阵时引导带来药水；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
		CarryBody = { source = "SHOULDER CARRY BODY", key = "" }, -- 用途：靠近可搬运布娃娃时显示肩扛引导；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
		ChuteLocked = { source = "UNLOCK FAST CHUTE FIRST", key = "" }, -- 用途：快速通道未解锁时的井口提示；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
		ChuteUnfinishedOnly = { source = "FAST CHUTE ACCEPTS UNFINISHED BODIES ONLY", key = "" }, -- 用途：快速通道仅接收未画符白膜时的提示；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
		ChuteNeedsBody = { source = "BRING AN UNFINISHED BODY TO THE FAST CHUTE", key = "" }, -- 用途：空手靠近快速通道井口时的引导；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
		ChuteEmpty = { source = "CHUTE LANDING EMPTY", key = "" }, -- 用途：快速通道落料垫为空时的提示；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
		AutoOutputEmpty = { source = "NO AUTO RUNE BODY READY", key = "" }, -- 用途：自动符文台出料断点垫为空时的提示；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
		NoAutoPotion = { source = "NO AUTO POTION READY", key = "" }, -- 用途：自动药水架为空时的提示；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
	},
	Hud = {
		Coins = { source = "{1}", key = "Processing.Coins" }, -- 金币胶囊只显示余额数字。
		Stock = { source = "POOL {1}  |  POTIONS {2}", key = "Processing.Stock" }, -- 用途：状态栏显示共享库存；{1} 为池内数量，{2} 为药水数量；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.StatusFrame.StockText
		AltarCountdown = { source = "ALTAR {1}s  |  POTIONS {2}", key = "Processing.AltarCountdown" }, -- 用途：显示转化进度；{1} 为剩余秒数，{2} 为药水数量；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.StatusFrame.StockText
		AltarShelfFull = { source = "ALTAR READY - SHELF FULL", key = "" }, -- 用途：转化结束但药水架已满时显示阻塞状态；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.StatusFrame.StockText
		CarryingPotion = { source = "CARRYING POTION", key = "" }, -- 用途：状态栏显示正在携带药水；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.StatusFrame.CarryText
		CarryingRuneBody = { source = "CARRYING RUNE BODY", key = "" }, -- 用途：状态栏显示正在携带完成画符的布娃娃；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.StatusFrame.CarryText
		CarryingBody = { source = "CARRYING BODY", key = "" }, -- 用途：状态栏显示正在携带未完成布娃娃；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.StatusFrame.CarryText
		CarryingBodies = { source = "CARRYING {1} / {2} BODIES", key = "Processing.CarryingBodies" }, -- 用途：显示携带总量和当前搬运上限；{1} 为具数，{2} 为上限；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.StatusFrame.CarryText
		HandsEmpty = { source = "HANDS EMPTY", key = "" }, -- 用途：状态栏显示双手空闲；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.StatusFrame.CarryText
		Painting = { source = "HOLD AND DRAG TO PAINT AND ROTATE", key = "" }, -- 用途：绘制模式下提示按住拖动旋转白膜并自动连续涂画；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
		PaintingFlat = { source = "HOLD AND DRAG TO PAINT RUNES", key = "" }, -- 用途：非旋转绘制模式下提示按住拖动在躯体上绘制符文；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
		TakeTableBody = { source = "TAKE TABLE BODY", key = "" }, -- 用途：空手靠近已占用工作台时按 Q 取回台上的身体；没有对应屏幕按钮
		ToolbarPotion = { source = "POTION {1}", key = "Processing.ToolbarPotion" }, -- 用途：底部工具栏显示药水名称与堆叠数；{1} 为当前堆叠数量；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.BottomButtonsFrame.ToolButton.ToolNameText
	},
	Combat = {
		TargetStunned = { source = "STUNNED", key = "" }, -- 用途：击晕状态文案；头顶标牌在击晕后直接隐藏，不再显示这段文字
		HitCount = { source = "HIT {1} / {2}", key = "Processing.HitCount" }, -- 用途：命中通知显示击打进度；{1} 为已命中次数，{2} 为击晕所需次数；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		StunnedCarry = { source = "STUNNED - CARRY THE BODY", key = "" }, -- 用途：击晕成功后通知玩家搬运布娃娃，同时兼容旧通知文本；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
	},
	Notices = {
		TableInUse = { source = "The table is in use.", key = "" }, -- 用途：操作失败通知：工作台正被使用；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		StoreUnfinished = { source = "Store unfinished bodies here.", key = "" }, -- 用途：存放失败通知：存放池仅接收未完成布娃娃；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		PoolFull = { source = "The holding pool is full.", key = "" }, -- 用途：存放失败通知及靠近满池的引导：共享池已满；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText、ReplicatedStorage.UI.GameScreenGui.CenterFrame.HintText
		PoolIsEmpty = { source = "The holding pool is empty.", key = "" }, -- 用途：取出失败通知：共享池为空；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		TableIsOccupied = { source = "The table is occupied.", key = "" }, -- 用途：放置失败通知：工作台已被占用；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		BringUnfinished = { source = "Bring an unfinished body.", key = "" }, -- 用途：放置失败通知：需要未完成布娃娃；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		BringStunned = { source = "Bring a stunned body or fill the pool.", key = "" }, -- 用途：开始绘制失败通知：需要击晕的布娃娃或共享池库存；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		AltarOccupied = { source = "The altar is occupied.", key = "" }, -- 用途：转化失败通知：祭坛已被占用；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		AltarNeedsCompleted = { source = "The altar needs a completed rune body.", key = "" }, -- 用途：转化失败通知：需要完成画符的布娃娃；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		HandsFull = { source = "Your hands are full.", key = "" }, -- 用途：拾取失败通知：双手已有携带物；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		PotionsNotReady = { source = "No potions are ready.", key = "" }, -- 用途：领取失败通知：没有成品药水；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		BringPotionSigil = { source = "Bring a potion to the summoning sigil.", key = "" }, -- 用途：提交失败通知：需要将药水带到召唤法阵；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		CoinLimit = { source = "Coin limit reached.", key = "" }, -- 用途：提交失败通知：金币已达到上限；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		RuneComplete = { source = "Rune complete. The body flies to the altar.", key = "" }, -- 用途：画符完成通知：白膜飞向祭坛；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		StationChanged = { source = "Station changed. Try interacting again.", key = "" }, -- 用途：交互失效通知：工位版本变化，需要重新操作；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		StationTooFar = { source = "Move closer with a clear path to the station.", key = "" }, -- 用途：交互距离或遮挡校验未通过：需靠近且无遮挡面对工位；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		ItemChanged = { source = "Item changed or was taken. Choose it again.", key = "" }, -- 用途：物品交互失效通知：状态变化或已被取走；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		ItemUnavailable = { source = "This item is occupied or cannot be carried yet.", key = "" }, -- 用途：拾取失败通知：物品被占用或尚不可搬运；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		PaintOutOfSequence = { source = "Paint batch out of sequence.", key = "" }, -- 用途：绘制上传失败通知：批次序号不连续；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		PaintRateExceeded = { source = "Paint upload rate exceeded.", key = "" }, -- 用途：绘制上传失败通知：上传频率超过限制；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		InvalidPaintPart = { source = "Invalid paint body part.", key = "" }, -- 用途：绘制上传失败通知：身体部位不合法；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		PaintVersionMismatch = { source = "Paint surface version mismatch.", key = "" }, -- 用途：绘制上传失败通知：绘制表面版本不一致；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		PaintRejected = { source = "Paint upload rejected.", key = "" }, -- 用途：绘制上传失败通知：服务端拒绝该批笔迹；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		InvalidVisualSegment = { source = "Invalid visual segment.", key = "" }, -- 用途：笔迹同步失败通知：可视笔段数据不合法；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		DuplicateVisualSegment = { source = "Duplicate visual segment in batch.", key = "" }, -- 用途：笔迹同步失败通知：批次包含重复笔段；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		SegmentOriginChanged = { source = "Segment origin changed.", key = "" }, -- 用途：笔迹同步失败通知：笔段起点发生变化；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		PaintBudgetReached = { source = "Paint segment budget reached.", key = "" }, -- 用途：绘制上传失败通知：服务端笔段预算耗尽；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		CoinsAwarded = { source = "+{1} COINS", key = "Processing.CoinsAwarded" }, -- 用途：提交药水成功后显示所得金币；{1} 为奖励数量；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		FacilityUnlocked = { source = "{1} UNLOCKED {2}", key = "Processing.FacilityUnlocked" }, -- 用途：全房广播玩家解锁自动化设施横幅；{1} 为玩家名，{2} 为设施名；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		PaintSyncFailed = { source = "Paint sync failed. Please reconnect.", key = "" }, -- 用途：笔迹同步失败且无具体原因时提示重新连接；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		PaintSurfaceUnavailable = { source = "PAINT SURFACE UNAVAILABLE. PLEASE TRY AGAIN.", key = "" }, -- 用途：进入绘制失败时提示绘制表面不可用；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		PaintSegmentLimit = { source = "PAINT SEGMENT LIMIT REACHED", key = "" }, -- 用途：本地笔迹数量达到上限时提示停止追加；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		PaintFlipped = { source = "50% - FLIPPING BODY TO PAINT THE BACK", key = "" }, -- 用途：进度达到 50% 自动翻面白膜时的提示文案；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
		UnknownNotice = { source = "Unable to complete this action. Please try again.", key = "" }, -- 用途：未知通知或未知文案 ID 的统一失败回退提示；UI：ReplicatedStorage.UI.GameScreenGui.CenterFrame.NoticeText
	},
	Automation = {
		PadPrereqNone = { source = "PRE-REQ: NONE", key = "" }, -- 用途：无前置条件解锁底盘的前置状态标签；UI：Workspace.NeonContractDistrict.AutomationLine.UnlockPads.<Pad>.GuiAnchor.PadGui.CardFrame.PrereqText
		PadPrereqUnlocked = { source = "PRE-REQ: UNLOCKED", key = "" }, -- 用途：前置设施已解锁时显示的前置状态标签；UI：Workspace.NeonContractDistrict.AutomationLine.UnlockPads.<Pad>.GuiAnchor.PadGui.CardFrame.PrereqText
		PadPrereqRequires = { source = "REQUIRES: {1}", key = "Processing.PadPrereqRequires" }, -- 用途：前置未解锁时提示需先解锁的目标设施；{1} 为前置设施名称；UI：Workspace.NeonContractDistrict.AutomationLine.UnlockPads.<Pad>.GuiAnchor.PadGui.CardFrame.PrereqText
		PadPrice = { source = "{1} COINS", key = "Processing.PadPrice" }, -- 用途：解锁底盘价格胶囊文本；{1} 为格式化金币数值；UI：Workspace.NeonContractDistrict.AutomationLine.UnlockPads.<Pad>.GuiAnchor.PadGui.CardFrame.PriceFrame.PriceText
	},
	PersonalShop = {
		ShopTitle = { source = "SHOP", key = "" },
		ShopAbilities = { source = "ABILITY UPGRADES", key = "" },
		ShopTools = { source = "TOOL EVOLUTION", key = "" },
		ShopMove = { source = "MOVE SPEED", key = "" },
		ShopRunes = { source = "RUNE BATCH", key = "" },
		ShopSales = { source = "SALE BONUS", key = "" },
		ShopSprint = { source = "SPRINT", key = "" },
		ShopStamina = { source = "STAMINA", key = "" },
		ShopEquipped = { source = "EQUIPPED", key = "" },
		ShopMax = { source = "MAX", key = "" },
		ShopPrice = { source = "{1}", key = "Processing.ShopPrice" },
		ShopMoveCompare = { source = "{1} → {2}", key = "Processing.ShopMoveCompare" },
		ShopMoveUnlimitedCompare = { source = "{1} → {2} (UNLIMITED SPRINT)", key = "Processing.ShopMoveUnlimitedCompare" },
		ShopMoveUnlimitedValue = { source = "{1} (UNLIMITED SPRINT)", key = "Processing.ShopMoveUnlimitedValue" },
		ShopRuneCompare = { source = "{1} → {2} BODIES", key = "Processing.ShopRuneCompare" },
		ShopRuneValue = { source = "{1} BODIES", key = "Processing.ShopRuneValue" },
		ShopSellCompare = { source = "+{1}% → +{2}%", key = "Processing.ShopSellCompare" },
		ShopSellValue = { source = "+{1}%", key = "Processing.ShopSellValue" },
		ShopCurrentWeapon = { source = "CURRENT: {1} / {2} TARGETS / {3} DAMAGE", key = "Processing.ShopCurrentWeapon" },
		ShopNextWeapon = { source = "NEXT: {1} | {2} / {3} TARGETS / {4} DAMAGE", key = "Processing.ShopNextWeapon" },
		ShopCurrentCarry = { source = "CURRENT: HOLDS {1}", key = "Processing.ShopCurrentCarry" },
		ShopNextCarry = { source = "NEXT: {1} | HOLDS {2}", key = "Processing.ShopNextCarry" },
		ShopWeaponSingle = { source = "MELEE", key = "" },
		ShopWeaponCone = { source = "WIDE SWEEP", key = "" },
		ShopWeaponSpin = { source = "SPIN ATTACK", key = "" },
		ShopWeaponLine = { source = "PIERCING WAVE", key = "" },
		ShopWeaponSlam = { source = "SLAM AND PULL", key = "" },
	},
}

-- 分组是词条唯一来源；索引和采集顺序均由它们构建。
local entryById: {[TextId]: Entry} = {}
local orderedIds: {TextId} = {}
local legacy: {[string]: TextId} = {}
function GameTexts.GetEntry(textId: TextId): Entry?
	return entryById[textId]
end

function GameTexts.ResolveLegacy(text: string): Description?
	local textId: TextId? = legacy[text]
	if textId then return { textId = textId } end
	local coins = string.match(text, "^%+(%d+) COINS$")
	if coins then return {textId = "CoinsAwarded", args = {coins}} end
	local hits, total = string.match(text, "^HIT (%d+)/(%d+)$")
	if hits and total then return {textId = "HitCount", args = {hits, total}} end
	if text == "STUNNED - E TO CARRY" then return {textId = "StunnedCarry"} end
	return nil
end

local groups: {{[string]: Entry}} = {
	GameTexts.Prompts, GameTexts.Guidance, GameTexts.Interactions,
	GameTexts.Hud, GameTexts.Combat, GameTexts.Notices, GameTexts.Automation, GameTexts.PersonalShop,
}
for _, group in groups do
	local names: {string} = {}
	for name in group do table.insert(names, name) end
	table.sort(names)
	for _, name in names do
		local textId: TextId = name :: TextId
		local entry = group[name]
		entryById[textId] = entry
		table.insert(orderedIds, textId)
		if not string.find(entry.source, "{", 1, true) then
			legacy[entry.source] = textId
		end
	end
end

-- LocalizationExtension 直接遍历模块；每次遍历持有自己的游标。
return setmetatable(GameTexts, {
	__iter = function()
		local index = 0
		return function(): (string?, Entry?)
			index += 1
			local textId: TextId? = orderedIds[index]
			if textId then
				local entry = entryById[textId]
				return if entry.key ~= "" then entry.key else textId, entry
			end
			return nil, nil
		end
	end,
})
