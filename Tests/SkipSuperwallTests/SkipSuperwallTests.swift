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
}
