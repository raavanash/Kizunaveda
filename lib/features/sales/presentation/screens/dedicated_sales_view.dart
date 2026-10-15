import 'package:flutter/material.dart';
import '../../../../app/providers/inventory_provider.dart';
import '../../../inventory/presentation/controllers/inventory_notifier.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/pdf_invoice_service.dart';
import '../../../../core/widgets/kizuna_card.dart';
import '../../../auth/presentation/controllers/auth_notifier.dart';
import '../../../inventory/domain/entities/product.dart';
import '../../../inventory/domain/entities/sale.dart';
import '../../../jaipur/presentation/screens/invoice_preview_screen.dart';
import '../../../owner/domain/entities/owner_dashboard_filter.dart';
import 'guided_new_sale_screen.dart';

/// Dedicated Sales Tab inspired by Vyapar:
/// Displays bill history cards with search, outlet/date/status filters,
/// contextual WhatsApp sharing, thermal receipt viewing, and a prominent "+ New Sale" CTA.
class DedicatedSalesView extends StatefulWidget {
  final UserRole role;
  final AuthNotifier? authNotifier;

  const DedicatedSalesView({
    super.key,
    required this.role,
    this.authNotifier,
  });

  @override
  State<DedicatedSalesView> createState() => _DedicatedSalesViewState();
}

class _DedicatedSalesViewState extends State<DedicatedSalesView> {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  OutletFilter _selectedOutlet = OutletFilter.all;
  DateRangePreset _selectedDatePreset = DateRangePreset.allTime;
  String _selectedStatus = 'ALL'; // ALL, COMPLETED, VOIDED

  @override
  void initState() {
    super.initState();
    if (widget.role == UserRole.jaipur) {
      _selectedOutlet = OutletFilter.jaipur;
    } else if (widget.role == UserRole.neemrana) {
      _selectedOutlet = OutletFilter.neemrana;
    }
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200) {
      final notifier = InventoryProvider.maybeOf(context);
      if (notifier != null &&
          notifier.hasMoreSales &&
          !notifier.isLoadingMoreSales) {
        notifier.loadMoreSales(locationId: _effectiveLocationId());
      }
    }
  }

  String? _effectiveLocationId({OutletFilter? outlet}) {
    if (widget.role == UserRole.neemrana) return LocationConstants.neemranaId;
    if (widget.role == UserRole.jaipur) return LocationConstants.jaipurId;
    final currentOutlet = outlet ?? _selectedOutlet;
    if (currentOutlet == OutletFilter.neemrana) {
      return LocationConstants.neemranaId;
    }
    if (currentOutlet == OutletFilter.jaipur) {
      return LocationConstants.jaipurId;
    }
    return null;
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Sale> _filterSales(List<Sale> allSales) {
    return allSales.where((sale) {
      // 1. Status filter
      if (_selectedStatus == 'COMPLETED' && !sale.isCompleted) return false;
      if (_selectedStatus == 'VOIDED' && !sale.isVoided) return false;

      // 2. Outlet filter
      if (_selectedOutlet == OutletFilter.jaipur &&
          sale.locationId != LocationConstants.jaipurId) {
        return false;
      }
      if (_selectedOutlet == OutletFilter.neemrana &&
          sale.locationId != LocationConstants.neemranaId) {
        return false;
      }

      // 3. Date filter
      final dateFilter = DateRangeFilter(preset: _selectedDatePreset);
      if (!dateFilter.matches(sale.soldAt)) return false;

      // 4. Search query
      final query = _searchCtrl.text.trim().toLowerCase();
      if (query.isNotEmpty) {
        final billMatch = sale.billNumber.toLowerCase().contains(query);
        final nameMatch =
            (sale.customerName ?? '').toLowerCase().contains(query);
        final phoneMatch =
            (sale.customerPhone ?? '').toLowerCase().contains(query);
        if (!billMatch && !nameMatch && !phoneMatch) return false;
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = InventoryProvider.maybeOf(context);
    final allSales = notifier?.sales ?? [];
    final filteredSales = _filterSales(allSales);

    final totalAmount = filteredSales
        .where((s) => s.isCompleted)
        .fold(0.0, (sum, s) => sum + s.totalAmount);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Sales & Bill History'),
        backgroundColor: widget.role == UserRole.neemrana
            ? AppColors.roleNeemrana
            : (widget.role == UserRole.jaipur
                ? AppColors.roleJaipur
                : AppColors.roleOwner),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Sales',
            onPressed: () => notifier?.loadInventoryData(),
          ),
          TextButton.icon(
            key: const Key('new_sale_button'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
            label: const Text('New Sale',
                style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => _openNewSale(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Controls: Search & Filters
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              color: Colors.white,
              child: Column(
                children: [
                  // Search Bar
                  TextField(
                    key: const Key('sales_search_field'),
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search by bill #, customer, or phone...',
                      prefixIcon:
                          const Icon(Icons.search_rounded, color: Colors.grey),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                setState(() {
                                  _searchCtrl.clear();
                                });
                              },
                            )
                          : null,
                      isDense: true,
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),

                  // Filter Chips Scrollable Row
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        // Status Filter
                        _buildFilterDropdown<String>(
                          label: _selectedStatus == 'ALL'
                              ? 'Status: All'
                              : (_selectedStatus == 'COMPLETED'
                                  ? 'Active Bills'
                                  : 'Voided Bills'),
                          value: _selectedStatus,
                          items: const [
                            DropdownMenuItem(
                                value: 'ALL', child: Text('All Bills')),
                            DropdownMenuItem(
                                value: 'COMPLETED',
                                child: Text('Active (Completed)')),
                            DropdownMenuItem(
                                value: 'VOIDED', child: Text('Voided')),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedStatus = val);
                          },
                        ),
                        const SizedBox(width: 8),

                        // Date Filter
                        _buildFilterDropdown<DateRangePreset>(
                          label: _selectedDatePreset.label,
                          value: _selectedDatePreset,
                          items: DateRangePreset.values
                              .where((p) => p != DateRangePreset.custom)
                              .map((p) => DropdownMenuItem(
                                    value: p,
                                    child: Text(p.label),
                                  ))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedDatePreset = val);
                            }
                          },
                        ),
                        const SizedBox(width: 8),

                        // Outlet Filter (if Owner)
                        if (widget.role == UserRole.owner) ...[
                          _buildFilterDropdown<OutletFilter>(
                            label: _selectedOutlet.label,
                            value: _selectedOutlet,
                            items: OutletFilter.values
                                .map((o) => DropdownMenuItem(
                                      value: o,
                                      child: Text(o.label),
                                    ))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedOutlet = val);
                                final notifier =
                                    InventoryProvider.maybeOf(context);
                                notifier?.refreshSales(
                                  locationId: _effectiveLocationId(outlet: val),
                                );
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Summary Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.grey.shade100,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${filteredSales.length} Bills Listed',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  Text(
                    'Total: ₹${totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),

            // Sales List View
            Expanded(
              child: notifier?.isLoading ?? false
                  ? const Center(child: CircularProgressIndicator())
                  : filteredSales.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: () async => notifier?.refreshSales(
                            locationId: _effectiveLocationId(),
                          ),
                          child: ListView.separated(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(12),
                            itemCount: filteredSales.length +
                                (notifier != null ? 1 : 0),
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (ctx, idx) {
                              if (idx == filteredSales.length) {
                                return _buildPaginationFooter(
                                    notifier!, filteredSales.length);
                              }
                              return _buildBillCard(filteredSales[idx]);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterDropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimaryLight,
          ),
          icon: const Icon(Icons.arrow_drop_down, size: 18),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final notifier = InventoryProvider.maybeOf(context);
    final hasMore = notifier?.hasMoreSales ?? false;
    final isLoadingMore = notifier?.isLoadingMoreSales ?? false;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'No Bills Found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'No sales match your search or selected filters.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 20),
            if (hasMore) ...[
              OutlinedButton.icon(
                key: const Key('empty_state_load_more_btn'),
                onPressed: isLoadingMore
                    ? null
                    : () => notifier?.loadMoreSales(
                          locationId: _effectiveLocationId(),
                        ),
                icon: isLoadingMore
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_downward, size: 16),
                label: Text(
                  isLoadingMore
                      ? 'Searching older bills...'
                      : 'Load Older Bills',
                ),
              ),
              const SizedBox(height: 12),
            ],
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: () => _openNewSale(context),
              icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
              label: const Text('Create New Sale'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaginationFooter(
      InventoryNotifier notifier, int displayedCount) {
    if (notifier.isLoadingMoreSales) {
      return Container(
        key: const Key('sales_pagination_loading'),
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              'Loading older bills...',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    if (notifier.salesPaginationError != null) {
      return Container(
        key: const Key('sales_pagination_error'),
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 20, color: Colors.red.shade700),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Failed to load more bills: ${notifier.salesPaginationError}',
                style: TextStyle(fontSize: 12, color: Colors.red.shade900),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton.icon(
              key: const Key('sales_pagination_retry_btn'),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
              onPressed: () =>
                  notifier.loadMoreSales(locationId: _effectiveLocationId()),
            ),
          ],
        ),
      );
    }

    if (!notifier.hasMoreSales) {
      return Container(
        key: const Key('sales_pagination_end'),
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        child: Text(
          'All records loaded ($displayedCount bills shown)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade500,
          ),
        ),
      );
    }

    return Container(
      key: const Key('sales_load_more_btn_container'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      alignment: Alignment.center,
      child: OutlinedButton.icon(
        key: const Key('sales_load_more_btn'),
        icon: const Icon(Icons.arrow_downward, size: 16),
        label: const Text('Load More Bills'),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          textStyle: const TextStyle(fontSize: 12),
        ),
        onPressed: () =>
            notifier.loadMoreSales(locationId: _effectiveLocationId()),
      ),
    );
  }

  Widget _buildBillCard(Sale sale) {
    final isJaipur = sale.locationId == LocationConstants.jaipurId;
    final storeName = isJaipur ? 'Jaipur Store' : 'Neemrana Store';
    final storeColor =
        isJaipur ? AppColors.roleJaipur : AppColors.roleNeemrana;

    final soldLocal = sale.soldAt.toLocal();
    final dateStr =
        '${soldLocal.day.toString().padLeft(2, '0')}/${soldLocal.month.toString().padLeft(2, '0')}/${soldLocal.year} ${soldLocal.hour.toString().padLeft(2, '0')}:${soldLocal.minute.toString().padLeft(2, '0')}';

    return KizunaCard(
      key: Key('bill_card_${sale.billNumber}'),
      padding: const EdgeInsets.all(14),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (ctx) => InvoicePreviewScreen(sale: sale),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Bill Number, Status, Store
          Row(
            children: [
              Text(
                sale.billNumber,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimaryLight,
                ),
              ),
              const SizedBox(width: 8),
              // Status Badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: sale.isCompleted
                      ? AppColors.success.withValues(alpha: 0.15)
                      : AppColors.error.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  sale.status,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: sale.isCompleted
                        ? AppColors.success
                        : AppColors.error,
                  ),
                ),
              ),
              const Spacer(),
              // Outlet Badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: storeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  storeName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: storeColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Customer and Date Details
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sale.customerName?.isNotEmpty == true
                          ? sale.customerName!
                          : 'Retail Customer',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (sale.customerPhone != null &&
                        sale.customerPhone!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        sale.customerPhone!,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                dateStr,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // Footer Row: Payment method, Amount, and Quick Actions
          Row(
            children: [
              // Payment Method Badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: sale.paymentMethod == 'UPI'
                      ? Colors.blue.shade50
                      : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: sale.paymentMethod == 'UPI'
                        ? Colors.blue.shade200
                        : Colors.green.shade200,
                  ),
                ),
                child: Text(
                  sale.paymentMethod,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: sale.paymentMethod == 'UPI'
                        ? Colors.blue.shade700
                        : Colors.green.shade700,
                  ),
                ),
              ),
              const Spacer(),

              // Amount
              Text(
                '₹${sale.totalAmount.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: sale.isCompleted
                      ? AppColors.primary
                      : Colors.grey.shade500,
                ),
              ),
              const SizedBox(width: 12),

              // Quick WhatsApp Share button
              IconButton(
                key: Key('share_whatsapp_${sale.billNumber}'),
                icon: const Icon(Icons.share_rounded, size: 20),
                color: const Color(0xFF25D366),
                tooltip: 'Send on WhatsApp',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _shareBillOnWhatsApp(sale),
              ),
              const SizedBox(width: 8),

              // View Invoice Arrow
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMutedLight,
                size: 20,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _shareBillOnWhatsApp(Sale sale) async {
    final notifier = InventoryProvider.maybeOf(context);
    final Map<String, Product> productMap = <String, Product>{
      for (final p in (notifier?.products ?? const <Product>[])) p.id: p,
    };

    final result = await PdfInvoiceService.sendBillOnWhatsApp(sale, productMap);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor:
            result.success ? const Color(0xFF1E7E34) : AppColors.warning,
      ),
    );
  }

  void _openNewSale(BuildContext context) {
    final notifier = InventoryProvider.maybeOf(context);
    if (notifier == null) return;

    final defaultLocation = widget.role == UserRole.neemrana
        ? LocationConstants.neemranaId
        : LocationConstants.jaipurId;

    GuidedNewSaleScreen.navigateTo(
      context,
      initialLocationId: defaultLocation,
      role: widget.role,
    );
  }
}
