import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import '../models/sms_message.dart';
import 'sms_dispatcher_service.dart';

typedef LogCallback = void Function(SmsMessage message);
typedef ConnectionCallback = void Function(bool isConnected, String? message);

class BackendSyncService {
  final SmsDispatcherService _smsDispatcher;

  bool _isRunning = false;
  String _backendUrl = AppConstants.defaultBackendUrl;
  String _deviceToken = AppConstants.defaultDeviceToken;
  int _simSlot = 0;
  int _pollingIntervalSeconds = AppConstants.defaultPollingIntervalSeconds;

  LogCallback? onMessageDispatched;
  ConnectionCallback? onConnectionStatusChanged;

  BackendSyncService({required SmsDispatcherService smsDispatcher})
      : _smsDispatcher = smsDispatcher {
    _smsDispatcher.onStatusChanged = _handleSmsStatusChanged;
    _smsDispatcher.onConnectionChanged = _handleNativeConnectionChanged;
    _smsDispatcher.onMessageDispatched = _handleNativeMessageDispatched;
  }

  bool get isRunning => _isRunning;
  String get backendUrl => _backendUrl;
  String get deviceToken => _deviceToken;
  int get simSlot => _simSlot;
  int get pollingIntervalSeconds => _pollingIntervalSeconds;

  /// Clean and normalize the backend URL to ensure no duplicate /api segments or trailing slashes
  static String normalizeBackendUrl(String rawUrl) {
    var clean = rawUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (clean.endsWith('/api')) {
      clean = clean.substring(0, clean.length - 4);
    }
    if (clean.isEmpty) {
      clean = AppConstants.defaultBackendUrl;
    }
    return clean;
  }

  /// Asynchronous initialization that MUST be awaited in main() before UI renders
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    final savedUrl = prefs.getString(AppConstants.keyBackendUrl);
    if (savedUrl == null || savedUrl.isEmpty || savedUrl.contains('10.0.2.2')) {
      _backendUrl = AppConstants.defaultBackendUrl;
      await prefs.setString(AppConstants.keyBackendUrl, _backendUrl);
    } else {
      _backendUrl = normalizeBackendUrl(savedUrl);
    }

    final savedToken = prefs.getString(AppConstants.keyDeviceToken);
    if (savedToken == null || savedToken.isEmpty) {
      _deviceToken = AppConstants.defaultDeviceToken;
      await prefs.setString(AppConstants.keyDeviceToken, _deviceToken);
    } else {
      _deviceToken = savedToken.trim();
    }

    _simSlot = prefs.getInt(AppConstants.keyDefaultSimSlot) ?? AppConstants.defaultSimSlot;
    _pollingIntervalSeconds = prefs.getInt(AppConstants.keyPollingInterval) ??
        AppConstants.defaultPollingIntervalSeconds;

    // Sync configuration to native Android SharedPreferences
    await _smsDispatcher.syncNativeConfig(
      backendUrl: _backendUrl,
      deviceToken: _deviceToken,
      pollingInterval: _pollingIntervalSeconds,
      simSlot: _simSlot,
    );

    // Check if native background service is already running
    _isRunning = await _smsDispatcher.isServiceRunning();
  }

  /// Update and permanently persist Gateway settings
  Future<void> updateConfig({
    required String backendUrl,
    required String deviceToken,
    required int simSlot,
    required int pollingIntervalSeconds,
  }) async {
    _backendUrl = normalizeBackendUrl(backendUrl);

    // Guard: Never overwrite a valid saved token with an empty string
    final cleanToken = deviceToken.trim();
    if (cleanToken.isNotEmpty) {
      _deviceToken = cleanToken;
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

    // Sync directly to Android Native SharedPreferences
    await _smsDispatcher.syncNativeConfig(
      backendUrl: _backendUrl,
      deviceToken: _deviceToken,
      pollingInterval: _pollingIntervalSeconds,
      simSlot: _simSlot,
    );

    // If service is currently active, restart native service to load new settings
    if (_isRunning) {
      await stopSync();
      await startSync();
    }
  }

  /// Check current native service state and connection
  Future<void> refreshStatus() async {
    _isRunning = await _smsDispatcher.isServiceRunning();
    if (_isRunning) {
      final statusMap = await _smsDispatcher.getConnectionStatus();
      final isConnected = statusMap['isConnected'] as bool? ?? false;
      final msg = statusMap['message']?.toString();
      onConnectionStatusChanged?.call(isConnected, msg);
    } else {
      onConnectionStatusChanged?.call(false, 'Service idle');
    }
  }

  /// Start persistent native Android Foreground Service
  Future<bool> startSync() async {
    final success = await _smsDispatcher.startForegroundService();
    if (success) {
      _isRunning = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppConstants.keyServiceEnabled, true);

      onConnectionStatusChanged?.call(true, 'Gateway service started. Polling $_backendUrl...');
    }
    return success;
  }

  /// Stop persistent native Android Foreground Service
  Future<bool> stopSync() async {
    final success = await _smsDispatcher.stopForegroundService();
    _isRunning = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyServiceEnabled, false);

    onConnectionStatusChanged?.call(false, 'Gateway service stopped.');
    return success;
  }

  void _handleNativeConnectionChanged(bool isConnected, String message) {
    onConnectionStatusChanged?.call(isConnected, message);
  }

  void _handleNativeMessageDispatched(Map<String, dynamic> taskData) {
    final message = SmsMessage(
      id: taskData['id']?.toString() ?? '',
      phoneNumber: taskData['phoneNumber']?.toString() ?? '',
      message: taskData['message']?.toString() ?? '',
      status: SmsStatus.sending,
      simSlot: taskData['simSlot'] is int ? taskData['simSlot'] : _simSlot,
      timestamp: DateTime.now(),
    );
    onMessageDispatched?.call(message);
  }

  void _handleSmsStatusChanged(String messageId, SmsStatus status, String? errorMessage) {
    final update = SmsMessage(
      id: messageId,
      phoneNumber: '',
      message: '',
      status: status,
      errorMessage: errorMessage,
      simSlot: _simSlot,
      timestamp: DateTime.now(),
    );
    onMessageDispatched?.call(update);
  }
}
