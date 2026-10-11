/// Entity representing an auditable stock adjustment ledger record.
class StockAdjustment {
  final String id;
  final String locationId;
  final String productId;
  final int previousQuantity;
  final int newQuantity;
  final int changeQuantity;
  final String reason;
  final String? notes;
  final String? createdBy;
  final DateTime createdAt;

  const StockAdjustment({
    required this.id,
    required this.locationId,
    required this.productId,
    required this.previousQuantity,
    required this.newQuantity,
    required this.changeQuantity,
    required this.reason,
    this.notes,
    this.createdBy,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'location_id': locationId,
      'product_id': productId,
      'previous_quantity': previousQuantity,
      'new_quantity': newQuantity,
      'change_quantity': changeQuantity,
      'reason': reason,
      'notes': notes,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory StockAdjustment.fromJson(Map<String, dynamic> json) {
    return StockAdjustment(
      id: json['id'] as String,
      locationId: json['location_id'] as String,
      productId: json['product_id'] as String,
      previousQuantity: (json['previous_quantity'] as num?)?.toInt() ?? 0,
      newQuantity: (json['new_quantity'] as num?)?.toInt() ?? 0,
      changeQuantity: (json['change_quantity'] as num?)?.toInt() ?? 0,
      reason: (json['reason'] as String?) ?? 'STOCK_ENTRY',
      notes: json['notes'] as String?,
      createdBy: json['created_by'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}
