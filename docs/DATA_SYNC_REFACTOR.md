# 固定应用外壳与文件增量同步交付记录

日期：2026-10-21。修改基线：`06567fb`。本记录覆盖该基线之后的重构和首次发包流程，发布状态以 GitHub Release 为准。

## 协议依据与上线边界

唯一线上契约是 [RSTONE_Data/docs/DATA_PROTOCOL.md](https://github.com/Mehael-Yeh/RSTONE_Data/blob/main/docs/DATA_PROTOCOL.md)。
客户端校验器和完整 Unicode case-fold 表来自发布端提交
`07e489195ce77acdb0aecabaf5a6ea646ae085f6` 的 `examples/flutter_protocol/lib/`，仅作代码格式调整。
`test/fixtures/protocol_v1.json` 保存同一提交的 Python 签名原始字节和模拟对象；其中的 example-only 公钥只用于测试。

协议保持六位补零 sequence、原始字节 SHA-256、纯 Ed25519、Base64 独立签名、完整清单、
NFC 路径及完整 Unicode 大小写冲突检查。只按 sequence 排序，dataVersion 仅展示。
未知密钥、重复 JSON 字段、非法路径、不兼容 schema/minAppVersion、回放和同序号不同哈希均拒绝。
首次安装无法识别持续提供旧有效签名的 freeze attack。

生产信任根已从发布端提交 `c33fa9955f95c2e2aa5242d126f691238a74658c` 的
`config/trusted_keys.json` 固定到 `assets/data_sync_config.json`：keyId 为 `production-2026`。
公钥文件 Git blob 为 `74ed404bb89c54c75d2a90d6b2b72fc6cbcd4140`；客户端不在运行时下载或自动信任公钥。
正式 Pages 与 raw 备用源均已逐对象联调。二者同属 GitHub，不能视为独立服务商容灾。
外壳实际版本提升为 `1.0.0`，与签名清单 `minAppVersion=1.0.0` 对齐，不绕过兼容校验。
Alpha/Production 版本计算同时以 pubspec 为下限，避免旧 0.x 标签使下一版低于新协议要求。

## 已实现的存储与事务

原生平台使用应用 Support 私有目录 `rst_data/`，旧版 Documents 目录只作为迁移输入。

```text
rst_data/
  official/objects/<sha256>    不可变内容对象
  official/state.db            SQLite 事务中的完整版本指针与已签名清单
  user/产品列表/*.md            独立个人资料
  user/产品应用/*.md
  user/产品配方/*.md
  user/custom_rules/...
```

Web 使用真实 IndexedDB，存储语义与原生一致；持久化不可用时报告错误，不静默降级到内存。
用户笔记、主题、列顺序及排序仍使用原 SharedPreferences 键。

1. 从配置的多个 HTTPS 源获取 latest，验证原始清单、签名、版本和绑定字段。
2. 比较完整旧/新映射，输出 ADD、MODIFY、DELETE、UNCHANGED、REPAIR；按唯一哈希去重下载。
3. 只下载缺失或损坏的对象；任一镜像失败时，从其他镜像取同一目标哈希。
4. 原生对象先写临时文件并 flush，再更名；校验写回内容。Web 对象和变更指纹同事务写入。
5. 校验所有引用对象并预构建完整产品、应用、配方、TDS 和规则快照。
6. 用 SQLite/IndexedDB 单事务比较并切换 active、完整签名清单、最高 sequence/hash 和上一个版本。
7. 同步替换内存快照，重建检索与 TDS 缓存，通知现有页面刷新，关闭已经打开的旧详情。

清单提交前的任何失败都继续使用旧快照；已经校验的孤立对象可在重试中复用。
正常启动会验证对象，日常同步用文件属性/同事务写入的 IndexedDB 修订号复用本会话验证结果。
完整修复重新校验全部对象。原生大对象校验、清单及批量解析使用后台 isolate；Web 解析分批让出事件循环。

启动时若 active 对象缺失，会尝试完整验证的上一个 generation，并明确显示实际服务的数据版本；
最高已接受序号保持不变，修复后恢复新版本。损坏的版本记录本身不能被当作全新安装覆盖。
这提供启动恢复路径；未将故障注入或文件 flush 等同于真实断电耐久性认证。

旧 CAS 对象暂时保留，不自动 GC。跨进程读者/维护租约尚未实现，保守保留能避免清理影响正在准备的版本。
存储额度/磁盘不足会中止本次同步并保留旧指针。

## 六阶段交付

| 阶段 | 改动文件 | 已实现与验证 | 未完成/协调项 |
| --- | --- | --- | --- |
| 1 审计与回归 | 原 `test/widget_test.dart`；本记录 | 改造前 18 项测试通过；保留产品解析、完整标签/片段检索、配方、PDF 标点、自然排序语义 | 真实设备的完整视觉巡检仍需安排 |
| 2 协议与差异 | `lib/data_sync/protocol/`、`models/data_manifest.dart`、`services/diff_engine.dart`、`test/protocol_contract_test.dart` | 发布端 Python 签名跨语言验证，字段绑定、Unicode 路径、哈希、版本、重命名复用及 REPAIR；生产信任根已固定 | 线上协议字段无分叉 |
| 3 对象与事务 | `data_sync_service.dart`、`services/content_store.dart`、`services/integrity_verifier.dart`、`storage/` | CAS、写回校验、事务切换、失败保留、启动恢复、防回放、单实例互斥及跨实例 CAS | 物理断电及设备文件系统耐久性未认证；自动 GC 延后 |
| 4 业务来源统一 | `services/obsidian_data_service.dart`、`models/product_item.dart`、`services/index_manager.dart`、现有 pages/widgets | 完整映射生成列表，清空 TDS 双索引，用户 overlay 优先，引用缺失标记，页面自动刷新 | 旧笔记仍以原显示名称为键，保留现有兼容性 |
| 5 镜像/UI/Web | `services/source_manager.dart`、`storage/indexed_db_storage.dart`、`main.dart`、`settings_page.dart`、分享服务、`web/index.html`、`scripts/prepare_web_offline.py`、`scripts/web_offline_worker.js`、构建工作流 | 后台检查、15 分钟节流、源优选/回退、设置与统计、Web 持久化/离线外壳、无 dart:io 导出、外壳构建解耦；正式双源 CORS 逐对象通过 | 浏览器配额和私密模式限制仍由平台决定 |
| 6 迁移与联调 | `storage/legacy_migration*`、`test/`、`integration_test/native_sync_test.dart`、`.github/workflows/test.yml` | 幂等复制迁移、隔离未标记旧副本、原文件保留；公开示例及正式双源 187 份资料 HTTPS 联调 | Android 设备端验收见下文 |

## 删除、同名与迁移规则

- 官方数据只来自 active 完整清单；绝不扫描旧对象或恢复旧 assets。
- 不同子目录同名官方文件保留完整路径；归一化 TDS 匹配有歧义时不选任意一个。
- 个人同逻辑路径优先显示，并标注“个人”；官方更新或删除不修改个人文件。
- 删除个人覆盖项只恢复**当前**清单内的同路径官方文件；远程已经删除时保持删除。
- 引用失效不删除整个应用方案，在详情中提示缺失引用。
- 旧 manual_items.json 明确标记的文件和自定义规则迁移到 user 层，不改变笔记/主题/排序键。
- 旧版未标记的 Markdown 可能是官方副本，也可能是用户编辑，故隔离保存并提供逐项恢复入口。
- 迁移不删除旧目录，不覆盖已经存在的新 user 文件；最后写迁移标记，重复运行幂等。

基础标签规则从 Dart 移到小型初始化资源。可用普通签名 Markdown 文件
`产品列表/标签同义词规则.md` 替换基础规则；用户规则始终叠加保留。
该路径是客户端业务约定，需发布端在源资料中加入，尚未成为上游 schema 文档的专门条款；没有增加传输协议字段。

## 验证与复现

```text
flutter pub get
flutter analyze
flutter test --reporter expanded
flutter test --dart-define=RSTONE_LITE=true --reporter expanded
flutter test --platform chrome test/browser_storage_test.dart
flutter test --dart-define=RUN_GITHUB_INTEROP=true test/github_interop_test.dart
flutter test --dart-define=RUN_PRODUCTION_INTEROP=true test/production_interop_test.dart
python -m unittest discover -s scripts -p 'test_*.py'
flutter test integration_test/native_sync_test.dart -d <设备> --flavor full
flutter build windows --release
flutter build web --release --no-web-resources-cdn --dart-define=APP_VERSION=1.0.0
python scripts/prepare_web_offline.py
flutter build apk --debug --flavor full --dart-define=RSTONE_LITE=false
flutter build apk --debug --flavor lite --dart-define=RSTONE_LITE=true
```

Web 外壳构建注入实际 pubspec APP_VERSION，启动不通过网络读取 version.json；这与数据版本无关。自动发布工作流已注入，手工构建应使用实际应用版本。

当前 Flutter SDK 自带的 service worker 是注销旧缓存的占位脚本。构建后处理会关闭其自动注册，
生成按站点 scope 隔离的 RSTONE 外壳 worker。它按构建资源哈希校验并完整缓存程序文件，失败保留旧缓存；
只在新缓存完整后激活和清理旧外壳版本，不处理官方 latest/manifest/object，也不触碰 IndexedDB 或 SharedPreferences。
Web 发布使用本地 CanvasKit，完成首次在线缓存后可断网刷新。

普通测试不访问 GitHub。公开示例和生产双源联调分别显式 opt-in；生产测试从实际配置读取公钥和下载源，
从 pubspec 读取实际应用版本，使用隔离的原生 SQLite/文件存储，覆盖首次安装、重复同步和断网重开。

真实 Web 公网联调使用 `scripts/verify_production_web.cjs`，需要可加载的 Playwright Node 包及其浏览器。
完成上面的 Web 构建与外壳后处理后，在另一终端运行
`python -m http.server 8691 --bind 127.0.0.1 --directory build/web`，再运行
`node scripts/verify_production_web.cjs`。可用 `CHROME_EXECUTABLE` 指向专用测试浏览器，
`RSTONE_PLAYWRIGHT_MODULE` 指向已安装模块，`RSTONE_WEB_URL` 指定被测本地站点。
脚本创建独立浏览器上下文，验证真实 Flutter 安装/重复同步、两源全部文件 CORS/签名/哈希、完整外壳缓存和断网检索。
其个人离线用例直接在该隔离上下文中预置一份测试资料；不是对真实用户数据的操作。
本机原验收使用 Flutter 3.50.0-0.1.pre / Dart 3.12.0 开发版；CI 固定 Flutter 3.47.7 stable。
云端首次构建暴露的新 SDK 最低构建要求已对齐：Gradle 8.14.3（官方 SHA-256 校验）、AGP 8.11.1、Kotlin 2.2.20、Java 17。
SDK 安装显式指定 platform-tools，避免旧默认 tools 包已下架；Linux 模拟器按上游要求开启 KVM。
本机 Java 回环管道问题通过仅本次进程设置短 `jdk.net.unixdomain.tmpdir` 解决，没有修改全局 Java 配置。

| 验收场景 | 对应测试/证据 |
| --- | --- |
| 1–2 初装/离线重开 | `data_sync_test.dart` first install and offline restart |
| 3–5 新增/修改/删除 | 500-file acceptance，含 5 新增、8 修改、3 删除 |
| 6 重命名/移动 | rename and nested move，仅删除/新增映射，无对象下载 |
| 7 TDS 删除 | direct/normalized/RD-RS alias 全部失效，应用引用保留 |
| 8 规则修改 | official rules change dynamically，自定义规则保留 |
| 9–10 跳跃升级/复用 | sequence 1→20 和 1→8；历史对象复用 |
| 11–12 丢失/损坏 | missing/corrupt/wrong-size 同 sequence 修复 |
| 13–14 中断/镜像 | retry reuse、per-object mirror fallback |
| 15–16 签名/不兼容 | 上游契约测试及 forged/schema/appVersion/key 场景 |
| 17–18 提交前终止/孤立对象 | FaultStorage 提交失败后重开到 V1，重试不重复下载已保存对象；故障注入，不是物理断电 |
| 19 索引失败 | 索引在提交前预构建，故障时旧 active 不变；提交后重开重建索引 |
| 20–21 同名与删除 | 用户同名项保留，删除个人项后不复活资产 |
| 22 笔记偏好 | notes/columns/sorting/theme 原存储键保持 |
| 23 旧版迁移 | 原生迁移、隔离、幂等、原文件保留与恢复测试 |
| 24 跨平台 | Windows SQLite、IndexedDB 适配器与原生集成入口；真实执行结果见验证结论 |
| 25 页面一致性 | `sync_ui_test.dart` 删除后搜索更新、详情只关闭一次、导航仍可用 |

500 文件验收还断言：清单从 500→502 项，下载 **13 个唯一对象**，489 项未变；
本地仍有 **513 个 CAS 对象**，已删除官方产品仍不出现；用户同名 RS0 作为个人资料保留。

## 正式配置与后续发布

正式配置已接入。私钥、Token 不进入 APP；公钥轮换必须先发布信任新公钥的客户端。
当前公开版本为 sequence=1、dataVersion=2026.10.21.001，清单 SHA-256 为
`e6e32540db6ecbda3cb869343b22bb4a400d28a73331ed858e59506228ef882f`。
共 99 产品、21 应用、16 配方、51 TDS；187 个唯一对象，共 84,388 字节。
两个入口均使用实际客户端完成全量校验安装，重复同步各为 0 个对象、0 字节，断网重开仍可用并保留个人资料。

实际配置：

```json
{
  "sources": [
    {"name": "GitHub Pages", "url": "https://mehael-yeh.github.io/RSTONE_Data/"},
    {"name": "GitHub raw 备用", "url": "https://raw.githubusercontent.com/Mehael-Yeh/RSTONE_Data/distribution/public/"}
  ],
  "keys": {"production-2026": "DUQs5MgDCn7/4RhnjtxzWc7eZfMCXU3u7UWQWJ7CKgg="}
}
```

`scripts/validate_data_sync_config.py` 阻止空配置、示例密钥或非法下载地址进入公开发布。
普通产品数据变更由 RSTONE_Data 发布，不触发 APP 版本号变化或重新构建 APK。
Full/Lite 原有字体及 PDF 功能差异保留。正常历史回滚由发布端签发新的 sequence，客户端不降低最高序号。
Android NDK 对齐到 `28.2.13676358`，满足当前 Flutter SDK 的原生集成测试插件要求。

主分支代码变更沿用 Alpha 自动发包，Production 仍为手动触发；两者调用同一 `release_apk.yml`。
该流程先运行静态检查、Full/Lite 回归和正式双源联调，再构建并验收签名、版本、ABI、内置公钥、字体和无 Markdown 资产。
六个 APK 与 SHA256SUMS 完整上传到草稿后才公开 Release；标签指向本次源提交，不再提前打标签或自动提交构建版本到 main。
新版本以 pubspec 为最低要求，旧标签继续递增；Alpha 与 Production 发包任务串行。

## 本次验证结论

- 改造前原有 18 项回归通过。
- 当前 Full 与 Lite 各 64 项离线测试通过；浏览器专用和真实网络测试在普通测试中分别显式跳过。
- `flutter analyze`：无问题。
- GitHub 公开模拟分发站点真实 HTTPS 联调通过：5 个文件验签安装，重复同步 0 字节对象下载。
- 正式 Pages/raw 双源真实客户端联调通过：各 187 文件、84,388 字节原始对象载荷；重复同步 0 个对象，原生持久化断网重开及个人资料保护通过。
- 发布版本脚本 5 项测试通过，覆盖 0.x→1.0.0 下限、已有版本递增、空标签、频道隔离及数值排序。
- APK 资源检查脚本 4 项测试通过，覆盖两版资源边界、旧 Markdown、错误信任配置和 Lite 字体泄漏；共用发包流程通过 actionlint 检查。
- Windows Release、Web Release、Android Full/Lite Debug 已构建成功。
- 真实 Chromium IndexedDB 测试通过，覆盖事务、重开、损坏修复、删除及个人资料保留。
  本机预发布 Flutter 的 Windows CanvasKit 测试路径返回 404，测试时映射到同一 SDK 原始资源后执行；没有改产品数据或存储实现。
- Android 原生集成入口及 Full/Lite CI 矩阵已加入；本机只读模拟器出现 ADB 未授权，未取得设备端集成通过证据。
- Web Release 1.0.0 正式数据冷启动复核通过：首次下载 187 个对象，在线重复同步 0 个；34 个程序资源经哈希校验后缓存，断网刷新仍能检索 RS-LIVE-WEB 个人资料，version.json 在线请求为 0，无页面异常。
- 生产站点配置与真实产品数据联调已完成；真实 Chromium 从本地 Web 外壳跨域获取两源全部 187 个对象，签名、大小及 SHA-256 均通过。

双源请求计数、清单与源提交、Web 实测及成品配置检查见 [本次正式联调证据](DATA_SYNC_LIVE_VERIFICATION.json)。
构建产物与完整源文件哈希另存于本机 `build/data_sync_verification.json`。

生产数据已由发布端上线；用户已授权将外壳改造提交、推送并触发首次 Alpha 发包。物理断电及 Android 设备验证仍不作通过声明。
