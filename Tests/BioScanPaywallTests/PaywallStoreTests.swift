import XCTest
@testable import BioScanPaywall

@MainActor
final class PaywallStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "PaywallStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testConsumableWithoutTransactionIDDoesNotDeliverCredits() async {
        let store = makeStore(transactionID: nil)

        await store.load()
        await store.purchaseSelectedProduct()

        XCTAssertEqual(store.creditBalance.paid, 0)
        XCTAssertEqual(store.operation, .idle)
        XCTAssertEqual(store.notice?.title, "Purchase Failed")
        XCTAssertTrue(store.notice?.message.contains("could not be confirmed") == true)
    }

    func testConsumableWithTransactionIDIsDeliveredExactlyOnce() async {
        let store = makeStore(transactionID: "transaction-1")

        await store.load()
        await store.purchaseSelectedProduct()
        XCTAssertEqual(store.creditBalance.paid, 5)
        XCTAssertEqual(store.operation, .succeeded)

        store.clearTransientOperation()
        await store.purchaseSelectedProduct()
        XCTAssertEqual(store.creditBalance.paid, 5)
        XCTAssertEqual(store.notice?.title, "Purchase Failed")
    }

    func testPendingPurchaseDoesNotDeliverCreditsOrShowFailure() async {
        var events: [PaywallEvent] = []
        let store = makeStore(transactionID: nil, pending: true, track: { events.append($0) })
        await store.load()
        await store.purchaseSelectedProduct()
        XCTAssertEqual(store.creditBalance.paid, 0)
        XCTAssertEqual(store.operation, .idle)
        XCTAssertEqual(store.notice?.title, "Waiting for Approval")
        XCTAssertTrue(events.contains(.purchaseBlocked(reason: "payment_pending")))
        XCTAssertFalse(events.contains { if case .purchaseFailed = $0 { return true }; return false })
        XCTAssertFalse(store.recoveryCoordinator?.isOfferPresented ?? false)
    }

    func testPurchaseFailurePreservesSystemErrorAndClearsOnNextAttempt() async {
        var failures: [NSError] = []
        let store = makeStore(transactionID: "retry", failure: NSError(domain: NSURLErrorDomain, code: -1009), track: { _ in })
        await store.load()
        await store.purchaseSelectedProduct()
        if let error = store.lastPurchaseError { failures.append(error) }
        XCTAssertEqual(failures.first?.domain, NSURLErrorDomain)
        XCTAssertEqual(failures.first?.code, -1009)
        await store.purchaseSelectedProduct()
        XCTAssertNil(store.lastPurchaseError)
        XCTAssertEqual(store.creditBalance.paid, 5)
    }

    private func makeStore(
        transactionID: String?, pending: Bool = false, failure: NSError? = nil,
        track: @escaping @MainActor (PaywallEvent) -> Void = { _ in }
    ) -> PaywallStore {
        let product = PaywallProduct(
            id: "credits-5",
            kind: .credits(5),
            title: "Five credits",
            subtitle: "Five identifications"
        )
        var nextFailure = failure
        let client = ClosureBillingClient(
            loadProducts: { _ in
                [BillingProduct(id: product.id, localizedPrice: "$0.99", price: 0.99)]
            },
            purchase: { _ in
                if let error = nextFailure {
                    nextFailure = nil
                    throw error
                }
                if pending { throw PurchasePendingError() }
                return PurchaseResult(
                    wasCancelled: false,
                    transactionID: transactionID,
                    entitlement: .standard
                )
            },
            restorePurchases: { .standard },
            refreshEntitlements: { .standard }
        )
        let ledger = CreditLedger(
            configuration: CreditStorageConfiguration(
                freeCredits: .remaining(key: "free", initialAllowance: 0),
                bonusCreditsKey: "bonus",
                paidCreditsKey: "paid",
                lifetimeCache: .boolean(key: "lifetime"),
                didSeedFreeCreditsKey: "seeded",
                processedTransactionIDsKey: "transactions"
            ),
            defaults: defaults
        )
        return PaywallStore(
            configuration: PaywallConfiguration(
                style: .iNature,
                catalog: PurchaseCatalog(
                    products: [product],
                    lifetimeProductIDs: [],
                    defaultProductID: product.id
                ),
                purchaseRecovery: nil
            ),
            billingClient: client,
            creditLedger: ledger,
            actions: PaywallActions(dismiss: {}, track: track)
        )
    }
}
