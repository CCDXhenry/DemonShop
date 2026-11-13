# DemonShop 开发入口

处理代码、配置、Studio 或资源前读取 [.agents/skills/demonshop-project/SKILL.md](.agents/skills/demonshop-project/SKILL.md)。

- 通用 Roblox/Luau：`.agents/skills/roblox-game-dev/SKILL.md`（SVN External，只读）。
- 工程、配置、网络、模型、配表：`.agents/skills/roblox-project-conventions/SKILL.md`。
- UI 设计、模板、文本拟合与适配：`.agents/skills/roblox-ui-system/SKILL.md`。
- 明确要求优质模型、UI、VFX：`.agents/skills/quality-instance-workflow/SKILL.md`。
- 音频：`.agents/skills/roblox-audio-workflow/SKILL.md`。
- MCP 之外的截图录像：`.agents/skills/roblox-obs-capture/SKILL.md`。

脚本只编辑本地文件，经现有 Script Sync 同步，不通过 MCP 覆写源码，不引入 Rojo。持久实例只在 Edit 模式修改。未明确要求不启动 Play。
UI 专项以 roblox-ui-system 为准：固定 1920×1080 Center 画布、模板唯一来源、屏幕单行文本二分拟合、描边 ScaledSize；这些覆盖 SVN UI reference 中对应旧规则。
