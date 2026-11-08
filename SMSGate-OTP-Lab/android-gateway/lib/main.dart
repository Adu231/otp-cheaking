import 'package:flutter/material.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'services/backend_sync_service.dart';
import 'services/permission_service.dart';
import 'services/sms_dispatcher_service.dart';
import 'services/sms_storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Instantiate singleton services
  final permissionService = PermissionService();
  final dispatcherService = SmsDispatcherService();
  final syncService = BackendSyncService(smsDispatcher: dispatcherService);
  final storageService = SmsStorageService();

  // Guarantee persistent settings are fully loaded before UI mounts
  await syncService.init();

  runApp(AndroidGatewayApp(
    permissionService: permissionService,
    dispatcherService: dispatcherService,
    syncService: syncService,
    storageService: storageService,
  ));
}

class AndroidGatewayApp extends StatelessWidget {
  final PermissionService permissionService;
  final SmsDispatcherService dispatcherService;
  final BackendSyncService syncService;
  final SmsStorageService storageService;

  const AndroidGatewayApp({
    super.key,
    required this.permissionService,
    required this.dispatcherService,
    required this.syncService,
    required this.storageService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: HomeScreen(
        permissionService: permissionService,
        dispatcherService: dispatcherService,
        syncService: syncService,
        storageService: storageService,
      ),
    );
  }
}
