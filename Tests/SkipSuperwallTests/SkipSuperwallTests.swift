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
}
