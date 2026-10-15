import 'package:flutter/material.dart';
import '../../../../app/providers/inventory_provider.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/widgets/kizuna_card.dart';
import '../../../inventory/domain/entities/product.dart';
import '../../../inventory/presentation/controllers/inventory_notifier.dart';

/// Predefined standard templates for dry fruits products.
/// The Owner can select any template to quickly prefill Name, Pack Size, and suggested SKU,
/// then specify the authorized selling price and purchase cost.
class DryFruitTemplate {
  final String name;
  final String packageSize;
  final String suggestedSku;

  const DryFruitTemplate({
    required this.name,
    required this.packageSize,
    required this.suggestedSku,
  });
}

const List<DryFruitTemplate> kDryFruitTemplates = [
  DryFruitTemplate(name: 'Almonds / Badam', packageSize: '250g', suggestedSku: 'KV-ALM-250'),
  DryFruitTemplate(name: 'Almonds / Badam', packageSize: '500g', suggestedSku: 'KV-ALM-500'),
  DryFruitTemplate(name: 'Almonds / Badam', packageSize: '1kg', suggestedSku: 'KV-ALM-1KG'),
  DryFruitTemplate(name: 'Kaju / Cashews', packageSize: '250g', suggestedSku: 'KV-KAJ-250'),
  DryFruitTemplate(name: 'Kaju / Cashews', packageSize: '500g', suggestedSku: 'KV-KAJ-500'),
  DryFruitTemplate(name: 'Pistachios / Pista', packageSize: '250g', suggestedSku: 'KV-PST-250'),
  DryFruitTemplate(name: 'Walnuts / Akhrot', packageSize: '250g', suggestedSku: 'KV-WAL-250'),
  DryFruitTemplate(name: 'Raisins / Kishmish', packageSize: '250g', suggestedSku: 'KV-RAI-250'),
  DryFruitTemplate(name: 'Raisins / Kishmish', packageSize: '500g', suggestedSku: 'KV-RAI-500'),
  DryFruitTemplate(name: 'Dates / Khajoor', packageSize: '500g', suggestedSku: 'KV-DATE-500'),
  DryFruitTemplate(name: 'Figs / Anjeer', packageSize: '250g', suggestedSku: 'KV-FIG-250'),
];

/// Owner-Only Product Master Screen:
/// Allows the authorized Owner to create, edit, activate, or deactivate products,
/// manage package sizes/SKUs, update pricing and purchase costs via server-side RPCs,
/// and quick-add dry fruit presets without deleting historical sales records.
class ProductMasterScreen extends StatefulWidget {
  final UserRole role;

  const ProductMasterScreen({
    super.key,
    required this.role,
  });

  @override
  State<ProductMasterScreen> createState() => _ProductMasterScreenState();
}

class _ProductMasterScreenState extends State<ProductMasterScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  int _selectedFilter = 0; // 0: All, 1: Active, 2: Inactive

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openAddEditDialog(BuildContext context, {Product? product, DryFruitTemplate? template}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _AddEditProductDialog(
        product: product,
        template: template,
        notifier: InventoryProvider.of(context),
      ),
    );
  }

  Future<void> _handleToggleActive(Product product) async {
    final notifier = InventoryProvider.of(context);
    final isDeactivating = product.active;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isDeactivating ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
              color: isDeactivating ? Colors.amber.shade800 : AppColors.success,
            ),
            const SizedBox(width: 8),
            Text(isDeactivating ? 'Deactivate Product?' : 'Reactivate Product?'),
          ],
        ),
        content: Text(
          isDeactivating
              ? 'Deactivating "${product.name} (${product.packageSize})" will hide it from New Sale and Stock In screens.\n\nAll historical sales and stock receipts remain 100% preserved.'
              : 'Reactivating "${product.name} (${product.packageSize})" will make it visible in New Sale and Stock In screens again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const Key('confirm_toggle_active_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDeactivating ? Colors.red.shade700 : AppColors.success,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(isDeactivating ? 'Deactivate' : 'Reactivate'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success = await notifier.toggleProductActive(
        id: product.id,
        active: !product.active,
      );
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isDeactivating
                    ? '${product.name} deactivated.'
                    : '${product.name} reactivated.',
              ),
              backgroundColor: AppColors.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(notifier.errorMessage ?? 'Failed to update product status.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.role != UserRole.owner) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Product Master'),
          backgroundColor: AppColors.roleOwner,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.gpp_bad_rounded, size: 64, color: Colors.red.shade400),
                const SizedBox(height: 16),
                const Text(
                  'Access Restricted',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Product Master management is restricted to authorized Owners.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final notifier = InventoryProvider.of(context);
    final allProducts = notifier.products;
    final summaries = notifier.inventorySummaries;

    final filteredProducts = allProducts.where((p) {
      if (_selectedFilter == 1 && !p.active) return false;
      if (_selectedFilter == 2 && p.active) return false;
      if (_searchQuery.isNotEmpty) {
        final matchName = p.name.toLowerCase().contains(_searchQuery);
        final matchSku = p.sku.toLowerCase().contains(_searchQuery);
        final matchPack = p.packageSize.toLowerCase().contains(_searchQuery);
        return matchName || matchSku || matchPack;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Product Master Catalog'),
        backgroundColor: AppColors.roleOwner,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Products',
            onPressed: () => notifier.loadInventoryData(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add_new_product_button'),
        backgroundColor: AppColors.roleOwner,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Product', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => _openAddEditDialog(context),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Quick-Add Dry Fruits Presets Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.amber.shade50,
              child: Row(
                children: [
                  Icon(Icons.inventory_2_rounded, size: 20, color: Colors.amber.shade900),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Quick Add Dry Fruits (Almonds, Kaju, Pista, etc.)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                  PopupMenuButton<DryFruitTemplate>(
                    key: const Key('quick_add_dry_fruits_button'),
                    tooltip: 'Choose dry fruit template',
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade700,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Presets',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Icon(Icons.arrow_drop_down, color: Colors.white, size: 18),
                        ],
                      ),
                    ),
                    onSelected: (template) {
                      _openAddEditDialog(context, template: template);
                    },
                    itemBuilder: (ctx) => kDryFruitTemplates.map((t) {
                      return PopupMenuItem<DryFruitTemplate>(
                        value: t,
                        child: Text('${t.name} (${t.packageSize}) — ${t.suggestedSku}'),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

            // Search and Status Filters
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Column(
                children: [
                  TextField(
                    key: const Key('product_master_search'),
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search products by name, SKU, or pack size...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () => _searchCtrl.clear(),
                            )
                          : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ChoiceChip(
                        key: const Key('filter_all'),
                        label: Text('All (${allProducts.length})'),
                        selected: _selectedFilter == 0,
                        selectedColor: AppColors.roleOwner,
                        labelStyle: TextStyle(
                          color: _selectedFilter == 0 ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        onSelected: (val) => setState(() => _selectedFilter = 0),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        key: const Key('filter_active'),
                        label: Text('Active (${allProducts.where((p) => p.active).length})'),
                        selected: _selectedFilter == 1,
                        selectedColor: AppColors.success,
                        labelStyle: TextStyle(
                          color: _selectedFilter == 1 ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        onSelected: (val) => setState(() => _selectedFilter = 1),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        key: const Key('filter_inactive'),
                        label: Text('Inactive (${allProducts.where((p) => !p.active).length})'),
                        selected: _selectedFilter == 2,
                        selectedColor: Colors.grey.shade700,
                        labelStyle: TextStyle(
                          color: _selectedFilter == 2 ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        onSelected: (val) => setState(() => _selectedFilter = 2),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Product List
            Expanded(
              child: filteredProducts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 56, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'No products match "$_searchQuery"'
                                : 'No products found.',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                      itemCount: filteredProducts.length,
                      itemBuilder: (context, index) {
                        final product = filteredProducts[index];
                        final summary = summaries.where((s) => s.product.id == product.id).firstOrNull;
                        final jaipurStock = summary?.jaipurFinishedStock ?? 0;
                        final neemranaStock = summary?.neemranaFinishedStock ?? 0;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: KizunaCard(
                            key: Key('product_card_${product.id}'),
                            padding: const EdgeInsets.all(14),
                            child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '${product.name} (${product.packageSize})',
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: product.active
                                                    ? AppColors.success.withValues(alpha: 0.12)
                                                    : Colors.grey.shade200,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                product.active ? 'ACTIVE' : 'INACTIVE',
                                                style: TextStyle(
                                                  color: product.active ? AppColors.success : Colors.grey.shade700,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.shade50,
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: Colors.blue.shade200),
                                              ),
                                              child: Text(
                                                'SKU: ${product.sku}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.blue.shade900,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Pack: ${product.packageSize}',
                                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              const Divider(height: 1),
                              const SizedBox(height: 8),

                              // Pricing & Stock Details
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Selling Price: ₹${product.standardSellingPrice.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                      Text(
                                        'Wholesale Cost: ₹${product.purchaseCost.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        'Jaipur Stock: $jaipurStock pkts',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: jaipurStock > 0 ? Colors.black87 : Colors.red.shade700,
                                        ),
                                      ),
                                      Text(
                                        'Neemrana Stock: $neemranaStock pkts',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),

                              // Actions
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  OutlinedButton.icon(
                                    key: Key('toggle_active_${product.id}'),
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      foregroundColor: product.active ? Colors.red.shade700 : AppColors.success,
                                    ),
                                    onPressed: () => _handleToggleActive(product),
                                    icon: Icon(
                                      product.active ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded,
                                      size: 16,
                                    ),
                                    label: Text(product.active ? 'Deactivate' : 'Reactivate'),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    key: Key('edit_product_${product.id}'),
                                    style: ElevatedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor: AppColors.roleOwner,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () => _openAddEditDialog(context, product: product),
                                    icon: const Icon(Icons.edit_rounded, size: 16),
                                    label: const Text('Edit Product'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog for Adding or Editing Product Master records
class _AddEditProductDialog extends StatefulWidget {
  final Product? product;
  final DryFruitTemplate? template;
  final InventoryNotifier notifier;

  const _AddEditProductDialog({
    this.product,
    this.template,
    required this.notifier,
  });

  @override
  State<_AddEditProductDialog> createState() => _AddEditProductDialogState();
}

class _AddEditProductDialogState extends State<_AddEditProductDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _packSizeCtrl;
  late final TextEditingController _skuCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _costCtrl;
  late bool _active;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    final t = widget.template;

    _nameCtrl = TextEditingController(text: p?.name ?? t?.name ?? '');
    _packSizeCtrl = TextEditingController(text: p?.packageSize ?? t?.packageSize ?? '250g');
    _skuCtrl = TextEditingController(text: p?.sku ?? t?.suggestedSku ?? '');
    _priceCtrl = TextEditingController(
      text: p != null ? p.standardSellingPrice.toStringAsFixed(2) : '',
    );
    _costCtrl = TextEditingController(
      text: p != null ? p.purchaseCost.toStringAsFixed(2) : '',
    );
    _active = p?.active ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _packSizeCtrl.dispose();
    _skuCtrl.dispose();
    _priceCtrl.dispose();
    _costCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameCtrl.text.trim();
    final packSize = _packSizeCtrl.text.trim();
    final sku = _skuCtrl.text.trim().toUpperCase();
    final price = double.parse(_priceCtrl.text.trim());
    final cost = double.parse(_costCtrl.text.trim());

    // Client-side duplicate SKU pre-check
    final isNew = widget.product == null;
    final otherProducts = widget.notifier.products.where((p) => isNew || p.id != widget.product!.id);
    if (otherProducts.any((p) => p.sku.toUpperCase() == sku)) {
      setState(() {
        _errorMessage = 'Product with SKU "$sku" already exists.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final bool success;
    if (isNew) {
      success = await widget.notifier.addProduct(
        name: name,
        packageSize: packSize,
        sku: sku,
        standardSellingPrice: price,
        purchaseCost: cost,
        active: _active,
      );
    } else {
      success = await widget.notifier.updateProduct(
        id: widget.product!.id,
        name: name,
        packageSize: packSize,
        sku: sku,
        standardSellingPrice: price,
        purchaseCost: cost,
        active: _active,
      );
    }

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isNew
                ? 'Product "$name ($packSize)" added to catalogue.'
                : 'Product "$name" updated successfully.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = widget.notifier.errorMessage ?? 'Failed to save product.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.product == null;

    return AlertDialog(
      title: Row(
        children: [
          Icon(isNew ? Icons.add_box_rounded : Icons.edit_note_rounded, color: AppColors.roleOwner),
          const SizedBox(width: 8),
          Text(isNew ? 'Add New Product' : 'Edit Product'),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Product Name
              TextFormField(
                key: const Key('product_form_name_field'),
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Product Name *',
                  hintText: 'e.g. Almonds / Badam, Kaju / Cashews',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Please enter product name.';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Package Size
              TextFormField(
                key: const Key('product_form_pack_size_field'),
                controller: _packSizeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Package Size / Selling Format *',
                  hintText: 'e.g. 100g, 250g, 500g, 1kg, 50ml',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Please enter pack size.';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // SKU
              TextFormField(
                key: const Key('product_form_sku_field'),
                controller: _skuCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Unique Product SKU *',
                  hintText: 'e.g. KV-ALM-250, KV-KAJ-250',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Please enter SKU.';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Standard Selling Price & Purchase Cost
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const Key('product_form_price_field'),
                      controller: _priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Selling Price (₹) *',
                        prefixText: '₹ ',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'Enter price';
                        final num = double.tryParse(val.trim());
                        if (num == null || num < 0) return 'Invalid price';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      key: const Key('product_form_cost_field'),
                      controller: _costCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Purchase Cost (₹) *',
                        prefixText: '₹ ',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'Enter cost';
                        final num = double.tryParse(val.trim());
                        if (num == null || num < 0) return 'Invalid cost';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Active Switch
              SwitchListTile(
                key: const Key('product_form_active_switch'),
                title: const Text('Active Status', style: TextStyle(fontSize: 14)),
                subtitle: Text(
                  _active ? 'Visible in POS Sale & Stock In' : 'Hidden from POS Sale & Stock In',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                value: _active,
                activeThumbColor: AppColors.success,
                contentPadding: EdgeInsets.zero,
                onChanged: (val) => setState(() => _active = val),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          key: const Key('product_form_submit_button'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.roleOwner,
            foregroundColor: Colors.white,
          ),
          onPressed: _isLoading ? null : _handleSubmit,
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(isNew ? 'Save Product' : 'Update Product'),
        ),
      ],
    );
  }
}
