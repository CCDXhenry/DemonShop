---
name: demonshop-project
description: DemonShop 项目身份、源码入口、Studio、工具及版本管理差异；处理本仓库开发工作时读取。
---
# DemonShop 项目

- 根目录以当前仓库为准，业务玩法尚未定义，不沿用参考项目业务。
- Studio：Place1，PlaceId `110812537538556`。每次 MCP 明确传 instance_id；不修改参考项目。
- 服务端入口 `Scripts/ServerScriptService/ServerRoot.legacy.luau`；客户端入口 `Scripts/StarterPlayer/StarterPlayerScripts/ClientRoot.local.luau`。
- 业务模块位于 `Scripts/ServerStorage/Scripts`、`Scripts/ReplicatedStorage/Scripts/Client` 与 `Shared`；Core 和 GameAnalytics 为共享/第三方依赖，本次迁移不修改。
- 通用规则读取相邻 roblox-project-conventions 和 roblox-game-dev；UI 专项读取 roblox-ui-system，优先于 SVN UI 旧规则。
- 本地文件为源码入口，经 Script Sync 同步。MCP 只读核对源码，Edit 模式修改 UI/模型，不启动未经请求的 Play。
- UI 唯一模板位于 `ReplicatedStorage.UI`。`GameScreenGui.ModalButton` 是模态遮罩，`GameFrame` 保留项目内容并使用固定 Center 画布；`ScreenLayoutGuideFrame` 仅作设计参考。可恢复导出在 `Assets/UI`，通过 MCP 导入，不作为运行时文件依赖。
- strict：`pwsh -File Tools/check-strict.ps1 <文件>`、`-Staged`、`-All`。sourcemap 为生成缓存，不提交。现有共享库诊断与本次改动诊断分别报告。
- OBS 默认场景 `DemonShop_Studio_Viewport`、来源 `DemonShop_Studio_Window`，Studio 标题默认匹配 `Place1`；可用 `ROBLOX_OBS_SCENE` / `ROBLOX_OBS_SOURCE` / `ROBLOX_OBS_PROJECT` 覆盖；工具位于 `Tools/Studio`，依赖 `requirements-obs.txt`。校准、录制与 live tests 按实际任务授权执行。
- 音频工具位于 `Tools/Audio`；上传显式提供 names、sounds-dir、manifest、creator-type、creator-id、prefix。凭证由 ROBLOX_API_KEY 环境变量提供。部署工具只生成 Luau，检查目标后经 MCP 执行；没有预置业务素材或归属 ID。
- 上传调用：`python Tools/Audio/upload_roblox_audio.py --names Click --sounds-dir Assets/Sounds --manifest Assets/Sounds/audio_manifest.json --creator-type group --creator-id <实际归属ID> --prefix DemonShop_`。部署前使用相同 names、sounds-dir、manifest、creator-type、creator-id 调用 `setup_sounds_in_studio.py --emit-code`，再经目标 MCP 执行。依赖声明在 `Tools/Audio/requirements.txt`。
- UI 离线工具：`python Tools/UI/build_screen_layout_guide.py <实测samples.json> --output-dir .cache/layout`；采样器和 Edit 构建器复用 roblox-ui-system/assets，不额外复制实现。当前禁放参考继承来源项目的 14 份样本，未在本项目重新做设备验证；系统区变化时补采样。
- SVN 文件及 External 不纳入 Git；保留所有 .svn。不发布 Package。提交、推送与资产发布分别按实际授权执行。
- 新增/维护业务脚本首行中文作用注释，第二行 --!strict。用户要求保存的设计文档放根目录 功能文档。
