# 常见故障排除与最佳实践 FAQ (Troubleshooting & FAQ)

本指南汇总了在调用本机本地工具、自动化脚本与 MCP 服务时最常见的高频问题、根本原因分析及标准处置流程。

---

## 一、网络端口与服务冲突

### 1. Roblox MCP 守护端口 `13469` 连不上或被占用
- **故障现象**：调用 MCP 时报错 `Connection refused`，或拉起守护服务时提示 `OSError: [WinError 10048] 通常每个套接字地址只允许使用一次`。
- **根本原因**：上一次运行的守护进程未优雅退出，后台遗留了孤儿 Python 进程占用了 `13469` 端口。
- **排查与解决**：
  ```powershell
  # 1. 查找占用 13469 端口的 PID
  netstat -ano | findstr :13469

  # 2. 终止该残留进程（假设 PID 为 1234）
  Stop-Process -Id 1234 -Force
  ```
- **探活验证**：
  在终端中测试探活端点：
  ```powershell
  curl http://127.0.0.1:13469/health
  # 应返回 200 OK
  ```

### 2. OBS WebSocket `4455` 连接失败或密码错误
- **故障现象**：`obs_media_tool.py` 报错 `WebSocketException` 或 `AuthenticationFailed`。
- **排查与对策**：
  1. 确认 OBS 已经启动，并在 `工具 -> WebSocket 服务器设置` 中勾选了“启用 WebSocket 服务器”；
  2. 核对服务器端口是否为默认的 `4455`；
  3. 若设置了密码，检查当前终端或环境中是否注入了 `OBS_WEBSOCKET_PASSWORD` 环境变量：
     ```powershell
     $env:OBS_WEBSOCKET_PASSWORD = "你的密码"
     ```

---

## 二、路径、盘符与命令行转义异常

### 1. 路径中包含空格导致命令解析失败
- **故障现象**：调用 Blender 或 OBS 时报错 `术语 'C:\Program' 无法识别为 cmdlet...`。
- **根本原因**：Windows 路径包含空格（如 `Program Files`），在 PowerShell 中直接调用未加引用符或未加 `&` 调用运算符。
- **正确书写范式**：
  ```powershell
  # 错误调用方式：
  C:\Program Files\nodejs\node.exe -v

  # 正确调用方式（加引号与 & 符号）：
  & "C:\Program Files\nodejs\node.exe" -v
  & "D:\blender-5.4.0\blender-5.4.0\blender.exe" --version
  ```

### 2. 跨盘符工作目录切换（C 盘 vs D 盘）
- **故障现象**：在 C 盘终端直接启动 D 盘的 OBS 时，OBS 瞬间闪退且无任何日志。
- **根本原因**：OBS 依赖当前工作目录（Cwd）加载周边的动态链接库（DLL）和插件目录。
- **正确启动方式**：
  ```powershell
  Start-Process -FilePath "D:\obs-studio\bin\64bit\obs64.exe" -WorkingDirectory "D:\obs-studio\bin\64bit"
  ```

---

## 三、Roblox 引擎与 MCP 模式状态避坑

### 1. `Module code did not return exactly one value` 假性报错
- **故障现象**：通过 MCP `execute_luau` 调用 `require(...)` 时抛出异常。
- **根本原因**：当前 Studio 处于 **Edit（编辑）模式**。Roblox 引擎出于安全和数据隔离考虑，禁止在编辑模式直接执行业务模块的主体逻辑。
- **规范解法**：
  1. 如果只需要修改 UI 属性、创建实例或修改配置，**切勿使用 require**，直接操作属性；
  2. 如果确实需要验证业务逻辑或函数返回，先调用 `start_stop_play(action='start')` 进入 **Play 模式**，再执行测试。

### 2. 代码在 Studio 中没有生效或被反向覆盖
- **故障现象**：修改了本地文件，Studio 内脚本未更新；或者在 Studio 中修改后，本地文件被冲掉。
- **红线规则**：
  - 项目均严格依托既有的本地同步插件（Script Sync）；
  - **严禁使用 MCP 的 execute_luau 覆写 `Script.Source`**；
  - 遇到同步延迟，可在 Studio 中检查同步插件窗口的状态，或轻微保存/触碰本地文件触发防抖同步。

---

## 四、环境变量与凭据检查清单

| 环境变量名 | 作用组件 | 缺失时后果 | 推荐配置方式 |
| :--- | :--- | :--- | :--- |
| `ROBLOX_API_KEY` | 音频/模型 Open Cloud 上传脚本 | 脚本报凭据缺失退出，无法上云 | 在用户系统环境变量配置，或会话前 `$env:ROBLOX_API_KEY="..."` |
| `OBS_WEBSOCKET_PASSWORD` | OBS 自动化视口采集 | WebSocket 握手认证被拒 | 在环境注入，禁止在脚本或代码中硬编码提交 |
| `ROBLOX_OBS_SCENE` | OBS 视口捕获目标场景 | 使用默认场景名，可能抓错画面 | 可选，用于多工程场景区分 |
| `ROBLOX_OBS_SOURCE` | OBS 视口捕获目标来源窗口 | 使用默认窗口来源名 | 可选，通常为当前 Studio 窗口名 |
