import 'package:flutter/material.dart';
import '../../domain/entities/location.dart';
import '../../domain/entities/packing_record.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/product_inventory_summary.dart';
import '../../domain/entities/raw_material.dart';
import '../../domain/entities/raw_material_receipt.dart';
import '../../domain/entities/sale.dart';
import '../../domain/entities/stock_transfer.dart';
import '../../domain/entities/store_inventory.dart';
import '../../domain/entities/stock_adjustment.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../../../sales/domain/entities/cart_item.dart';

enum InventoryStatus { initial, loading, success, error }

/// State controller managing V1 Inventory Flow with location-based validation.
class InventoryNotifier extends ChangeNotifier {
  final IInventoryRepository repository;
  final int _salesPageSize;
  int _serverSalesOffset = 0;

  InventoryNotifier({
    required this.repository,
    this._salesPageSize = 50,
  }) {
    loadInventoryData();
  }

  InventoryStatus _status = InventoryStatus.initial;
  String? _errorMessage;

  List<Location> _locations = [];
  List<Product> _products = [];
  List<RawMaterial> _rawMaterials = [];
  List<RawMaterialReceipt> _rawMaterialReceipts = [];
  List<PackingRecord> _packingRecords = [];
  List<StockTransfer> _transfers = [];
  List<Sale> _sales = [];
  bool _hasMoreSales = true;
  bool _isLoadingMoreSales = false;
  String? _salesPaginationError;

  List<ProductInventorySummary> _inventorySummaries = [];
  List<StoreInventory> _storeInventories = [];
  List<StockAdjustment> _stockAdjustments = [];

  InventoryStatus get status => _status;
  bool get isLoading => _status == InventoryStatus.loading;
  String? get errorMessage => _errorMessage;

  List<Location> get locations => _locations;
  List<Product> get products => _products;
  List<RawMaterial> get rawMaterials => _rawMaterials;
  List<RawMaterialReceipt> get rawMaterialReceipts => _rawMaterialReceipts;
  List<PackingRecord> get packingRecords => _packingRecords;
  List<StockTransfer> get transfers => _transfers;
  List<Sale> get sales => _sales;
  bool get hasMoreSales => _hasMoreSales;
  bool get isLoadingMoreSales => _isLoadingMoreSales;
  String? get salesPaginationError => _salesPaginationError;
  int get salesPageSize => _salesPageSize;
  List<ProductInventorySummary> get inventorySummaries => _inventorySummaries;
  List<StoreInventory> get storeInventories => _storeInventories;
  List<StockAdjustment> get stockAdjustments => _stockAdjustments;

  /// Fetch all inventory datasets and recalculate summaries
  Future<void> loadInventoryData() async {
    _status = InventoryStatus.loading;
    _errorMessage = null;
    notifyListeners();

    final errors = <String>[];

    await Future.wait([
      repository.getLocations().then((v) => _locations = v).catchError((e) {
        debugPrint('[INVENTORY] Failed to load locations: $e');
        errors.add('Locations: ${e.toString().replaceAll('Exception: ', '')}');
        return <Location>[];
      }),
      repository.getProducts().then((v) => _products = v).catchError((e) {
        debugPrint('[INVENTORY] Failed to load products: $e');
        errors.add('Products: ${e.toString().replaceAll('Exception: ', '')}');
        return <Product>[];
      }),
      repository.getStoreInventories().then((v) => _storeInventories = v).catchError((e) {
        debugPrint('[INVENTORY] Failed to load store inventories: $e');
        errors.add('Store Inventory: ${e.toString().replaceAll('Exception: ', '')}');
        return <StoreInventory>[];
      }),
      repository.getSales(limit: _salesPageSize, offset: 0).then((v) {
        _sales = List<Sale>.from(v);
        _serverSalesOffset = v.length;
        _hasMoreSales = v.length >= _salesPageSize;
        _salesPaginationError = null;
      }).catchError((e) {
        debugPrint('[INVENTORY] Failed to load sales: $e');
        errors.add('Sales: ${e.toString().replaceAll('Exception: ', '')}');
      }),
      repository.getRawMaterials().then((v) => _rawMaterials = v).catchError((e) {
        debugPrint('[INVENTORY] Failed to load raw materials: $e');
        errors.add('Raw Materials: ${e.toString().replaceAll('Exception: ', '')}');
        return <RawMaterial>[];
      }),
      repository.getRawMaterialReceipts().then((v) => _rawMaterialReceipts = v).catchError((e) {
        debugPrint('[INVENTORY] Failed to load raw material receipts: $e');
        errors.add('Raw Material Receipts: ${e.toString().replaceAll('Exception: ', '')}');
        return <RawMaterialReceipt>[];
      }),
      repository.getPackingRecords().then((v) => _packingRecords = v).catchError((e) {
        debugPrint('[INVENTORY] Failed to load packing records: $e');
        errors.add('Packing Records: ${e.toString().replaceAll('Exception: ', '')}');
        return <PackingRecord>[];
      }),
      repository.getTransfers().then((v) => _transfers = v).catchError((e) {
        debugPrint('[INVENTORY] Failed to load transfers: $e');
        errors.add('Transfers: ${e.toString().replaceAll('Exception: ', '')}');
        return <StockTransfer>[];
      }),
      repository.getStockAdjustments().then((v) => _stockAdjustments = v).catchError((e) {
        debugPrint('[INVENTORY] Failed to load stock adjustments: $e');
        errors.add('Stock Adjustments: ${e.toString().replaceAll('Exception: ', '')}');
        return <StockAdjustment>[];
      }),
    ]);

    try {
      _inventorySummaries = await repository.getInventorySummaries();
    } catch (e) {
      debugPrint('[INVENTORY] Failed to calculate inventory summaries: $e');
      errors.add('Summaries: ${e.toString().replaceAll('Exception: ', '')}');
    }

    if (errors.isNotEmpty) {
      _errorMessage = errors.join(' | ');
      _status = (_sales.isEmpty && _storeInventories.isEmpty && _products.isEmpty)
          ? InventoryStatus.error
          : InventoryStatus.success;
    } else {
      _status = InventoryStatus.success;
    }
    notifyListeners();
  }


  /// Create a new Product in master catalogue (OWNER authorized)
  Future<bool> addProduct({
    required String name,
    required String packageSize,
    required String sku,
    double? standardSellingPrice,
    double? purchaseCost,
    bool active = true,
  }) async {
    try {
      _errorMessage = null;
      await repository.addProduct(
        name: name,
        packageSize: packageSize,
        sku: sku,
        standardSellingPrice: standardSellingPrice,
        purchaseCost: purchaseCost,
        active: active,
      );
      await loadInventoryData();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Create a new Raw Material entry
  Future<bool> addRawMaterial({
    required String name,
    required String unitOfMeasure,
  }) async {
    try {
      _errorMessage = null;
      await repository.addRawMaterial(
        name: name,
        unitOfMeasure: unitOfMeasure,
      );
      await loadInventoryData();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Record an incoming raw material shipment at Neemrana
  Future<bool> addRawMaterialReceipt({
    required String rawMaterialId,
    required double quantity,
    required double cost,
    String? supplierReference,
  }) async {
    try {
      _errorMessage = null;
      await repository.addRawMaterialReceipt(
        rawMaterialId: rawMaterialId,
        quantity: quantity,
        cost: cost,
        supplierReference: supplierReference,
        locationId: Location.neemranaId,
      );
      await loadInventoryData();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Record packed quantity at Neemrana
  Future<bool> addPackingRecord({
    required String productId,
    required int packedQuantity,
    String? rawMaterialId,
    double rawMaterialConsumed = 0.0,
    double wastageQuantity = 0.0,
    String? locationId,
  }) async {
    try {
      _errorMessage = null;
      await repository.addPackingRecord(
        productId: productId,
        packedQuantity: packedQuantity,
        rawMaterialId: rawMaterialId,
        rawMaterialConsumed: rawMaterialConsumed,
        wastageQuantity: wastageQuantity,
        locationId: locationId ?? Location.neemranaId,
      );
      await loadInventoryData();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Inter-store transfers are permanently disabled: Neemrana and Jaipur operate as independent stores.
  Future<bool> createTransfer({
    required String productId,
    required int dispatchedQuantity,
    String? fromLocationId,
    String? toLocationId,
  }) async {
    _errorMessage =
        'Inter-store stock transfers are permanently disabled: '
        'Neemrana and Jaipur operate as independent retail stores.';
    notifyListeners();
    return false;
  }

  /// Inter-store transfers are permanently disabled: Neemrana and Jaipur operate as independent stores.
  Future<bool> confirmTransferReceipt({
    required String transferId,
    required int receivedQuantity,
    String? discrepancyReason,
  }) async {
    _errorMessage =
        'Inter-store stock transfers are permanently disabled: '
        'Neemrana and Jaipur operate as independent retail stores.';
    notifyListeners();
    return false;
  }

  /// Atomically receive finished stock into a store location (additive intake)
  Future<bool> receiveStoreStock({
    required String locationId,
    required String productId,
    required int quantity,
    String? notes,
  }) async {
    try {
      _errorMessage = null;
      await repository.receiveStoreStock(
        locationId: locationId,
        productId: productId,
        quantity: quantity,
        notes: notes,
      );
      await loadInventoryData();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Sale? _lastCreatedSale;
  Sale? get lastCreatedSale => _lastCreatedSale;

  /// Record a POS sale at Neemrana or Jaipur (supports multi-item cart and idempotency)
  Future<Sale?> recordSale({
    String? productId,
    int? quantity,
    List<CartItem>? items,
    String? clientRequestId,
    String? customerName,
    String? customerPhone,
    String paymentMethod = 'CASH',
    String? locationId,
    String? targetLocationId,
    String invoiceType = 'NON_GST',
    double gstRate = 0.0,
    double? taxableAmount,
    double cgstAmount = 0.0,
    double sgstAmount = 0.0,
    double igstAmount = 0.0,
    double totalAmount = 0.0,
    double? unitPrice,
    double discount = 0.0,
    String? callerRole,
  }) async {
    try {
      _errorMessage = null;
      _lastCreatedSale = null;
      final effectiveLocationId =
          locationId ?? targetLocationId ?? Location.jaipurId;
      final storeName =
          effectiveLocationId == Location.neemranaId ? 'Neemrana' : 'Jaipur';

      // Validate stock availability
      if (items != null && items.isNotEmpty) {
        for (final item in items) {
          final summary = _inventorySummaries.firstWhere(
            (s) => s.product.id == item.product.id,
            orElse: () =>
                throw Exception('Product "${item.product.name}" not found.'),
          );
          final availableStock = effectiveLocationId == Location.neemranaId
              ? summary.neemranaFinishedStock
              : summary.jaipurFinishedStock;
          if (item.quantity > availableStock) {
            throw Exception(
                'Cannot sell ${item.quantity} pkts of "${item.product.name}". Only $availableStock available at $storeName.');
          }
        }
      } else if (productId != null && quantity != null) {
        final summary = _inventorySummaries.firstWhere(
          (s) => s.product.id == productId,
          orElse: () => throw Exception('Selected product not found.'),
        );
        final availableStock = effectiveLocationId == Location.neemranaId
            ? summary.neemranaFinishedStock
            : summary.jaipurFinishedStock;
        if (quantity > availableStock) {
          throw Exception(
              'Cannot record sale of $quantity units. Only $availableStock finished packets available at $storeName.');
        }
      }

      final createdSale = await repository.recordSale(
        productId: productId,
        quantity: quantity,
        items: items,
        clientRequestId: clientRequestId,
        customerName: customerName,
        customerPhone: customerPhone,
        paymentMethod: paymentMethod,
        locationId: effectiveLocationId,
        invoiceType: invoiceType,
        gstRate: gstRate,
        taxableAmount: taxableAmount,
        cgstAmount: cgstAmount,
        sgstAmount: sgstAmount,
        igstAmount: igstAmount,
        totalAmount: totalAmount,
        unitPrice: unitPrice,
        discount: discount,
        callerRole: callerRole,
      );
      _lastCreatedSale = createdSale;
      if (!_sales.any((s) => s.id == createdSale.id)) {
        _sales.insert(0, createdSale);
      }
      await loadInventoryData();
      return createdSale;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return null;
    }
  }


  /// Update product master details (name, packageSize, sku, pricing, active status)
  Future<bool> updateProduct({
    required String id,
    String? name,
    String? packageSize,
    String? sku,
    double? standardSellingPrice,
    double? purchaseCost,
    bool? active,
  }) async {
    try {
      _errorMessage = null;
      await repository.updateProduct(
        id: id,
        name: name,
        packageSize: packageSize,
        sku: sku,
        standardSellingPrice: standardSellingPrice,
        purchaseCost: purchaseCost,
        active: active,
      );
      await loadInventoryData();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Toggle product active / inactive status without deleting historical records
  Future<bool> toggleProductActive({
    required String id,
    required bool active,
  }) async {
    return updateProduct(id: id, active: active);
  }

  /// Update standard selling price and purchase cost of a product (OWNER authorized)
  Future<bool> updateProductPricing({
    required String productId,
    required double standardSellingPrice,
    required double purchaseCost,
  }) async {
    try {
      _errorMessage = null;
      await repository.updateProductPricing(
        productId: productId,
        standardSellingPrice: standardSellingPrice,
        purchaseCost: purchaseCost,
      );
      await loadInventoryData();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Record Stock-In directly to a store location
  Future<bool> addStockIn({
    required String productId,
    required int quantity,
    required String locationId,
    String? notes,
  }) async {
    try {
      _errorMessage = null;
      if (quantity <= 0) {
        throw Exception('Stock-in quantity must be greater than zero.');
      }
      await repository.addStockIn(
        productId: productId,
        quantity: quantity,
        locationId: locationId,
        notes: notes,
      );
      await loadInventoryData();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Manually adjust store inventory count (initial count or corrections)
  Future<bool> adjustStoreStock({
    required String locationId,
    required String productId,
    required int newQuantity,
    String reason = 'STOCK_ENTRY',
    String? notes,
  }) async {
    try {
      _errorMessage = null;
      if (newQuantity < 0) {
        throw Exception('Stock quantity cannot be negative.');
      }
      await repository.adjustStoreStock(
        locationId: locationId,
        productId: productId,
        newQuantity: newQuantity,
        reason: reason,
        notes: notes,
      );
      await loadInventoryData();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Void a completed sale (OWNER authorized)
  Future<bool> voidSale({required String saleId}) async {
    try {
      _errorMessage = null;
      await repository.voidSale(saleId: saleId);
      final idx = _sales.indexWhere((s) => s.id == saleId);
      if (idx != -1) {
        _sales[idx] = _sales[idx].copyWith(status: 'VOIDED');
      }
      await loadInventoryData();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Load the next page of sales history from the server.
  /// Deduplicates records by sale.id to guarantee no duplicate sales or lost records.
  Future<bool> loadMoreSales({String? locationId}) async {
    if (_isLoadingMoreSales || !_hasMoreSales) return false;

    _isLoadingMoreSales = true;
    _salesPaginationError = null;
    notifyListeners();

    try {
      final nextPage = await repository.getSales(
        limit: _salesPageSize,
        offset: _serverSalesOffset,
        locationId: locationId,
      );

      if (nextPage.isEmpty) {
        _hasMoreSales = false;
      } else {
        _serverSalesOffset += nextPage.length;
        // Deduplicate against existing sales by id
        final existingIds = _sales.map((s) => s.id).toSet();
        final newSales =
            nextPage.where((s) => !existingIds.contains(s.id)).toList();

        if (nextPage.length < _salesPageSize) {
          _hasMoreSales = false;
        }
        _sales.addAll(newSales);
      }
      _isLoadingMoreSales = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[INVENTORY] Failed to load more sales: $e');
      _salesPaginationError = e.toString().replaceAll('Exception: ', '');
      _isLoadingMoreSales = false;
      notifyListeners();
      return false;
    }
  }

  /// Refreshes sales from page 0 and resets pagination flags
  Future<void> refreshSales({String? locationId}) async {
    _salesPaginationError = null;
    _hasMoreSales = true;
    try {
      final freshSales = await repository.getSales(
        limit: _salesPageSize,
        offset: 0,
        locationId: locationId,
      );
      _sales = List<Sale>.from(freshSales);
      _serverSalesOffset = freshSales.length;
      _hasMoreSales = freshSales.length >= _salesPageSize;
      notifyListeners();
    } catch (e) {
      debugPrint('[INVENTORY] Failed to refresh sales: $e');
      _salesPaginationError = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
    }
  }
}


