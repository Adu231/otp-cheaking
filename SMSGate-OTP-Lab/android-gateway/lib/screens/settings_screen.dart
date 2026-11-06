import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../services/backend_sync_service.dart';

class SettingsScreen extends StatefulWidget {
  final BackendSyncService syncService;
  final List<Map<String, dynamic>> simCards;

  const SettingsScreen({
    super.key,
    required this.syncService,
    required this.simCards,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _urlController;
  late TextEditingController _tokenController;
  int _selectedSimSlot = 0;
  double _pollingInterval = 5.0;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.syncService.backendUrl);
    _tokenController = TextEditingController();
    _selectedSimSlot = widget.syncService.simSlot;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    await widget.syncService.updateConfig(
      backendUrl: _urlController.text.trim(),
      deviceToken: _tokenController.text.trim(),
      simSlot: _selectedSimSlot,
      pollingIntervalSeconds: _pollingInterval.toInt(),
    );

    setState(() => _isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved successfully'),
          backgroundColor: AppTheme.successColor,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gateway Configuration'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Node.js Backend Server Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Node.js Backend Endpoint',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'URL where our Node.js backend is running. For Android Emulator use 10.0.2.2, for physical phone use your PC\'s Wi-Fi IP (e.g. 192.168.1.x:5000).',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: 'Server Base URL',
                      hintText: 'http://192.168.1.100:5000',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.dns_rounded),
                    ),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tokenController,
                    decoration: const InputDecoration(
                      labelText: 'Device Secret Token (Optional)',
                      hintText: 'Enter secret token if configured',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.key_rounded),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Polling Interval Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.between,
                    children: [
                      const Text(
                        'Dispatch Polling Interval',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${_pollingInterval.toInt()}s',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primaryColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'How frequently the gateway polls the backend for pending OTP SMS jobs.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                  Slider(
                    value: _pollingInterval,
                    min: 2,
                    max: 30,
                    divisions: 14,
                    label: '${_pollingInterval.toInt()} seconds',
                    activeColor: AppTheme.primaryColor,
                    onChanged: (val) => setState(() => _pollingInterval = val),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // SIM Card Selection Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Default Outgoing SIM Card',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Choose which SIM slot on this phone dispatches the outgoing OTP SMS.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 10),
                  RadioListTile<int>(
                    title: Text(
                      widget.simCards.isNotEmpty
                          ? 'SIM 1 (${widget.simCards[0]['carrierName'] ?? 'Slot 0'})'
                          : 'SIM 1 (Default)',
                    ),
                    value: 0,
                    groupValue: _selectedSimSlot,
                    activeColor: AppTheme.primaryColor,
                    onChanged: (val) => setState(() => _selectedSimSlot = val ?? 0),
                  ),
                  RadioListTile<int>(
                    title: Text(
                      widget.simCards.length > 1
                          ? 'SIM 2 (${widget.simCards[1]['carrierName'] ?? 'Slot 1'})'
                          : 'SIM 2',
                    ),
                    value: 1,
                    groupValue: _selectedSimSlot,
                    activeColor: AppTheme.primaryColor,
                    onChanged: (val) => setState(() => _selectedSimSlot = val ?? 1),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          ElevatedButton(
            onPressed: _isSaving ? null : _saveSettings,
            child: _isSaving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save Gateway Settings'),
          ),
        ],
      ),
    );
  }
}

