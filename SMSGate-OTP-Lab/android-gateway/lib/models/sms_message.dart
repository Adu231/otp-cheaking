enum SmsStatus {
  pending,
  sending,
  sent,
  delivered,
  failed,
}

class SmsMessage {
  final String id;
  final String phoneNumber;
  final String message;
  final SmsStatus status;
  final String? errorMessage;
  final int simSlot;
  final DateTime timestamp;

  SmsMessage({
    required this.id,
    required this.phoneNumber,
    required this.message,
    this.status = SmsStatus.pending,
    this.errorMessage,
    this.simSlot = 0,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  SmsMessage copyWith({
    String? id,
    String? phoneNumber,
    String? message,
    SmsStatus? status,
    String? errorMessage,
    int? simSlot,
    DateTime? timestamp,
  }) {
    return SmsMessage(
      id: id ?? this.id,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      message: message ?? this.message,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      simSlot: simSlot ?? this.simSlot,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  factory SmsMessage.fromJson(Map<String, dynamic> json) {
    return SmsMessage(
      id: json['id']?.toString() ?? '',
      phoneNumber: json['phoneNumber'] ?? json['to'] ?? '',
      message: json['message'] ?? json['text'] ?? '',
      status: _parseStatus(json['status']?.toString()),
      errorMessage: json['errorMessage'],
      simSlot: json['simSlot'] is int ? json['simSlot'] : 0,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp']) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phoneNumber': phoneNumber,
      'message': message,
      'status': status.name,
      'errorMessage': errorMessage,
      'simSlot': simSlot,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  static SmsStatus _parseStatus(String? str) {
    switch (str?.toLowerCase()) {
      case 'sending':
        return SmsStatus.sending;
      case 'sent':
        return SmsStatus.sent;
      case 'delivered':
        return SmsStatus.delivered;
      case 'failed':
        return SmsStatus.failed;
      default:
        return SmsStatus.pending;
    }
  }
}

