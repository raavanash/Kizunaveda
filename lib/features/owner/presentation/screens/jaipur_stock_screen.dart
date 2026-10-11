import 'package:flutter/material.dart';
import '../../../../app/providers/inventory_provider.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/widgets/kizuna_card.dart';
import '../../../inventory/data/repositories/unconnected_inventory_repository.dart';
import '../../../inventory/presentation/controllers/inventory_notifier.dart';
import '../../../inventory/presentation/widgets/record_pos_sale_dialog.dart';
import '../../../inventory/presentation/widgets/stock_in_dialog.dart';
import '../../../jaipur/presentation/screens/ebill_history_screen.dart';

/// Screen for Jaipur Store Inventory & POS Sales operations.
class JaipurStockScreen extends StatefulWidget {
  const JaipurStockScreen({super.key});

  @override
  State<JaipurStockScreen> createState() => _JaipurStockScreenState();
}

class _JaipurStockScreenState extends State<JaipurStockScreen> {
  InventoryNotifier? _fallbackNotifier;

  InventoryNotifier _getNotifier(BuildContext context) {
    final provided = InventoryProvider.maybeOf(context);
    if (provided != null) return provided;
    _fallbackNotifier ??=
        InventoryNotifier(repository: UnconnectedInventoryRepository());
    return _fallbackNotifier!;
  }

  @override
  void dispose() {
    _fallbackNotifier?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = _getNotifier(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Jaipur Store & Billing'),
        backgroundColor: AppColors.roleJaipur,
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_rounded),
            tooltip: 'E-Bill History',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const EBillHistoryScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: notifier,
          builder: (context, _) {
            if (notifier.isLoading) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.roleJaipur),
              );
            }

            final summaries = notifier.inventorySummaries;
            final totalJaipurStockAll =
                summaries.fold(0, (sum, s) => sum + s.jaipurStock);
            final totalSoldAll =
                summaries.fold(0, (sum, s) => sum + s.totalJaipurSold);

            final jaipurSales = notifier.sales.where((s) =>
                s.isCompleted && s.locationId == LocationConstants.jaipurId);
            final cashCollected = jaipurSales
                .where((s) => s.isCash)
                .fold(0.0, (sum, s) => sum + s.totalAmount);
            final upiCollected = jaipurSales
                .where((s) => s.isUpi)
                .fold(0.0, (sum, s) => sum + s.totalAmount);
            final totalRevenue = cashCollected + upiCollected;

            return RefreshIndicator(
              onRefresh: () => notifier.loadInventoryData(),
              color: AppColors.roleJaipur,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (notifier.errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.error),
                        ),
                        child: Text(
                          notifier.errorMessage!,
                          style: const TextStyle(
                              color: AppColors.error, fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Jaipur Operations Overview Card
                    KizunaCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.roleJaipur
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.storefront_rounded,
                                  color: AppColors.roleJaipur,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Jaipur Store Performance',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'Independent retail store inventory, sales & cash/UPI collections.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondaryLight,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildMetricStat('Stock on Hand',
                                  '$totalJaipurStockAll pkts', AppColors.roleJaipur),
                              _buildMetricStat(
                                  'Units Sold', '$totalSoldAll pkts', AppColors.primary),
                              _buildMetricStat('Sales Revenue',
                                  '₹${totalRevenue.toStringAsFixed(0)}', AppColors.success),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                Text(
                                  'Cash: ₹${cashCollected.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondaryLight,
                                  ),
                                ),
                                const Text('•',
                                    style: TextStyle(
                                        color: AppColors.textMutedLight)),
                                Text(
                                  'UPI: ₹${upiCollected.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondaryLight,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Actions Row
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.roleJaipur,
                              minimumSize: const Size.fromHeight(44),
                            ),
                            onPressed: () => StockInDialog.show(
                              context,
                              userRole: UserRole.jaipur,
                              initialLocationId: LocationConstants.jaipurId,
                            ),
                            icon: const Icon(Icons.tune_rounded, size: 18),
                            label: const Text('Stock Entry / Edit'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              minimumSize: const Size.fromHeight(44),
                            ),
                            onPressed: notifier.products.isEmpty
                                ? null
                                : () => _showRecordSaleDialog(context, notifier),
                            icon: const Icon(Icons.point_of_sale_rounded,
                                size: 18),
                            label: const Text('Record POS Sale'),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    Text(
                      'Store Inventory & Stock on Hand',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),

                    if (summaries.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Text(
                            'No inventory records found.',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: AppColors.textSecondaryLight),
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: summaries.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final item = summaries[index];
                          return KizunaCard(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.product.name,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.roleJaipur
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'SKU: ${item.product.sku} • ${item.product.packageSize}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.roleJaipur,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.backgroundLight,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceAround,
                                    children: [
                                      _buildSubStat(
                                          'Stock on Hand', '${item.jaipurStock}',
                                          isHighlight: true),
                                      _buildSubStat(
                                          'Sold at Jaipur', '${item.totalJaipurSold}'),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () => StockInDialog.show(
                                      context,
                                      userRole: UserRole.jaipur,
                                      initialLocationId: LocationConstants.jaipurId,
                                      initialProduct: item.product,
                                    ),
                                    icon: const Icon(Icons.edit_note_rounded, size: 16),
                                    label: const Text('Adjust Stock', style: TextStyle(fontSize: 12)),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMetricStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondaryLight,
          ),
        ),
      ],
    );
  }

  Widget _buildSubStat(String label, String value, {bool isHighlight = false}) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: isHighlight ? 18 : 15,
            fontWeight: isHighlight ? FontWeight.bold : FontWeight.w600,
            color: isHighlight
                ? AppColors.roleJaipur
                : AppColors.textPrimaryLight,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondaryLight,
          ),
        ),
      ],
    );
  }

  void _showRecordSaleDialog(BuildContext context, InventoryNotifier notifier) {
    RecordPosSaleDialog.show(
      context,
      targetLocationId: LocationConstants.jaipurId,
      locationName: 'Jaipur Store',
      notifier: notifier,
    );
  }
}
