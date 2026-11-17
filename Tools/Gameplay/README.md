# 布娃娃加工工具与验收

运行代码位于 `Scripts/`，通过现有 Script Sync 同步，禁止用 MCP 覆写脚本源码。集中数值位于 `Shared/GameConfig.luau`，独立布娃娃模块为 `ServerStorage/Scripts/Ragdoll.luau`。

## 基础框架恢复（2026-11-17）

- 以提交 `7933d7c` 的通用能力为依据恢复基础管理器、消息、设置、商城、统计和 UI 窗口，剥离旧农场依赖。`ServerGameManager` 统一维护玩家加入、退出、自动保存与关闭；`ProcessingManager` 只维护本局加工状态。`ClientGameManager` 完成资料握手后幂等启动 `ClientProcessingManager`，补发资料仅刷新缓存和设置。
- `ServerGameInfo` 是存档唯一所有者。版本 1 的 `{version, coins}` 迁移为版本 2，金币保持不变；新增默认设置、首次进入信息、UTC 登录天数、累计在线时长和通行证列表。未知、损坏或旧农场结构拒绝加载，不默认覆盖。四个历史租约键保持原始持久化字符串。
- `FoundationNet` 提供资料握手、设置和通行证通知。设置经服务端校验及限频；现有加工协议独立保留。商品目录默认为空，未配置商品不确认收据；外部统计、BGM、清档传送均默认关闭或未配置，不使用旧项目 ID。
- `UIManager` 恢复窗口注册、单例、模态层级、按钮交互、文本拟合和销毁接口。`WindowCanvas` 固定 1920×1080，与现有 HUD 分别负责各自画布缩放；`ModalButton` 覆盖实际视口。窗口缩放动画只使用模板中预置的 `AnimationScale`。没有注册旧农场窗口。
- 恢复实例时，在目标 Place Edit 执行 `build-foundation-assets.luau`，补齐基础 RemoteEvent、BindableEvent、窗口画布、模态遮罩及音量分组，并将模型中的音效接到 SoundEffects 分组。该安装器不创建或覆写脚本，不替换现有 HUD。然后按既有方式恢复模型和 UI 导出；模型位于 `ReplicatedStorage.Models`，若恢复模型后丢失外部分组引用，可再次执行此幂等安装器。
- 本轮离线结果：原有 506 条回归、50 条基础框架断言、13 条 UI 框架断言，共 569 条通过；业务 strict 为 0 Error，全量检查仅保留共享 Core/TeleportTool 的两条既有诊断。Studio 保持 Edit，未启动 Play。
- `python Tools/Gameplay/test_rules.py` 覆盖正式资料规则、版本迁移、设置/商城及双端装配、异步保存、UI 单例与模态栈；引擎服务与 GUI/Tween 使用离线边界。仍需按授权另做实机验收，离线通过不代表 Play、云端统计或商城交易验证。

## 参考框架契约重构（2026-11-17）

- 只读参考改为实际场景 `17432470623`，基线清单 `foundation-reference.json`；`check_foundation_contracts.py` 检查参考模块、公开方法参数数量、公开类型、事件及业务边界，并接入统一回归。它是结构门禁，参数类型由 strict 和正式网络行为测试补充验证。
- `NetMsg` 恢复参考具名事件，加工实现迁入 `ProcessingNet`，原通用方法兼容转发。`FoundationNet` 是单传输路径适配器，组合连接通过 `Disconnect()` 完整释放；`FoundationRequest` 仅握手，`FoundationNotify` 不再使用。
- `ServerGameInfo` 的参考字段是版本 2 权威资料的兼容视图；运行期持有地区、配置、通行证映射及修订号，保存快照只取持久化字段。GameConfig 已恢复参考框架的分段定义、原生 `PlayerSaveInfo.dataVersion` 与默认工厂（默认登录 1 天、UTC 当日零点）；`SaveRules.FromPlayerSaveInfo / ToPlayerSaveInfo` 显式转换基础结构与实际 version=2 存档，GameConfig 不再维护元表别名或持久化替身类型。客户端收到允许展示的本地资料与其他玩家公开资料，不接收服务端完整存档。迁移入口 `PlayerSaveInfoVersionUpdateTool.Update` 成功时兼容原地更新，失败保留输入，统一规则仍在 SaveRules。
- UIManager 创建和销毁唯一 `GameScreenGui`，基础总控先初始化 UI，再将引用交给加工客户端。HUD 通过正式 GameFrameWrapper 管理缩放与清理；摄像机替换重新绑定，嵌套画布不重复缩放。StarterGui 不再保留第二份主界面模板。
- Edit 安装器增量恢复基础事件、遮罩与音量组，重复执行不替换 HUD；删除退役的 FoundationNotify 和重复的 StarterGui.GameScreenGui。恢复导出映射见 `Assets/Foundation/README.md`。先恢复资源、再执行安装器，以重新连接跨导出文件的 SoundGroup 引用；脚本始终通过 Script Sync 同步。
- 同步核验必须分别报告本地、GetEditorSource 编辑草稿与 Instance.Source。未提交草稿不等同于丢失源码；禁止通过 MCP 覆写或在 Studio 提交脚本草稿来消除差异。

## 曲面白膜（2026-11-17）

- `WhiteR15` 已替换为 15 个独立曲面 MeshPart、15 个标准 R15 Motor6D，共 14,400 三角面；身体部件和模板带 `SurfaceVersion=1`。云端模型 `84781021841961` 属于体验群组 `33977495`，上传审核 Approved。正式恢复源为 `Assets/Models/GameModels.rbxm`，旧块状身体单独保存在 `Assets/Models/WhiteBody/WhiteR15Legacy.rbxm`。
- Blender 源文件、FBX、四视角图、Studio Play 截图和验证结果位于 `Assets/Models/WhiteBody`。生成命令：`& 'D:/blender-5.4.0/blender-5.4.0/blender.exe' --background --python Tools/Gameplay/build_white_body.py`；渲染使用同目录 `render_white_body.py`。生成数据 `BodySurfaceData.luau` 经 Script Sync 同步。更改几何或 UV 必须递增表面版本，并一起更新客户端、服务端、模板及云端资产。
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
- `test_curved_raster.luau` 直接执行正式曲面渲染器，图像 API、纹理绑定和时钟使用离线边界；以修复前完整扫描算法逐像素比对短线、长线、跨面、真实 UV 接缝、重复覆盖及两档分辨率，检查预算恢复、脏区域提交、缓存和任务释放。`test_paint_client_lifecycle.luau` 执行正式客户端方法，检查退出端点、输入冻结、采样顺序与清理。均接入 `python Tools/Gameplay/test_rules.py`。未启动 Play，离线工作量比较不代表 Studio 帧率或实机拖画观感。

## Edit 资源

`build-game-assets.luau` 是初始原型构建器，会重建业务模板。已有二次重构样板时不要重新执行它，以免覆盖模板细节。`build-quality-samples.luau` 在目标 Place1 的 Edit 模式增量维护白膜、笔尖、命中标牌、HUD 和药水样板；两者均不创建或覆写运行脚本。运行时不依赖这些工具文件。

恢复导出：`Assets/Models/GameModels.rbxm` 对应 `ReplicatedStorage.Models`；`Assets/UI/ProjectTemplates.rbxm` 包含业务 UI 模板；`Assets/UI/CommonTemplates.rbxm` 包含静态布局参考；`Assets/Models/SceneAnchors.rbxm` 包含 `Workspace.NeonContractDistrict.SummoningSubmitAnchor` 与 `StreetSpawn`。导入时避免保留同名旧实例。

武器使用 Roblox 官方 [Sword（47433）](https://create.roblox.com/store/asset/47433)，独立恢复文件为 `Assets/Models/ClassicSword.rbxm`，导入到 `ReplicatedStorage.Models` 并替换旧 `Club`；完整 `GameModels.rbxm` 也已包含同一模板。内部名仍为 `Club`，保留官方网格与握持参数，只保留 SwordSlash 音效，不携带脚本或缩略图相机。初始构建器要求先导入此模板，不再生成方棍。动画 `522635514` 与音效 `12222216` 集中在 `GameConfig`；本地 Animator 播放标准 R15 挥剑，服务端接受攻击后播放一次音效，原版伤害与突刺不启用。

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
