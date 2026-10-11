import 'owner_dashboard_filter.dart';

/// Performance and stock metrics for an individual product SKU.
class ProductPerformanceMetric {
  final String productId;
  final String productName;
  final String sku;
  final String packageSize;
  final int packetsSold;
  final double salesRevenue;
  final int neemranaStock;
  final int jaipurStock;
  final int combinedStock;
  final double? unitCost; // Null if cost basis is not available in database
  final double? cogs; // packetsSold * unitCost
  final double? grossProfit; // salesRevenue - cogs
  final double? grossMarginPercent; // (grossProfit / salesRevenue) * 100
  final bool hasReliableCost;

  const ProductPerformanceMetric({
    required this.productId,
    required this.productName,
    required this.sku,
    required this.packageSize,
    required this.packetsSold,
    required this.salesRevenue,
    required this.neemranaStock,
    required this.jaipurStock,
    required this.combinedStock,
    this.unitCost,
    this.cogs,
    this.grossProfit,
    this.grossMarginPercent,
    this.hasReliableCost = false,
  });

  bool get isSold => packetsSold > 0;
}

/// Comprehensive, database-derived metrics for the Owner executive dashboard.
class OwnerDashboardMetrics {
  final OutletFilter outletFilter;
  final DateRangeFilter dateRangeFilter;

  // Sales Volume & Revenue
  final double totalRevenue;
  final int completedBillsCount;
  final int voidedBillsCount;
  final int totalPacketsSold;

  // Payment Collections
  final double cashTotal;
  final double upiTotal;

  // Outlet-wise Performance
  final double neemranaRevenue;
  final double jaipurRevenue;
  final int neemranaPacketsSold;
  final int jaipurPacketsSold;

  // Current On-Hand Physical Stock (Canonical)
  final int neemranaCurrentStock;
  final int jaipurCurrentStock;
  final int combinedCurrentStock;

  // Product-wise Performance
  final List<ProductPerformanceMetric> allProducts;
  final List<ProductPerformanceMetric> soldProducts;
  final List<ProductPerformanceMetric> unsoldProducts;

  // Cost of Goods Sold (COGS) & Profitability
  final double? totalCogs;
  final double? totalGrossProfit;
  final double? grossMarginPercent;
  final bool hasReliableCostData;

  const OwnerDashboardMetrics({
    required this.outletFilter,
    required this.dateRangeFilter,
    required this.totalRevenue,
    required this.completedBillsCount,
    required this.voidedBillsCount,
    required this.totalPacketsSold,
    required this.cashTotal,
    required this.upiTotal,
    required this.neemranaRevenue,
    required this.jaipurRevenue,
    required this.neemranaPacketsSold,
    required this.jaipurPacketsSold,
    required this.neemranaCurrentStock,
    required this.jaipurCurrentStock,
    required this.combinedCurrentStock,
    required this.allProducts,
    required this.soldProducts,
    required this.unsoldProducts,
    this.totalCogs,
    this.totalGrossProfit,
    this.grossMarginPercent,
    this.hasReliableCostData = false,
  });

  /// Factory for empty/zero metrics state with clear filters.
  factory OwnerDashboardMetrics.empty({
    OutletFilter outletFilter = OutletFilter.all,
    DateRangeFilter dateRangeFilter = const DateRangeFilter.allTime(),
  }) {
    return OwnerDashboardMetrics(
      outletFilter: outletFilter,
      dateRangeFilter: dateRangeFilter,
      totalRevenue: 0.0,
      completedBillsCount: 0,
      voidedBillsCount: 0,
      totalPacketsSold: 0,
      cashTotal: 0.0,
      upiTotal: 0.0,
      neemranaRevenue: 0.0,
      jaipurRevenue: 0.0,
      neemranaPacketsSold: 0,
      jaipurPacketsSold: 0,
      neemranaCurrentStock: 0,
      jaipurCurrentStock: 0,
      combinedCurrentStock: 0,
      allProducts: const [],
      soldProducts: const [],
      unsoldProducts: const [],
      totalCogs: null,
      totalGrossProfit: null,
      grossMarginPercent: null,
      hasReliableCostData: false,
    );
  }
}
