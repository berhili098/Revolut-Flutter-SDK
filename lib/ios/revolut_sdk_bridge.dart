import 'revolut_sdk_bridge_platform_interface.dart';

export 'revolut_sdk_bridge_method_channel.dart' hide RevolutSdkException;
export 'revolut_sdk_bridge_platform_interface.dart';
export 'services/revolut_callbacks.dart';
export 'widgets/revolut_pay_button.dart';

/// Main class for the Revolut SDK Bridge plugin
/// This plugin integrates with the Revolut Pay SDK for iOS
/// and provides a bridge for accepting Revolut Pay payments in Flutter apps
class RevolutSdkBridgeIos {
  /// Clean up all Revolut Pay buttons
  ///
  /// Returns true if cleanup was successful
  static Future<bool> cleanupAllButtonsIos() {
    return RevolutSdkBridgePlatform.instance.cleanupAllButtonsIos();
  }

  /// Clean up a specific Revolut Pay button
  ///
  /// [viewId] - The view ID of the button to clean up
  /// Returns true if cleanup was successful
  static Future<bool> cleanupButtonIos(int viewId) {
    return RevolutSdkBridgePlatform.instance.cleanupButtonIos(viewId);
  }

  /// Continue confirmation flow on a controller
  ///
  /// [controllerId] - ID of the controller to continue with
  ///
  /// Returns true if successful
  static Future<bool> continueConfirmationFlowIos({
    required String controllerId,
  }) {
    return RevolutSdkBridgePlatform.instance.continueConfirmationFlowIos(
      controllerId: controllerId,
    );
  }

  /// Create a payment controller
  ///
  /// Returns a Map with controller details
  static Future<Map<String, dynamic>?> createControllerIos() {
    return RevolutSdkBridgePlatform.instance.createControllerIos();
  }

  /// Create a Revolut Pay button for payment processing
  ///
  /// [orderToken] - The order token obtained from your server after creating an order
  /// [amount] - Payment amount in minor units (e.g., 1000 for £10.00)
  /// [currency] - Payment currency (e.g., 'GBP', 'EUR', 'USD')
  /// [email] - Customer's email address
  /// [shouldRequestShipping] - Whether to request shipping details via Revolut Pay
  /// [savePaymentMethodForMerchant] - Whether to save payment method for merchant (MIT)
  /// [returnURL] - Custom return URL for payment completion
  /// [merchantName] - Name of the merchant (optional)
  /// [merchantLogoURL] - URL to merchant logo (optional)
  /// [additionalData] - Additional data to pass with the payment (optional)
  ///
  /// Returns a Map with button configuration and payment result
  static Future<Map<String, dynamic>?> createRevolutPayButtonIos({
    required String orderToken,
    required int amount,
    required String currency,
    required String email,
    bool shouldRequestShipping = false,
    bool savePaymentMethodForMerchant = false,
    String? returnURL,
    String? merchantName,
    String? merchantLogoURL,
    Map<String, dynamic>? additionalData,
  }) {
    return RevolutSdkBridgePlatform.instance.createRevolutPayButtonIos(
      orderToken: orderToken,
      amount: amount,
      currency: currency,
      email: email,
      shouldRequestShipping: shouldRequestShipping,
      savePaymentMethodForMerchant: savePaymentMethodForMerchant,
      returnURL: returnURL,
      merchantName: merchantName,
      merchantLogoURL: merchantLogoURL,
      additionalData: additionalData,
    );
  }

  /// Dispose a controller
  ///
  /// [controllerId] - ID of the controller to dispose
  ///
  /// Returns true if successful
  static Future<bool> disposeControllerIos({required String controllerId}) {
    return RevolutSdkBridgePlatform.instance.disposeControllerIos(
      controllerId: controllerId,
    );
  }

  /// Get platform version (for debugging)
  static Future<String?> getPlatformVersionIos() {
    return RevolutSdkBridgePlatform.instance.getPlatformVersionIos();
  }

  /// Get SDK version information
  ///
  /// Returns a Map with SDK version details
  static Future<Map<String, dynamic>?> getSdkVersionIos() {
    return RevolutSdkBridgePlatform.instance.getSdkVersionIos();
  }

  /// Initialize the Revolut Pay SDK with configuration
  ///
  /// [merchantPublicKey] - Your merchant public API key from Revolut Developer Dashboard
  /// [environment] - 'sandbox' for testing, 'production' for live payments
  static Future<bool> initializeIos({
    required String merchantPublicKey,
    String? environment,
  }) {
    return RevolutSdkBridgePlatform.instance.initializeIos(
      merchantPublicKey: merchantPublicKey,
      environment: environment,
    );
  }

  /// Process a payment with the given order token
  ///
  /// [orderToken] - Order token for payment processing
  /// [savePaymentMethodForMerchant] - Whether to save payment method for merchant
  ///
  /// Returns a Map with payment result details
  static Future<Map<String, dynamic>?> payIos({
    required String orderToken,
    bool savePaymentMethodForMerchant = false,
  }) {
    return RevolutSdkBridgePlatform.instance.payIos(
      orderToken: orderToken,
      savePaymentMethodForMerchant: savePaymentMethodForMerchant,
    );
  }

  /// Provide promotional banner widget
  ///
  /// [promoParams] - Parameters for the promotional banner
  /// [themeId] - Optional theme ID for styling
  ///
  /// Returns a Map with banner details
  static Future<Map<String, dynamic>?> providePromotionalBannerWidgetIos({
    required Map<String, dynamic> promoParams,
    String? themeId,
  }) {
    return RevolutSdkBridgePlatform.instance.providePromotionalBannerWidgetIos(
      promoParams: promoParams,
      themeId: themeId,
    );
  }

  /// Set order token on a controller
  ///
  /// [orderToken] - Order token to set on the controller
  /// [controllerId] - ID of the controller to update
  ///
  /// Returns true if successful
  static Future<bool> setOrderTokenIos({
    required String orderToken,
    required String controllerId,
  }) {
    return RevolutSdkBridgePlatform.instance.setOrderTokenIos(
      orderToken: orderToken,
      controllerId: controllerId,
    );
  }

  /// Set save payment method for merchant on a controller
  ///
  /// [savePaymentMethodForMerchant] - Whether to save payment method for merchant
  /// [controllerId] - ID of the controller to update
  ///
  /// Returns true if successful
  static Future<bool> setSavePaymentMethodForMerchantIos({
    required bool savePaymentMethodForMerchant,
    required String controllerId,
  }) {
    return RevolutSdkBridgePlatform.instance.setSavePaymentMethodForMerchantIos(
      savePaymentMethodForMerchant: savePaymentMethodForMerchant,
      controllerId: controllerId,
    );
  }
}
