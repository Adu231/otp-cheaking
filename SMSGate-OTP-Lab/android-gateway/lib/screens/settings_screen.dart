import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  bool _obscureToken = true;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.syncService.backendUrl);

    // Initial value from in-memory service
    final initialToken = widget.syncService.deviceToken.isNotEmpty
        ? widget.syncService.deviceToken
        : AppConstants.defaultDeviceToken;
    _tokenController = TextEditingController(text: initialToken);

    _selectedSimSlot = widget.syncService.simSlot;
    _pollingInterval = widget.syncService.pollingIntervalSeconds.toDouble();

    // Redundant verification directly from disk SharedPreferences
    _loadFromDisk();
  }

  Future<void> _loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final diskUrl = prefs.getString(AppConstants.keyBackendUrl);
      final diskToken = prefs.getString(AppConstants.keyDeviceToken);
      final diskSlot = prefs.getInt(AppConstants.keyDefaultSimSlot);
      final diskInterval = prefs.getInt(AppConstants.keyPollingInterval);

      if (mounted) {
        setState(() {
          if (diskUrl != null && diskUrl.isNotEmpty) {
            _urlController.text = BackendSyncService.normalizeBackendUrl(diskUrl);
          }
          if (diskToken != null && diskToken.isNotEmpty) {
            _tokenController.text = diskToken;
          }
          if (diskSlot != null) {
            _selectedSimSlot = diskSlot;
          }
          if (diskInterval != null && diskInterval > 0) {
            _pollingInterval = diskInterval.toDouble();
          }
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    final inputUrl = _urlController.text.trim();
    final inputToken = _tokenController.text.trim();

    // Guard: Never overwrite a valid saved token with an empty value
    String tokenToSave = inputToken;
    if (tokenToSave.isEmpty) {
      if (widget.syncService.deviceToken.isNotEmpty) {
        tokenToSave = widget.syncService.deviceToken;
      } else {
        tokenToSave = AppConstants.defaultDeviceToken;
      }
      _tokenController.text = tokenToSave;
    }

    final normalizedUrl = BackendSyncService.normalizeBackendUrl(
      inputUrl.isNotEmpty ? inputUrl : AppConstants.defaultBackendUrl,
    );
    _urlController.text = normalizedUrl;

    await widget.syncService.updateConfig(
      backendUrl: normalizedUrl,
      deviceToken: tokenToSave,
      simSlot: _selectedSimSlot,
      pollingIntervalSeconds: _pollingInterval.toInt(),
    );

    setState(() => _isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gateway Secret Token and Settings saved permanently!'),
          backgroundColor: AppTheme.successColor,
          duration: Duration(seconds: 3),
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
                    'Target URL of our live Node.js Express backend deployment (e.g. Render).',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: 'Server Base URL',
                      hintText: 'https://otp-cheaking-1.onrender.com',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.dns_rounded),
                    ),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Gateway Secret Token',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Must match GATEWAY_SECRET_TOKEN in backend environment variables. Sent in x-gateway-token header.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tokenController,
                    obscureText: _obscureToken,
                    decoration: InputDecoration(
                      labelText: 'Secret Token (x-gateway-token)',
                      hintText: 'smsgate_gateway_secret_2026',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.key_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureToken ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        ),
                        tooltip: _obscureToken ? 'Reveal token' : 'Hide token',
                        onPressed: () => setState(() => _obscureToken = !_obscureToken),
                      ),
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                    'How frequently the background service polls the backend for pending OTP SMS jobs.',
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
                    'Choose which SIM slot on this phone dispatches the outgoing OTP SMS. Airtel SIM is recommended.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 10),
                  RadioListTile<int>(
                    title: Text(
                      widget.simCards.isNotEmpty
                          ? 'SIM 1 (${widget.simCards[0]['carrierName'] ?? 'Slot 0'})'
                          : 'SIM 1 (Default / Airtel)',
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
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Save Gateway Settings'),
          ),
        ],
      ),
    );
  }
}
