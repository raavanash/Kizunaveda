import '../../domain/entities/location.dart';
import '../../domain/entities/packing_record.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/product_inventory_summary.dart';
import '../../domain/entities/raw_material.dart';
import '../../domain/entities/raw_material_receipt.dart';
import '../../domain/entities/sale.dart';
import '../../domain/entities/stock_transfer.dart';
import '../../domain/repositories/inventory_repository.dart';

import '../../domain/entities/stock_in_record.dart';
import '../../domain/entities/store_inventory.dart';
import '../../domain/entities/stock_adjustment.dart';

/// In-memory implementation of [IInventoryRepository] for testing and offline fallback.
class UnconnectedInventoryRepository implements IInventoryRepository {
  final List<StockInRecord> _stockInRecords = [];
  final Map<String, int> _storeStock = {}; // key: '$locationId:$productId'
  final List<StockAdjustment> _stockAdjustments = [];
  final List<Location> _locations = [
    Location(
      id: Location.neemranaId,
      code: 'NEEMRANA',
      name: 'Neemrana Retail Outlet',
      locationType: 'RETAIL',
      active: true,
      createdAt: DateTime.now().subtract(const Duration(days: 30)),
    ),
    Location(
      id: Location.jaipurId,
      code: 'JAIPUR',
      name: 'Jaipur Retail Outlet',
      locationType: 'RETAIL',
      active: true,
      createdAt: DateTime.now().subtract(const Duration(days: 30)),
    ),
  ];

  final List<Product> _products = [
    Product(
      id: 'prod-101',
      name: 'Triphala Churna Premium',
      packageSize: '250g',
      sku: 'KV-TRI-250',
      active: true,
      standardSellingPrice: 120.0,
      purchaseCost: 55.0,
      createdAt: DateTime.now().subtract(const Duration(days: 10)),
    ),
    Product(
      id: 'prod-102',
      name: 'Ashwagandha Root Powder',
      packageSize: '100g',
      sku: 'KV-ASH-100',
      active: true,
      standardSellingPrice: 150.0,
      purchaseCost: 70.0,
      createdAt: DateTime.now().subtract(const Duration(days: 8)),
    ),
    Product(
      id: 'prod-103',
      name: 'Chyawanprash Special',
      packageSize: '500g',
      sku: 'KV-CHY-500',
      active: true,
      standardSellingPrice: 200.0,
      purchaseCost: 90.0,
      createdAt: DateTime.now().subtract(const Duration(days: 5)),
    ),
  ];

  final List<RawMaterial> _rawMaterials = [
    RawMaterial(
      id: 'raw-101',
      name: 'Dried Tulsi Leaves',
      unitOfMeasure: 'KG',
      active: true,
      createdAt: DateTime.now().subtract(const Duration(days: 20)),
    ),
    RawMaterial(
      id: 'raw-102',
      name: 'Ashwagandha Root Bulk',
      unitOfMeasure: 'KG',
      active: true,
      createdAt: DateTime.now().subtract(const Duration(days: 15)),
    ),
  ];

  final List<RawMaterialReceipt> _rawMaterialReceipts = [
    RawMaterialReceipt(
      id: 'rec-1',
      rawMaterialId: 'raw-101',
      locationId: Location.neemranaId,
      quantity: 500.0,
      cost: 25000.0,
      supplierReference: 'SUP-9901',
      receivedAt: DateTime.now().subtract(const Duration(days: 10)),
      createdAt: DateTime.now().subtract(const Duration(days: 10)),
    ),
  ];

  final List<PackingRecord> _packingRecords = [
    PackingRecord(
      id: 'pack-1',
      locationId: Location.neemranaId,
      productId: 'prod-101',
      rawMaterialId: 'raw-101',
      rawMaterialConsumed: 125.0,
      packedQuantity: 500,
      wastageQuantity: 2.0,
      packedAt: DateTime.now().subtract(const Duration(days: 4)),
      createdAt: DateTime.now().subtract(const Duration(days: 4)),
    ),
    PackingRecord(
      id: 'pack-2',
      locationId: Location.neemranaId,
      productId: 'prod-102',
      rawMaterialId: 'raw-102',
      rawMaterialConsumed: 30.0,
      packedQuantity: 300,
      wastageQuantity: 0.5,
      packedAt: DateTime.now().subtract(const Duration(days: 3)),
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
    ),
  ];

  final List<StockTransfer> _transfers = [
    StockTransfer(
      id: 'trans-1',
      productId: 'prod-101',
      fromLocationId: Location.neemranaId,
      toLocationId: Location.jaipurId,
      dispatchedQuantity: 200,
      receivedQuantity: 200,
      dispatchedAt: DateTime.now().subtract(const Duration(days: 3)),
      receivedAt: DateTime.now().subtract(const Duration(days: 2)),
      discrepancyReason: null,
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
    ),
    StockTransfer(
      id: 'trans-2',
      productId: 'prod-102',
      fromLocationId: Location.neemranaId,
      toLocationId: Location.jaipurId,
      dispatchedQuantity: 100,
      receivedQuantity: null,
      dispatchedAt: DateTime.now().subtract(const Duration(days: 1)),
      receivedAt: null,
      discrepancyReason: null,
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
  ];

  final List<Sale> _sales = [
    Sale(
      id: 'sale-1',
      locationId: Location.jaipurId,
      billNumber: 'BILL-1001',
      customerPhone: '9876543210',
      totalAmount: 1250.0,
      productId: 'prod-101',
      quantity: 50,
      soldAt: DateTime.now().subtract(const Duration(hours: 12)),
      createdAt: DateTime.now().subtract(const Duration(hours: 12)),
    ),
  ];

  int _idCounter = 1000;

  String _generateId(String prefix) {
    _idCounter++;
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$_idCounter';
  }

  @override
  Future<List<Location>> getLocations() async {
    return List.unmodifiable(_locations);
  }

  @override
  Future<List<Product>> getProducts() async {
    return List.unmodifiable(_products.where((p) => p.active));
  }

  @override
  Future<Product> addProduct({
    required String name,
    required String packageSize,
    required String sku,
  }) async {
    final trimmedSku = sku.trim().toUpperCase();
    if (_products.any((p) => p.sku.toUpperCase() == trimmedSku)) {
      throw Exception('Product with SKU "$trimmedSku" already exists.');
    }

    final product = Product(
      id: _generateId('prod'),
      name: name.trim(),
      packageSize: packageSize.trim(),
      sku: trimmedSku,
      active: true,
      createdAt: DateTime.now(),
    );
    _products.add(product);
    return product;
  }

  @override
  Future<Product> updateProductPricing({
    required String productId,
    required double standardSellingPrice,
    required double purchaseCost,
  }) async {
    if (standardSellingPrice < 0) {
      throw Exception('Standard selling price cannot be negative.');
    }
    if (purchaseCost < 0) {
      throw Exception('Purchase cost cannot be negative.');
    }
    final index = _products.indexWhere((p) => p.id == productId);
    if (index == -1) {
      throw Exception('Product with ID "$productId" not found.');
    }
    final updated = _products[index].copyWith(
      standardSellingPrice: standardSellingPrice,
      purchaseCost: purchaseCost,
    );
    _products[index] = updated;
    return updated;
  }

  @override
  Future<List<RawMaterial>> getRawMaterials() async {
    return List.unmodifiable(_rawMaterials.where((r) => r.active));
  }

  @override
  Future<RawMaterial> addRawMaterial({
    required String name,
    required String unitOfMeasure,
  }) async {
    final trimmedName = name.trim();
    final rawMat = RawMaterial(
      id: _generateId('raw'),
      name: trimmedName,
      unitOfMeasure: unitOfMeasure.trim().toUpperCase(),
      active: true,
      createdAt: DateTime.now(),
    );
    _rawMaterials.add(rawMat);
    return rawMat;
  }

  @override
  Future<List<RawMaterialReceipt>> getRawMaterialReceipts() async {
    return List.unmodifiable(_rawMaterialReceipts);
  }

  @override
  Future<RawMaterialReceipt> addRawMaterialReceipt({
    required String rawMaterialId,
    required double quantity,
    required double cost,
    String? supplierReference,
    String? locationId,
    DateTime? receivedAt,
  }) async {
    final receipt = RawMaterialReceipt(
      id: _generateId('rec'),
      rawMaterialId: rawMaterialId,
      locationId: locationId ?? Location.neemranaId,
      quantity: quantity,
      cost: cost,
      supplierReference: supplierReference?.trim(),
      receivedAt: receivedAt ?? DateTime.now(),
      createdAt: DateTime.now(),
    );
    _rawMaterialReceipts.add(receipt);
    return receipt;
  }

  @override
  Future<List<PackingRecord>> getPackingRecords() async {
    return List.unmodifiable(_packingRecords);
  }

  @override
  Future<PackingRecord> addPackingRecord({
    required String productId,
    required int packedQuantity,
    String? rawMaterialId,
    double rawMaterialConsumed = 0.0,
    double wastageQuantity = 0.0,
    String? locationId,
    DateTime? packedAt,
  }) async {
    final record = PackingRecord(
      id: _generateId('pack'),
      locationId: locationId ?? Location.neemranaId,
      productId: productId,
      rawMaterialId: rawMaterialId,
      rawMaterialConsumed: rawMaterialConsumed,
      packedQuantity: packedQuantity,
      wastageQuantity: wastageQuantity,
      packedAt: packedAt ?? DateTime.now(),
      createdAt: DateTime.now(),
    );
    _packingRecords.add(record);
    return record;
  }

  @override
  Future<List<StockInRecord>> getStockInRecords() async {
    return List.unmodifiable(_stockInRecords);
  }

  @override
  Future<StockInRecord> addStockIn({
    required String productId,
    required int quantity,
    required String locationId,
    String? notes,
  }) async {
    final record = StockInRecord(
      id: _generateId('stockin'),
      locationId: locationId,
      productId: productId,
      quantity: quantity,
      notes: notes,
      createdAt: DateTime.now(),
    );
    _stockInRecords.add(record);
    return record;
  }

  @override
  Future<List<StoreInventory>> getStoreInventories() async {
    final list = <StoreInventory>[];
    _storeStock.forEach((key, qty) {
      final parts = key.split(':');
      if (parts.length == 2) {
        list.add(StoreInventory(
          id: 'inv-$key',
          locationId: parts[0],
          productId: parts[1],
          currentQuantity: qty,
          updatedAt: DateTime.now(),
        ));
      }
    });
    return list;
  }

  @override
  Future<StockAdjustment> adjustStoreStock({
    required String locationId,
    required String productId,
    required int newQuantity,
    String reason = 'STOCK_ENTRY',
    String? notes,
  }) async {
    if (newQuantity < 0) {
      throw Exception('Stock quantity cannot be negative.');
    }
    final key = '$locationId:$productId';
    final prev = _storeStock[key] ?? 0;
    _storeStock[key] = newQuantity;
    final change = newQuantity - prev;
    final adj = StockAdjustment(
      id: 'adj-${DateTime.now().millisecondsSinceEpoch}',
      locationId: locationId,
      productId: productId,
      previousQuantity: prev,
      newQuantity: newQuantity,
      changeQuantity: change,
      reason: reason,
      notes: notes,
      createdAt: DateTime.now(),
    );
    _stockAdjustments.insert(0, adj);
    return adj;
  }

  @override
  Future<List<StockAdjustment>> getStockAdjustments({String? locationId}) async {
    if (locationId == null) {
      return List.unmodifiable(_stockAdjustments);
    }
    return _stockAdjustments.where((a) => a.locationId == locationId).toList();
  }

  @override
  Future<List<StockTransfer>> getTransfers() async {

    return List.unmodifiable(_transfers);
  }

  @override
  Future<StockTransfer> createTransfer({
    required String productId,
    required int dispatchedQuantity,
    String? fromLocationId,
    String? toLocationId,
    DateTime? dispatchedAt,
  }) async {
    final transfer = StockTransfer(
      id: _generateId('trans'),
      productId: productId,
      fromLocationId: fromLocationId ?? Location.neemranaId,
      toLocationId: toLocationId ?? Location.jaipurId,
      dispatchedQuantity: dispatchedQuantity,
      receivedQuantity: null,
      dispatchedAt: dispatchedAt ?? DateTime.now(),
      receivedAt: null,
      discrepancyReason: null,
      createdAt: DateTime.now(),
    );
    _transfers.add(transfer);
    return transfer;
  }

  @override
  Future<StockTransfer> confirmTransferReceipt({
    required String transferId,
    required int receivedQuantity,
    String? discrepancyReason,
    DateTime? receivedAt,
  }) async {
    final index = _transfers.indexWhere((t) => t.id == transferId);
    if (index == -1) {
      throw Exception('Transfer with ID "$transferId" not found.');
    }
    final existing = _transfers[index];
    if (receivedQuantity > existing.dispatchedQuantity) {
      throw Exception('Received quantity ($receivedQuantity) cannot exceed dispatched quantity (${existing.dispatchedQuantity}).');
    }
    if (receivedQuantity != existing.dispatchedQuantity &&
        (discrepancyReason == null || discrepancyReason.trim().isEmpty)) {
      throw Exception('Discrepancy reason is required when received quantity differs from dispatched quantity.');
    }

    final updated = existing.copyWith(
      receivedQuantity: receivedQuantity,
      receivedAt: receivedAt ?? DateTime.now(),
      discrepancyReason: discrepancyReason?.trim(),
    );
    _transfers[index] = updated;
    return updated;
  }

  @override
  Future<List<Sale>> getSales() async {
    return List.unmodifiable(_sales);
  }

  @override
  Future<Sale> recordSale({
    required String productId,
    required int quantity,
    String? customerName,
    String? customerPhone,
    String paymentMethod = 'CASH',
    String? locationId,
    String invoiceType = 'NON_GST',
    double gstRate = 0.0,
    double? taxableAmount,
    double cgstAmount = 0.0,
    double sgstAmount = 0.0,
    double igstAmount = 0.0,
    double totalAmount = 0.0,
    double? unitPrice,
    double discount = 0.0,
    DateTime? soldAt,
  }) async {
    if (quantity <= 0) {
      throw Exception('Quantity must be greater than zero.');
    }
    final cleanMethod = paymentMethod.trim().toUpperCase();
    if (cleanMethod != 'CASH' && cleanMethod != 'UPI') {
      throw Exception('Invalid payment method "$paymentMethod". Allowed values: CASH, UPI.');
    }
    final targetLocationId = locationId ?? Location.jaipurId;
    final calcTaxable = taxableAmount ?? (invoiceType == 'GST' ? (totalAmount / (1 + (gstRate / 100.0))) : totalAmount);

    final product = _products.firstWhere(
      (p) => p.id == productId,
      orElse: () => Product(
        id: productId,
        name: 'Product',
        packageSize: 'Standard',
        sku: 'KV-ITEM',
        createdAt: DateTime.now(),
      ),
    );

    final effectiveUnitPrice = unitPrice ??
        (totalAmount > 0 && quantity > 0
            ? (totalAmount / quantity)
            : product.standardSellingPrice);

    final calculatedTotal = totalAmount > 0
        ? totalAmount
        : ((quantity * effectiveUnitPrice) - discount);

    final saleId = _generateId('sale');
    final saleItem = SaleItem(
      id: _generateId('sale_item'),
      saleId: saleId,
      productId: productId,
      quantity: quantity,
      unitPrice: effectiveUnitPrice,
      discount: discount,
      unitCost: product.purchaseCost > 0 ? product.purchaseCost : null,
      createdAt: soldAt ?? DateTime.now(),
    );

    final sale = Sale(
      id: saleId,
      locationId: targetLocationId,
      billNumber: 'BILL-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}',
      customerName: customerName?.trim(),
      customerPhone: customerPhone?.trim(),
      paymentMethod: cleanMethod,
      invoiceType: invoiceType,
      gstRate: gstRate,
      taxableAmount: calcTaxable,
      cgstAmount: cgstAmount,
      sgstAmount: sgstAmount,
      igstAmount: igstAmount,
      whatsappStatus: 'NOT_SENT',
      totalAmount: calculatedTotal,
      productId: productId,
      quantity: quantity,
      items: [saleItem],
      soldAt: soldAt ?? DateTime.now(),
      createdAt: DateTime.now(),
    );

    final stockKey = '$targetLocationId:$productId';
    if (_storeStock.containsKey(stockKey)) {
      final current = _storeStock[stockKey]!;
      if (quantity > current) {
        throw Exception('Insufficient stock. Requested: $quantity, Available: $current.');
      }
      _storeStock[stockKey] = current - quantity;
    }

    _sales.add(sale);
    return sale;
  }

  @override
  Future<Sale> voidSale({required String saleId}) async {
    final index = _sales.indexWhere((s) => s.id == saleId);
    if (index == -1) {
      throw Exception('Sale with ID "$saleId" not found.');
    }
    final existing = _sales[index];
    if (existing.isVoided) {
      throw Exception('Sale is already voided.');
    }

    final stockKey = '${existing.locationId}:${existing.productId}';
    if (_storeStock.containsKey(stockKey)) {
      _storeStock[stockKey] = _storeStock[stockKey]! + existing.quantity;
    }

    final updated = existing.copyWith(status: 'VOIDED');
    _sales[index] = updated;
    return updated;
  }

  @override
  Future<List<ProductInventorySummary>> getInventorySummaries() async {
    final products = await getProducts();
    final summaries = <ProductInventorySummary>[];

    for (final product in products) {
      final totalPacked = _packingRecords
          .where((p) => p.productId == product.id)
          .fold(0, (sum, item) => sum + item.packedQuantity);

      final totalNeemranaStockIn = _stockInRecords
          .where((s) => s.productId == product.id && s.locationId == Location.neemranaId)
          .fold(0, (sum, item) => sum + item.quantity);

      final totalDispatched = _transfers
          .where((t) => t.productId == product.id)
          .fold(0, (sum, item) => sum + item.dispatchedQuantity);

      final totalReceived = _transfers
          .where((t) => t.productId == product.id && t.receivedQuantity != null)
          .fold(0, (sum, item) => sum + (item.receivedQuantity ?? 0));

      final totalJaipurStockIn = _stockInRecords
          .where((s) => s.productId == product.id && s.locationId == Location.jaipurId)
          .fold(0, (sum, item) => sum + item.quantity);

      final completedSales = _sales.where((s) => s.isCompleted);

      final totalNeemranaSold = completedSales
          .where((s) => s.locationId == Location.neemranaId)
          .fold(0, (sum, sale) {
            if (sale.items.isNotEmpty) {
              return sum +
                  sale.items
                      .where((i) => i.productId == product.id)
                      .fold(0, (acc, item) => acc + item.quantity);
            }
            return sale.productId == product.id ? sum + sale.quantity : sum;
          });

      final totalJaipurSold = completedSales
          .where((s) => s.locationId != Location.neemranaId)
          .fold(0, (sum, sale) {
            if (sale.items.isNotEmpty) {
              return sum +
                  sale.items
                      .where((i) => i.productId == product.id)
                      .fold(0, (acc, item) => acc + item.quantity);
            }
            return sale.productId == product.id ? sum + sale.quantity : sum;
          });

      final neemranaKey = '${Location.neemranaId}:${product.id}';
      final jaipurKey = '${Location.jaipurId}:${product.id}';

      summaries.add(
        ProductInventorySummary(
          product: product,
          totalPacked: totalPacked,
          totalNeemranaStockIn: totalNeemranaStockIn,
          totalDispatched: totalDispatched,
          totalReceived: totalReceived,
          totalJaipurStockIn: totalJaipurStockIn,
          totalNeemranaSold: totalNeemranaSold,
          totalJaipurSold: totalJaipurSold,
          neemranaPhysicalStock: _storeStock.containsKey(neemranaKey) ? _storeStock[neemranaKey] : null,
          jaipurPhysicalStock: _storeStock.containsKey(jaipurKey) ? _storeStock[jaipurKey] : null,
        ),
      );
    }

    return summaries;
  }
}


