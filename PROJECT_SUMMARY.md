# 课表系统：当前项目说明

更新日期：2026-10-21。产品面向 iPhone、Apple Watch 和两端日程小组件。
当前工作区基于 v0.2.1，包含尚未发布的功能修正；发布记录见 [CHANGELOG](CHANGELOG.md)。
早期网络版调查已保存到 [历史基线](docs/history/PROJECT_SUMMARY_20260919.md)，不能作为当前功能清单。

## 使用流程

1. 在「学业」创建学期，设置开始/结束日期及第一周星期一。
2. 核对节次表；在学期课程列表手动新增课程，或选择「导入 PDF」。
3. PDF 首版以浙大教务课表格式为主。iPhone 本地提取文字，文字不足时使用中文 OCR。
4. 检查导入草稿的课程名、星期、周次、节次，补齐未确认信息；课程号、学分、教师和地点可选。
5. 确认后一次性新增课程和上课安排，再从「日程」打开课表。重复课程会提示，可关闭导入开关跳过。

日期来自本地学期，时间来自本地节次表。PDF 不自动决定学期日期、第一周起点或节假日。
其他版式、OCR 错字及未识别页面需人工核对，识别完整不代表内容一定正确。

## 已有功能

| 功能 | 当前实现 |
| --- | --- |
| 课表 | 课程、星期、周次、节次、地点及按安排设置的教师；支持列表/周课表展示 |
| 假期与调休 | 在课程详情按日期停课、调课或新增补课；不自动下载官方放假/调休安排 |
| 学业 | 学期、考试、成绩、学分、GPA、重修口径和实践记录 |
| 任务与接下来 | 本地任务、固定事项、截止日期、按课程占用安排工作时间 |
| 日历与提醒 | 本地日历视图、ICS 导出、系统日历同步、本地提醒 |
| 备份 | 本地 JSON 导出、预览、校验和恢复；恢复先写入候选数据代再激活 |
| Apple 设备 | 日程数据通过 App Group、Pigeon 和 WatchConnectivity 提供给 Watch 及两端小组件 |
| 升级兼容 | 旧 Hive 记录迁移、问题记录修正/跳过、旧后台任务停用、指定旧凭据清理 |

旧校园账号抓取与校园卡支付已停止。兼容文件及旧卡片升级提示用于处理旧数据，不能仅因不在新页面中出现就删除。

## 代码与数据

| 目录 | 职责 |
| --- | --- |
| `lib/main.dart`、`lib/page/home_page.dart` | 本地启动、迁移状态及五个主入口 |
| `lib/manual/model/`、`data/` | 学期、课程、规则等权威模型与串行快照保存 |
| `lib/manual/page/`、`service/` | 表单、PDF 草稿、课表展开、成绩计算、备份、提醒和设备日程适配 |
| `lib/manual/migration/` | 保留 ID/关联的旧记录转换与可恢复迁移 |
| `lib/model/`、`database/` | 共享任务/日程模型及旧数据读取兼容 |
| `lib/debug/` | 与正式数据隔离的开发预览入口和样例存储 |
| `lib/pigeon/`、`ios/Runner/`、`ios/Shared/` | 生成的日程桥接、iOS 文件选择/PDFKit/Vision、Apple 共享数据 |
| `ios/CelechronWatch/`、`WidgetExtensions/`、`WatchWidgetExtensions/` | Watch 应用及两端小组件 |
| `test/`、`ios/CelechronWatchTests/` | 合成数据自动化回归和原生旧凭据清理检查 |

课程与规则通过稳定 ID 关联；派生课表/GPA 不反写为第二份业务数据。
表单草稿独立，确认和持久化成功后才发布状态。PDF 只在设备读取，不保存原文件或上传内容。
Pigeon 文件必须从 `lib/pigeon/prompt/flow_message_prompt.dart` 生成，不能手改生成实现。

## 工具链与验证边界

本机工具链为 Flutter 3.47.3 / Dart 3.13.3、Xcode 27.0。iOS 最低部署版本为 15，目标运行系统为 iOS 26/27；watchOS 最低版本为 10。
依赖以 `pubspec.lock` 为准，不随整理任务升级。

检查命令和证据范围见 [Apple CI](docs/APPLE_CI.md)、[Apple 验收](docs/APPLE_ACCEPTANCE.md)。
模拟器构建、页面测试与本地服务测试不能替代签名真机的通知送达、App Group、Watch 联动和升级验收。
历史方案及编号进度见 [手动输入方案](MANUAL_INPUT_PLAN.md)和[步骤清单](MANUAL_INPUT_STEPS.md)；S150 的实机部分仍需设备与开发签名。
