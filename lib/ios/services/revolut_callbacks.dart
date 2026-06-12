import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Callback service for Revolut SDK operations
/// This service receives callbacks from the native platform plugins (iOS/Android)
class RevolutCallbacksIos {
  static const MethodChannel _logChannel = MethodChannel(
    'revolut_sdk_bridge_logs',
  );

  /// Callback for log entries
  static Function(RevolutLogEntryIos)? onLog;

  /// Callback for payment results
  static Function(RevolutPaymentResultIos)? onPaymentResult;

  /// Dispose the callback service
  static void dispose() {
    _logChannel.setMethodCallHandler(null);
  }

  /// Initialize the callback service and set up method channel handlers
  static void initialize() {
    _logChannel.setMethodCallHandler(_handleMethodCall);
  }

  /// Handle method calls from the native platform plugins
  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onLog':
        if (call.arguments != null && call.arguments is Map) {
          final logEntry = RevolutLogEntryIos.fromMap(
            Map<String, dynamic>.from(call.arguments),
          );
          onLog?.call(logEntry);

          // Also print to console for debugging
          debugPrint('Revolut SDK Log: $logEntry');
        }
        break;

      case 'onPaymentResult':
        if (call.arguments != null && call.arguments is Map) {
          final paymentResult = RevolutPaymentResultIos.fromMap(
            Map<String, dynamic>.from(call.arguments),
          );
          onPaymentResult?.call(paymentResult);

          // Also print to console for debugging
          debugPrint('Revolut Payment Result: $paymentResult');
        }
        break;

      default:
        debugPrint('Unknown method call: ${call.method}');
    }
  }
}

/// Log entry from the native Revolut SDK
class RevolutLogEntryIos {
  final RevolutLogLevelIos level;
  final String message;
  final DateTime timestamp;
  final String source;

  RevolutLogEntryIos({
    required this.level,
    required this.message,
    required this.timestamp,
    required this.source,
  });

  factory RevolutLogEntryIos.fromMap(Map<String, dynamic> map) {
    return RevolutLogEntryIos(
      level: _parseLogLevel(map['level'] as String?),
      message: map['message'] as String? ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        ((map['timestamp'] as num?) ?? 0).toInt(),
      ),
      source: map['source'] as String? ?? 'Unknown',
    );
  }

  @override
  String toString() {
    return '[${timestamp.toIso8601String()}] [$source] [${level.name.toUpperCase()}] $message';
  }

  static RevolutLogLevelIos _parseLogLevel(String? level) {
    switch (level?.toLowerCase()) {
      case 'success':
        return RevolutLogLevelIos.success;
      case 'warning':
        return RevolutLogLevelIos.warning;
      case 'error':
        return RevolutLogLevelIos.error;
      case 'info':
      default:
        return RevolutLogLevelIos.info;
    }
  }
}

/// Log levels for Revolut SDK operations
enum RevolutLogLevelIos { info, success, warning, error }

/// Payment result from the native Revolut SDK
class RevolutPaymentResultIos {
  final bool success;
  final String message;
  final String error;
  final DateTime timestamp;

  RevolutPaymentResultIos({
    required this.success,
    required this.message,
    required this.error,
    required this.timestamp,
  });

  factory RevolutPaymentResultIos.fromMap(Map<String, dynamic> map) {
    return RevolutPaymentResultIos(
      success: map['success'] as bool? ?? false,
      message: map['message'] as String? ?? '',
      error: map['error'] as String? ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        ((map['timestamp'] as num?) ?? 0).toInt(),
      ),
    );
  }

  @override
  String toString() {
    if (success) {
      return '[${timestamp.toIso8601String()}] SUCCESS: $message';
    } else {
      return '[${timestamp.toIso8601String()}] ERROR: $error';
    }
  }
}
