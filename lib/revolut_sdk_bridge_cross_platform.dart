import 'dart:io';

import 'package:flutter/material.dart';

// Import common models and enums
import 'android/enums/revolut_enums.dart';
import 'android/models/revolut_pay_models.dart';
// Import platform-specific implementations
import 'android/revolut_sdk_bridge.dart' as android;
import 'ios/revolut_sdk_bridge.dart' as ios;

/// Cross-platform Revolut Pay button widget
/// Automatically adapts to the current platform
class CrossPlatformRevolutPayButton extends StatelessWidget {
  final String orderToken;
  final int amount;
  final String currency;
  final String email;
  final bool shouldRequestShipping;
  final bool savePaymentMethodForMerchant;
  final String? returnURL;
  final String? merchantName;
  final String? merchantLogoURL;
  final Map<String, dynamic>? additionalData;

  // Android-specific parameters
  final ButtonParamsData? buttonParams;
  final String? preferredMode;

  // iOS-specific parameters
  final double? height;
  final double? width;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;

  // Callbacks
  final VoidCallback? onPressed;
  final Function(String)? onError;
  final Function(Map<String, dynamic>)? onPaymentResult;
  final Function(String)? onPaymentError;
  final VoidCallback? onPaymentCancelled;
  final VoidCallback? onButtonCreated;
  final VoidCallback? onButtonError;

  const CrossPlatformRevolutPayButton({
    super.key,
    required this.orderToken,
    required this.amount,
    required this.currency,
    required this.email,
    this.shouldRequestShipping = false,
    this.savePaymentMethodForMerchant = false,
    this.returnURL,
    this.merchantName,
    this.merchantLogoURL,
    this.additionalData,
    this.buttonParams,
    this.preferredMode,
    this.height,
    this.width,
    this.margin,
    this.padding,
    this.borderRadius,
    this.onPressed,
    this.onError,
    this.onPaymentResult,
    this.onPaymentError,
    this.onPaymentCancelled,
    this.onButtonCreated,
    this.onButtonError,
  });

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) {
      // Use Android implementation
      return android.RevolutPayButton(
        buttonParams: buttonParams,
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
        preferredMode: preferredMode,
        onPressed: onPressed,
        onPaymentSuccess: onPaymentResult,
        onPaymentError: (error, details) => onPaymentError?.call(error),
        onPaymentCancelled: onPaymentCancelled,
        onError: onError,
        width: width,
        height: height,
        margin: margin,
        padding: padding,
        decoration: borderRadius != null ? BoxDecoration(borderRadius: borderRadius) : null,
      );
    } else if (Platform.isIOS) {
      // Use iOS implementation
      return ios.RevolutPayButtonIos(
        config: ios.RevolutPayButtonConfigIos(
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
        ),
        style: ios.RevolutPayButtonStyleIos(
          height: height,
          width: width,
          margin: margin,
          padding: padding,
          borderRadius: borderRadius,
        ),
        onPaymentResult: onPaymentResult != null
            ? (result) => onPaymentResult!({
                'success': result.success,
                'message': result.message,
                'error': result.error,
                'timestamp': result.timestamp.toIso8601String(),
              })
            : null,
        onPaymentError: onPaymentError,
        onPaymentCancelled: onPaymentCancelled,
        onButtonCreated: onButtonCreated,
        onButtonError: onButtonError,
        onError: onError,
      );
    } else {
      // Fallback for unsupported platforms
      return Container(
        height: height ?? 50,
        width: width,
        margin: margin,
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.grey[300], borderRadius: borderRadius ?? BorderRadius.circular(8)),
        child: const Center(
          child: Text(
            'Revolut Pay Button\n(Platform not supported)',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12),
          ),
        ),
      );
    }
  }
}

/// Cross-platform promotional banner widget (Android only)
class CrossPlatformRevolutPayPromoBanner extends StatelessWidget {
  final PromoBannerParamsData? promoParams;
  final String? themeId;
  final double? width;
  final double? height;
  final Function(String, String)? onInteraction;
  final Function(String)? onError;

  const CrossPlatformRevolutPayPromoBanner({
    super.key,
    this.promoParams,
    this.themeId,
    this.width,
    this.height,
    this.onInteraction,
    this.onError,
  });

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) {
      // Use Android implementation
      return android.RevolutPayPromoBanner(
        promoParams: promoParams,
        themeId: themeId,
        width: width,
        height: height,
        onInteraction: onInteraction != null
            ? (bannerId, interactionType) => onInteraction!(bannerId, interactionType)
            : null,
        onError: onError,
      );
    } else {
      // iOS doesn't support promotional banners
      return Container(
        width: width,
        height: height ?? 80,
        decoration: BoxDecoration(
          color: Colors.orange[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange),
        ),
        child: const Center(
          child: Text(
            'Promotional Banners\n(Not supported on iOS)',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
      );
    }
  }
}

//
/// Cross-platform Revolut SDK Bridge
/// Automatically selects the appropriate platform implementation
class RevolutSdkBridge {
  static final RevolutSdkBridge _instance = RevolutSdkBridge._internal();
  factory RevolutSdkBridge() => _instance;
  RevolutSdkBridge._internal();

  /// Check if running on Android
  bool get isAndroid => Platform.isAndroid;

  /// Check if the event channel is ready (Android only)
  bool get isEventChannelReady {
    if (isAndroid) {
      try {
        final methodChannel = android.RevolutSdkBridgeMethodChannel(android.RevolutCallbacks());
        return methodChannel.isEventChannelReady;
      } catch (e) {
        debugPrint('Failed to check event channel status: $e');
        return false;
      }
    }
    return false;
  }

  /// Check if running on iOS
  bool get isIOS => Platform.isIOS;

  /// Clean up all buttons (iOS only)
  Future<bool> cleanupAllButtons() async {
    try {
      if (isAndroid) {
        // Android doesn't have this method
        return true;
      } else if (isIOS) {
        // iOS implementation
        return await ios.RevolutSdkBridgeIos.cleanupAllButtonsIos();
      } else {
        throw UnsupportedError('Platform not supported');
      }
    } catch (e) {
      debugPrint('Failed to cleanup buttons: $e');
      rethrow;
    }
  }

  /// Clean up a specific button (iOS only)
  Future<bool> cleanupButton(int viewId) async {
    try {
      if (isAndroid) {
        // Android doesn't have this method
        return true;
      } else if (isIOS) {
        // iOS implementation
        return await ios.RevolutSdkBridgeIos.cleanupButtonIos(viewId);
      } else {
        throw UnsupportedError('Platform not supported');
      }
    } catch (e) {
      debugPrint('Failed to cleanup button: $e');
      rethrow;
    }
  }

  /// Continue confirmation flow on a controller
  ///
  /// [controllerId] - ID of the controller to continue with
  ///
  /// Returns true if successful
  Future<bool> continueConfirmationFlow({required String controllerId}) async {
    try {
      if (isAndroid) {
        // Android implementation
        return await android.RevolutSdkBridgeMethodChannel(
          android.RevolutCallbacks(),
        ).continueConfirmationFlow(controllerId: controllerId);
      } else if (isIOS) {
        // iOS implementation
        return await ios.RevolutSdkBridgeIos.continueConfirmationFlowIos(controllerId: controllerId);
      } else {
        throw UnsupportedError('Platform not supported');
      }
    } catch (e) {
      debugPrint('Failed to continue confirmation flow: $e');
      rethrow;
    }
  }

  /// Create a payment controller
  ///
  /// Returns a Map with controller details
  Future<Map<String, dynamic>?> createController() async {
    try {
      if (isAndroid) {
        // Android implementation
        final result = await android.RevolutSdkBridgeMethodChannel(android.RevolutCallbacks()).createController();
        return result.toMap();
      } else if (isIOS) {
        // iOS implementation
        return await ios.RevolutSdkBridgeIos.createControllerIos();
      } else {
        throw UnsupportedError('Platform not supported');
      }
    } catch (e) {
      debugPrint('Failed to create controller: $e');
      rethrow;
    }
  }

  /// Create a Revolut Pay button for the current platform
  ///
  /// [orderToken] - Order token for payment processing
  /// [amount] - Payment amount in minor units (e.g., 1000 for £10.00)
  /// [currency] - Payment currency (e.g., 'GBP', 'EUR', 'USD')
  /// [email] - Customer email address
  /// [buttonParams] - Button customization parameters (Android only)
  /// [shouldRequestShipping] - Whether to request shipping information
  /// [savePaymentMethodForMerchant] - Whether to save payment method
  /// [returnURL] - Return URL for payment completion
  /// [merchantName] - Merchant name to display
  /// [merchantLogoURL] - Merchant logo URL
  /// [additionalData] - Additional data for the payment
  /// Imperative button creation is not supported.
  ///
  /// Render the [CrossPlatformRevolutPayButton] widget instead — it creates and
  /// displays the native Revolut Pay button and reports the payment result.
  @Deprecated('Render the CrossPlatformRevolutPayButton widget instead.')
  Future<Map<String, dynamic>?> createPaymentButton({
    required String orderToken,
    required int amount,
    required String currency,
    required String email,
    ButtonParamsData? buttonParams,
    bool shouldRequestShipping = false,
    bool savePaymentMethodForMerchant = false,
    String? returnURL,
    String? merchantName,
    String? merchantLogoURL,
    Map<String, dynamic>? additionalData,
  }) async {
    throw UnsupportedError(
      'createPaymentButton() is not supported. Render the CrossPlatformRevolutPayButton '
      'widget instead — it displays the native Revolut Pay button and reports results.',
    );
  }

  /// Create a promotional banner (Android only)
  ///
  /// [promoParams] - Promotional banner parameters
  /// [themeId] - Theme ID for the banner
  /// Imperative banner creation is not supported.
  ///
  /// Render the [CrossPlatformRevolutPayPromoBanner] widget instead (Android only).
  @Deprecated('Render the CrossPlatformRevolutPayPromoBanner widget instead.')
  Future<BannerResultData?> createPromotionalBanner({PromoBannerParamsData? promoParams, String? themeId}) async {
    throw UnsupportedError(
      'createPromotionalBanner() is not supported. Render the CrossPlatformRevolutPayPromoBanner '
      'widget instead (Android only).',
    );
  }

  /// Dispose a controller
  ///
  /// [controllerId] - ID of the controller to dispose
  ///
  /// Returns true if successful
  ///
  ///
  ///

  Future<bool> disposeController({required String controllerId}) async {
    try {
      if (isAndroid) {
        // Android implementation
        return await android.RevolutSdkBridgeMethodChannel(
          android.RevolutCallbacks(),
        ).disposeController(controllerId: controllerId);
      } else if (isIOS) {
        // iOS implementation
        return await ios.RevolutSdkBridgeIos.disposeControllerIos(controllerId: controllerId);
      } else {
        throw UnsupportedError('Platform not supported');
      }
    } catch (e) {
      debugPrint('Failed to dispose controller: $e');
      rethrow;
    }
  }

  /// Get the platform version
  Future<String> getPlatformVersion() async {
    try {
      if (isAndroid) {
        // Android implementation
        return await android.RevolutSdkBridgeMethodChannel(android.RevolutCallbacks()).getPlatformVersion();
      } else if (isIOS) {
        // iOS implementation
        final result = await ios.RevolutSdkBridgeIos.getPlatformVersionIos();
        return result ?? 'Unknown';
      } else {
        throw UnsupportedError('Platform not supported');
      }
    } catch (e) {
      debugPrint('Failed to get platform version: $e');
      rethrow;
    }
  }

  /// Check the overall plugin status
  Future<Map<String, dynamic>> getPluginStatus() async {
    try {
      final status = <String, dynamic>{
        'platform': isAndroid
            ? 'android'
            : isIOS
            ? 'ios'
            : 'unknown',
        'isAndroid': isAndroid,
        'isIOS': isIOS,
      };

      if (isAndroid) {
        status['eventChannelReady'] = isEventChannelReady;
        status['platformVersion'] = await getPlatformVersion();
        status['sdkVersion'] = await getSdkVersion();
      } else if (isIOS) {
        status['platformVersion'] = await getPlatformVersion();
      }

      return status;
    } catch (e) {
      debugPrint('Failed to get plugin status: $e');
      return {
        'error': e.toString(),
        'platform': isAndroid
            ? 'android'
            : isIOS
            ? 'ios'
            : 'unknown',
      };
    }
  }

  /// Get SDK version information
  ///
  /// Returns a Map with SDK version details
  Future<Map<Object?, dynamic>?> getSdkVersion() async {
    try {
      if (isAndroid) {
        // Android implementation
        return await android.RevolutSdkBridgeMethodChannel(android.RevolutCallbacks()).getSdkVersion();
      } else if (isIOS) {
        // iOS implementation
        return await ios.RevolutSdkBridgeIos.getSdkVersionIos();
      } else {
        throw UnsupportedError('Platform not supported');
      }
    } catch (e) {
      debugPrint('Failed to get SDK version: $e');
      rethrow;
    }
  }

  /// Initialize the Revolut SDK for the current platform
  ///
  /// [merchantPublicKey] - Your Revolut merchant public key
  /// [environment] - Environment ('sandbox' or 'main')
  /// [returnUri] - Return URI for payment completion (Android only)
  /// [requestShipping] - Whether to request shipping information (Android only)
  /// [customer] - Customer data (Android only)
  Future<bool> initialize({required String merchantPublicKey, String? environment}) async {
    try {
      if (isAndroid) {
        // Android implementation
        final androidEnv = _resolveAndroidEnvironment(environment);

        // Wait for event channel to be ready
        final eventChannelReady = await waitForEventChannel();
        if (!eventChannelReady) {
          debugPrint('Warning: Event channel not ready, but continuing with initialization');
        }

        // Create the method channel and proceed with initialization
        final methodChannel = android.RevolutSdkBridgeMethodChannel(android.RevolutCallbacks());

        return await methodChannel.init(environment: androidEnv.value, merchantPublicKey: merchantPublicKey);
      } else if (isIOS) {
        // iOS implementation
        return await ios.RevolutSdkBridgeIos.initializeIos(
          merchantPublicKey: merchantPublicKey,
          environment: environment,
        );
      } else {
        throw UnsupportedError('Platform not supported');
      }
    } catch (e) {
      debugPrint('Failed to initialize Revolut SDK: $e');
      rethrow;
    }
  }

  /// Process a payment with the given order token
  ///
  /// [orderToken] - Order token for payment processing
  /// [savePaymentMethodForMerchant] - Whether to save payment method
  Future<bool> processPayment({required String orderToken, bool savePaymentMethodForMerchant = false}) async {
    try {
      if (isAndroid) {
        // Android implementation
        return await android.RevolutSdkBridgeMethodChannel(
          android.RevolutCallbacks(),
        ).pay(orderToken: orderToken, savePaymentMethodForMerchant: savePaymentMethodForMerchant);
      } else if (isIOS) {
        // iOS implementation
        final result = await ios.RevolutSdkBridgeIos.payIos(
          orderToken: orderToken,
          savePaymentMethodForMerchant: savePaymentMethodForMerchant,
        );
        return result != null;
      } else {
        throw UnsupportedError('Platform not supported');
      }
    } catch (e) {
      debugPrint('Failed to process payment: $e');
      rethrow;
    }
  }

  /// Provide promotional banner widget
  ///
  /// [promoParams] - Parameters for the promotional banner
  /// [themeId] - Optional theme ID for styling
  ///
  /// Returns a Map with banner details
  /// Imperative banner creation is not supported.
  ///
  /// Render the [CrossPlatformRevolutPayPromoBanner] widget instead (Android only).
  @Deprecated('Render the CrossPlatformRevolutPayPromoBanner widget instead.')
  Future<Map<String, dynamic>?> providePromotionalBannerWidget({
    required Map<String, dynamic> promoParams,
    String? themeId,
  }) async {
    throw UnsupportedError(
      'providePromotionalBannerWidget() is not supported. Render the '
      'CrossPlatformRevolutPayPromoBanner widget instead (Android only).',
    );
  }

  /// Set order token on a controller
  ///
  /// [orderToken] - Order token to set on the controller
  /// [controllerId] - ID of the controller to update
  ///
  /// Returns true if successful
  Future<bool> setOrderToken({required String orderToken, required String controllerId}) async {
    try {
      if (isAndroid) {
        // Android implementation
        return await android.RevolutSdkBridgeMethodChannel(
          android.RevolutCallbacks(),
        ).setOrderToken(orderToken: orderToken, controllerId: controllerId);
      } else if (isIOS) {
        // iOS implementation
        return await ios.RevolutSdkBridgeIos.setOrderTokenIos(orderToken: orderToken, controllerId: controllerId);
      } else {
        throw UnsupportedError('Platform not supported');
      }
    } catch (e) {
      debugPrint('Failed to set order token: $e');
      rethrow;
    }
  }

  /// Set save payment method for merchant on a controller
  ///
  /// [savePaymentMethodForMerchant] - Whether to save payment method for merchant
  /// [controllerId] - ID of the controller to update
  ///
  /// Returns true if successful
  Future<bool> setSavePaymentMethodForMerchant({
    required bool savePaymentMethodForMerchant,
    required String controllerId,
  }) async {
    try {
      if (isAndroid) {
        // Android implementation
        return await android.RevolutSdkBridgeMethodChannel(android.RevolutCallbacks()).setSavePaymentMethodForMerchant(
          savePaymentMethodForMerchant: savePaymentMethodForMerchant,
          controllerId: controllerId,
        );
      } else if (isIOS) {
        // iOS implementation
        return await ios.RevolutSdkBridgeIos.setSavePaymentMethodForMerchantIos(
          savePaymentMethodForMerchant: savePaymentMethodForMerchant,
          controllerId: controllerId,
        );
      } else {
        throw UnsupportedError('Platform not supported');
      }
    } catch (e) {
      debugPrint('Failed to set save payment method: $e');
      rethrow;
    }
  }

  /// Manually setup the event channel (Android only)
  Future<bool> setupEventChannel() async {
    if (isAndroid) {
      try {
        final methodChannel = android.RevolutSdkBridgeMethodChannel(android.RevolutCallbacks());
        methodChannel.ensureEventChannelReady();
        return methodChannel.isEventChannelReady;
      } catch (e) {
        debugPrint('Failed to setup event channel: $e');
        return false;
      }
    }
    return false;
  }

  /// Manually trigger event channel setup and wait for it to be ready
  Future<bool> waitForEventChannel() async {
    if (isAndroid) {
      try {
        // Try to setup the event channel
        await setupEventChannel();

        // Wait for it to be ready
        int attempts = 0;
        const maxAttempts = 10;
        const delayMs = 100;

        while (!isEventChannelReady && attempts < maxAttempts) {
          await Future.delayed(Duration(milliseconds: delayMs));
          attempts++;
          debugPrint('Waiting for event channel... attempt $attempts/$maxAttempts');
        }

        return isEventChannelReady;
      } catch (e) {
        debugPrint('Failed to wait for event channel: $e');
        return false;
      }
    }
    return true; // iOS doesn't need event channel
  }

  RevolutEnvironment _resolveAndroidEnvironment(String? environment) {
    final normalized = environment?.trim().toLowerCase();
    switch (normalized) {
      case 'production':
      case 'prod':
      case 'live':
      case 'main':
        return RevolutEnvironment.main;
      case 'sandbox':
      case 'test':
      case 'testing':
      case 'dev':
      case 'development':
      case null:
        return RevolutEnvironment.sandbox;
      default:
        debugPrint('Unknown environment "$environment", defaulting to sandbox.');
        return RevolutEnvironment.sandbox;
    }
  }
}
