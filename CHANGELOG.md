# Changelog

## 0.1.0

First public release of the Revolut Pay Flutter plugin. It wraps the native
Revolut Pay **Lite** SDK on Android and the Revolut Pay SDK on iOS.

### Added
- `RevolutPayButton` widget that renders the native Revolut Pay button and runs
  the real payment flow on both Android and iOS.
- `CrossPlatformRevolutPayButton` convenience widget that picks the right
  platform implementation automatically.
- One-shot `pay()` for custom (merchant-rendered) buttons on Android, backed by a
  real `RevolutPaymentController`.
- Native Revolut Pay promotional banner (`RevolutPayPromoBanner`) on Android.
- SDK initialization with `sandbox` / `production` environments.

### Changed
- Android plugin namespace is now `com.revolutpay.flutter`.
- Bumped the Android Revolut Pay Lite SDK to `3.1.2`.

### Notes
- The Revolut Pay Lite SDK has **no** manual confirmation-flow/controller API.
  The former `createController` / `setOrderToken` / `setSavePaymentMethodForMerchant`
  / `continueConfirmationFlow` / `disposeController` stubs used to return fake
  success; they now return an explicit `UNSUPPORTED` error. Use the
  `RevolutPayButton` widget, or `pay()` for a custom button.
- iOS is button/widget-only: use the `RevolutPayButton` widget. A headless
  `pay()` is not supported by the iOS SDK and returns an explicit error.
- Promotional banners are Android-only.
