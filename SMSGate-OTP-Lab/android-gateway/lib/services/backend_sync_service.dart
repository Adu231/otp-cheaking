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
  String _deviceToken = AppConstants.defaultDeviceToken;
  int _simSlot = 0;
  int _pollingIntervalSeconds = AppConstants.defaultPollingIntervalSeconds;

  // Deduplication & in-flight task tracking to prevent duplicate SMS transmissions
  final Set<String> _inFlightTaskIds = {};
  final Set<String> _dispatchedTaskIds = {};
  final Map<String, SmsMessage> _taskCache = {};
  final List<SmsMessage> _pendingStatusQueue = [];

  LogCallback? onMessageDispatched;
  ConnectionCallback? onConnectionStatusChanged;

  BackendSyncService({required SmsDispatcherService smsDispatcher})
      : _smsDispatcher = smsDispatcher {
    _loadSettings();
    _smsDispatcher.onStatusChanged = _handleSmsStatusChanged;
  }

  bool get isRunning => _isRunning;
  String get backendUrl => _backendUrl;
  String get deviceToken => _deviceToken;
  int get simSlot => _simSlot;
  int get pollingIntervalSeconds => _pollingIntervalSeconds;

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final savedUrl = prefs.getString(AppConstants.keyBackendUrl);
    if (savedUrl == null || savedUrl.isEmpty || savedUrl.contains('10.0.2.2')) {
      _backendUrl = AppConstants.defaultBackendUrl;
      await prefs.setString(AppConstants.keyBackendUrl, _backendUrl);
    } else {
      _backendUrl = savedUrl.replaceAll(RegExp(r'/+$'), '');
    }

    final savedToken = prefs.getString(AppConstants.keyDeviceToken);
    if (savedToken == null || savedToken.isEmpty) {
      _deviceToken = AppConstants.defaultDeviceToken;
      await prefs.setString(AppConstants.keyDeviceToken, _deviceToken);
    } else {
      _deviceToken = savedToken;
    }

    _simSlot = prefs.getInt(AppConstants.keyDefaultSimSlot) ?? AppConstants.defaultSimSlot;
    _pollingIntervalSeconds = prefs.getInt(AppConstants.keyPollingInterval) ?? AppConstants.defaultPollingIntervalSeconds;
  }

  Future<void> updateConfig({
    required String backendUrl,
    required String deviceToken,
    required int simSlot,
    required int pollingIntervalSeconds,
  }) async {
    _backendUrl = backendUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (_backendUrl.isEmpty) {
      _backendUrl = AppConstants.defaultBackendUrl;
    }

    // Preserve valid token if empty string was passed unintentionally
    if (deviceToken.trim().isNotEmpty) {
      _deviceToken = deviceToken.trim();
    } else if (_deviceToken.isEmpty) {
      _deviceToken = AppConstants.defaultDeviceToken;
    }

    _simSlot = simSlot;
    _pollingIntervalSeconds = pollingIntervalSeconds > 0
        ? pollingIntervalSeconds
        : AppConstants.defaultPollingIntervalSeconds;

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
          'x-gateway-token': _deviceToken,
          'x-gateway-id': 'android-gateway',
        },
      ).timeout(const Duration(seconds: 25)); // 25s for Render cold start tolerance

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data is Map && data['tasks'] is List) {
          final List tasks = data['tasks'];
          final count = tasks.length;
          onConnectionStatusChanged?.call(
            true,
            count > 0
                ? 'Connected: Claimed $count pending SMS task${count > 1 ? 's' : ''}'
                : 'Connected: Waiting for OTP requests...',
          );

          // Flush any status updates queued while temporarily offline
          await _flushPendingStatusQueue();

          for (final taskJson in tasks) {
            final task = SmsMessage.fromJson(Map<String, dynamic>.from(taskJson));
            if (task.id.isEmpty) continue;

            // Deduplication guard: ignore already in-flight or recently dispatched tasks
            if (_inFlightTaskIds.contains(task.id) || _dispatchedTaskIds.contains(task.id)) {
              continue;
            }

            _inFlightTaskIds.add(task.id);
            _taskCache[task.id] = task;
            await _dispatchIncomingTask(task);
          }
        } else {
          onConnectionStatusChanged?.call(true, 'Connected to backend');
        }
      } else if (response.statusCode == 401) {
        onConnectionStatusChanged?.call(
          false,
          'HTTP 401: Unauthorized gateway token. Check settings.',
        );
      } else if (response.statusCode == 404) {
        onConnectionStatusChanged?.call(
          false,
          'HTTP 404: Endpoint /api/gateway/pending not found.',
        );
      } else {
        onConnectionStatusChanged?.call(
          false,
          'Server returned HTTP ${response.statusCode}',
        );
      }
    } on TimeoutException {
      onConnectionStatusChanged?.call(
        false,
        'Connection timeout (Render backend may be spinning up). Retrying...',
      );
    } catch (e) {
      onConnectionStatusChanged?.call(
        false,
        'Cannot reach server at $_backendUrl',
      );
    }
  }

  /// Send individual SMS via SIM and notify listeners
  Future<void> _dispatchIncomingTask(SmsMessage message) async {
    final updatedMessage = message.copyWith(status: SmsStatus.sending);
    _taskCache[message.id] = updatedMessage;
    onMessageDispatched?.call(updatedMessage);

    final success = await _smsDispatcher.sendSms(
      phoneNumber: message.phoneNumber,
      message: message.message,
      messageId: message.id,
      simSlot: _simSlot,
    );

    if (!success) {
      _inFlightTaskIds.remove(message.id);
      _dispatchedTaskIds.add(message.id);
      final failedMessage = message.copyWith(
        status: SmsStatus.failed,
        errorMessage: 'Failed to invoke Android SmsManager',
      );
      _taskCache[message.id] = failedMessage;
      onMessageDispatched?.call(failedMessage);
      await reportStatusToBackend(failedMessage);
    }
  }

  /// Broadcast callback from native Kotlin layer when SIM finishes transmission
  void _handleSmsStatusChanged(String messageId, SmsStatus status, String? errorMessage) {
    if (status == SmsStatus.sent || status == SmsStatus.delivered || status == SmsStatus.failed) {
      _inFlightTaskIds.remove(messageId);
      _dispatchedTaskIds.add(messageId);
      if (_dispatchedTaskIds.length > 500) {
        _dispatchedTaskIds.remove(_dispatchedTaskIds.first);
      }
    }

    final cached = _taskCache[messageId];
    final update = SmsMessage(
      id: messageId,
      phoneNumber: cached?.phoneNumber ?? '',
      message: cached?.message ?? '',
      status: status,
      errorMessage: errorMessage ?? cached?.errorMessage,
      simSlot: cached?.simSlot ?? _simSlot,
      timestamp: cached?.timestamp ?? DateTime.now(),
    );
    _taskCache[messageId] = update;

    onMessageDispatched?.call(update);
    reportStatusToBackend(update);
  }

  /// Report status (Sent, Failed, Delivered) back to our Node.js backend
  Future<void> reportStatusToBackend(SmsMessage message) async {
    try {
      final uri = Uri.parse('$_backendUrl/api/gateway/status');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'x-gateway-token': _deviceToken,
          'x-gateway-id': 'android-gateway',
        },
        body: jsonEncode({
          'messageId': message.id,
          'status': message.status.name,
          'errorMessage': message.errorMessage,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Success
      } else {
        _queuePendingStatus(message);
      }
    } catch (_) {
      _queuePendingStatus(message);
    }
  }

  void _queuePendingStatus(SmsMessage message) {
    if (!_pendingStatusQueue.any((m) => m.id == message.id && m.status == message.status)) {
      _pendingStatusQueue.add(message);
    }
  }

  Future<void> _flushPendingStatusQueue() async {
    if (_pendingStatusQueue.isEmpty) return;
    final toRetry = List<SmsMessage>.from(_pendingStatusQueue);
    _pendingStatusQueue.clear();
    for (final msg in toRetry) {
      await reportStatusToBackend(msg);
    }
  }
}
