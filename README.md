# 锐石 RSTONE

一款基于 Flutter 开发的多平台应用，用于浏览和管理锐石（RSTONE）产品数据库。采用 Obsidian 风格的深色主题界面，支持产品搜索、列表展示、详情查看等功能。

## 📱 支持平台

- ✅ Android
- ✅ iOS
- ✅ Windows

## ✨ 功能特点

### 搜索页面（主界面）
- 居中圆角矩形搜索框，交互动画效果
- 实时搜索，搜索时搜索框上移并缩小
- 支持关键词和产品标签（Tags）搜索
- 搜索范围覆盖产品列表和产品应用两大类数据

### 产品列表页面
- Obsidian 风格的表格/列表展示
- 支持自定义显示列的左右拖拽排序
- 支持升序/降序排序
- 手机端默认显示：牌号、标签
- 桌面端默认显示：牌号、标签、实验牌号、工程师、固含、羟值、水接触角、技术源、对标、粘度

### 产品应用页面
- 与产品列表类似的 Obsidian 风格展示
- 支持自定义列排序和拖拽重排
- 手机端默认显示：名称、基材、底漆、中漆、面漆
- 桌面端默认显示：名称、基材、底漆、中漆、面漆、标签

### 产品详情弹窗
- 从下往上滑出的半屏弹窗
- 支持向上拖拽展开、向下滑动收起
- Markdown 内容渲染
- 产品配方表格展示（Canvas 绘制，支持分享为图片）
- 配方信息结构化展示（底漆、中漆、面漆、基材）

### 设置页面
- 数据统计（产品数量、应用数量、初始化状态）
- 日志查看、复制、清除
- 重新加载数据功能
- 版本信息

## 🗂 数据结构

应用数据来自 Obsidian 数据库，分三类：

| 类型 | 说明 |
|------|------|
| **产品列表** | 存储产品基础信息（牌号、实验牌号、工程师等） |
| **产品应用** | 存储产品应用信息（基材、底漆、中漆、面漆等） |
| **产品配方** | 存储产品配方表（Markdown 表格格式） |

数据通过 AssetBundle 内置在应用中，启动时自动加载。

## 🛠 技术栈

| 技术 | 用途 |
|------|------|
| Flutter 3.24 | 跨平台 UI 框架 |
| Dart 3.5 | 编程语言 |
| flutter_markdown | Markdown 内容渲染 |
| shared_preferences | 本地用户偏好设置持久化 |
| reorderables | 列拖拽排序组件 |
| share_plus | 分享功能 |
| path_provider | 文件路径访问 |

## 📦 项目结构

```
lib/
├── main.dart                      # 应用入口、根组件、底部导航
├── models/
│   └── product_item.dart         # 产品/应用数据模型
├── pages/
│   ├── search_page.dart           # 搜索页面（首页）
│   ├── product_list_page.dart     # 产品列表页面
│   ├── product_applications_page.dart  # 产品应用页面
│   └── settings_page.dart         # 设置页面（含日志查看）
├── services/
│   ├── obsidian_data_service.dart # Obsidian 数据加载与管理
│   └── preferences_service.dart   # 用户偏好设置持久化
└── widgets/
    ├── obsidian_table.dart        # Obsidian 风格表格组件
    └── product_detail_sheet.dart  # 产品详情弹窗组件
```

## 🔧 构建说明

### 环境要求

- Flutter SDK 3.24.0+
- Android SDK 34+
- JDK 17+

### 构建 Debug APK

```bash
cd RSTONE_Flutter
flutter pub get
flutter build apk --debug
```

构建产物位于: `build/app/outputs/flutter-apk/app-debug.apk`

### 构建 Release APK

```bash
flutter build apk --release
```

### 热重载开发

```bash
flutter run
```

## 🎨 界面主题

| 元素 | 颜色 |
|------|------|
| 背景色 | `#1A1A1A` |
| 卡片/表面 | `#2D2D2D` |
| 主色调 | 橙色 `#FF9800` |
| 文字色 | 白色/灰白色 |
| 产品列表标签 | 蓝色 |
| 产品应用标签 | 绿色 |

## 📄 许可证

私有项目，仅供锐石内部使用。

---

**版本**: v0.0.28-alpha  
**最后更新**: 2026-04-08
