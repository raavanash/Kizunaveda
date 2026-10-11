import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../../domain/entities/location.dart';
import '../../domain/entities/packing_record.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/product_inventory_summary.dart';
import '../../domain/entities/raw_material.dart';
import '../../domain/entities/raw_material_receipt.dart';
import '../../domain/entities/sale.dart';
import '../../domain/entities/stock_in_record.dart';
import '../../domain/entities/stock_transfer.dart';
import '../../domain/entities/store_inventory.dart';
import '../../domain/entities/stock_adjustment.dart';
import '../../domain/repositories/inventory_repository.dart';

/// Supabase production implementation of [IInventoryRepository].
class SupabaseInventoryRepository implements IInventoryRepository {
  final supabase.SupabaseClient? _customClient;

  SupabaseInventoryRepository({
    supabase.SupabaseClient? supabaseClient,
  }) : _customClient = supabaseClient;

  supabase.SupabaseClient get _client {
    final custom = _customClient;
    if (custom != null) return custom;
    final client = supabase.Supabase.instance.client;
    final session = client.auth.currentSession;
    final user = session?.user;
    debugPrint(
      '[INVENTORY_DIAGNOSTIC] Pre-query auth check: sessionExists=${session != null}, userId=${user?.id}, isExpired=${session?.isExpired}',
    );
    return client;
  }


  @override
  Future<List<Location>> getLocations() async {
    final response = await _client
        .from('locations')
        .select()
        .eq('active', true)
        .order('code', ascending: true);
    return (response as List)
        .map((json) => Location.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Product>> getProducts() async {
    final response = await _client
        .from('products')
        .select()
        .eq('active', true)
        .order('name', ascending: true);
    return (response as List)
        .map((json) => Product.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Product> addProduct({
    required String name,
    required String packageSize,
    required String sku,
  }) async {
    final response = await _client
        .from('products')
        .insert({
          'name': name.trim(),
          'package_size': packageSize.trim(),
          'sku': sku.trim().toUpperCase(),
          'active': true,
        })
        .select()
        .single();
    return Product.fromJson(response);
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
    final response = await _client
        .from('products')
        .update({
          'standard_selling_price': standardSellingPrice,
          'purchase_cost': purchaseCost,
        })
        .eq('id', productId)
        .select()
        .single();
    return Product.fromJson(response);
  }

  @override
  Future<List<RawMaterial>> getRawMaterials() async {
    final response = await _client
        .from('raw_materials')
        .select()
        .eq('active', true)
        .order('name', ascending: true);
    return (response as List)
        .map((json) => RawMaterial.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<RawMaterial> addRawMaterial({
    required String name,
    required String unitOfMeasure,
  }) async {
    final response = await _client
        .from('raw_materials')
        .insert({
          'name': name.trim(),
          'unit_of_measure': unitOfMeasure.trim().toUpperCase(),
          'active': true,
        })
        .select()
        .single();
    return RawMaterial.fromJson(response);
  }

  @override
  Future<List<RawMaterialReceipt>> getRawMaterialReceipts() async {
    final response = await _client
        .from('raw_material_receipts')
        .select()
        .order('received_at', ascending: false);
    return (response as List)
        .map((json) => RawMaterialReceipt.fromJson(json as Map<String, dynamic>))
        .toList();
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
    final response = await _client
        .from('raw_material_receipts')
        .insert({
          'raw_material_id': rawMaterialId,
          'location_id': locationId ?? Location.neemranaId,
          'quantity': quantity,
          'cost': cost,
          'supplier_reference': supplierReference?.trim(),
          'received_at': (receivedAt ?? DateTime.now()).toIso8601String(),
        })
        .select()
        .single();
    return RawMaterialReceipt.fromJson(response);
  }

  @override
  Future<List<PackingRecord>> getPackingRecords() async {
    final response = await _client
        .from('packing_records')
        .select()
        .order('created_at', ascending: false);
    return (response as List)
        .map((json) => PackingRecord.fromJson(json as Map<String, dynamic>))
        .toList();
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
    final locId = locationId ?? Location.neemranaId;
    final payload = <String, dynamic>{
      'location_id': locId,
      'product_id': productId,
      'packed_quantity': packedQuantity,
      'raw_material_consumed': rawMaterialConsumed,
      'wastage_quantity': wastageQuantity,
      'packed_at': (packedAt ?? DateTime.now()).toIso8601String(),
    };
    if (rawMaterialId != null) {
      payload['raw_material_id'] = rawMaterialId;
    }

    final response = await _client
        .from('packing_records')
        .insert(payload)
        .select()
        .single();
    return PackingRecord.fromJson(response);
  }

  @override
  Future<List<StockInRecord>> getStockInRecords() async {
    final response = await _client
        .from('stock_in_records')
        .select('*, products(*), locations(*)')
        .order('created_at', ascending: false);
    return (response as List)
        .map((json) => StockInRecord.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<StockInRecord> addStockIn({
    required String productId,
    required int quantity,
    required String locationId,
    String? notes,
  }) async {
    final payload = <String, dynamic>{
      'product_id': productId,
      'location_id': locationId,
      'quantity': quantity,
    };
    if (notes != null && notes.trim().isNotEmpty) {
      payload['notes'] = notes.trim();
    }

    final response = await _client
        .from('stock_in_records')
        .insert(payload)
        .select('*, products(*), locations(*)')
        .single();
    return StockInRecord.fromJson(response);
  }

  @override
  Future<List<StoreInventory>> getStoreInventories() async {
    try {
      final response = await _client
          .from('store_inventory')
          .select()
          .order('updated_at', ascending: false);
      return (response as List)
          .map((json) => StoreInventory.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('relation "store_inventory" does not exist') ||
          msg.contains('42p01')) {
        debugPrint('[INVENTORY] store_inventory table not yet present: $e');
        return [];
      }
      debugPrint('[INVENTORY] store_inventory query error: $e');
      rethrow;
    }
  }

  @override
  Future<StockAdjustment> adjustStoreStock({
    required String locationId,
    required String productId,
    required int newQuantity,
    String reason = 'STOCK_ENTRY',
    String? notes,
  }) async {
    final response = await _client.rpc(
      'fn_adjust_store_stock',
      params: {
        'p_location_id': locationId,
        'p_product_id': productId,
        'p_new_quantity': newQuantity,
        'p_reason': reason.trim(),
        'p_notes': notes != null && notes.trim().isNotEmpty ? notes.trim() : null,
      },
    );
    final map = Map<String, dynamic>.from(response as Map);
    return StockAdjustment(
      id: (map['adjustment_id'] ?? '') as String,
      locationId: locationId,
      productId: productId,
      previousQuantity: (map['previous_quantity'] as num?)?.toInt() ?? 0,
      newQuantity: (map['new_quantity'] as num?)?.toInt() ?? newQuantity,
      changeQuantity: (map['change_quantity'] as num?)?.toInt() ?? 0,
      reason: (map['reason'] ?? reason) as String,
      notes: notes,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<List<StockAdjustment>> getStockAdjustments({String? locationId}) async {
    try {
      var query = _client.from('stock_adjustments').select();
      if (locationId != null) {
        query = query.eq('location_id', locationId);
      }
      final response = await query.order('created_at', ascending: false);
      return (response as List)
          .map((json) => StockAdjustment.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('relation "stock_adjustments" does not exist') ||
          msg.contains('42p01')) {
        debugPrint('[INVENTORY] stock_adjustments table not yet present: $e');
        return [];
      }
      debugPrint('[INVENTORY] stock_adjustments query error: $e');
      rethrow;
    }
  }

  @override
  Future<List<StockTransfer>> getTransfers() async {

    final response = await _client
        .from('transfers')
        .select()
        .order('created_at', ascending: false);
    return (response as List)
        .map((json) => StockTransfer.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<StockTransfer> createTransfer({
    required String productId,
    required int dispatchedQuantity,
    String? fromLocationId,
    String? toLocationId,
    DateTime? dispatchedAt,
  }) async {
    final response = await _client
        .from('transfers')
        .insert({
          'product_id': productId,
          'from_location_id': fromLocationId ?? Location.neemranaId,
          'to_location_id': toLocationId ?? Location.jaipurId,
          'dispatched_quantity': dispatchedQuantity,
          'dispatched_at': (dispatchedAt ?? DateTime.now()).toIso8601String(),
        })
        .select()
        .single();
    return StockTransfer.fromJson(response);
  }

  @override
  Future<StockTransfer> confirmTransferReceipt({
    required String transferId,
    required int receivedQuantity,
    String? discrepancyReason,
    DateTime? receivedAt,
  }) async {
    final response = await _client.rpc(
      'fn_confirm_jaipur_receipt',
      params: {
        'p_transfer_id': transferId,
        'p_received_quantity': receivedQuantity,
        'p_discrepancy_reason': discrepancyReason?.trim(),
      },
    );
    return StockTransfer.fromJson(Map<String, dynamic>.from(response as Map));
  }

  @override
  Future<List<Sale>> getSales() async {
    try {
      final response = await _client
          .from('sales')
          .select('*, sale_items(*)')
          .order('created_at', ascending: false);
      return (response as List)
          .map((json) => Sale.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[INVENTORY] sales query error: $e');
      rethrow;
    }
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
    final effectiveUnitPrice = unitPrice ??
        (totalAmount > 0 && quantity > 0 ? (totalAmount / quantity) : 0.0);
    final params = <String, dynamic>{
      'p_customer_name': customerName?.trim(),
      'p_customer_phone': customerPhone?.trim(),
      'p_payment_method': paymentMethod.trim().toUpperCase(),
      'p_items': [
        {
          'product_id': productId,
          'quantity': quantity,
          'unit_price': effectiveUnitPrice,
          'discount': discount,
        }
      ],
      'p_location_id': locationId,
      'p_invoice_type': invoiceType,
      'p_gst_rate': gstRate,
      'p_taxable_amount': taxableAmount,
      'p_cgst_amount': cgstAmount,
      'p_sgst_amount': sgstAmount,
      'p_igst_amount': igstAmount,
    };

    final response = await _client.rpc(
      'fn_create_pos_sale',
      params: params,
    );
    return Sale.fromJson(Map<String, dynamic>.from(response as Map));
  }

  @override
  Future<Sale> voidSale({required String saleId}) async {
    final response = await _client
        .from('sales')
        .update({'status': 'VOIDED'})
        .eq('id', saleId)
        .select('*, sale_items(*)')
        .single();
    return Sale.fromJson(response);
  }

  @override
  Future<List<ProductInventorySummary>> getInventorySummaries() async {
    final products = await getProducts();
    final packingRecords = await getPackingRecords();
    List<StockInRecord> stockInRecords = [];
    try {
      stockInRecords = await getStockInRecords();
    } catch (_) {
      // StockIn table fallback if not yet migrated
    }
    List<StoreInventory> storeInventories = [];
    try {
      storeInventories = await getStoreInventories();
    } catch (_) {
      // StoreInventory table fallback if not yet migrated
    }
    final transfers = await getTransfers();
    final sales = await getSales();

    final summaries = <ProductInventorySummary>[];

    for (final product in products) {
      final totalPacked = packingRecords
          .where((p) => p.productId == product.id)
          .fold(0, (sum, item) => sum + item.packedQuantity);

      final totalNeemranaStockIn = stockInRecords
          .where((s) => s.productId == product.id && s.locationId == Location.neemranaId)
          .fold(0, (sum, item) => sum + item.quantity);

      final totalDispatched = transfers
          .where((t) => t.productId == product.id)
          .fold(0, (sum, item) => sum + item.dispatchedQuantity);

      final totalReceived = transfers
          .where((t) => t.productId == product.id && t.receivedQuantity != null)
          .fold(0, (sum, item) => sum + (item.receivedQuantity ?? 0));

      final totalJaipurStockIn = stockInRecords
          .where((s) => s.productId == product.id && s.locationId == Location.jaipurId)
          .fold(0, (sum, item) => sum + item.quantity);

      final completedSales = sales.where((s) => s.isCompleted);

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
          .where((s) => s.locationId == Location.jaipurId)
          .fold(0, (sum, sale) {
            if (sale.items.isNotEmpty) {
              return sum +
                  sale.items
                      .where((i) => i.productId == product.id)
                      .fold(0, (acc, item) => acc + item.quantity);
            }
            return sale.productId == product.id ? sum + sale.quantity : sum;
          });

      // Find canonical store inventory row if present
      final neemranaInv = storeInventories
          .where((s) => s.productId == product.id && s.locationId == Location.neemranaId)
          .firstOrNull;
      final jaipurInv = storeInventories
          .where((s) => s.productId == product.id && s.locationId == Location.jaipurId)
          .firstOrNull;

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
          neemranaPhysicalStock: neemranaInv?.currentQuantity,
          jaipurPhysicalStock: jaipurInv?.currentQuantity,
        ),
      );
    }

    return summaries;
  }
}


