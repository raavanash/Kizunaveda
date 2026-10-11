/// Location entity representing physical facilities (NEEMRANA, JAIPUR).
class Location {
  final String id;
  final String code;
  final String name;
  final String locationType;
  final bool active;
  final DateTime createdAt;

  const Location({
    required this.id,
    required this.code,
    required this.name,
    required this.locationType,
    this.active = true,
    required this.createdAt,
  });

  bool get isProduction => locationType.toUpperCase() == 'PRODUCTION';
  bool get isRetail => locationType.toUpperCase() == 'RETAIL';

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'code': code,
      'name': name,
      'location_type': locationType,
      'active': active,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Location.fromJson(Map<String, dynamic> json) {
    return Location(
      id: json['id'] as String,
      code: json['code'] as String,
      name: json['name'] as String,
      locationType:
          (json['location_type'] ?? json['locationType'] ?? '') as String,
      active: (json['active'] as bool?) ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  static const String neemranaId = '11111111-1111-1111-1111-111111111111';
  static const String jaipurId = '22222222-2222-2222-2222-222222222222';
}
