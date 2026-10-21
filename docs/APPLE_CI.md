# iOS / watchOS 持续集成

工作流为 `.github/workflows/code_check.yml`，在 main 分支推送、PR、`v*` 标签推送及手动触发时运行。标签触发覆盖本仓库以标签提供版本源码的发布方式。

CI 使用 macOS 15、Xcode 16.4 和 Flutter 3.47.3 / Dart 3.13.3。本机检查使用同版 Flutter 和 Xcode 27.0；CI 的旧 SDK 构建与本机 iOS 26/27 运行检查是不同证据，不将前者视为新系统运行验证。

## 检查顺序

```sh
flutter pub get --enforce-lockfile
flutter analyze --no-fatal-infos
flutter test
flutter build ios --simulator --no-codesign
xcodebuild -project ios/Runner.xcodeproj -scheme CelechronWatch \
  -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath build/watchDerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ios/Runner.xcodeproj -scheme WatchWidgetExtensions \
  -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath build/watchDerivedData CODE_SIGNING_ALLOWED=NO build
bash ios/CelechronWatchTests/run_tests.sh
```

先生成 Flutter 插件配置和依赖，再执行 Xcode 构建。iOS 构建包含 WidgetExtensions，Watch 应用和 WatchWidgetExtensions 均检查独立 scheme。

本轮只格式化修改的 Dart 文件，避免全仓历史格式差异造成无关变动。依赖版本由 pubspec.lock 固定，整理不升级依赖。

上述构建不使用开发签名，不能验证实体设备安装、通知送达、App Group entitlement、Watch 配对同步或 TestFlight 上传。实际设备验收见 [Apple 验收](APPLE_ACCEPTANCE.md)。

当前整理后的工作流尚未推送触发，不能报告 GitHub Actions 远端已通过；本机结果需以验收记录为准。
