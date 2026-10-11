/// RawMaterialReceipt entity tracking incoming bulk raw material shipments at Neemrana.
class RawMaterialReceipt {
  final String id;
  final String rawMaterialId;
  final String locationId;
  final double quantity;
  final double cost;
  final String? supplierReference;
  final DateTime receivedAt;
  final DateTime createdAt;

  const RawMaterialReceipt({
    required this.id,
    required this.rawMaterialId,
    required this.locationId,
    required this.quantity,
    required this.cost,
    this.supplierReference,
    required this.receivedAt,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'raw_material_id': rawMaterialId,
      'location_id': locationId,
      'quantity': quantity,
      'cost': cost,
      'supplier_reference': supplierReference,
      'received_at': receivedAt.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory RawMaterialReceipt.fromJson(Map<String, dynamic> json) {
    return RawMaterialReceipt(
      id: json['id'] as String,
      rawMaterialId: (json['raw_material_id'] ?? json['rawMaterialId']) as String,
      locationId: (json['location_id'] ?? json['locationId'] ?? '') as String,
      quantity: (json['quantity'] as num).toDouble(),
      cost: (json['cost'] as num).toDouble(),
      supplierReference: json['supplier_reference'] as String?,
      receivedAt: json['received_at'] != null
          ? DateTime.parse(json['received_at'] as String)
          : DateTime.now(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}
