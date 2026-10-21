# 锐石 RSTONE（Flutter）

<div align="center">

![Flutter](https://img.shields.io/badge/Flutter-3.32.8-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.8-0175C2?logo=dart&logoColor=white)
![Platforms](https://img.shields.io/badge/Platforms-Android%20%7C%20iOS%20%7C%20Windows%20%7C%20Web-6C63FF)

**锐石内部产品资料检索应用**  
搜索管理产品、应用场景、配方信息，并支持现场笔记记录与导出。

📱 **Android 2.0.1 正式版下载**：[Full / Lite 安装包](https://github.com/Mehael-Yeh/RSTONE_Flutter/releases/tag/v2.0.1)，支持 Android 10 及以上，可覆盖安装旧版。

🌐 **静态网页（GitHub Pages）**：  
https://Mehael-Yeh.github.io/RSTONE_Flutter/

</div>

---

## 项目概述

RSTONE 是一个基于 Flutter 的跨平台检索工具，用于集中管理和查询分散的产品资料（Markdown/JSON）。
核心目标：

- 一个入口完成产品以及应用的搜索与浏览
- 统一展示产品信息、应用场景等产品资料
- 支持标签同义词提升搜索增强（如 `PA6 -> 尼龙`）
- 支持业务笔记记录与导出
- 固定应用外壳：官方资料按签名清单同步，只下载缺失对象，支持删除、离线检索与失败恢复
- 个人 Markdown、笔记和偏好独立保存，官方同步不会覆盖个人资料

本次重构的分阶段改动、测试、生产配置和证据边界见 [数据同步交付记录](docs/DATA_SYNC_REFACTOR.md)。
`assets/data_sync_config.json` 已固定正式 Pages/备用 raw 源及 production-2026 公钥。
新外壳版本为 2.0.1，支持 Android 10 及以上系统；保留旧应用标识、签名及个人资料存储。
真实首版资料 187 份，重复同步不下载已有对象。示例公钥仅用于测试。
首次下载并发提速；设置页合并版本与更新入口，点击下载源直接切换，更新后自动校验并仅提示一次结果。
后续发包在构建、签名和上传完成后直接发布；不再自动运行测试、静态检查或模拟器安装验证，测试入口保留为手动触发。

---

## 平台与技术栈

### 支持平台

- Android 10 及以上
- iOS
- Windows
- Web

### 技术栈

- **Flutter 3.24+ / Dart 3.5+**
- **UI**：Material 3
- **关键依赖**：
  - `flutter_markdown`（Markdown 渲染）
  - `shared_preferences`（偏好与笔记存储）
  - `reorderables`（列拖拽排序）
  - `share_plus`（导出与分享）
  - `package_info_plus`（版本信息）
  - `path_provider`（本地目录读写）

---

## 目录结构

```text
lib/
├── main.dart
├── models/
│   └── product_item.dart
├── pages/
│   ├── search_page.dart
│   ├── product_list_page.dart
│   ├── product_applications_page.dart
│   └── settings_page.dart
├── services/
│   ├── obsidian_data_service.dart
│   ├── preferences_service.dart
│   └── tds_pdf_service.dart
└── widgets/
    ├── obsidian_table.dart
    ├── product_detail_sheet.dart
    └── product_detail/
```

---

## 本地开发

### 环境要求

- Flutter SDK `>= 3.24.0`
- Dart SDK `>= 3.5.0`

### 快速启动

```bash
flutter pub get
flutter run
```

### Web 调试

```bash
flutter run -d chrome
```

Web 离线外壳构建（应用版本请与 pubspec.yaml 保持一致）：

```bash
flutter build web --release --no-web-resources-cdn --dart-define=APP_VERSION=2.0.1
python scripts/prepare_web_offline.py
```

完成首次在线缓存后可断网刷新。外壳缓存仅包含程序资源，官方资料仍由签名清单和 IndexedDB 管理。

### 构建 APK

```bash
flutter build apk --debug --flavor full --dart-define=RSTONE_LITE=false
flutter build apk --release --split-per-abi --flavor full --dart-define=RSTONE_LITE=false
flutter build apk --release --split-per-abi --flavor lite --dart-define=RSTONE_LITE=true
```

---

## 许可与用途

本项目为**锐石内部私有项目**，仅限内部业务使用；未经授权不得对外分发、商用或二次发布。
