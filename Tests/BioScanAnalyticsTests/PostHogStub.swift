import Foundation

// 仅替代传输层：回归测试直接编译生产 BioScanAnalytics，绝不发送网络事件。
public final class PostHogConfig {
    public init(projectToken: String, host: String) {}
    public var debug = false
    public var captureApplicationLifecycleEvents = false
    public var captureScreenViews = false
    public var captureElementInteractions = false
    public var sessionReplay = false
    public var errorTrackingConfig = ErrorConfig()
    public var sessionReplayConfig = ReplayConfig()
    public func setBeforeSend(_ callback: @escaping (Event) -> Event?) { beforeSend = callback }
    public var beforeSend: ((Event) -> Event?)?
}
public struct ErrorConfig { public var autoCapture = false }
public struct ReplayConfig {
    public var screenshotMode = false
    public var maskAllTextInputs = true
    public var maskAllImages = true
    public var maskAllSandboxedViews = true
}
public final class Event {
    public var properties: [String: Any]
    public let name: String
    public init(_ name: String, _ properties: [String: Any]) { self.name = name; self.properties = properties }
}
public final class PostHogSDK {
    public static let shared = PostHogSDK()
    public var events: [Event] = []
    public var config: PostHogConfig?
    public func setup(_ config: PostHogConfig) { self.config = config }
    public func register(_ properties: [String: Any]) {}
    public func capture(_ name: String, properties: [String: Any]?) {
        let event = Event(name, properties ?? [:])
        if let processed = config?.beforeSend?(event) { events.append(processed) }
    }
    public func captureException(_ error: Error, properties: [String: Any]?) { capture("$exception", properties: properties) }
    public func screen(_ name: String, properties: [String: Any]) { capture("$screen", properties: properties) }
    public func identify(_ id: String, userProperties: [String: Any]) {}
    public func reset() {}
    public func optIn() {}
    public func optOut() {}
    public func flush() {}
}
