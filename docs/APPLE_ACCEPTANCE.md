# Apple 离线与升级验收记录（S150）

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
