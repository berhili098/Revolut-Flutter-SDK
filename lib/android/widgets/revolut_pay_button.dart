import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/revolut_pay_models.dart';

/// A Flutter widget that displays a Revolut Pay button using the native Android SDK
/// This widget creates a platform view that renders the native Revolut Pay button
class RevolutPayButton extends StatefulWidget {
  /// Button parameters for customization
  final ButtonParamsData? buttonParams;

  /// Order token for payment processing
  final String? orderToken;

  /// Payment amount in minor units (e.g., 1000 for £10.00)
  final int? amount;

  /// Payment currency (e.g., 'GBP', 'EUR', 'USD')
  final String? currency;

  /// Customer email address
  final String? email;

  /// Whether to request shipping information
  final bool shouldRequestShipping;

  /// Whether to save payment method for merchant
  final bool savePaymentMethodForMerchant;

  /// Return URL for payment completion
  final String? returnURL;

  /// Merchant name to display
  final String? merchantName;

  /// Merchant logo URL
  final String? merchantLogoURL;

  /// Additional data for the payment
  final Map<String, dynamic>? additionalData;

  final String? preferredMode;

  /// Callback when button is clicked
  /// Note: The native button handles clicks directly and triggers the payment flow.
  final VoidCallback? onPressed;

  /// Callback when payment succeeds
  final Function(Map<String, dynamic> result)? onPaymentSuccess;

  /// Callback when payment fails
  final Function(String error, Map<String, dynamic>? details)? onPaymentError;

  /// Callback when payment is cancelled by user
  final Function()? onPaymentCancelled;

  /// Callback when button creation fails
  final Function(String error)? onError;

  /// Width of the button (optional)
  final double? width;

  /// Height of the button (optional)
  final double? height;

  /// Whether the button is enabled
  final bool enabled;

  /// Custom styling for the button container
  final BoxDecoration? decoration;

  /// Margin around the button
  final EdgeInsetsGeometry? margin;

  /// Padding inside the button
  final EdgeInsetsGeometry? padding;

  const RevolutPayButton({
    super.key,
    this.buttonParams,
    this.orderToken,
    this.amount,
    this.currency,
    this.email,
    this.shouldRequestShipping = false,
    this.savePaymentMethodForMerchant = false,
    this.returnURL,
    this.merchantName,
    this.merchantLogoURL,
    this.additionalData,
    this.preferredMode,
    this.onPressed,
    this.onPaymentSuccess,
    this.onPaymentError,
    this.onPaymentCancelled,
    this.onError,
    this.width,
    this.height,
    this.enabled = true,
    this.decoration,
    this.margin,
    this.padding,
  });

  @override
  State<RevolutPayButton> createState() => _RevolutPayButtonState();
}

/// A promotional banner widget for Revolut Pay
class RevolutPayPromoBanner extends StatefulWidget {
  /// Promotional banner parameters
  final PromoBannerParamsData? promoParams;

  /// Theme ID for the banner
  final String? themeId;

  /// Callback when banner is interacted with
  final Function(String bannerId, String interactionType)? onInteraction;

  /// Callback when banner creation fails
  final Function(String error)? onError;

  /// Width of the banner
  final double? width;

  /// Height of the banner
  final double? height;

  const RevolutPayPromoBanner({
    super.key,
    this.promoParams,
    this.themeId,
    this.onInteraction,
    this.onError,
    this.width,
    this.height,
  });

  @override
  State<RevolutPayPromoBanner> createState() => _RevolutPayPromoBannerState();
}

class _RevolutPayButtonState extends State<RevolutPayButton> {
  static const String _viewType = 'revolut_pay_button';
  MethodChannel? _paymentChannel;

  @override
  void dispose() {
    _paymentChannel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.orderToken == null || widget.amount == null || widget.currency == null) {
      return _buildErrorState('Missing required parameters (orderToken, amount, currency)');
    }

    final buttonParamsMap = (widget.buttonParams ?? const ButtonParamsData()).toMap();

    final creationParams = <String, dynamic>{
      'buttonParams': buttonParamsMap,
      'orderToken': widget.orderToken,
      'amount': widget.amount,
      'currency': widget.currency,
      'email': widget.email,
      'shouldRequestShipping': widget.shouldRequestShipping,
      'savePaymentMethodForMerchant': widget.savePaymentMethodForMerchant,
      'returnURL': widget.returnURL ?? 'revolut-sdk-bridge://revolut-pay',
      'merchantName': widget.merchantName,
      'merchantLogoURL': widget.merchantLogoURL,
      'additionalData': widget.additionalData,
      'preferredMode': widget.preferredMode,
    };

    return Container(
      width: widget.width ?? double.infinity,
      height: widget.height ?? 60.0, // Default height for Revolut button
      margin: widget.margin,
      padding: widget.padding,
      decoration: widget.decoration,
      child: AndroidView(
        key: ValueKey(widget.orderToken),
        viewType: _viewType,
        onPlatformViewCreated: _onPlatformViewCreated,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Container(
      width: widget.width,
      height: widget.height ?? 48.0,
      margin: widget.margin,
      decoration:
          widget.decoration ??
          BoxDecoration(
            color: Colors.red[100],
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(color: Colors.red),
          ),
      child: Center(
        child: SelectableText.rich(
          TextSpan(
            text: message,
            style: TextStyle(color: Colors.red[800], fontSize: 12.0),
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  void _onPlatformViewCreated(int id) {
    _paymentChannel = MethodChannel('revolut_pay_button_payment_$id');
    _paymentChannel!.setMethodCallHandler(_handlePaymentChannelCall);
  }

  Future<void> _handlePaymentChannelCall(MethodCall call) async {
    if (!mounted) return;

    switch (call.method) {
      case 'onPaymentResult':
        final args = call.arguments as Map<dynamic, dynamic>?;
        if (args == null) return;

        final resultData = _normalizeNativeMap(args);
        final success = resultData['success'] as bool? ?? false;
        final message = resultData['message'] as String? ?? '';
        final error = resultData['error'] as String? ?? '';

        if (success) {
          widget.onPaymentSuccess?.call(resultData);
          return;
        }

        final failureMessage = error.isNotEmpty ? error : message;

        if (error == 'user_abandoned_payment' ||
            message.toLowerCase().contains('abandoned') ||
            message.toLowerCase().contains('cancelled')) {
          widget.onPaymentCancelled?.call();
        } else {
          widget.onError?.call(failureMessage);
          widget.onPaymentError?.call(failureMessage, resultData);
        }
        break;
    }
  }

  Map<String, dynamic> _normalizeNativeMap(Map<dynamic, dynamic> source) {
    return source.map((key, value) => MapEntry(key.toString(), value));
  }
}

class _RevolutPayPromoBannerState extends State<RevolutPayPromoBanner> {
  static const String _viewType = 'revolut_pay_promo_banner';

  @override
  Widget build(BuildContext context) {
    if (widget.promoParams == null) {
      return _buildErrorState('Missing promoParams');
    }

    final creationParams = <String, dynamic>{'promoParams': widget.promoParams!.toMap(), 'themeId': widget.themeId};

    return SizedBox(
      width: widget.width ?? double.infinity,
      height: widget.height ?? 80.0, // Estimated height for banner
      child: AndroidView(
        viewType: _viewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Container(
      width: widget.width,
      height: widget.height ?? 80.0,
      decoration: BoxDecoration(
        color: Colors.orange[100],
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: Colors.orange),
      ),
      child: Center(
        child: Text(
          message,
          style: TextStyle(color: Colors.orange[800], fontSize: 12.0),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
