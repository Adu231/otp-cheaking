import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sms_message.dart';

class SmsStorageService {
  static const String _keySmsHistory = 'sms_gateway_history_log';
  static const int _maxStoredMessages = 150;

  /// Load persisted SMS message history from local storage
  Future<List<SmsMessage>> loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? jsonList = prefs.getStringList(_keySmsHistory);
      if (jsonList == null) return [];

      return jsonList
          .map((str) => SmsMessage.fromJson(jsonDecode(str) as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Save or update an SMS message in local history
  Future<void> saveOrUpdateMessage(SmsMessage message) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<SmsMessage> currentList = await loadHistory();

      final existingIndex = currentList.indexWhere((m) => m.id == message.id);
      if (existingIndex >= 0) {
        currentList[existingIndex] = message;
      } else {
        currentList.insert(0, message);
      }

      // Keep only up to max items to preserve storage
      if (currentList.length > _maxStoredMessages) {
        currentList.removeRange(_maxStoredMessages, currentList.length);
      }

      final List<String> encodedList =
          currentList.map((m) => jsonEncode(m.toJson())).toList();
      await prefs.setStringList(_keySmsHistory, encodedList);
    } catch (_) {}
  }

  /// Clear all stored history
  Future<void> clearHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keySmsHistory);
    } catch (_) {}
  }
}

