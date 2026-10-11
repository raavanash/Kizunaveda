import 'package:flutter/material.dart';
import '../../../../app/providers/inventory_provider.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/services/pdf_invoice_service.dart';
import '../../../../core/widgets/kizuna_card.dart';
import '../../../inventory/domain/entities/location.dart';
import '../../../inventory/domain/entities/product.dart';
import '../../../inventory/domain/entities/sale.dart';

/// Interactive preview screen for completed retail sale invoices.
class InvoicePreviewScreen extends StatelessWidget {
  final Sale sale;

  const InvoicePreviewScreen({super.key, required this.sale});

  @override
  Widget build(BuildContext context) {
    final inventoryNotifier = InventoryProvider.maybeOf(context);
    final products = inventoryNotifier?.products ?? [];
    final productMap = <String, Product>{for (var p in products) p.id: p};

    final soldLocal = sale.soldAt.toLocal();
    final dateStr =
        '${soldLocal.day.toString().padLeft(2, '0')}/${soldLocal.month.toString().padLeft(2, '0')}/${soldLocal.year} ${soldLocal.hour.toString().padLeft(2, '0')}:${soldLocal.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(
        title: Text('Invoice • ${sale.billNumber}'),
        backgroundColor: AppColors.roleJaipur,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Share Invoice PDF',
            onPressed: () =>
                PdfInvoiceService.shareInvoicePdf(sale, productMap),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Voided Warning Banner if sale is voided
              if (sale.isVoided) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.error),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.cancel_outlined, color: AppColors.error),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'THIS SALE WAS VOIDED ON HISTORICAL LOGS. IT IS NOT AN ACTIVE RETAIL INVOICE.',
                          style: TextStyle(
                            color: AppColors.error,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Invoice Document Card
              KizunaCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand Header & Address Placeholder
                    Center(
                      child: Column(
                        children: [
                          const Text(
                            'KIZUNA VEDA',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Ayurvedic Wellness & Pure Botanicals',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondaryLight,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.backgroundLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              sale.locationId == Location.neemranaId
                                  ? 'Neemrana Manufacturing & Sales Unit, Rajasthan'
                                  : 'Jaipur Retail Outlet & Sales Unit, Rajasthan',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondaryLight,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (sale.isGst) ...[
                            const SizedBox(height: 6),
                            Text(
                              'GSTIN: ${AppConfig.gstin}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: sale.isCompleted
                                  ? AppColors.roleJaipur.withValues(alpha: 0.15)
                                  : AppColors.error.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              sale.isCompleted
                                  ? (sale.isGst ? 'TAX INVOICE (GST)' : 'RETAIL INVOICE (NON-GST)')
                                  : 'VOIDED INVOICE',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: sale.isCompleted
                                    ? AppColors.roleJaipur
                                    : AppColors.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 12),

                    // Bill & Customer Details Grid
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabelValue(
                                  'Bill Number:', sale.billNumber, isBold: true),
                              const SizedBox(height: 6),
                              _buildLabelValue('Date & Time:', dateStr),
                              const SizedBox(height: 6),
                              _buildLabelValue(
                                  'Status:', sale.status, isBold: true),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabelValue(
                                'Customer:',
                                sale.customerName ?? 'Retail Customer',
                                isBold: true,
                              ),
                              const SizedBox(height: 6),
                              _buildLabelValue(
                                  'Phone:', sale.customerPhone ?? 'N/A'),
                              const SizedBox(height: 6),
                              _buildLabelValue(
                                'Payment & Mode:',
                                '${sale.paymentMethod} (${sale.invoiceType})',
                                isBold: true,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 12),

                    // Itemized Table Header
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              'Product & SKU',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Text(
                              'Qty',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              'Total Amount',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Itemized Rows Listing
                    if (sale.items.isNotEmpty)
                      ...sale.items.map((item) {
                        final prod = productMap[item.productId];
                        final name = prod?.name ?? 'Product (${item.productId})';
                        final sku = prod?.sku ?? '';
                        final size = prod?.packageSize ?? '';
                        final lineTotal = item.quantity * item.unitPrice;

                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 6),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                    if (sku.isNotEmpty || size.isNotEmpty)
                                      Text(
                                        '$sku ${size.isNotEmpty ? "($size)" : ""}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondaryLight,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Text(
                                  '${item.quantity}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '₹${lineTotal.toStringAsFixed(2)}',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      })
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 6),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(
                                productMap[sale.productId]?.name ??
                                    'Retail Product',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                '${sale.quantity}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '₹${sale.totalAmount.toStringAsFixed(2)}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 12),

                    // Totals & GST Breakdown
                    if (sale.isGst) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Taxable Amount:',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondaryLight,
                            ),
                          ),
                          Text(
                            '₹${sale.taxableAmount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (sale.igstAmount > 0) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'IGST (${sale.gstRate.toStringAsFixed(1)}%):',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondaryLight,
                              ),
                            ),
                            Text(
                              '₹${sale.igstAmount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'CGST (${(sale.gstRate / 2).toStringAsFixed(1)}%):',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondaryLight,
                              ),
                            ),
                            Text(
                              '₹${sale.cgstAmount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'SGST (${(sale.gstRate / 2).toStringAsFixed(1)}%):',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondaryLight,
                              ),
                            ),
                            Text(
                              '₹${sale.sgstAmount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 6),
                    ] else ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Subtotal:',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondaryLight,
                            ),
                          ),
                          Text(
                            '₹${sale.totalAmount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'GRAND TOTAL:',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                        Text(
                          '₹${sale.totalAmount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 12),

                    // Thank You Note
                    const Center(
                      child: Column(
                        children: [
                          Text(
                            'Thank you for choosing Kizuna Veda!',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: AppColors.textPrimaryLight,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Pure Ayurvedic Quality & Enterprise Heritage',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textMutedLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Action Buttons
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366), // WhatsApp Green
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.send_rounded),
                label: const Text(
                  'SEND BILL ON WHATSAPP',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                onPressed: () async {
                  final result = await PdfInvoiceService.sendBillOnWhatsApp(
                    sale,
                    productMap,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(result.message),
                        backgroundColor: result.success
                            ? const Color(0xFF25D366)
                            : AppColors.roleJaipur,
                        duration: const Duration(seconds: 4),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.roleJaipur,
                  side: const BorderSide(color: AppColors.roleJaipur),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.picture_as_pdf_rounded),
                label: const Text(
                  'GENERATE & SHARE PDF',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                onPressed: () =>
                    PdfInvoiceService.shareInvoicePdf(sale, productMap),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabelValue(String label, String value, {bool isBold = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondaryLight,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
