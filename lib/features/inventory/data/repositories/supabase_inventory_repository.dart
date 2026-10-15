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
import '../../../sales/domain/entities/cart_item.dart';

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
    try {
      final response = await _client
          .from('products')
          .select('*, product_procurement_costs(purchase_cost)')
          .order('name', ascending: true);
      return (response as List)
          .map((json) => Product.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[INVENTORY] getProducts procurement costs join error: $e. Falling back to basic product query.');
      final fallbackResponse = await _client
          .from('products')
          .select()
          .order('name', ascending: true);
      return (fallbackResponse as List)
          .map((json) => Product.fromJson(json as Map<String, dynamic>))
          .toList();
    }
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
    final cleanSku = sku.trim().toUpperCase();
    if (cleanSku.isEmpty) throw Exception('Product SKU cannot be empty.');

    if (standardSellingPrice != null && standardSellingPrice < 0) {
      throw Exception('Standard selling price cannot be negative.');
    }
    if (purchaseCost != null && purchaseCost < 0) {
      throw Exception('Purchase cost cannot be negative.');
    }

    final existing = await _client
        .from('products')
        .select('id')
        .eq('sku', cleanSku)
        .maybeSingle();
    if (existing != null) {
      throw Exception('Product with SKU "$cleanSku" already exists.');
    }

    final insertData = <String, dynamic>{
      'name': cleanName,
      'package_size': cleanSize,
      'sku': cleanSku,
      'active': active,
    };
    if (standardSellingPrice != null) {
      insertData['standard_selling_price'] = standardSellingPrice;
    }
    if (purchaseCost != null) {
      insertData['purchase_cost'] = purchaseCost;
    }

    Map<String, dynamic> response;
    try {
      response = await _client
          .from('products')
          .insert(insertData)
          .select()
          .single();
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('purchase_cost') ||
          errStr.contains('standard_selling_price') ||
          errStr.contains('pgrst204') ||
          errStr.contains('42703')) {
        debugPrint('[INVENTORY] addProduct schema fallback: $e');
        final baseData = <String, dynamic>{
          'name': cleanName,
          'package_size': cleanSize,
          'sku': cleanSku,
          'active': active,
        };
        response = await _client
            .from('products')
            .insert(baseData)
            .select()
            .single();
      } else {
        rethrow;
      }
    }

    final newProductId = response['id'] as String;

    if (standardSellingPrice != null || purchaseCost != null) {
      try {
        await _client.rpc(
          'fn_update_product_pricing',
          params: {
            'p_product_id': newProductId,
            'p_standard_selling_price': standardSellingPrice ?? 100.0,
            'p_purchase_cost': purchaseCost ?? 0.0,
          },
        );
      } catch (_) {
        if (purchaseCost != null && purchaseCost > 0) {
          try {
            await _client.from('product_procurement_costs').insert({
              'product_id': newProductId,
              'purchase_cost': purchaseCost,
            });
          } catch (_) {}
        }
      }
    }

    final createdProduct = Product.fromJson(response);
    return createdProduct.copyWith(
      standardSellingPrice: standardSellingPrice ?? createdProduct.standardSellingPrice,
      purchaseCost: purchaseCost ?? createdProduct.purchaseCost,
    );
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
    final Map<String, dynamic> updates = {};
    if (name != null) {
      final cleanName = name.trim();
      if (cleanName.isEmpty) throw Exception('Product name cannot be empty.');
      updates['name'] = cleanName;
    }
    if (packageSize != null) {
      final cleanSize = packageSize.trim();
      if (cleanSize.isEmpty) throw Exception('Package size cannot be empty.');
      updates['package_size'] = cleanSize;
    }
    if (sku != null) {
      final cleanSku = sku.trim().toUpperCase();
      if (cleanSku.isEmpty) throw Exception('Product SKU cannot be empty.');
      final existing = await _client
          .from('products')
          .select('id')
          .eq('sku', cleanSku)
          .neq('id', id)
          .maybeSingle();
      if (existing != null) {
        throw Exception('Product with SKU "$cleanSku" already exists.');
      }
      updates['sku'] = cleanSku;
    }
    if (active != null) {
      updates['active'] = active;
    }
    if (standardSellingPrice != null) {
      if (standardSellingPrice < 0) {
        throw Exception('Standard selling price cannot be negative.');
      }
      updates['standard_selling_price'] = standardSellingPrice;
    }
    if (purchaseCost != null) {
      if (purchaseCost < 0) {
        throw Exception('Purchase cost cannot be negative.');
      }
      updates['purchase_cost'] = purchaseCost;
    }

    if (updates.isNotEmpty) {
      try {
        await _client
            .from('products')
            .update(updates)
            .eq('id', id);
      } catch (e) {
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('purchase_cost') ||
            errStr.contains('standard_selling_price') ||
            errStr.contains('pgrst204') ||
            errStr.contains('42703')) {
          debugPrint('[INVENTORY] updateProduct schema fallback: $e');
          final safeUpdates = Map<String, dynamic>.from(updates)
            ..remove('purchase_cost')
            ..remove('standard_selling_price');
          if (safeUpdates.isNotEmpty) {
            await _client.from('products').update(safeUpdates).eq('id', id);
          }
        } else {
          rethrow;
        }
      }
    }

    if (standardSellingPrice != null || purchaseCost != null) {
      try {
        await _client.rpc(
          'fn_update_product_pricing',
          params: {
            'p_product_id': id,
            'p_standard_selling_price': standardSellingPrice ?? 100.0,
            'p_purchase_cost': purchaseCost ?? 0.0,
          },
        );
      } catch (e) {
        debugPrint('[INVENTORY] fn_update_product_pricing fallback: $e');
        if (purchaseCost != null) {
          try {
            await _client.from('product_procurement_costs').upsert({
              'product_id': id,
              'purchase_cost': purchaseCost,
            });
          } catch (_) {}
        }
      }
    }

    final response = await _client
        .from('products')
        .select()
        .eq('id', id)
        .single();
    final p = Product.fromJson(response);
    return p.copyWith(
      standardSellingPrice: standardSellingPrice ?? p.standardSellingPrice,
      purchaseCost: purchaseCost ?? p.purchaseCost,
    );
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
    try {
      await _client.rpc(
        'fn_update_product_pricing',
        params: {
          'p_product_id': productId,
          'p_standard_selling_price': standardSellingPrice,
          'p_purchase_cost': purchaseCost,
        },
      );
    } catch (e) {
      debugPrint('[INVENTORY] fn_update_product_pricing fallback: $e');
      try {
        await _client
            .from('products')
            .update({
              'standard_selling_price': standardSellingPrice,
            })
            .eq('id', productId);
      } catch (_) {}
      try {
        await _client
            .from('product_procurement_costs')
            .upsert({
              'product_id': productId,
              'purchase_cost': purchaseCost,
            });
      } catch (_) {}
    }
    final response = await _client
        .from('products')
        .select()
        .eq('id', productId)
        .single();
    final p = Product.fromJson(response);
    return p.copyWith(
      standardSellingPrice: standardSellingPrice,
      purchaseCost: purchaseCost,
    );
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
  Future<StockAdjustment> receiveStoreStock({
    required String locationId,
    required String productId,
    required int quantity,
    String? notes,
  }) async {
    try {
      final response = await _client.rpc(
        'fn_receive_store_stock',
        params: {
          'p_location_id': locationId,
          'p_product_id': productId,
          'p_quantity': quantity,
          'p_notes': notes != null && notes.trim().isNotEmpty ? notes.trim() : null,
        },
      );
      final map = Map<String, dynamic>.from(response as Map);
      return StockAdjustment(
        id: (map['adjustment_id'] ?? '') as String,
        locationId: locationId,
        productId: productId,
        previousQuantity: (map['previous_quantity'] as num?)?.toInt() ?? 0,
        newQuantity: (map['new_quantity'] as num?)?.toInt() ?? quantity,
        changeQuantity: (map['change_quantity'] as num?)?.toInt() ?? quantity,
        reason: 'STOCK_RECEIPT',
        notes: notes,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      final msg = e.toString().toLowerCase();
      // If server has not had Migration V1.6 applied yet (PGRST202: function not found in schema cache)
      if (msg.contains('pgrst202') ||
          msg.contains('fn_receive_store_stock') ||
          msg.contains('42883')) {
        debugPrint('[INVENTORY] fn_receive_store_stock not present on server ($e). Falling back to fn_adjust_store_stock.');

        // 1. Fetch current on-hand stock for (locationId, productId)
        int currentQty = 0;
        try {
          final invResponse = await _client
              .from('store_inventory')
              .select('current_quantity')
              .eq('location_id', locationId)
              .eq('product_id', productId)
              .maybeSingle();
          if (invResponse != null && invResponse['current_quantity'] != null) {
            currentQty = (invResponse['current_quantity'] as num).toInt();
          }
        } catch (invErr) {
          debugPrint('[INVENTORY] Could not read baseline stock before adjustment: $invErr');
        }

        // 2. Additively calculate target stock
        final targetQty = currentQty + quantity;

        // 3. Fall back to fn_adjust_store_stock (created in V1.3, verified remotely)
        return await adjustStoreStock(
          locationId: locationId,
          productId: productId,
          newQuantity: targetQty,
          reason: 'STOCK_RECEIPT',
          notes: notes,
        );
      }
      rethrow;
    }
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
    final to = offset + limit - 1;
    try {
      final baseQuery = (locationId != null && locationId.isNotEmpty)
          ? _client
              .from('sales')
              .select('*, sale_items(*, sale_item_procurement_costs(unit_cost))')
              .eq('location_id', locationId)
          : _client
              .from('sales')
              .select('*, sale_items(*, sale_item_procurement_costs(unit_cost))');

      final response = await baseQuery
          .order('created_at', ascending: false)
          .range(offset, to);

      return (response as List)
          .map((json) => Sale.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint(
          '[INVENTORY] getSales procurement costs join error: $e. Falling back to basic sales query.');
      try {
        final fallbackQuery = (locationId != null && locationId.isNotEmpty)
            ? _client
                .from('sales')
                .select('*, sale_items(*)')
                .eq('location_id', locationId)
            : _client
                .from('sales')
                .select('*, sale_items(*)');

        final fallbackResponse = await fallbackQuery
            .order('created_at', ascending: false)
            .range(offset, to);

        return (fallbackResponse as List)
            .map((json) => Sale.fromJson(json as Map<String, dynamic>))
            .toList();
      } catch (fallbackError) {
        debugPrint('[INVENTORY] sales query fallback error: $fallbackError');
        rethrow;
      }
    }
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
    final List<Map<String, dynamic>> itemsPayload;
    if (items != null && items.isNotEmpty) {
      itemsPayload = items.map((i) => i.toRpcItemJson()).toList();
    } else if (productId != null && quantity != null) {
      final effectiveUnitPrice = unitPrice ??
          (totalAmount > 0 && quantity > 0 ? (totalAmount / quantity) : 0.0);
      itemsPayload = [
        {
          'product_id': productId,
          'quantity': quantity,
          'unit_price': effectiveUnitPrice,
          'discount': discount,
        }
      ];
    } else {
      throw ArgumentError(
          'Either items or productId and quantity must be provided.');
    }

    final params = <String, dynamic>{
      'p_customer_name': customerName?.trim(),
      'p_customer_phone': customerPhone?.trim(),
      'p_payment_method': paymentMethod.trim().toUpperCase(),
      'p_items': itemsPayload,
      'p_location_id': locationId,
      'p_invoice_type': invoiceType,
      'p_gst_rate': gstRate,
      'p_taxable_amount': taxableAmount,
      'p_cgst_amount': cgstAmount,
      'p_sgst_amount': sgstAmount,
      'p_igst_amount': igstAmount,
      'p_client_request_id': clientRequestId,
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
    final sales = await getSales();

    final summaries = <ProductInventorySummary>[];

    for (final product in products) {
      final totalPacked = packingRecords
          .where((p) => p.productId == product.id)
          .fold(0, (sum, item) => sum + item.packedQuantity);

      final totalNeemranaStockIn = stockInRecords
          .where((s) => s.productId == product.id && s.locationId == Location.neemranaId)
          .fold(0, (sum, item) => sum + item.quantity);

      // Inter-store transfers are permanently disabled: stock is never transferred
      const totalDispatched = 0;
      const totalReceived = 0;

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


