/// Entity representing canonical physical on-hand inventory per store and per product.
class StoreInventory {
  final String id;
  final String locationId;
  final String productId;
  final int currentQuantity;
  final DateTime updatedAt;

  const StoreInventory({
    required this.id,
    required this.locationId,
    required this.productId,
    required this.currentQuantity,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'location_id': locationId,
      'product_id': productId,
      'current_quantity': currentQuantity,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory StoreInventory.fromJson(Map<String, dynamic> json) {
    return StoreInventory(
      id: json['id'] as String,
      locationId: json['location_id'] as String,
      productId: json['product_id'] as String,
      currentQuantity: (json['current_quantity'] as num?)?.toInt() ?? 0,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }

  StoreInventory copyWith({
    String? id,
    String? locationId,
    String? productId,
    int? currentQuantity,
    DateTime? updatedAt,
  }) {
    return StoreInventory(
      id: id ?? this.id,
      locationId: locationId ?? this.locationId,
      productId: productId ?? this.productId,
      currentQuantity: currentQuantity ?? this.currentQuantity,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
