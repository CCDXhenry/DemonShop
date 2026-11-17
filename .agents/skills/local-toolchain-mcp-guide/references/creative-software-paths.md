# 本机大型创作软件与无头环境调用指南 (Creative Software Paths & Headless Guide)

本指南详细记录了本机已安装的 3D 建模、屏幕录制、实时协作及游戏引擎等大型软件的物理路径、无头（Headless）自动化调用范式及工作目录约束。

---

## 一、Blender 5.4.0 (3D 建模与无头渲染)

### 1. 软件信息与绝对路径
- **版本**：Blender 5.4.0
- **主程序物理路径**：`D:\blender-5.4.0\blender-5.4.0\blender.exe`
- **启动器路径**：`D:\blender-5.4.0\blender-5.4.0\blender-launcher.exe`
- **PATH 状态**：未加入全局 PATH，**必须使用绝对物理路径调用**。

### 2. 无头自动化模式（Headless Mode）调用范式
Blender 支持无图形界面直接执行 Python 脚本（利用内部 `bpy` 库完成全自动拓扑生成、几何断言、多视角自动渲染导出）。

```powershell
# 标准调用模板
& "D:\blender-5.4.0\blender-5.4.0\blender.exe" --background --python <Python脚本路径> -- [传递给脚本的自定义参数]
```

#### 常用参数说明：
- `--background` 或 `-b`：后台无头运行，不开启任何 GUI 窗口；
- `--python <file.py>` 或 `-P <file.py>`：启动后立即执行指定的 Python 脚本；
- `--factory-startup`：忽略用户自定义设置与插件，保证纯净无干扰环境；
- `--`：分隔符，此符号后的所有参数将作为普通命令行参数传递给脚本内部（通过 `sys.argv` 读取）。

#### 自动化脚本执行示例：
```powershell
# 示例：执行道具自动化建模脚本并导出 glb
& "D:\blender-5.4.0\blender-5.4.0\blender.exe" --background --factory-startup --python "Tools/Gameplay/build_white_body.py" -- --output "Assets/Models/WhiteBody.glb"
```

---

## 二、OBS Studio (64-bit 游戏视口准确采集)

### 1. 软件信息与绝对路径
- **主程序物理路径**：`D:\obs-studio\bin\64bit\obs64.exe`
- **工作目录要求**：`D:\obs-studio\bin\64bit\`
- **PATH 状态**：未加入全局 PATH。

> [!WARNING]
> **启动工作目录约束**：
> 如果通过脚本或命令行拉起 OBS，**必须将工作目录（Cwd / WorkingDirectory）设置为 `D:\obs-studio\bin\64bit\`**，否则 OBS 无法正确加载其核心依赖与插件 DLL，会导致静默退出或黑屏。

### 2. OBS WebSocket 服务配置
- **默认监听地址**：`127.0.0.1:4455`
- **协议标准**：OBS WebSocket v5 协议
- **安全鉴权**：
  - 密码需在 OBS 的 `工具 -> WebSocket 服务器设置` 中配置；
  - 自动化脚本需通过环境变量 `OBS_WEBSOCKET_PASSWORD` 传递密码，禁止在代码或日志中明文打印。

### 3. 本地联动工作流说明
在 Roblox 自动化测试与视频验收中，推荐通过项目封装的 `Tools/Studio/obs_media_tool.py` 驱动 OBS（基于 Win32 视口物理像素自动裁切，实现 1:1 无黑边 60FPS 采集）：
```powershell
# 1. 视口校准
python Tools/Studio/obs_media_tool.py calibrate

# 2. 视觉核验后批准
python Tools/Studio/obs_media_tool.py approve

# 3. 截取视口高清图
python Tools/Studio/obs_media_tool.py screenshot --save .cache/capture.png

# 4. 守卫录像
python Tools/Studio/obs_media_tool.py record start --duration 10 --expect-motion
```

---

## 三、Spline (3D 交互设计协作工具)

### 1. 软件信息与绝对路径
- **客户端物理路径**：`C:\Users\herong\AppData\Local\Programs\Spline\Spline.exe`
- **MCP 服务端脚本**：`C:\Users\herong\AppData\Local\Programs\Spline\resources\spline-mcp.cjs`

### 2. 运行与服务机制
Spline 是一款基于 Electron 的 3D 设计工具。本机不仅安装了客户端，还配置了 Spline MCP 服务（通过将 `Spline.exe` 设置环境变量 `ELECTRON_RUN_AS_NODE=1` 运行 `spline-mcp.cjs`）。
详细 MCP 工具调用请参见 [Spline 2D/3D MCP 工具手册](mcp-spline.md)。

---

## 四、Roblox Studio & Roblox Player

### 1. 客户端安装绝对路径
- **Roblox Studio 主程序**：
  `C:\Users\herong\AppData\Local\Roblox\Versions\version-63eb6055af4e4688\RobloxStudioBeta.exe`
  *(注意：Roblox 客户端每次版本更新会自动更换 `version-xxxxxxxx` 目录，动态定位见下节)*
- **Roblox Player 客户端**：
  `C:\Users\herong\AppData\Local\Roblox\Versions\version-4ea8e85481e34f46\RobloxPlayerBeta.exe`

### 2. 动态定位与版本无关寻址 (Best Practice)
由于 Roblox 更新机制会轮转目录，推荐通过系统注册表或批处理脚本寻址：
- **MCP 包装入口**：
  `C:\Users\herong\AppData\Local\Roblox\mcp.bat`
  该脚本已自动实现注册表寻址逻辑：
  ```bat
  for /f "tokens=2*" %%A in ('reg query HKEY_CURRENT_USER\Software\Roblox\RobloxStudio /v ContentFolder') do (
      "%%B/..\StudioMCP.exe" %*
  )
  ```
- **Studio 启动与场景文件打开**：
  在命令行中打开指定 `.rbxl` 工程：
  ```powershell
  & "C:\Users\herong\AppData\Local\Roblox\Versions\version-63eb6055af4e4688\RobloxStudioBeta.exe" "C:\path\to\game.rbxl"
  ```
