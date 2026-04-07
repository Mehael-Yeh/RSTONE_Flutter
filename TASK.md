# RSTONE Flutter App - 开发任务

## 项目信息
- 项目路径: /vol1/@apphome/trim.openclaw/data/workspace/rst_flutter
- 中文名: 锐石
- 英文名: RSTONE
- 包名: com.rst.rst_flutter
- 版本: v0.0.1 alpha，预发行版

## 数据源
Obsidian数据库路径: /vol2/1000/Obsidian/锐石
- 产品列表MD文件: /vol2/1000/Obsidian/锐石/产品列表/*.md
- 产品应用MD文件: /vol2/1000/Obsidian/锐石/产品应用/*.md
- .base文件是Obsidian数据库配置文件(YAML格式)

数据读取: 在应用首次启动时，将数据从Obsidian源路径复制到应用私有目录(getApplicationDocumentsDirectory()或类似位置)。不要出现在download、document等公共文件夹。

## 数据结构示例

### 产品列表MD文件 (产品列表/RS7915v02.md):
```yaml
---
tags:
  - 水性
  - UV
  - 哑光
  - 面漆
  - 3C
  - 脂肪族
工程师: 王玉平
实验牌号: wp4313-02
固含: 45
---
properties:
  note.基材:
    displayName: 水煮
  note.tags:
    displayName: 基材
views:
  - type: table
    name: 表格
    filters:
      and:
        - file.folder == "产品列表"
    order:
      - file.name
      - tags
      - 底漆
      - 中漆
      - 面漆
      - 基材
    sort:
      - property: file.name
        direction: ASC
      - property: 基材
        direction: ASC
      - property: tags
        direction: DESC
    columnSize:
      file.name: 134
      note.tags: 136
      note.底漆: 124
      note.面漆: 124
```

### 产品应用MD文件 (产品应用/水性PU1涂银粉-1.md):
```yaml
---
tags:
  - PC
底漆: "[[RS8214-银]]"
中漆:
面漆:
基材:
---
properties:
  file.name:
    displayName: 牌号
views:
  - type: table
    name: 表格
    filters:
      and:
        - file.folder == "产品应用"
    order:
      - file.name
      - 实验牌号
      - 工程师
      - tags
      - 固含
      - 羟值
      - 水接触角
      - 技术源
      - 对标
    sort:
      - property: file.name
        direction: ASC
      - property: 实验牌号
        direction: ASC
```

## 三个页面

### 1. 搜索页（主界面）
- 居中圆角矩形搜索框
- 用户输入时，搜索框向上移动
- 搜索框下方以列表形式呈现即时搜索结果
- 支持关键词搜索和标签(tags)搜索
- 搜索范围: 产品列表 + 产品应用
- 搜索时显示结果数量

### 2. 产品列表页
- 模仿Obsidian数据库的列表/表格方式
- 支持用户自定义显示列的左右顺序(拖拽调整)
- 支持设置排序顺序
- 手机端默认只显示: 牌号(file.name) + 标签(tags)
- 点击产品从下往上弹窗显示MD文件内容(md阅读方式)
- 弹窗应包含关闭按钮

### 3. 产品应用页
- 模仿Obsidian数据库的列表/表格方式
- 支持用户自定义显示列的左右顺序(拖拽调整)
- 支持设置排序顺序
- 手机端默认只显示: 名称、基材、底漆、中漆、面漆
- 点击产品从下往上弹窗显示MD文件内容(md阅读方式)
- 弹窗应包含关闭按钮

## 技术要求
1. Flutter多平台: Android, Windows, iOS
2. 数据存储在应用私有目录
3. MD文件解析和渲染(使用flutter_markdown或类似包)
4. 底部弹窗(从下往上滑出)
5. 列表拖拽排序
6. 列顺序自定义
7. 搜索功能(实时搜索)
8. 版本号: v0.0.1 alpha，预发行版

## GitHub集成
1. 创建GitHub仓库(如果不存在)
2. 提交所有代码
3. 创建Tag: v0.0.1-alpha
4. 创建GitHub Release
5. 签名要求: 保持一致(无签名或统一签名)
6. 编写README.md

## 开发步骤
1. 分析Obsidian数据结构
2. 设计Flutter数据模型
3. 实现MD文件解析服务
4. 实现三个页面
5. 实现底部弹窗
6. 实现搜索功能
7. 实现列排序和拖拽
8. 测试并打包

完成后请构建debug APK用于测试。
