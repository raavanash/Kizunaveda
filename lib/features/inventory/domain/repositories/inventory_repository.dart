import '../entities/location.dart';
import '../entities/packing_record.dart';
import '../entities/product.dart';
import '../entities/product_inventory_summary.dart';
import '../entities/raw_material.dart';
import '../entities/raw_material_receipt.dart';
import '../entities/sale.dart';
import '../entities/stock_transfer.dart';

import '../entities/stock_in_record.dart';
import '../entities/store_inventory.dart';
import '../entities/stock_adjustment.dart';
import '../../../sales/domain/entities/cart_item.dart';

/// Abstract repository interface defining operations for V1 Inventory Foundation.
abstract class IInventoryRepository {
  /// Fetch all locations
  Future<List<Location>> getLocations();

  /// Fetch all active products
  Future<List<Product>> getProducts();

  /// Create a new product entry (OWNER role authorized)
  Future<Product> addProduct({
    required String name,
    required String packageSize,
    required String sku,
    double? standardSellingPrice,
    double? purchaseCost,
    bool active = true,
  });

  /// Update an existing product entry (OWNER role authorized)
  Future<Product> updateProduct({
    required String id,
    String? name,
    String? packageSize,
    String? sku,
    double? standardSellingPrice,
    double? purchaseCost,
    bool? active,
  });

  /// Update standard selling price and purchase cost of a product (OWNER role authorized)
  Future<Product> updateProductPricing({
    required String productId,
    required double standardSellingPrice,
    required double purchaseCost,
  });

  /// Fetch all raw materials
  Future<List<RawMaterial>> getRawMaterials();

  /// Add a new raw material entry
  Future<RawMaterial> addRawMaterial({
    required String name,
    required String unitOfMeasure,
  });

  /// Fetch all raw material receipts at Neemrana
  Future<List<RawMaterialReceipt>> getRawMaterialReceipts();

  /// Record an incoming raw material shipment at Neemrana
  Future<RawMaterialReceipt> addRawMaterialReceipt({
    required String rawMaterialId,
    required double quantity,
    required double cost,
    String? supplierReference,
    String? locationId,
    DateTime? receivedAt,
  });

  /// Fetch all packing records
  Future<List<PackingRecord>> getPackingRecords();

  /// Record packed quantity at Neemrana (with raw material consumed & wastage)
  Future<PackingRecord> addPackingRecord({
    required String productId,
    required int packedQuantity,
    String? rawMaterialId,
    double rawMaterialConsumed = 0.0,
    double wastageQuantity = 0.0,
    String? locationId,
    DateTime? packedAt,
  });

  /// Fetch all stock-in entries across stores
  Future<List<StockInRecord>> getStockInRecords();

  /// Record stock-in quantity directly for a store
  Future<StockInRecord> addStockIn({
    required String productId,
    required int quantity,
    required String locationId,
    String? notes,
  });

  /// Fetch canonical store inventory records
  Future<List<StoreInventory>> getStoreInventories();

  /// Manually adjust store inventory count (initial stock entry or corrections)
  Future<StockAdjustment> adjustStoreStock({
    required String locationId,
    required String productId,
    required int newQuantity,
    String reason = 'STOCK_ENTRY',
    String? notes,
  });

  /// Atomically receive finished stock into a store location (additive intake)
  Future<StockAdjustment> receiveStoreStock({
    required String locationId,
    required String productId,
    required int quantity,
    String? notes,
  });

  /// Fetch auditable stock adjustments ledger
  Future<List<StockAdjustment>> getStockAdjustments({String? locationId});

  /// Fetch all inter-facility transfers (preserved for read-only historical audit)
  Future<List<StockTransfer>> getTransfers();

  /// Inter-store transfers are permanently disabled.
  /// Throws [UnsupportedError] because Neemrana and Jaipur operate as independent stores.
  Future<StockTransfer> createTransfer({
    required String productId,
    required int dispatchedQuantity,
    String? fromLocationId,
    String? toLocationId,
    DateTime? dispatchedAt,
  });

  /// Inter-store transfers are permanently disabled.
  /// Throws [UnsupportedError] because Neemrana and Jaipur operate as independent stores.
  Future<StockTransfer> confirmTransferReceipt({
    required String transferId,
    required int receivedQuantity,
    String? discrepancyReason,
    DateTime? receivedAt,
  });

  /// Fetch sales with server-side pagination, ordering, and optional location filter.
  /// [limit] - Maximum number of sales records to fetch (default: 50).
  /// [offset] - 0-based row offset for pagination (default: 0).
  /// [locationId] - Optional store location UUID filter.
  Future<List<Sale>> getSales({
    int limit = 50,
    int offset = 0,
    String? locationId,
  });

  /// Record a POS retail sale at Neemrana or Jaipur (supports multi-item cart and idempotency)
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
  });

  /// Void a completed sale (OWNER role authorized)
  Future<Sale> voidSale({required String saleId});

  /// Compute aggregated inventory summaries per product
  Future<List<ProductInventorySummary>> getInventorySummaries();
}


