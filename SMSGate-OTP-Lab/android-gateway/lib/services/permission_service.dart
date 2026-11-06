import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  /// Check whether all essential permissions for SMS gateway operation are granted
  Future<bool> hasAllPermissions() async {
    final smsGranted = await Permission.sms.isGranted;
    final phoneGranted = await Permission.phone.isGranted;
    return smsGranted && phoneGranted;
  }

  /// Request essential permissions: SMS, Phone State, and Notifications
  Future<Map<Permission, PermissionStatus>> requestAllPermissions() async {
    final statuses = await [
      Permission.sms,
      Permission.phone,
      Permission.notification,
    ].request();

    // Check battery optimization ignore request if available
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }

    return statuses;
  }

  /// Check individual SMS permission
  Future<bool> isSmsPermissionGranted() async {
    return await Permission.sms.isGranted;
  }

  /// Check phone state permission
  Future<bool> isPhoneStateGranted() async {
    return await Permission.phone.isGranted;
  }

  /// Open application system settings if permissions are permanently denied
  Future<bool> openSettings() async {
    return await openAppSettings();
  }
}

