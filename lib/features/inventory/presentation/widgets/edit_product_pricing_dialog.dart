import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../domain/entities/product.dart';
import '../controllers/inventory_notifier.dart';

/// Modal dialog for Owner to manage standard selling price and purchase cost of a product.
class EditProductPricingDialog extends StatefulWidget {
  final Product product;
  final InventoryNotifier notifier;

  const EditProductPricingDialog({
    super.key,
    required this.product,
    required this.notifier,
  });

  static Future<bool?> show(
    BuildContext context, {
    required Product product,
    required InventoryNotifier notifier,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => EditProductPricingDialog(
        product: product,
        notifier: notifier,
      ),
    );
  }

  @override
  State<EditProductPricingDialog> createState() =>
      _EditProductPricingDialogState();
}

class _EditProductPricingDialogState extends State<EditProductPricingDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _priceCtrl;
  late final TextEditingController _costCtrl;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController(
      text: widget.product.standardSellingPrice.toStringAsFixed(2),
    );
    _costCtrl = TextEditingController(
      text: widget.product.purchaseCost.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _costCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    final price = double.parse(_priceCtrl.text.trim());
    final cost = double.parse(_costCtrl.text.trim());

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final success = await widget.notifier.updateProductPricing(
      productId: widget.product.id,
      standardSellingPrice: price,
      purchaseCost: cost,
    );

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Updated ${widget.product.name} — Selling Price: ₹${price.toStringAsFixed(2)}, Cost: ₹${cost.toStringAsFixed(2)}',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage =
            widget.notifier.errorMessage ?? 'Failed to update product pricing.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.roleOwner.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.price_change_rounded,
                color: AppColors.roleOwner, size: 22),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Manage Product Pricing',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
              // Product details banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.product.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'SKU: ${widget.product.sku} • Size: ${widget.product.packageSize}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _errorMessage!,
                    style:
                        const TextStyle(color: AppColors.error, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Standard Selling Price (₹ per packet)
              TextFormField(
                key: const Key('edit_selling_price_field'),
                controller: _priceCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Standard Selling Price (₹ per packet) *',
                  helperText: 'Default price prefilled in POS for new sales',
                  prefixIcon: Icon(Icons.currency_rupee_rounded),
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter standard selling price';
                  }
                  final p = double.tryParse(val.trim());
                  if (p == null || p < 0) {
                    return 'Selling price must be non-negative (>= 0)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Purchase Cost (₹ per packet)
              TextFormField(
                key: const Key('edit_purchase_cost_field'),
                controller: _costCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Purchase Cost (₹ per packet) *',
                  helperText: 'Used for COGS and gross profit calculations',
                  prefixIcon: Icon(Icons.receipt_long_rounded),
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter purchase cost';
                  }
                  final c = double.tryParse(val.trim());
                  if (c == null || c < 0) {
                    return 'Purchase cost must be non-negative (>= 0)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              Text(
                'Note: Updating standard prices and costs does NOT modify historical sales or past bills. Historical gross profits are preserved.',
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade600,
                ),
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
          key: const Key('save_product_pricing_button'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.roleOwner,
            foregroundColor: Colors.white,
          ),
          onPressed: _isLoading ? null : _handleSubmit,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Save Pricing'),
        ),
      ],
    );
  }
}
