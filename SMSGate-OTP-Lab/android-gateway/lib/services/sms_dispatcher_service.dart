import 'package:flutter/services.dart';
import '../core/constants/app_constants.dart';
import '../models/sms_message.dart';

typedef SmsStatusCallback = void Function(String messageId, SmsStatus status, String? errorMessage);

class SmsDispatcherService {
  static const MethodChannel _channel = MethodChannel(AppConstants.smsMethodChannel);

  SmsStatusCallback? onStatusChanged;

  SmsDispatcherService() {
    _channel.setMethodCallHandler(_handleNativeMethodCall);
  }

  Future<dynamic> _handleNativeMethodCall(MethodCall call) async {
    if (call.method == 'onSmsStatusUpdated') {
      final Map<dynamic, dynamic> args = call.arguments as Map<dynamic, dynamic>;
      final String messageId = args['messageId']?.toString() ?? '';
      final String statusStr = args['status']?.toString() ?? '';
      final String? errorMessage = args['errorMessage']?.toString();

      SmsStatus status = SmsStatus.pending;
      if (statusStr == 'Sent') {
        status = SmsStatus.sent;
      } else if (statusStr == 'Delivered') {
        status = SmsStatus.delivered;
      } else if (statusStr == 'Failed' || statusStr == 'DeliveryFailed') {
        status = SmsStatus.failed;
      }

      onStatusChanged?.call(messageId, status, errorMessage);
    }
  }

  /// Dispatch SMS through native Android SmsManager
  Future<bool> sendSms({
    required String phoneNumber,
    required String message,
    required String messageId,
    int simSlot = 0,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('sendSMS', {
        'phoneNumber': phoneNumber,
        'message': message,
        'messageId': messageId,
        'simSlot': simSlot,
      });

      return result != null && result['success'] == true;
    } on PlatformException catch (e) {
      onStatusChanged?.call(messageId, SmsStatus.failed, e.message ?? 'Native SMS error');
      return false;
    } catch (e) {
      onStatusChanged?.call(messageId, SmsStatus.failed, e.toString());
      return false;
    }
  }

  /// Retrieve active SIM cards present in device
  Future<List<Map<String, dynamic>>> getActiveSimCards() async {
    try {
      final List<dynamic>? list = await _channel.invokeListMethod<dynamic>('getSimCards');
      if (list == null) return [];
      return list.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Check if device telephony is SMS capable
  Future<bool> isSmsCapable() async {
    try {
      final bool? capable = await _channel.invokeMethod<bool>('canSendSms');
      return capable ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Start persistent Android Foreground Service with sticky notification
  Future<bool> startForegroundService() async {
    try {
      final bool? res = await _channel.invokeMethod<bool>('startForegroundService');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Stop persistent Android Foreground Service
  Future<bool> stopForegroundService() async {
    try {
      final bool? res = await _channel.invokeMethod<bool>('stopForegroundService');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}

