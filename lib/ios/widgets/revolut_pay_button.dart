import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:revolut_sdk_bridge/revolut_sdk_bridge.dart';

/// Configuration for the Revolut Pay button
class RevolutPayButtonConfigIos {
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

  const RevolutPayButtonConfigIos({
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
  });

  Map<String, dynamic> toMap() {
    return {
      'orderToken': orderToken,
      'amount': amount,
      'currency': currency,
      'email': email,
      'shouldRequestShipping': shouldRequestShipping,
      'savePaymentMethodForMerchant': savePaymentMethodForMerchant,
      'returnURL': returnURL,
      'merchantName': merchantName,
      'merchantLogoURL': merchantLogoURL,
      'additionalData': additionalData,
    };
  }
}

/// The Revolut Pay button widget
class RevolutPayButtonIos extends StatefulWidget {
  final RevolutPayButtonConfigIos config;
  final RevolutPayButtonStyleIos? style;
  final Widget? loadingWidget;
  final Widget? placeholderWidget;
  final Function(RevolutPaymentResultIos)? onPaymentResult;
  final Function(String)? onPaymentError;
  final VoidCallback? onPaymentCancelled;
  final VoidCallback? onButtonCreated;
  final VoidCallback? onButtonError;
  final Function(String)? onError; // Simple error callback

  const RevolutPayButtonIos({
    super.key,
    required this.config,
    this.style,
    this.loadingWidget,
    this.placeholderWidget,
    this.onPaymentResult,
    this.onPaymentError,
    this.onPaymentCancelled,
    this.onButtonCreated,
    this.onButtonError,
    this.onError,
  });

  @override
  State<RevolutPayButtonIos> createState() => _RevolutPayButtonIosState();
}

/// Style configuration for the Revolut Pay button
class RevolutPayButtonStyleIos {
  final double? height;
  final double? width;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final BoxBorder? border;
  final List<BoxShadow>? boxShadow;
  final Color? backgroundColor;
  final Color? textColor;
  final double? fontSize;
  final FontWeight? fontWeight;
  final String? fontFamily;

  const RevolutPayButtonStyleIos({
    this.height,
    this.width,
    this.margin,
    this.padding,
    this.borderRadius,
    this.border,
    this.boxShadow,
    this.backgroundColor,
    this.textColor,
    this.fontSize,
    this.fontWeight,
    this.fontFamily,
  });

  Map<String, dynamic> toMap() {
    return {
      'height': height,
      'width': width,
      'margin': margin?.toString(),
      'padding': padding?.toString(),
      'borderRadius': borderRadius?.toString(),
      'border': border?.toString(),
      'boxShadow': boxShadow?.map((shadow) => shadow.toString()).toList(),
      'backgroundColor': backgroundColor?.toARGB32(),
      'textColor': textColor?.toARGB32(),
      'fontSize': fontSize,
      'fontWeight': fontWeight?.value,
      'fontFamily': fontFamily,
    };
  }
}

class _RevolutPayButtonIosState extends State<RevolutPayButtonIos> {
  Map<String, dynamic>? _buttonConfig;
  bool _isLoading = true;

  /// Channel that receives payment results from the native button. It is created
  /// once the native button exists, using a per-button name so that multiple
  /// buttons on the same screen don't collide.
  MethodChannel? _paymentChannel;

  @override
  void initState() {
    super.initState();
    _createButton();
  }

  @override
  void dispose() {
    _paymentChannel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return widget.loadingWidget ?? _buildDefaultLoading();
    }
    if (_buttonConfig == null) {
      return widget.placeholderWidget ?? _buildDefaultLoading();
    }
    return _buildIOSButton();
  }

  Future<void> _createButton() async {
    try {
      setState(() => _isLoading = true);

      final result = await RevolutSdkBridgeIos.createRevolutPayButtonIos(
        orderToken: widget.config.orderToken,
        amount: widget.config.amount,
        currency: widget.config.currency,
        email: widget.config.email,
        shouldRequestShipping: widget.config.shouldRequestShipping,
        savePaymentMethodForMerchant: widget.config.savePaymentMethodForMerchant,
        returnURL: widget.config.returnURL,
        merchantName: widget.config.merchantName,
        merchantLogoURL: widget.config.merchantLogoURL,
        additionalData: widget.config.additionalData,
      );

      if (!mounted) return;

      if (result != null && result['buttonCreated'] == true) {
        final viewId = result['viewId'];
        _paymentChannel = MethodChannel('revolut_pay_button_payment_$viewId')
          ..setMethodCallHandler(_handlePaymentChannelCall);

        setState(() {
          _buttonConfig = result;
          _isLoading = false;
        });
        widget.onButtonCreated?.call();
      } else {
        throw Exception(
          'Failed to create button: ${result?['message'] ?? 'Unknown error'}',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      widget.onError?.call(e.toString());
      widget.onButtonError?.call();
    }
  }

  Future<void> _handlePaymentChannelCall(MethodCall call) async {
    if (!mounted) return;
    if (call.method == 'onPaymentResult' && call.arguments is Map) {
      _handlePaymentResult(Map<String, dynamic>.from(call.arguments as Map));
    }
  }

  void _handlePaymentResult(Map<String, dynamic> resultData) {
    final success = resultData['success'] as bool? ?? false;
    final message = resultData['message'] as String? ?? '';
    final error = resultData['error'] as String? ?? '';

    if (success) {
      widget.onPaymentResult?.call(
        RevolutPaymentResultIos(
          success: true,
          message: message,
          error: '',
          timestamp: DateTime.now(),
        ),
      );
      return;
    }

    final lowerMessage = message.toLowerCase();
    if (error == 'user_abandoned_payment' ||
        lowerMessage.contains('abandoned') ||
        lowerMessage.contains('cancelled')) {
      widget.onPaymentCancelled?.call();
    } else {
      final failure = error.isNotEmpty ? error : 'Payment failed';
      widget.onError?.call(failure);
      widget.onPaymentError?.call(failure);
    }
  }

  Widget _buildIOSButton() {
    final creationParams = {
      ..._buttonConfig!,
      'buttonId': _buttonConfig!['viewId'],
      'style': widget.style?.toMap(),
    };

    return Container(
      height: widget.style?.height ?? 50,
      width: widget.style?.width,
      margin: widget.style?.margin,
      child: UiKitView(
        viewType: 'revolut_pay_button',
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
      ),
    );
  }

  Widget _buildDefaultLoading() {
    return Container(
      height: widget.style?.height ?? 50,
      width: widget.style?.width,
      margin: widget.style?.margin,
      padding: widget.style?.padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.style?.backgroundColor ?? Colors.grey[300],
        borderRadius: widget.style?.borderRadius ?? BorderRadius.circular(8),
        border: widget.style?.border,
        boxShadow: widget.style?.boxShadow,
      ),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              widget.style?.textColor ?? Colors.grey[600]!,
            ),
          ),
        ),
      ),
    );
  }
}
