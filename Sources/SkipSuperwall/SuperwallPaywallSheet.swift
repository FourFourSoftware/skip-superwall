#if !SKIP_BRIDGE
#if !SKIP && os(macOS) && canImport(SuperwallKit)
import SwiftUI
import SuperwallKit

/// A Superwall paywall for the app to present in its own SwiftUI `.sheet` on
/// native macOS.
///
/// `SuperwallManager.register(placement:params:feature:)` presents with the
/// style set on the Superwall dashboard, which on macOS turns a Fullscreen
/// paywall into a full-window overlay. Hosting the paywall here keeps the Mac
/// presentation a sheet without changing the dashboard style that iOS uses.
///
/// Exactly one callback runs per presentation, matching `register`'s `feature`
/// semantics:
/// - `onEntitled`: the user purchased or restored, closed a non-gated paywall,
///   or the placement was skipped (holdout, no audience match, or not found).
/// - `onDismiss`: any other close (a gated paywall's close button, Escape, the
///   sheet being dismissed externally), a load error, or Superwall being
///   unconfigured.
///
/// Neither callback dismisses the sheet; clear the presenting state in both.
/// Give each presentation a fresh identity (e.g. `.sheet(item:)`): Superwall
/// crashes if the same paywall is shown in two places at once.
public struct SuperwallPaywallSheet: View {
    let placement: String
    let params: [String: String]?
    let onDismiss: () -> Void
    let onEntitled: () -> Void

    @State private var hasFinished = false

    public init(
        placement: String,
        params: [String: String]? = nil,
        onDismiss: @escaping () -> Void,
        onEntitled: @escaping () -> Void
    ) {
        self.placement = placement
        self.params = params
        self.onDismiss = onDismiss
        self.onEntitled = onEntitled
    }

    public var body: some View {
        ZStack {
            ProgressView()
            if SuperwallManager.shared.isConfigured {
                PaywallView(
                    placement: placement,
                    params: params,
                    onRequestDismiss: { info, result in
                        finish(entitled: Self.grantsAccess(
                            result,
                            closeReason: info.closeReason,
                            featureGating: info.featureGatingBehavior
                        ))
                    },
                    onSkippedView: { _ in
                        Color.clear.onAppear { finish(entitled: true) }
                    },
                    onErrorView: { _ in
                        Color.clear.onAppear { finish(entitled: false) }
                    }
                )
            } else {
                Color.clear.onAppear { finish(entitled: false) }
            }
        }
        // SuperwallKit's own sheet size (`PaywallSheetSize.preferred`).
        .frame(idealWidth: 480, idealHeight: 720)
        .onDisappear { finish(entitled: false) }
    }

    /// `PaywallView`'s own `feature` callback is not used: it skips skipped
    /// placements, and its ordering against `onRequestDismiss` is unspecified.
    func finish(entitled: Bool) {
        guard !hasFinished else { return }
        hasFinished = true
        if entitled {
            onEntitled()
        } else {
            onDismiss()
        }
    }

    /// Whether a paywall close grants the feature, as `register` decides it.
    nonisolated static func grantsAccess(
        _ result: PaywallResult,
        closeReason: PaywallCloseReason,
        featureGating: FeatureGatingBehavior
    ) -> Bool {
        switch result {
        case .purchased, .restored:
            return true
        case .declined:
            return closeReason != .forNextPaywall && featureGating == .nonGated
        }
    }
}
#endif
#endif
