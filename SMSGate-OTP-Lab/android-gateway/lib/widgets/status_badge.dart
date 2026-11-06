import 'package:flutter/material.dart';
import '../models/sms_message.dart';

class StatusBadge extends StatelessWidget {
  final SmsStatus status;

  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String label;
    IconData icon;

    switch (status) {
      case SmsStatus.pending:
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFD97706);
        label = 'Pending';
        icon = Icons.hourglass_top_rounded;
        break;
      case SmsStatus.sending:
        bg = const Color(0xFFE0F2FE);
        fg = const Color(0xFF0284C7);
        label = 'Sending';
        icon = Icons.sync_rounded;
        break;
      case SmsStatus.sent:
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF16A34A);
        label = 'Sent';
        icon = Icons.check_circle_outline_rounded;
        break;
      case SmsStatus.delivered:
        bg = const Color(0xFFD1FAE5);
        fg = const Color(0xFF059669);
        label = 'Delivered';
        icon = Icons.done_all_rounded;
        break;
      case SmsStatus.failed:
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFDC2626);
        label = 'Failed';
        icon = Icons.error_outline_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

