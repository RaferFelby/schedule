# 课表系统

面向 iPhone 与 Apple Watch 的本地时间管理应用：手动录入或从浙大 PDF 课表导入课程，管理考试、成绩及任务，规划日程并提供两端日程小组件。

## 支持范围

- iOS 主应用、iOS WidgetKit 小组件。
- watchOS 应用、watchOS WidgetKit 小组件。
- Flutter/Dart 共享业务代码；不再维护 Android、macOS、Windows、Linux 产品工程。
- PDF 课表由 iPhone 本机 PDFKit 与 Vision 读取；确认前可编辑，课程数据保存在本机。

## 版本

- v0.1.0：Apple 平台手动课表与学业记录。
- v0.2.0：新增本机 PDF 课表识别、导入草稿与课程安排编辑。

## 开发与验收

已验证工具链：Flutter 3.47.5、Dart 3.13.4、Xcode 16.4。依赖以 `pubspec.lock` 为准，使用 `flutter pub get --enforce-lockfile`。

- [Apple CI 与构建步骤](docs/APPLE_CI.md)
- [Apple 验收与待完成实机检查](docs/APPLE_ACCEPTANCE.md)
- [项目现状与历史基线](PROJECT_SUMMARY.md)
- [手动输入设计](MANUAL_INPUT_PLAN.md)及[实施清单](MANUAL_INPUT_STEPS.md)
- [清理记录](docs/PROJECT_CLEANUP.md)

旧版数据迁移及后台任务、Keychain 凭据清理仍需保留；不得清空用户数据代替迁移。独立开发预览入口 `lib/debug/manual_preview.dart` 用于隔离样例数据。

本项目采用 [GNU GPL v3](LICENSE)。
