# RSTONE_Flutter 仓库分析与拆解建议

## 1. 仓库结构总览

- `lib/`：核心业务代码（页面、组件、服务、模型）。
- `assets/`：字体、图标、产品数据源 JSON。
- `android/` `ios/` `windows/`：多端平台工程与启动配置。
- `test/`：Flutter 组件测试。
- `scripts/`：构建辅助脚本。

## 2. 组件职责梳理（按目录）

### `lib/services`
- `obsidian_data_service.dart`：数据加载、索引、标签同义词扩展、搜索策略和日志收集。
- `tds_pdf_service.dart`：TDS 文本解析、段落/表格结构化、PDF 导出与分享前文件落地。
- `preferences_service.dart`：本地偏好、收藏和笔记存储读写。

### `lib/pages`
- `product_list_page.dart`：产品主列表与过滤入口。
- `product_applications_page.dart`：应用场景/配方的分类展示页。
- `search_page.dart`：统一搜索页，支持关键字与标签匹配。
- `settings_page.dart`：主题、同步、导入导出、日志/关于入口。
- `about_detail_page.dart`：从设置页拆出，专注版本展示和更新检查。
- `log_viewer_page.dart`：从设置页拆出，专注日志浏览与复制。

### `lib/widgets`
- `product_detail_sheet.dart`：产品详情底部弹层，承载 Markdown 与 PDF 预览等重 UI 逻辑。
- `obsidian_table.dart`：复杂表格渲染（多级表头/布局计算）。
- `note_swipe_tile.dart` / `swipe_note_item_card.dart`：笔记条目及滑动行为。
- `compact_token_row.dart`：紧凑型标签展示。
- `product_detail/*`：详情页内的 Markdown 表格/公式解析工具。

### 其他
- `lib/models/product_item.dart`：产品数据模型与字段映射。
- `lib/main.dart`：应用入口、路由与服务初始化。
- `scripts/generate_build_date.py`：构建时间注入脚本。

## 3. 超 500 行文件拆解情况与后续建议

### 已完成拆解
1. `settings_page.dart`
   - 已把“关于页”与“日志页”拆到独立文件：
     - `about_detail_page.dart`
     - `log_viewer_page.dart`
   - 好处：设置页职责更聚焦，后续可单独迭代更新检查与日志展示。

### 建议继续拆解（下一步）
1. `product_detail_sheet.dart`（> 1300 行）
   - 建议拆为：
     - PDF 预览控制器/状态管理
     - 配方选择与表格区域 widget
     - Markdown 信息区 widget
2. `obsidian_data_service.dart`（> 700 行）
   - 建议拆为：
     - 标签同义词规则模块
     - 搜索分词/匹配策略模块
     - 数据源加载与缓存模块
3. `tds_pdf_service.dart`（> 600 行）
   - 建议拆为：
     - Markdown -> 中间结构解析器
     - PDF 样式与组件工厂
     - 文件输出与分享模块
4. `obsidian_table.dart`（> 500 行）
   - 建议拆为：
     - 表格数据预处理
     - 布局计算器
     - 绘制层（Painter）

## 4. 复用提升建议

1. 复用“分组卡片 Section Card”样式
   - 可提取到通用组件，减少设置页/关于页重复布局。
2. 复用 URL 打开与失败提示逻辑
   - 目前散落在页面内，可统一到 `utils/launcher_utils.dart`。
3. 复用“版本比较/解析”逻辑
   - 从关于页抽出后可用于启动页的静默更新提示。
4. 复用“文本规范化”函数
   - `obsidian_data_service` 与 `tds_pdf_service` 都存在文本清洗，建议统一到 `text_normalizer.dart`。

## 5. 注释补充原则（本次已执行）

- 为核心 Dart 代码文件补充了文件级说明注释，明确职责与边界。
- 新拆分页面文件均附加页面级注释，保证后续维护可读性。
