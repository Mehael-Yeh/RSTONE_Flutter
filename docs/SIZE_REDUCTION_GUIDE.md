# 软件包体积优化研究（RSTONE_Flutter）

## 已落地改动

1. Android `release` 启用 `minifyEnabled` 与 `shrinkResources`。
2. 增加 `proguard-rules.pro`，为后续三方库反射 keep 规则预留入口。
3. 启用 ABI 拆分（`armeabi-v7a` / `arm64-v8a` / `x86_64`），禁用 universal APK。

> 说明：如果使用 Google Play，建议优先上传 AAB，让商店自动按设备分发，体积通常更小。

## 后续建议

- 资产瘦身：
  - 清理未使用字体（当前 assets/fonts 下有多套字体）。
  - 将非必要位图改为 WebP/矢量资源。
- 依赖瘦身：
  - 定期检查 `pubspec.yaml` 中未使用依赖并移除。
- 功能拆包：
  - 非核心功能采用延迟加载或按需初始化（例如重量级预览逻辑）。
- 构建分析：
  - 使用 `flutter build appbundle --analyze-size` 输出体积分解报告。

## 建议验证命令

```bash
flutter build apk --release --split-per-abi
flutter build appbundle --release --analyze-size
```
