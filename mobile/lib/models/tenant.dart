class Tenant {
  final String id;
  final String ownerId;
  final String name;
  final String phone;
  final String unit;

  Tenant({required this.id, required this.ownerId, required this.name, required this.phone, required this.unit});

  factory Tenant.fromMap(Map<String, dynamic> m) => Tenant(
        id: m['id'] as String,
        ownerId: m['ownerId'] as String? ?? '',
        name: m['name'] as String? ?? '',
        phone: m['phone'] as String? ?? '',
        unit: m['unit'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'ownerId': ownerId,
        'name': name,
        'phone': phone,
        'unit': unit,
      };
}
