import 'package:flutter/material.dart';
import '../../../../app/providers/inventory_provider.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/widgets/kizuna_card.dart';
import '../../../owner/domain/entities/owner_dashboard_filter.dart';
import '../widgets/edit_product_pricing_dialog.dart';
import '../widgets/stock_in_dialog.dart';

/// Unified Inventory & Products View inspired by Vyapar:
/// Presents stock on hand across Jaipur and Neemrana, combined inventory counts,
/// and product catalog with quick stock-entry actions.
class UnifiedInventoryView extends StatefulWidget {
  final UserRole role;

  const UnifiedInventoryView({
    super.key,
    required this.role,
  });

  @override
  State<UnifiedInventoryView> createState() => _UnifiedInventoryViewState();
}

class _UnifiedInventoryViewState extends State<UnifiedInventoryView> {
  OutletFilter _selectedOutlet = OutletFilter.all;

  @override
  void initState() {
    super.initState();
    if (widget.role == UserRole.jaipur) {
      _selectedOutlet = OutletFilter.jaipur;
    } else if (widget.role == UserRole.neemrana) {
      _selectedOutlet = OutletFilter.neemrana;
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = InventoryProvider.maybeOf(context);
    final summaries = notifier?.inventorySummaries ?? [];

    final totalJaipurStock =
        summaries.fold<int>(0, (sum, s) => sum + s.jaipurFinishedStock);
    final totalNeemranaStock =
        summaries.fold<int>(0, (sum, s) => sum + s.neemranaFinishedStock);
    final totalCombinedStock = totalJaipurStock + totalNeemranaStock;

    final primaryColor = widget.role == UserRole.neemrana
        ? AppColors.roleNeemrana
        : (widget.role == UserRole.jaipur
            ? AppColors.roleJaipur
            : AppColors.roleOwner);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Inventory & Stock'),
        backgroundColor: primaryColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Inventory',
            onPressed: () => notifier?.loadInventoryData(),
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Stock Entry / Adjust',
            onPressed: () => _openStockIn(context),
          ),
        ],
      ),
      body: SafeArea(
        child: notifier?.isLoading ?? false
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () async => notifier?.loadInventoryData(),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Outlet Filter (if Owner)
                      if (widget.role == UserRole.owner) ...[
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: OutletFilter.values.map((filter) {
                              final isSelected = _selectedOutlet == filter;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(filter.label),
                                  selected: isSelected,
                                  selectedColor: AppColors.roleOwner,
                                  labelStyle: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.grey.shade800,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                  onSelected: (_) {
                                    setState(() => _selectedOutlet = filter);
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Store Stock Summary Cards
                      if (_selectedOutlet == OutletFilter.all ||
                          _selectedOutlet == OutletFilter.jaipur) ...[
                        _buildStoreCard(
                          title: 'Jaipur Retail Store',
                          locationId: LocationConstants.jaipurId,
                          stock: totalJaipurStock,
                          color: AppColors.roleJaipur,
                          icon: Icons.storefront_rounded,
                        ),
                        const SizedBox(height: 12),
                      ],

                      if (_selectedOutlet == OutletFilter.all ||
                          _selectedOutlet == OutletFilter.neemrana) ...[
                        _buildStoreCard(
                          title: 'Neemrana Retail Store',
                          locationId: LocationConstants.neemranaId,
                          stock: totalNeemranaStock,
                          color: AppColors.roleNeemrana,
                          icon: Icons.warehouse_rounded,
                        ),
                        const SizedBox(height: 12),
                      ],

                      if (_selectedOutlet == OutletFilter.all &&
                          widget.role == UserRole.owner) ...[
                        KizunaCard(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.all_inbox_rounded,
                                  color: AppColors.primary,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Combined Outlets Stock',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'Total across Jaipur & Neemrana',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '$totalCombinedStock pkts',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Product Catalog Section
                      Text(
                        'Product Catalog & On-Hand Stock',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 10),

                      if (summaries.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(24),
                          alignment: Alignment.center,
                          child: Text(
                            'No products in inventory.',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: summaries.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 8),
                          itemBuilder: (ctx, idx) {
                            final s = summaries[idx];
                            return KizunaCard(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.green.shade50,
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.local_florist_rounded,
                                      color: Colors.green.shade700,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          s.product.name,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'SKU: ${s.product.sku} • ${s.product.packageSize}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Price: ₹${s.product.standardSellingPrice.toStringAsFixed(2)} | Cost: ₹${s.product.purchaseCost.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.purple.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${s.combinedTotalStock} pkts',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'JPR: ${s.jaipurFinishedStock} | NMR: ${s.neemranaFinishedStock}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (widget.role == UserRole.owner) ...[
                                    const SizedBox(width: 4),
                                    IconButton(
                                      key: Key('edit_pricing_${s.product.id}'),
                                      tooltip: 'Manage Selling Price & Cost',
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(
                                        Icons.edit_note_rounded,
                                        color: AppColors.roleOwner,
                                        size: 20,
                                      ),
                                      onPressed: () {
                                        EditProductPricingDialog.show(
                                          context,
                                          product: s.product,
                                          notifier: notifier!,
                                        );
                                      },
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
              ),
      ),
    );
  }

  Widget _buildStoreCard({
    required String title,
    required String locationId,
    required int stock,
    required Color color,
    required IconData icon,
  }) {
    return KizunaCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Store Inventory & Stock on Hand',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$stock pkts',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: color,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: const Text('Stock In / Edit'),
                onPressed: () => _openStockIn(context, locationId: locationId),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openStockIn(BuildContext context, {String? locationId}) {
    final targetLoc = locationId ??
        (widget.role == UserRole.neemrana
            ? LocationConstants.neemranaId
            : LocationConstants.jaipurId);

    StockInDialog.show(
      context,
      userRole: widget.role,
      initialLocationId: targetLoc,
    );
  }
}
