# iOS / watchOS 持续集成

GitHub Actions workflow：`.github/workflows/code_check.yml`。它在推送到 `main`、向 `main` 提交 PR 或手动触发时运行，使用 macOS 15 runner、Xcode 16.4 和 Flutter 3.47.5 / Dart 3.13.4。GitHub runner image 的 Xcode 16.4 路径和 iOS/watchOS SDK 版本见 [macos-15 image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md)。

## 检查内容

- `flutter pub get --enforce-lockfile`：使用已提交的 `pubspec.lock`，发现清单与锁不一致即失败。
- `flutter analyze --no-fatal-infos` 与 `flutter test`：检查共享 Dart 源码和完整自动化测试。
- `flutter build ios --simulator --no-codesign`：构建 iOS app 及其小组件。
- `xcodebuild -project ios/Runner.xcodeproj -scheme CelechronWatch -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build`：构建 Apple Watch app 与 WatchWidgetExtensions。
- `bash ios/CelechronWatchTests/run_tests.sh`：执行旧 Watch 凭据清理 harness。

可在安装了 Xcode 16.4 和 Flutter 3.47.5 的 macOS 上按工作流顺序复现这些命令。先运行 `flutter pub get --enforce-lockfile`，以生成 Xcode 所需的 Flutter 插件 package graph，再执行 watchOS `xcodebuild`。

模拟器构建不使用签名，也不验证设备安装、归档上传、推送通知或 iPhone/Apple Watch 实机同步。真机/发布验证需要签名证书、provisioning profiles、Apple Developer 团队和测试设备；CI 不存放这些凭据。GitHub runner 上的首次真实 workflow 结果需在变更推送后查看，本地隔离镜像已逐项运行上述命令。

CI 暂不做全仓 `dart format --set-exit-if-changed` 门禁：当前基线有 10 个 Dart 文件会触发格式差异，本轮遵循小步修改原则，没有对其做批量纯格式改写。Analyzer 和 tests 仍是必需门禁；格式债务可在独立步骤逐个处理后再启用。
