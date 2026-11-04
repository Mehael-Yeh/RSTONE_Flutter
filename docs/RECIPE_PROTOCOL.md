# 统一配方读取协议

客户端按父冻结 `rstone-recipe/1` / `rstone-recipe-markdown/1` 消费：10 个封闭键、ASCII canonical JSON 单行 frontmatter、完整实体化正文。冻结合同 SHA-256：`a20d8a187fcc329d8407e5668ff35562380335f32c947a000be7c8476fcd0e7a`。这不是数据或发布审批。

## 数据边界

- `FormulaDocument` 保存不可变原事实；`FormulaProtocolCodec` 独立于 Flutter，严格检查 Unicode scalar、UTF-16 字符串上限、数组、深度、header/file caps、唯一 JSON 键及完整字节一致性。
- 有新标记而模型未知、坏掉、CRLF/BOM 或正文不一致时拒绝，不能改走 legacy。错误只含类别，不回显配方 JSON 或格值。
- Manifest 允许 schema 1/2，wire protocolVersion 仍为 1。schema 2 的 `minAppVersion` 至少为 2.0.2，必须全配方 structured。完整 catalog 关联/稳定 ID/标题/最长完整 owner/闭合用途尾缀及主方真实正投量，均在 commitActive 之前核验。主方的十进制比较不使用浮点数，也不代表批准。
- 所有 classification 的每一行投入数都必须可解释：十进制数值或低位不高于高位的区间，或封闭的未知量措辞（适量／少量／若干／另加／按当量另加／开稀至可喷粘度／按NCO/OH=…另加／适量（NCO/OH=…））。负数、倒置区间、任意文本在目录门即拒。`example/reference/unverified` 不要求正投量 owner，只表示资料可读，不贡献身份信用；`main` 仍必须有真实正投量 owner。该口径与 Python 发布器目录门一致。
- Web 的 32 项分批只做局部解析，完整合并后才校验引用。旧 schema 1 签名代和旧个人文件只读兼容；原产品物性、性能、TDS 与旧实验别名/完整后缀守卫未替换。

## 展示与个人层

- 新配方详情（产品、应用、直接配方入口）、PNG 和复制共用 `FormulaDisplayView` 的原始五列。**有意原样显示 `[[wiki|alias]]`**，本次不引入链接化投影。没有 derivedMarkdown → parseTable 链。
- UI 五列可横向滚动，行高按原格换行测量；PNG 使用同一五列几何，按 preTable、表格、content 原序完整绘制，不截图当前滚动视口。图片超过单边 32768 像素或总计 6400 万像素时显式拒绝，不裁行/截列。
- 复制输出带引号的 TSV，包含空尾格、TAB/LF、空格、竖线、零、范围和另加原文。输入支持五列 TSV/Markdown；不补缺列、不截多列、不强制 double。TSV 的业务空格不 trim；Markdown 仅移除至多一个格式填充空格。输入行结束符统一为 LF。
- 新建个人配方通过结构化表单保存同一 codec；独立稳定 ID 在创建时生成一次。前置说明和有序 note/process 可显式输入 JSON。旧 Markdown 只保留读取，新保存不提供 legacy 绕过。
- 坏个人文件保原件并隔离，不能阻挡官方初始化，不能静默露出同路径的官方版本；页面显示隔离通知与详情。个人 ZIP 包含隔离原件。仅明确的“清除所有个人资料”操作才删除隔离原件。
- 没有新增配方 PDF/CSV/XLSX 功能；现有 PDF 是 TDS PDF，未改。

## 可重复测试

使用已配置依赖，无需 `pub get` 或改锁：

```sh
dart --packages=.dart_tool/package_config.json test/formula_protocol_probe.dart
dart --packages=.dart_tool/package_config.json test/formula_caps_probe.dart
flutter test --no-pub --concurrency=1
flutter analyze --no-pub
```

公共 fixture 全为合成数据：共享 48 golden（6 shape 接受）及边界探针，不含真实配方。`test/widget_test.dart` 中原四列剪贴板 fixture 原文保留，改作明确拒绝的协议断代回归；另外有五列、空尾格、多行和不可截列的测试。其余原测试不删除、不新增 skip。

## 验证限制

本次离线兼容栈为既有 Dart 3.8.1 / Flutter 3.32.8；本地包解析与生产 lock 的版本并不全相同，不能冒称锁定生产 CI 验收。真实 catalog/缓存旧17的私有服务与 Widget 重放不属于公开测试 fixture，也不表示当前线上状态或迁移已批准。系统剪贴板后端、系统分享面板、真机、真实浏览器 IndexedDB、Windows、Android/iOS 安装包升级仍需目标平台验收。
