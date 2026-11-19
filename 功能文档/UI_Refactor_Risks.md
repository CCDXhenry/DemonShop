# DemonShop UI 重构风险

风险按造成的回归范围和恢复成本排序。页面证据与实际视口读数见 [UI_Audit.md](UI_Audit.md)，影响路径见 [UI_Node_Contracts.md](UI_Node_Contracts.md)。

| ID | 级别 | 证据和影响 | 后续验收 |
|---|---|---|---|
| R01 | P0 | `Tools/Gameplay/build-game-assets.luau:44–101` 销毁并重建 GameScreenGui、PaintFaceGui、PaintCellFrame。生成的 HUD 缺当前工具栏、窗口画布、模态遮罩和画符光标，需要附加安装步骤才能补部分结构。清理表还删除基础资料／设置远程事件、OpenWindow/CloseWindow 绑定和 UIClick 等共享资源 | 在隔离的资产回归场景中验证，重复运行任何获支持的恢复/补齐流程时，设计模板节点、资源 ID、绑定属性与基础事件保持一致 |
| R02 | P0 | UIManager 在克隆前检查主要根节点，Toolbar 与 HUD 用 WaitForChild 强绑定。移动 CenterFrame、底部模板、Viewport/WorldModel 或触控变体，可令初始化中断或无限等待。当前后代查找有同名 `TitleText`、`LabelText`，FillFrame 和 CountText 也采用递归首个命中 | 在模板与运行实例双层核查必需节点、类型、唯一性和挂载时间。启动、资料补发、重生、销毁和重开各走一次 |
| R03 | P1 | 手机竖屏画布按宽度压缩，既有 HUD、提示与工具槽约为 1920 基准的五分之一，右侧触摸按钮仍保持 140×50。根 ScreenGui 当前实际为 `DeviceSafeInsets` 且 `ClipToDeviceSafeArea=true`，视口和遮罩可用几何需分别验证。画符触摸布局共用底部 Frame | 用实测 viewport、根缩放、Inset 和遮罩尺寸复核，记录字号、系统覆盖、工具槽触控和绘制误触。实机结论另以物理设备复核 |
| R04 | P1 | 原生长按是交互权威入口，HUD 最近目标提示是另一套距离选择和原因说明。更改 HUD、接管 E 或改 Prompt.Style 可能破坏 hold 生命周期、LoS、手柄 X、触摸及版本校验 | 每个工位在可执行、满/占用、状态过期和视线受阻时验证。长按中目标或版本变化时无过期请求，画符时不会误触拾取 |
| R05 | P1 | 画符生命周期跨相机、TouchGui、刷子、指针、权威进度与最终视觉握手。平面 SurfaceGui 与曲面 EditableImage 是两条渲染路径。替换一条模板无法同步深色笔迹／端帽行为 | 同一试验体覆盖进入、落笔、旋转、退出、重入、完成、观察者。双路可见性及颜色一致性按各自可测样本记录，清理预算及失败回退保留 |
| R06 | P1 | 生产源码无已注册窗口，现有游戏画面无法覆盖模态基类的正确性。直接移除 WindowCanvas、ModalButton 或基础消息会破坏未来窗口接入，Processing 还用模态 Visibility 门控世界交互 | 用现有框架回归和临时双窗夹具验证遮罩全屏、顺序、点击关闭、窗口开闭消息、鼠标/触控遮罩和画符输入优先级 |
| R07 | P1 | 工具预览基于实际 Tool 的三维副本，依赖 Viewport 属性、镜头补建和排队去重。固定列表使用 0 宽锚点和未裁剪的 132 槽。长条工具／多药水时可能扩散到操作区。手机显示数字键帽，触端含义弱 | 覆盖 Club、RuneBrush、单/多 Potion、装备切换和快速移入 Backpack，测量实际槽排布、点按及 3D 克隆生命周期 |
| R08 | P1 | 长提示、通知、库存和操作文字由不同入口更新。文字拟合依赖有效设计盒、翻译成功、TextSize 上限。示例静态祭坛牌仍写 `5s`，`GameConfig.ConversionSeconds=10`，实际倒计时来自权威 Snapshot | 长短中英文本、纯数字与符号核验。保持动态键和参数顺序。静态说明与实际计时一致，维护本地化与设计几何无交叉覆盖 |
| R09 | P1 | `build-quality-samples.luau` 包含 PaintFaceGui 属性覆写、光标与 TargetGui 补建以及本地化迁移副本。`update-processing-localization.luau` 按名字扫描并改写 Text/AutoLocalize、Prompt 配置、删除旧交互键帽。新组件复用旧名时会扩大命中范围 | 将旧迁移与新视觉资产流程隔离。对重构模板执行写入范围检测，验证运行前后 diff 仅涉及各自拥有的字段 |
| R10 | P2 | `build-foundation-assets.luau` 缺失时补齐 WindowCanvas/ModalButton，删除旧 StarterGui.GameScreenGui 和 FoundationNotify。已存在的 WindowCanvas 若缺 UIScale 不会补齐。恢复包 `Assets/UI`、`Assets/Foundation` 与当前树如未更新，重导可能恢复旧模板、字段或事件 | 恢复流程以目标节点清单、文件哈希和覆盖模式为依据，做隔离恢复对比。保留旧导出可追溯，不覆盖正式模板 |
| R11 | P2 | `BuildScreenLayoutGuide.luau` 只替换同名设计参考。14 份来源样本继承自参考场景，没有项目设备的重新采样矩阵。直接项目渲染中已能看到系统控件与独立触控按钮共同占据右下区域 | 采集项目自身视口／顶栏／跳跃按钮，以离线投影和并集合并更新参考。双方向及原生 TouchGui 隔离时的显示核验 |
| R12 | P2 | 世界牌直挂 Workspace。部分牌的固定文案、色彩及安装面与 HUD 风格分头维护。白体资产构建器会替换 WhiteR15 网格、UV 和面资源，可能改变曲面画符的可视结果 | 用相同观察距离验证牌面、文本译文和场景光照。替换身体资产时跑 UV/部位/笔迹回归。给场景牌登记所有者 |
| R13 | P2 | 定点 MCP 方可截独立模拟客户端。默认 Roqer 截图在多人模式曾拍到 Edit 布局。项目 OBS 守卫检查同窗口的 Client/客户端文档标签，拦截独立 Play 客户端 | 采集矩阵必须记录实例、设备、输入类型、实际 viewport、截图尺寸和提供方。OBS 扩展或可隔离的单窗口模式需先通过四边审核 |
| R14 | P1 | 桌面画符快照中，左侧工具槽与退出按钮在 X 方向重叠约 61 px、Y 方向约 48 px。手机横屏亦有槽位与底部按钮重叠。竖屏虽分离了触控按钮，HUD 却占用身体绘制区域。桌面入场后切到触屏模拟观察到后来创建的 TouchGui 仍启用 | 同时按几何和输入命中验收。正常入场、端型切换和退出重入按桌面及两方向检查按钮、工具栏、摇杆、落笔及相机 |

## 构建器处理顺序

1. 重构开始前冻结 `build-game-assets.luau` 对正式树的执行，将其破坏性范围纳入基线差异检查。
2. 确定 Scene UI、UI 模板、设计参考、本地化及模型恢复各自的维护入口。样例和旧迁移脚本应在隔离环境核验。
3. 发布视觉模板前对恢复包与 Studio 树做结构、属性、可克隆性和资源清点。回退时按修改的根恢复并验证引用闭合。

源码 [build-game-assets](../Tools/Gameplay/build-game-assets.luau)、[build-quality-samples](../Tools/Gameplay/build-quality-samples.luau)、[update-processing-localization](../Tools/Gameplay/update-processing-localization.luau)、[build-foundation-assets](../Tools/Gameplay/build-foundation-assets.luau)、[build-white-assets](../Tools/Gameplay/build-white-assets.luau)、[BuildScreenLayoutGuide](../.agents/skills/roblox-ui-system/assets/BuildScreenLayoutGuide.luau)。
