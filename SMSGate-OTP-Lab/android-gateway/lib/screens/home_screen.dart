import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../models/gateway_stats.dart';
import '../models/sms_message.dart';
import '../services/backend_sync_service.dart';
import '../services/permission_service.dart';
import '../services/sms_dispatcher_service.dart';
import '../services/sms_storage_service.dart';
import '../widgets/sms_log_tile.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final BackendSyncService syncService;
  final PermissionService permissionService;
  final SmsDispatcherService dispatcherService;
  final SmsStorageService? storageService;

  const HomeScreen({
    super.key,
    required this.syncService,
    required this.permissionService,
    required this.dispatcherService,
    this.storageService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _hasPermissions = false;
  bool _isBatteryOptimizationIgnored = true;
  bool _isConnected = false;
  String _statusMessage = 'Service idle';

  final List<SmsMessage> _logs = [];
  GatewayStats _stats = GatewayStats();
  List<Map<String, dynamic>> _simCards = [];

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _loadSimCards();
    _checkBatteryOptimization();

    // Check if background service is already running on device
    widget.syncService.refreshStatus().then((_) {
      if (mounted) setState(() {});
    });

    widget.storageService?.loadHistory().then((history) {
      if (!mounted) return;
      setState(() {
        _logs.addAll(history);
        _recalculateStats();
      });
    });

    widget.syncService.onConnectionStatusChanged = (connected, message) {
      if (!mounted) return;
      setState(() {
        _isConnected = connected;
        _statusMessage = message ?? (connected ? 'Online' : 'Offline');
      });
    };

    widget.syncService.onMessageDispatched = (message) {
      if (!mounted) return;
      widget.storageService?.saveOrUpdateMessage(message);
      setState(() {
        final existingIndex = _logs.indexWhere((m) => m.id == message.id);
        if (existingIndex >= 0) {
          final existing = _logs[existingIndex];
          _logs[existingIndex] = existing.copyWith(
            status: message.status,
            errorMessage: message.errorMessage ?? existing.errorMessage,
            phoneNumber: message.phoneNumber.isNotEmpty ? message.phoneNumber : existing.phoneNumber,
            message: message.message.isNotEmpty ? message.message : existing.message,
          );
        } else {
          _logs.insert(0, message);
        }
        _recalculateStats();
      });
    };
  }

  void _recalculateStats() {
    int sent = 0;
    int delivered = 0;
    int failed = 0;
    int pending = 0;

    for (final m in _logs) {
      if (m.status == SmsStatus.sent) sent++;
      if (m.status == SmsStatus.delivered) delivered++;
      if (m.status == SmsStatus.failed) failed++;
      if (m.status == SmsStatus.pending || m.status == SmsStatus.sending) pending++;
    }

    _stats = _stats.copyWith(
      totalSent: sent,
      totalDelivered: delivered,
      totalFailed: failed,
      totalPending: pending,
    );
  }

  Future<void> _checkPermissions() async {
    final granted = await widget.permissionService.hasAllPermissions();
    if (!mounted) return;
    setState(() {
      _hasPermissions = granted;
    });
  }

  Future<void> _checkBatteryOptimization() async {
    final ignored = await widget.dispatcherService.isBatteryOptimizationIgnored();
    if (!mounted) return;
    setState(() {
      _isBatteryOptimizationIgnored = ignored;
    });
  }

  Future<void> _requestPermissions() async {
    await widget.permissionService.requestAllPermissions();
    await _checkPermissions();
    await _loadSimCards();
  }

  Future<void> _loadSimCards() async {
    final sims = await widget.dispatcherService.getActiveSimCards();
    if (!mounted) return;
    setState(() {
      _simCards = sims;
    });
  }

  Future<void> _toggleService(bool enable) async {
    if (enable) {
      if (!_hasPermissions) {
        await _requestPermissions();
        if (!_hasPermissions) return;
      }
      await widget.syncService.startSync();
    } else {
      await widget.syncService.stopSync();
    }
    setState(() {});
  }

  void _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => SettingsScreen(
          syncService: widget.syncService,
          simCards: _simCards,
        ),
      ),
    );
    _loadSimCards();
    widget.syncService.refreshStatus();
    setState(() {});
  }

  void _showSendTestSmsDialog() {
    final phoneCtrl = TextEditingController();
    final messageCtrl = TextEditingController(text: 'Test OTP verification code: 123456');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send Manual Test SMS'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: phoneCtrl,
              decoration: const InputDecoration(
                labelText: 'Recipient Phone (+91XXXXXXXXXX)',
                hintText: '+919876543210',
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: messageCtrl,
              decoration: const InputDecoration(labelText: 'Message Body'),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final rawPhone = phoneCtrl.text.trim();
              final msg = messageCtrl.text.trim();
              if (rawPhone.isNotEmpty && msg.isNotEmpty) {
                final normalizedPhone = SmsDispatcherService.normalizePhoneNumber(rawPhone);
                final messageId = 'test_${DateTime.now().millisecondsSinceEpoch}';
                widget.dispatcherService.sendSms(
                  phoneNumber: normalizedPhone,
                  message: msg,
                  messageId: messageId,
                  simSlot: widget.syncService.simSlot,
                );
                final testMsg = SmsMessage(
                  id: messageId,
                  phoneNumber: normalizedPhone,
                  message: msg,
                  status: SmsStatus.sending,
                  simSlot: widget.syncService.simSlot,
                );
                setState(() {
                  _logs.insert(0, testMsg);
                  _recalculateStats();
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Send via SIM'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = widget.syncService.isRunning;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.cell_tower_rounded, color: AppTheme.primaryColor),
            SizedBox(width: 8),
            Text('Android SMS Gateway'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Gateway Settings',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _checkPermissions();
          await _loadSimCards();
          await _checkBatteryOptimization();
          await widget.syncService.refreshStatus();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Permission Banner (if missing)
            if (!_hasPermissions)
              Card(
                color: const Color(0xFFFEF2F2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Color(0xFFFECACA)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppTheme.errorColor),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'SMS & Phone permissions are required to send SMS through SIM.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF991B1B)),
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.errorColor,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                        onPressed: _requestPermissions,
                        child: const Text('Grant'),
                      ),
                    ],
                  ),
                ),
              ),

            // Battery Optimization Banner (if active)
            if (!_isBatteryOptimizationIgnored)
              Card(
                color: const Color(0xFFEFF6FF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Color(0xFFBFDBFE)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.battery_alert_rounded, color: AppTheme.primaryColor),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Disable battery optimization to allow persistent 24/7 background operation.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF1E40AF)),
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                        onPressed: () async {
                          await widget.dispatcherService.requestIgnoreBatteryOptimizations();
                          await _checkBatteryOptimization();
                        },
                        child: const Text('Exempt'),
                      ),
                    ],
                  ),
                ),
              ),

            // Service Master Switch Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    'Gateway Service',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isRunning
                                          ? AppTheme.successColor.withOpacity(0.15)
                                          : Colors.grey.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      isRunning ? 'RUNNING' : 'STOPPED',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: isRunning ? AppTheme.successColor : AppTheme.textMuted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _statusMessage,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isRunning
                                      ? (_statusMessage.contains('401')
                                          ? AppTheme.errorColor
                                          : (_isConnected ? AppTheme.successColor : AppTheme.warningColor))
                                      : AppTheme.textMuted,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch.adaptive(
                          value: isRunning,
                          activeColor: AppTheme.primaryColor,
                          onChanged: _toggleService,
                        ),
                      ],
                    ),
                    if (_statusMessage.contains('401')) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, size: 14, color: AppTheme.errorColor),
                          const SizedBox(width: 4),
                          const Expanded(
                            child: Text(
                              'Device secret token does not match backend GATEWAY_SECRET_TOKEN.',
                              style: TextStyle(fontSize: 11, color: AppTheme.errorColor),
                            ),
                          ),
                          TextButton(
                            onPressed: _openSettings,
                            child: const Text('Update Token', style: TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                    ],
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Target: ${widget.syncService.backendUrl}',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_simCards.isNotEmpty)
                          Builder(
                            builder: (context) {
                              Map<String, dynamic>? activeSim;
                              for (final s in _simCards) {
                                if (s['isAirtel'] == true) {
                                  activeSim = s;
                                  break;
                                }
                              }
                              activeSim ??= _simCards.firstWhere(
                                (s) => s['slotIndex'] == widget.syncService.simSlot,
                                orElse: () => _simCards.first,
                              );
                              return Text(
                                'SIM: ${activeSim['carrierName']} (Slot ${activeSim['slotIndex']})',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textColor),
                              );
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Token: ${widget.syncService.deviceToken.isNotEmpty ? "•••••••• (${widget.syncService.deviceToken.length} chars)" : "Not Configured"}',
                          style: TextStyle(
                            fontSize: 11,
                            color: widget.syncService.deviceToken.isNotEmpty ? AppTheme.successColor : AppTheme.warningColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'Poll: ${widget.syncService.pollingIntervalSeconds}s',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Statistics Row
            Row(
              children: [
                _buildStatCard('Sent', _stats.totalSent.toString(), AppTheme.primaryColor, Icons.send_rounded),
                const SizedBox(width: 8),
                _buildStatCard('Delivered', _stats.totalDelivered.toString(), AppTheme.successColor, Icons.done_all_rounded),
                const SizedBox(width: 8),
                _buildStatCard('Failed', _stats.totalFailed.toString(), AppTheme.errorColor, Icons.cancel_outlined),
              ],
            ),
            const SizedBox(height: 16),

            // Activity Log Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recent SMS Activity',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textColor),
                ),
                if (_logs.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      widget.storageService?.clearHistory();
                      setState(() => _logs.clear());
                    },
                    child: const Text('Clear', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Activity List
            if (_logs.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 40),
                alignment: Alignment.center,
                child: const Column(
                  children: [
                    Icon(Icons.inbox_outlined, size: 36, color: Color(0xFFCBD5E1)),
                    SizedBox(height: 8),
                    Text(
                      'No SMS requests processed yet.',
                      style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              )
            else
              ..._logs.map((m) => SmsLogTile(message: m)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showSendTestSmsDialog,
        backgroundColor: AppTheme.primaryColor,
        icon: const Icon(Icons.sms_outlined, color: Colors.white),
        label: const Text('Test Send', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
