# DemonShop UI 审计截图

全部图像采集于 `110812537538556`（开发者_恶魔商店）的 Studio 本地测试客户端。通过 Roblox Studio MCP `screen_capture` 定位到 Client 窗口。JPEG 保存 Studio 原输出。图片解码、尺寸和 SHA-256 已记录在 [UI_Inventory.json](../UI_Inventory.json)。

## 设备与采集范围

| 模式 | 模拟 | 运行采样 |
|---|---|---|
| 桌面 | HD 720 预设 | 典型 Paint/药水快照的 Camera.ViewportSize 为 1279×720，根 UIScale 为约 0.666。抓图帧由 MCP 独立导出 |
| 横屏 | iPhone 13、LandscapeLeft | Camera.ViewportSize 749×389，根 UIScale 约 0.360 |
| 竖屏 | iPhone 13、Portrait | Camera.ViewportSize 389×762，根 UIScale 约 0.203 |

手机为 Studio 设备模拟。在两种方向各观察了空手、画符中切换设备、触屏模式就绪后进入画符。桌面攻击、原生长按和落笔包含实际客户端输入。流程中使用了测试定位、个别生产管理器调用与完成态夹具。金币数据由进程内表承载。

## 截图索引

| 文件 | 导出像素 | 状态 |
|---|---:|---|
| [desktop-01-idle-mcp.jpg](desktop-01-idle-mcp.jpg) | 1920×1080 | 出生、金币 0、空手引导、Club |
| [desktop-02-target-hit-mcp.jpg](desktop-02-target-hit-mcp.jpg) | 1919×1080 | 首次命中 1/3 与街道门店标牌 |
| [desktop-03-stunned-pickup-hint-mcp.jpg](desktop-03-stunned-pickup-hint-mcp.jpg) | 1919×1080 | 三次击晕、HUD 拾取引导，另验证原生 Hold 成功 |
| [desktop-04-carry-pool-hint-mcp.jpg](desktop-04-carry-pool-hint-mcp.jpg) | 1919×1080 | 肩扛与存放池指引。工位定位后重新挂接 |
| [desktop-05-pool-stored-mcp.jpg](desktop-05-pool-stored-mcp.jpg) | 1919×1080 | 存入共享池，库存由 0 到 1 |
| [desktop-06-paint-mcp.jpg](desktop-06-paint-mcp.jpg) | 1919×1080 | 画符初始界面、进度与两个工具槽 |
| [desktop-07-paint-stroke-mcp.jpg](desktop-07-paint-stroke-mcp.jpg) | 1919×1080 | 桌面实际虚拟指针绘制、3% HUD 与曲面可见笔迹 |
| [desktop-08-painted-table-mcp.jpg](desktop-08-painted-table-mcp.jpg) | 1919×1080 | 完成态夹具、工位取回文字和按钮 |
| [desktop-09-altar-countdown-mcp.jpg](desktop-09-altar-countdown-mcp.jpg) | 1919×1080 | 祭坛转化中、权威计时从 10 秒开始 |
| [desktop-10-potion-shelf-mcp.jpg](desktop-10-potion-shelf-mcp.jpg) | 1919×1080 | 转化完成、架上药水与取药引导 |
| [desktop-11-potion-equipped-mcp.jpg](desktop-11-potion-equipped-mcp.jpg) | 1919×1080 | 装备 Potion、槽位变化和提交引导 |
| [desktop-12-submitted-mcp.jpg](desktop-12-submitted-mcp.jpg) | 1919×1080 | 提交后药水移除、烟花与 100 金币反馈 |
| [desktop-13-target-focus-mcp.jpg](desktop-13-target-focus-mcp.jpg) | 1919×1080 | 目标聚焦的场景帧。同期运行记录确认标牌启用和绑定 |
| [mobile-landscape-01-idle-mcp.jpg](mobile-landscape-01-idle-mcp.jpg) | 1920×887 | 空手、常驻 HUD 和原生触控 |
| [mobile-landscape-02-paint-mcp.jpg](mobile-landscape-02-paint-mcp.jpg) | 1920×887 | 桌面先进入画符，再切换到手机。观察 TouchGui 创建时序 |
| [mobile-landscape-03-direct-paint-entry-mcp.jpg](mobile-landscape-03-direct-paint-entry-mcp.jpg) | 1920×887 | 手机模拟就绪后进入画符。TouchGui 已禁用 |
| [mobile-portrait-01-idle-mcp.jpg](mobile-portrait-01-idle-mcp.jpg) | 498×1080 | 空手、常驻 HUD 和原生触控 |
| [mobile-portrait-02-paint-mcp.jpg](mobile-portrait-02-paint-mcp.jpg) | 498×1080 | 桌面先进入画符，再切换到手机。观察 TouchGui 创建时序 |
| [mobile-portrait-03-direct-paint-entry-mcp.jpg](mobile-portrait-03-direct-paint-entry-mcp.jpg) | 498×1080 | 手机模拟就绪后进入画符。TouchGui 已禁用 |

## 证据边界

- 对原生 Prompt 的 Enabled、长按时长、路径和文案进行了客户端读数，长按拾取成功。世界标牌快照还读得 `Enabled=true`、目标 Head 和 `HIT 0 / 3`。这些读数见清单，截图只用于对应可见场景和 HUD。
- OBS 校准使用项目守卫、目标 `Place1 - Roblox Studio`。守卫报告「未选中 Play 客户端标签」，Studio MCP 同时确认独立窗口的活动 DataModel 是 Client。OBS 通过该守卫的有效采集为 0。专用场景的配置步骤在守卫确认窗口前未执行。
- 系统顶栏、原生长按提示的完整画面、实体手机、完整手涂至终点、多客户端与压力状态须在后续补证。当前 Play 已结束并恢复 Edit，设备模拟已关闭。
