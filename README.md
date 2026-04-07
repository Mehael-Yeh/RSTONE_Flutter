# 锐石 RSTONE

一款基于 Flutter 开发的多平台应用，用于浏览和管理锐石产品数据库。

## 📱 支持平台

- Android
- iOS
- Windows

## ✨ 功能特点

### 搜索页面（主界面）
- 居中圆角矩形搜索框
- 实时搜索，搜索时搜索框上移
- 支持关键词和标签(Tags)搜索
- 搜索范围覆盖产品列表和产品应用

### 产品列表页面
- Obsidian 风格的列表展示
- 支持自定义显示列的左右顺序
- 支持设置排序方式
- 手机端默认显示：牌号、标签

### 产品应用页面
- Obsidian 风格的列表展示
- 支持自定义显示列的左右顺序
- 支持设置排序方式
- 手机端默认显示：名称、基材、底漆、中漆、面漆

### 产品详情
- 点击产品从下往上弹窗显示
- Markdown 格式渲染，展示完整产品信息

## 🛠 技术栈

- Flutter 3.24.0
- Dart 3.5.0
- flutter_markdown - Markdown 渲染
- shared_preferences - 本地偏好设置存储
- reorderables - 列拖拽排序

## 📦 数据存储

应用数据存储在应用私有目录下，卸载后自动清除：
- Android: `data/data/com.rst.rst_flutter/`
- iOS: 应用沙盒 Documents 目录
- Windows: `%APPDATA%/RSTONE_Flutter/`

数据源来自 Obsidian 数据库文件夹 `/vol2/1000/Obsidian/锐石`

## 🔧 构建说明

### 环境要求
- Flutter SDK 3.24.0+
- Android SDK 34+
- JDK 17+

### 构建 Debug APK
```bash
flutter pub get
flutter build apk --debug
```

构建产物位于: `build/app/outputs/flutter-apk/app-debug.apk`

### 构建 Release APK
```bash
flutter build apk --release
```

## 🔄 版本历史

### v0.0.1-alpha (预发行版)
- 初始版本
- 三个核心页面：搜索、产品列表、产品应用
- Obsidian 风格的表格展示
- 列自定义排序和拖拽重排
- 底部弹窗显示产品详情
- Markdown 内容渲染

## 📋 后续计划

- [ ] 迭代至 v0.1.0 正式版
- [ ] 添加更多筛选功能
- [ ] 优化移动端体验
- [ ] 添加收藏/笔记功能

## ⚙️ 配置说明

首次启动时，应用会自动从 Obsidian 数据源复制数据到应用私有目录。数据包含：
- 产品列表 MD 文件
- 产品应用 MD 文件

## 📄 许可证

私有项目，仅供内部使用。

---

**版本**: v0.0.1-alpha  
**预发行版**: ✔️
