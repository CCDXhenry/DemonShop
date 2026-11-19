# DemonShop UI 全量审计 · Phase 0

审计日期为 2026-11-18，目标为「开发者_恶魔商店」PlaceId `110812537538556`。现状以该场景的 Edit 实例、直接启动的 Studio 客户端和本地源码为依据。后续视觉方向由设计评审决定。

**旧资产构建器会把整棵 HUD 和笔迹模板替换掉。** 手机竖屏下常驻信息、主提示和工具栏过小，而独立触控按钮保持原尺寸。HUD、工具栏和原生世界提示依赖现有节点名及交互生命周期，迁移结构前应锁定契约。

## 审计范围

| 范围 | 核实结果 |
|---|---|
| `ReplicatedStorage.UI` | 6 个一级模板、123 个后代，含设计参考、主界面、平面笔迹表面、笔迹段、目标 Billboard、世界 Prompt。主界面本身及其后代共 105 个节点 |
| 项目持久场景 UI | `Workspace.NeonContractDistrict` 内 12 个 SurfaceGui 和各自的文字节点。四个工位牌与八个门店牌均在场景中直接挂载。扫描未发现其他业务 ScreenGui、BillboardGui、SurfaceGui 或持久 Prompt |
| 运行客户端 | `PlayerGui.GameScreenGui`、`TargetGui`、桌面／触屏变化、克隆的工具槽和预览、世界交互 Prompt。Studio 注入 Freecam，触端另有引擎 TouchGui。曲面笔迹走 EditableImage，平面笔迹由模板路径和源码补充 |
| 业务与框架源码 | 从 ClientRoot 到 ClientGameManager、UIManager、ClientProcessingManager、ClientToolbar、画符、世界交互、本地化、数据与服务端边界。将 70 个本地脚本与目标 Edit 缓冲区作归一化字节长度和 Adler-32 指纹比对，全部一致 |
| 基础功能与平台 UI | WindowBase、GuiWrapperBase、模态遮罩、ClientMsg、设置及商城后端纳入依赖审计。当前无生产窗口注册与设置/商城窗体。CoreGui 作为外围覆盖区。Studio 编辑器插件界面排除 |

逐节点属性、资源地址、运行引用、快照及工具归属见 [UI_Inventory.json](UI_Inventory.json)。该清单覆盖 148 条 Edit 记录，含模板目录、模板后代和场景牌两层节点。具体路径依赖和生命周期见 [UI_Node_Contracts.md](UI_Node_Contracts.md)。

## 模板现状

| 一级模板 | 核实的基线 |
|---|---|
| `ScreenLayoutGuideFrame` | 固定 1920×1080、7 个禁放矩形，属性声明原始 14 个模拟样本、24 px 间距。现有样本来自参考项目 |
| `GameScreenGui` | DisplayOrder 10、Global ZIndex、ResetOnSpawn=false。CenterFrame 和 WindowCanvas 各自 1920×1080、居中、配 UIScale。ScreenInsets 实际为 DeviceSafeInsets，ClipToDeviceSafeArea 为 true。主树包含右上状态卡、提示、通知、画符条、屏幕光标、桌面操作、工具栏、3 个触控变体、窗口画布及模态遮罩 |
| `PaintFaceGui` | SurfaceGui，FixedSize 256×256、Brightness 1.2、LightInfluence 0。运行时按部件表面尺寸和 128 px/stud 设置 CanvasSize |
| `PaintCellFrame` | 居中锚定 Frame，圆角端帽、紫色填充，运行时作为 StrokeSegment 设置位置、宽高、旋转与版本 |
| `TargetGui` | BillboardGui 170×44，MaxDistance 45、AlwaysOnTop=true、LightInfluence=0，子 Frame 贴底。CountText 实际自左留出 32 px |
| `WorldInteractionPrompt` | 原生 Default 样式，E／手柄 X、长按 0.5 秒，RequiresLineOfSight=true，模板初始禁用 |

主屏幕 23 个 TextLabel 均配置 DesignTextSize、TextScaled=false 和 TextWrapped=false。UI 模板树所读 27 个 UIStroke 均为 ScaledSize。可见贴图集中在工具槽的底图、装备描边和品质图（`18300392432`、`18300392104`、`100338692242374`）。工具预览直接展示实际 Tool 网格和外观。工位 SurfaceGui 使用固定 800×100、Back 面，门店牌使用固定 700×140、Front 面。

## 职责与迁移边界

| 层 | 现有实现 | 迁移影响 |
|---|---|---|
| 视觉表现 | Studio 模板、GameScreenGuiManager、TargetGuiManager、PaintPointer、PaintView/CurvedPaintView、HitPresentation、BodyPresentation、场景牌 | 处理布局、字体、状态、色彩、反馈、世界依附。绘制区域与命中采样相互影响 |
| 交互控制 | ClientProcessingManager、WorldInteractionManager、ClientToolbar、PaintCamera、输入绑定与客户端状态切换 | 保持鼠标、触控、键盘、手柄动作语义，防止模态、画符、原生长按和工具选择抢焦点 |
| 数据绑定 | ClientGameInfo、ProcessingNet、GameTypes、玩家属性、Hints、WorldInteractionRules、GameTexts、ProcessingTextTool、TranslationTool | 保持 Snapshot/Notice、状态优先级、翻译参数与版本。UI 处理数据展示，金币与覆盖率仍由服务端计算 |
| 底层框架 | ClientRoot、ClientGameManager、UIManager、GameFrameWrapper、WindowBase、GuiWrapperBase、UIActions、TextFitting、ClientMsg、LifecycleTool、共享 UIAdapter | 保留根所有权、一次装配、单处视口缩放、窗口栈、消息、事件和清理入口。共享 UIAdapter 的其他模式视为通用能力 |

## 现状问题与证据

| 维度 | 观察 | 证据 |
|---|---|---|
| 视觉层级 | HUD 同时展示品牌、金币、携带、容量，行动提示和状态通知缺少稳定的视觉容器。初始 Club 的名称与实物为剑形，装备提示用高亮黄色轮廓，在紫色操作按钮旁形成强对比 | 桌面出生、工具栏和攻击截图 |
| 空态反馈 | Hands Empty 时仍显示 Drop。非画符时 Attack 可常驻，是否具备武器、目标和权限由业务入口判断。手机端用 HIT、桌面用 ATTACK，手机工具槽仍展示数字按键 | 桌面/横/竖空手截图及 `GameScreenGuiManager.Refresh` |
| 画符任务 | 桌面和手机横屏的两个工具槽与 Exit／Reset 按钮矩形相交。手机竖屏中进度卡横过身体上半部，主提示和工具槽覆盖中心作画区。输入拦截范围还需专门验证 | 画符截图和运行 `AbsolutePosition/AbsoluteSize` |
| 竖屏可读性 | 竖屏中状态卡和主提示大幅变小并集中在画面中段。原尺寸 Drop/HIT 相对抢眼，工具位和键帽很小。横屏同一 HUD 更易读，玩法按钮与跳跃键同处右侧 | iPhone 13 模拟横屏与竖屏，实测客户端 Camera.ViewportSize 分别为 749×389、389×762 |
| Safe Area | 当前手机默认关闭的遮罩给出的几何为横屏 749×389、竖屏 389×762，而 `GetInsetArea(None)` 分别为 843×389 和 389×843。正式窗口若启用遮罩，需核查可见区域及交互阻断。固定参考仍来自参考场景 | Studio 实例属性、运行时遮罩与 Inset，以及移动截图 |
| 场景指引 | 工位牌静态写 `SOUL ALTAR / 5s`，配置为 10 s，运行倒计时来自 Snapshot。世界交互与 HUD 按不同信息选目标，靠近、遮挡、手持改变时应一起检查 | 场景牌 TextLabel、`GameConfig.ConversionSeconds`、`ClientProcessingManager.Update` |
| 结构与回退 | resync、重生和销毁牵涉同一主实例，按名字搜索增加误绑定风险。旧生成器覆盖根资产，样例/本地化工具可再次改写已迁移属性 | [风险表](UI_Refactor_Risks.md) |

## 构建与恢复审计

`build-game-assets.luau` 具有最高覆盖风险。它先删除现有 GameScreenGui，然后重建旧 HUD 与 PaintFaceGui/Cell，并从不同容器清理一些基础事件和声音。 `build-quality-samples.luau` 会写笔迹、补建缺失光标和目标牌，并带一份历史本地化修改。 `update-processing-localization.luau` 会重设 Text、AutoLocalize 和 Prompt 属性并删除旧节点。 `build-foundation-assets.luau` 按需补齐画布、遮罩及基础资源，其清理步骤涉及旧 StarterGui 和 FoundationNotify。 `BuildScreenLayoutGuide.luau` 只替换设计参考。白体构建器的网格和 UV 改动影响曲面笔迹。CommonTemplates 和 ProjectTemplates 的 9 与 114 个节点分别与主场景对应模板按路径及类匹配。此项仅验证导出结构。构建器通过阅读本地源码审计。

## 主场景实测

- 直接在 `110812537538556` 启动零客户端本地测试服务器。确认玩家数为零后，将测试服务器 VM 的 `DataStoreTool.SafeUpdate` 临时接入进程内表，再加入负 ID 模拟玩家。正常资料握手及原有客户端入口创建 HUD。测试中的金币从 0 到 100，来自生产奖励逻辑与内存表。结束会话后该表及临时状态随 VM 清除。
- 桌面验证出生／空手、命中、击晕后原生长按拾取、搬运与池容量、画符入场、实落笔、工位完成态、祭坛倒计时、药水架、装备药水、提交反馈和目标标牌。测试用定位和服务端管理器调用推进部分步骤。一次虚拟鼠标笔划从 0 写到约 3.35% 并在服务端计到 23 段。后段用完成态夹具触发转化流程。完整手绘达到权威阈值、双客户端观察、实体手机及本地化视觉遍历留待后续验收。
- 手机以 iPhone 13 Studio 预设核查横屏、竖屏、各自空手与画符视图。横屏实测主根 UIScale 约 0.360，竖屏约 0.203。132px 设计工具槽在竖屏实测约 26.7px，触屏动作按钮仍是 140×50。抓图文件像素尺寸由 Studio 导出，几何分析采用当时客户端的 Camera.ViewportSize 及 GUI 实测。
- 先从桌面进入画符再开启触屏模拟，后创建的 `TouchGui` 会保持 Enabled，观察到左侧摇杆。两种方向在触屏预设就绪后进入画符，均读得 TouchGui.Enabled=false。
- 已核对 19 张 Studio MCP 抓图。原生 Prompt 的证据包括 Action/Object/Enabled 读数和一次真实长按拾取，目标标牌读数确认了 Enabled、Adornee 与命中标签。系统顶栏、引擎 Prompt 和目标标牌的完整画面仍待补证。OBS WebSocket 可连接，现有视口守卫拒绝独立客户端的文档标签，OBS 采集未通过。

详细矩阵和截图见 [UI 审计资源目录索引](UI_Audit_Resources/README.md)。基础契约离线校验 245 项通过，安全区投影测试 4 项通过，OBS 离线守卫 12 项通过，OBS 实机回归跳过。

移植任务、依赖、复杂度、推荐模型、推理等级和验收标准见 [UI_Refactor_Task_Breakdown.md](UI_Refactor_Task_Breakdown.md)。
