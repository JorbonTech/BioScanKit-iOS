import Foundation
import PostHog

@main
struct AnalyticsRegressionChecks {
    static func main() {
        let disabled = CommandLine.arguments.contains("--disabled")
        BioScanAnalytics.configure(.postHogDefault(appID: "test.app", appName: "Test", debug: disabled))
        let sdk = PostHogSDK.shared
        if disabled {
            BioScanAnalytics.track("recognition_failed")
            BioScanAnalytics.captureException(NSError(domain: "test", code: 1))
            precondition(sdk.events.isEmpty)
            precondition(sdk.config?.errorTrackingConfig.autoCapture == false)
            print("PASS: Debug 禁止事件与异常上报")
            return
        }
        func last(_ name: String) -> Event {
            sdk.events.last(where: { $0.name == name })!
        }
        BioScanAnalytics.track("paywall_shown", properties: ["paywall_session_id": "visit-a"])
        BioScanAnalytics.track("purchase_started", properties: ["paywall_session_id": "visit-a", "purchase_attempt_id": "attempt-a"])
        BioScanAnalytics.track("purchase_started", properties: ["paywall_session_id": "visit-b", "purchase_attempt_id": "attempt-b"])
        BioScanAnalytics.track("purchase_succeeded", properties: ["paywall_session_id": "visit-a", "purchase_attempt_id": "attempt-a"])
        precondition(last("purchase_success").properties["purchase_attempt_id"] as? String == "attempt-a")
        precondition(last("purchase_success").properties["paywall_session_id"] as? String == "visit-a")
        BioScanAnalytics.track("purchase_failed", properties: ["paywall_session_id": "visit-b", "purchase_attempt_id": "attempt-b", "error_code": 42])
        precondition(last("purchase_failed").properties["purchase_attempt_id"] as? String == "attempt-b")
        BioScanAnalytics.track("paywall_viewed")
        BioScanAnalytics.track("purchase_started")
        BioScanAnalytics.track("purchase_pending")
        let outcomeCount = sdk.events.count
        BioScanAnalytics.track("purchase_success")
        BioScanAnalytics.track("purchase_failed")
        BioScanAnalytics.track("purchase_cancelled")
        precondition(sdk.events.count == outcomeCount, "pending 必须结束即时购买尝试")
        BioScanAnalytics.track("paywall_dismissed")
        precondition(last("paywall_dismissed").properties["did_convert"] as? Bool == false)
        BioScanAnalytics.track("recognition_failed", properties: ["error_domain": "ModelLoader", "error_code": 23, "recognition_attempt_id": "scan-a"])
        precondition(last("$exception").properties["error_code"] as? Int == 23)
        precondition(last("$exception").properties["recognition_attempt_id"] as? String == "scan-a")
        precondition(last("$exception").properties["$app_namespace"] as? String == "test.app")
        let exceptions = sdk.events.filter { $0.name == "$exception" }.count
        BioScanAnalytics.track("recognition_cancelled")
        BioScanAnalytics.track("recognition_blocked")
        precondition(sdk.events.filter { $0.name == "$exception" }.count == exceptions)
        BioScanAnalytics.track("sound_listen_start")
        precondition(last(BioScanBehaviorEvent.recognitionEntrySelected).properties["recognition_mode"] as? String == "sound")
        BioScanAnalytics.track("favorite_remove")
        precondition(last(BioScanBehaviorEvent.resultFavoriteChanged).properties["is_favorite"] as? Bool == false)
        print("PASS: 并发付费会话 ID、pending 终态、重复结果过滤、识别异常与错误码、App 属性、行为归一化")
    }
}
