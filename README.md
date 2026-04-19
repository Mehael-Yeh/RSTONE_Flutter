# 锐石 RSTONE（Flutter）

<div align="center">

![Flutter](https://img.shields.io/badge/Flutter-3.24+-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.5+-0175C2?logo=dart&logoColor=white)
![Platforms](https://img.shields.io/badge/Platforms-Android%20%7C%20iOS%20%7C%20Windows%20%7C%20Web-6C63FF)

**锐石内部产品资料检索应用**  
统一查看产品、应用场景、配方与 TDS，并支持现场笔记记录与导出。

🌐 **静态网页（GitHub Pages）**：  
https://Mehael-Yeh.github.io/RSTONE_Flutter/

</div>

---

## 项目概述

RSTONE 是一个基于 Flutter 的跨平台检索工具，用于集中管理和查询分散的产品资料（Markdown/JSON）。
核心目标：

- 一个入口完成搜索与浏览
- 统一展示产品信息、应用场景、配方和 TDS
- 支持标签同义词提升搜索召回（如 `PA6 -> 尼龙`）
- 支持业务笔记记录与导出

---

## 平台与技术栈

### 支持平台

- Android
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

### 构建 APK

```bash
flutter build apk --debug
flutter build apk --release --split-per-abi
```

---

## 数据与配置说明

- 业务数据主要来源于 `assets/` 下的产品列表、应用、配方、TDS 与标签规则文件。
- 用户偏好（主题、列表配置）与笔记通过 `shared_preferences` 本地保存。
- 应用卸载后，本地偏好和笔记会被系统清除。

---

## 许可与用途

本项目为**锐石内部私有项目**，仅限内部业务使用；未经授权不得对外分发、商用或二次发布。
