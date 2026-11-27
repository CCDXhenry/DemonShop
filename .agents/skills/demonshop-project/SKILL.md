---
name: demonshop-project
description: DemonShop 项目身份、源码入口、Studio、工具及版本管理差异；处理本仓库开发工作时读取。
---
# DemonShop 项目

- 根目录以当前仓库为准，业务为共享合作布娃娃加工游戏：街道击晕、肩扛、存放池、覆盖率画符、祭坛转化、药水提交换金币。
- Studio：Place1，PlaceId `110812537538556`。每次 MCP 明确传 instance_id；不修改参考项目。
- 服务端入口 `Scripts/ServerScriptService/ServerRoot.legacy.luau`；客户端入口 `Scripts/StarterPlayer/StarterPlayerScripts/ClientRoot.local.luau`。
- 业务模块位于 `Scripts/ServerStorage/Scripts`、`Scripts/ReplicatedStorage/Scripts/Client` 与 `Shared`；Core 和 GameAnalytics 为共享/第三方依赖，本次迁移不修改。
- 通用规则读取相邻 roblox-project-conventions 和 roblox-game-dev；UI 专项读取 roblox-ui-system，优先于 SVN UI 旧规则。
- 本地文件为源码入口，经 Script Sync 同步。MCP 只读核对源码，Edit 模式修改 UI/模型，不启动未经请求的 Play。
- 静态常驻场景 `Workspace.NeonContractDistrict`（含街区、工位、锚点与已摆放自动化设施/解锁底盘）常驻 `Workspace`，不放进 `ReplicatedStorage.Models`、不在启动时克隆，以 Studio 云端 Place 为准。
- 运行中动态创建/克隆的模型与道具模板统一以 `ReplicatedStorage.Models` 为唯一来源，根目录仅放 6 个分类 `Folder`（`Characters`、`Weapons`、`CarryRigs`、`Items`、`Effects`、`Previews`），代码经 `Shared/ModelTemplates` 访问；恢复导出为 `Assets/Models/GameModels.rbxm`（仅含 `ReplicatedStorage.Models`，不含静态场景、`UnlockPad` 与已退役 `Club`）。不使用 ServerStorage 保存业务模型模板。
- 主 GUI 由 `UIManager.CreateGameScreenGui` 创建和持有；加工客户端只接收 GUI 引用。`GameFrameWrapper` 维护 HUD 根缩放，UIManager 维护窗口根缩放，嵌套包装器不重复缩放。资料补发只更新缓存和设置，不重复初始化业务。
- UI 唯一模板位于 `ReplicatedStorage.UI`。`GameScreenGui` 使用 `ScreenInsets = None`、`IgnoreGuiInset = true` 与固定 `1920×1080` `CenterFrame` 画布（所有屏幕 UI 含移动端触控操作容器 `TouchControlsFrame` 与自研固定跳跃键均固定在画布内，按 `PreferredInput == Touch` 控制显隐，不动态追踪原生 `JumpButton`）；`PaintFaceGui` / `PaintCellFrame` 用于本地身体笔迹；`ScreenLayoutGuideFrame` 仅作设计参考。可恢复导出在 `Assets/UI`，通过 MCP 导入，不作为运行时文件依赖。
- 基础总控为 `ServerGameManager` / `ClientGameManager`，只装配通用能力与业务；加工总控为 `ProcessingManager` / `ClientProcessingManager`，布娃娃模块为 `Ragdoll`。`ServerGameInfo.GetPlayerInfo` 返回无元表的原生 `GameConfig.PlayerInfo`；修订号、保存锁和关闭状态仅保存在私有 sessions，不公开 profile 包装。`ServerGameInfo` 唯一持有玩家资料，当前项目没有旧存档；`PlayerInfo` DataStore 直接保存完整原生 `PlayerSaveInfo`（金币、设置、登录/在线统计与通行证），保留基础初始 `dataVersion = 0`，不新增版本或兼容历史存档。加工模块不得另建存档或玩家全局生命周期。集中参数为 `Shared/GameConfig`，场景加工状态仅本局有效。GameConfig 保持参考框架分段赋值、原生 PlayerSaveInfo/PlayerInfo 类型和默认工厂结构，业务参数追加到末尾；SaveRules 只做当前原生结构校验与快照复制，不维护独立 version 字段或格式转换；不在 GameConfig 增加元表或持久化替身类型。
- 基础初始化顺序为 AcquirePlayerSaveInfo → 地区/最终配置解析 → InitPlayerInfo（服务端事件、本玩家及其他玩家通知）→ 加工装配/GameReady；资料补发不重新初始化。离场或关服时取消加载并释放租约。PlayerSaveInfoVersionUpdateTool 仅保留基础框架预留接口，不注册迁移步骤；参考框架的第一步示例保留但不调用，删除本项目新增的版本 2 模块。
- 客户端基础初始化禁用原生 Backpack。自定义统计按玩家缓存，8 秒批量发送，失败保留重试；离场队列与在途请求在基础总控的同一 25 秒关服预算内收尾。默认关闭时不创建发送循环或访问网络。清档传送携带 GameConfig.CreateDefaultPlayerSaveInfo 原生结构。
- 保留通用玩家、消息、设置、商城、统计、声音和 UI 窗口框架；业务迁移不得删除这些基础能力。外部统计、BGM 和清档目标默认未配置，通行证目录为空；不自动启用来源项目服务。
- 参考基础框架为 PlaceId `17432470623`，仅只读；模块、公开方法和事件基线为 `Tools/Gameplay/foundation-reference.json`，门禁 `python Tools/Gameplay/check_foundation_contracts.py`。基础契约通过适配扩展，禁止再次删除玩家资料、消息、设置、商城、统计及 UI 基类。
- 基础框架 Edit 资源安装器 `Tools/Gameplay/build-foundation-assets.luau` 只增量补齐实例，不替换现有 HUD。基础网络恢复 `NetMsg` 具名资料/设置/通行证事件；`FoundationRequest` 仅作资料握手，`FoundationNotify` 已退役。加工网络为 `ProcessingNet`，`NetMsg` 保留旧加工方法转发；`FoundationNet` 为可释放组合连接的兼容适配器。基础资源恢复导出位于 `Assets/Foundation`。
- Edit 资源构建器 `Tools/Gameplay/build-game-assets.luau`；离线规则回归 `python Tools/Gameplay/test_rules.py`。
- 存档元数据键集中于 `PlayerSaveLeaseRules.MetadataKeys`，保持持久化字符串兼容；业务代码通过常量访问，不直接改键。
- strict：`pwsh -File Tools/check-strict.ps1 <文件>`、`-Staged`、`-All`。sourcemap 为生成缓存，不提交。现有共享库诊断与本次改动诊断分别报告。
- 录屏优先 Studio MCP 的 `video_capture`（或实时 schema 含录像参数的 `screen_capture`）。MCP 录像不可用或失败后，OBS 作为后备：默认场景 `DemonShop_Studio_Viewport`、来源 `DemonShop_Studio_Window`，Studio 标题默认匹配 `Place1`；可用 `ROBLOX_OBS_SCENE` / `ROBLOX_OBS_SOURCE` / `ROBLOX_OBS_PROJECT` 覆盖；工具位于 `Tools/Studio`，依赖 `requirements-obs.txt`。校准、录制与 live tests 按实际任务授权执行。
- 音频工具位于 `Tools/Audio`；上传显式提供 names、sounds-dir、manifest、creator-type、creator-id、prefix。音频工具默认从 ROBLOX_API_KEY 读取凭据。本项目也可显式传入 `--api-key-env SIXCUBE_ROBLOX_OPENCLOUD_KEY`，复用既有 Open Cloud 凭据。部署工具只生成 Luau，检查目标后经 MCP 执行；没有预置业务素材或归属 ID。
- 上传调用：`python Tools/Audio/upload_roblox_audio.py --names Click --sounds-dir Assets/Sounds --manifest Assets/Sounds/audio_manifest.json --creator-type group --creator-id <实际归属ID> --prefix DemonShop_`。部署前使用相同 names、sounds-dir、manifest、creator-type、creator-id 调用 `setup_sounds_in_studio.py --emit-code`，再经目标 MCP 执行。依赖声明在 `Tools/Audio/requirements.txt`。
- UI 离线工具：`python Tools/UI/build_screen_layout_guide.py <实测samples.json> --output-dir .cache/layout`；采样器和 Edit 构建器复用 roblox-ui-system/assets，不额外复制实现。离线并集默认仅合并 `TopLeftCore`（仅保留原生跳跃键时按需传入 `JumpButton`）；系统区变化时补采样更新。
- SVN 文件及 External 不纳入 Git；保留所有 .svn。不发布 Package。提交、推送与资产发布分别按实际授权执行。
- 新增/维护业务脚本首行中文作用注释，第二行 --!strict。用户要求保存的设计文档放根目录 功能文档。
