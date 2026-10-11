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

/// Screen for Neemrana Store Inventory & POS Sales operations.
class NeemranaStockScreen extends StatefulWidget {
  const NeemranaStockScreen({super.key});

  @override
  State<NeemranaStockScreen> createState() => _NeemranaStockScreenState();
}

class _NeemranaStockScreenState extends State<NeemranaStockScreen> {
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
        title: const Text('Neemrana Store & Billing'),
        backgroundColor: AppColors.roleNeemrana,
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
                child: CircularProgressIndicator(color: AppColors.roleNeemrana),
              );
            }

            final summaries = notifier.inventorySummaries;
            final remainingAll =
                summaries.fold(0, (sum, s) => sum + s.neemranaRemaining);
            final totalSoldAll =
                summaries.fold(0, (sum, s) => sum + s.totalNeemranaSold);

            final neemranaSales = notifier.sales.where((s) =>
                s.isCompleted && s.locationId == LocationConstants.neemranaId);
            final cashCollected = neemranaSales
                .where((s) => s.isCash)
                .fold(0.0, (sum, s) => sum + s.totalAmount);
            final upiCollected = neemranaSales
                .where((s) => s.isUpi)
                .fold(0.0, (sum, s) => sum + s.totalAmount);
            final totalRevenue = cashCollected + upiCollected;

            return RefreshIndicator(
              onRefresh: () => notifier.loadInventoryData(),
              color: AppColors.roleNeemrana,
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

                    // Neemrana Operations Summary Card
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
                                  color: AppColors.roleNeemrana
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.storefront_rounded,
                                  color: AppColors.roleNeemrana,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Neemrana Store Performance',
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
                              _buildMetricStat('Stock on Hand', '$remainingAll pkts',
                                  AppColors.roleNeemrana),
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

                    // Quick Action Buttons
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.start,
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.roleNeemrana,
                            minimumSize: const Size(140, 44),
                          ),
                          onPressed: () => StockInDialog.show(
                            context,
                            userRole: UserRole.neemrana,
                            initialLocationId: LocationConstants.neemranaId,
                          ),
                          icon: const Icon(Icons.tune_rounded, size: 18),
                          label: const Text('Stock Entry / Edit'),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            minimumSize: const Size(140, 44),
                          ),
                          onPressed: notifier.products.isEmpty
                              ? null
                              : () => _showRecordSaleDialog(context, notifier),
                          icon: const Icon(Icons.point_of_sale_rounded, size: 18),
                          label: const Text('Create Bill'),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                AppColors.roleNeemrana.withValues(alpha: 0.8),
                            minimumSize: const Size(140, 44),
                          ),
                          onPressed: () =>
                              _showAddProductDialog(context, notifier),
                          icon: const Icon(Icons.add_circle_outline_rounded,
                              size: 18),
                          label: const Text('Add Product'),
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
                            'No products registered yet.\nTap "Add Product" to get started.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondaryLight),
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
                                        color: AppColors.roleNeemrana
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'SKU: ${item.product.sku} • ${item.product.packageSize}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.roleNeemrana,
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
                                          'Stock on Hand', '${item.neemranaRemaining}',
                                          isHighlight: true),
                                      _buildSubStat(
                                          'Sold at Neemrana', '${item.totalNeemranaSold}'),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () => StockInDialog.show(
                                      context,
                                      userRole: UserRole.neemrana,
                                      initialLocationId: LocationConstants.neemranaId,
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
                ? AppColors.roleNeemrana
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

  void _showAddProductDialog(BuildContext context, InventoryNotifier notifier) {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final sizeCtrl = TextEditingController();
    final skuCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Register New Product'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Product Name',
                  hintText: 'e.g. A2 Desi Cow Ghee',
                ),
                validator: (val) =>
                    (val?.trim().isEmpty ?? true) ? 'Required' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: sizeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Package Size',
                  hintText: 'e.g. 500ml',
                ),
                validator: (val) =>
                    (val?.trim().isEmpty ?? true) ? 'Required' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: skuCtrl,
                decoration: const InputDecoration(
                  labelText: 'SKU Code',
                  hintText: 'e.g. KV-GHEE-500',
                ),
                validator: (val) =>
                    (val?.trim().isEmpty ?? true) ? 'Required' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.roleNeemrana),
            onPressed: () async {
              if (formKey.currentState?.validate() ?? false) {
                final success = await notifier.addProduct(
                  name: nameCtrl.text,
                  packageSize: sizeCtrl.text,
                  sku: skuCtrl.text,
                );
                if (ctx.mounted && success) {
                  Navigator.pop(ctx);
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showRecordSaleDialog(BuildContext context, InventoryNotifier notifier) {
    RecordPosSaleDialog.show(
      context,
      targetLocationId: LocationConstants.neemranaId,
      locationName: 'Neemrana Store',
      notifier: notifier,
    );
  }
}
