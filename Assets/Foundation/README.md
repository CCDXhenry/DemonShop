# 基础框架资源恢复

这些 RBXM 只包含实例，不包含运行脚本。目标仅为 DemonShop `110812537538556` 的 Edit 模式；禁止导入到参考场景。

| 文件 | 导入父级 | 根实例 |
| --- | --- | --- |
| ReplicatedStorage.rbxm | ReplicatedStorage | RemoteEvents、BindableEvents（包含加工与基础事件） |
| ServerStorage.rbxm | ServerStorage | BindableEvents |
| SoundService.rbxm | SoundService | SoundGroups |

UI 模板单独从 `Assets/UI/ProjectTemplates.rbxm` 恢复到 ReplicatedStorage.UI；静态禁放参考从 CommonTemplates.rbxm 恢复；模型从 `Assets/Models/GameModels.rbxm` 恢复到 ReplicatedStorage。保留现有场景锚点。

完整恢复时避免同名双份根实例；已有实例优先运行 `Tools/Gameplay/build-foundation-assets.luau` 增量补齐。模型和音量组分开导入可能丢失外部分组引用，导入完成后再运行一次该安装器。安装器只在目标 Edit 模式执行，不创建或覆写脚本，不重建 HUD。

源码只由本地 Scripts 经现有 Script Sync 同步；这些资产不作为游戏运行时文件依赖。
