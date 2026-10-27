# SkipSuperwall

A cross-platform [Skip](https://skip.tools) wrapper around the native
[Superwall](https://superwall.com) paywall SDKs, so a single Swift API drives
remotely-configured paywalls on both iOS and Android — in the same style as
`skip-crisp`, `skip-firebase`, and `skip-revenue`.

> **Note:** this repo will likely move under the [skiptools](https://github.com/skiptools)
> org in the future.

- **iOS / macOS** → `SuperwallKit` (`import SuperwallKit`): `Superwall.configure`,
  `Superwall.shared.register`, `identify`, `setUserAttributes`, `reset`.
- **Android** → the `com.superwall.sdk:superwall-android` Maven artifact
  (`com.superwall.sdk.Superwall`, `Superwall.instance.*`), declared in
  `Sources/SkipSuperwall/Skip/skip.yml`.

## Why a wrapper

Superwall ships first-class native SDKs on both platforms but no cross-platform
binding. Wrapping the two native SDKs behind one Swift surface
(`SuperwallManager`) keeps native paywall UX and lets app code stay
platform-agnostic. The public API deliberately mirrors the **Superwall iOS SDK**
so it reads the same as the upstream docs.

## API

```swift
SuperwallManager.shared.configure(apiKey:)                     // once, at launch
SuperwallManager.shared.identify(userID:)                      // after sign-in
SuperwallManager.shared.setUserAttributes(_:)
SuperwallManager.shared.register(placement:params:feature:)    // @MainActor
SuperwallManager.shared.reset()                                // on sign-out
```

On native macOS, `register` uses the dashboard's presentation style, so a
Fullscreen paywall covers the whole window. To show it as a sheet instead,
present `SuperwallPaywallSheet(placement:params:onDismiss:onEntitled:)` in the
app's own `.sheet` (macOS only; `onEntitled` follows `register`'s `feature`
semantics).

Superwall presents its own paywalls (a dedicated window on iOS, a
`SuperwallPaywallActivity` on Android), so `register` needs no host view
controller. With no `PurchaseController` passed to `configure`, Superwall
handles StoreKit / Google Play Billing and subscription status automatically.

## Android host-app requirements

The consuming app's `AndroidManifest.xml` must grant the Billing permission and
declare Superwall's paywall activity (per the Superwall Android quickstart):

```xml
<uses-permission android:name="com.android.vending.BILLING" />

<activity
    android:name="com.superwall.sdk.paywall.view.SuperwallPaywallActivity"
    android:theme="@style/Theme.MaterialComponents.DayNight.NoActionBar"
    android:configChanges="orientation|screenSize|keyboardHidden" />
```

## Verified

Confirmed against real iOS (Xcode) and Android (Gradle) builds:

- The SuperwallKit SPM product (`SuperwallKit`, `Package.swift`), pinned to
  the head of [superwall/Superwall-iOS#548](https://github.com/superwall/Superwall-iOS/pull/548)
  for native macOS support. `swift build` on a macOS host now compiles the
  wrapper against the real SuperwallKit instead of the no-op fallback.
- The Superwall Android Maven artifact (`Skip/skip.yml`,
  `com.superwall.sdk:superwall-android:2.7.20`) — the `com.superwall.sdk.Superwall`
  symbols match (`configure`, `instance.register`, `identify`,
  `setUserAttributes`, `reset`).
