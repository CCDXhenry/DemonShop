# 布娃娃加工工具与验收

运行代码位于 `Scripts/`，通过现有 Script Sync 同步，禁止用 MCP 覆写脚本源码。集中数值位于 `Shared/GameConfig.luau`，独立布娃娃模块为 `ServerStorage/Scripts/Ragdoll.luau`。

## 基础框架结构与行为修复（2026-11-17）

- 只读参考为场景 `17432470623`，清单 `foundation-reference.json`。结构门禁除模块、方法、公开类型和事件外，还约束原生资料结构、迁移边界、初始化顺序和必要的基础行为；运行语义由执行正式模块的离线测试补充。
- `ServerGameInfo.GetPlayerInfo` 返回普通 `GameConfig.PlayerInfo`，基础字段可枚举，`playerInfoChanged` 可读写。权威资料不再包装在 profile 中；租约、修订号、关闭状态和保存串行锁放在私有记录中。快照在获得保存锁后生成，成功后仅当资料内容及修订号未变化才清除脏标记。
- 初始化顺序为取得原生存档及租约、解析地区/最终配置、调用 `InitPlayerInfo`，再装配加工并设置 GameReady。`InitPlayerInfo` 自身发送服务端事件、本玩家资料和其他玩家通知；总控不重复派发。离场/关服取消尚未发布的初始化，释放加载中的租约；多个流程不并发 Release 同一租约。
- `GameConfig` 保持参考分段结构。项目没有旧存档，默认工厂从一开始就包含金币和全部基础字段，保留初始 `dataVersion = 0` 并直接持久化原生结构。SaveRules 仅校验与复制；不再有 SaveVersion、Migrate、独立 version 字段或两套结构转换。基础版本工具仅保留预留校验接口，未注册迁移；原参考第一步示例不调用，本项目新增版本 2 模块已删除。租约修订号用于并发保存，与存档结构版本分开维护。
- 基础网络保留 NetMsg 具名接口，加工协议位于 ProcessingNet。FoundationNet 是组合连接可释放的兼容适配层，FoundationRequest 只握手，FoundationNotify 已退役。设置限频、空商城目录和未配置商品不确认收据的规则保留。
- UIManager 创建唯一主 GUI，加工客户端只接收引用；HUD/窗口各自的根画布固定 1920×1080，嵌套包装器不重复缩放。客户端基础初始化禁用原生 Backpack，资料重发不重复执行。
- 自定义统计每玩家缓存并每 8 秒批量发送，失败留队重试，在途发送期间的新增事件保留到下一批。离场事件保存在独立于玩家资料的队列中，总控在同一个 25 秒期限内等待最终发送；期限到达后报告数量并释放任务。默认关闭时无发送循环或 HTTP。清档命令继续默认禁用，配置后传送原生默认存档及 GameConfig.GamePlaceId；ServerConfig 恢复分段赋值，密钥为空。
- `python Tools/Gameplay/test_rules.py`：1059 项通过，包含原玩法/保存规则 506、基础资料/装配 82、UI 21、网络/初始结构/上下文 33、参考契约 245、恢复 RBXM 144、统计队列 18、清档命令 10。HTTP、传送和引擎服务均使用离线边界，失败警告来自显式负向用例，不表示访问了真实服务。
- 业务 strict 6 个文件 0 Error；全量 82 个目标仅保留共享 Core/TeleportTool 的两条既有类型错误，不修改共享库来消除。
- 本轮仅脚本与测试/说明变化，没有重新运行 Edit 资源构建器或导出资产。资源恢复映射仍见 `Assets/Foundation/README.md`；已有项目优先增量安装，导入模型后可重跑安装器修复 SoundGroup 外部引用。
- 本轮按首次上线结构简化，最新源码同步核验见 foundation-validation.json。核验本地、`GetEditorSource` 与已提交 Instance.Source 时分别报告，遵守不在 Studio 提交草稿的规则；源码一致与离线通过不等于 Play 或云服务验证。

## 曲面白膜（2026-11-17）

- `WhiteR15` 已替换为 15 个独立曲面 MeshPart、15 个标准 R15 Motor6D，共 14,400 三角面；身体部件和模板带 `SurfaceVersion=1`。云端模型 `84781021841961` 属于体验群组 `33977495`，上传审核 Approved。正式恢复源为 `Assets/Models/GameModels.rbxm`，旧块状身体单独保存在 `Assets/Models/WhiteBody/WhiteR15Legacy.rbxm`。
- 原 `WhiteR15` 的 Blender 源文件、FBX 和验证结果位于 `Assets/Models/WhiteBody`。用同目录的工具重建原模型时，旧版曲面数据输出到 `Assets/Models/WhiteBody/BodySurfaceData-v1.luau`。
- 街头行人和工位补料使用 `WhiteR15-People`，保留原 people 的体型、Plastic 材质与颜色。模型资产为 `102576860827795`，由原贴图烘焙的底图为 `131077260089592`。模板通过 `PaintBaseTexture` 指定底图，画符在底图上混合笔迹。当前 `BodySurfaceData.luau` 来自上传后网格的回读，表面版本为 2。调整几何或 UV 时应同步更新曲面版本、模板和画符数据。
- 上云命令为 `python Tools/Gameplay/upload_white_body.py --api-key-env SIXCUBE_ROBLOX_OPENCLOUD_KEY`；只读取所选环境变量，不输出凭证。`upload.json` 记录上传操作、归属与结果，审核等待复用原操作。更新模型资产后同步更新 `build-white-assets.luau` 的模型 ID，再在目标 Place 的 Edit 执行该安装器。构建器不创建或覆写业务脚本。
- 画符采用稳定三角面索引和重心坐标，`face=1` 保留为内部兼容字段，`u/v` 在曲面上表示第二、第三顶点的权重；视觉线段携带两个端点的三角面索引。UV 接缝两侧分别栅格化到同一图集，覆盖率按三角面真实面积的四等分采样累计。旧平面路径仅用于旧资产/规则回归，曲面资产拒绝不匹配的版本。
- 图集操作者 1024、观察者 512；最近的 8 具身体驻留，每帧最多更新一个图集，CPU 栅格化时间预算 4ms。没有纹理内存或 API 权限时退出画符并提示不可用，不退回悬浮平面笔迹。服务器仍独立校验画符可见性、采样与完成度。
- 肩部位置采用快速、无反作用力支撑，目标朝向叠加最大 10° 的加速度摆动，躯干与四肢保留物理惯性。搬运状态停止 Humanoid 自动碰撞管理，所有后代部件关闭碰撞与触碰；根部件始终不参与画符射线。自然释放保留姿态和有限速度，原承载者仍重叠时延长碰撞隔离，分离后回收约束。
- `python Tools/Gameplay/test_rules.py`：现有 145 条加 261 条曲面几何/面积/协议断言，共 406 条通过。`play-white-body-checks.luau` 在授权 Play 服务端运行，隔离创建身体并在结束恢复位置、销毁资源，覆盖走停、踉跄、第三击倒地、跳跃与连续 20 次拾放。
- Play 已验证双客户端实际三击/拾取请求、双方零碰撞、13 条曲面线段广播和重新同步重建；通过自动表面采样发送正式 Paint 请求达到 100%，材料进入 Painted。该扫涂不代表人工连续拖画的完整观感验收。
- 发布环境的 Mesh / Image APIs 开关尚未核实：Studio Edit 和 Play 客户端创建/绘制/读回成功；Creator Hub 当前账号访问目标体验权限页受限。需有管理权限的账号在目标体验确认该开关。未发布体验，Script Sync 的本地源码也未通过 Studio 提交草稿。

完整实测数值及未验证项见 `Assets/Models/WhiteBody/play-validation.json`。移动端、真实公网高延迟、长时间压力和发布后的 API 可用性仍需另外验证。

### 曲面首笔退出修复

曲面 `DrawLocal` 曾误将上传线段标识拼为 `bodyId:session:gesture:serial`，而服务端要求 `session:gesture:serial`。因此真实首笔触发 VisualRejected，客户端结束绘画并移除本地预览。现已统一会话前缀，保留身体 ID 作为本地路径缓存的隔离键。`test_curved_visual_pipeline.luau` 串联正式 DrawLocal、Drain、上传队列、协议校验、服务端存储和历史重建；修复前稳定失败，修复后新增 14 条断言通过，总计 420 条。Studio 真实鼠标拖画验证无拒绝，退出重进恢复 55 条已存线段，再次拖画累计 92 条线段，覆盖进度约 4.7%；截图为 `Assets/Models/WhiteBody/paint_fix_reenter.png`。

### 绘画台悬挂动态

按确认的悬挂方案，仅固定上躯干；头部、腰部及四肢保留本地 BallSocket 物理关节。旋转时只移动躯干支点，关节产生惯性摆动；降低工作台关节摩擦并限制异常速度。观察者按服务端广播的姿态平滑展示，不各自运行一套物理。

`PaintBodyPose` 定义上躯干局部姿态，校验部件白名单、有限正交坐标、躯干固定、关节连接距离和摆动限位。绘画采样与视觉批次携带相同姿态，服务端先重建身体再校验移动部位的落笔。纯姿态更新复用现有可靠批次及限流；退出时忽略持续物理摆动，待已有笔迹确认后结束。新观察模型直接使用收到的姿态，避免依赖实体复制的到达顺序。

本次 9 个业务文件 strict 检查通过，新增 29 条姿态/队列断言，全部离线断言合计 449 条通过。Studio 真实鼠标旋转录得手部相对躯干摆动约 0.99 stud，连续 79 帧姿态校验全部通过；前臂成功上传 29 条笔迹。主动退出再进入后恢复 232 条线段、约 7.5% 覆盖进度，绘画保持开启。双客户端收到 10 个带姿态的视觉包、45 条笔迹，观察端手部相邻采样最大位移约 0.52 stud，未发生 VisualRejected。新观察模型姿态位置重建误差小于 0.000004 stud。截图：`Assets/Models/WhiteBody/table_hanging_paint.png`。这次检查未模拟公网延迟或实体手机物理性能。

### 绘画延迟与退出补画修复（离线验证）

- 帧内先更新身体姿态和采样输入，再执行一次曲面栅格化。画刷扫描限制到其 UV 影响区域，长线段按小片段检查 4ms 栅格化预算并跨帧恢复；队列通过读游标消费，纹理只提交脏矩形。
- 已驻留的 1024 图集退出后继续复用，不立即降为 512 重画历史；缓存淘汰或分辨率升级后的历史先完整重建再绑定，避免逐笔回放。退出冻结输入与画布端点，等待本地绘制和服务器上传确认后结束会话；图像 API 失败仍允许提示并退出。
- `test_curved_raster.luau` 直接执行正式曲面渲染器，图像 API、纹理绑定和时钟使用离线边界；以独立的连续笔刷完整扫描参考逐像素比对短线、长线、跨面、真实 UV 接缝、重复覆盖及两档分辨率，并检查与旧圆点算法的覆盖差异、断笔/超距跳跃、预算恢复、脏区域提交、纹理绑定及任务释放。`test_paint_client_lifecycle.luau` 执行正式客户端方法，检查退出端点、输入冻结、采样顺序与清理。均接入 `python Tools/Gameplay/test_rules.py`。未启动 Play，离线工作量比较不代表 Studio 帧率或实机拖画观感。

## Edit 资源

`build-game-assets.luau` 是初始原型构建器，会重建业务模板。已有二次重构样板时不要重新执行它，以免覆盖模板细节。`build-quality-samples.luau` 在目标 Place1 的 Edit 模式增量维护白膜、笔尖、命中标牌、HUD 和药水样板；两者均不创建或覆写运行脚本。运行时不依赖这些工具文件。

恢复导出：`Assets/Models/GameModels.rbxm` 仅对应分类后的 `ReplicatedStorage.Models`（运行时动态克隆模板）；`Assets/UI/ProjectTemplates.rbxm` 包含业务 UI 模板；`Assets/UI/CommonTemplates.rbxm` 包含静态布局参考；`Assets/UI/PersonalShopTemplates.rbxm` 包含随身商店与个人 HUD 模板。静态常驻场景 `Workspace.NeonContractDistrict`（含街道、工位、锚点与已摆放的 `AutomationLine` / `UnlockPads`）直接常驻 `Workspace`，以 Studio 云端 Place 为准，不再塞入 `GameModels.rbxm`，也不在服务端启动时克隆。

历史经典剑参考归档保留在 `Assets/Models/ClassicSword.rbxm`（原 `Club` 已退役并移出 `ReplicatedStorage.Models`）。动画 `522635514` 与音效 `12222216` 集中在 `GameConfig`；本地 Animator 播放标准 R15 挥击，服务端接受攻击后播放一次音效。

`ReplicatedStorage.Models` 根目录仅放 6 个语义分类目录，业务脚本统一经 `Shared/ModelTemplates` 访问：
- `Characters`：`WhiteR15-People`、`WhiteR15`、`HellBrute_1`、`HellBrute_2`、`AutoClerk`
- `Weapons`：`W01_RustyPan` ~ `W06_AbyssalHammer`（由 `build-weapon-assets.luau` 在 Edit 构建；发放与工具栏克隆对应 `Tool`，商店克隆其 `Visual`）
- `CarryRigs`：`CarryRig_T1` ~ `CarryRig_T4`（由 `build-carry-assets.luau` 在 Edit 增量重建，角色背饰与商店视口共用）
- `Items`：`Potion`
- `Effects`：`ThrowAim`
- `Previews`：`T0`（徒手搬运商店预览）、`ViewportWorld`（工具栏与随身商店 3D 视口空容器）

恢复时先导入 `GameModels.rbxm` 到 `ReplicatedStorage`，再导入 `ProjectTemplates.rbxm` 和 `PersonalShopTemplates.rbxm` 到 `ReplicatedStorage.UI`。静态场景直接在 Edit 模式的 `Workspace.NeonContractDistrict` 中维护。

## 回归

- `python Tools/Gameplay/test_rules.py`：需要 Lune；复制正式模块到忽略的缓存，服务与模板查找边界使用 mock。现有 38 条规则、13 条权威画符、7 条复制、9 条连续几何、12 条统一渲染、30 条视觉协议/队列、5 条满预算重建与清理断言，共 114 条；渲染器测试使用真实 Lune GUI 实例。不能替代连续游玩验收。
- 同一命令还执行 31 条官方剑资源与动作回归，合计 145 条：两份 RBXM 模板契约、动作轨道复用、观察端不重复播放、卸装/画符/死亡/重生/肩扛清理，以及动画加载失败。动画播放器与角色事件使用 mock，不能证明实机动作观感、云端动画/音效可用性或多人复制效果。
- `play-visual-finish-checks.luau`：获授权的 Play 服务端隔离检查，捕获网络边界、创建临时物品，验证 100% 收尾与最终视觉序号；不写存档，恢复玩家属性。不是正常玩家完整流程验收。
- `pwsh -File Tools/check-strict.ps1`：检查本次改动。`-All` 的共享 Core/TeleportTool 两条既有诊断应独立报告，不修改 SVN External 来消除。
- `play-server-checks.luau`：仅在双人 Play 服务端执行。创建临时状态机和资源，验证容量、FIFO、锁定、交接、无效材料、等待出货、旧工位版本与重复奖励；不写 DataStore，结束清理临时资源并恢复玩家金币属性和位置。
- `play-coverage-sweep.luau`：仅在正在画符的 Play 客户端执行，需先建立 `_G.GameplayTest.snapshot` 的 `NetMsg.ConnectNotify` 监听。通过正式请求上报可见表面采样，不直接写进度，结果写入 `paintResults`。这是规则验收辅助，不替代真实拖画手感验收。

## 初始原型的历史记录（不是二次重构验收）

- 38 条离线规则断言和 25 条隔离 Play 状态机断言通过。
- 单人启动与双人真实请求闭环通过：三击晕倒、肩扛、存放池、工作台取料、画符 100%、10 秒转化、药水交接、提交金币 0→100、重复提交保持 100；重开双人会话后 Player1 保留 100，Player2 为 0。
- 真实鼠标拖画验证笔迹和旋转；iPhone 模拟器横竖屏验证独立 50 像素操作按钮，并产生真实 Touch 输入增加身体覆盖。尚未在实体手机上验收。
- 最终运行日志没有 脚本错误；Studio 插件的资源图标错误与本业务无关。
- 地图通道和楼梯自动门沿用现有场景；长时间物理压力、实体手机性能及高延迟网络仍需后续专项实机观察。

上述历史流程含服务端定位、请求驱动和自动扫涂，只证明部分规则与状态流，不代表正常玩家全程通过。二次重构结果与未验证项以 `功能文档/布娃娃加工二次重构实施与验收记录.md` 为准。

## 连续快速绘画渲染回归

曲面笔迹按最多 256 条线段组成可恢复任务，将连续轨迹投影至三角面并按 8×8 像素分块合并扫描；同面短线使用已有重心坐标，跨面路径继续贴面投影。三角面转换与网格候选集合缓存随纹理释放，单部件候选查询缓存上限 256 个。逐帧仍使用原有 4 毫秒栅格预算及一次脏区域提交；缓存纹理不再反复赋给 MeshPart。网络协议、服务端覆盖率、线段上限和结束确认逻辑保持原有契约。

`test_curved_raster_stream.luau` 已接入 `python Tools/Gameplay/test_rules.py`：30/60 FPS × 100/300 像素每帧，按 3 像素弧长准备输入，模拟 30 秒持续拖画并插入快速反复落笔。压力测试直接输入渲染器，故意超过业务 8192 条限制；若触达业务上限就停止生成，会掩盖队列增长。四种场景使用独立 Lune 进程，避免前一场景的压力数据保留影响后续时钟测量。

2026-11-17 离线验证：四组分别处理 30,600 / 90,000 / 61,200 / 180,000 条线段，无丢失且结束时全部排空，完成延迟第 95 百分位均在当前输入帧内；最高压力场景曾出现 4 帧短暂峰值。修复前快照在相同 60 FPS / 300 像素每帧压力下，30 秒后约 179,204 条仍待处理，额外两帧未排空。该比较使用真实 CPU 时钟及模拟图像写入，不代表 Studio FPS 或真实 GPU 提交延迟。未启动 Play；实机第 95 百分位不超过两个显示帧、松手后两帧完成的目标仍需实机确认。


## 原生世界交互提示（2026-11-17）

五个工位与可拾取物使用玩家私有的原生 ProximityPrompt，模板为 `ReplicatedStorage.UI.WorldInteractionPrompt`，恢复源为 `Assets/UI/ProjectTemplates.rbxm`。E / 手柄 X / 鼠标与触屏均需长按 0.5 秒，距离沿用 InteractionRange。旧屏幕交互按钮及手写 E 输入已移除；最近目标仅用于 HUD 原因提示，Q 的工作台取回行为保留。

`WorldInteractionRules` 生成可操作条件与长按状态签名，`WorldInteractionManager` 管理本地提示、翻译、失效取消及网络请求。仍使用原服务端 Interact 校验。增量 Edit 安装使用 `update-processing-localization.luau`，两个资源构建器内嵌同一迁移，禁止重建现有 HUD 来更新提示。

`python Tools/Gameplay/test_world_interaction.py` 执行正式规则与控制器，覆盖工位/携带条件、长按取消、版本争抢、模型替换、重复触发及资源释放；已接入 `test_rules.py`。`python Tools/Gameplay/test_processing_texts.py` 核对本地化和真实 RBXM 提示属性。原生长按计时、三端输入以及提示视线表现仍须在后续获授权 Play 中验收，本次没有启动 Play。
