import '../../../inventory/domain/entities/product.dart';

/// Represents an item in the active POS shopping cart.
class CartItem {
  final Product product;
  int quantity;
  double unitPrice;
  double discount;

  CartItem({
    required this.product,
    this.quantity = 1,
    double? unitPrice,
    this.discount = 0.0,
  }) : unitPrice = unitPrice ?? product.standardSellingPrice;

  /// Gross subtotal before discount: quantity * unitPrice
  double get grossTotal => quantity * unitPrice;

  /// Effective line total after discount: clamp to >= 0
  double get lineTotal {
    final net = grossTotal - discount;
    return net > 0 ? net : 0.0;
  }

  /// Whether the current selling price differs from the official catalog price
  bool get isPriceOverridden =>
      (unitPrice - product.standardSellingPrice).abs() > 0.001;

  /// Discount percentage relative to gross item total
  double get discountPercentage {
    if (grossTotal <= 0) return 0.0;
    return (discount / grossTotal) * 100.0;
  }

  CartItem copyWith({
    Product? product,
    int? quantity,
    double? unitPrice,
    double? discount,
  }) {
    return CartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      discount: discount ?? this.discount,
    );
  }

  /// Serializes into the line item JSON object required by Supabase `fn_create_pos_sale`
  Map<String, dynamic> toRpcItemJson({String? overrideReason}) {
    return {
      'product_id': product.id,
      'quantity': quantity,
      'unit_price': unitPrice,
      'discount': discount,
      'discount_amount': discount,
      if (isPriceOverridden)
        'override_reason': overrideReason ?? 'PRICE_OVERRIDE',
    };
  }
}
