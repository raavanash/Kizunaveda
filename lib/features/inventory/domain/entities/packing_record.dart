/// PackingRecord entity tracking packaged products produced at Neemrana.
class PackingRecord {
  final String id;
  final String locationId;
  final String productId;
  final String? rawMaterialId;
  final double rawMaterialConsumed;
  final int packedQuantity;
  final double wastageQuantity;
  final DateTime packedAt;
  final DateTime createdAt;

  const PackingRecord({
    required this.id,
    required this.locationId,
    required this.productId,
    this.rawMaterialId,
    this.rawMaterialConsumed = 0.0,
    required this.packedQuantity,
    this.wastageQuantity = 0.0,
    required this.packedAt,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'location_id': locationId,
      'product_id': productId,
      'raw_material_id': rawMaterialId,
      'raw_material_consumed': rawMaterialConsumed,
      'packed_quantity': packedQuantity,
      'wastage_quantity': wastageQuantity,
      'packed_at': packedAt.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory PackingRecord.fromJson(Map<String, dynamic> json) {
    return PackingRecord(
      id: json['id'] as String,
      locationId: (json['location_id'] ?? json['locationId'] ?? '') as String,
      productId: (json['product_id'] ?? json['productId']) as String,
      rawMaterialId: (json['raw_material_id'] ?? json['rawMaterialId']) as String?,
      rawMaterialConsumed: ((json['raw_material_consumed'] ?? json['rawMaterialConsumed'] ?? 0) as num).toDouble(),
      packedQuantity: (json['packed_quantity'] ?? json['packedQuantity']) as int,
      wastageQuantity: ((json['wastage_quantity'] ?? json['wastageQuantity'] ?? 0) as num).toDouble(),
      packedAt: json['packed_at'] != null
          ? DateTime.parse(json['packed_at'] as String)
          : DateTime.now(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}
