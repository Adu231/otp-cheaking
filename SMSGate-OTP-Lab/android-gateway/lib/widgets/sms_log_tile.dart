import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/sms_message.dart';
import 'status_badge.dart';

class SmsLogTile extends StatelessWidget {
  final SmsMessage message;

  const SmsLogTile({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('HH:mm:ss').format(message.timestamp);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.phone_android_rounded, size: 16, color: Color(0xFF64748B)),
                    const SizedBox(width: 6),
                    Text(
                      message.phoneNumber.isNotEmpty ? message.phoneNumber : 'Recipient',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                StatusBadge(status: message.status),
              ],
            ),
            const SizedBox(height: 6),
            if (message.message.isNotEmpty)
              Text(
                message.message,
                style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            if (message.errorMessage != null) ...[
              const SizedBox(height: 4),
              Text(
                'Error: ${message.errorMessage}',
                style: const TextStyle(fontSize: 11, color: Color(0xFFDC2626), fontWeight: FontWeight.w500),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'ID: ${message.id.length > 12 ? message.id.substring(0, 12) : message.id}',
                  style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                ),
                Text(
                  timeStr,
                  style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

