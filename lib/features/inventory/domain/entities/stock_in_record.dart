import 'location.dart';
import 'product.dart';

/// Auditable Stock-In entry for adding inventory directly to Neemrana or Jaipur.
class StockInRecord {
  final String id;
  final String locationId;
  final String productId;
  final int quantity;
  final String? notes;
  final String? createdBy;
  final DateTime createdAt;
  final Product? product;
  final Location? location;

  const StockInRecord({
    required this.id,
    required this.locationId,
    required this.productId,
    required this.quantity,
    this.notes,
    this.createdBy,
    required this.createdAt,
    this.product,
    this.location,
  });

  factory StockInRecord.fromJson(Map<String, dynamic> json) {
    return StockInRecord(
      id: json['id'] as String,
      locationId: json['location_id'] as String,
      productId: json['product_id'] as String,
      quantity: (json['quantity'] as num).toInt(),
      notes: json['notes'] as String?,
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      product: json['products'] != null
          ? Product.fromJson(json['products'] as Map<String, dynamic>)
          : null,
      location: json['locations'] != null
          ? Location.fromJson(json['locations'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'location_id': locationId,
      'product_id': productId,
      'quantity': quantity,
      'notes': notes,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
