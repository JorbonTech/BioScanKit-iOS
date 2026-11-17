# iOS analytics 验收补充

普通 Debug、Simulator、Preview 和 XCTest 不上报。专用 Debug 真机可通过启动环境变量 `BIOSCAN_ANALYTICS_VALIDATION_BATCH` 显式提供非空批次来启用事件。验收事件强制标记 `environment=debug`、`validation_batch`、`is_test_event=true`，该通道不启用 Session Replay；Release 忽略该变量。查询必须按批次过滤，测试数据不纳入生产指标。

## 异常

共享初始化在可上报环境开启 PostHog 崩溃采集（watchOS / visionOS 除外）。SDK 在下一次启动发送保存的 fatal 事件，调试器附加时无法验证崩溃采集。服务端自动异常采集开关也需核对。`BioScanAnalytics.captureException(_:properties:)` 用于已捕获错误，保留 error_domain/error_code 并沿用环境和属性过滤。

当前 MrRock、NatureEar、MrBird、MrFish、MrMushroom 的购买失败桥接读取共享 NSError 并上报错误域/码和异常；iNature 复用已有 billing 错误回调补错误域，在最终 purchase_failed 分支上报异常。实际收件仍待验证。

## 购买

PaywallStore.lastPurchaseError 保存当前失败的 NSError，在下一次尝试前清空。MrRock 桥接把错误域、错误码写入 purchase_failed。pending、取消不进入该异常分支。购买失败事件与 $exception 各自承担漏斗和异常诊断用途。

MrRock、iNature、NatureEar、MrBird、MrFish、MrMushroom 配置 RevenueCat 时写 app_namespace、app_name。需实际核对 RevenueCat → PostHog 回传字段，不能假定自定义属性自动变成 $app_namespace。

## 行为命名

新事件必须先在共享层定义，再由各 App 引用。MrRock、MrBird、NatureEar、iNature、MrFish、MrMushroom 的公共入口、裁剪、收藏和分享请求已迁移到 `BioScanBehaviorEvent` 常量；NatureEar 保留 `sound_listen_start`，共享层额外发送 `recognition_entry_selected`。`result_shared` 仅保留已完成的保存结果，分享按钮点击记录 `result_share_requested`，不能把请求误记成完成。

## 2026-11-17 补充修复

- 共享层保留付费桥接自带的 `paywall_session_id` / `purchase_attempt_id`，避免被全局会话覆盖；legacy 路径将 pending 视作即时终态，过滤没有活动尝试的重复结果。pending 后到账不再记第二次即时购买成功。Bird、Fish、Shroom、NatureEar 和 iNature 的 RevenueCat 错误在桥接处将 paymentPendingError 转成 PurchasePendingError；iNature 同步修正 pending 的关联 ID、结果去重与尝试清理。
- `recognition_failed` 统一向 Error Tracking 发送一条已处理异常，携带识别关联 ID、错误域和错误码；取消、额度拦截不走此路径。Rock、Bird、Fish、Shroom 与 iNature 在识别失败入口保留原始 NSError；NatureEar 沿用录音错误属性。Bird / NatureEar 的 ONNX 加载及推理 catch 单独上报原始错误，iNature 预加载异常同样上报；Fish 保留模型加载 NSError，避免识别时降级为没有原始错误码的 missingModel。
- 识别成功字段检查补齐 NatureEar Watch 发起识别的 confidence，MrBird 声音识别映射到统一 recognition 事件并补 confidence / 稳定 top_species；Fish 的科学名称为空时使用模型类别索引，NatureEar 名称缺失时回退到物种 code。其余图像识别成功分支已有字段，未重复发送成功事件。
- `setBeforeSend` 为包括自动崩溃在内的所有事件补 `$app_namespace`、`$app_name`、`$app_version`。RevenueCat 六款 App 的 `app_namespace` / `app_name` 已存在，方案 A 无需重复改动；回传属性的实际结构仍需发布后检查。
- `bash Scripts/run_analytics_checks.sh` 使用仅替代 PostHog 传输的 stub，直接编译生产共享层，检查交错会话关联、pending 终态、重复结果过滤、错误属性、声音入口、收藏归一化与 Debug 禁止上报，不向网络发送数据。

## 构建依赖

最初本地构建通过 `BIOSCAN_POD_SOURCE=local pod install` 验证。随后按用户要求将共享层源码提交为 `a2aa79d2a50e23ccb3b00cb73ca4ed7d152cfb33` 并推送至 main；六款 App 的 Podfile 远程分支和 lockfile 均固定到该 commit，已执行 `BIOSCAN_POD_SOURCE=remote pod install`。下载的 BioScanAnalytics Swift 源码与本地测试源码 SHA256 一致，lockfile 不再包含本地路径。

此处采用不可变 Git commit 引用交付修复，没有创建新的版本 tag、GitHub Release 或提交 App 商店发布。后续若改用版本 tag，应确保 tag 包含上述修复，再同步更新引用和 lockfile。

## 验证记录

此前记录：MrRock Debug 真机签名构建通过；共享付费逻辑 24 个 XCTest 通过，包含购买系统错误保留和重试后清除。

2026-11-17 本轮：`Scripts/run_analytics_checks.sh` 的普通与禁止上报两个进程均通过，所有修改的 Swift 文件语法检查和 Git whitespace 检查通过。

六款 App 使用本地共享库、generic iOS 设备目标、Debug 配置及 `CODE_SIGNING_ALLOWED=NO` 构建，全部成功：

| App / scheme | 结果 |
| --- | --- |
| MrRock | 构建成功，最后共享层改动后的增量复核成功 |
| MrBird | 构建成功，最后 ONNX 异常上报改动后的增量复核成功 |
| NatureEar | iOS 与关联 Watch 目标构建成功 |
| MrFish / Fish | 构建成功 |
| MrMushroom / Mushroom | 构建成功 |
| iNature / BioScan | 构建成功 |

构建日志保存在 `/tmp/ios-analytics-validation/`，汇总见 `build-results.txt`。这属于无签名构建验证，不代表已安装或发布。真实崩溃、沙盒购买失败、RevenueCat 回传和新事件的 PostHog 实际收件按约定留到上线后验证。
