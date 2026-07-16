#if !SKIP_BRIDGE
import Foundation
import SwiftUI // for `UIApplication.shared.androidActivity` on Android
#if !SKIP
#if canImport(SuperwallKit)
import SuperwallKit
#endif
#else
import android.app.Application
import android.app.Activity
import com.superwall.sdk.Superwall
import com.superwall.sdk.misc.ActivityProvider
// register/identify/setUserAttributes are top-level extension functions, so
// each is imported by name.
import com.superwall.sdk.paywall.presentation.register
import com.superwall.sdk.identity.identify
import com.superwall.sdk.identity.setUserAttributes
#endif

#if SKIP
/// Supplies Superwall with the current Android `Activity`. `configure` runs from
/// SwiftUI's launch task, after the host activity has resumed, so Superwall's own
/// lifecycle tracking misses it ("Current Activity is null"); SkipUI holds the
/// live reference instead.
///
/// `// SKIP @nobridge`: this is an Android-internal helper (its
/// `getCurrentActivity()` returns the Android `Activity` type), never called
/// from Swift, so it must be excluded from skip-fuse's bridge generation —
/// otherwise the generator errors with "'Activity' does not appear to be a
/// bridged type".
// SKIP @nobridge
final class SkipSuperwallActivityProvider: ActivityProvider {
    // `override` is emitted only for Android (skipstone can't infer it from the
    // external Kotlin interface); this block never reaches the Swift compiler.
    public override func getCurrentActivity() -> Activity? {
        UIApplication.shared.androidActivity
    }
}
#endif

// MARK: - SuperwallManager

/// Cross-platform wrapper around the native Superwall paywall SDKs.
///
/// On Apple platforms this drives `SuperwallKit` (`import SuperwallKit`); on
/// Android it drives the `com.superwall.sdk:superwall-android` SDK
/// (`com.superwall.sdk.Superwall`). Both expose the same Swift surface — modelled
/// on the Superwall iOS API — so callers stay platform-agnostic, mirroring the
/// `CrispChat` / `RevenueCatFuse` / `SkipFirebase*` wrappers.
///
/// Superwall presents its own paywalls (a dedicated window on iOS, a
/// `SuperwallPaywallActivity` on Android), so ``register(placement:params:feature:)``
/// needs no host view controller from the caller. With no `PurchaseController`
/// supplied at ``configure(apiKey:)``, Superwall handles StoreKit / Billing and
/// subscription status automatically.
///
/// Typical lifecycle:
/// ```swift
/// SuperwallManager.shared.configure(apiKey: "pk_…")          // once, at launch
/// SuperwallManager.shared.identify(userID: "uid123")         // after sign-in
/// SuperwallManager.shared.setUserAttributes(["plan": "free"])
/// SuperwallManager.shared.register(placement: "campaign_trigger") {
///     // runs when the user is (or becomes) entitled
/// }
/// SuperwallManager.shared.reset()                            // on sign-out
/// ```
public struct SuperwallManager: @unchecked Sendable {
    public static let shared = SuperwallManager()

    private init() {}

    /// Configure Superwall with the public API key from the dashboard.
    /// Idempotent-ish — call once early in app launch, before any
    /// ``register(placement:params:feature:)``.
    public func configure(apiKey: String) {
        #if !SKIP
        #if canImport(SuperwallKit)
        Superwall.configure(apiKey: apiKey)
        #endif
        #else
        // Android `configure` needs an `Application` and an activity provider (see
        // SkipSuperwallActivityProvider). The two nils are purchaseController/options.
        let context = ProcessInfo.processInfo.androidContext
        let application = context.applicationContext as! Application
        Superwall.configure(application, apiKey, nil, nil, SkipSuperwallActivityProvider())
        #endif
    }

    /// Register a placement. When that placement is attached to a campaign on
    /// the Superwall dashboard it can trigger a paywall and optionally gate the
    /// `feature` block. `feature` runs immediately when the user is already
    /// entitled (or after a successful purchase/restore); it is skipped if the
    /// user dismisses a gating paywall.
    @MainActor
    public func register(placement: String,
                         params: [String: String]? = nil,
                         feature: @escaping () -> Void = {}) {
        #if !SKIP
        #if canImport(SuperwallKit)
        let anyParams: [String: Any]? = params
        Superwall.shared.register(placement: placement, params: anyParams, feature: feature)
        #endif
        #else
        // `.kotlin()` yields a star-projected map; cast to the `Map<String, Any>`
        // that `register(params:)` expects.
        Superwall.instance.register(placement: placement, params: params?.kotlin() as? Map<String, Any>, feature: feature)
        #endif
    }

    /// Alias the current anonymous Superwall ID with your own user ID so the
    /// user's assigned paywalls and attributes follow them across devices.
    /// Call as soon as you have a stable user identity (e.g. after sign-in).
    public func identify(userID: String) {
        #if !SKIP
        #if canImport(SuperwallKit)
        Superwall.shared.identify(userId: userID)
        #endif
        #else
        Superwall.instance.identify(userID)
        #endif
    }

    /// Set user attributes for audience filtering / analytics on the dashboard.
    /// Existing attributes are overwritten; others are left untouched.
    public func setUserAttributes(_ attributes: [String: String]) {
        #if !SKIP
        #if canImport(SuperwallKit)
        let anyAttributes: [String: Any] = attributes
        Superwall.shared.setUserAttributes(anyAttributes)
        #endif
        #else
        Superwall.instance.setUserAttributes(attributes.kotlin() as Map<String, Any>)
        #endif
    }

    /// Reset the on-device Superwall user (identity, attributes, assignments).
    /// Call on sign-out so the next user doesn't inherit the previous session.
    public func reset() {
        #if !SKIP
        #if canImport(SuperwallKit)
        Superwall.shared.reset()
        #endif
        #else
        Superwall.instance.reset()
        #endif
    }
}
#endif
