import Foundation

@main
struct PendingCreditPurchasesChecks {
    @MainActor
    static func main() {
        let suite = "PendingCreditPurchasesChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let ledger = CreditLedger(configuration: CreditStorageConfiguration(
            freeCredits: .remaining(key: "free", initialAllowance: 0),
            paidCreditsKey: "paid", lifetimeCache: .boolean(key: "lifetime"),
            processedTransactionIDsKey: "processed"
        ), defaults: defaults)
        let now = Date(timeIntervalSince1970: 2_000_000)
        var pending = PendingCreditPurchases(defaults: defaults, key: "pending")
        // 旧收据或未进入等待状态的购买不得产生新额度。
        precondition(!pending.deliver(productID: "five", transactionID: "old", purchaseDate: now, amount: 5, ledger: ledger))
        pending.record(productID: "five", now: now)
        precondition(!pending.deliver(productID: "five", transactionID: "old", purchaseDate: now.addingTimeInterval(-60), amount: 5, ledger: ledger))
        precondition(ledger.balance.paid == 0)
        // 等待状态跨进程保留；重复请求不能把原先的发起时间覆盖掉。
        pending = PendingCreditPurchases(defaults: defaults, key: "pending")
        pending.record(productID: "five", now: now.addingTimeInterval(600))
        precondition(pending.deliver(productID: "five", transactionID: "approved-1", purchaseDate: now, amount: 5, ledger: ledger))
        precondition(ledger.balance.paid == 5)
        precondition(!pending.deliver(productID: "five", transactionID: "approved-1", purchaseDate: now, amount: 5, ledger: ledger))
        precondition(ledger.balance.paid == 5)
        // 两个商品独立，20次包能正确发放；重复刷新不重复充值。
        pending.record(productID: "twenty", now: now)
        precondition(pending.deliver(productID: "twenty", transactionID: "approved-2", purchaseDate: now, amount: 20, ledger: ledger))
        precondition(ledger.balance.paid == 25)
        pending.finish(productID: "five")
        precondition(!pending.deliver(productID: "five", transactionID: "unrequested", purchaseDate: now, amount: 5, ledger: ledger))
        pending.finish(productID: "twenty")
        precondition(!pending.deliver(productID: "twenty", transactionID: "approved-2", purchaseDate: now, amount: 20, ledger: ledger))
        // 无交易、被拒绝的请求不发额度；空交易ID始终被拒绝。
        pending.record(productID: "rejected", now: now)
        precondition(!pending.deliver(productID: "rejected", transactionID: "", purchaseDate: now, amount: 20, ledger: ledger))
        precondition(ledger.balance.paid == 25)
        print("PendingCreditPurchases checks passed")
    }
}
