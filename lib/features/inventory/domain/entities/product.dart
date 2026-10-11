/// Product entity representing finished goods or raw packaging variants.
class Product {
  final String id;
  final String name;
  final String packageSize;
  final String sku;
  final double standardSellingPrice;
  final double purchaseCost;
  final bool active;
  final DateTime createdAt;

  const Product({
    required this.id,
    required this.name,
    required this.packageSize,
    required this.sku,
    this.active = true,
    this.standardSellingPrice = 100.0,
    this.purchaseCost = 0.0,
    required this.createdAt,
  });

  /// Intelligent fallback price based on standard SKU conventions
  static double defaultPriceForSku(String sku) {
    final lower = sku.toLowerCase();
    if (lower.contains('triphala') || lower.contains('tri')) return 120.0;
    if (lower.contains('ashwa')) return 150.0;
    return 100.0;
  }

  /// Intelligent fallback purchase cost based on standard production conventions
  static double defaultCostForSku(String sku) {
    final lower = sku.toLowerCase();
    if (lower.contains('triphala') || lower.contains('tri')) return 55.0;
    if (lower.contains('ashwa')) return 70.0;
    if (lower.contains('tulsi')) return 45.0;
    return 0.0;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'package_size': packageSize,
      'sku': sku,
      'active': active,
      'standard_selling_price': standardSellingPrice,
      'purchase_cost': purchaseCost,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    final skuStr = (json['sku'] ?? '') as String;
    final rawPrice = json['standard_selling_price'] ??
        json['standardSellingPrice'] ??
        json['selling_price'] ??
        json['price'];
    final standardPrice = rawPrice != null
        ? (rawPrice as num).toDouble()
        : defaultPriceForSku(skuStr);

    final rawCost = json['purchase_cost'] ??
        json['purchaseCost'] ??
        json['cost'];
    final cost = rawCost != null
        ? (rawCost as num).toDouble()
        : defaultCostForSku(skuStr);

    return Product(
      id: json['id'] as String,
      name: json['name'] as String,
      packageSize:
          (json['package_size'] ?? json['packageSize'] ?? '') as String,
      sku: skuStr,
      active: (json['active'] as bool?) ?? true,
      standardSellingPrice: standardPrice,
      purchaseCost: cost,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Product copyWith({
    String? id,
    String? name,
    String? packageSize,
    String? sku,
    bool? active,
    double? standardSellingPrice,
    double? purchaseCost,
    DateTime? createdAt,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      packageSize: packageSize ?? this.packageSize,
      sku: sku ?? this.sku,
      active: active ?? this.active,
      standardSellingPrice:
          standardSellingPrice ?? this.standardSellingPrice,
      purchaseCost: purchaseCost ?? this.purchaseCost,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
