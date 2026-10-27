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
        // Superwall iOS SDK (SwiftPM product `SuperwallKit`), used on iOS and
        // native macOS. Released 4.x imports UIKit unconditionally and does not
        // build on macOS, so this pins the head of superwall/Superwall-iOS#548
        // (`brian/native-macos`, AppKit support for macOS 12+). Switch back to
        // a version requirement once that PR ships in a release. The wrapper
        // still gates its use behind `#if canImport(SuperwallKit)`.
        // Android pulls the `com.superwall.sdk:superwall-android` Maven artifact
        // via Sources/SkipSuperwall/Skip/skip.yml.
        .package(url: "https://github.com/superwall/Superwall-iOS.git", revision: "d17752af85c9f035b9a52ba0114d0c69df34e0d0"),
    ],
    targets: [
        .target(name: "SkipSuperwall", dependencies: [
            .product(name: "SkipFoundation", package: "skip-foundation"),
            .product(name: "SkipUI", package: "skip-ui"),
            .product(name: "SuperwallKit", package: "Superwall-iOS", condition: .when(platforms: [.iOS, .macOS])),
        ], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .testTarget(name: "SkipSuperwallTests", dependencies: [
            "SkipSuperwall",
            .product(name: "SkipTest", package: "skip"),
        ], plugins: [.plugin(name: "skipstone", package: "skip")]),
    ]
)

if Context.environment["SKIP_BRIDGE"] ?? "0" != "0" {
    package.dependencies += [
        .package(url: "https://source.skip.tools/skip-fuse.git", "0.0.0"..<"2.0.0"),
        .package(url: "https://source.skip.tools/skip-fuse-ui.git", from: "1.0.0")
    ]
    package.targets.forEach({ target in
        target.dependencies += [
            .product(name: "SkipFuse", package: "skip-fuse"),
            .product(name: "SkipFuseUI", package: "skip-fuse-ui")
        ]
    })
    // all library types must be dynamic to support bridging
    package.products = package.products.map({ product in
        guard let libraryProduct = product as? Product.Library else { return product }
        return .library(name: libraryProduct.name, type: .dynamic, targets: libraryProduct.targets)
    })
}
