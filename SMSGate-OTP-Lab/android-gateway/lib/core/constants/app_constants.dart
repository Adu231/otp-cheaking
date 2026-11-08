class AppConstants {
  static const String appTitle = 'In-House SMS Gateway';
  
  // Method Channel for native Android SMSManager integration
  static const String smsMethodChannel = 'com.smsgate.android_gateway/sms';

  // SharedPreferences Keys
  static const String keyBackendUrl = 'backend_server_url';
  static const String keyDeviceToken = 'gateway_device_token';
  static const String keyPollingInterval = 'polling_interval_seconds';
  static const String keyDefaultSimSlot = 'default_sim_slot';
  static const String keyAutoStartService = 'auto_start_service';

  // Default configuration values
  // Live backend hosted on Render
  static const String defaultBackendUrl = 'https://otp-cheaking-1.onrender.com';
  static const String defaultDeviceToken = 'smsgate_gateway_secret_2026';
  static const int defaultPollingIntervalSeconds = 5;
  static const int defaultSimSlot = 0; // SIM 1
}

