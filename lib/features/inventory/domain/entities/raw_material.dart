/// RawMaterial entity representing bulk raw inputs at Neemrana.
class RawMaterial {
  final String id;
  final String name;
  final String unitOfMeasure;
  final bool active;
  final DateTime createdAt;

  const RawMaterial({
    required this.id,
    required this.name,
    required this.unitOfMeasure,
    this.active = true,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'unit_of_measure': unitOfMeasure,
      'active': active,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory RawMaterial.fromJson(Map<String, dynamic> json) {
    return RawMaterial(
      id: json['id'] as String,
      name: json['name'] as String,
      unitOfMeasure: (json['unit_of_measure'] ?? json['unitOfMeasure'] ?? 'KG') as String,
      active: json['active'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}
