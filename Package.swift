// swift-tools-version: 6.2
// This is a Skip (https://skip.tools) package.
import PackageDescription

// SkipSuperwall wraps the native Superwall paywall SDKs — SuperwallKit on Apple
// platforms and the `com.superwall.sdk:superwall-android` Android SDK on
// Android — behind a single cross-platform Swift API, in the same style as
// skip-crisp / skip-revenue / skip-firebase. The public surface mirrors the
// Superwall iOS SDK (configure / register / identify / setUserAttributes /
// reset) so app code stays platform-agnostic.
let package = Package(
    name: "skip-superwall",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SkipSuperwall", type: .dynamic, targets: ["SkipSuperwall"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "1.7.4"),
        .package(url: "https://source.skip.tools/skip-foundation.git", from: "1.0.0"),
        .package(url: "https://source.skip.tools/skip-ui.git", from: "1.0.0"),
        // Superwall iOS SDK (SwiftPM product `SuperwallKit`). iOS-only —
        // SuperwallKit imports UIKit unconditionally, so it does not build on
        // macOS; the wrapper gates its use behind `#if canImport(SuperwallKit)`.
        // Android pulls the `com.superwall.sdk:superwall-android` Maven artifact
        // via Sources/SkipSuperwall/Skip/skip.yml. `from: "4.0.0"` tracks the
        // current 4.x line.
        .package(url: "https://github.com/superwall/Superwall-iOS.git", from: "4.0.0"),
    ],
    targets: [
        .target(name: "SkipSuperwall", dependencies: [
            .product(name: "SkipFoundation", package: "skip-foundation"),
            .product(name: "SkipUI", package: "skip-ui"),
            .product(name: "SuperwallKit", package: "Superwall-iOS", condition: .when(platforms: [.iOS])),
        ], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .testTarget(name: "SkipSuperwallTests", dependencies: [
            "SkipSuperwall",
            .product(name: "SkipTest", package: "skip"),
        ], plugins: [.plugin(name: "skipstone", package: "skip")]),
    ]
)

if Context.environment["SKIP_BRIDGE"] ?? "0" != "0" {
    package.dependencies += [
        .package(url: "https://source.skip.tools/skip-bridge.git", "0.0.0"..<"2.0.0"),
        .package(url: "https://source.skip.tools/skip-fuse-ui.git", from: "1.0.0")
    ]
    package.targets.forEach({ target in
        target.dependencies += [
            .product(name: "SkipBridge", package: "skip-bridge"),
            .product(name: "SkipFuseUI", package: "skip-fuse-ui")
        ]
    })
    // all library types must be dynamic to support bridging
    package.products = package.products.map({ product in
        guard let libraryProduct = product as? Product.Library else { return product }
        return .library(name: libraryProduct.name, type: .dynamic, targets: libraryProduct.targets)
    })
}
