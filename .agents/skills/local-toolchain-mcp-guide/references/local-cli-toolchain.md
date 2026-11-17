# 本机通用 CLI 与语言工具链指南 (Local CLI & Toolchain)

本指南汇总了本机所有通用开发命令行工具、包管理器及语言服务的物理路径、版本核验命令及常用调用范式。

---

## 一、Python 与生态包管理

### 1. Python 3.13 (Miniconda 环境)
- **绝对物理路径**：`C:\Users\herong\AppData\Local\miniconda3\python.exe`
- **PATH 状态**：已加入系统 PATH（可直接在终端使用 `python`）
- **版本检查**：
  ```powershell
  & "C:\Users\herong\AppData\Local\miniconda3\python.exe" --version
  # 输出：Python 3.13.x
  ```
- **典型用法**：
  - 运行单文件脚本：`python path/to/script.py`
  - 模块模式执行：`python -m unittest discover -s tests`
  - 安装依赖包：`pip install -r requirements.txt`

### 2. uv / uvx (现代化极速 Python 包与工具管理器)
- **绝对物理路径**：
  - `uv.exe`：`C:\Users\herong\.local\bin\uv.exe`
  - `uvx.exe`：`C:\Users\herong\.local\bin\uvx.exe`
- **PATH 状态**：已加入系统 PATH
- **版本检查**：
  ```powershell
  uv --version
  uvx --version
  ```
- **核心优势与用法**：
  - **即用即弃免安装运行 Python CLI 工具**（推荐用于 MCP 启动）：
    ```powershell
    uvx <package-name>
    # 例如启动 Blender MCP 服务：
    uvx mcp-for-blender
    ```
  - **极速虚拟环境创建与依赖同步**：
    ```powershell
    uv venv
    uv pip install -r requirements.txt
    ```

---

## 二、Node.js 与前端生态

### 1. Node.js & npm
- **绝对物理路径**：
  - Node：`C:\Program Files\nodejs\node.exe`
  - npm 脚本：`C:\Program Files\nodejs\npm.ps1`（或 `npm.cmd`）
- **PATH 状态**：已加入系统 PATH
- **版本检查**：
  ```powershell
  node -v
  npm -v
  ```
- **典型用法**：
  - 运行 JS 脚本：`node script.js`
  - 启动工具服务：`npm run build`、`npm test`

---

## 三、版本控制系统 (VCS)

### 1. Git
- **绝对物理路径**：`C:\Program Files\Git\cmd\git.exe`
- **PATH 状态**：已加入系统 PATH
- **版本检查**：
  ```powershell
  git --version
  ```
- **常用命令规范**：
  - 查看状态：`git status`
  - 暂存改动：`git add <files>`
  - 提交改动：`git commit -m "feat/fix: 说明"`
  - 查看分支：`git branch -a`

### 2. TortoiseSVN (SVN CLI)
- **绝对物理路径**：`C:\Program Files\TortoiseSVN\bin\svn.exe`
- **PATH 状态**：已加入系统 PATH
- **版本检查**：
  ```powershell
  svn --version
  ```
- **常用命令规范**（在包含 SVN 外部依赖或美术仓库的场景中使用）：
  - 检查状态：`svn status`
  - 更新仓库：`svn update`
  - 查看变更差异：`svn diff`

---

## 四、终端 Shell 环境

### 1. PowerShell 7 (pwsh) - 推荐主要 Shell
- **绝对物理路径**：`C:\Program Files\PowerShell\7\pwsh.exe`
- **PATH 状态**：已加入系统 PATH
- **调用规范**：
  ```powershell
  pwsh -File path/to/script.ps1
  pwsh -Command "Write-Host 'Hello'"
  ```

### 2. Windows PowerShell (System 5.1)
- **绝对物理路径**：`C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe`
- **适用场景**：备用环境，或调用某些特定 COM / Win32 老旧系统组件。

---

## 五、Roblox 与 Luau 专项语言工具链

### 1. Aftman (Roblox CLI 包管理器)
- **绝对物理路径**：`C:\Users\herong\.aftman\bin\aftman.exe`
- **PATH 状态**：`~/.aftman/bin` 已加入 PATH
- **用途**：用于管理 Roblox 工具链版本（如 Rojo、luau-lsp、selene 等）。
- **用法**：
  ```powershell
  aftman install
  aftman update
  ```

### 2. Rojo (Roblox 同步与构建工具)
- **绝对物理路径**：`C:\Users\herong\.aftman\bin\rojo.exe`
- **PATH 状态**：已加入系统 PATH
- **版本检查**：
  ```powershell
  rojo --version
  ```
- **用法与项目约定**：
  - 启动同步服务：`rojo serve default.project.json`
  - 构建项目文件：`rojo build -o Game.rbxl`
  - *注意：若项目使用自定义 Script Sync 工具同步代码，请按项目特定规范执行，不随意引入冲突的 Rojo 服务。*

### 3. luau-lsp (Luau 语言服务器与离线类型检查)
- **绝对物理路径**：`C:\Users\herong\.aftman\bin\luau-lsp.exe`
- **PATH 状态**：已加入系统 PATH
- **用法**：
  ```powershell
  # 离线严格类型分析与语法分析
  luau-lsp analyze --settings=path/to/settings.json <目标文件或目录>
  ```

### 4. Stylua (Luau 代码格式化工具)
- **绝对物理路径**：`C:\Users\herong\AppData\Roaming\npm\stylua.ps1`
- **PATH 状态**：已加入系统 PATH
- **版本检查**：
  ```powershell
  stylua --version
  ```
- **典型用法**：
  - 格式化单个文件：`stylua Scripts/ServerScriptService/ServerRoot.legacy.luau`
  - 检查代码风格（不写入）：`stylua --check Scripts/`

---

## 六、Google Antigravity CLI

### 1. agy (Antigravity 命令行客户端)
- **绝对物理路径**：`C:\Users\herong\AppData\Local\agy\bin\agy.exe`
- **PATH 状态**：已加入系统 PATH
- **版本与状态检查**：
  ```powershell
  agy --version
  agy status
  ```
