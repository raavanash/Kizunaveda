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

enum InventoryStatus { initial, loading, success, error }

/// State controller managing V1 Inventory Flow with location-based validation.
class InventoryNotifier extends ChangeNotifier {
  final IInventoryRepository repository;

  InventoryNotifier({required this.repository}) {
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
      repository.getSales().then((v) => _sales = v).catchError((e) {
        debugPrint('[INVENTORY] Failed to load sales: $e');
        errors.add('Sales: ${e.toString().replaceAll('Exception: ', '')}');
        return <Sale>[];
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


  /// Create a new Product
  Future<bool> addProduct({
    required String name,
    required String packageSize,
    required String sku,
  }) async {
    try {
      _errorMessage = null;
      await repository.addProduct(
        name: name,
        packageSize: packageSize,
        sku: sku,
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

  /// Dispatch stock from Neemrana to Jaipur
  Future<bool> createTransfer({
    required String productId,
    required int dispatchedQuantity,
    String? fromLocationId,
    String? toLocationId,
  }) async {
    try {
      _errorMessage = null;
      final summary = _inventorySummaries.firstWhere(
        (s) => s.product.id == productId,
        orElse: () => throw Exception('Selected product not found.'),
      );

      if (dispatchedQuantity > summary.neemranaFinishedStock) {
        throw Exception(
            'Cannot dispatch $dispatchedQuantity units. Only ${summary.neemranaFinishedStock} finished packets remaining at Neemrana.');
      }

      await repository.createTransfer(
        productId: productId,
        dispatchedQuantity: dispatchedQuantity,
        fromLocationId: fromLocationId ?? Location.neemranaId,
        toLocationId: toLocationId ?? Location.jaipurId,
      );
      await loadInventoryData();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Confirm receipt of a transfer at Jaipur
  Future<bool> confirmTransferReceipt({
    required String transferId,
    required int receivedQuantity,
    String? discrepancyReason,
  }) async {
    try {
      _errorMessage = null;
      final transfer = _transfers.firstWhere(
        (t) => t.id == transferId,
        orElse: () => throw Exception('Transfer record not found.'),
      );

      if (receivedQuantity > transfer.dispatchedQuantity) {
        throw Exception(
            'Received quantity ($receivedQuantity) cannot exceed dispatched quantity (${transfer.dispatchedQuantity}).');
      }

      if (receivedQuantity != transfer.dispatchedQuantity &&
          (discrepancyReason == null || discrepancyReason.trim().isEmpty)) {
        throw Exception(
            'Discrepancy reason is required when received quantity differs from dispatched quantity.');
      }

      await repository.confirmTransferReceipt(
        transferId: transferId,
        receivedQuantity: receivedQuantity,
        discrepancyReason: discrepancyReason,
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

  /// Record a POS sale at Neemrana or Jaipur
  Future<Sale?> recordSale({
    required String productId,
    required int quantity,
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
  }) async {
    try {
      _errorMessage = null;
      _lastCreatedSale = null;
      final effectiveLocationId = locationId ?? targetLocationId ?? Location.jaipurId;
      final summary = _inventorySummaries.firstWhere(
        (s) => s.product.id == productId,
        orElse: () => throw Exception('Selected product not found.'),
      );

      final availableStock = effectiveLocationId == Location.neemranaId
          ? summary.neemranaFinishedStock
          : summary.jaipurFinishedStock;

      final storeName = effectiveLocationId == Location.neemranaId ? 'Neemrana' : 'Jaipur';

      if (quantity > availableStock) {
        throw Exception(
            'Cannot record sale of $quantity units. Only $availableStock finished packets available at $storeName.');
      }

      final createdSale = await repository.recordSale(
        productId: productId,
        quantity: quantity,
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
      );
      _lastCreatedSale = createdSale;
      await loadInventoryData();
      return createdSale;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return null;
    }
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
      await loadInventoryData();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }
}


