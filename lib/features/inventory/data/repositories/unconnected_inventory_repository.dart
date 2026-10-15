import 'dart:convert';
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
import '../../../sales/domain/entities/cart_item.dart';

/// In-memory implementation of [IInventoryRepository] for testing and offline fallback.
class UnconnectedInventoryRepository implements IInventoryRepository {
  final List<StockInRecord> _stockInRecords = [];
  final Map<String, int> _storeStock = {
    // Independent Jaipur Store Inventory
    '${Location.jaipurId}:prod-101': 50,
    '${Location.jaipurId}:prod-102': 50,
    '${Location.jaipurId}:prod-103': 0, // Chyawanprash has 0 initial stock at Jaipur
    '${Location.jaipurId}:prod-104': 50,
    '${Location.jaipurId}:prod-105': 25,
    '${Location.jaipurId}:prod-106': 25,
    '${Location.jaipurId}:prod-107': 25,
  };
  final List<StockAdjustment> _stockAdjustments = [];
  final Map<String, Sale> _salesByRequestId = {};
  final Map<String, String> _payloadHashByRequestId = {};
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
    Product(
      id: 'prod-104',
      name: 'Tulsi Ark',
      packageSize: '50ml',
      sku: 'KV-TUL-050',
      active: true,
      standardSellingPrice: 100.0,
      purchaseCost: 45.0,
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
    ),
    Product(
      id: 'prod-105',
      name: 'Almonds / Badam',
      packageSize: '250g',
      sku: 'KV-ALM-250',
      active: true,
      standardSellingPrice: 300.0,
      purchaseCost: 180.0,
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
    Product(
      id: 'prod-106',
      name: 'Kaju / Cashews',
      packageSize: '250g',
      sku: 'KV-KAJ-250',
      active: true,
      standardSellingPrice: 350.0,
      purchaseCost: 210.0,
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
    Product(
      id: 'prod-107',
      name: 'Raisins / Kishmish',
      packageSize: '250g',
      sku: 'KV-RAI-250',
      active: true,
      standardSellingPrice: 180.0,
      purchaseCost: 95.0,
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
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
    PackingRecord(
      id: 'pack-3',
      locationId: Location.neemranaId,
      productId: 'prod-104',
      rawMaterialId: 'raw-101',
      rawMaterialConsumed: 20.0,
      packedQuantity: 200,
      wastageQuantity: 0.2,
      packedAt: DateTime.now().subtract(const Duration(days: 2)),
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
    PackingRecord(
      id: 'pack-4',
      locationId: Location.neemranaId,
      productId: 'prod-105',
      packedQuantity: 100,
      packedAt: DateTime.now().subtract(const Duration(days: 2)),
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
    PackingRecord(
      id: 'pack-5',
      locationId: Location.neemranaId,
      productId: 'prod-106',
      packedQuantity: 100,
      packedAt: DateTime.now().subtract(const Duration(days: 2)),
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
    PackingRecord(
      id: 'pack-6',
      locationId: Location.neemranaId,
      productId: 'prod-107',
      packedQuantity: 100,
      packedAt: DateTime.now().subtract(const Duration(days: 2)),
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
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
    StockTransfer(
      id: 'trans-3',
      productId: 'prod-104',
      fromLocationId: Location.neemranaId,
      toLocationId: Location.jaipurId,
      dispatchedQuantity: 100,
      receivedQuantity: 100,
      dispatchedAt: DateTime.now().subtract(const Duration(days: 2)),
      receivedAt: DateTime.now().subtract(const Duration(days: 1)),
      discrepancyReason: null,
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
    StockTransfer(
      id: 'trans-4',
      productId: 'prod-105',
      fromLocationId: Location.neemranaId,
      toLocationId: Location.jaipurId,
      dispatchedQuantity: 50,
      receivedQuantity: 50,
      dispatchedAt: DateTime.now().subtract(const Duration(days: 2)),
      receivedAt: DateTime.now().subtract(const Duration(days: 1)),
      discrepancyReason: null,
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
    StockTransfer(
      id: 'trans-5',
      productId: 'prod-106',
      fromLocationId: Location.neemranaId,
      toLocationId: Location.jaipurId,
      dispatchedQuantity: 50,
      receivedQuantity: 50,
      dispatchedAt: DateTime.now().subtract(const Duration(days: 2)),
      receivedAt: DateTime.now().subtract(const Duration(days: 1)),
      discrepancyReason: null,
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
    StockTransfer(
      id: 'trans-6',
      productId: 'prod-107',
      fromLocationId: Location.neemranaId,
      toLocationId: Location.jaipurId,
      dispatchedQuantity: 50,
      receivedQuantity: 50,
      dispatchedAt: DateTime.now().subtract(const Duration(days: 2)),
      receivedAt: DateTime.now().subtract(const Duration(days: 1)),
      discrepancyReason: null,
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
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
    return List.unmodifiable(_products);
  }

  @override
  Future<Product> addProduct({
    required String name,
    required String packageSize,
    required String sku,
    double? standardSellingPrice,
    double? purchaseCost,
    bool active = true,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw Exception('Product name cannot be empty.');
    final cleanSize = packageSize.trim();
    if (cleanSize.isEmpty) throw Exception('Package size cannot be empty.');
    final trimmedSku = sku.trim().toUpperCase();
    if (trimmedSku.isEmpty) throw Exception('Product SKU cannot be empty.');

    if (standardSellingPrice != null && standardSellingPrice < 0) {
      throw Exception('Standard selling price cannot be negative.');
    }
    if (purchaseCost != null && purchaseCost < 0) {
      throw Exception('Purchase cost cannot be negative.');
    }

    if (_products.any((p) => p.sku.toUpperCase() == trimmedSku)) {
      throw Exception('Product with SKU "$trimmedSku" already exists.');
    }

    final product = Product(
      id: _generateId('prod'),
      name: cleanName,
      packageSize: cleanSize,
      sku: trimmedSku,
      standardSellingPrice: standardSellingPrice ?? Product.defaultPriceForSku(trimmedSku),
      purchaseCost: purchaseCost ?? Product.defaultCostForSku(trimmedSku),
      active: active,
      createdAt: DateTime.now(),
    );
    _products.add(product);
    return product;
  }

  @override
  Future<Product> updateProduct({
    required String id,
    String? name,
    String? packageSize,
    String? sku,
    double? standardSellingPrice,
    double? purchaseCost,
    bool? active,
  }) async {
    final index = _products.indexWhere((p) => p.id == id);
    if (index == -1) {
      throw Exception('Product with ID "$id" not found.');
    }
    final existing = _products[index];

    if (name != null && name.trim().isEmpty) {
      throw Exception('Product name cannot be empty.');
    }
    if (packageSize != null && packageSize.trim().isEmpty) {
      throw Exception('Package size cannot be empty.');
    }
    String? cleanSku;
    if (sku != null) {
      cleanSku = sku.trim().toUpperCase();
      if (cleanSku.isEmpty) throw Exception('Product SKU cannot be empty.');
      if (_products.any((p) => p.id != id && p.sku.toUpperCase() == cleanSku)) {
        throw Exception('Product with SKU "$cleanSku" already exists.');
      }
    }
    if (standardSellingPrice != null && standardSellingPrice < 0) {
      throw Exception('Standard selling price cannot be negative.');
    }
    if (purchaseCost != null && purchaseCost < 0) {
      throw Exception('Purchase cost cannot be negative.');
    }

    final updated = existing.copyWith(
      name: name?.trim(),
      packageSize: packageSize?.trim(),
      sku: cleanSku,
      standardSellingPrice: standardSellingPrice,
      purchaseCost: purchaseCost,
      active: active,
    );
    _products[index] = updated;
    return updated;
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
  Future<StockAdjustment> receiveStoreStock({
    required String locationId,
    required String productId,
    required int quantity,
    String? notes,
  }) async {
    if (quantity <= 0) {
      throw Exception('Received stock quantity must be greater than zero.');
    }
    final stockKey = '$locationId:$productId';
    final int prevQty;
    if (_storeStock.containsKey(stockKey)) {
      prevQty = _storeStock[stockKey]!;
    } else {
      final summaries = await getInventorySummaries();
      final match = summaries.where((s) => s.product.id == productId);
      if (match.isNotEmpty) {
        prevQty = locationId == Location.neemranaId
            ? match.first.neemranaFinishedStock
            : match.first.jaipurFinishedStock;
      } else {
        prevQty = 0;
      }
    }
    final newQty = prevQty + quantity;
    _storeStock[stockKey] = newQty;

    final adj = StockAdjustment(
      id: _generateId('adj'),
      locationId: locationId,
      productId: productId,
      previousQuantity: prevQty,
      newQuantity: newQty,
      changeQuantity: quantity,
      reason: 'STOCK_RECEIPT',
      notes: notes ?? 'Stock received into store',
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
    throw UnsupportedError(
      'Inter-store stock transfers are permanently disabled: '
      'Neemrana and Jaipur operate as independent retail stores.',
    );
  }

  @override
  Future<StockTransfer> confirmTransferReceipt({
    required String transferId,
    required int receivedQuantity,
    String? discrepancyReason,
    DateTime? receivedAt,
  }) async {
    throw UnsupportedError(
      'Inter-store stock transfers are permanently disabled: '
      'Neemrana and Jaipur operate as independent retail stores.',
    );
  }

  @override
  Future<List<Sale>> getSales({
    int limit = 50,
    int offset = 0,
    String? locationId,
  }) async {
    final sorted = List<Sale>.from(_sales)
      ..sort((a, b) => b.soldAt.compareTo(a.soldAt));

    final filtered = (locationId != null && locationId.isNotEmpty)
        ? sorted.where((s) => s.locationId == locationId).toList()
        : sorted;

    if (offset >= filtered.length) {
      return [];
    }
    final end =
        (offset + limit < filtered.length) ? offset + limit : filtered.length;
    return filtered.sublist(offset, end);
  }

  /// Test helper to simulate a legacy sale row with client_request_id but NULL payload hash.
  void seedLegacySaleWithNullHash({
    required String requestId,
    required Sale sale,
  }) {
    _salesByRequestId[requestId] = sale;
    _payloadHashByRequestId.remove(requestId);
  }

  @override
  Future<Sale> recordSale({
    String? productId,
    int? quantity,
    List<CartItem>? items,
    String? clientRequestId,
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
    String? callerRole,
  }) async {
    final cleanMethod = paymentMethod.trim().toUpperCase();
    if (cleanMethod != 'CASH' && cleanMethod != 'UPI') {
      throw Exception(
          'Invalid payment method "$paymentMethod". Allowed values: CASH, UPI.');
    }
    final targetLocationId = locationId ?? Location.jaipurId;

    if (quantity != null && quantity <= 0) {
      throw Exception('Quantity must be greater than zero.');
    }

    // Build line items list
    final List<Map<String, dynamic>> itemsPayload;
    if (items != null && items.isNotEmpty) {
      for (final item in items) {
        if (item.quantity <= 0) {
          throw Exception('Quantity must be greater than zero.');
        }
      }
      itemsPayload = items.map((i) => i.toRpcItemJson()).toList();
    } else if (productId != null && quantity != null && quantity > 0) {
      final effectiveUnitPrice = unitPrice ??
          (totalAmount > 0 ? (totalAmount / quantity) : 100.0);
      itemsPayload = [
        {
          'product_id': productId,
          'quantity': quantity,
          'unit_price': effectiveUnitPrice,
          'discount': discount,
        }
      ];
    } else {
      throw Exception('Either items or valid productId and quantity must be provided.');
    }

    // Server-side Idempotency Verification
    if (clientRequestId != null && clientRequestId.isNotEmpty) {
      // Build normalized line items list sorted deterministically
      final sortedItems = List<Map<String, dynamic>>.from(itemsPayload)
        ..sort((a, b) {
          final cmpPid = (a['product_id'] as String).compareTo(b['product_id'] as String);
          if (cmpPid != 0) return cmpPid;
          final cmpQty = ((a['quantity'] as num).toInt()).compareTo((b['quantity'] as num).toInt());
          if (cmpQty != 0) return cmpQty;
          final cmpPrice = ((a['unit_price'] as num).toDouble()).compareTo((b['unit_price'] as num).toDouble());
          if (cmpPrice != 0) return cmpPrice;
          return (((a['discount'] ?? 0) as num).toDouble()).compareTo(((b['discount'] ?? 0) as num).toDouble());
        });

      final canonicalPayload = jsonEncode({
        'canonical_version': 1,
        'customer_name': customerName?.trim(),
        'customer_phone': customerPhone?.trim(),
        'invoice_type': invoiceType.trim().toUpperCase(),
        'items': sortedItems.map((i) => {
          'discount': double.parse(((i['discount'] ?? 0) as num).toDouble().toStringAsFixed(2)),
          'product_id': i['product_id'],
          'quantity': (i['quantity'] as num).toInt(),
          'unit_price': double.parse(((i['unit_price'] ?? 0) as num).toDouble().toStringAsFixed(2)),
        }).toList(),
        'location_id': targetLocationId,
        'payment_method': cleanMethod,
      });

      if (_salesByRequestId.containsKey(clientRequestId)) {
        final existingHash = _payloadHashByRequestId[clientRequestId];
        if (existingHash == null) {
          throw Exception(
              'Idempotency conflict: Client request ID $clientRequestId exists on a legacy record without a verified payload hash. Request cannot be safely replayed.');
        } else if (existingHash != canonicalPayload) {
          throw Exception(
              'Idempotency conflict: client_request_id $clientRequestId was already used with a different request payload.');
        }
        // Return existing committed sale without decrementing stock a second time
        return _salesByRequestId[clientRequestId]!;
      }
      _payloadHashByRequestId[clientRequestId] = canonicalPayload;
    }

    final saleId = _generateId('sale');
    final List<SaleItem> saleItems = [];
    double calculatedTotal = 0.0;

    // 1. Validate inputs and calculate totals
    for (final itemMap in itemsPayload) {
      final pId = itemMap['product_id'] as String;
      final q = (itemMap['quantity'] as num).toInt();
      final up = (itemMap['unit_price'] as num).toDouble();
      final d = (itemMap['discount'] as num?)?.toDouble() ?? 0.0;

      if (!q.isFinite || q.isNaN || q <= 0) {
        throw Exception('Quantity must be greater than zero.');
      }
      if (!up.isFinite || up.isNaN || up <= 0) {
        throw Exception('Unit price must be greater than zero.');
      }
      if (!d.isFinite || d.isNaN || d < 0) {
        throw Exception('Discount cannot be negative.');
      }
      if (d > (q * up)) {
        throw Exception('Discount cannot exceed line item total.');
      }

      final product = _products.firstWhere(
        (p) => p.id == pId,
        orElse: () => Product(
          id: pId,
          name: 'Product',
          packageSize: 'Standard',
          sku: 'KV-ITEM',
          createdAt: DateTime.now(),
        ),
      );

      // Cashier role boundary enforcement: 10% maximum discount ceiling and no price modification
      if (callerRole == 'neemrana' || callerRole == 'jaipur') {
        if ((up - product.standardSellingPrice).abs() > 0.001) {
          throw Exception(
              'Unauthorized price modification: Cashier role "$callerRole" cannot modify catalog price (Catalog: ${product.standardSellingPrice}, Provided: $up). Owner authorization required.');
        }

        final itemGross = q * product.standardSellingPrice;
        if (d > 0 && itemGross > 0) {
          final pct = double.parse(((d / itemGross) * 100.0).toStringAsFixed(4));
          if (pct > 10.00) {
            throw Exception(
                'Unauthorized discount: Cashier discount ($pct pct) exceeds allowed maximum of 10.0 pct. Owner authorization required.');
          }
        }
      }

      final lineTotal = (q * up) - d;
      calculatedTotal += lineTotal;

      saleItems.add(SaleItem(
        id: _generateId('sale_item'),
        saleId: saleId,
        productId: pId,
        quantity: q,
        unitPrice: up,
        discount: d,
        unitCost: product.purchaseCost > 0 ? product.purchaseCost : null,
        createdAt: soldAt ?? DateTime.now(),
        productName: product.name,
        sku: product.sku,
        packageSize: product.packageSize,
      ));
    }

    // 2. Pre-validate stock availability for all products (atomic check supporting duplicate lines)
    final Map<String, int> totalRequiredByProduct = {};
    for (final itemMap in itemsPayload) {
      final pId = itemMap['product_id'] as String;
      final q = (itemMap['quantity'] as num).toInt();
      totalRequiredByProduct[pId] = (totalRequiredByProduct[pId] ?? 0) + q;
    }

    final summaries = await getInventorySummaries();
    for (final entry in totalRequiredByProduct.entries) {
      final pId = entry.key;
      final totalReq = entry.value;
      final stockKey = '$targetLocationId:$pId';
      final int current;
      if (_storeStock.containsKey(stockKey)) {
        current = _storeStock[stockKey]!;
      } else {
        final match = summaries.where((s) => s.product.id == pId);
        current = match.isNotEmpty
            ? (targetLocationId == Location.neemranaId
                ? match.first.neemranaFinishedStock
                : match.first.jaipurFinishedStock)
            : 0;
        _storeStock[stockKey] = current;
      }
      if (totalReq > current) {
        throw Exception(
            'Insufficient stock for product ID $pId at $targetLocationId. Available: $current, Requested: $totalReq.');
      }
    }

    // 3. Atomically deduct stock only after all items and constraints are verified
    for (final entry in totalRequiredByProduct.entries) {
      final pId = entry.key;
      final totalReq = entry.value;
      final stockKey = '$targetLocationId:$pId';
      _storeStock[stockKey] = (_storeStock[stockKey] ?? 0) - totalReq;
    }

    final effectiveTotal = totalAmount > 0 ? totalAmount : calculatedTotal;
    final calcTaxable = taxableAmount ??
        (invoiceType == 'GST'
            ? (effectiveTotal / (1 + (gstRate / 100.0)))
            : effectiveTotal);

    final firstItem = saleItems.first;
    final sale = Sale(
      id: saleId,
      locationId: targetLocationId,
      billNumber:
          'BILL-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}',
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
      totalAmount: effectiveTotal,
      productId: firstItem.productId,
      quantity: saleItems.fold<int>(0, (sum, i) => sum + i.quantity),
      items: saleItems,
      soldAt: soldAt ?? DateTime.now(),
      createdAt: DateTime.now(),
    );

    _sales.add(sale);
    if (clientRequestId != null && clientRequestId.isNotEmpty) {
      _salesByRequestId[clientRequestId] = sale;
    }
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

    if (existing.items.isNotEmpty) {
      for (final item in existing.items) {
        final stockKey = '${existing.locationId}:${item.productId}';
        if (_storeStock.containsKey(stockKey)) {
          _storeStock[stockKey] = _storeStock[stockKey]! + item.quantity;
        }
      }
    } else {
      final stockKey = '${existing.locationId}:${existing.productId}';
      if (_storeStock.containsKey(stockKey)) {
        _storeStock[stockKey] = _storeStock[stockKey]! + existing.quantity;
      }
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

      // Inter-store transfers are permanently disabled: stock is never transferred
      const totalDispatched = 0;
      const totalReceived = 0;

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


