# iOS / watchOS 依赖用途核对（S148）

本表基于当前 Dart、Swift、Pigeon、测试源码和 `pubspec.yaml`/`pubspec.lock` 核对。用途以 iOS 与 Apple Watch 为目标；没有为了其他平台安排验收或清理。这里只调整确认无调用的依赖和依赖分类，不升级版本。

## 应用运行与数据

| 依赖 | 当前用途 / 保留依据 |
| --- | --- |
| `get` | 页面状态、响应式更新、路由和控制器；旧模型与手动日程 UI 均使用。 |
| `hive` | 本地业务数据、手动录入数据、预览隔离库、迁移和升级清理标记；生产、调试与测试都有直接调用。应用自行调用 `Hive.init(path)`。 |
| `uuid` | task、period、课程、成绩等记录创建稳定唯一 ID，并维持显式关联。 |
| `table_calendar` | 手动日历与本地日程页面的日历视图、日期适配。 |
| `quiver` | `Task` 的日期辅助计算（`quiver/time.dart`）。 |
| `flutter_secure_storage` | 兼容旧安装凭据清理及旧数据库兼容读取；升级清理完成前必须保留。详见 S147。 |
| `crypto` | iCalendar 内容编码/摘要，以及本地迁移、生成选择和转换流程的摘要/校验。 |
| `path_provider` | 定位应用文档/缓存目录，用于 Hive 初始化、隔离预览、导出文件和诊断日志。 |
| `app_links` | 应用链接与旧 ECard 深链接的入口处理；旧 ECard 页面保留为禁用/清理引导状态。 |

## iOS 系统能力与用户操作

| 依赖 | 当前用途 / 保留依据 |
| --- | --- |
| `flutter_local_notifications` | 本地提醒的授权、排程和取消；启动时提醒恢复也依赖它。 |
| `timezone` | 本地提醒的时区初始化、计划时间转换；设备日历读写也使用时区类型。 |
| `device_calendar` | iOS 本机日历授权、事件读取和同步映射。 |
| `share_plus` | 用户主动分享 iCalendar 导出文件和诊断报告。 |
| `device_info_plus` | iCalendar 导出元数据中识别设备平台/版本，并构建产品标识。 |
| `url_launcher` | 设置页和服务条款中的外部链接。 |
| `cupertino_icons` | `CupertinoIcons` 的图标字体资源。图标通过 Flutter SDK 的 `CupertinoIcons` 使用，不需要 `package:cupertino_icons` 源码导入。 |
| `flutter` / `flutter_localizations` | Flutter 应用框架与 SDK 本地化能力。 |

## 开发、生成与验证工具

| 依赖 | 当前用途 / 保留依据 |
| --- | --- |
| `flutter_launcher_icons`（dev） | 从 `assets/logo.png` 生成 iOS 应用图标；仅开发/生成阶段需要。配置沿用仓库现状，本轮没有运行 Android 资源生成器。 |
| `pigeon`（dev） | 维护 Flow 消息通道 schema 并生成 Dart/Swift 通道代码。 |
| `flutter_test`（SDK dev） | 运行模型、存储、迁移、页面及清理逻辑的自动化测试。 |
| `flutter_lints`（dev） | 项目 `analysis_options.yaml` 启用的 Dart lint 规则。 |

`workmanager` 仅用于 S147 中的旧 iOS 后台任务取消；新版本已删除周期注册，但旧安装的取消标记成功前仍需保留该包。它是一次性兼容清理依赖，不是当前功能后台调度入口。

## 已清理或调整

| 依赖 | 处理结果 / 依据 |
| --- | --- |
| `rename_app` | 移除。全仓源码、脚本、CI、文档无调用或配置。 |
| `hive_flutter` | 移除。没有 `Hive.initFlutter()` 或该包导入，应用与测试都显式初始化 Hive 路径。 |
| `flutter_svg` | 移除。全仓无包导入、资产或构建配置；其独有的 http/vector graphics 传递依赖随解析一并移除。 |
| `extended_sliver` | 移除。无包导入，页面使用 Flutter SDK 内建 Sliver API。 |
| `intl` | 从 direct dependency 移除；lock 中仍保留为其他依赖所需的 transitive dependency。 |

每个移除/分类调整均单独解析依赖，并运行 analyzer、347 项 Flutter tests 和 iOS Simulator build。详细过程见 `docs/WORK_LOG.md` 的 LOG-20261003-258 至 LOG-20261003-263。Analyzer 保留 21 条已有 `calendar_to_system.dart` info，无 error/warning。
