class Payment {
  final String id;
  final String tenantId;
  final int month;
  final int year;
  final double amount;
  final String status; // pending | paid

  Payment({required this.id, required this.tenantId, required this.month, required this.year, required this.amount, required this.status});

  factory Payment.fromMap(Map<String, dynamic> m) => Payment(
        id: m['id'] as String,
        tenantId: m['tenantId'] as String? ?? '',
        month: m['month'] as int? ?? 0,
        year: m['year'] as int? ?? 0,
        amount: (m['amount'] is int) ? (m['amount'] as int).toDouble() : (m['amount'] as double? ?? 0.0),
        status: m['status'] as String? ?? 'pending',
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'tenantId': tenantId,
        'month': month,
        'year': year,
        'amount': amount,
        'status': status,
      };
}
