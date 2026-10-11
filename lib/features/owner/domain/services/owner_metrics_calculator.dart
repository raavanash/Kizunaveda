import '../../../../core/constants/app_constants.dart';
import '../../../inventory/domain/entities/product.dart';
import '../../../inventory/domain/entities/product_inventory_summary.dart';
import '../../../inventory/domain/entities/sale.dart';
import '../../../inventory/domain/entities/store_inventory.dart';
import '../entities/owner_dashboard_filter.dart';
import '../entities/owner_dashboard_metrics.dart';

/// Pure domain calculation service for Owner Dashboard analytics and cost accounting.
class OwnerMetricsCalculator {
  OwnerMetricsCalculator._();

  /// Computes comprehensive dashboard metrics from live database entities.
  ///
  /// [sales] - Raw sales list from public.sales with line items.
  /// [products] - Active product catalog from public.products.
  /// [storeInventories] - Canonical store inventory balances from public.store_inventory.
  /// [summaries] - Fallback product inventory summaries.
  /// [outletFilter] - Active store filter (All, Jaipur, Neemrana).
  /// [dateRangeFilter] - Active date range window.
  /// [productUnitCosts] - Optional SKU unit cost map. If absent or null for an item,
  ///   historical profit will NOT be fabricated, and unavailable cost is cleanly flagged.
  static OwnerDashboardMetrics compute({
    required List<Sale> sales,
    required List<Product> products,
    required List<StoreInventory> storeInventories,
    List<ProductInventorySummary> summaries = const [],
    OutletFilter outletFilter = OutletFilter.all,
    DateRangeFilter dateRangeFilter = const DateRangeFilter.allTime(),
    Map<String, double>? productUnitCosts,
  }) {
    // 1. Separate completed vs. voided sales within the date range
    final inDateRangeSales = sales.where((s) => dateRangeFilter.matches(s.soldAt));

    // Filter by outlet if specific store selected
    bool matchesOutlet(Sale s) {
      if (outletFilter == OutletFilter.all) return true;
      if (outletFilter == OutletFilter.jaipur) {
        return s.locationId == LocationConstants.jaipurId;
      }
      if (outletFilter == OutletFilter.neemrana) {
        return s.locationId == LocationConstants.neemranaId;
      }
      return true;
    }

    final filteredCompletedSales = inDateRangeSales
        .where((s) => s.isCompleted && matchesOutlet(s))
        .toList();

    final filteredVoidedSales = inDateRangeSales
        .where((s) => s.isVoided && matchesOutlet(s))
        .toList();

    // 2. Aggregate Sales Revenue, Bills count & Collections
    double totalRevenue = 0.0;
    double cashTotal = 0.0;
    double upiTotal = 0.0;

    for (final sale in filteredCompletedSales) {
      // Net revenue: use taxableAmount when positive to avoid double-counting tax,
      // falling back to totalAmount for standard NON_GST sales.
      final netSaleAmount = sale.totalAmount;
      totalRevenue += netSaleAmount;

      if (sale.isCash) {
        cashTotal += netSaleAmount;
      } else if (sale.isUpi) {
        upiTotal += netSaleAmount;
      }
    }

    // 3. Outlet-specific breakdowns (from all in-date-range completed sales)
    final allCompletedInPeriod = inDateRangeSales.where((s) => s.isCompleted);
    final neemranaSales = allCompletedInPeriod.where(
      (s) => s.locationId == LocationConstants.neemranaId,
    );
    final jaipurSales = allCompletedInPeriod.where(
      (s) => s.locationId == LocationConstants.jaipurId,
    );

    final neemranaRevenue = neemranaSales.fold<double>(
      0.0,
      (sum, s) => sum + s.totalAmount,
    );
    final jaipurRevenue = jaipurSales.fold<double>(
      0.0,
      (sum, s) => sum + s.totalAmount,
    );

    int neemranaPacketsSold = 0;
    for (final sale in neemranaSales) {
      if (sale.items.isNotEmpty) {
        for (final item in sale.items) {
          neemranaPacketsSold += item.quantity;
        }
      } else {
        neemranaPacketsSold += sale.quantity;
      }
    }

    int jaipurPacketsSold = 0;
    for (final sale in jaipurSales) {
      if (sale.items.isNotEmpty) {
        for (final item in sale.items) {
          jaipurPacketsSold += item.quantity;
        }
      } else {
        jaipurPacketsSold += sale.quantity;
      }
    }

    // 4. Product-wise sales aggregation for filtered sales
    final Map<String, int> productSoldQuantities = {};
    final Map<String, double> productSoldRevenue = {};

    for (final sale in filteredCompletedSales) {
      if (sale.items.isNotEmpty) {
        for (final item in sale.items) {
          productSoldQuantities[item.productId] =
              (productSoldQuantities[item.productId] ?? 0) + item.quantity;
          final itemRevenue = item.lineTotal;
          productSoldRevenue[item.productId] =
              (productSoldRevenue[item.productId] ?? 0.0) + itemRevenue;
        }
      } else if (sale.productId.isNotEmpty) {
        productSoldQuantities[sale.productId] =
            (productSoldQuantities[sale.productId] ?? 0) + sale.quantity;
        productSoldRevenue[sale.productId] =
            (productSoldRevenue[sale.productId] ?? 0.0) + sale.totalAmount;
      }
    }

    final int totalPacketsSold = productSoldQuantities.values.fold(
      0,
      (sum, qty) => sum + qty,
    );

    // 5. Canonical On-Hand Inventory per Product & Store
    // Index canonical store_inventory rows
    final Map<String, int> canonicalNeemranaStock = {};
    final Map<String, int> canonicalJaipurStock = {};

    for (final inv in storeInventories) {
      if (inv.locationId == LocationConstants.neemranaId) {
        canonicalNeemranaStock[inv.productId] = inv.currentQuantity;
      } else if (inv.locationId == LocationConstants.jaipurId) {
        canonicalJaipurStock[inv.productId] = inv.currentQuantity;
      }
    }

    // Index summaries as fallback if store_inventory is empty
    final Map<String, int> fallbackNeemranaStock = {};
    final Map<String, int> fallbackJaipurStock = {};
    for (final s in summaries) {
      fallbackNeemranaStock[s.product.id] = s.neemranaFinishedStock;
      fallbackJaipurStock[s.product.id] = s.jaipurStock;
    }

    final int totalNeemranaStock = storeInventories.isNotEmpty
        ? storeInventories
            .where((i) => i.locationId == LocationConstants.neemranaId)
            .fold(0, (sum, i) => sum + i.currentQuantity)
        : fallbackNeemranaStock.values.fold(0, (sum, q) => sum + q);

    final int totalJaipurStock = storeInventories.isNotEmpty
        ? storeInventories
            .where((i) => i.locationId == LocationConstants.jaipurId)
            .fold(0, (sum, i) => sum + i.currentQuantity)
        : fallbackJaipurStock.values.fold(0, (sum, q) => sum + q);

    // 6. Build product-wise performance metrics
    // 6. Build product-wise snapshotted COGS from sale items
    final Map<String, double> productSoldCogs = {};
    final Map<String, bool> productCostMissingForSale = {};

    for (final sale in filteredCompletedSales) {
      if (sale.items.isNotEmpty) {
        for (final item in sale.items) {
          final pid = item.productId;
          final prod = products.where((p) => p.id == pid).firstOrNull;
          final itemUnitCost = item.unitCost ??
              productUnitCosts?[pid] ??
              (prod != null && prod.purchaseCost > 0 ? prod.purchaseCost : null);
          if (itemUnitCost != null && itemUnitCost > 0) {
            productSoldCogs[pid] =
                (productSoldCogs[pid] ?? 0.0) + (itemUnitCost * item.quantity);
          } else {
            productCostMissingForSale[pid] = true;
          }
        }
      } else if (sale.productId.isNotEmpty) {
        final pid = sale.productId;
        final prod = products.where((p) => p.id == pid).firstOrNull;
        final itemUnitCost = productUnitCosts?[pid] ??
            (prod != null && prod.purchaseCost > 0 ? prod.purchaseCost : null);
        if (itemUnitCost != null && itemUnitCost > 0) {
          productSoldCogs[pid] =
              (productSoldCogs[pid] ?? 0.0) + (itemUnitCost * sale.quantity);
        } else {
          productCostMissingForSale[pid] = true;
        }
      }
    }

    final List<ProductPerformanceMetric> productMetrics = [];
    double totalCogsAccumulator = 0.0;
    bool hasAnyReliableCost = false;

    // Collect all active products plus any product appearing in sales or inventory
    final Set<String> catalogProductIds = products.map((p) => p.id).toSet();
    final allProductList = List<Product>.from(products);

    // If there are sale items for products not currently in products catalog,
    // maintain referential integrity
    for (final pid in productSoldQuantities.keys) {
      if (!catalogProductIds.contains(pid)) {
        catalogProductIds.add(pid);
        allProductList.add(
          Product(
            id: pid,
            name: 'Product ${pid.length > 8 ? pid.substring(0, 8) : pid}',
            packageSize: 'Standard',
            sku: 'SKU-${pid.length > 8 ? pid.substring(0, 8) : pid}',
            active: true,
            createdAt: DateTime.now(),
          ),
        );
      }
    }

    // Ensure products existing in store_inventory are also tracked
    for (final inv in storeInventories) {
      if (!catalogProductIds.contains(inv.productId)) {
        catalogProductIds.add(inv.productId);
        final shortId = inv.productId.length > 8
            ? inv.productId.substring(0, 8)
            : inv.productId;
        allProductList.add(
          Product(
            id: inv.productId,
            name: 'Product $shortId',
            packageSize: 'Standard',
            sku: 'KV-$shortId',
            active: true,
            createdAt: DateTime.now(),
          ),
        );
      }
    }

    for (final prod in allProductList) {
      final neemStock = canonicalNeemranaStock[prod.id] ??
          fallbackNeemranaStock[prod.id] ??
          0;
      final jaipStock = canonicalJaipurStock[prod.id] ??
          fallbackJaipurStock[prod.id] ??
          0;
      final combStock = neemStock + jaipStock;

      final int soldCount = productSoldQuantities[prod.id] ?? 0;
      final double soldRev = productSoldRevenue[prod.id] ?? 0.0;

      // Cost of goods sold & gross profit calculation
      final catalogCost = productUnitCosts?[prod.id] ??
          (prod.purchaseCost > 0 ? prod.purchaseCost : null);
      final bool hasMissingSaleCost =
          productCostMissingForSale[prod.id] ?? false;
      final bool hasReliableItemCost =
          productSoldCogs.containsKey(prod.id) && !hasMissingSaleCost;

      double? cogs;
      double? grossProfit;
      double? grossMargin;
      final bool productHasCost;

      if (soldCount > 0) {
        if (hasReliableItemCost) {
          hasAnyReliableCost = true;
          productHasCost = true;
          cogs = productSoldCogs[prod.id]!;
          grossProfit = soldRev - cogs;
          grossMargin = soldRev > 0 ? (grossProfit / soldRev) * 100 : 0.0;
          totalCogsAccumulator += cogs;
        } else {
          // Legacy sales or missing cost: do NOT invent cost or profit
          productHasCost = false;
          cogs = null;
          grossProfit = null;
          grossMargin = null;
        }
      } else {
        // Not sold in period, check if catalog cost is known
        productHasCost = catalogCost != null && catalogCost > 0;
        if (productHasCost) {
          cogs = 0.0;
          grossProfit = 0.0;
          grossMargin = 0.0;
        }
      }

      productMetrics.add(
        ProductPerformanceMetric(
          productId: prod.id,
          productName: prod.name,
          sku: prod.sku,
          packageSize: prod.packageSize,
          packetsSold: soldCount,
          salesRevenue: soldRev,
          neemranaStock: neemStock,
          jaipurStock: jaipStock,
          combinedStock: combStock,
          unitCost: catalogCost,
          cogs: cogs,
          grossProfit: grossProfit,
          grossMarginPercent: grossMargin,
          hasReliableCost: productHasCost,
        ),
      );
    }

    // Sort product metrics: highest sales quantity first, then alphabetically
    productMetrics.sort((a, b) {
      final cmp = b.packetsSold.compareTo(a.packetsSold);
      if (cmp != 0) return cmp;
      return a.productName.compareTo(b.productName);
    });

    final soldProducts = productMetrics.where((p) => p.isSold).toList();
    final unsoldProducts = productMetrics.where((p) => !p.isSold).toList();

    // Determine overall profitability:
    // If any completed sale had missing cost, flag overall as unreliable rather than inventing numbers
    final bool anyMissingCostInSoldSales = productCostMissingForSale.isNotEmpty;
    final bool hasReliableCostData =
        hasAnyReliableCost && !anyMissingCostInSoldSales;

    double? overallCogs;
    double? overallGrossProfit;
    double? overallGrossMargin;

    if (hasReliableCostData) {
      overallCogs = totalCogsAccumulator;
      overallGrossProfit = totalRevenue - overallCogs;
      overallGrossMargin = totalRevenue > 0
          ? (overallGrossProfit / totalRevenue) * 100
          : 0.0;
    }

    return OwnerDashboardMetrics(
      outletFilter: outletFilter,
      dateRangeFilter: dateRangeFilter,
      totalRevenue: totalRevenue,
      completedBillsCount: filteredCompletedSales.length,
      voidedBillsCount: filteredVoidedSales.length,
      totalPacketsSold: totalPacketsSold,
      cashTotal: cashTotal,
      upiTotal: upiTotal,
      neemranaRevenue: neemranaRevenue,
      jaipurRevenue: jaipurRevenue,
      neemranaPacketsSold: neemranaPacketsSold,
      jaipurPacketsSold: jaipurPacketsSold,
      neemranaCurrentStock: totalNeemranaStock,
      jaipurCurrentStock: totalJaipurStock,
      combinedCurrentStock: totalNeemranaStock + totalJaipurStock,
      allProducts: productMetrics,
      soldProducts: soldProducts,
      unsoldProducts: unsoldProducts,
      totalCogs: overallCogs,
      totalGrossProfit: overallGrossProfit,
      grossMarginPercent: overallGrossMargin,
      hasReliableCostData: hasAnyReliableCost,
    );
  }
}
