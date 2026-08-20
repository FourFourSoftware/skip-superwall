import XCTest
@testable import SkipSuperwall

final class SkipSuperwallTests: XCTestCase {
    /// The shared instance is a stable singleton. Configuration / register /
    /// identity calls forward to the native SDKs, so behavioural coverage lives
    /// in the app's integration; here we just guard the wrapper's basic shape.
    func testSharedInstanceIsStable() {
        let a = SuperwallManager.shared
        let b = SuperwallManager.shared
        XCTAssertTrue(type(of: a) == type(of: b))
    }

    /// LIV-895: before `configure(apiKey:)` runs, every lifecycle and
    /// presentation call must be a safe no-op. On Android, touching the SDK
    /// while unconfigured throws `IllegalStateException`, which the generated
    /// bridge escalates to a fatal `try!` crash — so these calls may never
    /// reach the SDK.
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
}
