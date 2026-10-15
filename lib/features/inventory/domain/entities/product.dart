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

  /// Calculate readable total weight/volume for a given packet quantity
  String calculateTotalWeight(int quantity) {
    if (quantity <= 0) return '0 pkts';
    final clean = packageSize.trim().toLowerCase();
    final match = RegExp(r'^(\d+(?:\.\d+)?)\s*([a-zA-Z]+)$').firstMatch(clean);
    if (match != null) {
      final value = double.tryParse(match.group(1)!) ?? 0;
      final unit = match.group(2)!;
      final totalVal = value * quantity;
      if (unit == 'g') {
        if (totalVal >= 1000) {
          final kg = totalVal / 1000;
          final kgStr = kg % 1 == 0 ? kg.toInt().toString() : kg.toStringAsFixed(2);
          final gStr = totalVal % 1 == 0 ? totalVal.toInt().toString() : totalVal.toStringAsFixed(1);
          return '$gStr g ($kgStr kg)';
        }
        final gStr = totalVal % 1 == 0 ? totalVal.toInt().toString() : totalVal.toStringAsFixed(1);
        return '$gStr g';
      } else if (unit == 'kg') {
        final kgStr = totalVal % 1 == 0 ? totalVal.toInt().toString() : totalVal.toStringAsFixed(2);
        return '$kgStr kg';
      } else if (unit == 'ml') {
        if (totalVal >= 1000) {
          final l = totalVal / 1000;
          final lStr = l % 1 == 0 ? l.toInt().toString() : l.toStringAsFixed(2);
          return '${totalVal.toInt()} ml ($lStr L)';
        }
        return '${totalVal.toInt()} ml';
      } else if (unit == 'l') {
        final lStr = totalVal % 1 == 0 ? totalVal.toInt().toString() : totalVal.toStringAsFixed(2);
        return '$lStr L';
      }
    }
    return '$quantity × $packageSize';
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

    final rawProcurement = json['product_procurement_costs'];
    final double? procurementCost = rawProcurement is Map
        ? (rawProcurement['purchase_cost'] as num?)?.toDouble()
        : rawProcurement is List && rawProcurement.isNotEmpty && rawProcurement.first is Map
            ? (rawProcurement.first['purchase_cost'] as num?)?.toDouble()
            : null;

    final rawCost = procurementCost ??
        (json['purchase_cost'] != null && (json['purchase_cost'] as num) > 0
            ? (json['purchase_cost'] as num).toDouble()
            : (json['purchaseCost'] != null && (json['purchaseCost'] as num) > 0
                ? (json['purchaseCost'] as num).toDouble()
                : (json['cost'] != null && (json['cost'] as num) > 0
                    ? (json['cost'] as num).toDouble()
                    : null)));
    final cost = rawCost ?? defaultCostForSku(skuStr);

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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Product && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
