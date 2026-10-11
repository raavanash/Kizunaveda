import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/pdf_invoice_service.dart';
import '../../../jaipur/presentation/screens/invoice_preview_screen.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/sale.dart';
import '../controllers/inventory_notifier.dart';

/// Reusable modal dialog to record a POS Sale with unified WhatsApp sharing,
/// independent outlet stock deduction, and safe failure recovery.
class RecordPosSaleDialog extends StatefulWidget {
  final String targetLocationId;
  final String locationName;
  final InventoryNotifier notifier;
  final VoidCallback? onSaleCompleted;
  final Future<bool> Function(Uri uri)? customLauncher;
  final Future<void> Function(List<XFile> files, {String? text})? customSharer;
  final Future<Directory> Function()? customTempDir;

  const RecordPosSaleDialog({
    super.key,
    required this.targetLocationId,
    required this.locationName,
    required this.notifier,
    this.onSaleCompleted,
    this.customLauncher,
    this.customSharer,
    this.customTempDir,
  });

  static Future<Sale?> show(
    BuildContext context, {
    required String targetLocationId,
    required String locationName,
    required InventoryNotifier notifier,
    VoidCallback? onSaleCompleted,
    Future<bool> Function(Uri uri)? customLauncher,
    Future<void> Function(List<XFile> files, {String? text})? customSharer,
    Future<Directory> Function()? customTempDir,
  }) {
    return showDialog<Sale>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => RecordPosSaleDialog(
        targetLocationId: targetLocationId,
        locationName: locationName,
        notifier: notifier,
        onSaleCompleted: onSaleCompleted,
        customLauncher: customLauncher,
        customSharer: customSharer,
        customTempDir: customTempDir,
      ),
    );
  }

  @override
  State<RecordPosSaleDialog> createState() => _RecordPosSaleDialogState();
}

class _RecordPosSaleDialogState extends State<RecordPosSaleDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _unitPriceCtrl = TextEditingController(text: '100');

  Product? _selectedProduct;
  String _paymentMethod = 'CASH';
  String _invoiceType = 'NON_GST'; // Default Without GST
  double _gstRate = AppConfig.defaultGstRate;

  bool _isSubmitting = false;
  String? _dialogError;

  // Post-sale completion state
  Sale? _completedSale;
  WhatsAppResult? _whatsAppResult;
  bool _isRetryingWhatsApp = false;

  @override
  void initState() {
    super.initState();
    if (widget.notifier.products.isNotEmpty) {
      _selectedProduct = widget.notifier.products.first;
      _unitPriceCtrl.text =
          _selectedProduct!.standardSellingPrice.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _qtyCtrl.dispose();
    _unitPriceCtrl.dispose();
    super.dispose();
  }

  double get _subtotal {
    final qty = int.tryParse(_qtyCtrl.text) ?? 0;
    final price = double.tryParse(_unitPriceCtrl.text) ?? 0.0;
    return qty * price;
  }

  double get _cgst {
    if (_invoiceType != 'GST') return 0.0;
    return (_subtotal * (_gstRate / 2.0) / 100.0);
  }

  double get _sgst {
    if (_invoiceType != 'GST') return 0.0;
    return (_subtotal * (_gstRate / 2.0) / 100.0);
  }

  double get _totalAmount {
    if (_invoiceType == 'GST') {
      return _subtotal + _cgst + _sgst;
    }
    return _subtotal;
  }

  Future<void> _handleCompleteSaleAndSendWhatsApp() async {
    // 1. Guard against double submission
    if (_isSubmitting || _completedSale != null) return;

    if (!(_formKey.currentState?.validate() ?? false) || _selectedProduct == null) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _dialogError = null;
    });

    try {
      // 2. Persist sale through existing secure Supabase RPC
      final createdSale = await widget.notifier.recordSale(
        productId: _selectedProduct!.id,
        quantity: int.parse(_qtyCtrl.text),
        customerName: _nameCtrl.text.trim(),
        customerPhone: _phoneCtrl.text.trim(),
        paymentMethod: _paymentMethod,
        targetLocationId: widget.targetLocationId,
        invoiceType: _invoiceType,
        gstRate: _invoiceType == 'GST' ? _gstRate : 0.0,
        taxableAmount: _subtotal,
        cgstAmount: _cgst,
        sgstAmount: _sgst,
        igstAmount: 0.0,
        totalAmount: _totalAmount,
        unitPrice: double.tryParse(_unitPriceCtrl.text) ?? 0.0,
      );

      if (!mounted) return;

      if (createdSale == null) {
        // Sale creation failed: stock was NOT deducted, do NOT launch WhatsApp
        setState(() {
          _isSubmitting = false;
          _dialogError = widget.notifier.errorMessage ?? 'Failed to record sale.';
        });
        return;
      }

      // 3. Sale is committed! Stock deducted exactly once from this outlet.
      setState(() {
        _completedSale = createdSale;
      });

      widget.onSaleCompleted?.call();

      // 4. Immediately trigger WhatsApp sharing for customer's phone
      await _dispatchWhatsApp(createdSale);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _dialogError = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  Future<void> _dispatchWhatsApp(Sale sale) async {
    final productMap = {
      for (final p in widget.notifier.products) p.id: p,
    };

    try {
      final result = await PdfInvoiceService.sendBillOnWhatsApp(
        sale,
        productMap,
        widget.customLauncher,
        widget.customSharer,
        widget.customTempDir,
      );

      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _isRetryingWhatsApp = false;
          _whatsAppResult = result;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _isRetryingWhatsApp = false;
          _whatsAppResult = WhatsAppResult(
            success: false,
            launchedDirectly: false,
            fallbackToShare: true,
            normalizedPhone: sale.customerPhone,
            message: 'WhatsApp launch failed: $e',
          );
        });
      }
    }
  }

  Future<void> _handleRetryWhatsApp() async {
    if (_completedSale == null || _isRetryingWhatsApp) return;
    setState(() {
      _isRetryingWhatsApp = true;
    });
    // Resend WhatsApp for existing persisted sale; never recreates sale!
    await _dispatchWhatsApp(_completedSale!);
  }

  @override
  Widget build(BuildContext context) {
    if (_completedSale != null) {
      return _buildCompletionDialog(context);
    }
    return _buildPosFormDialog(context);
  }

  Widget _buildPosFormDialog(BuildContext context) {
    final isGstConfigured = AppConfig.isGstConfigured;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.point_of_sale_rounded,
            color: widget.targetLocationId == LocationConstants.neemranaId
                ? AppColors.roleNeemrana
                : AppColors.roleJaipur,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create Bill (${widget.locationName})',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Complete Sale & Instant WhatsApp Invoice',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_dialogError != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: AppColors.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _dialogError!,
                          style: const TextStyle(
                              color: AppColors.error, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Customer Details
              TextFormField(
                key: const Key('customer_name_field'),
                controller: _nameCtrl,
                enabled: !_isSubmitting,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Customer Name *',
                  hintText: 'e.g. Rahul Sharma',
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Customer name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                key: const Key('customer_phone_field'),
                controller: _phoneCtrl,
                enabled: !_isSubmitting,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Customer WhatsApp Number *',
                  hintText: 'e.g. 9876543210',
                  prefixIcon: Icon(Icons.phone_android_rounded, size: 20),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Customer phone is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),

              // Product & Pricing
              DropdownButtonFormField<Product>(
                key: const Key('product_select_dropdown'),
                initialValue: _selectedProduct,
                decoration: const InputDecoration(labelText: 'Select Product *'),
                items: widget.notifier.products
                    .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text('${p.name} (${p.packageSize})'),
                        ))
                    .toList(),
                onChanged: _isSubmitting
                    ? null
                    : (val) {
                        setState(() {
                          _selectedProduct = val;
                          if (val != null) {
                            _unitPriceCtrl.text =
                                val.standardSellingPrice.toStringAsFixed(2);
                          }
                        });
                      },
                validator: (val) => val == null ? 'Select a product' : null,
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const Key('quantity_field'),
                      controller: _qtyCtrl,
                      enabled: !_isSubmitting,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Qty *',
                        hintText: 'e.g. 2',
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (val) {
                        final qty = int.tryParse(val ?? '');
                        if (qty == null || qty <= 0) {
                          return 'Enter qty > 0';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      key: const Key('unit_price_field'),
                      controller: _unitPriceCtrl,
                      enabled: !_isSubmitting,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Unit Price (₹) *',
                        hintText: 'e.g. 150',
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (val) {
                        final price = double.tryParse(val ?? '');
                        if (price == null || price < 0) {
                          return 'Enter price >= 0';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // GST / Without GST Mode Selection
              const Text(
                'Invoice Type *',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondaryLight,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  ChoiceChip(
                    key: const Key('invoice_type_nongst_chip'),
                    label: const Text('Without GST'),
                    selected: _invoiceType == 'NON_GST',
                    selectedColor: AppColors.primary.withValues(alpha: 0.2),
                    onSelected: _isSubmitting
                        ? null
                        : (selected) {
                            if (selected) {
                              setState(() {
                                _invoiceType = 'NON_GST';
                              });
                            }
                          },
                  ),
                  const SizedBox(width: 10),
                  ChoiceChip(
                    key: const Key('invoice_type_gst_chip'),
                    label: const Text('With GST'),
                    selected: _invoiceType == 'GST',
                    disabledColor: Colors.grey.shade200,
                    selectedColor: AppColors.success.withValues(alpha: 0.2),
                    onSelected: !_isSubmitting && isGstConfigured
                        ? (selected) {
                            if (selected) {
                              setState(() {
                                _invoiceType = 'GST';
                              });
                            }
                          }
                        : null,
                  ),
                ],
              ),

              if (!isGstConfigured) ...[
                const SizedBox(height: 4),
                const Text(
                  'Note: GST toggle disabled until GSTIN configuration is completed.',
                  style: TextStyle(fontSize: 11, color: AppColors.warning),
                ),
              ],

              if (_invoiceType == 'GST') ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('GST Rate: ',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    DropdownButton<double>(
                      value: _gstRate,
                      items: const [
                        DropdownMenuItem(value: 5.0, child: Text('5%')),
                        DropdownMenuItem(value: 12.0, child: Text('12%')),
                        DropdownMenuItem(value: 18.0, child: Text('18%')),
                        DropdownMenuItem(value: 28.0, child: Text('28%')),
                      ],
                      onChanged: _isSubmitting
                          ? null
                          : (val) {
                              if (val != null) {
                                setState(() => _gstRate = val);
                              }
                            },
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 14),

              // Payment Method Selection
              const Text(
                'Payment Method *',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondaryLight,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  ChoiceChip(
                    key: const Key('payment_cash_chip'),
                    label: const Text('Cash'),
                    selected: _paymentMethod == 'CASH',
                    selectedColor: AppColors.roleJaipur.withValues(alpha: 0.2),
                    onSelected: _isSubmitting
                        ? null
                        : (selected) {
                            if (selected) {
                              setState(() => _paymentMethod = 'CASH');
                            }
                          },
                  ),
                  const SizedBox(width: 10),
                  ChoiceChip(
                    key: const Key('payment_upi_chip'),
                    label: const Text('UPI'),
                    selected: _paymentMethod == 'UPI',
                    selectedColor: AppColors.roleJaipur.withValues(alpha: 0.2),
                    onSelected: _isSubmitting
                        ? null
                        : (selected) {
                            if (selected) {
                              setState(() => _paymentMethod = 'UPI');
                            }
                          },
                  ),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              // Live Invoice Summary
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.backgroundLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.cardBorderLight),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Subtotal:',
                            style: TextStyle(
                                fontSize: 13, color: AppColors.textSecondaryLight)),
                        Text('₹${_subtotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    if (_invoiceType == 'GST') ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('CGST (${(_gstRate / 2).toStringAsFixed(1)}%):',
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.textSecondaryLight)),
                          Text('₹${_cgst.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('SGST (${(_gstRate / 2).toStringAsFixed(1)}%):',
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.textSecondaryLight)),
                          Text('₹${_sgst.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ],
                    const Divider(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Payable:',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '₹${_totalAmount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        KeyedSubtree(
          key: const Key('submit_sale_button'),
          child: ElevatedButton.icon(
            key: const Key('complete_sale_send_whatsapp_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            icon: _isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_rounded, size: 16),
            label: Text(_isSubmitting ? 'Processing...' : 'Complete Sale & Send WhatsApp'),
            onPressed: _isSubmitting ? null : _handleCompleteSaleAndSendWhatsApp,
          ),
        ),
      ],
    );
  }

  Widget _buildCompletionDialog(BuildContext context) {
    final sale = _completedSale!;
    final wa = _whatsAppResult;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: AppColors.success,
            size: 28,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sale Completed!',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.success,
                  ),
                ),
                Text(
                  '${sale.billNumber} • ${widget.locationName}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Bill Details Card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.cardBorderLight),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Bill Number:',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondaryLight)),
                      Text(sale.billNumber,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Customer:',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondaryLight)),
                      Text('${sale.customerName ?? "Customer"} (${sale.customerPhone ?? ""})',
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Amount:',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondaryLight)),
                      Text('₹${sale.totalAmount.toStringAsFixed(2)} (${sale.paymentMethod})',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // WhatsApp Handoff Status Card
            if (wa != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: wa.success
                      ? const Color(0xFF25D366).withValues(alpha: 0.12)
                      : AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: wa.success
                        ? const Color(0xFF25D366)
                        : AppColors.warning,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      wa.success
                          ? Icons.mark_chat_read_rounded
                          : Icons.info_outline_rounded,
                      color: wa.success
                          ? const Color(0xFF1E7E34)
                          : AppColors.warning,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            wa.success
                                ? 'WhatsApp Handoff Successful'
                                : 'WhatsApp Handoff Notice',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: wa.success
                                  ? const Color(0xFF1E7E34)
                                  : AppColors.warning,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            wa.message,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (_isSubmitting) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: Color(0xFF25D366)),
                      SizedBox(height: 8),
                      Text('Preparing invoice & opening WhatsApp...',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondaryLight)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        OutlinedButton.icon(
          key: const Key('retry_whatsapp_button'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF128C7E),
            side: const BorderSide(color: Color(0xFF25D366)),
          ),
          icon: _isRetryingWhatsApp
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF25D366)),
                )
              : const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Retry WhatsApp'),
          onPressed: _isRetryingWhatsApp ? null : _handleRetryWhatsApp,
        ),
        OutlinedButton.icon(
          key: const Key('view_invoice_button'),
          icon: const Icon(Icons.receipt_long_rounded, size: 16),
          label: const Text('View / Print Bill'),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => InvoicePreviewScreen(sale: sale),
              ),
            );
          },
        ),
        ElevatedButton(
          key: const Key('done_button'),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.roleJaipur),
          onPressed: () => Navigator.pop(context, sale),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
