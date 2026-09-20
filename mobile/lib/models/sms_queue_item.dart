class SmsQueueItem {
  final String id;
  final String ownerId;
  final String tenantId;
  final String body;
  final int scheduledAt;
  String status;

  SmsQueueItem({
    required this.id, 
    required this.ownerId, 
    required this.tenantId, 
    required this.body, 
    required this.scheduledAt, 
    this.status = 'queued'
  });

  factory SmsQueueItem.fromMap(Map<String, dynamic> map) {
    return SmsQueueItem(
      id: map['id'] ?? '',
      ownerId: map['ownerId'] ?? '',
      tenantId: map['tenantId'] ?? '',
      body: map['body'] ?? '',
      scheduledAt: map['scheduledAt'] ?? 0,
      status: map['status'] ?? 'queued',
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'ownerId': ownerId,
    'tenantId': tenantId,
    'body': body,
    'scheduledAt': scheduledAt,
    'status': status,
  };
}
