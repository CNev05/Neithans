class Violation {
  final String id;
  final String tenantId;
  final String tenantName;
  final String tenantUnit;
  final String violationType;
  final String description;
  final double fine;
  final DateTime violationDate;
  final String status; // 'pending', 'paid', 'resolved'

  Violation({
    required this.id,
    required this.tenantId,
    required this.tenantName,
    required this.tenantUnit,
    required this.violationType,
    required this.description,
    required this.fine,
    required this.violationDate,
    required this.status,
  });

  factory Violation.fromMap(Map<String, dynamic> m) => Violation(
        id: m['id'] as String,
        tenantId: m['tenantId'] as String? ?? '',
        tenantName: m['tenantName'] as String? ?? '',
        tenantUnit: m['tenantUnit'] as String? ?? '',
        violationType: m['violationType'] as String? ?? '',
        description: m['description'] as String? ?? '',
        fine: (m['fine'] as num?)?.toDouble() ?? 0.0,
        violationDate: DateTime.parse(m['violationDate'] as String? ?? DateTime.now().toIso8601String()),
        status: m['status'] as String? ?? 'pending',
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'tenantId': tenantId,
        'tenantName': tenantName,
        'tenantUnit': tenantUnit,
        'violationType': violationType,
        'description': description,
        'fine': fine,
        'violationDate': violationDate.toIso8601String(),
        'status': status,
      };
}
