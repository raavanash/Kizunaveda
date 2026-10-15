import 'package:flutter/material.dart';
import '../../../../app/providers/inventory_provider.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/pdf_invoice_service.dart';
import '../../../../core/widgets/kizuna_card.dart';
import '../../../inventory/domain/entities/product.dart';
import '../../../inventory/domain/entities/sale.dart';
import '../../../inventory/presentation/controllers/inventory_notifier.dart';
import '../../../jaipur/presentation/screens/invoice_preview_screen.dart';
import '../../../../core/utils/id_generator.dart';
import '../../domain/entities/cart_item.dart';

/// Single, Guided New Sale Workflow inspired by Vyapar:
/// Multi-step staged workflow with visible step progress:
/// 1. Products & Quantities
/// 2. Customer & Payment
/// 3. Review Bill & Complete Sale & Send WhatsApp
/// Eliminates back-and-forth navigation, preserves state across steps,
/// and handles failure gracefully without recreating sales.
class GuidedNewSaleScreen extends StatefulWidget {
  final String initialLocationId;
  final UserRole role;

  const GuidedNewSaleScreen({
    super.key,
    required this.initialLocationId,
    required this.role,
  });

  static Future<Sale?> navigateTo(
    BuildContext context, {
    required String initialLocationId,
    required UserRole role,
  }) {
    return Navigator.push<Sale>(
      context,
      MaterialPageRoute(
        builder: (_) => GuidedNewSaleScreen(
          initialLocationId: initialLocationId,
          role: role,
        ),
      ),
    );
  }

  @override
  State<GuidedNewSaleScreen> createState() => _GuidedNewSaleScreenState();
}

class _GuidedNewSaleScreenState extends State<GuidedNewSaleScreen> {
  int _currentStep = 0; // 0 = Products, 1 = Customer & Payment, 2 = Review, 3 = Completed

  late String _selectedLocationId;
  Product? _selectedProduct;
  final TextEditingController _qtyCtrl = TextEditingController(text: '1');
  final TextEditingController _priceCtrl = TextEditingController();
  final TextEditingController _discountCtrl = TextEditingController(text: '0');
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  String _paymentMethod = 'CASH';
  bool _hasUserEditedPrice = false;

  final List<CartItem> _additionalCartItems = [];
  String? _clientRequestId;

  bool _isSubmitting = false;
  String? _errorMessage;
  Sale? _completedSale;
  WhatsAppResult? _whatsAppResult;
  bool _isRetryingWhatsApp = false;

  final _step1FormKey = GlobalKey<FormState>();
  final _step2FormKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _selectedLocationId = widget.initialLocationId;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifier = InventoryProvider.maybeOf(context);
    final activeProducts =
        notifier?.products.where((p) => p.active).toList() ?? [];
    if (_selectedProduct == null && activeProducts.isNotEmpty) {
      _selectedProduct = activeProducts.first;
      if (!_hasUserEditedPrice && _priceCtrl.text.isEmpty) {
        _priceCtrl.text =
            _selectedProduct!.standardSellingPrice.toStringAsFixed(2);
      }
    } else if (_selectedProduct != null &&
        _priceCtrl.text.isEmpty &&
        !_hasUserEditedPrice) {
      _priceCtrl.text =
          _selectedProduct!.standardSellingPrice.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    _discountCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  int get _quantity => int.tryParse(_qtyCtrl.text.trim()) ?? 0;

  double get _unitPrice {
    final parsed = double.tryParse(_priceCtrl.text.trim());
    if (parsed != null && parsed >= 0) {
      return parsed;
    }
    return _selectedProduct?.standardSellingPrice ?? 100.0;
  }

  double get _discount {
    final parsed = double.tryParse(_discountCtrl.text.trim());
    if (parsed != null && parsed >= 0) {
      return parsed;
    }
    return 0.0;
  }

  double get _currentLineTotal {
    final gross = _quantity * _unitPrice;
    final total = gross - _discount;
    return total > 0 ? total : 0.0;
  }

  double get _totalAmount {
    if (_additionalCartItems.isNotEmpty) {
      final total = _additionalCartItems.fold<double>(
          0.0, (acc, item) => acc + item.lineTotal);
      return total > 0 ? total : 0.0;
    }
    return _currentLineTotal;
  }

  List<CartItem> get _allCartItems {
    if (_additionalCartItems.isNotEmpty) {
      return List<CartItem>.unmodifiable(_additionalCartItems);
    }
    if (_selectedProduct != null && _quantity > 0) {
      return [
        CartItem(
          product: _selectedProduct!,
          quantity: _quantity,
          unitPrice: _unitPrice,
          discount: _discount,
        ),
      ];
    }
    return const [];
  }

  bool get _isPriceOverridden {
    if (_selectedProduct == null) return false;
    return (_unitPrice - _selectedProduct!.standardSellingPrice).abs() > 0.001;
  }

  int _getAvailableStock(InventoryNotifier notifier) {
    if (_selectedProduct == null) return 0;
    final summary = notifier.inventorySummaries
        .where((s) => s.product.id == _selectedProduct!.id)
        .firstOrNull;
    if (summary == null) return 0;

    return _selectedLocationId == LocationConstants.neemranaId
        ? summary.neemranaFinishedStock
        : summary.jaipurFinishedStock;
  }

  void _addCurrentProductToCart() {
    if (_selectedProduct == null) return;
    if (!_step1FormKey.currentState!.validate()) return;
    if (_quantity <= 0) {
      setState(() => _errorMessage = 'Quantity must be greater than zero.');
      return;
    }
    if (!_unitPrice.isFinite || _unitPrice.isNaN || _unitPrice <= 0) {
      setState(() =>
          _errorMessage = 'Selling price must be greater than zero (₹ > 0).');
      return;
    }
    if (!_discount.isFinite || _discount.isNaN || _discount < 0) {
      setState(() => _errorMessage = 'Discount cannot be negative.');
      return;
    }
    if (_discount > (_quantity * _unitPrice)) {
      setState(() => _errorMessage =
          'Discount cannot exceed subtotal (₹${(_quantity * _unitPrice).toStringAsFixed(2)}).');
      return;
    }

    // Cashier Authorization Guard
    if (widget.role != UserRole.owner) {
      if (_isPriceOverridden) {
        setState(() => _errorMessage =
            'Unauthorized price change: Cashiers cannot modify catalog price (₹${_selectedProduct!.standardSellingPrice.toStringAsFixed(2)}). Owner authorization required.');
        return;
      }
      final gross = _quantity * _unitPrice;
      if (_discount > 0 && gross > 0) {
        final pct = (_discount / gross) * 100.0;
        if (double.parse(pct.toStringAsFixed(4)) > 10.00) {
          setState(() => _errorMessage =
              'Unauthorized discount: Cashier discount exceeds allowed maximum of 10%. Owner authorization required.');
          return;
        }
      }
    }

    final notifier = InventoryProvider.maybeOf(context);
    final available = notifier != null ? _getAvailableStock(notifier) : 0;
    final existingIndex = _additionalCartItems
        .indexWhere((item) => item.product.id == _selectedProduct!.id);
    final currentQtyInCart = existingIndex != -1
        ? _additionalCartItems[existingIndex].quantity
        : 0;

    if (notifier != null && (currentQtyInCart + _quantity) > available) {
      setState(() => _errorMessage =
          'Cannot add $_quantity pkts of ${_selectedProduct!.name}. '
          '${currentQtyInCart > 0 ? "Cart already has $currentQtyInCart pkts. " : ""}'
          'Only $available pkts available in stock.');
      return;
    }

    if (existingIndex != -1 && widget.role != UserRole.owner) {
      final existingItem = _additionalCartItems[existingIndex];
      final combinedQty = existingItem.quantity + _quantity;
      final combinedDiscount = existingItem.discount + _discount;
      final combinedGross = combinedQty * _unitPrice;
      if (combinedGross > 0 && combinedDiscount > 0) {
        final pct = (combinedDiscount / combinedGross) * 100.0;
        if (double.parse(pct.toStringAsFixed(4)) > 10.00) {
          setState(() => _errorMessage =
              'Unauthorized discount: Combined cashier discount exceeds allowed maximum of 10%. Owner authorization required.');
          return;
        }
      }
    }

    setState(() {
      if (existingIndex != -1) {
        final existingItem = _additionalCartItems[existingIndex];
        _additionalCartItems[existingIndex] = CartItem(
          product: _selectedProduct!,
          quantity: existingItem.quantity + _quantity,
          unitPrice: _unitPrice,
          discount: existingItem.discount + _discount,
        );
      } else {
        _additionalCartItems.add(CartItem(
          product: _selectedProduct!,
          quantity: _quantity,
          unitPrice: _unitPrice,
          discount: _discount,
        ));
      }

      // Advance product dropdown to next remaining product if any
      final products =
          notifier?.products.where((p) => p.active).toList() ?? [];
      final remaining = products
          .where((p) =>
              !_additionalCartItems.any((item) => item.product.id == p.id))
          .toList();
      final remainingWithStock = remaining.where((p) {
        final summary = notifier?.inventorySummaries
            .where((s) => s.product.id == p.id)
            .firstOrNull;
        final available = summary == null
            ? 0
            : (_selectedLocationId == LocationConstants.neemranaId
                ? summary.neemranaFinishedStock
                : summary.jaipurFinishedStock);
        return available > 0;
      }).toList();
      if (remainingWithStock.isNotEmpty) {
        _selectedProduct = remainingWithStock.first;
      } else if (remaining.isNotEmpty) {
        _selectedProduct = remaining.first;
      }
      _qtyCtrl.text = '1';
      if (_selectedProduct != null) {
        _priceCtrl.text =
            _selectedProduct!.standardSellingPrice.toStringAsFixed(2);
      }
      _discountCtrl.text = '0';
      _hasUserEditedPrice = false;
      _errorMessage = null;
    });
  }

  void _removeCartItem(int index) {
    setState(() {
      _additionalCartItems.removeAt(index);
      _errorMessage = null;
    });
  }

  void _nextStep() {
    FocusScope.of(context).unfocus();
    setState(() => _errorMessage = null);
    if (_currentStep == 0) {
      final notifier = InventoryProvider.maybeOf(context);
      if (_additionalCartItems.isEmpty) {
        if (_selectedProduct == null) {
          setState(() => _errorMessage = 'Please select a product.');
          return;
        }
        if (!_step1FormKey.currentState!.validate()) {
          setState(() => _errorMessage =
              'Please enter a valid quantity, selling price, and discount.');
          return;
        }
        if (_quantity <= 0) {
          setState(() =>
              _errorMessage = 'Quantity must be greater than zero.');
          return;
        }
        if (!_unitPrice.isFinite || _unitPrice.isNaN || _unitPrice <= 0) {
          setState(() =>
              _errorMessage = 'Selling price must be greater than zero (₹ > 0).');
          return;
        }
        if (!_discount.isFinite || _discount.isNaN || _discount < 0) {
          setState(() => _errorMessage = 'Discount cannot be negative.');
          return;
        }
        if (_discount > (_quantity * _unitPrice)) {
          setState(() => _errorMessage =
              'Discount cannot exceed subtotal (₹${(_quantity * _unitPrice).toStringAsFixed(2)}).');
          return;
        }

        // Cashier Authorization Guard
        if (widget.role != UserRole.owner) {
          if (_isPriceOverridden) {
            setState(() => _errorMessage =
                'Unauthorized price change: Cashiers cannot modify catalog price (₹${_selectedProduct!.standardSellingPrice.toStringAsFixed(2)}). Owner authorization required.');
            return;
          }
          final gross = _quantity * _unitPrice;
          if (_discount > 0 && gross > 0) {
            final pct = (_discount / gross) * 100.0;
            if (double.parse(pct.toStringAsFixed(4)) > 10.00) {
              setState(() => _errorMessage =
                  'Unauthorized discount: Cashier discount exceeds allowed maximum of 10%. Owner authorization required.');
              return;
            }
          }
        }

        if (notifier != null) {
          final available = _getAvailableStock(notifier);
          if (_quantity > available) {
            setState(() => _errorMessage =
                'Cannot sell $_quantity pkts. Only $available pkts available in stock.');
            return;
          }
        }
      } else {
        // Multi-item cart checkout validation: validate every product's stock & cashier discount at selected outlet
        if (widget.role != UserRole.owner) {
          for (final item in _additionalCartItems) {
            if (item.isPriceOverridden) {
              setState(() => _errorMessage =
                  'Unauthorized price change on "${item.product.name}": Cashiers cannot modify catalog price. Owner authorization required.');
              return;
            }
            if (!item.discount.isFinite || item.discount.isNaN || item.discount < 0) {
              setState(() => _errorMessage =
                  'Invalid discount on "${item.product.name}": must be a non-negative finite number.');
              return;
            }
            if (item.discount > item.grossTotal) {
              setState(() => _errorMessage =
                  'Discount on "${item.product.name}" cannot exceed subtotal (₹${item.grossTotal.toStringAsFixed(2)}).');
              return;
            }
            if (item.grossTotal > 0 && item.discount > 0) {
              final pct = (item.discount / item.grossTotal) * 100.0;
              if (double.parse(pct.toStringAsFixed(4)) > 10.00) {
                setState(() => _errorMessage =
                    'Unauthorized discount on "${item.product.name}": Cashier discount (${pct.toStringAsFixed(1)}%) exceeds allowed maximum of 10%. Owner authorization required.');
                return;
              }
            }
          }
        }

        if (notifier != null) {
          for (final item in _additionalCartItems) {
            final summary = notifier.inventorySummaries
                .where((s) => s.product.id == item.product.id)
                .firstOrNull;
            final available = summary == null
                ? 0
                : (_selectedLocationId == LocationConstants.neemranaId
                    ? summary.neemranaFinishedStock
                    : summary.jaipurFinishedStock);
            if (item.quantity > available) {
              setState(() => _errorMessage =
                  'Cannot sell ${item.quantity} pkts of ${item.product.name}. Only $available pkts available in stock.');
              return;
            }
          }
        }
      }
      setState(() {
        _errorMessage = null;
        _currentStep = 1;
      });
    } else if (_currentStep == 1) {
      final isValid = _step2FormKey.currentState?.validate() ?? false;
      if (!isValid) {
        final name = _nameCtrl.text.trim();
        final phoneDigits = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
        if (name.isEmpty && phoneDigits.length < 10) {
          setState(() => _errorMessage =
              'Please enter customer name and a valid 10-digit WhatsApp number.');
        } else if (name.isEmpty) {
          setState(() => _errorMessage = 'Please enter customer name.');
        } else if (phoneDigits.length < 10) {
          setState(() => _errorMessage =
              'Please enter a valid 10-digit WhatsApp number.');
        } else {
          setState(() => _errorMessage =
              'Please complete all required customer fields.');
        }
        return;
      }
      setState(() {
        _errorMessage = null;
        _currentStep = 2;
      });
    }
  }

  void _previousStep() {
    FocusScope.of(context).unfocus();
    setState(() => _errorMessage = null);
    if (_currentStep > 0 && _completedSale == null) {
      setState(() => _currentStep--);
    }
  }

  Future<void> _handleCompleteSaleAndSendWhatsApp() async {
    if (_isSubmitting || _completedSale != null) return;
    final notifier = InventoryProvider.maybeOf(context);
    final itemsToSubmit = _allCartItems;
    if (notifier == null || itemsToSubmit.isEmpty) {
      setState(() => _errorMessage = 'Cart is empty. Please select a product.');
      return;
    }
    final primaryItem = itemsToSubmit.first;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      // 1. Commit sale through secure Supabase RPC with Idempotency Token
      _clientRequestId ??= IdGenerator.generateUuidV4();
      final createdSale = await notifier.recordSale(
        items: itemsToSubmit,
        productId: primaryItem.product.id,
        quantity: primaryItem.quantity,
        clientRequestId: _clientRequestId,
        customerName: _nameCtrl.text.trim(),
        customerPhone: _phoneCtrl.text.trim(),
        paymentMethod: _paymentMethod,
        locationId: _selectedLocationId,
        invoiceType: 'NON_GST',
        totalAmount: _totalAmount,
        unitPrice: primaryItem.unitPrice,
        discount: primaryItem.discount,
        callerRole: widget.role.name,
      );

      if (!mounted) return;

      if (createdSale == null) {
        setState(() {
          _isSubmitting = false;
          _errorMessage =
              notifier.errorMessage ?? 'Failed to record sale in database.';
        });
        return;
      }

      // 2. Lock committed sale, clear client request token, and transition to completion
      setState(() {
        _completedSale = createdSale;
        _currentStep = 3;
      });

      // 3. Immediately launch WhatsApp targeting customer
      await _dispatchWhatsApp(createdSale);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  Future<void> _dispatchWhatsApp(Sale sale) async {
    final notifier = InventoryProvider.maybeOf(context);
    final Map<String, Product> productMap = <String, Product>{
      for (final p in (notifier?.products ?? const <Product>[])) p.id: p,
    };

    try {
      final result =
          await PdfInvoiceService.sendBillOnWhatsApp(sale, productMap);
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
    setState(() => _isRetryingWhatsApp = true);
    await _dispatchWhatsApp(_completedSale!);
  }

  @override
  Widget build(BuildContext context) {
    final notifier = InventoryProvider.maybeOf(context);
    final isNeemrana =
        _selectedLocationId == LocationConstants.neemranaId;
    final primaryColor =
        isNeemrana ? AppColors.roleNeemrana : AppColors.roleJaipur;

    return PopScope(
      canPop: _completedSale != null || !_isSubmitting,
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          title: Text(_completedSale != null
              ? 'Sale Completed'
              : 'New Retail Bill (POS)'),
          backgroundColor: primaryColor,
          leading: _completedSale != null
              ? IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context, _completedSale),
                )
              : null,
        ),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Visible Step Progress Header
              _buildStepIndicator(primaryColor),

              // Inline Error Notice
              if (_errorMessage != null)
                Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: AppColors.error, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                              color: AppColors.error, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),

              // Active Stage Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: notifier == null
                      ? const Center(child: CircularProgressIndicator())
                      : _buildActiveStepContent(notifier, primaryColor),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: _completedSale == null
              ? _buildBottomControls(primaryColor)
              : _buildCompletionActions(primaryColor),
        ),
      ),
    );
  }

  Widget _buildStepIndicator(Color activeColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.white,
      child: Row(
        children: [
          _buildStepPill(0, '1. Items', activeColor),
          _buildStepDivider(0),
          _buildStepPill(1, '2. Customer & Pay', activeColor),
          _buildStepDivider(1),
          _buildStepPill(2, '3. Review Bill', activeColor),
        ],
      ),
    );
  }

  Widget _buildStepPill(int stepIndex, String title, Color activeColor) {
    final isDone = _currentStep > stepIndex || _completedSale != null;
    final isActive = _currentStep == stepIndex;

    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDone
                  ? AppColors.success
                  : (isActive ? activeColor : Colors.grey.shade300),
            ),
            child: Center(
              child: isDone
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : Text(
                      '${stepIndex + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isActive ? Colors.white : Colors.grey.shade700,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? activeColor : Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepDivider(int afterStep) {
    final isDone = _currentStep > afterStep;
    return Container(
      width: 16,
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: isDone ? AppColors.success : Colors.grey.shade300,
    );
  }

  Widget _buildActiveStepContent(
      InventoryNotifier notifier, Color primaryColor) {
    switch (_currentStep) {
      case 0:
        return _buildStep1Products(notifier, primaryColor);
      case 1:
        return _buildStep2CustomerAndPayment(primaryColor);
      case 2:
        return _buildStep3Review(notifier, primaryColor);
      case 3:
      default:
        return _buildStep4Completed(primaryColor);
    }
  }

  // STEP 1: Products & Quantities
  Widget _buildStep1Products(
      InventoryNotifier notifier, Color primaryColor) {
    final stockAvailable = _getAvailableStock(notifier);

    return Form(
      key: _step1FormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Outlet Selector Card
          KizunaCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select Selling Outlet',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildOutletRadio(
                        title: 'Jaipur Store',
                        locationId: LocationConstants.jaipurId,
                        color: AppColors.roleJaipur,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildOutletRadio(
                        title: 'Neemrana Store',
                        locationId: LocationConstants.neemranaId,
                        color: AppColors.roleNeemrana,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Product Selection Card
          KizunaCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Product & Stock Availability',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                // Product Dropdown
                DropdownButtonFormField<Product>(
                  key: const Key('guided_product_select'),
                  // ignore: deprecated_member_use
                  value: _selectedProduct,
                  decoration: const InputDecoration(
                    labelText: 'Select Product *',
                    border: OutlineInputBorder(),
                  ),
                  items: notifier.products
                      .where((p) => p.active)
                      .map((p) => DropdownMenuItem(
                            value: p,
                            child: Text('${p.name} (${p.packageSize})'),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedProduct = val;
                        _priceCtrl.text =
                            val.standardSellingPrice.toStringAsFixed(2);
                        _hasUserEditedPrice = false;
                      });
                    }
                  },
                  validator: (val) => val == null ? 'Select a product' : null,
                ),
                const SizedBox(height: 12),

                // Live Stock On Hand Indicator
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: stockAvailable > 0
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: stockAvailable > 0
                          ? Colors.green.shade300
                          : Colors.orange.shade300,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        stockAvailable > 0
                            ? Icons.inventory_2_rounded
                            : Icons.warning_amber_rounded,
                        color: stockAvailable > 0
                            ? Colors.green.shade800
                            : Colors.orange.shade800,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Available Stock: $stockAvailable pkts',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: stockAvailable > 0
                              ? Colors.green.shade900
                              : Colors.orange.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Quantity & Pricing Card
          KizunaCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Quantity & Price',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    // Decrement Button
                    IconButton.filledTonal(
                      icon: const Icon(Icons.remove),
                      onPressed: () {
                        final current = _quantity;
                        if (current > 1) {
                          setState(() => _qtyCtrl.text = '${current - 1}');
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    // Quantity Field
                    Expanded(
                      child: TextFormField(
                        key: const Key('guided_quantity_field'),
                        controller: _qtyCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          labelText: 'Packets *',
                          border: OutlineInputBorder(),
                        ),
                        validator: (val) {
                          final q = int.tryParse(val ?? '');
                          if (q == null || q <= 0) {
                            return 'Enter quantity > 0';
                          }
                          return null;
                        },
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Increment Button
                    IconButton.filledTonal(
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        final current = _quantity;
                        setState(() => _qtyCtrl.text = '${current + 1}');
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Clearly labelled Selling Price (₹ per packet) numeric input directly below Quantity
                TextFormField(
                  key: const Key('guided_selling_price_field'),
                  controller: _priceCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Selling Price (₹ per packet) *',
                    helperText: _selectedProduct != null
                        ? 'Standard price: ₹${_selectedProduct!.standardSellingPrice.toStringAsFixed(2)} per pkt'
                        : null,
                    prefixIcon: const Icon(Icons.currency_rupee_rounded),
                    suffixIcon: _isPriceOverridden
                        ? IconButton(
                            tooltip: 'Reset to standard catalog price',
                            icon: const Icon(Icons.restore_rounded),
                            onPressed: () {
                              if (_selectedProduct != null) {
                                setState(() {
                                  _priceCtrl.text = _selectedProduct!
                                      .standardSellingPrice
                                      .toStringAsFixed(2);
                                  _hasUserEditedPrice = false;
                                });
                              }
                            },
                          )
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Selling price is required';
                    }
                    final p = double.tryParse(val.trim());
                    if (p == null || p <= 0) {
                      return 'Enter a positive selling price (> 0)';
                    }
                    return null;
                  },
                  onChanged: (_) {
                    _hasUserEditedPrice = true;
                    setState(() {});
                  },
                ),
                const SizedBox(height: 12),

                // Applicable Discount (₹) input
                TextFormField(
                  key: const Key('guided_discount_field'),
                  controller: _discountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Discount (₹)',
                    hintText: '0.00',
                    prefixIcon: Icon(Icons.discount_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return null;
                    final d = double.tryParse(val.trim());
                    if (d == null || d < 0) {
                      return 'Discount cannot be negative';
                    }
                    final gross = _quantity * _unitPrice;
                    if (d > gross) {
                      return 'Discount cannot exceed ₹${gross.toStringAsFixed(2)}';
                    }
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),

                // Price Override Note if changed
                if (_isPriceOverridden) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.edit_note_rounded,
                            color: Colors.amber.shade800, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Authorized Price Override: ₹${_unitPrice.toStringAsFixed(2)} (Standard: ₹${_selectedProduct?.standardSellingPrice.toStringAsFixed(2)})',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Rate and Subtotal Row: updates automatically
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Rate per pkt: ₹${_unitPrice.toStringAsFixed(2)}',
                            style: TextStyle(color: Colors.grey.shade700)),
                        if (_discount > 0)
                          Text(
                            'Discount: -₹${_discount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.green,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    Text(
                      _additionalCartItems.isEmpty
                          ? 'Subtotal: ₹${_totalAmount.toStringAsFixed(2)}'
                          : 'Item Total: ₹${_currentLineTotal.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Add Product to Bill Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('add_item_to_cart_button'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _addCurrentProductToCart,
              icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
              label: Text(
                _additionalCartItems.isEmpty
                    ? '+ Add Product to Bill'
                    : '+ Add Another Product to Bill',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Items in Current Bill Card
          if (_additionalCartItems.isNotEmpty) ...[
            KizunaCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Items in this Bill (${_additionalCartItems.length} ${_additionalCartItems.length == 1 ? "product" : "products"})',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Text(
                        'Bill Total: ₹${_totalAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                            fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 6),
                  ..._additionalCartItems.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final itm = entry.value;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${itm.product.name} (${itm.product.packageSize}) × ${itm.quantity} pkts (${itm.product.calculateTotalWeight(itm.quantity)}) @ ₹${itm.unitPrice.toStringAsFixed(2)}${itm.discount > 0 ? " (-₹${itm.discount.toStringAsFixed(2)})" : ""}',
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ),
                          Text(
                            '₹${itm.lineTotal.toStringAsFixed(2)}',
                            key: Key('line_total_$idx'),
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            key: Key('remove_cart_item_$idx'),
                            icon: const Icon(Icons.remove_circle_outline,
                                color: Colors.red, size: 20),
                            tooltip: 'Remove item from bill',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => _removeCartItem(idx),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 4),

          // Continue to Customer & Payment Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              key: const Key('continue_to_customer_button'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 1,
              ),
              onPressed: _nextStep,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text(
                'Continue to Customer & Payment',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutletRadio({
    required String title,
    required String locationId,
    required Color color,
  }) {
    final isSelected = _selectedLocationId == locationId;
    return InkWell(
      onTap: () {
        setState(() => _selectedLocationId = locationId);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.12) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? color : Colors.grey,
              size: 18,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? color : Colors.grey.shade700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // STEP 2: Customer & Payment
  Widget _buildStep2CustomerAndPayment(Color primaryColor) {
    return Form(
      key: _step2FormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Customer Details Card
          KizunaCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Customer Information',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('guided_customer_name_field'),
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Customer Name *',
                    hintText: 'e.g. Ramesh Kumar',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Customer name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('guided_customer_phone_field'),
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'WhatsApp Phone Number *',
                    hintText: 'e.g. 9876543210',
                    prefixIcon: Icon(Icons.phone_android_rounded),
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Customer phone is required';
                    }
                    final digits = val.replaceAll(RegExp(r'\D'), '');
                    if (digits.length < 10) {
                      return 'Enter a valid 10-digit mobile number';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Payment Mode Card
          KizunaCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Payment Method',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    // CASH
                    Expanded(
                      child: _buildPaymentOptionCard(
                        title: 'Cash',
                        value: 'CASH',
                        icon: Icons.payments_rounded,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // UPI
                    Expanded(
                      child: _buildPaymentOptionCard(
                        title: 'UPI',
                        value: 'UPI',
                        icon: Icons.qr_code_scanner_rounded,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Continue to Review Bill Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              key: const Key('continue_to_review_bill_button'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 2,
              ),
              onPressed: _nextStep,
              icon: const Icon(Icons.arrow_forward_rounded, size: 20),
              label: const Text(
                'Continue to Review Bill',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Back to Items Action
          Center(
            child: TextButton.icon(
              key: const Key('step2_back_to_items_button'),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Back to Items'),
              onPressed: _previousStep,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentOptionCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _paymentMethod == value;
    return InkWell(
      key: Key('payment_option_$value'),
      onTap: () => setState(() => _paymentMethod = value),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.12) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? color : Colors.grey.shade600, size: 28),
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? color : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // STEP 3: Review Bill & Complete
  Widget _buildStep3Review(InventoryNotifier notifier, Color primaryColor) {
    final storeName = _selectedLocationId == LocationConstants.neemranaId
        ? 'Neemrana Store'
        : 'Jaipur Store';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Bill Summary Card
        KizunaCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Bill Preview',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      storeName,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Customer Info Header with Edit Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'CUSTOMER & PAYMENT',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('edit_customer_button'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    ),
                    icon: const Icon(Icons.edit_rounded, size: 14),
                    label: const Text('Edit Customer', style: TextStyle(fontSize: 12)),
                    onPressed: () => setState(() => _currentStep = 1),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _buildReviewRow('Customer:', _nameCtrl.text.trim()),
              const SizedBox(height: 6),
              _buildReviewRow('WhatsApp:', _phoneCtrl.text.trim()),
              const SizedBox(height: 6),
              _buildReviewRow('Payment Mode:', _paymentMethod),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Purchased Items Header with Edit Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'PURCHASED ITEMS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('edit_items_button'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    ),
                    icon: const Icon(Icons.edit_rounded, size: 14),
                    label: const Text('Edit Items', style: TextStyle(fontSize: 12)),
                    onPressed: () => setState(() => _currentStep = 0),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Line Items in Review
              for (final item in _allCartItems) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.product.name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${item.quantity} pkts @ ₹${item.unitPrice.toStringAsFixed(2)}${item.discount > 0 ? " (Disc: -₹${item.discount.toStringAsFixed(2)})" : ""} • Total: ${item.product.calculateTotalWeight(item.quantity)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          if (item.isPriceOverridden) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Price override from standard ₹${item.product.standardSellingPrice.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Text(
                      '₹${item.lineTotal.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 16),
              const Divider(thickness: 1.2),
              const SizedBox(height: 12),

              // Grand Total
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total Amount:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '₹${_totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Process Guarantee Notice
        Builder(
          builder: (context) {
            final totalPkts =
                _allCartItems.fold<int>(0, (sum, i) => sum + i.quantity);
            final itemsCount = _allCartItems.length;
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.verified_user_rounded,
                      color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tapping "Complete Sale & Send WhatsApp" below will securely record this sale in Supabase, decrement $storeName stock by $totalPkts pkts across $itemsCount item(s), and automatically launch WhatsApp.',
                      style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildReviewRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }

  // STEP 4: Completed
  Widget _buildStep4Completed(Color primaryColor) {
    final sale = _completedSale!;
    final wa = _whatsAppResult;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Success Header Card
        KizunaCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: AppColors.success, size: 54),
              const SizedBox(height: 12),
              const Text(
                'Sale Completed!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Bill No: ${sale.billNumber}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimaryLight,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Total Amount: ₹${sale.totalAmount.toStringAsFixed(2)} • ${sale.paymentMethod}',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // WhatsApp Status Card
        if (wa != null)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: wa.success
                  ? const Color(0xFF25D366).withValues(alpha: 0.12)
                  : AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: wa.success ? const Color(0xFF25D366) : AppColors.warning,
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
                  size: 22,
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
                      Text(wa.message, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          )
        else if (_isSubmitting)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Column(
                children: [
                  CircularProgressIndicator(color: Color(0xFF25D366)),
                  SizedBox(height: 8),
                  Text('Opening WhatsApp...',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // Bottom Navigation Buttons
  Widget _buildBottomControls(Color primaryColor) {
    if (_currentStep == 2) {
      // Step 3: Dedicated full-width fixed-bottom Complete Sale action
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              offset: const Offset(0, -3),
              blurRadius: 8,
            ),
          ],
          border: Border(
            top: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: double.infinity,
              height: 52,
              child: KeyedSubtree(
                key: const Key('submit_sale_button'),
                child: ElevatedButton.icon(
                  key: const Key('complete_sale_send_whatsapp_button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 3,
                  ),
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 20),
                  label: Text(
                    _isSubmitting
                        ? 'Processing Sale...'
                        : 'Complete Sale & Send WhatsApp',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      letterSpacing: 0.2,
                    ),
                  ),
                  onPressed: _isSubmitting
                      ? null
                      : _handleCompleteSaleAndSendWhatsApp,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: TextButton.icon(
                key: const Key('guided_back_button'),
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label:
                    const Text('Back to Edit', style: TextStyle(fontSize: 13)),
                onPressed: _isSubmitting ? null : _previousStep,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            offset: const Offset(0, -2),
            blurRadius: 4,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (_currentStep > 0) ...[
            OutlinedButton(
              key: const Key('guided_back_button'),
              onPressed: _isSubmitting ? null : _previousStep,
              child: const Text('Back'),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: ElevatedButton(
              key: const Key('guided_next_button'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _nextStep,
              child: Text(
                _currentStep == 0
                    ? 'Continue to Customer & Payment →'
                    : 'Continue to Review Bill →',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletionActions(Color primaryColor) {
    final sale = _completedSale!;

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Row(
        children: [
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
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF25D366),
                    ),
                  )
                : const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry WhatsApp'),
            onPressed: _isRetryingWhatsApp ? null : _handleRetryWhatsApp,
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            key: const Key('view_invoice_button'),
            icon: const Icon(Icons.receipt_long_rounded, size: 16),
            label: const Text('View Bill'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => InvoicePreviewScreen(sale: sale),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton(
              key: const Key('done_button'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => Navigator.pop(context, sale),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }
}
