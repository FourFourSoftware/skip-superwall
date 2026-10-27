import XCTest
@testable import SkipSuperwall
#if !SKIP && os(macOS) && canImport(SuperwallKit)
import SuperwallKit
#endif

final class SkipSuperwallTests: XCTestCase {
    /// The shared instance is a stable singleton. Configuration / register /
    /// identity calls forward to the native SDKs, so behavioural coverage lives
    /// in the app's integration; here we just guard the wrapper's basic shape.
    func testSharedInstanceIsStable() {
        let a = SuperwallManager.shared
        let b = SuperwallManager.shared
        XCTAssertTrue(type(of: a) == type(of: b))
    }

    /// Before `configure(apiKey:)` runs, every call must be a safe no-op —
    /// on Android an unconfigured SDK call would crash via the bridge's `try!`.
    @MainActor
    func testUnconfiguredLifecycleCallsAreSafeNoOps() {
        let manager = SuperwallManager.shared
        XCTAssertFalse(manager.isConfigured)
        manager.identify(userID: "user-123")
        manager.setUserAttributes(["plan": "free"])
        manager.reset()
        var featureRan = false
        manager.register(placement: "test_placement") { featureRan = true }
        XCTAssertFalse(featureRan, "register must not grant entitlement while unconfigured")
        XCTAssertFalse(manager.isConfigured)
    }

    /// The raw values are a documented contract: handlers may round-trip the
    /// outcome across the bridge as an integer, and both platform adapters map
    /// from these cases.
    func testPurchaseOutcomeRawValuesAreStable() {
        XCTAssertEqual(SuperwallPurchaseOutcome.purchased.rawValue, 0)
        XCTAssertEqual(SuperwallPurchaseOutcome.restored.rawValue, 1)
        XCTAssertEqual(SuperwallPurchaseOutcome.cancelled.rawValue, 2)
        XCTAssertEqual(SuperwallPurchaseOutcome.pending.rawValue, 3)
        XCTAssertEqual(SuperwallPurchaseOutcome.failed.rawValue, 4)
        XCTAssertEqual(SuperwallPurchaseOutcome(rawValue: 1), SuperwallPurchaseOutcome.restored)
        XCTAssertNil(SuperwallPurchaseOutcome(rawValue: 5))
    }

    /// `setPurchaseController` must be callable before `configure` (that is the
    /// supported ordering) and must retain the handlers for configure to install.
    func testSetPurchaseControllerBeforeConfigureRetainsHandlers() async {
        let manager = SuperwallManager.shared
        XCTAssertFalse(manager.isConfigured)
        manager.setPurchaseController(
            purchaseFromAppStore: { productID in
                productID == "monthly" ? SuperwallPurchaseOutcome.purchased : SuperwallPurchaseOutcome.failed
            },
            purchaseFromGooglePlay: { _, basePlanID, offerID in
                offerID != nil ? SuperwallPurchaseOutcome.pending : (basePlanID != nil ? SuperwallPurchaseOutcome.purchased : SuperwallPurchaseOutcome.cancelled)
            },
            restorePurchases: { true }
        )

        let handlers = SuperwallPurchaseHandlers.shared
        XCTAssertTrue(handlers.isRegistered)

        guard let appStore = handlers.purchaseFromAppStore,
              let googlePlay = handlers.purchaseFromGooglePlay,
              let restore = handlers.restorePurchases else {
            XCTFail("handlers must be retained until configure installs the adapter")
            return
        }
        let purchased = await appStore("monthly")
        XCTAssertEqual(purchased, SuperwallPurchaseOutcome.purchased)
        let failed = await appStore("unknown")
        XCTAssertEqual(failed, SuperwallPurchaseOutcome.failed)
        let cancelled = await googlePlay("monthly", nil, nil)
        XCTAssertEqual(cancelled, SuperwallPurchaseOutcome.cancelled)
        let withBasePlan = await googlePlay("monthly", "base", nil)
        XCTAssertEqual(withBasePlan, SuperwallPurchaseOutcome.purchased)
        let withOffer = await googlePlay("monthly", "base", "offer")
        XCTAssertEqual(withOffer, SuperwallPurchaseOutcome.pending)
        let restored = await restore()
        XCTAssertTrue(restored)
    }

    /// A second registration replaces the previous handlers wholesale.
    func testSetPurchaseControllerReplacesPreviousHandlers() async {
        let manager = SuperwallManager.shared
        manager.setPurchaseController(
            purchaseFromAppStore: { _ in SuperwallPurchaseOutcome.failed },
            purchaseFromGooglePlay: { _, _, _ in SuperwallPurchaseOutcome.failed },
            restorePurchases: { false }
        )
        manager.setPurchaseController(
            purchaseFromAppStore: { _ in SuperwallPurchaseOutcome.purchased },
            purchaseFromGooglePlay: { _, _, _ in SuperwallPurchaseOutcome.purchased },
            restorePurchases: { true }
        )

        let handlers = SuperwallPurchaseHandlers.shared
        guard let appStore = handlers.purchaseFromAppStore,
              let restore = handlers.restorePurchases else {
            XCTFail("handlers must be registered")
            return
        }
        let outcome = await appStore("any")
        XCTAssertEqual(outcome, SuperwallPurchaseOutcome.purchased)
        let restored = await restore()
        XCTAssertTrue(restored)
    }

    /// Before `configure(apiKey:)` runs, pushing subscription status must be a
    /// safe no-op (LIV-895 guard pattern) — on Android an unconfigured SDK call
    /// would crash via the bridge's `try!`.
    func testUnconfiguredSetSubscriptionStatusIsSafeNoOp() {
        let manager = SuperwallManager.shared
        XCTAssertFalse(manager.isConfigured)
        manager.setSubscriptionStatus(activeEntitlements: ["pro"])
        manager.setSubscriptionStatus(activeEntitlements: [])
        XCTAssertFalse(manager.isConfigured)
    }

    #if !SKIP && os(macOS) && canImport(SuperwallKit)
    /// The Mac sheet must grant the feature exactly when `register` would.
    func testPaywallSheetGrantsAccessLikeRegister() {
        XCTAssertTrue(SuperwallPaywallSheet.grantsAccess(.restored, closeReason: .systemLogic, featureGating: .gated))
        XCTAssertFalse(SuperwallPaywallSheet.grantsAccess(.declined, closeReason: .manualClose, featureGating: .gated))
        XCTAssertTrue(SuperwallPaywallSheet.grantsAccess(.declined, closeReason: .manualClose, featureGating: .nonGated))
        XCTAssertFalse(SuperwallPaywallSheet.grantsAccess(.declined, closeReason: .forNextPaywall, featureGating: .nonGated))
    }
    #endif
}
