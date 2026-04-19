# 锐石 RSTONE（Flutter）

锐石内部使用的产品资料检索 App，基于 Flutter 开发，支持 **搜索、列表浏览、应用场景查看、TDS/配方详情查看、标签同义词规则维护、产品笔记记录与导出**。

> 🌐 **Web 访问地址（GitHub Pages）**：
> `https://<你的 GitHub 用户名或组织名>.github.io/RSTONE_Flutter/`
>
> 例如：`https://my-org.github.io/RSTONE_Flutter/`

---

## 1. 项目定位

RSTONE 用于把分散的 Obsidian Markdown 数据（产品列表 / 产品应用 / 产品配方 / TDS）统一打包到移动端与桌面端，提供更高效的检索与现场提报能力。

核心目标：
- 在一个入口检索产品与应用信息。
- 统一展示 Markdown 内容与配方表。
- 支持业务同事在现场记录产品笔记并导出。
- 支持标签同义词规则（如 `PA6 -> 尼龙`）提升搜索召回。

---

## 2. 平台与技术栈

### 支持平台
- Android
- iOS
- Windows
- Web（可通过 GitHub Pages 发布）

### 主要技术
- Flutter 3.24（Material 3）
- Dart 3.5
- `flutter_markdown`：Markdown 渲染
- `shared_preferences`：本地偏好与笔记存储
- `reorderables`：列拖拽重排
- `share_plus`：导出分享
- `package_info_plus`：版本信息
- `path_provider`：应用目录读写

---

## 3. 功能总览

### 3.1 搜索页（首页）
- 搜索产品与应用（统一入口）
- 支持关键词 + 标签搜索
- 搜索结果点击可打开详情抽屉
- 支持对单条结果快速记录笔记（侧滑入口）

### 3.2 产品列表页
- 表格化展示产品数据
- 移动端/桌面端默认列不同
- 支持列拖拽重排
- 支持按列排序（A-Z / Z-A）

### 3.3 产品应用页
- 与产品列表页一致的交互能力
- 默认字段聚焦“基材、底漆、中漆、面漆”等应用维度

### 3.4 产品详情
- 底部弹出详情面板
- 支持 Markdown 内容渲染
- 支持产品配方表解析展示
- 支持 TDS 内容按产品名匹配读取（含归一化匹配策略）

### 3.5 设置页
- 主题模式（系统/浅色/深色）
- 主题色切换（预设 + 自定义 HEX）
- 数据统计（产品数、应用数、TDS 覆盖率）
- 标签同义词规则查看/编辑
- 日志查看、复制、清空
- 产品笔记导出（Markdown）与一键清空
- 版本信息展示

---

## 4. 数据来源与加载机制

### 4.1 资源结构
应用打包以下资源：
- `assets/产品列表/` + `assets/产品列表.json`
- `assets/产品应用/` + `assets/产品应用.json`
- `assets/产品配方/` + `assets/产品配方.json`
- `assets/产品TDS/` + `assets/产品TDS.json`
- `assets/tag_alias_rules.txt`

### 4.2 初始化流程（DataService）
1. 优先从 assets 索引 + Markdown 文件加载。
2. 若 assets 异常且数据为空，尝试从应用私有目录读取。
3. 成功加载后将资源复制到私有目录，供后续规则编辑等场景使用。

### 4.3 标签同义词规则
- 默认内置：`assets/tag_alias_rules.txt`
- 用户可在设置页编辑并保存到私有目录，后续优先读取私有版本。

---

## 5. 本地持久化（Preferences）

通过 `shared_preferences` 保存：
- 产品列表列配置与排序
- 产品应用列配置与排序
- 主题模式与主题色
- 产品笔记（JSON Map）

> 注：卸载应用后，以上本地数据会被系统清除。

---

## 6. 目录结构（核心）

```text
lib/
├── main.dart                              # 入口、主题、底部导航
├── models/
│   └── product_item.dart                  # 产品/应用实体与 Markdown 解析
├── pages/
│   ├── search_page.dart                   # 搜索页
│   ├── product_list_page.dart             # 产品列表页
│   ├── product_applications_page.dart     # 产品应用页
│   └── settings_page.dart                 # 设置页
├── services/
│   ├── obsidian_data_service.dart         # 数据加载/搜索/日志/规则
│   ├── preferences_service.dart           # 用户偏好与笔记
│   └── tds_pdf_service.dart               # TDS 导出相关
└── widgets/
    ├── obsidian_table.dart                # 表格主组件
    ├── product_detail_sheet.dart          # 详情抽屉
    └── product_detail/                    # 配方/Markdown 解析子模块
```

---

## 7. 本地开发

### 环境要求
- Flutter SDK >= 3.24.0
- Dart SDK >= 3.5.0
- Android SDK（如需构建 Android）
- Xcode（如需构建 iOS）

### 常用命令
```bash
flutter pub get
flutter run

# 运行 Web
flutter run -d chrome
```

### 构建 APK
```bash
# Debug
flutter build apk --debug

# Release
flutter build apk --release --split-per-abi
```

---

## 8. CI/CD（GitHub Actions）

### 8.1 Alpha 流程（`release_alpha.yml`）
- 触发：`push main` 或手动触发
- 自动递增 Alpha 标签：`vX.Y.Z-alpha`
- 写回 `pubspec.yaml` 版本
- 构建并上传多 ABI APK 到 GitHub Release（pre-release）

### 8.2 正式版流程（`release_production.yml`）
- 触发：仅手动触发
- 版本从 `v1.0.0` 起步并递增补丁号
- 构建并上传多 ABI APK 到正式 Release

### 8.3 Web + GitHub Pages（`deploy_web_pages.yml`）
- 触发：`push main` 或手动触发
- 产物：`flutter build web --release` 后自动发布到 GitHub Pages
- 路由基路径：自动使用 `/<仓库名>/`，适配 Project Pages
- 若仓库暂未提交 `web/` 目录，工作流会自动读取 `pubspec.yaml` 的 `name` 并执行 `flutter create --platforms=web --project-name <name> .`，避免仓库名含大写时创建失败
- Web 工作流会对齐 APK 流程：若配置 `PRIVATE_REPO_READ_TOKEN`，会拉取 `Rstone` 与 `RstoneTDS` 私有仓库刷新资产；未配置时会生成空 JSON 索引（`[]`，与当前 `产品TDS.json` 一致）以保证构建不报错

#### 启用步骤
1. 进入 GitHub 仓库 `Settings -> Pages`
2. `Build and deployment` 选择 `Source: GitHub Actions`
3. 合并本仓库中的 `deploy_web_pages.yml` 到 `main`
4. 推送后等待 Action 完成，访问：
   - `https://<你的 GitHub 用户名>.github.io/<仓库名>/`

> 如果你的仓库是组织仓库，请将用户名替换为组织名。

### 8.4 版本展示格式
发布界面中会展示带日期的版本文案，例如：
- `v0.0.149 (20260418)`
- `v1.0.0 (20260418)`

> 其中日期为构建当天（UTC）`YYYYMMDD`。
> 同时该日期会写入应用构建号（`pubspec.yaml` 的 `+build`），因此 App 内「设置-版本」也会显示为 `vX.Y.Z (YYYYMMDD)`。

---

## 9. 许可与用途

本项目为锐石内部私有项目，仅限内部业务使用。
