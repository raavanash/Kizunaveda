import 'product.dart';

/// Computed inventory statistics for a specific product across Neemrana & Jaipur.
/// Supports both canonical physical store stock and legacy calculated fallback.
class ProductInventorySummary {
  final Product product;
  final int totalPacked;
  final int totalNeemranaStockIn;
  final int totalDispatched;
  final int totalReceived;
  final int totalJaipurStockIn;
  final int totalNeemranaSold;
  final int totalJaipurSold;
  final int? neemranaPhysicalStock;
  final int? jaipurPhysicalStock;

  const ProductInventorySummary({
    required this.product,
    required this.totalPacked,
    this.totalNeemranaStockIn = 0,
    required this.totalDispatched,
    required this.totalReceived,
    this.totalJaipurStockIn = 0,
    this.totalNeemranaSold = 0,
    int totalJaipurSold = 0,
    int? totalSold,
    this.neemranaPhysicalStock,
    this.jaipurPhysicalStock,
  }) : totalJaipurSold = totalJaipurSold != 0 ? totalJaipurSold : (totalSold ?? 0);

  /// Total units sold across all stores
  int get totalSold => totalNeemranaSold + totalJaipurSold;

  /// Neemrana finished stock: canonical physical store inventory if available,
  /// else local Neemrana fallback calculation (totalPacked + totalStockIn - totalSold).
  /// Strictly isolated: never deducted by transfers to other stores.
  int get neemranaFinishedStock =>
      neemranaPhysicalStock ??
      (totalPacked + totalNeemranaStockIn - totalNeemranaSold);

  /// Alias for backward compatibility
  int get neemranaRemaining => neemranaFinishedStock;

  /// Jaipur finished stock: canonical physical store inventory if available,
  /// else local Jaipur fallback calculation (totalStockIn - totalSold).
  /// Strictly isolated: never derived from or dependent on Neemrana dispatches.
  int get jaipurFinishedStock =>
      jaipurPhysicalStock ??
      (totalJaipurStockIn - totalJaipurSold);

  /// Alias for backward compatibility
  int get jaipurStock => jaipurFinishedStock;

  /// Combined total stock across both store locations: dynamically calculated
  int get combinedTotalStock => neemranaFinishedStock + jaipurFinishedStock;

  /// Transfer discrepancy: permanently 0 as inter-store transfers are disabled
  int get transferDiscrepancy => 0;
}
