# BioScanAnalytics 事件约定

新事件必须先在共享层定义，App 引用 `BioScanBehaviorEvent`，不要重新定义公共事件字符串。此清单适用于 iOS / iPadOS 的 BioScan 系列 App。

## 公共行为

| 共享常量 | 事件名 | 含义 / 属性 |
| --- | --- | --- |
| `recognitionEntrySelected` | `recognition_entry_selected` | 用户选择识别入口，携带 `source`、`recognition_mode` |
| `recognitionCropConfirmed` | `recognition_crop_confirmed` | 用户确认裁剪 |
| `recognitionCropCancelled` | `recognition_crop_cancelled` | 用户取消裁剪 |
| `resultFavoriteChanged` | `result_favorite_changed` | 收藏状态变化，`is_favorite` 为 Boolean |
| `resultShareRequested` | `result_share_requested` | 用户请求打开分享，不表示分享已完成 |

声音入口保留 `sound_listen_start`，共享层同时发送 `recognition_entry_selected`，并标记 `recognition_mode=sound`。不要再在 App 侧重复补发同一入口事件。

`result_shared` 用于已完成的结果保存；点击分享按钮必须使用 `result_share_requested`。旧 `scan_entry_tap`、`crop_confirm` / `crop_confirmed`、`crop_cancel` / `crop_cancelled`、`favorite_changed` / `favorite_add` / `favorite_remove`、`result_share_tap` 由共享层兼容归一化，新调用应直接使用常量。分析时按部署后的版本过滤，保留历史名称查询。

## 识别结果与异常

- `recognition_succeeded`：`confidence` 为 0–1；`top_species` 为科学名称、物种 code 或稳定模型类别标识，不能使用本地化显示名；保留 `recognition_attempt_id`、`duration_ms`、识别来源。
- `recognition_failed`：保留原始 `error_domain` / `error_code`，共享层同步进入 Error Tracking。`recognition_cancelled`、`recognition_blocked` 不进入该异常路径。
- 原始模型加载 / 推理异常可通过 `captureException` 上报，使用 `failure_stage=model_load|model_inference`；录音失败保留系统错误码和 `failure_step`、`app_state`。
- 所有事件在发送前补充 `$app_namespace`、`$app_name`、`$app_version` 和环境属性，便于异常与行为按 App / 版本关联。

## 购买结果

一次 `purchase_started` 通过 `purchase_attempt_id` 关联至最多一个即时结果：`purchase_success`、`purchase_cancelled`、`purchase_failed`、`purchase_pending`。待批准后到账属于后续 delivery，不重复计算即时结果。

每个付费页独立生成 `paywall_session_id`，每次购买独立生成 `purchase_attempt_id`；共享层保留桥接传入的 ID。失败需提供 `product_id`、`error_type`、`error_code`、`failure_stage`，取消和等待批准不作为失败上报。窗口内仍在进行、App 退出或中断的尝试单列，不通过同日事件总数强行对账。

RevenueCat 配置时设置订阅者属性 `app_namespace` / `app_name`。它们与 PostHog 的 `$app_namespace` 不是同一个字段，回传验收需查看实际集成发送的属性结构。

## 验证

运行 `bash Scripts/run_analytics_checks.sh` 执行不联网的共享层回归检查。普通 Debug、Simulator、Preview 和 XCTest 不上报；专用真机验证使用独立批次。环境设置、各 issue 的实现记录与发布后收件范围见 [Analytics-Validation.md](Docs/Analytics-Validation.md)。
