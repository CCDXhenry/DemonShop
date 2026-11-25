# 独立模型与预制体结构

用于新增独立刚性道具、动物/生物、装备与表现预制体的通用规范。已有资产优先兼容实际消费代码。

## 存储边界与目录分类

- **静态常驻场景直接放 `Workspace`**：地图、建筑、工位、静态锚点与已在 Edit 模式摆放好的固定设施常驻 `Workspace`，不放进 `ReplicatedStorage.Models`，不在服务端启动时从 `ReplicatedStorage` 克隆整张静态地图，也不塞入运行时模板恢复包。
- **`ReplicatedStorage.Models` 仅放运行时动态创建/克隆的模板**：凡在运行中通过 `Clone()` 实例化的角色/NPC、装备武器、角色挂件、道具、表现/瞄准特效与 3D 视口预览模板，统一以 `ReplicatedStorage.Models` 作为唯一实例来源，避免多份副本漂移。
- **分类明确，禁止根目录散放**：`ReplicatedStorage.Models` 根目录只放置语义明确的分类 `Folder`（如 `Characters`、`Weapons`、`CarryRigs`、`Items`、`Effects`、`Previews`），禁止在根目录直接平铺 `Model`、`Tool` 或 `WorldModel`；业务代码通过共享模板索引模块或明确分类路径读取，预加载逻辑需遍历分类子目录。
- **Edit 专用或废弃原型不留驻 `Models`**：仅用于 Edit 构建期且运行时不克隆的静态设施母版、已退役的旧原型模型，不长期滞留在 `ReplicatedStorage.Models`。

## 锚点与边界

- 需要统一放置锚点时，以 RootPart 为 Model.PrimaryPart。新建辅助 RootPart 默认 Part 尺寸 0.2×0.2×0.2，位于模型底部中心，底面与视觉包围盒底面对齐。
- 计算包围盒时只取实际视觉部件，排除已有 RootPart、VfxInstance、触发体及其他辅助件，避免重复处理使边界不断膨胀。
- 明确模型局部朝向；倾斜模型的底部中心按约定局部轴计算，不能将旋转包围盒的高度直接当世界 Y 高度。
- 需要粒子范围或头顶 UI 锚点时添加 VfxInstance，使其中心与尺寸匹配视觉包围盒；模型几何变化后核对边界，不重复计算包含辅助件的包围盒。
- 辅助件透明、无阴影、无碰撞、无触碰、无查询且 Massless。VfxInstance 是参考边界，不能凭其存在当作真实命中盒。

## 约束与物理

- 刚性模型的 WeldConstraint 集中在 RootPart 下，Part0 指向 RootPart，Part1 指向对应可视件或 VfxInstance；命名区分目标，避免重复约束。
- 不盲删已有 RootPart 或约束；先检查引用、Joint、动画及物理用途。重复执行标准化应保持幂等，不破坏 ObjectValue 或业务引用。
- 静态展示模板可 Anchored=true。动态移动、掉落或拾取物按实际物理需求设置 Anchored、CanCollide、CanTouch、CollisionGroup、质量和网络所有权。
- 焊接的动态装配不能因某个子件仍 Anchored 而导致整体固定。实际承载碰撞与质量的部件需要明确，不将透明辅助件当作唯一物理本体。
- Bone、Motor6D、AnimationController/Animator 和原有 Rig 层级保持完整；不能将需要相对运动的关节焊死到 RootPart。角色/生物保留其规范骨骼与 Humanoid/Animation 契约。

## 验证

- 持久资产只在 Studio 的 Edit 模式编辑。
- 检查 PrimaryPart、PivotTo、缩放后边界、碰撞查询和约束数量；动态资产按授权在 Play 中验证解锚、重力与碰撞行为。
