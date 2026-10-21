# Apple 离线与升级验收记录（S150）

## 2026-10-21 当前检查

- 工具链：Flutter 3.47.3 / Dart 3.13.3、Xcode 27.0；已安装 iOS 26/27、watchOS 27 模拟器。
- 全量 Flutter 回归 373 项通过，静态分析 `No issues found`，Watch 凭据清理 harness 12 项通过。
- iOS Runner + WidgetExtensions、CelechronWatch、WatchWidgetExtensions 的 Simulator/no-codesign 构建通过；iOS/Watch Release/device 配置的未签名构建也通过。
- 四个源码 Info.plist lint 通过；四个构建产物版本均为 0.2.1 / build 3。iOS app/widget 最低版本 15.0，watchOS app/widget 最低版本 10.0。
- PDF 页面测试覆盖：读取结果→草稿编辑/校验→确认→一次性保存→课表可见，并校验导入日程能生成 Watch/widget 同步 DTO。还覆盖重选、取消、疑似重复跳过、缺节次、加密错误重选和删后再加安排。页面测试的原生读取结果使用合成 MethodChannel 数据。
- 390×844 iPhone 视口曾测得并排字段的输入区域宽度为 0，现已改为竖排；回归检查星期/周次/节次字段可编辑，关键输入区域至少保留 48 px 可读宽度。
- 主要浙大 PDF 样例使用 macOS PDFKit 的同一文字提取核心作只读回归，文字只经内存管道传递。新解析器发现 20 个候选安排，12 项必填完整、8 项待人工核对/补全。候选数不等于人工确认的课程总数；残缺节次/周次会阻止确认，用户可以修正或跳过。
- 假期停课、调课、补课、学期边界、迁移、备份、成绩和任务等随全量合成回归通过；不自动读取官方节假日安排。
- 当前改动位于主工作目录并记为未发布；远端 GitHub Actions 尚未运行本次更改，不能将本机结果写成远端 CI 通过。

## 尚需设备条件

2026-10-21 重新检查未发现有效开发签名 identity，devicectl 只列出模拟器，没有实体 iPhone/Watch。
因此仍需签名构建和配对设备验证 iOS 26/27 的真实文件选择/导入操作、旧数据升级、通知实际送达、App Group 小组件刷新、Watch 同步和系统日历权限行为。
先前无 entitlement 的 no-codesign 启动限制见下方历史记录，不能据进程能启动就宣称生产启动或完整功能通过。

## 2026-10-04 历史检查

日期：2026-10-04。当前记录区分自动化/模拟器证据与尚需真机确认的行为；没有使用真实账号或生产数据。

## 已验证

- Flutter 3.47.5 / Dart 3.13.4、Xcode 16.4 (16F6)；S149 的 enforce-lockfile、analyzer、347 项 Flutter tests、iOS Simulator build、CelechronWatch + WatchWidgetExtensions build 和 12 项 Watch legacy credential cleanup harness 均通过。
- iOS Runner、Watch、iOS Widget、Watch Widget 四个 Info.plist 均通过 `plutil -lint`。
- 源码搜索未发现 Dart/Swift 生产路径使用 HTTP client、URLSession、Dio、socket 或远程图片加载。`calendar_config_parser.dart` 仍保留一个旧校历 URI 构造 helper，但没有生产调用方，只有其纯函数测试；它只组装 URI，不发送请求。Apple Maps、服务条款和网站入口需要用户主动点击。此项是源码审查，不是运行期网络抓包证明。
- `xcrun devicectl list devices` 没有发现连接的 iPhone/Apple Watch。Xcode 有 iOS 18.5 和 watchOS 11.5 模拟器；原有 iPhone 16 模拟器当时处于启动状态，因此新装启动测试使用单独创建的临时 iPhone 16 模拟器，结束后已删除。

## 临时模拟器新装结果与限制

- 使用 Flutter `--no-codesign` simulator app 安装并启动，Flutter UI 与通知授权提示均出现。测试模拟器内授予通知后，启动流程显示 Keychain `-34018`。
- 对该产物的 `codesign` 检查显示 ad-hoc 签名、没有嵌入 entitlement。应用 Runner Debug 配置声明 `group.top.celechron.celechron.debug` App Group；旧凭据清理会按这个组读取 Keychain。Apple 文档说明，已签名应用的 App Groups entitlement 可授权对应 keychain access group。因此无 entitlement 的 no-codesign 产物返回 missing-entitlement，不能据此断定正常签名 app 有回归。[Apple Keychain sharing](https://developer.apple.com/documentation/Security/sharing-access-to-keychain-items-among-a-collection-of-apps)
- 尝试对 Runner scheme 使用 ad-hoc Xcode 签名：直接 project 构建因 CocoaPods Swift module 缺失而失败；workspace 构建成功，但产物仍未嵌入 entitlement。手动给临时副本添加 entitlement 后，SpringBoard 拒绝启动该 ad-hoc 包。上述签名试验仅在隔离镜像/临时模拟器进行，测试设备与签名副本已清理；没有修改产品代码或项目 entitlement。
- 因当前没有可用 Developer signing identity / provisioning profile 和连接设备，无法验证真正签名应用的新装、通知权限后的 bootstrap、升级旧 Hive/Keychain 数据、后台送达、App Group widget 刷新、Watch 同步、设备日历同步以及备份恢复。不能将 simulator 编译通过替代这些验收。

## 结论与继续条件

源码离线路径审查和自动化/编译检查通过。旧校历 URL helper 没有运行时 caller；未发现已移除的联网服务直接请求。真机升级与两端联动验收仍待执行。继续该部分需要一台可连接的 iPhone 和已配对 Apple Watch，并需要能安装同一 bundle/team 签名构建的开发签名与 provisioning profile；升级用例还需要设备保留旧版 Celechron 安装及其数据。测试前不要清除旧 App 或重置设备。无需提供账号密码。
