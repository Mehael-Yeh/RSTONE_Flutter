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
用户指定新外壳为 `2.0.0`，满足签名清单 `minAppVersion=1.0.0`，不绕过兼容校验。
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
| 6 迁移与联调 | `storage/legacy_migration*`、`test/`、`integration_test/native_sync_test.dart`、`.github/workflows/test.yml` | 幂等复制迁移、仅导入明确标记的个人文件、保留旧原件；公开示例及正式双源 187 份资料 HTTPS 联调 | Android 设备端验收见下文 |

## 删除、同名与迁移规则

- 官方数据只来自 active 完整清单；绝不扫描旧对象或恢复旧 assets。
- 不同子目录同名官方文件保留完整路径；归一化 TDS 匹配有歧义时不选任意一个。
- 个人同逻辑路径优先显示，并标注“个人”；官方更新或删除不修改个人文件。
- 删除个人覆盖项只恢复**当前**清单内的同路径官方文件；远程已经删除时保持删除。
- 引用失效不删除整个应用方案，在详情中提示缺失引用。
- 旧 manual_items.json 明确标记的文件和自定义规则迁移到 user 层，不改变笔记/主题/排序键。
- 旧版未标记的 Markdown 保留在原目录，不导入当前资料库；不再提供历史资料和旧版资料恢复功能。已有隔离副本不主动删除。
- 迁移不删除旧目录，不覆盖已经存在的新 user 文件；最后写迁移标记，重复运行幂等。

基础标签规则从 Dart 移到小型初始化资源。可用普通签名 Markdown 文件
`产品列表/标签同义词规则.md` 替换基础规则；用户规则始终叠加保留。
该路径是客户端业务约定，需发布端在源资料中加入，尚未成为上游 schema 文档的专门条款；没有增加传输协议字段。

## 首次下载与同步设置优化

首次下载使用最多 8 个并发任务，两个源及清单/签名请求并行检查；仍等待并核对各源的可信结果，不跳过同序号冲突检查。
本轮出错的数据源优先级降低，后续对象优先使用可用源，避免每个文件都重复等待同一源超时。
下载失败后先等待在途任务结束再返回，保留已验证对象供重试复用，不发生上一轮任务写入下一轮同步的情况。
完成下载后自动逐对象校验，发现缺失或损坏时自动补取一次，再通过校验和索引构建后事务提交。

设置只显示一行当前资料版本，右侧提供“更新”按钮；发现更高版本时才在同一行下方显示可更新版本。
点击“下载源”直接打开选择面板；不保留下拉框、手动校验修复、历史恢复或常驻的最近同步明细。
有实际资料变动时，完成信息通过全局底部提示显示一次；重进设置和自动空检查不重复提示。
设置卡片外侧左右均为 16 像素，卡内更新按钮和列表入口统一为 16 像素边距。

本机 Windows 正式 HTTPS 对比（同一签名清单、187 文件、84,388 字节）：Pages 首装从 75.243 秒降为 5.247 秒，
raw 备用源从 89.541 秒降为 5.367 秒；两者重复同步均为 0 个对象。该计时包含资料安装与提交，
是本次网络环境的实测，不代表所有设备和网络的固定耗时。详情见 [下载与界面优化验收](SYNC_SETTINGS_OPTIMIZATION_VERIFICATION.json)。

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
flutter build web --release --no-web-resources-cdn --dart-define=APP_VERSION=2.0.0
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
本机原验收使用 Flutter 3.50.0-0.1.pre / Dart 3.12.0 开发版；2.0 的 CI 固定 Flutter 3.32.8 stable。
旧 APK 最低 Android API 为 21；按用户最新要求，2.0 最低系统提高为 Android 10（API 29）。
保留已验证的 SDK 与依赖组合：idb_shim 2.6.7、SQLite 2.9.4 与 ffi 2.3.6，
并通过 sqlite3_flutter_libs 0.5.41 为桌面打包原生 SQLite。
Gradle 8.11.1 使用官方分发和 SHA-256 校验，AGP 8.9.1、Kotlin 2.1.0、Java 17 与原项目工具链保持一致。
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
| 23 旧版迁移 | 原生迁移、幂等、个人资料导入、未标记旧原件保留测试 |
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

`scripts/validate_data_sync_config.py` 可手动检查空配置、示例密钥或非法下载地址。
普通产品数据变更由 RSTONE_Data 发布，不触发 APP 版本号变化或重新构建 APK。
Full/Lite 原有字体及 PDF 功能差异保留。正常历史回滚由发布端签发新的 sequence，客户端不降低最高序号。
Android NDK 对齐到 `28.2.13676358`，满足当前 Flutter SDK 的原生集成测试插件要求。

主分支代码变更沿用 Alpha 自动发包，Production 仍为手动触发；两者调用同一 `release_apk.yml`。
按用户 2026-10-21 的最新要求，后续流程只构建、签名和上传安装包，成功后直接发布，
不再自动执行静态检查、测试、双源联调、APK 审计或模拟器安装验证；独立测试流程改为仅手动触发。
六个 APK 与 SHA256SUMS 完整上传到草稿后才公开 Release；标签指向本次源提交，不再提前打标签或自动提交构建版本到 main。
新版本以 pubspec 为最低要求，旧标签继续递增；Alpha 与 Production 发包任务串行。
版本码继续采用构建时的 epoch 分钟数，沿用原应用标识与签名。首次 2.0.0 发布及本次设置改造已完成的验证结果保留为历史记录。

首次 2.0.0 发包曾执行覆盖安装门禁：下载已发布的 `v0.0.263-alpha` Full/Lite 与 `v1.0.9` 的三种 ABI，
并纳入最新稳定/预发布包，核对应用标识、签名和版本码。新版本码高于全部基线，六个 APK 的最低 Android API 必须为 29。
旧签名证书 SHA-256 为 `8a593a18b7f62500f1f47f27643c04456f51c5756defd9d9460365e058495658`。
在专用 Android API 29 与 35 模拟器上先安装旧包、预置个人 Markdown/规则/笔记/主题/排序，再执行 `adb install -r`；
两次安装之间不卸载或清数据，检查 UID 不变、个人文件迁移后字节一致、笔记与偏好保留、旧原件仍在。
覆盖旧 Alpha Full→新 Full、旧 Alpha Lite→新 Lite、旧正式 Full→新 Full，以及 Full→Lite。
脚本限制为专用模拟器，所有测试资料均为合成内容，不操作用户手机。通过后才公开六个签名 APK。

## 本次验证结论

- 改造前原有 18 项回归通过。
- 当前 Full 与 Lite 各 73 项离线测试通过；浏览器专用和真实网络测试在普通测试中分别显式跳过。
- `flutter analyze`：无问题。
- GitHub 公开模拟分发站点真实 HTTPS 联调通过：5 个文件验签安装，重复同步 0 字节对象下载。
- 正式 Pages/raw 双源真实客户端联调通过：各 187 文件、84,388 字节原始对象载荷；重复同步 0 个对象，原生持久化断网重开及个人资料保护通过。
- 发布与 APK 检查脚本共 17 项测试通过，覆盖 2.0 大版本、已有版本递增、频道版本下限、数值排序、Full/Lite 资产、跨工具元数据解析、应用身份读取和直接升级的签名/版本码/最低系统约束。
- 共用发包流程通过 actionlint 检查；[2.0 发包流程](https://github.com/Mehael-Yeh/RSTONE_Flutter/actions/runs/39561149330)全部通过。
- `2.0.0+29876120` Full/Lite 六个签名 APK 已公开发布，最低 Android API 均为 29；下载后的 SHA-256 与发布资产摘要一致，签名与九个历史包一致。
- Android 10/API 29 和 Android 15/API 35 共八种真实覆盖安装测试通过，两次安装之间没有卸载或清数据；UID、笔记、个人 Markdown、规则、主题及排序保留，旧个人文件原件仍在。
- Windows Release、Web Release、Android Full/Lite Debug 已构建成功。
- Windows 2.0.0+29876067 Release 已重新构建，随包 SQLite DLL 在隔离内存数据库中完成 BLOB 写入与读取。
- 真实 Chromium IndexedDB 测试通过，覆盖事务、重开、损坏修复、删除及个人资料保留。
  本机预发布 Flutter 的 Windows CanvasKit 测试路径返回 404，测试时映射到同一 SDK 原始资源后执行；没有改产品数据或存储实现。
- Android Full/Lite 原生集成已在 GitHub Actions 的专用 API 35 模拟器通过，覆盖事务、离线重开、损坏修复和个人资料保护；见 [CI 运行](https://github.com/Mehael-Yeh/RSTONE_Flutter/actions/runs/39561149158)。
- Web Release 1.0.0 正式数据冷启动复核通过：首次下载 187 个对象，在线重复同步 0 个；34 个程序资源经哈希校验后缓存，断网刷新仍能检索 RS-LIVE-WEB 个人资料，version.json 在线请求为 0，无页面异常。
- 线上 Web 2.0.0 已部署并重新验收：首次下载 187 个对象，重复同步 0 个；33 个程序资源完整缓存，断网冷刷新仍可检索合成个人资料，两源全部对象的浏览器跨域请求、签名与哈希通过，无页面异常或 version.json 请求。
- 生产站点配置与真实产品数据联调已完成；真实 Chromium 从本地 Web 外壳跨域获取两源全部 187 个对象，签名、大小及 SHA-256 均通过。

2.0 发布的包信息、校验值、源码提交、八种覆盖安装与线上 Web 复核见 [2.0 发布验收证据](RELEASE_2_0_VERIFICATION.json)。
早期 1.0.0 外壳的双源联调快照见 [原正式联调证据](DATA_SYNC_LIVE_VERIFICATION.json)；
本机 `build/data_sync_verification.json` 也是早期快照，不代表当前 2.0 发布包。

生产数据与 [2.0.0-alpha](https://github.com/Mehael-Yeh/RSTONE_Flutter/releases/tag/v2.0.0-alpha) 均已上线。
Android 安装验证在 CI 专用模拟器执行；ARM 包已核对签名及元数据，物理断电和实体手机长期运行不作通过声明。
