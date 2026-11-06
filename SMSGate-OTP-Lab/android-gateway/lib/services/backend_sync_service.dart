import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import '../models/sms_message.dart';
import 'sms_dispatcher_service.dart';

typedef LogCallback = void Function(SmsMessage message);
typedef ConnectionCallback = void Function(bool isConnected, String? message);

class BackendSyncService {
  final SmsDispatcherService _smsDispatcher;

  Timer? _pollingTimer;
  bool _isRunning = false;
  String _backendUrl = AppConstants.defaultBackendUrl;
  String _deviceToken = '';
  int _simSlot = 0;
  int _pollingIntervalSeconds = AppConstants.defaultPollingIntervalSeconds;

  LogCallback? onMessageDispatched;
  ConnectionCallback? onConnectionStatusChanged;

  BackendSyncService({required SmsDispatcherService smsDispatcher})
      : _smsDispatcher = smsDispatcher {
    _loadSettings();
    _smsDispatcher.onStatusChanged = _handleSmsStatusChanged;
  }

  bool get isRunning => _isRunning;
  String get backendUrl => _backendUrl;
  int get simSlot => _simSlot;

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _backendUrl = prefs.getString(AppConstants.keyBackendUrl) ?? AppConstants.defaultBackendUrl;
    _deviceToken = prefs.getString(AppConstants.keyDeviceToken) ?? '';
    _simSlot = prefs.getInt(AppConstants.keyDefaultSimSlot) ?? AppConstants.defaultSimSlot;
    _pollingIntervalSeconds = prefs.getInt(AppConstants.keyPollingInterval) ?? AppConstants.defaultPollingIntervalSeconds;
  }

  Future<void> updateConfig({
    required String backendUrl,
    required String deviceToken,
    required int simSlot,
    required int pollingIntervalSeconds,
  }) async {
    _backendUrl = backendUrl.replaceAll(RegExp(r'/+$'), '');
    _deviceToken = deviceToken;
    _simSlot = simSlot;
    _pollingIntervalSeconds = pollingIntervalSeconds;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyBackendUrl, _backendUrl);
    await prefs.setString(AppConstants.keyDeviceToken, _deviceToken);
    await prefs.setInt(AppConstants.keyDefaultSimSlot, _simSlot);
    await prefs.setInt(AppConstants.keyPollingInterval, _pollingIntervalSeconds);

    // Restart timer with new interval if currently running
    if (_isRunning) {
      stopSync();
      startSync();
    }
  }

  /// Start background polling to Node.js backend
  void startSync() {
    if (_isRunning) return;
    _isRunning = true;
    _smsDispatcher.startForegroundService();
    onConnectionStatusChanged?.call(true, 'Gateway service started. Polling $_backendUrl...');

    // Run first check immediately
    _pollPendingSmsRequests();

    // Start periodic polling timer
    _pollingTimer = Timer.periodic(
      Duration(seconds: _pollingIntervalSeconds),
      (_) => _pollPendingSmsRequests(),
    );
  }

  /// Stop background polling
  void stopSync() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _isRunning = false;
    _smsDispatcher.stopForegroundService();
    onConnectionStatusChanged?.call(false, 'Gateway service stopped.');
  }

  /// Poll Node.js backend for pending OTP SMS dispatch jobs
  Future<void> _pollPendingSmsRequests() async {
    try {
      final uri = Uri.parse('$_backendUrl/api/gateway/pending');
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (_deviceToken.isNotEmpty) 'x-gateway-token': _deviceToken,
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        onConnectionStatusChanged?.call(true, 'Connected to Node.js backend');
        final data = jsonDecode(response.body);

        if (data is Map && data['tasks'] is List) {
          final List tasks = data['tasks'];
          for (final taskJson in tasks) {
            final task = SmsMessage.fromJson(Map<String, dynamic>.from(taskJson));
            await _dispatchIncomingTask(task);
          }
        }
      } else {
        onConnectionStatusChanged?.call(false, 'Server returned HTTP ${response.statusCode}');
      }
    } catch (e) {
      onConnectionStatusChanged?.call(false, 'Cannot reach server at $_backendUrl');
    }
  }

  /// Send individual SMS via SIM and notify listeners
  Future<void> _dispatchIncomingTask(SmsMessage message) async {
    final updatedMessage = message.copyWith(status: SmsStatus.sending);
    onMessageDispatched?.call(updatedMessage);

    final success = await _smsDispatcher.sendSms(
      phoneNumber: message.phoneNumber,
      message: message.message,
      messageId: message.id,
      simSlot: _simSlot,
    );

    if (!success) {
      final failedMessage = message.copyWith(
        status: SmsStatus.failed,
        errorMessage: 'Failed to invoke Android SmsManager',
      );
      onMessageDispatched?.call(failedMessage);
      await reportStatusToBackend(failedMessage);
    }
  }

  /// Broadcast callback from native Kotlin layer when SIM finishes transmission
  void _handleSmsStatusChanged(String messageId, SmsStatus status, String? errorMessage) {
    final update = SmsMessage(
      id: messageId,
      phoneNumber: '',
      message: '',
      status: status,
      errorMessage: errorMessage,
    );

    onMessageDispatched?.call(update);
    reportStatusToBackend(update);
  }

  /// Report status (Sent, Failed, Delivered) back to our Node.js backend
  Future<void> reportStatusToBackend(SmsMessage message) async {
    try {
      final uri = Uri.parse('$_backendUrl/api/gateway/status');
      await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (_deviceToken.isNotEmpty) 'x-gateway-token': _deviceToken,
        },
        body: jsonEncode({
          'messageId': message.id,
          'status': message.status.name,
          'errorMessage': message.errorMessage,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      // Offline status queueing can be implemented here
    }
  }
}

