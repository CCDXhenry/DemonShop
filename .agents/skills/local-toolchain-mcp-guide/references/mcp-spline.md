# Spline 2D/3D MCP 工具手册 (Spline MCP Reference)

Spline MCP 提供了 AI Agent 与 Spline 3D 设计工具进行无头通信、画布排版、3D 场景控制、资产导出及代码交互的完整能力。
本机配置的 Spline MCP 涵盖 **23 个 2D 工具** 与 **22 个 3D 工具**，共计 45 项原子操作。

---

## 一、服务配置与运行环境

- **配置文件**：`C:\Users\herong\.gemini\config\mcp_config.json` 与 `C:\Users\herong\.gemini\antigravity\mcp_config.json`
- **运行配置**：
  ```json
  "Spline": {
    "command": "C:\\Users\\herong\\AppData\\Local\\Programs\\Spline\\Spline.exe",
    "args": [
      "C:\\Users\\herong\\AppData\\Local\\Programs\\Spline\\resources\\spline-mcp.cjs"
    ],
    "env": {
      "ELECTRON_RUN_AS_NODE": "1"
    }
  }
  ```

---

## 二、Spline 2D 工具集 (23 项)

2D 工具集专注于 UI 画板、矢量组件、图层排版、素材生成及 HTML 导出。

### 1. 2D 文件与画板管理
- **`2d_create_file`**：在 Spline 中新建一个 2D 设计文件。
  - 参数：`name` (string, 可选)
- **`2d_load_skill`**：加载 Spline 2D 相关的排版设计能力规范。
- **`2d_reserve_frames`**：在画板上预留并规划多个 Frame 区域，防止图层重叠。
- **`2d_resize_frame`**：调整指定 Frame 的宽高尺寸。
- **`2d_find_space`**：在当前画布寻找空白未占用的物理空间，用于放置新元素。
- **`2d_get_canvas_state`**：获取整个 2D 画布的缩放、视区中心及全局状态。
- **`2d_review_frame`**：对指定的 Frame 进行视觉或布局核验。

### 2. 2D 场景对象与图层操作
- **`2d_get_scene`**：获取当前 2D 场景的完整层级树与元素列表。
- **`2d_update_scene`**：全局更新场景属性（背景色、全局网格等）。
- **`2d_get_object`**：获取指定 2D 对象的详细属性（位置、旋转、尺寸、样式）。
- **`2d_add_objects`**：向画布批量添加新对象（矩形、文本、圆形、图层组等）。
- **`2d_update_objects`**：更新现有对象的样式、填充色、描边或层级。
- **`2d_move_objects`**：平移一个或多个对象至新坐标。
- **`2d_duplicate_objects`**：克隆选中的对象。
- **`2d_delete_objects`**：从场景中移除指定对象。
- **`2d_recolor`**：批量或针对性修改图层调色板与配色方案。

### 3. 2D 图像与 HTML 导出
- **`2d_generate_images`**：通过 AI 提示词生成 2D 纹理或插画资产。
- **`2d_edit_image`**：对现有图像进行局部重绘、修饰或滤镜调整。
- **`2d_upload_assets`**：将本地图片或矢量资产上传导入当前画布。
- **`2d_write_html`**：将设计直接转写为静态 HTML/CSS 代码。
- **`2d_export_html`**：导出可交互的 2D Web 前端静态页面。

### 4. 2D 版本管理
- **`2d_list_versions`**：查询该 2D 文件的历史保存快照列表。
- **`2d_restore_version`**：将画布回退至指定历史版本快照。

---

## 三、Spline 3D 工具集 (22 项)

3D 工具集专注于 3D 几何建模、材质设置、相机视角、交互动画及无头代码执行。

### 1. 3D 文件与环境管理
- **`3d_create_file`**：在 Spline 中新建一个 3D 场景文件。
- **`3d_load_skill`**：加载 Spline 3D 核心建模技巧与最佳实践。
- **`3d_set_view`**：调整 3D 视口相机视角（正交、透视、顶视、前视、侧视等）。
- **`3d_take_screenshot`**：从当前或指定相机视角捕获高质量渲染快照。

### 2. 3D 场景分析与对象管理
- **`3d_get_scene`** / **`3d_get_scene_mcp`**：获取 3D 场景图（Scene Graph），包含网格、灯光、材质节点。
- **`3d_get_objects`**：查询特定 3D 网格对象的顶点数、材质属性与变换矩阵。
- **`3d_analyze_scene`**：对 3D 场景进行综合拓扑与性能分析（面数预算、灯光数量、物理碰撞体等）。

### 3. 3D 代码运行与程序化建模
- **`3d_run_code`**：在 Spline 3D 引擎运行时中执行自定义 JavaScript 代码，用于程序化生成复杂形变或逻辑动画。
- **`3d_generate_3d_model`**：基于自然语言提示词生成 3D 基础几何体或低面数模型。
- **`3d_generate_image`**：生成 3D 场景所需的纹理贴图或环境 HDR。
- **`3d_get_generation`**：轮询异步 3D 模型或贴图生成任务的状态。

### 4. 3D 网页嵌入与导出
- **`3d_set_html_content`** / **`3d_edit_html_content`** / **`3d_get_html_content`**：操作嵌入式 3D HTML 包装容器与运行时交互界面。
- **`3d_publish_export`**：发布并导出 3D 场景（支持 Spline Code、Web Component、glTF / GLB 等格式）。

### 5. 3D 评审批注与版本回溯
- **`3d_get_comments`** / **`3d_reply_to_comment`** / **`3d_resolve_comment`**：针对 3D 场景特定几何锚点的团队评审与批注管理。
- **`3d_list_versions`** / **`3d_restore_version`**：3D 场景历史快照列表与版本恢复。

---

## 四、典型应用场景与工作流

### 1. 快速导出轻量级 3D 网页预览
1. 调用 `3d_create_file` 或 `3d_get_scene` 准备模型；
2. 调用 `3d_set_view` 调整最佳展示视角；
3. 调用 `3d_take_screenshot` 导出渲染图进行视觉核验；
4. 调用 `3d_publish_export` 获取可独立加载的 3D 资产或 GLB 文件。
