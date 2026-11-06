import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../models/gateway_stats.dart';
import '../models/sms_message.dart';
import '../services/backend_sync_service.dart';
import '../services/permission_service.dart';
import '../services/sms_dispatcher_service.dart';
import '../widgets/sms_log_tile.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final BackendSyncService syncService;
  final PermissionService permissionService;
  final SmsDispatcherService dispatcherService;

  const HomeScreen({
    super.key,
    required this.syncService,
    required this.permissionService,
    required this.dispatcherService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _hasPermissions = false;
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

    widget.syncService.onConnectionStatusChanged = (connected, message) {
      if (!mounted) return;
      setState(() {
        _isConnected = connected;
        _statusMessage = message ?? (connected ? 'Online' : 'Offline');
      });
    };

    widget.syncService.onMessageDispatched = (message) {
      if (!mounted) return;
      setState(() {
        final existingIndex = _logs.indexWhere((m) => m.id == message.id);
        if (existingIndex >= 0) {
          _logs[existingIndex] = message;
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

  void _toggleService(bool enable) {
    if (enable) {
      if (!_hasPermissions) {
        _requestPermissions();
        return;
      }
      widget.syncService.startSync();
    } else {
      widget.syncService.stopSync();
    }
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
              final phone = phoneCtrl.text.trim();
              final msg = messageCtrl.text.trim();
              if (phone.isNotEmpty && msg.isNotEmpty) {
                final messageId = 'test_${DateTime.now().millisecondsSinceEpoch}';
                widget.dispatcherService.sendSms(
                  phoneNumber: phone,
                  message: msg,
                  messageId: messageId,
                  simSlot: widget.syncService.simSlot,
                );
                final testMsg = SmsMessage(
                  id: messageId,
                  phoneNumber: phone,
                  message: msg,
                  status: SmsStatus.sending,
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
            onPressed: () async {
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
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _checkPermissions();
          await _loadSimCards();
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

            // Service Master Switch Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.between,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Gateway Dispatcher',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _statusMessage,
                              style: TextStyle(
                                fontSize: 12,
                                color: isRunning
                                    ? (_isConnected ? AppTheme.successColor : AppTheme.warningColor)
                                    : AppTheme.textMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        Switch.adaptive(
                          value: isRunning,
                          activeColor: AppTheme.primaryColor,
                          onChanged: _toggleService,
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Target: ${widget.syncService.backendUrl}',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        ),
                        if (_simCards.isNotEmpty)
                          Text(
                            'Active: ${_simCards[0]['carrierName'] ?? 'SIM 1'}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textColor),
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
              mainAxisAlignment: MainAxisAlignment.between,
              children: [
                const Text(
                  'Recent SMS Activity',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textColor),
                ),
                if (_logs.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _logs.clear()),
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

