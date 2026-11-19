# DemonShop UI 节点契约

审计场景为 PlaceId `110812537538556`。逐节点属性见 [UI_Inventory.json](UI_Inventory.json)。下文 `UI` 指 `ReplicatedStorage.UI`，`G` 指 `UI.GameScreenGui`，`C` 指 `G.CenterFrame`。运行时主界面路径将 `UI` 替换为 `PlayerGui`。

## 启动与生命周期

| 消费者 | 输入与输出 | 迁移要保护的行为 |
|---|---|---|
| `ClientRoot → ClientGameManager` | `NetMsg.NotifyPlayerInfoInit` 更新 `ClientGameInfo` 和三项声音设置，首次调用 `UIManager.CreateGameScreenGui`，依次初始化 Toolbar、Processing | 原生 Backpack 由基础入口关闭。资料补发只刷新缓存与设置。销毁顺序为 Processing → Toolbar → UIManager → 声音与资料 |
| `UIManager` | `CreateGameScreenGui / Init / Destroy`。暴露模板管理器、`UIActions` 与文本拟合 | 持有单个根实例，拒绝外部同名副本，窗口和业务管理器共享这棵树。使用 `LifecycleTool` 清理监听、Tween 和 Camera 订阅 |
| `GameFrameWrapper` | `C.UIScale`，观察 `Workspace.CurrentCamera` 和 `ViewportSize` | HUD 根按 `min(w/1920,h/1080)` 缩放，继承父 GuiObject 的包装器跳过第二次视口缩放 |
| `UIManager / WindowBase` | `G.WindowCanvas.UIScale` 独立缩放，`G.ModalButton : ImageButton` 全屏覆盖。`RegisterWindow(id, {frameName,isModal,modalTransparency,openAnimation,newWindow})` 从 `UI.<frameName> : Frame` 克隆 | 同 ID 单例，按打开顺序设置层级，每层步长 100。多遮罩透明度相乘，点击关最顶层模态。Open/Close 发 `ClientMsg` 事件。窗口面板可用 `AnimationScale`。当前生产源码无窗口注册调用，框架归入回归范围 |
| `GuiWrapperBase / UIActions` | 常驻包装、自身和子对象释放、窗口与 CreateFrame 接口 | 保留 Destroying 及外部订阅清理，避免把 Provider 与视图的释放责任混用 |

源码 [ClientGameManager](../Scripts/ReplicatedStorage/Scripts/Client/ClientGameManager.luau)、[UIManager](../Scripts/ReplicatedStorage/Scripts/Client/UIManager/init.luau)、[WindowBase](../Scripts/ReplicatedStorage/Scripts/Client/UIManager/WindowBase.luau)、[GameFrameWrapper](../Scripts/ReplicatedStorage/Scripts/Client/UIManager/GameFrameWrapper.luau)。

## 主屏幕与操作变体

| 节点或模板 | 类与查找方式 | 状态、事件及动态写入 |
|---|---|---|
| `C`、`WindowCanvas`、`ModalButton` | 两个直接 Frame 各有 UIScale，遮罩是直接 ImageButton。克隆前断言类型 | Scale 为独立缩放所有者，遮罩 Visible、ZIndex、BackgroundTransparency 由窗口栈驱动 |
| `C.StatusFrame.{CoinsText,CarryText,StockText}` | TextLabel。主屏幕管理器按后代 **Name** 建字典 | Coins 从玩家属性读取。Carry 源于持有物 Stage。Stock 来自 Snapshot 池/架容量和祭坛结束时间 |
| `C.HintText / NoticeText` | TextLabel。同一名字缓存 | `Hints.Action/Next` 计算附近原因或下一步。通知由 `ProcessingNet` 事件／本地反馈驱动，到期清空。保留参数、错误文案和优先级 |
| `C.PaintFrame.ProgressText`、`C.PaintFrame.ProgressBarFrame.FillFrame` | TextLabel、Frame。后者通过递归 `FindFirstChild("FillFrame", true)` 取首个匹配 | 画符画面开关、百分比取整、条宽比例。进度取服务端覆盖率 |
| `C.PaintCursorFrame`（含 `TipFrame`） | Frame。`PaintPointer.Update` 以主画布根和后代参考几何计算投影 | 绘制姿态、表面命中与指针决定位置及可见性。触摸在实际绘制时才显示 |
| `C.{ExitPaintButton,ResetViewButton}` | 直接 GuiButton | 桌面画符时显示，按名绑定 `Activated`。攻击用鼠标左键，丢弃和取回用 Q，这两项没有屏幕按钮 |
| `UI.TouchAttackFrame` | 独立 Frame，运行时克隆到 `G`，不放进 `C`。子级 `AttackButton`，含 `UIScale` 和 `ActionText` | `PreferredInput == Touch`、跳跃键可见、未画符且没有打开窗口时显示。尺寸取 `max(MinimumTouchSize, 跳跃键宽度 × JumpSizeRatio)`，放在跳跃键左上并空出 `JumpGap`。按下调用攻击 |
| `G.TouchPaintFrame` | 直接 Frame，含 ExitPaintButton 和 ResetViewButton | 两方向共用，固定底部双按钮。画符过程中客户端切换原生 TouchGui 并恢复 |
| 任何使用动效的 GuiButton | `HasInteractionEffect=true` + 直接 UIScale | UIManager 观察 Workspace 和主 GUI 的 DescendantAdded。生成 hover、press Tween 及点击声音。销毁时解绑。原生 Prompt 交由引擎处理 |

`GameScreenGuiManager.Init` 扫描整棵主界面，并把 `TouchAttackFrame` 克隆到主界面下。重复的 `TitleText`、`LabelText` 等后代名字现已存在，业务读写仍以唯一的动态键为边界。新增同名动态节点或跨区移动时需要改寻址。 `BindActions` 按名字绑定退出和重置；攻击钮走按下事件。一次 Refresh 传入 `hasTarget` 和可选的 `windowOpen`，显示分支使用 painting、触控和窗口状态。

文本使用 `ProcessingTextTool → GameTexts/TranslationTool → TextFitting`。单行设计字号以 `DesignTextSize` 为上限。纯数字进度由 `SetProgress` 直接写入并使用模板字号，工具栏名称与数字键走显式拟合。动态键和参数顺序、AutoLocalize、翻译解绑与异步回写保护应随节点迁移。静态键帽、影子和视网膜尺寸是独立属性契约。

源码 [GameScreenGuiManager](../Scripts/ReplicatedStorage/Scripts/Client/UIManager/GameScreenGuiManager.luau)、[ClientProcessingManager](../Scripts/ReplicatedStorage/Scripts/Client/ClientProcessingManager.luau)、[ProcessingTextTool](../Scripts/ReplicatedStorage/Scripts/Client/ProcessingTextTool.luau)、[TextFitting](../Scripts/ReplicatedStorage/Scripts/Client/UIManager/TextFitting.luau)、[GameTexts](../Scripts/ReplicatedStorage/Scripts/Shared/GameTexts.luau)。

## 工具栏

- `C.BottomButtonsFrame : Frame` 内有 `UIListLayout`，隐藏 `ToolButton : ImageButton` 是槽位克隆源。保留 `ToolViewport : ViewportFrame → WorldModel`、`EquippedImage`。 `ToolNameText`、`KeyCodeText` 以存在时写入。 `ToolLvText`、`ToolUsageEffectFrame` 当前源码无读写调用，静态保留。
- `ToolViewport.ViewDirection / PreviewFieldOfView` 控制朝向与相机，模板的 Camera 可能不随序列化或克隆保留，`PreviewCamera` 会补建 Camera。清理旧预览后，把实际 Tool 外观复制到 WorldModel。槽位和空模板共用名字，同层不能按名字识别活槽。
- 按 Tool 实例去重，监控 Backpack 和 Character 的增删及重生，按 `ToolbarOrder` 等规则重排，点击和数字键切换装备，画符期间受 Painting 限制。移除槽位时销毁节点与监听。

源码 [ClientToolbar](../Scripts/ReplicatedStorage/Scripts/Client/ClientToolbar.luau)。

## 世界 UI、笔迹与设计参考

| 模板或场景节点 | 实际放置 | 所有者和易受影响的属性 |
|---|---|---|
| `UI.TargetGui` | 客户端克隆到 PlayerGui，Adornee 为目标 Head | TargetGuiManager。ContentFrame.ClipFrame.FillImage 按剩余命中次数设置宽度，框为 FrameImage。启用随攻击焦点、持有、画符切换，击晕后隐藏。保留可见距离、贴底锚点、AlwaysOnTop 与 LightInfluence |
| `UI.PaintFaceGui` | 平面路径在 PlayerGui 下克隆为 `RuneStroke`，多个同名节点 | PaintFaceGuiManager 按身体/部件/面键缓存。重绑 Adornee、Face 和 CanvasSize。按身体释放 |
| `UI.PaintCellFrame` | 在 RuneStroke 内为 `StrokeSegment`。池中的 Frame 暂时无 Parent | PaintCellFrameManager 更新 `VisualKey/VisualVersion`、Size、Position、Rotation。按身体回收，池上限 256。模板颜色/端帽影响平面笔迹 |
| 曲面身体 | `MeshPart.TextureContent` 的本地 EditableImage | CurvedPaintView 依据 UV、视角、缓冲预算和纹理驻留出图。PaintFaceGui 和 PaintCellFrame 不控制这一路径。修改颜色或笔宽前确认两条渲染路径 |
| `UI.WorldInteractionPrompt` | 本地克隆到 Workspace 工位锚点或可拾取模型，画面由引擎生成 | WorldInteractionManager 克隆 Disabled 的默认 prompt，运行时覆盖激活距离，动态绑定 Action/Object text。键 E、手柄 X、长按 0.5 秒、LoS。签名变更禁用一帧并取消陈旧 hold。触发请求发 target/version |
| Workspace 四块工位牌、八块门店牌 | 静态 SurfaceGui 直挂 Part，内部为单个 TextLabel | 无生产脚本按牌子节点名绑定。依附面、CanvasSize/PixelsPerStud、色彩与文本由场景持久实例定义。工位牌和触发锚点是不同对象 |
| `UI.ScreenLayoutGuideFrame.ReservedAreasFrame` | 设计期 Overlay，7 个参考矩形 | ScreenLayoutGuideFrameManager 要求显式父节点。`DesignOnly` 和采样元数据应保留。当前生产业务无调用 |

源码 [TargetGuiManager](../Scripts/ReplicatedStorage/Scripts/Client/UIManager/TargetGuiManager.luau)、[PaintFaceGuiManager](../Scripts/ReplicatedStorage/Scripts/Client/UIManager/PaintFaceGuiManager.luau)、[PaintCellFrameManager](../Scripts/ReplicatedStorage/Scripts/Client/UIManager/PaintCellFrameManager.luau)、[WorldInteractionManager](../Scripts/ReplicatedStorage/Scripts/Client/WorldInteractionManager.luau)、[PaintView](../Scripts/ReplicatedStorage/Scripts/Client/PaintView.luau)、[CurvedPaintView](../Scripts/ReplicatedStorage/Scripts/Client/CurvedPaintView.luau)。

## 权威边界

`ClientProcessingManager` 聚合输入、画符相机、展示、网络、UI 文案及道具。`ProcessingNet` 和 `GameTypes` 提供 Snapshot、Notice、会话和版本结构。`ServerStorage.Scripts.ProcessingManager` 负责交互条件、覆盖率与奖励。UI 可替换视觉和客户端编排，确认时仍由服务端检查动作、距离、版本、容量及提交条件。基础设置、Marketplace、资料和 Analytics 框架保留现有入口，当前没有对应的自定义窗口模板。
