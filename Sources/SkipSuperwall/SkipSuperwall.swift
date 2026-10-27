#if !SKIP_BRIDGE
import Foundation
import OSLog
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
import com.superwall.sdk.delegate.PurchaseResult
import com.superwall.sdk.delegate.RestorationResult
import com.superwall.sdk.delegate.subscription_controller.PurchaseController
import com.superwall.sdk.models.entitlements.Entitlement
import com.superwall.sdk.models.entitlements.SubscriptionStatus
import com.android.billingclient.api.ProductDetails
import java.util.LinkedHashSet
#endif

#if SKIP
/// Supplies Superwall with the current Android `Activity`. `configure` runs from
/// SwiftUI's launch task, after the host activity has resumed, so Superwall's own
/// lifecycle tracking misses it ("Current Activity is null"); SkipUI holds the
/// live reference instead.
///
/// `// SKIP @nobridge`: Android-internal and never called from Swift; excluded
/// from bridge generation because skip-fuse can't bridge the `Activity` type.
// SKIP @nobridge
final class SkipSuperwallActivityProvider: ActivityProvider {
    // `override` is emitted only for Android (skipstone can't infer it from the
    // external Kotlin interface); this block never reaches the Swift compiler.
    public override func getCurrentActivity() -> Activity? {
        UIApplication.shared.androidActivity
    }
}
#endif

let logger: Logger = Logger(subsystem: "skip.superwall", category: "SuperwallManager")

// MARK: - Purchase controller surface

/// Cross-platform outcome of an app-implemented purchase, mirroring
/// react-native-superwall's `PurchaseResult`. Raw values are stable so the
/// outcome can round-trip across the bridge as an integer if ever needed:
/// 0 purchased, 1 restored, 2 cancelled, 3 pending, 4 failed.
public enum SuperwallPurchaseOutcome: Int, Sendable {
    case purchased = 0
    case restored = 1
    case cancelled = 2
    case pending = 3
    case failed = 4
}

/// Holds the handlers registered via
/// ``SuperwallManager/setPurchaseController(purchaseFromAppStore:purchaseFromGooglePlay:restorePurchases:)``
/// until ``SuperwallManager/configure(apiKey:)`` runs — both native SDKs only
/// accept a purchase controller at configure time.
// SKIP @nobridge
final class SuperwallPurchaseHandlers: @unchecked Sendable {
    static let shared = SuperwallPurchaseHandlers()

    private init() {}

    var purchaseFromAppStore: ((String) async -> SuperwallPurchaseOutcome)?
    var purchaseFromGooglePlay: ((String, String?, String?) async -> SuperwallPurchaseOutcome)?
    var restorePurchases: (() async -> Bool)?

    var isRegistered: Bool {
        purchaseFromAppStore != nil && purchaseFromGooglePlay != nil && restorePurchases != nil
    }
}

#if !SKIP
#if canImport(SuperwallKit)
/// Adapts the app-registered primitive-typed handlers to SuperwallKit's
/// `PurchaseController`. Installed by `configure(apiKey:)` when handlers were
/// registered beforehand; SuperwallKit retains it for the app's lifetime.
final class AppPurchaseControllerAdapter: PurchaseController {
    private let purchaseHandler: (String) async -> SuperwallPurchaseOutcome
    private let restoreHandler: () async -> Bool

    init(purchaseHandler: @escaping (String) async -> SuperwallPurchaseOutcome,
         restoreHandler: @escaping () async -> Bool) {
        self.purchaseHandler = purchaseHandler
        self.restoreHandler = restoreHandler
    }

    @MainActor
    func purchase(product: StoreProduct) async -> PurchaseResult {
        let outcome = await purchaseHandler(product.productIdentifier)
        switch outcome {
        case .purchased, .restored:
            // SuperwallKit 4.x's PurchaseResult has no restored case; a purchase
            // completed via restoration still unlocks, so report it as purchased.
            return .purchased
        case .cancelled:
            return .cancelled
        case .pending:
            return .pending
        case .failed:
            return .failed(NSError(
                domain: "SkipSuperwall.purchase",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The app's purchase handler reported failure."]
            ))
        }
    }

    @MainActor
    func restorePurchases() async -> RestorationResult {
        let restored = await restoreHandler()
        return restored ? .restored : .failed(nil)
    }
}
#endif
#else
/// Adapts the app-registered primitive-typed handlers to the Android SDK's
/// `PurchaseController` interface.
///
/// `// SKIP @nobridge`: the signature mentions Android types (`Activity`,
/// `ProductDetails`) that skip-fuse can't bridge; Android-internal only.
// SKIP @nobridge
final class SkipSuperwallPurchaseController: PurchaseController {
    // The `activity` param is deliberately unused: the app's handler obtains the
    // current Activity itself, from the same source SkipSuperwallActivityProvider
    // uses. `override` is emitted only for Android (skipstone can't infer it from
    // the external Kotlin interface); this block never reaches the Swift compiler.
    public override func purchase(activity: Activity,
                                  productDetails: ProductDetails,
                                  basePlanId: String?,
                                  offerId: String?) async -> PurchaseResult {
        guard let handler = SuperwallPurchaseHandlers.shared.purchaseFromGooglePlay else {
            return PurchaseResult.Failed("SkipSuperwall: no Google Play purchase handler registered")
        }
        let outcome = await handler(productDetails.productId, basePlanId, offerId)
        switch outcome {
        case .purchased, .restored:
            // superwall-android 2.7.x's PurchaseResult has no restored case; a
            // purchase completed via restoration still unlocks, so report purchased.
            return PurchaseResult.Purchased()
        case .cancelled:
            return PurchaseResult.Cancelled()
        case .pending:
            return PurchaseResult.Pending()
        case .failed:
            return PurchaseResult.Failed("The app's purchase handler reported failure.")
        }
    }

    public override func restorePurchases() async -> RestorationResult {
        guard let handler = SuperwallPurchaseHandlers.shared.restorePurchases else {
            return RestorationResult.Failed(nil)
        }
        let restored = await handler()
        return restored ? RestorationResult.Restored() : RestorationResult.Failed(nil)
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
/// needs no host view controller from the caller. By default Superwall handles
/// StoreKit / Billing and subscription status automatically; alternatively, call
/// ``setPurchaseController(purchaseFromAppStore:purchaseFromGooglePlay:restorePurchases:)``
/// before ``configure(apiKey:)`` to delegate purchases and restores to the app,
/// then keep Superwall's status in sync via
/// ``setSubscriptionStatus(activeEntitlements:)``.
///
/// Typical lifecycle:
/// ```swift
/// SuperwallManager.shared.setPurchaseController(…)           // optional; before configure
/// SuperwallManager.shared.configure(apiKey: "pk_…")          // once, at launch
/// SuperwallManager.shared.setSubscriptionStatus(activeEntitlements: ["pro"])
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

    /// `true` once the underlying native SDK has been configured.
    ///
    /// All calls below are gated on this: on Android, `Superwall.instance`
    /// throws when unconfigured, and the generated bridge's `try!` escalates
    /// that to a fatal crash — so unconfigured calls become safe no-ops here.
    public var isConfigured: Bool {
        #if !SKIP
        #if canImport(SuperwallKit)
        return Superwall.isInitialized
        #else
        return false
        #endif
        #else
        return Superwall.initialized
        #endif
    }

    /// Configure Superwall with the public API key from the dashboard.
    /// Idempotent — a second call is ignored. Call once early in app launch,
    /// before any ``register(placement:params:feature:)``. If purchase handlers
    /// were registered via
    /// ``setPurchaseController(purchaseFromAppStore:purchaseFromGooglePlay:restorePurchases:)``,
    /// the platform purchase-controller adapter is installed here.
    public func configure(apiKey: String) {
        guard !isConfigured else {
            logger.info("configure skipped — Superwall is already configured")
            return
        }
        #if !SKIP
        #if canImport(SuperwallKit)
        let handlers = SuperwallPurchaseHandlers.shared
        if let purchase = handlers.purchaseFromAppStore, let restore = handlers.restorePurchases {
            Superwall.configure(
                apiKey: apiKey,
                purchaseController: AppPurchaseControllerAdapter(purchaseHandler: purchase, restoreHandler: restore)
            )
        } else {
            Superwall.configure(apiKey: apiKey)
        }
        #endif
        #else
        // Android `configure` needs an `Application` and an activity provider (see
        // SkipSuperwallActivityProvider). The remaining nil is options.
        let context = ProcessInfo.processInfo.androidContext
        let application = context.applicationContext as! Application
        let purchaseController: PurchaseController? = SuperwallPurchaseHandlers.shared.isRegistered
            ? SkipSuperwallPurchaseController()
            : nil
        Superwall.configure(application, apiKey, purchaseController, nil, SkipSuperwallActivityProvider())
        #endif
    }

    /// Register the app's purchase handlers so Superwall delegates purchases and
    /// restores to the app instead of running StoreKit / Play Billing itself.
    ///
    /// Must be called **before** ``configure(apiKey:)`` — both native SDKs only
    /// accept a purchase controller at configure time; calling this afterwards
    /// logs a warning and has no effect on the running SDK. Once registered, the
    /// app is also responsible for pushing entitlement state via
    /// ``setSubscriptionStatus(activeEntitlements:)``.
    ///
    /// Handlers are primitive-typed so they bridge; only the platform-relevant
    /// purchase handler is invoked. A ``SuperwallPurchaseOutcome/restored``
    /// outcome is reported to Superwall as a completed purchase (neither native
    /// SDK models restored purchase results at the pinned versions).
    ///
    /// - Parameters:
    ///   - purchaseFromAppStore: Purchase the App Store product with the given
    ///     product identifier.
    ///   - purchaseFromGooglePlay: Purchase the Google Play product with the
    ///     given product ID, optional base plan ID, and optional offer ID.
    ///   - restorePurchases: Restore purchases, returning whether restoration
    ///     completed without error.
    public func setPurchaseController(
        purchaseFromAppStore: @escaping (String) async -> SuperwallPurchaseOutcome,
        purchaseFromGooglePlay: @escaping (String, String?, String?) async -> SuperwallPurchaseOutcome,
        restorePurchases: @escaping () async -> Bool
    ) {
        if isConfigured {
            logger.warning("setPurchaseController called after configure — the native SDKs only accept a purchase controller at configure time, so this has no effect")
        }
        let handlers = SuperwallPurchaseHandlers.shared
        handlers.purchaseFromAppStore = purchaseFromAppStore
        handlers.purchaseFromGooglePlay = purchaseFromGooglePlay
        handlers.restorePurchases = restorePurchases
    }

    /// Push the app's entitlement state into Superwall (e.g. the active
    /// RevenueCat entitlement identifiers after every customer-info refresh).
    /// An empty array marks the subscription inactive.
    /// While unconfigured this is a safe no-op.
    public func setSubscriptionStatus(activeEntitlements: [String]) {
        guard isConfigured else {
            logger.warning("setSubscriptionStatus skipped — Superwall is not configured")
            return
        }
        #if !SKIP
        #if canImport(SuperwallKit)
        if activeEntitlements.isEmpty {
            Superwall.shared.subscriptionStatus = .inactive
        } else {
            Superwall.shared.subscriptionStatus = .active(Set(activeEntitlements.map { Entitlement(id: $0) }))
        }
        #endif
        #else
        if activeEntitlements.isEmpty {
            Superwall.instance.setSubscriptionStatus(SubscriptionStatus.Inactive)
        } else {
            // Built as a Kotlin set directly — `SubscriptionStatus.Active` wants
            // `Set<Entitlement>`, and `.kotlin()` on a Swift collection would be
            // star-projected.
            let entitlementSet = LinkedHashSet<Entitlement>()
            for id in activeEntitlements {
                entitlementSet.add(Entitlement(id))
            }
            Superwall.instance.setSubscriptionStatus(SubscriptionStatus.Active(entitlementSet))
        }
        #endif
    }

    /// Register a placement. When that placement is attached to a campaign on
    /// the Superwall dashboard it can trigger a paywall and optionally gate the
    /// `feature` block. `feature` runs immediately when the user is already
    /// entitled (or after a successful purchase/restore); it is skipped if the
    /// user dismisses a gating paywall.
    /// While unconfigured this is a no-op: no paywall is shown and `feature`
    /// does not run (that would silently grant entitlement).
    @MainActor
    public func register(placement: String,
                         params: [String: String]? = nil,
                         feature: @escaping () -> Void = {}) {
        guard isConfigured else {
            logger.warning("register(\(placement)) skipped — Superwall is not configured")
            return
        }
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
        guard isConfigured else {
            logger.warning("identify skipped — Superwall is not configured")
            return
        }
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
        guard isConfigured else {
            logger.warning("setUserAttributes skipped — Superwall is not configured")
            return
        }
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
        guard isConfigured else {
            logger.warning("reset skipped — Superwall is not configured")
            return
        }
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
