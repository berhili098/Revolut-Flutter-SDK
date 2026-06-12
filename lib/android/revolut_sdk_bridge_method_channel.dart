import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models/revolut_pay_models.dart';
import 'services/revolut_callbacks.dart';

/// Method channel implementation for Android Revolut SDK Bridge
/// This class handles all method calls and event streams between Flutter and native Android
class RevolutSdkBridgeMethodChannel {
  static const MethodChannel _channel = MethodChannel('revolut_sdk_bridge');
  static const EventChannel _eventChannel = EventChannel('revolut_sdk_bridge_events');

  final RevolutCallbacks _callbacks;
  StreamSubscription<dynamic>? _eventSubscription;
  bool _isInitialized = false;

  /// Creates a new method channel instance
  RevolutSdkBridgeMethodChannel(this._callbacks) {
    _setupEventChannel();

    // If event channel setup fails, retry after a short delay
    if (!isEventChannelReady) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!isEventChannelReady) {
          debugPrint('Retrying event channel setup...');
          _retryEventChannelSetup();
        }
      });
    }
  }

  /// Checks if the event channel is ready
  bool get isEventChannelReady => _eventSubscription != null;

  /// Checks if the SDK is initialized
  bool get isInitialized => _isInitialized;

  /// Ensures a platform map is returned as a `Map<String, dynamic>`
  Map<String, dynamic> _ensureStringDynamicMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      final mapped = value.map((key, v) => MapEntry(key.toString(), v));
      return Map<String, dynamic>.from(mapped);
    }
    throw FormatException(
      'Invalid response format from native side. Expected Map<String, dynamic>, got ${value.runtimeType}',
    );
  }

  /// Continues the confirmation flow
  Future<bool> continueConfirmationFlow({required String controllerId}) async {
    try {
      final result = await _channel.invokeMethod('continueConfirmationFlow', {'controllerId': controllerId});

      if (result is bool) {
        return result;
      } else if (result is Map) {
        return _ensureStringDynamicMap(result)['success'] as bool? ?? false;
      }
      return false;
    } on PlatformException catch (e) {
      debugPrint('Platform exception during continueConfirmationFlow: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Error during continueConfirmationFlow: $e');
      rethrow;
    }
  }

  /// Creates a controller for managing confirmation flows
  Future<ControllerResultData> createController() async {
    if (!_isInitialized) {
      throw StateError('Revolut SDK not initialized. Call init() first.');
    }

    try {
      final result = await _channel.invokeMethod('createController');

      if (result is Map) {
        return ControllerResultData.fromMap(_ensureStringDynamicMap(result));
      }
      throw FormatException('Invalid response format from native side');
    } on PlatformException catch (e) {
      debugPrint('Platform exception during createController: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Error during createController: $e');
      rethrow;
    }
  }

  /// Disposes the method channel and cleans up resources
  void dispose() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _isInitialized = false;
  }

  /// Disposes a controller
  Future<bool> disposeController({required String controllerId}) async {
    try {
      final result = await _channel.invokeMethod('disposeController', {'controllerId': controllerId});

      if (result is bool) {
        return result;
      } else if (result is Map) {
        return _ensureStringDynamicMap(result)['success'] as bool? ?? false;
      }
      return false;
    } on PlatformException catch (e) {
      debugPrint('Platform exception during disposeController: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Error during disposeController: $e');
      rethrow;
    }
  }

  /// Ensures the event channel is set up
  void ensureEventChannelReady() {
    if (!isEventChannelReady) {
      debugPrint('Event channel not ready, setting up...');
      _setupEventChannel();
    }
  }

  /// Gets the platform version
  Future<String> getPlatformVersion() async {
    try {
      final result = await _channel.invokeMethod('getPlatformVersion');

      if (result is String) {
        return result;
      }
      throw FormatException('Invalid response format from native side');
    } on PlatformException catch (e) {
      debugPrint('Platform exception during getPlatformVersion: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Error during getPlatformVersion: $e');
      rethrow;
    }
  }

  /// Gets the SDK version
  Future<Map<Object, dynamic>> getSdkVersion() async {
    try {
      debugPrint('Invoking getSdkVersion method...');
      final result = await _channel.invokeMethod('getSdkVersion');
      debugPrint('getSdkVersion raw result: $result');
      debugPrint('getSdkVersion result type: ${result.runtimeType}');

      final map = _ensureStringDynamicMap(result);
      debugPrint('getSdkVersion result is Map with keys: ${map.keys.toList()}');
      return map;
    } on PlatformException catch (e) {
      debugPrint('Platform exception during getSdkVersion: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Error during getSdkVersion: $e');
      rethrow;
    }
  }

  /// Initializes the Revolut Pay SDK
  Future<bool> init({required String environment, required String merchantPublicKey}) async {
    try {
      // Ensure event channel is ready before proceeding
      ensureEventChannelReady();

      final result = await _channel.invokeMethod('init', {
        'environment': environment,
        'merchantPublicKey': merchantPublicKey,
      });

      if (result is bool) {
        _isInitialized = result;
        return result;
      } else if (result is Map) {
        final success = result['success'] as bool? ?? false;
        _isInitialized = success;
        return success;
      }
      return false;
    } on PlatformException catch (e) {
      debugPrint('Platform exception during init: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Error during init: $e');
      rethrow;
    }
  }

  /// Initiates a payment flow
  Future<bool> pay({required String orderToken, bool savePaymentMethodForMerchant = false}) async {
    if (!_isInitialized) {
      throw StateError('Revolut SDK not initialized. Call init() first.');
    }

    try {
      final result = await _channel.invokeMethod('pay', {
        'orderToken': orderToken,
        'savePaymentMethodForMerchant': savePaymentMethodForMerchant,
      });

      if (result is bool) {
        return result;
      } else if (result is Map) {
        final map = _ensureStringDynamicMap(result);
        return map['success'] as bool? ?? map['status'] == 'initiated';
      }
      return false;
    } on PlatformException catch (e) {
      debugPrint('Platform exception during pay: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Error during pay: $e');
      rethrow;
    }
  }

  /// Creates a Revolut Pay button
  Future<ButtonResultData> provideButton({Map<String, dynamic>? buttonParams}) async {
    if (!_isInitialized) {
      throw StateError('Revolut SDK not initialized. Call init() first.');
    }

    try {
      final result = await _channel.invokeMethod('provideButton', {'buttonParams': buttonParams});

      if (result is Map) {
        return ButtonResultData.fromMap(_ensureStringDynamicMap(result));
      }
      throw FormatException('Invalid response format from native side');
    } on PlatformException catch (e) {
      debugPrint('Platform exception during provideButton: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Error during provideButton: $e');
      rethrow;
    }
  }

  /// Creates a promotional banner widget
  Future<BannerResultData> providePromotionalBannerWidget({Map<String, dynamic>? promoParams, String? themeId}) async {
    if (!_isInitialized) {
      throw StateError('Revolut SDK not initialized. Call init() first.');
    }

    try {
      final result = await _channel.invokeMethod('providePromotionalBannerWidget', {
        'promoParams': promoParams,
        'themeId': themeId,
      });

      if (result is Map) {
        return BannerResultData.fromMap(_ensureStringDynamicMap(result));
      }
      throw FormatException('Invalid response format from native side');
    } on PlatformException catch (e) {
      debugPrint('Platform exception during providePromotionalBannerWidget: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Error during providePromotionalBannerWidget: $e');
      rethrow;
    }
  }

  /// Sets the order token for a controller
  Future<bool> setOrderToken({required String orderToken, required String controllerId}) async {
    try {
      final result = await _channel.invokeMethod('setOrderToken', {
        'orderToken': orderToken,
        'controllerId': controllerId,
      });

      if (result is bool) {
        return result;
      } else if (result is Map) {
        return _ensureStringDynamicMap(result)['success'] as bool? ?? false;
      }
      return false;
    } on PlatformException catch (e) {
      debugPrint('Platform exception during setOrderToken: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Error during setOrderToken: $e');
      rethrow;
    }
  }

  /// Sets whether to save payment method for merchant
  Future<bool> setSavePaymentMethodForMerchant({
    required bool savePaymentMethodForMerchant,
    required String controllerId,
  }) async {
    try {
      final result = await _channel.invokeMethod('setSavePaymentMethodForMerchant', {
        'savePaymentMethodForMerchant': savePaymentMethodForMerchant,
        'controllerId': controllerId,
      });

      if (result is bool) {
        return result;
      } else if (result is Map) {
        return _ensureStringDynamicMap(result)['success'] as bool? ?? false;
      }
      return false;
    } on PlatformException catch (e) {
      debugPrint('Platform exception during setSavePaymentMethodForMerchant: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Error during setSavePaymentMethodForMerchant: $e');
      rethrow;
    }
  }

  /// Handles events received from the native side
  void _handleNativeEvent(dynamic event) {
    if (event is String) {
      try {
        final json = jsonDecode(event);
        _handleNativeEvent(json);
      } catch (_) {}
      return;
    }
    if (event is Map<Object?, Object?> && event is! Map<String, dynamic>) {
      try {
        final castedMap = event.map((key, value) => MapEntry(key.toString(), value));
        _handleNativeEvent(Map<String, dynamic>.from(castedMap));
        return;
      } catch (e) {
        debugPrint('Error handling native event map: $e');
      }
    }
    try {
      if (event is! Map<String, dynamic>) {
        debugPrint('Invalid event format received: $event with type of ${event.runtimeType}');
        return;
      }

      final methodName = event['method'] as String?;
      final data = Map<String, dynamic>.from(event['data']);

      if (methodName == null) {
        debugPrint('Invalid event structure: $event');
        return;
      }

      // LIVE LOG: Show all events in Flutter console
      debugPrint(
        '🔔 FLUTTER EVENT: $methodName - ${data.toString().substring(0, data.toString().length > 100 ? 100 : data.toString().length)}',
      );

      switch (methodName) {
        case 'onEventChannelReady':
          debugPrint('✅ Event channel is ready: $data');
          break;
        case 'printHello':
          debugPrint('👋 Print hello: $data');
          break;
        case 'onOrderCompleted':
          debugPrint('🎉 ORDER COMPLETED: $data');
          _callbacks.handleOrderCompleted(data);
          break;
        case 'onOrderFailed':
          debugPrint('❌ ORDER FAILED: $data');
          _callbacks.handleOrderFailed(data);
          break;
        case 'onUserPaymentAbandoned':
          debugPrint('⚠️ USER ABANDONED PAYMENT: $data');
          _callbacks.handleUserPaymentAbandoned(data);
          break;
        case 'onPaymentStatusUpdate':
          debugPrint('📊 PAYMENT STATUS UPDATE: $data');
          _callbacks.handlePaymentStatusUpdate(data);
          break;
        case 'onButtonClick':
          debugPrint('🔵 BUTTON CLICKED: $data');
          _callbacks.handleButtonClick(data);
          break;
        case 'onControllerStateChange':
          debugPrint('🔄 CONTROLLER STATE CHANGE: $data');
          _callbacks.handleControllerStateChange(data);
          break;
        case 'onBannerInteraction':
          _callbacks.handleBannerInteraction(data);
          break;
        case 'onLifecycleEvent':
          _callbacks.handleLifecycleEvent(data);
          break;
        case 'onDeepLinkReceived':
          debugPrint('🔗 DEEP LINK RECEIVED: $data');
          _callbacks.handleDeepLinkEvent(data);
          break;
        case 'onNetworkStatusUpdate':
          _callbacks.handleNetworkStatusUpdate(data);
          break;
        case 'onConfigurationUpdate':
          _callbacks.handleConfigurationUpdate(data);
          break;
        case 'onDebugLog':
          _callbacks.handleDebugLog(data);
          break;
        case 'onPerformanceMetric':
          _callbacks.handlePerformanceMetric(data);
          break;
        case 'onUserInteraction':
          _callbacks.handleUserInteraction(data);
          break;
        case 'onSessionEvent':
          _callbacks.handleSessionEvent(data);
          break;
        default:
          debugPrint('❓ Unknown event method: $methodName');
      }
    } catch (e) {
      debugPrint('❌ Error handling native event: $e');
      // Don't crash on event handling errors
    }
  }

  /// Retries setting up the event channel
  void _retryEventChannelSetup() {  
    if (_eventSubscription != null) {
      _eventSubscription?.cancel();
      _eventSubscription = null;
    }
    _setupEventChannel();
  }

  /// Sets up the event channel to listen for native events
  void _setupEventChannel() {
    try {
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
        (event) {
          _handleNativeEvent(event);
        },
        onError: (error) {
          debugPrint('Revolut SDK Bridge event channel error: $error');
          // Don't crash on event channel errors, just log them
        },
        cancelOnError: false, // Don't cancel the subscription on errors
      );
    } catch (e) {
      debugPrint('Failed to setup event channel: $e');
      // Don't crash if event channel setup fails
    }
  }
}
