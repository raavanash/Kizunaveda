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

  /// Neemrana finished stock: canonical physical stock if available, else legacy formula
  int get neemranaFinishedStock =>
      neemranaPhysicalStock ??
      (totalPacked + totalNeemranaStockIn - totalDispatched - totalNeemranaSold);

  /// Alias for backward compatibility
  int get neemranaRemaining => neemranaFinishedStock;

  /// Jaipur finished stock: canonical physical stock if available, else legacy formula
  int get jaipurFinishedStock =>
      jaipurPhysicalStock ??
      (totalReceived + totalJaipurStockIn - totalJaipurSold);

  /// Alias for backward compatibility
  int get jaipurStock => jaipurFinishedStock;

  /// Combined total stock across both store locations: dynamically calculated
  int get combinedTotalStock => neemranaFinishedStock + jaipurFinishedStock;

  /// Transfer discrepancy = Dispatched quantity MINUS Received quantity
  int get transferDiscrepancy => totalDispatched - totalReceived;
}
