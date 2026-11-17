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
- 实例模型与道具模板统一放置于 `ReplicatedStorage.Models`，服务端从该目录克隆；恢复导出为 `Assets/Models/GameModels.rbxm`。不使用 ServerStorage 保存业务模型模板。
- 主 GUI 由 `UIManager.CreateGameScreenGui` 创建和持有；加工客户端只接收 GUI 引用。`GameFrameWrapper` 维护 HUD 根缩放，UIManager 维护窗口根缩放，嵌套包装器不重复缩放。资料补发只更新缓存和设置，不重复初始化业务。
- UI 唯一模板位于 `ReplicatedStorage.UI`。`GameScreenGui.CenterFrame` 使用固定 Center 画布；`PaintFaceGui` / `PaintCellFrame` 用于本地身体笔迹；`ScreenLayoutGuideFrame` 仅作设计参考。可恢复导出在 `Assets/UI`，通过 MCP 导入，不作为运行时文件依赖。
- 基础总控为 `ServerGameManager` / `ClientGameManager`，只装配通用能力与业务；加工总控为 `ProcessingManager` / `ClientProcessingManager`，布娃娃模块为 `Ragdoll`。`ServerGameInfo` 唯一持有玩家资料，`PlayerInfo` DataStore 使用版本 2（金币、设置、登录/在线统计与通行证），版本 1 金币档自动补齐基础字段。加工模块不得另建存档或玩家全局生命周期。集中参数为 `Shared/GameConfig`，场景加工状态仅本局有效。GameConfig 保持参考框架分段赋值、原生 PlayerSaveInfo/PlayerInfo 类型和默认工厂结构，业务参数追加到末尾；实际 version=2 存档形状及 dataVersion 转换只放 SaveRules，不在 GameConfig 增加元表或持久化替身类型。
- 保留通用玩家、消息、设置、商城、统计、声音和 UI 窗口框架；业务迁移不得删除这些基础能力。外部统计、BGM 和清档目标默认未配置，通行证目录为空；不自动启用来源项目服务。
- 参考基础框架为 PlaceId `17432470623`，仅只读；模块、公开方法和事件基线为 `Tools/Gameplay/foundation-reference.json`，门禁 `python Tools/Gameplay/check_foundation_contracts.py`。基础契约通过适配扩展，禁止再次删除玩家资料、消息、设置、商城、统计及 UI 基类。
- 基础框架 Edit 资源安装器 `Tools/Gameplay/build-foundation-assets.luau` 只增量补齐实例，不替换现有 HUD。基础网络恢复 `NetMsg` 具名资料/设置/通行证事件；`FoundationRequest` 仅作资料握手，`FoundationNotify` 已退役。加工网络为 `ProcessingNet`，`NetMsg` 保留旧加工方法转发；`FoundationNet` 为可释放组合连接的兼容适配器。基础资源恢复导出位于 `Assets/Foundation`。
- Edit 资源构建器 `Tools/Gameplay/build-game-assets.luau`；离线规则回归 `python Tools/Gameplay/test_rules.py`。
- 存档元数据历史键集中于 `PlayerSaveLeaseRules.MetadataKeys`，保持持久化字符串兼容；业务代码通过常量访问，不直接改键。
- strict：`pwsh -File Tools/check-strict.ps1 <文件>`、`-Staged`、`-All`。sourcemap 为生成缓存，不提交。现有共享库诊断与本次改动诊断分别报告。
- OBS 默认场景 `DemonShop_Studio_Viewport`、来源 `DemonShop_Studio_Window`，Studio 标题默认匹配 `Place1`；可用 `ROBLOX_OBS_SCENE` / `ROBLOX_OBS_SOURCE` / `ROBLOX_OBS_PROJECT` 覆盖；工具位于 `Tools/Studio`，依赖 `requirements-obs.txt`。校准、录制与 live tests 按实际任务授权执行。
- 音频工具位于 `Tools/Audio`；上传显式提供 names、sounds-dir、manifest、creator-type、creator-id、prefix。凭证由 ROBLOX_API_KEY 环境变量提供。部署工具只生成 Luau，检查目标后经 MCP 执行；没有预置业务素材或归属 ID。
- 上传调用：`python Tools/Audio/upload_roblox_audio.py --names Click --sounds-dir Assets/Sounds --manifest Assets/Sounds/audio_manifest.json --creator-type group --creator-id <实际归属ID> --prefix DemonShop_`。部署前使用相同 names、sounds-dir、manifest、creator-type、creator-id 调用 `setup_sounds_in_studio.py --emit-code`，再经目标 MCP 执行。依赖声明在 `Tools/Audio/requirements.txt`。
- UI 离线工具：`python Tools/UI/build_screen_layout_guide.py <实测samples.json> --output-dir .cache/layout`；采样器和 Edit 构建器复用 roblox-ui-system/assets，不额外复制实现。当前禁放参考继承来源项目的 14 份样本，未在本项目重新做设备验证；系统区变化时补采样。
- SVN 文件及 External 不纳入 Git；保留所有 .svn。不发布 Package。提交、推送与资产发布分别按实际授权执行。
- 新增/维护业务脚本首行中文作用注释，第二行 --!strict。用户要求保存的设计文档放根目录 功能文档。
