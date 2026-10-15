import 'package:flutter/material.dart';
import '../../../../app/providers/inventory_provider.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../domain/entities/product.dart';

/// Auditable Store Stock Entry & Adjustment Dialog for Neemrana & Jaipur stores.
/// Allows operators and owners to record actual physical on-hand stock and corrections.
class StockInDialog extends StatefulWidget {
  final UserRole userRole;
  final String? initialLocationId;
  final Product? initialProduct;

  const StockInDialog({
    super.key,
    required this.userRole,
    this.initialLocationId,
    this.initialProduct,
  });

  static Future<bool?> show(
    BuildContext context, {
    required UserRole userRole,
    String? initialLocationId,
    Product? initialProduct,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => StockInDialog(
        userRole: userRole,
        initialLocationId: initialLocationId,
        initialProduct: initialProduct,
      ),
    );
  }

  @override
  State<StockInDialog> createState() => _StockInDialogState();
}

class _StockInDialogState extends State<StockInDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _notesController = TextEditingController();

  Product? _selectedProduct;
  late String _selectedLocationId;
  String _selectedReason = 'RESTOCK';
  bool _isDirectCountMode = false; // false = Receive Stock (+), true = Physical Shelf Audit (Overwrite)
  bool _isSubmitting = false;

  final Map<String, String> _reasons = {
    'RESTOCK': 'Direct Store Restock / Shipment Receipt',
    'PHYSICAL_AUDIT': 'Physical Audit / Shelf Count Correction',
    'OPENING_STOCK': 'Initial Physical Stock Entry',
    'CORRECTION': 'Inventory Correction',
    'DAMAGE_EXPIRY': 'Damaged / Expired Stock',
  };

  @override
  void initState() {
    super.initState();
    _selectedProduct = widget.initialProduct;
    if (widget.userRole == UserRole.neemrana) {
      _selectedLocationId = LocationConstants.neemranaId;
    } else if (widget.userRole == UserRole.jaipur) {
      _selectedLocationId = LocationConstants.jaipurId;
    } else {
      _selectedLocationId = widget.initialLocationId ?? LocationConstants.neemranaId;
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  int _getCurrentStock() {
    if (_selectedProduct == null) return 0;
    final inventoryNotifier = InventoryProvider.of(context);
    final summary = inventoryNotifier.inventorySummaries
        .where((s) => s.product.id == _selectedProduct!.id)
        .firstOrNull;
    if (summary == null) return 0;

    return _selectedLocationId == LocationConstants.neemranaId
        ? summary.neemranaFinishedStock
        : summary.jaipurFinishedStock;
  }

  int? _calculateNewQuantity() {
    final inputVal = int.tryParse(_quantityController.text.trim());
    if (inputVal == null) return null;

    if (_isDirectCountMode) {
      return inputVal >= 0 ? inputVal : null;
    } else {
      final current = _getCurrentStock();
      final target = current + inputVal;
      return target >= 0 ? target : null;
    }
  }

  Future<void> _submitAdjustment() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a product.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final inputVal = int.tryParse(_quantityController.text.trim());
    if (inputVal == null || (!_isDirectCountMode && inputVal <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid positive quantity.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final newQuantity = _calculateNewQuantity();
    if (newQuantity == null || newQuantity < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid quantity: Resulting stock cannot be negative.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final inventoryNotifier = InventoryProvider.of(context);
    final storeName = _selectedLocationId == LocationConstants.neemranaId
        ? 'Neemrana'
        : 'Jaipur';
    final notes = _notesController.text.trim().isNotEmpty
        ? _notesController.text.trim()
        : null;

    final bool success;
    if (!_isDirectCountMode) {
      // Safe additive stock receipt
      success = await inventoryNotifier.receiveStoreStock(
        locationId: _selectedLocationId,
        productId: _selectedProduct!.id,
        quantity: inputVal,
        notes: notes,
      );
    } else {
      // Physical shelf count adjustment (absolute overwrite)
      success = await inventoryNotifier.adjustStoreStock(
        locationId: _selectedLocationId,
        productId: _selectedProduct!.id,
        newQuantity: newQuantity,
        reason: _selectedReason,
        notes: notes,
      );
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (success) {
      final message = !_isDirectCountMode
          ? 'Stock received: +$inputVal packets of ${_selectedProduct!.name} added at $storeName.'
          : 'Stock updated: ${_selectedProduct!.name} set to $newQuantity packets at $storeName.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.of(context).pop(true);
    } else {
      final error = inventoryNotifier.errorMessage ?? 'Failed to update store stock.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final inventoryNotifier = InventoryProvider.of(context);
    final products = inventoryNotifier.products;
    final currentStock = _getCurrentStock();
    final newStock = _calculateNewQuantity();

    final primaryColor = widget.userRole == UserRole.neemrana
        ? AppColors.roleNeemrana
        : widget.userRole == UserRole.jaipur
            ? AppColors.roleJaipur
            : AppColors.roleOwner;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.tune_rounded, color: primaryColor),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stock Entry & Adjustment',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
                Text(
                  'Independent Store Physical Count',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondaryLight,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Store Location Selection
              if (widget.userRole == UserRole.owner) ...[
                const Text(
                  'Target Store Location',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _selectedLocationId,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.storefront_rounded),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: LocationConstants.neemranaId,
                      child: Text('Neemrana Store'),
                    ),
                    DropdownMenuItem(
                      value: LocationConstants.jaipurId,
                      child: Text('Jaipur Store'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedLocationId = val);
                  },
                ),
                const SizedBox(height: 14),
              ] else ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.storefront_rounded, color: primaryColor, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Store: ${widget.userRole == UserRole.neemrana ? "Neemrana Store" : "Jaipur Store"}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Product Selection Dropdown
              const Text(
                'Select Product / SKU',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<Product>(
                key: const Key('stock_in_product_dropdown'),
                initialValue: _selectedProduct,
                isExpanded: true,
                hint: const Text('Choose product...'),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.inventory_2_rounded),
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                items: products.where((product) => product.active).map((product) {
                  return DropdownMenuItem<Product>(
                    value: product,
                    child: Text(
                      '${product.name} (${product.packageSize})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (product) {
                  setState(() => _selectedProduct = product);
                },
                validator: (val) => val == null ? 'Please select a product' : null,
              ),
              const SizedBox(height: 14),

              // Current Stock Display Card
              if (_selectedProduct != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Current Stock On Hand:',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$currentStock packets',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Entry Mode Switcher
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      avatar: const Icon(Icons.add_box_rounded, size: 16),
                      label: const Text('Receive Stock (+)'),
                      selected: !_isDirectCountMode,
                      onSelected: (selected) {
                        if (selected) setState(() => _isDirectCountMode = false);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      avatar: const Icon(Icons.fact_check_rounded, size: 16),
                      label: const Text('Physical Audit'),
                      selected: _isDirectCountMode,
                      onSelected: (selected) {
                        if (selected) setState(() => _isDirectCountMode = true);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Quantity Input Field
              Text(
                !_isDirectCountMode
                    ? 'Received Quantity to Add (+) *'
                    : 'Actual Physical Shelf Count (Overwrite) *',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 6),
              TextFormField(
                key: const Key('stock_in_quantity_field'),
                controller: _quantityController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  prefixIcon: Icon(!_isDirectCountMode
                      ? Icons.add_circle_outline_rounded
                      : Icons.edit_note_rounded),
                  hintText: !_isDirectCountMode ? 'e.g. 20' : 'e.g. 50',
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onChanged: (_) => setState(() {}),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Enter quantity';
                  final numVal = int.tryParse(val.trim());
                  if (numVal == null) return 'Enter a valid number';
                  if (!_isDirectCountMode && numVal <= 0) {
                    return 'Received quantity must be greater than zero';
                  }
                  if (_isDirectCountMode && numVal < 0) {
                    return 'Shelf count cannot be negative';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Dynamic Preview of New Stock & Adjustment
              if (newStock != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'New Stock: $newStock packets',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.success,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        'Change: ${newStock - currentStock >= 0 ? "+" : ""}${newStock - currentStock}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: (newStock - currentStock) >= 0
                              ? AppColors.success
                              : AppColors.error,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Reason Dropdown
              const Text(
                'Adjustment Reason *',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _selectedReason,
                isExpanded: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.assignment_turned_in_rounded),
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                items: _reasons.entries.map((e) {
                  return DropdownMenuItem<String>(
                    value: e.key,
                    child: Text(e.value, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedReason = val);
                },
              ),
              const SizedBox(height: 14),

              // Notes Input
              const Text(
                'Notes / Audit Reference (Optional)',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.note_rounded),
                  hintText: 'e.g. Shelf recount, received fresh supply',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          key: const Key('stock_in_submit_button'),
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
          ),
          onPressed: _isSubmitting ? null : _submitAdjustment,
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Save Stock'),
        ),
      ],
    );
  }
}
