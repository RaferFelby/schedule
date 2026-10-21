# Apple 产品范围清理

## 2026-10-21 整理

- 当前项目说明与历史网络版调查分开：旧内容移至 `docs/history/PROJECT_SUMMARY_20260919.md`。
- 根忽略规则精简为 Flutter、CocoaPods、Xcode、构建包和本地编辑器产物；保留 pubspec.lock。
- 删除未被 Xcode 引用且内容重复的 `ios/CelechronWatch/Resources/AppLogo.png`。实际 target 引用的 AppLogo.png 和 asset catalog 保留。
- 清理 5 个属于已消失临时副本的 Xcode DerivedData 缓存，回收约 1.9 GiB；不删除模拟器或用户数据。
- Dart 引用图涵盖生产入口、预览入口、Pigeon 定义及测试，未发现完全无引用的 Dart 文件。旧迁移及兼容实现继续保留。
- 本轮功能修正和检查结果见 CHANGELOG 的未发布条目及 Apple 验收文档。

## 2026-10-04 历史整理

日期：2026-10-04。用户授权检查全项目，最终只支持 iOS/watchOS 与两端小组件。

## 已移出

- 已安装 Xcode 16.4 的 `.xip` 安装包（约 2.8 GiB）。
- 根目录 `build/`、`.dart_tool/`、`.flutter-plugins-dependencies` 生成缓存；正常构建会重新生成。
- 11 个无消费者的设计组件：animate_button、captcha_input、cupertino_async_switch、custom_colors、custom_decoration、multiple_columns、refresh_status_indicator、rolling_shimmer_text、round_rectangle_card、sub_title、two_line_card。
- 旧设置入口 option_view 及仅由它引用的 allow_time_edit_page、course_id_mapping_edit_page、custom_license_page；它们不在现有设置路由。
- 仅服务上述旧入口的 platform_features。
- 未加入 Xcode target、未注册 WidgetBundle 的 WidgetExtensionsLiveActivity 模板；实际两端日程 widget 保留。无 Live Activity capability 声明需要撤销。
- 旧 README 使用的 banner.png；新 README 不再引用。

移出文件暂存于 `/private/tmp/celechron-cleanup-20261004`，没有覆盖其他临时文件，也没有丢弃未提交修改。此目录可能被系统清理，不作为长期备份。

## 非 Apple 平台工程清理完成

用户恢复目录所有权后，Android、macOS、Windows、Linux 工程均已移出项目，暂存于上述目录。图标生成配置已禁用 Android，`.metadata` 原本就只声明 root/ios，CI 只构建 Apple 目标。

## 保留依据

- iOS Runner、CelechronWatch、WidgetExtensions、WatchWidgetExtensions、共享 Swift 日程通信、App Group、通知和日历能力。
- Hive 旧模型/适配器、迁移代码、迁移与历史纯计算/解析回归测试；测试引用的兼容实现不作为孤立文件删除。
- workmanager / flutter_secure_storage 与 Apple 旧凭据撤销链路：取消旧后台任务、清除指定旧凭据、失败后重试。禁用校园卡 widget 保留升级提示及旧缓存清理。
- Pigeon 源定义及生成文件；独立 manual_preview.dart 开发入口、样例与测试夹具。
- LICENSE、项目协作说明、历史基线、方案与操作日志。历史描述已在 PROJECT_SUMMARY 顶部明确标记。
- pubspec.lock：纳入可复现依赖锁；本次不升级依赖。

## 检查

本次静态导入审查：所有本地 Dart import/export/part 目标存在；保留的生产 Swift 文件均在 pbxproj 中有对应引用。具体 analyzer、测试及 Apple 构建结果见操作日志 LOG-20261004-269。真实签名设备上的旧版升级、同步、通知和 widget 验收仍见 APPLE_ACCEPTANCE.md，不能以模拟器构建代替。

### 本轮验证结果

严格锁文件解析成功；347 项 Flutter tests 全通过；analyzer 0 errors/warnings、21 条既有 infos；iOS Runner 与 WidgetExtensions、CelechronWatch 与 WatchWidgetExtensions 模拟器构建全部通过；Watch 旧凭据清理 harness 12 assertions 通过。`git diff --check` 退出 0。检查在隔离镜像执行，没有修改用户设备或模拟器数据。四个非 Apple 平台目录已移出；移出后再次完整复跑同一检查组全部通过，见 LOG-20261004-271。

清理收尾已完成，无权限阻塞、无仍运行检查、无 Git 提交。仓库平台工程仅剩 `ios/`（含 watchOS 与两端小组件）。
