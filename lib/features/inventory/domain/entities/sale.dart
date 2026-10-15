/// Line item for a retail sale bill at Jaipur or Neemrana.
class SaleItem {
  final String id;
  final String saleId;
  final String productId;
  final int quantity;
  final double unitPrice;
  final double discount;
  final double? unitCost;
  final DateTime createdAt;
  final String? productName;
  final String? sku;
  final String? packageSize;

  const SaleItem({
    required this.id,
    required this.saleId,
    required this.productId,
    required this.quantity,
    this.unitPrice = 0.0,
    this.discount = 0.0,
    this.unitCost,
    required this.createdAt,
    this.productName,
    this.sku,
    this.packageSize,
  });

  /// Computed line item total: (quantity * unitPrice) - discount
  double get lineTotal => (quantity * unitPrice) - discount;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sale_id': saleId,
      'product_id': productId,
      'quantity': quantity,
      'unit_price': unitPrice,
      'discount_amount': discount,
      'unit_cost': unitCost,
      'created_at': createdAt.toIso8601String(),
      if (productName != null) 'product_name': productName,
      if (sku != null) 'sku': sku,
      if (packageSize != null) 'package_size': packageSize,
    };
  }

  factory SaleItem.fromJson(Map<String, dynamic> json) {
    return SaleItem(
      id: json['id'] as String,
      saleId: (json['sale_id'] ?? json['saleId'] ?? '') as String,
      productId: (json['product_id'] ?? json['productId']) as String,
      quantity: ((json['quantity'] ?? json['qty'] ?? 1) as num).toInt(),
      unitPrice:
          ((json['unit_price'] ?? json['unitPrice'] ?? 0) as num).toDouble(),
      discount: ((json['discount_amount'] ??
              json['discountAmount'] ??
              json['discount'] ??
              0) as num)
          .toDouble(),
      unitCost: () {
        final rawProc = json['sale_item_procurement_costs'];
        final double? procCost = rawProc is Map
            ? (rawProc['unit_cost'] as num?)?.toDouble()
            : rawProc is List && rawProc.isNotEmpty && rawProc.first is Map
                ? (rawProc.first['unit_cost'] as num?)?.toDouble()
                : null;
        if (procCost != null) return procCost;
        final raw = json['unit_cost'] ?? json['unitCost'] ?? json['purchase_cost'];
        if (raw is num && raw > 0) {
          return raw.toDouble();
        }
        return null;
      }(),
      productName: (json['product_name'] ??
          (json['products'] is Map ? json['products']['name'] : null) ??
          (json['product'] is Map ? json['product']['name'] : null)) as String?,
      sku: (json['sku'] ??
          (json['products'] is Map ? json['products']['sku'] : null) ??
          (json['product'] is Map ? json['product']['sku'] : null)) as String?,
      packageSize: (json['package_size'] ??
          (json['products'] is Map ? json['products']['package_size'] : null) ??
          (json['product'] is Map ? json['product']['package_size'] : null)) as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}

/// Parent Sale entity tracking retail sales bills.
class Sale {
  final String id;
  final String locationId;
  final String billNumber;
  final String? customerName;
  final String? customerPhone;
  final String paymentMethod; // 'CASH' or 'UPI'
  final String invoiceType; // 'NON_GST' or 'GST'
  final double gstRate;
  final double taxableAmount;
  final double cgstAmount;
  final double sgstAmount;
  final double igstAmount;
  final String whatsappStatus;
  final double totalAmount;
  final String status; // 'COMPLETED' or 'VOIDED'
  final String productId; // Primary product ID for single-product shorthand
  final int quantity; // Primary quantity for single-product shorthand
  final List<SaleItem> items;
  final DateTime soldAt;
  final DateTime createdAt;

  const Sale({
    required this.id,
    required this.locationId,
    required this.billNumber,
    this.customerName,
    this.customerPhone,
    this.paymentMethod = 'CASH',
    this.invoiceType = 'NON_GST',
    this.gstRate = 0.0,
    this.taxableAmount = 0.0,
    this.cgstAmount = 0.0,
    this.sgstAmount = 0.0,
    this.igstAmount = 0.0,
    this.whatsappStatus = 'NOT_SENT',
    this.totalAmount = 0.0,
    this.status = 'COMPLETED',
    required this.productId,
    required this.quantity,
    this.items = const [],
    required this.soldAt,
    required this.createdAt,
  });

  bool get isCompleted => status.toUpperCase() == 'COMPLETED';
  bool get isVoided => status.toUpperCase() == 'VOIDED';
  bool get isGst => invoiceType.toUpperCase() == 'GST';
  bool get isCash => paymentMethod.toUpperCase() == 'CASH';
  bool get isUpi => paymentMethod.toUpperCase() == 'UPI';

  Sale copyWith({
    String? id,
    String? locationId,
    String? billNumber,
    String? customerName,
    String? customerPhone,
    String? paymentMethod,
    String? invoiceType,
    double? gstRate,
    double? taxableAmount,
    double? cgstAmount,
    double? sgstAmount,
    double? igstAmount,
    String? whatsappStatus,
    double? totalAmount,
    String? status,
    String? productId,
    int? quantity,
    List<SaleItem>? items,
    DateTime? soldAt,
    DateTime? createdAt,
  }) {
    return Sale(
      id: id ?? this.id,
      locationId: locationId ?? this.locationId,
      billNumber: billNumber ?? this.billNumber,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      invoiceType: invoiceType ?? this.invoiceType,
      gstRate: gstRate ?? this.gstRate,
      taxableAmount: taxableAmount ?? this.taxableAmount,
      cgstAmount: cgstAmount ?? this.cgstAmount,
      sgstAmount: sgstAmount ?? this.sgstAmount,
      igstAmount: igstAmount ?? this.igstAmount,
      whatsappStatus: whatsappStatus ?? this.whatsappStatus,
      totalAmount: totalAmount ?? this.totalAmount,
      status: status ?? this.status,
      productId: productId ?? this.productId,
      quantity: quantity ?? this.quantity,
      items: items ?? this.items,
      soldAt: soldAt ?? this.soldAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'location_id': locationId,
      'bill_number': billNumber,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'payment_method': paymentMethod,
      'invoice_type': invoiceType,
      'gst_rate': gstRate,
      'taxable_amount': taxableAmount,
      'cgst_amount': cgstAmount,
      'sgst_amount': sgstAmount,
      'igst_amount': igstAmount,
      'whatsapp_status': whatsappStatus,
      'total_amount': totalAmount,
      'status': status,
      'product_id': productId,
      'quantity': quantity,
      'sold_at': soldAt.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Sale.fromJson(Map<String, dynamic> json) {
    final rawItems = json['sale_items'] != null
        ? (json['sale_items'] as List)
            .map((i) => SaleItem.fromJson(i as Map<String, dynamic>))
            .toList()
        : <SaleItem>[];

    final primaryProductId = (json['product_id'] ?? json['productId'])?.toString() ??
        (rawItems.isNotEmpty ? rawItems.first.productId : '');

    final int primaryQuantity = ((json['quantity'] ?? json['qty']) as num?)?.toInt() ??
        (rawItems.isNotEmpty ? rawItems.fold<int>(0, (sum, i) => sum + i.quantity) : 1);

    final double totAmount = ((json['total_amount'] ?? json['totalAmount'] ?? 0) as num).toDouble();
    final double taxAmount = ((json['taxable_amount'] ?? json['taxableAmount'] ?? totAmount) as num).toDouble();

    return Sale(
      id: json['id'] as String,
      locationId: (json['location_id'] ?? json['locationId'] ?? '') as String,
      billNumber: (json['bill_number'] ?? json['billNumber'] ?? 'BILL-000') as String,
      customerName: (json['customer_name'] ?? json['customerName']) as String?,
      customerPhone: (json['customer_phone'] ?? json['customerPhone']) as String?,
      paymentMethod: (json['payment_method'] ?? json['paymentMethod'] ?? 'CASH') as String,
      invoiceType: (json['invoice_type'] ?? json['invoiceType'] ?? 'NON_GST') as String,
      gstRate: ((json['gst_rate'] ?? json['gstRate'] ?? 0.0) as num).toDouble(),
      taxableAmount: taxAmount,
      cgstAmount: ((json['cgst_amount'] ?? json['cgstAmount'] ?? 0.0) as num).toDouble(),
      sgstAmount: ((json['sgst_amount'] ?? json['sgstAmount'] ?? 0.0) as num).toDouble(),
      igstAmount: ((json['igst_amount'] ?? json['igstAmount'] ?? 0.0) as num).toDouble(),
      whatsappStatus: (json['whatsapp_status'] ?? json['whatsappStatus'] ?? 'NOT_SENT') as String,
      totalAmount: totAmount,
      status: (json['status'] ?? 'COMPLETED') as String,
      productId: primaryProductId,
      quantity: primaryQuantity,
      items: rawItems,
      soldAt: json['sold_at'] != null
          ? DateTime.parse(json['sold_at'] as String)
          : DateTime.now(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}

