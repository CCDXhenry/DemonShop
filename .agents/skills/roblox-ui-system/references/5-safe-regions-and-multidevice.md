# 固定画布、移动端触控区与多端统一禁放参考

## 一、日常 UI 制作：全端统一一张 1920×1080 画布

- **所有自研屏幕 UI**（包含普通 HUD、功能按钮、弹窗及移动端虚拟操作按键）的完整根画布固定 `1920×1080`，居中；所有内容在该画布内排版。局部面板、列表项与触控按键均按设计稿使用 Offset 尺寸。
- 根 `UIScale` 仅使用 `min(屏幕宽/1920, 屏幕高/1080)`，不扩展逻辑尺寸。若项目 `UIAdapter` 的 `FullScreen` 会扩展根尺寸，必须使用只缩放的 `Center` 模式。
- 屏幕容器 `ScreenGui` 强制配置 `ScreenInsets = Enum.ScreenInsets.None` 与 `IgnoreGuiInset = true`（严禁混用 `DeviceSafeInsets`，否则刘海屏下容器区域缩小会导致 `CenterFrame` 居中基准与 `ViewportSize` 缩放基准错位、`ModalButton` 边缘漏白）。背景与模态遮罩独立铺满真实视口；画布之外显示游戏场景，不同宽高比不重排控件。
- 通用 HUD、功能按钮（如退出/重置）与弹窗双端合一，不拆 `Desktop` / `Touch` 两套独立模板；仅触控独有操作（跳跃、攻击、冲刺、虚拟摇杆等）统一预置在根画布的 `TouchControlsFrame` 子容器内，在 Studio Edit 中与 HUD/工具栏同画布所见即所得排版。
- 触控按键通过 `1920×1080` 设计尺寸自然满足点击舒适度（主流横屏手机 `scale ≈ 0.35~0.40`，主操作键设计 `180~200 px` 对应真实屏幕约 `63~76 px`，辅助键 `150~160 px` 对应约 `53~64 px`），**严禁在运行时按屏幕像素或原生跳跃键坐标重算位置与物理尺寸**。
- 全项目统一以 `UserInputService.PreferredInput == Enum.PreferredInput.Touch` 作为触控 UI 显隐唯一判定口径，**禁止混用 `UserInputService.TouchEnabled`**（避免触屏笔记本或外接键鼠平板误显触控键）。
- Studio Edit 预置 `ReplicatedStorage.UI.ScreenLayoutGuideFrame`：透明 `1920×1080` Frame，内部 `ReservedAreasFrame` 由静态红色矩形表示多端系统禁放区并集。
- 设计时临时复制到业务画布下，`AnchorPoint=(0,0)`、`Position=(0,0)`、尺寸不变、不加第二层 `UIScale`。所有节点 `Active=false`，不包含按钮/滚动容器。
- 文字、按钮和关键内容避开红色块；背景与装饰可进入。红色块已经包含统一间距，不重复追加同一间距。完成核对后移除临时副本，正式业务模板不携带参考层，客户端不绑定、不监听、不查询这张图。
- 公共禁放参考**默认仅纳入左上系统区（`TopLeftCore`）**的多端并集；不预留底部横条、设备侧边、右上系统区或左下摇杆。仅当个别旧项目显式保留 Roblox 原生跳跃键时，才通过参数按需将 `JumpButton` 纳入并集（即便避让原生跳跃键，所有自研按钮也必须留在 `1920×1080` 画布内静态固定，绝不运行时追踪）。

## 二、移动端操作 UI 与原生控件工程规范

默认推荐方案：**保留 Roblox 原生左下移动摇杆，仅压制隐藏原生 `JumpButton`，右侧所有操作键（含自研固定跳跃键）在 `CenterFrame.TouchControlsFrame` 内自主固定排版**。

### 1. 原生 `JumpButton` 防反弹压制（保留左移动摇杆）
- Roblox 的 `PlayerModule.ControlModule.TouchJump` 会在触屏环境创建 `PlayerGui.TouchGui.TouchControlFrame.JumpButton`，且在角色重生或 `Humanoid.JumpPower`/`JumpHeight` 变更时重新将其设为 `Visible = true`。
- 正确压制方式：
  - 仅定位 `PlayerGui.TouchGui` 下名为 `JumpButton` 的 `GuiObject`，**严禁关闭或破坏 `TouchGui` 或左侧摇杆节点**（除非进入画符/全屏特写等明确禁用移动的模式）；
  - 对原生 `JumpButton` 执行：`Visible = false`、`Active = false`、`Selectable = false` 并移出可视区域（如 `Position = UDim2.fromOffset(-9999, -9999)`）；
  - 监听 `PlayerGui.DescendantAdded` 以及目标按钮的 `Visible`、`AncestryChanged` 信号，一旦引擎尝试恢复显示立即再次压制；销毁时释放所有连接，保证重复初始化幂等。
  - **严禁通过设置 `Humanoid.JumpPower = 0` 或 `JumpHeight = 0` 来隐藏原生跳跃键**，否则自研跳跃键也无法起跳。

### 2. 自研固定跳跃键交互契约
- **单点与长按连跳**：监听 `JumpButton.InputBegan`（接受 `Touch` 及测试用 `MouseButton1`），记录当前触发的那一根 `InputObject`，立即触发 `Humanoid.Jump = true`，并在按住期间持续维持跳跃请求（实现与 Roblox 原生 `TouchJump` 一致的长按自动连跳）。
- **多点触控与防穿透**：设置 `JumpButton.InputSink = Enum.InputSink.Activate`，仅追踪对应 `InputObject`，避免点击跳跃穿透触发镜头旋转或误攻击，且不干扰左手移动摇杆。
- **完备中断清理**：在抬手（`InputEnded`）、`UserInputState.Cancel`、按钮/父容器隐藏、进入画符或锁定视角模式、打开模态窗口、系统菜单打开（`GuiService.MenuOpened`）、窗口失焦（`WindowFocusReleased`）或角色移除/死亡时，立即释放输入引用并停止跳跃请求。

### 3. 父容器显隐与子控件可见性双保险
- 当触控按钮和虚拟摇杆收纳在 `TouchControlsFrame` 下时，非触控端隐藏父容器后，若某业务模块仅判断子控件自身的 `child.Visible`（例如键鼠鼠标按下时判断 `if throwStick.Visible then return end`），可能因父隐藏而子仍为 `true` 产生误拦截。
- **强制双保险**：UI 管理器刷新时同步更新父容器与受控子帧的 `Visible`；同时消费子控件可见性的输入控制器应校验**完整祖先可见链**（所有 `GuiObject` 祖先 `Visible == true` 且宿主 `ScreenGui.Enabled == true`）。

### 4. `ScreenInsets = None` 与指针/摇杆坐标核查
- 确认 `ScreenGui.ScreenInsets = Enum.ScreenInsets.None`、`IgnoreGuiInset = true` 后，需核对以下三类坐标：
  - `CenterFrame` / `WindowCanvas` 居中原点与 `ViewportSize` 严格一致；
  - `ModalButton`（`Size = {1,0},{1,0}`）100% 铺满含刘海与圆角在内的真实物理视口；
  - 自定义屏幕指针/笔刷（如 `PaintPointer`）与虚拟摇杆（如 `ManualThrowController`）的屏幕坐标换算不因 TopBar Inset 产生垂直偏移（摇杆拖拽半径直接读取 `stick.AbsoluteSize` 可自动适配 `CenterFrame.UIScale`）。

## 三、首次建立／补充设备时的开发期采样

采样只在建立参考图或补充设备时执行，不是每个新 UI 的接入步骤。

1. 先落地最终固定画布（`ScreenInsets = None`、`IgnoreGuiInset = true`）和根缩放，再启动已获授权的 Studio 运行客户端。记录当前设备模拟设置，完成后恢复并停止本次测试。
2. 查询 Studio 实际预设 ID，覆盖桌面 1920×1080、1280×720、2560×1440、2560×1080；手机覆盖常规 16:9、超宽、刘海/切角；平板覆盖 4:3 与接近 16:10。手机、平板采集两个横屏方向。
3. 布局稳定后读取真实屏幕尺寸、根原点、根缩放、逻辑尺寸、设备四边安全区、顶栏左右系统占用区；若项目显式保留原生跳跃键，则一并记录有效可见跳跃键；不采集摇杆。尺寸以客户端实际读数为准，不以预设值替代。
4. 普通系统按钮及收起聊天的布局纳入参考；展开聊天窗口、系统菜单和软键盘等临时覆盖层不永久预留。确保截图与测量状态对应。
5. 跳跃键仅在显式启用 `JumpButton` 合并，且自己与所有 `GuiObject`/`ScreenGui` 祖先均可见、尺寸非零时纳入。缺失、隐藏和读取失败分别记录，失败不能被当作无占用。
6. 保存原始 JSON 与截图，注明 Studio 模拟还是物理真机、设备预设、方向、时间、系统状态；不能将模拟结果描述为真机测试。截图工具若遗漏 CoreGui，补充应用窗口截图核对系统按钮。

采样资产 `ReadScreenLayoutSample.luau` 在**客户端插件上下文**执行；先配置该项目的 ScreenGui 和业务根路径。它不是业务脚本，不复制进 Scripts 同步根，不向游戏注入长期监听。

## 四、坐标换算与并集规则

`GuiService:GetInsetArea` 的原点与 `GuiObject.AbsolutePosition` 必须统一：

```text
full = GetInsetArea(ScreenInsets.None)
shift = -full.Min
屏幕矩形 = 引擎矩形 + shift
画布屏幕原点 = Root.AbsolutePosition + shift
设计矩形 = (屏幕矩形 - 画布屏幕原点) / 根缩放
```

- 先与 `[0,1920]×[0,1080]` 求交；完全位于画布外及零面积区域不纳入。
- 再向外增加默认 `24` 设计像素间距，向外取整并裁回画布。
- 通过 `includedRegionNames` 选择合并区域：**默认为 `["TopLeftCore"]`**（自研固定跳跃键项目）；仅显式保留原生跳跃键的项目传入 `["TopLeftCore", "JumpButton"]`。其他原始矩形仅留档；对全部入选有效样本取精确矩形并集，分割后只合并相邻且边界匹配的矩形；保留不连续区域、顶部中央通道和内部空洞。不使用整组大包围盒。
- 工具必须验证：根逻辑尺寸、缩放、居中原点和遮罩尺寸正确；合并结果完整覆盖每一个已扩边矩形。
- 不给所有项目预填同一组矩形数值。各项目以自身最终缩放、系统设置及采样矩阵生成结果。

离线工具调用：

```text
python scripts/build_screen_layout_guide.py samples.json --output-dir output
```

输入包含 `canvas=[1920,1080]`、`padding=24`、可选 `includedRegionNames`（默认 `["TopLeftCore"]`）、`samples`。每个样本包含 `logicalSize`、`screenSize`、`origin`、`scale`、`movementExcluded=true`、`modal.size`，以及 `reserved=[{name,screenRect:[x1,y1,x2,y2]}]`。采样器输出这些字段；设备标签和截图路径由采样执行器补充。

输出投影记录、`screen-layout-union.json` 和 `screen-layout-guide.svg`。在 Studio Edit 中执行构建资产，以 `BuildScreenLayoutGuide(UI文件夹, rectangles)` 创建或更新唯一公共模板。矩形数组为设计坐标 `[x1,y1,x2,y2]`。业务不依赖参考块数量与名称。

## 五、运行时与验收边界

- 客户端只有根整体缩放；**所有屏幕 UI（含移动端触控操作按钮）均不使用区域控制器、顶栏水平夹取、物理尺寸补偿或原生跳跃键坐标追踪**。
- 顶栏／设备采样与离线并集不进入客户端。旧动态区域模块、原生跳跃键依附属性（`JumpAnchor`/`JumpGapDirection`/`JumpRelativeSize`/`MinimumTouchSize`）与画布外触控模板在迁移后移除。
- 将参考图反投影到已测设备，并结合截图与数值验证覆盖；确认正式模板没有参考副本，`ScreenInsets = None`，背景/遮罩铺满真实视口。
- 验证 HUD 重复初始化、销毁、事件解绑、模态交互、原生 `JumpButton` 全程隐藏（含角色重生不反弹）、左下原生摇杆正常、自研跳跃键单点/长按连跳及中断清理。
- 静态参考覆盖已采样设备和状态；新增设备、系统 UI 变化通过离线补采样更新。最终报告分别注明静态检查、同步、模板和运行验证状态。
