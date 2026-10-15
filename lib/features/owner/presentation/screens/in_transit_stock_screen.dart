import 'package:flutter/material.dart';
import '../../../../app/providers/inventory_provider.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/kizuna_card.dart';
import '../../../inventory/data/repositories/unconnected_inventory_repository.dart';
import '../../../inventory/domain/entities/product.dart';
import '../../../inventory/presentation/controllers/inventory_notifier.dart';

/// Screen for In-Transit Stock & Discrepancies monitoring.
class InTransitStockScreen extends StatefulWidget {
  const InTransitStockScreen({super.key});

  @override
  State<InTransitStockScreen> createState() => _InTransitStockScreenState();
}

class _InTransitStockScreenState extends State<InTransitStockScreen> {
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
        title: const Text('In-Transit Stock & Discrepancies'),
        backgroundColor: AppColors.accentDark,
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: notifier,
          builder: (context, _) {
            if (notifier.isLoading) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.accentDark),
              );
            }

            final transfers = notifier.transfers;

            final totalDispatchedAll =
                transfers.fold(0, (sum, t) => sum + t.dispatchedQuantity);
            final totalReceivedAll = transfers.fold(
                0, (sum, t) => sum + (t.receivedQuantity ?? 0));
            final pendingReceiptAll = transfers
                .where((t) => t.isPending)
                .fold(0, (sum, t) => sum + t.dispatchedQuantity);
            final totalDiscrepanciesAll =
                transfers.fold(0, (sum, t) => sum + t.discrepancy);

            return RefreshIndicator(
              onRefresh: () => notifier.loadInventoryData(),
              color: AppColors.accentDark,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Independent Stores Policy Banner
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.amber.shade700.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: Colors.amber.shade800,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Transfers Permanently Disabled',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Neemrana and Jaipur operate as completely independent retail stores. Inter-store dispatches and transfer receipts are permanently disabled. Manifests below are retained for compliance audit only.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.brown.shade800,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Overview Summary Card
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
                                  color: AppColors.accentDark
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.local_shipping_rounded,
                                  color: AppColors.accentDark,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Inter-Unit Transfer Control (Archived)',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'Historical dispatches, receipts and audit manifests.',
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
                              _buildMetricStat('Dispatched',
                                  '$totalDispatchedAll', AppColors.primary),
                              _buildMetricStat('Received',
                                  '$totalReceivedAll', AppColors.success),
                              _buildMetricStat('Pending',
                                  '$pendingReceiptAll', AppColors.warning),
                              _buildMetricStat('Discrepancy',
                                  '$totalDiscrepanciesAll', AppColors.error),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    Text(
                      'Shipment & Transfer Manifests',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),

                    if (transfers.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Text(
                            'No shipment transfers logged yet.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondaryLight),
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: transfers.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final transfer = transfers[index];
                          final product = notifier.products.firstWhere(
                            (p) => p.id == transfer.productId,
                            orElse: () => Product(
                              id: transfer.productId,
                              name: 'Unknown Product',
                              packageSize: '',
                              sku: '',
                              createdAt: DateTime.now(),
                            ),
                          );

                          return KizunaCard(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        product.name,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    _buildStatusBadge(transfer),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'SKU: ${product.sku} • ${product.packageSize}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondaryLight,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.backgroundLight,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text('Dispatched',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: AppColors
                                                        .textSecondaryLight)),
                                            Text(
                                              '${transfer.dispatchedQuantity} units',
                                              style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.bold),
                                            ),
                                            Text(
                                              _formatDate(transfer.dispatchedAt),
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  color: AppColors
                                                      .textMutedLight),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const VerticalDivider(),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text('Received',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: AppColors
                                                        .textSecondaryLight)),
                                            Text(
                                              transfer.isReceived
                                                  ? '${transfer.receivedQuantity} units'
                                                  : 'Pending',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: transfer.isReceived
                                                    ? AppColors.textPrimaryLight
                                                    : AppColors.warning,
                                              ),
                                            ),
                                            if (transfer.receivedAt != null)
                                              Text(
                                                _formatDate(transfer.receivedAt!),
                                                style: const TextStyle(
                                                    fontSize: 10,
                                                    color: AppColors
                                                        .textMutedLight),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Discrepancy Callout if exists
                                if (transfer.hasDiscrepancy) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color:
                                          AppColors.error.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: AppColors.error
                                              .withValues(alpha: 0.3)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(
                                                Icons.report_problem_rounded,
                                                color: AppColors.error,
                                                size: 18),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Discrepancy: ${transfer.discrepancy} units missing',
                                              style: const TextStyle(
                                                color: AppColors.error,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (transfer.discrepancyReason != null &&
                                            transfer.discrepancyReason!
                                                .isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            'Reason: "${transfer.discrepancyReason}"',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.error,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
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

  Widget _buildStatusBadge(dynamic transfer) {
    if (transfer.isPending) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'Pending Receipt',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: AppColors.warning,
          ),
        ),
      );
    }
    if (transfer.hasDiscrepancy) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'Discrepancy',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: AppColors.error,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'Confirmed',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: AppColors.success,
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
