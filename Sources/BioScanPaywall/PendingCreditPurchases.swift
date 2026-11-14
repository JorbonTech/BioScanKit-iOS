import Foundation

/// 只补发明确进入等待批准状态的购买；不把旧收据当成新购买重新发放。
@MainActor
public final class PendingCreditPurchases {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String) {
        self.defaults = defaults
        self.key = key
    }

    public func record(productID: String, now: Date = Date()) {
        var pending = defaults.dictionary(forKey: key) as? [String: Date] ?? [:]
        if pending[productID] == nil { pending[productID] = now }
        defaults.set(pending, forKey: key)
    }

    @discardableResult
    public func deliver(
        productID: String, transactionID: String, purchaseDate: Date,
        amount: Int, ledger: CreditLedger
    ) -> Bool {
        let pending = defaults.dictionary(forKey: key) as? [String: Date] ?? [:]
        guard let requestedAt = pending[productID], purchaseDate >= requestedAt.addingTimeInterval(-5) else {
            return false
        }
        // CreditLedger 按交易 ID 去重，即使回调、前台刷新和重启重复出现也只发放一次。
        return ledger.addPurchasedCredits(amount, transactionID: transactionID)
    }

    public func finish(productID: String) {
        var pending = defaults.dictionary(forKey: key) as? [String: Date] ?? [:]
        pending.removeValue(forKey: productID)
        defaults.set(pending, forKey: key)
    }
}
