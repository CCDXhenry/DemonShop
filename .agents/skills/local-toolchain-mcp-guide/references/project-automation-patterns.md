# 项目级通用自动化模式与脚本指南 (Project Automation Patterns)

本指南总结了在游戏开发工程中极为常见、且具有极高复用价值的自动化工具模式。
尽管部分脚本路径位于当前项目的 `Tools/` 目录下，但其架构设计遵循参数化与解耦标准，可直接复用于任何同类 Roblox / 游戏开发项目。

---

## 一、Luau 严格类型检查自动化 (`check-strict.ps1`)

### 1. 工具定位
针对 Luau 代码进行离线静态分析，自动加载 `sourcemap.json`（若存在）和全局类型定义 `globalTypes.d.luau`，检测 `--!strict` 类型违规。

### 2. 标准调用范式
```powershell
# 1. 检查暂存区（Git Staged）文件（推荐在 Git Commit 前调用）
pwsh -File Tools/check-strict.ps1 -Staged

# 2. 检查特定修改的脚本文件
pwsh -File Tools/check-strict.ps1 Scripts/ServerStorage/Scripts/Ragdoll.luau

# 3. 全局扫描所有业务代码
pwsh -File Tools/check-strict.ps1 -All
```

### 3. 输出解读与质量红线
- 共享库与第三方依赖（如 Core、GameAnalytics）的历史诊断会与本次改动分别汇报；
- 新增/维护的业务脚本首行必须为中文作用注释，第二行为 `--!strict`，且本次改动必须实现零诊断报错。

---

## 二、Roblox Open Cloud 音频全自动上云与 Studio 部署

音频工作流由两阶段组成：**Open Cloud 云端上传（获取 AssetId）** + **Studio Edit 模式模板部署**。

### 1. 增量上传脚本 (`upload_roblox_audio.py`)
- **功能**：基于哈希增量对比，只上传内容发生变更的音频文件，防止重复消耗配额。
- **凭据来源**：自动从环境变量 `ROBLOX_API_KEY` 读取 API Key。
- **调用模板**：
  ```powershell
  python Tools/Audio/upload_roblox_audio.py `
    --names Click,CoinDrop `
    --sounds-dir Assets/Sounds `
    --manifest Assets/Sounds/audio_manifest.json `
    --creator-type group `
    --creator-id <实际归属ID> `
    --prefix <项目前缀>_
  ```

### 2. Studio 模板部署工具 (`setup_sounds_in_studio.py`)
- **功能**：根据清单文件生成对应的 Luau 部署代码（只操作 `ReplicatedStorage.Sounds` 模板，不污染运行时代码）。
- **生成代码模式**：
  ```powershell
  python Tools/Audio/setup_sounds_in_studio.py `
    --names Click `
    --sounds-dir Assets/Sounds `
    --manifest Assets/Sounds/audio_manifest.json `
    --emit-code
  ```
  生成的代码经审查后，通过 Roblox Studio MCP 的 `execute_luau(datamodel_type='Edit')` 执行。

---

## 三、OBS Studio 客户端视口准确采集管线

OBS 视口工具集（`Tools/Studio/`）通过本地 Win32 UI 自动化精确定位 Roblox 内部渲染区域 `QEngineWidget`，实现 1:1 物理像素剪裁与 60FPS 受守卫录像。

### 1. 四步标准采集流程
```powershell
# 步骤 1：自动探测 Play 客户端并生成边界比对预览
python Tools/Studio/obs_media_tool.py calibrate

# 步骤 2：在视觉确认 .cache/obs-viewport/acceptance 下的基准图四边完整后，批准校准
python Tools/Studio/obs_media_tool.py approve

# 步骤 3：只读校验校准合法性（窗口移动或尺寸变化时会报错拦截）
python Tools/Studio/obs_media_tool.py check

# 步骤 4：无失真原尺寸视口截屏
python Tools/Studio/obs_media_tool.py screenshot --save .cache/example.png

# 步骤 5：受守卫录像（自动守卫窗口遮挡与位移，最长 300 秒）
python Tools/Studio/obs_media_tool.py record start --duration 15 --expect-motion
```

### 2. 录像合规自动化核验 (`obs_verify_video.py`)
录像结束后，必须对产出的 MP4 进行解码合规与丢帧核验：
```powershell
python Tools/Studio/obs_verify_video.py ".cache/obs-viewport/record_xxx.mp4"
```
核验关键指标：
- 渲染/编码丢帧增量必须为 0；
- 首、中、尾关键帧画面必须有效且无黑屏；
- 实测分辨率必须与校准时的物理像素完全一致。

---

## 四、Excel 配表转 JSON 自动化 (`excel2json`)

### 1. 工具定位
用于将策划编辑的 `.xlsx` 配置表自动转换为客户端与服务端可加载的紧凑 `.json` 数据文件及对应的 Luau 类型声明。

### 2. 本机路径与调用
- **Windows 执行入口**：`Tools/excel2json/excel2json_Windows.py`
- **底层可执行文件**：`Tools/excel2json/excel2json.exe`
- **调用范式**：
  ```powershell
  python Tools/excel2json/excel2json_Windows.py
  ```
  该脚本会自动读取配置表源目录，批量输出至 `Scripts/ReplicatedStorage/Config` 或指定输出目录。

---

## 五、离线业务规则回归与白模构建

### 1. 离线规则快速回归
针对复杂游戏逻辑（如合成配方、伤害结算、掉落算法），在不启动 Studio Play 的情况下，使用纯 Python 或无依赖 Luau 执行极速验证：
```powershell
python Tools/Gameplay/test_rules.py
```

### 2. 白模拓扑生成与上传
```powershell
python Tools/Gameplay/build_white_body.py
python Tools/Gameplay/upload_white_body.py
```
通过纯脚本构建符合角色身高的参考网格并自动推流。
