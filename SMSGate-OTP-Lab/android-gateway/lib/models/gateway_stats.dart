class GatewayStats {
  final int totalSent;
  final int totalDelivered;
  final int totalFailed;
  final int totalPending;
  final bool isConnected;
  final DateTime? lastSyncTime;

  GatewayStats({
    this.totalSent = 0,
    this.totalDelivered = 0,
    this.totalFailed = 0,
    this.totalPending = 0,
    this.isConnected = false,
    this.lastSyncTime,
  });

  GatewayStats copyWith({
    int? totalSent,
    int? totalDelivered,
    int? totalFailed,
    int? totalPending,
    bool? isConnected,
    DateTime? lastSyncTime,
  }) {
    return GatewayStats(
      totalSent: totalSent ?? this.totalSent,
      totalDelivered: totalDelivered ?? this.totalDelivered,
      totalFailed: totalFailed ?? this.totalFailed,
      totalPending: totalPending ?? this.totalPending,
      isConnected: isConnected ?? this.isConnected,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
    );
  }
}

