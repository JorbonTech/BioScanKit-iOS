import Foundation

// MARK: - Routes document

public struct RelatedRoutesDocument: Decodable, Sendable {
    public let version: Int?
    public let routes: [String: [RelatedRoute]]

    public init(version: Int?, routes: [String: [RelatedRoute]]) {
        self.version = version
        self.routes = routes
    }
}

public struct RelatedRoute: Decodable, Sendable {
    /// `taxon` routes follow the identified group; `context` routes follow the
    /// state of the identification itself (for example an unmatched taxon).
    public let trigger: String
    public let match: [String]
    public let apps: [RelatedToolEntry]
    public let minConfidence: Double?
    public let maxConfidence: Double?
    public let isEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case trigger
        case match
        case apps
        case minConfidence = "min_confidence"
        case maxConfidence = "max_confidence"
        case isEnabled = "is_enabled"
    }

    public init(
        trigger: String,
        match: [String],
        apps: [RelatedToolEntry],
        minConfidence: Double? = nil,
        maxConfidence: Double? = nil,
        isEnabled: Bool = true
    ) {
        self.trigger = trigger
        self.match = match
        self.apps = apps
        self.minConfidence = minConfidence
        self.maxConfidence = maxConfidence
        self.isEnabled = isEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trigger = try container.decodeIfPresent(String.self, forKey: .trigger) ?? "taxon"
        match = try container.decodeIfPresent([String].self, forKey: .match) ?? []
        apps = try container.decodeIfPresent([RelatedToolEntry].self, forKey: .apps) ?? []
        minConfidence = try container.decodeIfPresent(Double.self, forKey: .minConfidence)
        maxConfidence = try container.decodeIfPresent(Double.self, forKey: .maxConfidence)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
}

public struct RelatedToolEntry: Decodable, Sendable {
    public let id: String
    public let actionKey: String?
    public let detailKey: String?

    enum CodingKeys: String, CodingKey {
        case id
        case actionKey = "action_key"
        case detailKey = "detail_key"
    }

    public init(id: String, actionKey: String? = nil, detailKey: String? = nil) {
        self.id = id
        self.actionKey = actionKey
        self.detailKey = detailKey
    }
}

// MARK: - Resolved tool

public struct RelatedTool: Identifiable, Sendable {
    public let id: String
    public let name: String
    /// Action-first line, for example "Cross-check in a mushroom guide".
    public let action: String
    /// Secondary line, for example "Mr.Mushroom · offline field guide".
    public let detail: String
    public let destination: URL
    public let imageName: String?
    public let accentHex: String?
    public let backgroundHexes: [String]
}

// MARK: - Recommendation

public struct RelatedToolsRecommendation: Sendable {
    public enum Variant: Sendable {
        /// Confidence is high enough to trust the identification: the panel is a
        /// footnote placed after the species overview.
        case related
        /// Confidence is too low to confirm the species: the panel moves above
        /// the species header and gains a headline plus a retake action.
        case caution
    }

    public let variant: Variant
    public let confidence: Double
    public let taxon: RelatedTaxon
    public let tools: [RelatedTool]

    public var hasTools: Bool { !tools.isEmpty }
}

// MARK: - Exposure

/// Keeps the panel from turning into wallpaper.
///
/// One rule: an app is offered at most `weeklyLimit` times in any rolling seven
/// days. A session only decides how often that counter moves — once per app per
/// process — so re-evaluating a result page can never make a row disappear
/// mid-render.
///
/// When every tool is suppressed the caution variant still renders: the caveat
/// and the retake row matter more than the offer.
public final class RelatedToolsExposure: @unchecked Sendable {
    public static let shared = RelatedToolsExposure()

    public static let weeklyLimit = 3
    public static let sessionLimit = 2
    public static let window: TimeInterval = 7 * 24 * 60 * 60

    private enum Key {
        static let shown = "bioscan.relatedTools.exposure"
    }

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var history: [String: [Date]]?
    private var sessionContexts: [String: Set<String>] = [:]
    private var recordedThisSession: Set<String> = []

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// - Parameter contextID: identifies the screen the offer would appear on.
    ///   Re-evaluating the same screen must not spend the allowance, so the
    ///   session limit counts distinct contexts, not renders.
    public func canShow(_ appID: String, contextID: String? = nil, now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        // 已展示的结果保持稳定，达到周限额只阻止新的结果页。
        if let contextID, sessionContexts[appID, default: []].contains(contextID) {
            return true
        }
        guard historyLocked(now: now)[appID, default: []].count < Self.weeklyLimit else {
            return false
        }
        guard let contextID else { return true }
        let contexts = sessionContexts[appID] ?? []
        return contexts.contains(contextID) || contexts.count < Self.sessionLimit
    }

    /// Call when the panel actually appeared, never when it was merely computed.
    public func record(_ appIDs: [String], contextID: String? = nil, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        var history = historyLocked(now: now)
        var changed = false
        for appID in appIDs {
            let token = "\(appID)#\(contextID ?? "-")"
            guard !recordedThisSession.contains(token) else { continue }
            recordedThisSession.insert(token)
            if let contextID {
                sessionContexts[appID, default: []].insert(contextID)
            } else {
                sessionContexts[appID, default: []].insert("-")
            }
            history[appID, default: []].append(now)
            changed = true
        }
        guard changed else { return }
        self.history = history
        let raw = history.mapValues { $0.map(\.timeIntervalSince1970) }
        defaults.set(raw, forKey: Key.shown)
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        recordedThisSession.removeAll()
        sessionContexts.removeAll()
        history = [:]
        defaults.removeObject(forKey: Key.shown)
    }

    private func historyLocked(now: Date) -> [String: [Date]] {
        if let history {
            let recent = history.mapValues { dates in
                dates.filter { now.timeIntervalSince($0) < Self.window }
            }
            self.history = recent
            return recent
        }
        let raw = defaults.dictionary(forKey: Key.shown) as? [String: [Double]] ?? [:]
        var loaded: [String: [Date]] = [:]
        for (appID, stamps) in raw {
            let recent = stamps
                .map { Date(timeIntervalSince1970: $0) }
                .filter { now.timeIntervalSince($0) < Self.window }
            if !recent.isEmpty { loaded[appID] = recent }
        }
        history = loaded
        return loaded
    }
}

// MARK: - Recommender

public enum RelatedToolsRecommender {
    /// The single line between "related" and "caution", shared by every host.
    ///
    /// 0.45 matches what four of the six apps already used at their own scan
    /// gate. A host whose gate differs MUST pass its own value as `threshold`:
    /// the panel and the page it sits on cannot disagree about whether the
    /// identification is trustworthy.
    public static let lowConfidenceThreshold = 0.45
    public static let maxRelatedTools = 2
    public static let maxCautionTools = 1

    /// Resolves the tools a host should show for one identification.
    ///
    /// - Parameters:
    ///   - hostAppID: the host's id in `RecommendedApps.json` / `RelatedRoutes.json`.
    ///   - taxon: classified group of the identification.
    ///   - confidence: top candidate confidence in 0...1.
    ///   - threshold: the host's own low-confidence gate. Pass it whenever the
    ///     host routes on a different number, so the panel never contradicts
    ///     the page around it.
    ///   - suppressedAppIDs: apps the host must not offer for this result, for
    ///     example the mushroom guide when the species is high risk.
    /// - Returns: `nil` only when confidence is trustworthy and nothing matched,
    ///   so a low-confidence result always gets its caution panel.
    public static func recommend(
        hostAppID: String,
        taxon: RelatedTaxon,
        confidence: Double,
        threshold: Double = lowConfidenceThreshold,
        suppressedAppIDs: Set<String> = [],
        exposure: RelatedToolsExposure? = .shared,
        contextID: String? = nil,
        now: Date = Date(),
        bundle: Bundle = .main,
        preferredLanguages: [String] = RecommendedAppsLoader.mainAppPreferredLanguages()
    ) -> RelatedToolsRecommendation? {
        let catalogue = catalogue(
            bundle: bundle,
            excluding: hostAppID,
            preferredLanguages: preferredLanguages
        )
        let recommendation = resolve(
            routes: routes(bundle: bundle)[hostAppID] ?? [],
            catalogue: catalogue,
            taxon: taxon,
            confidence: confidence,
            threshold: threshold,
            suppressedAppIDs: suppressedAppIDs,
            isAppAllowed: { exposure?.canShow($0, contextID: contextID, now: now) ?? true }
        )

        return recommendation
    }

    /// The app catalogue is decoded once per bundle and language list: the
    /// panel is a computed property, so it is evaluated on every scroll frame.
    private static func catalogue(
        bundle: Bundle,
        excluding hostAppID: String,
        preferredLanguages: [String]
    ) -> [RecommendedApp] {
        let key = "\(bundle.bundlePath)|\(hostAppID)|\(preferredLanguages.joined(separator: ","))"
        if let cached = catalogueCache.get(key) { return cached }
        let apps = RecommendedAppsLoader.load(
            bundle: bundle,
            excluding: hostAppID,
            preferredLanguages: preferredLanguages
        )
        catalogueCache.set(apps, for: key)
        return apps
    }

    /// Pure resolution step, so the routing rules can be tested without a bundle.
    public static func resolve(
        routes: [RelatedRoute],
        catalogue: [RecommendedApp],
        taxon: RelatedTaxon,
        confidence: Double,
        threshold: Double = lowConfidenceThreshold,
        suppressedAppIDs: Set<String> = [],
        isAppAllowed: (String) -> Bool = { _ in true }
    ) -> RelatedToolsRecommendation? {
        let clamped = min(max(confidence, 0), 1)
        let variant: RelatedToolsRecommendation.Variant =
            clamped < threshold ? .caution : .related

        let appsByID = Dictionary(
            catalogue.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var seen = Set<String>()
        var resolved: [RelatedTool] = []

        for route in routes where route.isEnabled {
            guard route.match.contains(taxon.rawValue) else { continue }
            if let maxConfidence = route.maxConfidence, clamped >= maxConfidence { continue }
            if let minConfidence = route.minConfidence, clamped < minConfidence { continue }

            for entry in route.apps {
                guard !seen.contains(entry.id) else { continue }
                guard !suppressedAppIDs.contains(entry.id) else { continue }
                // 先过滤频控，再截取数量，允许后续候选补位。
                guard isAppAllowed(entry.id) else { continue }
                // Without action copy the row title would degrade to the app
                // name, which is exactly the "advert" framing the panel avoids.
                guard entry.actionKey?.isEmpty == false else { continue }
                guard let app = appsByID[entry.id] else { continue }
                seen.insert(entry.id)
                resolved.append(
                    RelatedTool(
                        id: app.id,
                        name: app.name,
                        action: localizedCopy(entry.actionKey, fallback: app.name),
                        detail: localizedCopy(entry.detailKey, fallback: app.subtitle),
                        destination: app.appStoreURL,
                        imageName: app.imageName,
                        accentHex: app.accentHex,
                        backgroundHexes: app.backgroundHexes
                    )
                )
            }
        }

        let limit = variant == .caution ? maxCautionTools : maxRelatedTools
        let tools = Array(resolved.prefix(limit))

        guard !tools.isEmpty || variant == .caution else { return nil }
        return RelatedToolsRecommendation(
            variant: variant,
            confidence: clamped,
            taxon: taxon,
            tools: tools
        )
    }

    /// Reads `RelatedRoutes.json`. Routes are language-independent: only the
    /// action and detail copy is localized, through the settings bundle.
    public static func routes(bundle: Bundle = .main) -> [String: [RelatedRoute]] {
        let key = bundle.bundlePath
        if let cached = routesCache.get(key) { return cached }

        guard let url = bundle.url(forResource: "RelatedRoutes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(RelatedRoutesDocument.self, from: data) else {
            routesCache.set([:], for: key)
            return [:]
        }

        routesCache.set(document.routes, for: key)
        return document.routes
    }

    /// Test seam: drops the cached routes so a fixture bundle can be reloaded.
    static func resetRoutesCache() {
        routesCache.removeAll()
        catalogueCache.removeAll()
    }

    private static func localizedCopy(_ key: String?, fallback: String) -> String {
        guard let key, !key.isEmpty else { return fallback }
        let value = BioScanSettingsL10n.string(key)
        return value == key ? fallback : value
    }

    private static let routesCache = RoutesCache()
    private static let catalogueCache = CatalogueCache()
}

/// Small lock-guarded caches: routes and the app catalogue never change while
/// a process is running, and both are read from the render path.
private final class CatalogueCache: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: [RecommendedApp]] = [:]

    func get(_ key: String) -> [RecommendedApp]? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func set(_ apps: [RecommendedApp], for key: String) {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = apps
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }
}

private final class RoutesCache: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: [String: [RelatedRoute]]] = [:]

    func get(_ key: String) -> [String: [RelatedRoute]]? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func set(_ routes: [String: [RelatedRoute]], for key: String) {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = routes
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }
}
