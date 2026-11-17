# Blender、Filesystem 与 Memory MCP 使用指南 (Blender, Filesystem & Memory MCP)

本指南涵盖本机已配置的 Blender MCP、内置系统文件服务（Filesystem MCP）以及长期记忆系统（Memory MCP）。

---

## 一、Blender MCP (`mcp-for-blender`)

### 1. 服务配置信息
- **配置文件**：`C:\Users\herong\.gemini\config\mcp_config.json`
- **注册定义**：
  ```json
  "blender": {
    "command": "C:\\Users\\herong\\.local\\bin\\uvx.exe",
    "args": [
      "mcp-for-blender"
    ]
  }
  ```
- **核心机制**：通过 `uvx` 免安装隔离拉起 `mcp-for-blender` 服务，作为标准 JSON-RPC 接口与本地 Blender 进行通信。

### 2. 双路线工作流选择：MCP vs CLI Headless

| 特性维度 | Blender MCP (`mcp-for-blender`) | CLI 无头脚本 (`blender.exe -b -P`) |
| :--- | :--- | :--- |
| **执行模式** | 通过 MCP 协议通信，适合交互式探查与单步建模 | 后台无头静默批处理，全自动执行 |
| **执行时间** | 适合快速操作与状态获取 | 支持复杂长脚本（如 200 秒增量建模与渲染） |
| **使用场景** | 场景节点探查、材质轻量调整 | 自动化拓扑分析、四视角渲染合成、GLB 批量导出 |
| **调用命令** | `call_mcp_tool(ServerName="blender", ...)` | `& "D:\blender-5.4.0\blender-5.4.0\blender.exe" -b -P script.py` |

---

## 二、Filesystem MCP (系统文件操作服务 - 14 项)

Filesystem MCP 提供了无需依赖系统 Shell、跨平台的沙箱化文件读写与目录探查能力。

### 核心工具列表与参数范式：
1. **`list_directory`**：列出目录下的直接子文件与子目录。
   - 参数：`path` (string, 绝对路径)
2. **`list_directory_with_sizes`**：列出目录内容并附带各文件物理字节大小。
3. **`directory_tree`**：以树状 JSON 结构递归获取目录层级。
4. **`create_directory`**：递归创建新目录（类似 `mkdir -p`）。
5. **`read_file`** / **`read_text_file`**：读取指定文本文件的完整内容。
6. **`read_media_file`**：以 Base64 或专用格式读取图像、音频等二进制媒体。
7. **`read_multiple_files`**：一次性批量读取多个文件，降低往返延迟。
   - 参数：`paths` (array of string)
8. **`write_file`**：写入新文件或覆盖现有文件内容。
9. **`edit_file`**：对文件执行基于精确匹配的字符串块增量替换。
10. **`move_file`**：移动或重命名文件/目录。
11. **`get_file_info`**：获取文件的创建时间、最后修改时间、读写权限与尺寸。
12. **`search_files`**：按通配符模式或文件名递归搜索文件。
13. **`list_allowed_directories`**：查看当前 MCP 授权访问的允许根目录清单。

---

## 三、Memory MCP (知识图谱与长程记忆 - 9 项)

Memory MCP 用于在多轮对话、跨任务甚至跨会话中沉淀业务架构知识、实体关系与项目规范。

### 核心工具与实体图谱操作：
1. **`create_entities`**：创建新的知识实体节点。
   - 参数示例：
     ```json
     {
       "entities": [
         {
           "name": "Roblox_Studio_MCP",
           "entityType": "ToolService",
           "observations": ["运行在 13469 端口", "Edit 模式禁止 require 业务代码"]
         }
       ]
     }
     ```
2. **`add_observations`**：向现有实体追加新的事实记录。
3. **`create_relations`**：在两个实体之间建立语义关系（如 `"uses"`, `"depends_on"`, `"implements"`）。
4. **`read_graph`**：读取整个知识图谱网络，用于全面上下文注入。
5. **`search_nodes`**：通过关键词对实体及其 observations 进行模糊检索。
6. **`open_nodes`**：通过实体名称获取该节点及其所有关联边。
7. **`delete_entities`** / **`delete_observations`** / **`delete_relations`**：清理过期或失效的记忆节点。
