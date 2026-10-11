enum TransferStatus { dispatched, received, discrepancy }

/// StockTransfer entity tracking finished packets moving from Neemrana to Jaipur.
class StockTransfer {
  final String id;
  final String productId;
  final String fromLocationId;
  final String toLocationId;
  final int dispatchedQuantity;
  final int? receivedQuantity;
  final DateTime dispatchedAt;
  final DateTime? receivedAt;
  final String? discrepancyReason;
  final DateTime createdAt;

  const StockTransfer({
    required this.id,
    required this.productId,
    required this.fromLocationId,
    required this.toLocationId,
    required this.dispatchedQuantity,
    this.receivedQuantity,
    required this.dispatchedAt,
    this.receivedAt,
    this.discrepancyReason,
    required this.createdAt,
  });

  bool get isReceived => receivedQuantity != null;
  bool get isPending => receivedQuantity == null;
  int get discrepancy => isReceived ? (dispatchedQuantity - (receivedQuantity ?? 0)) : 0;
  bool get hasDiscrepancy => isReceived && (receivedQuantity != dispatchedQuantity);

  TransferStatus get status {
    if (isPending) return TransferStatus.dispatched;
    if (hasDiscrepancy) return TransferStatus.discrepancy;
    return TransferStatus.received;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'from_location_id': fromLocationId,
      'to_location_id': toLocationId,
      'dispatched_quantity': dispatchedQuantity,
      'received_quantity': receivedQuantity,
      'dispatched_at': dispatchedAt.toIso8601String(),
      'received_at': receivedAt?.toIso8601String(),
      'discrepancy_reason': discrepancyReason,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory StockTransfer.fromJson(Map<String, dynamic> json) {
    return StockTransfer(
      id: json['id'] as String,
      productId: (json['product_id'] ?? json['productId']) as String,
      fromLocationId:
          (json['from_location_id'] ?? json['fromLocationId'] ?? '') as String,
      toLocationId:
          (json['to_location_id'] ?? json['toLocationId'] ?? '') as String,
      dispatchedQuantity:
          (json['dispatched_quantity'] ?? json['dispatchedQuantity']) as int,
      receivedQuantity:
          (json['received_quantity'] ?? json['receivedQuantity']) as int?,
      dispatchedAt: json['dispatched_at'] != null
          ? DateTime.parse(json['dispatched_at'] as String)
          : DateTime.now(),
      receivedAt: json['received_at'] != null
          ? DateTime.parse(json['received_at'] as String)
          : null,
      discrepancyReason:
          (json['discrepancy_reason'] ?? json['discrepancyReason']) as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  StockTransfer copyWith({
    String? id,
    String? productId,
    String? fromLocationId,
    String? toLocationId,
    int? dispatchedQuantity,
    int? receivedQuantity,
    DateTime? dispatchedAt,
    DateTime? receivedAt,
    String? discrepancyReason,
    DateTime? createdAt,
  }) {
    return StockTransfer(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      fromLocationId: fromLocationId ?? this.fromLocationId,
      toLocationId: toLocationId ?? this.toLocationId,
      dispatchedQuantity: dispatchedQuantity ?? this.dispatchedQuantity,
      receivedQuantity: receivedQuantity ?? this.receivedQuantity,
      dispatchedAt: dispatchedAt ?? this.dispatchedAt,
      receivedAt: receivedAt ?? this.receivedAt,
      discrepancyReason: discrepancyReason ?? this.discrepancyReason,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
