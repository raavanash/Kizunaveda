import 'package:flutter/material.dart';
import '../../../../app/providers/inventory_provider.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/kizuna_card.dart';
import 'invoice_preview_screen.dart';

/// Screen displaying completed and voided retail sale invoices for Jaipur & Owner roles.
class EBillHistoryScreen extends StatefulWidget {
  const EBillHistoryScreen({super.key});

  @override
  State<EBillHistoryScreen> createState() => _EBillHistoryScreenState();
}

class _EBillHistoryScreenState extends State<EBillHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventoryNotifier = InventoryProvider.maybeOf(context);
    final sales = inventoryNotifier?.sales ?? [];

    final completedSales = sales.where((s) => s.isCompleted).toList();
    final voidedSales = sales.where((s) => s.isVoided).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Generated PDF E-Bills History'),
        backgroundColor: AppColors.roleJaipur,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(
              text: 'Active Bills (${completedSales.length})',
              icon: const Icon(Icons.receipt_long_rounded, size: 20),
            ),
            Tab(
              text: 'Voided Bills (${voidedSales.length})',
              icon: const Icon(Icons.cancel_outlined, size: 20),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: inventoryNotifier ?? ChangeNotifier(),
          builder: (context, _) {
            if (inventoryNotifier?.isLoading ?? false) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.roleJaipur),
              );
            }

            return TabBarView(
              controller: _tabController,
              children: [
                // Active Completed Bills Tab
                _buildSalesListView(
                  context,
                  salesList: completedSales,
                  emptyMessage: 'No completed retail invoices found.',
                ),
                // Voided Bills Tab
                _buildSalesListView(
                  context,
                  salesList: voidedSales,
                  emptyMessage: 'No voided bill records found.',
                  isVoidedTab: true,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSalesListView(
    BuildContext context, {
    required List salesList,
    required String emptyMessage,
    bool isVoidedTab = false,
  }) {
    if (salesList.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isVoidedTab
                    ? Icons.remove_shopping_cart_rounded
                    : Icons.receipt_long_outlined,
                size: 56,
                color: AppColors.textMutedLight,
              ),
              const SizedBox(height: 16),
              Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textSecondaryLight,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        final notifier = InventoryProvider.maybeOf(context);
        await notifier?.loadInventoryData();
      },
      color: AppColors.roleJaipur,
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: salesList.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final sale = salesList[index];
          final soldLocal = sale.soldAt.toLocal();
          final dateStr =
              '${soldLocal.day.toString().padLeft(2, '0')}/${soldLocal.month.toString().padLeft(2, '0')}/${soldLocal.year} ${soldLocal.hour.toString().padLeft(2, '0')}:${soldLocal.minute.toString().padLeft(2, '0')}';

          return KizunaCard(
            padding: const EdgeInsets.all(16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => InvoicePreviewScreen(sale: sale),
                ),
              );
            },
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isVoidedTab
                        ? AppColors.error.withValues(alpha: 0.12)
                        : AppColors.roleJaipur.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isVoidedTab
                        ? Icons.cancel_outlined
                        : Icons.receipt_long_rounded,
                    color:
                        isVoidedTab ? AppColors.error : AppColors.roleJaipur,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            sale.billNumber,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isVoidedTab
                                  ? AppColors.error
                                  : AppColors.success,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              sale.status,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: sale.isGst
                                  ? AppColors.primary
                                  : Colors.grey.shade400,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              sale.isGst ? 'GST' : 'NON-GST',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Store: ${sale.locationId == "11111111-1111-1111-1111-111111111111" ? "Neemrana" : "Jaipur"} • Customer: ${sale.customerName ?? "Retail Customer"} (${sale.customerPhone ?? "N/A"})',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondaryLight,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Date: $dateStr • Method: ${sale.paymentMethod}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMutedLight,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹${sale.totalAmount.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color:
                            isVoidedTab ? AppColors.error : AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Row(
                      children: [
                        Text(
                          'View',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.roleJaipur,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: AppColors.roleJaipur,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
