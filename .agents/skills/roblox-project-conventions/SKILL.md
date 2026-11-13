---
name: roblox-project-conventions
description: Roblox 项目的架构配置、源码同步、严格检查、模型结构、网络权威与 Excel 配表工程约定；实际路径与差异由项目 skill 提供。
---
# Roblox 公共工程约定

遵循当前项目实现；先核对调用链，不为统一风格扩大改动。业务身份与入口读取项目 skill。

- 架构、配置、存档兼容：[架构与配置](references/architecture-and-config.md)。
- 本地源码、Script Sync、strict、包及 Git：[开发交付](references/development-workflow.md)。
- 模型、锚点、约束：[模型结构](references/model-structure.md)。
- 服务端校验、碰撞、高延迟：[网络同步](references/network-sync.md)。
- Excel、JSON、转换命令：[配表维护](references/xlsx-json-maintenance.md)。
- UI 读取相邻 roblox-ui-system；模型质量、音频、OBS 分别读取对应 skill。

资源 ID 集中在正式配置中；事件连接、任务、Tween、克隆和对象池须有所有者与释放点。高频动画缓存 AnimationTrack，避免重复加载。纯数字、时间、玩家名及装饰符号关闭 AutoLocalize。
