# 课表系统

面向 iPhone 与 Apple Watch 的本地时间管理应用：手动录入或从浙大 PDF 课表导入课程，管理考试、成绩及任务，规划日程并提供两端日程小组件。

## 支持范围

- iOS 主应用、iOS WidgetKit 小组件。
- watchOS 应用、watchOS WidgetKit 小组件。
- Flutter/Dart 共享业务代码；不再维护 Android、macOS、Windows、Linux 产品工程。
- PDF 课表由 iPhone 本机 PDFKit 与 Vision 读取；确认前可编辑，课程数据保存在本机。

## 版本

- v0.1.1：手动课表与学业记录，已修复早期 iOS 编译问题。
- v0.2.1：本机 PDF 课表识别、可编辑草稿、课程安排与分周教师。
- 当前工作区的后续修正见 [更新记录](CHANGELOG.md)中的“未发布”。

先在「学业」建立学期、设置第一周星期一和节次时间，再进入学期课程列表导入 PDF。
首版主要支持浙大教务课表格式；核对草稿、补齐周次/节次等信息后确认，课程会进入本地课表。
假期停课、调课和补课在课程详情按日期设置。

## 开发与验收

当前本机工具链：Flutter 3.47.3、Dart 3.13.3、Xcode 27.0；iOS 26/27 为目标运行系统。
依赖以 `pubspec.lock` 为准，使用 `flutter pub get --enforce-lockfile`。

- [Apple CI 与构建步骤](docs/APPLE_CI.md)
- [Apple 验收与待完成实机检查](docs/APPLE_ACCEPTANCE.md)
- [项目现状与历史基线](PROJECT_SUMMARY.md)
- [手动输入设计](MANUAL_INPUT_PLAN.md)及[实施清单](MANUAL_INPUT_STEPS.md)
- [清理记录](docs/PROJECT_CLEANUP.md)

旧版数据迁移及后台任务、Keychain 凭据清理仍需保留；不得清空用户数据代替迁移。独立开发预览入口 `lib/debug/manual_preview.dart` 用于隔离样例数据。

本项目采用 [GNU GPL v3](LICENSE)。
