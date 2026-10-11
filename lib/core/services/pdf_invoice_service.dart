import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../features/inventory/domain/entities/location.dart';
import '../../features/inventory/domain/entities/product.dart';
import '../../features/inventory/domain/entities/sale.dart';
import '../config/app_config.dart';

/// Handoff status result when attempting to send a bill on WhatsApp.
class WhatsAppResult {
  final bool success;
  final String message;
  final bool launchedDirectly;
  final bool fallbackToShare;
  final String? normalizedPhone;

  const WhatsAppResult({
    required this.success,
    required this.message,
    required this.launchedDirectly,
    required this.fallbackToShare,
    this.normalizedPhone,
  });
}

/// Renders client-side 80mm thermal receipt PDFs for completed Kizuna Veda sales and invokes native sharing.
abstract final class PdfInvoiceService {
  /// Normalizes raw phone number strings to international E.164 digits for Indian numbers (+91).
  static String normalizePhoneNumber(String rawPhone) {
    final digits = rawPhone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) {
      return '91$digits';
    } else if (digits.length == 11 && digits.startsWith('0')) {
      return '91${digits.substring(1)}';
    } else if (digits.length == 12 && digits.startsWith('91')) {
      return digits;
    }
    return digits;
  }

  /// Formats normalized phone number digits into a clean display string (e.g., +91 98765 43210).
  static String formatDisplayPhone(String rawPhone) {
    final digits = normalizePhoneNumber(rawPhone);
    if (digits.length == 12 && digits.startsWith('91')) {
      final area = digits.substring(2, 7);
      final rest = digits.substring(7);
      return '+91 $area $rest';
    }
    return '+$digits';
  }

  /// Generates 80mm thermal receipt PDF bytes for a completed [Sale].
  static Future<Uint8List> generateInvoicePdf(
    Sale sale,
    Map<String, Product> productMap,
  ) async {
    final pdf = pw.Document();
    final soldLocal = sale.soldAt.toLocal();
    final dateStr =
        '${soldLocal.day.toString().padLeft(2, '0')}/${soldLocal.month.toString().padLeft(2, '0')}/${soldLocal.year} ${soldLocal.hour.toString().padLeft(2, '0')}:${soldLocal.minute.toString().padLeft(2, '0')}';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(10),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header & Branding
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      'KIZUNA VEDA',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'Ayurvedic Wellness Enterprise - ${sale.locationId == Location.neemranaId ? "NEEMRANA" : "JAIPUR"}',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                    if (sale.isGst) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'GSTIN: ${AppConfig.gstin}',
                        style: pw.TextStyle(
                          fontSize: 7,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                    pw.SizedBox(height: 4),
                    pw.Text(
                      sale.isGst ? 'TAX INVOICE (GST)' : 'RETAIL INVOICE',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              pw.Divider(thickness: 0.8),

              // Metadata & Customer Info
              pw.Text(
                'Bill No: ${sale.billNumber}',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Date: $dateStr',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Text(
                'Customer: ${sale.customerName ?? "Retail Customer"}',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Text(
                'Phone: ${sale.customerPhone ?? "N/A"}',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Text(
                'Payment: ${sale.paymentMethod} | Mode: ${sale.invoiceType}',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Divider(thickness: 0.8),

              // Items Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    flex: 3,
                    child: pw.Text(
                      'Item / SKU',
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    flex: 1,
                    child: pw.Text(
                      'Qty',
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Text(
                      'Total (INR)',
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              pw.Divider(thickness: 0.5),

              // Line Items Listing
              if (sale.items.isNotEmpty)
                ...sale.items.map((item) {
                  final prod = productMap[item.productId];
                  final name = prod?.name ?? 'Product (${item.productId})';
                  final sku = prod?.sku ?? '';
                  final totalStr = item.lineTotal.toStringAsFixed(2);
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          flex: 3,
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(name,
                                  style: const pw.TextStyle(fontSize: 8)),
                              if (sku.isNotEmpty)
                                pw.Text(
                                  item.discount > 0
                                      ? '$sku @ Rs ${item.unitPrice.toStringAsFixed(2)} (Disc: -Rs ${item.discount.toStringAsFixed(2)})'
                                      : '$sku @ Rs ${item.unitPrice.toStringAsFixed(2)}',
                                  style: const pw.TextStyle(fontSize: 7),
                                ),
                            ],
                          ),
                        ),
                        pw.Expanded(
                          flex: 1,
                          child: pw.Text(
                            '${item.quantity}',
                            textAlign: pw.TextAlign.right,
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        ),
                        pw.Expanded(
                          flex: 2,
                          child: pw.Text(
                            'Rs $totalStr',
                            textAlign: pw.TextAlign.right,
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        ),
                      ],
                    ),
                  );
                })
              else ...[
                // Single Product Shorthand fallback
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        flex: 3,
                        child: pw.Text(
                          productMap[sale.productId]?.name ?? 'Retail Product',
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      ),
                      pw.Expanded(
                        flex: 1,
                        child: pw.Text(
                          '${sale.quantity}',
                          textAlign: pw.TextAlign.right,
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      ),
                      pw.Expanded(
                        flex: 2,
                        child: pw.Text(
                          'Rs ${sale.totalAmount.toStringAsFixed(2)}',
                          textAlign: pw.TextAlign.right,
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              pw.Divider(thickness: 0.8),

              // Totals & GST Breakdown
              if (sale.isGst) ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Taxable Amount:', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text(
                      'Rs ${sale.taxableAmount.toStringAsFixed(2)}',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ],
                ),
                pw.SizedBox(height: 2),
                if (sale.igstAmount > 0) ...[
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('IGST (${sale.gstRate.toStringAsFixed(1)}%):',
                          style: const pw.TextStyle(fontSize: 8)),
                      pw.Text(
                        'Rs ${sale.igstAmount.toStringAsFixed(2)}',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                ] else ...[
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('CGST (${(sale.gstRate / 2).toStringAsFixed(1)}%):',
                          style: const pw.TextStyle(fontSize: 8)),
                      pw.Text(
                        'Rs ${sale.cgstAmount.toStringAsFixed(2)}',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 2),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('SGST (${(sale.gstRate / 2).toStringAsFixed(1)}%):',
                          style: const pw.TextStyle(fontSize: 8)),
                      pw.Text(
                        'Rs ${sale.sgstAmount.toStringAsFixed(2)}',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                ],
                pw.SizedBox(height: 2),
              ] else ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Subtotal:', style: const pw.TextStyle(fontSize: 9)),
                    pw.Text(
                      'Rs ${sale.totalAmount.toStringAsFixed(2)}',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ],
                ),
                pw.SizedBox(height: 2),
              ],

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'GRAND TOTAL:',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'Rs ${sale.totalAmount.toStringAsFixed(2)}',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),

              pw.Divider(thickness: 0.8),
              pw.SizedBox(height: 6),

              // Thank You Footer
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      'Thank you for choosing Kizuna Veda!',
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'Pure Ayurvedic Quality & Heritage',
                      style: const pw.TextStyle(fontSize: 7),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Convenience wrapper for generating PDF bytes
  static Future<Uint8List> buildPdf(Sale sale, [Map<String, Product> productMap = const {}]) {
    return generateInvoicePdf(sale, productMap);
  }

  /// Generates and invokes Android native share sheet for the specified [Sale].
  static Future<void> shareInvoicePdf(
    Sale sale,
    Map<String, Product> productMap,
  ) async {
    final pdfBytes = await generateInvoicePdf(sale, productMap);
    final tempDir = await getTemporaryDirectory();
    final filePath = '${tempDir.path}/KizunaVeda_${sale.billNumber}.pdf';
    final file = File(filePath);
    await file.writeAsBytes(pdfBytes, flush: true);

    await Share.shareXFiles(
      [XFile(filePath)],
      text:
          'Kizuna Veda Retail Invoice: ${sale.billNumber} (Rs ${sale.totalAmount.toStringAsFixed(2)})',
    );
  }

  /// Convenience alias for shareInvoicePdf
  static Future<void> generateAndSharePdf(Sale sale, [Map<String, Product> productMap = const {}]) {
    return shareInvoicePdf(sale, productMap);
  }

  /// Formats a complete WhatsApp text summary of the bill for customer communication.
  static String formatWhatsAppMessage(Sale sale, [Map<String, Product> productMap = const {}]) {
    final soldLocal = sale.soldAt.toLocal();
    final dateStr =
        '${soldLocal.day.toString().padLeft(2, '0')}/${soldLocal.month.toString().padLeft(2, '0')}/${soldLocal.year} ${soldLocal.hour.toString().padLeft(2, '0')}:${soldLocal.minute.toString().padLeft(2, '0')}';

    final outletName = sale.locationId == Location.neemranaId
        ? 'Neemrana Store'
        : 'Jaipur Store';

    final itemsSummary = StringBuffer();
    if (sale.items.isNotEmpty) {
      for (final item in sale.items) {
        final prodName = productMap[item.productId]?.name ?? 'Item';
        final discPart = item.discount > 0
            ? ' | Disc: -Rs ${item.discount.toStringAsFixed(2)}'
            : '';
        itemsSummary.writeln(
            '• $prodName | Qty: ${item.quantity} | Rate: Rs ${item.unitPrice.toStringAsFixed(2)}$discPart | Amt: Rs ${item.lineTotal.toStringAsFixed(2)}');
      }
    } else {
      final prodName = productMap[sale.productId]?.name ?? 'Item';
      final unitPrice =
          sale.quantity > 0 ? (sale.totalAmount / sale.quantity) : 0.0;
      itemsSummary.writeln(
          '• $prodName | Qty: ${sale.quantity} | Rate: Rs ${unitPrice.toStringAsFixed(2)} | Amt: Rs ${sale.totalAmount.toStringAsFixed(2)}');
    }

    return '''Kizuna Veda Retail Invoice: ${sale.billNumber}
Date: $dateStr
Outlet: $outletName
Customer: ${sale.customerName ?? "Retail Customer"}

Items:
${itemsSummary.toString().trim()}

Total Amount: Rs ${sale.totalAmount.toStringAsFixed(2)}
Payment Method: ${sale.paymentMethod}

Thank you for choosing Kizuna Veda!''';
  }

  static Future<bool> Function(Uri uri)? testLauncher;
  static Future<void> Function(List<XFile> files, {String? text})? testSharer;
  static Future<Directory> Function()? testTempDir = () async => Directory.systemTemp;

  /// Attempts to open WhatsApp directly targeting the entered customer phone number
  /// with prefilled invoice details and prepped PDF file attachment.
  /// Falls back gracefully to system share sheet if WhatsApp is not installed.
  static Future<WhatsAppResult> sendBillOnWhatsApp(
    Sale sale, [
    Map<String, Product> productMap = const {},
    Future<bool> Function(Uri uri)? customLauncher,
    Future<void> Function(List<XFile> files, {String? text})? customSharer,
    Future<Directory> Function()? customTempDir,
  ]) async {
    final phone = sale.customerPhone;
    final displayPhone = (phone != null && phone.trim().isNotEmpty)
        ? formatDisplayPhone(phone)
        : 'Customer Phone';

    final pdfBytes = await generateInvoicePdf(sale, productMap);
    final tempDir = (customTempDir != null)
        ? await customTempDir()
        : (testTempDir != null)
            ? await testTempDir!()
            : await getTemporaryDirectory();
    final filePath = '${tempDir.path}/KizunaVeda_${sale.billNumber}.pdf';
    final file = File(filePath);
    try {
      file.writeAsBytesSync(pdfBytes);
    } catch (_) {
      await file.writeAsBytes(pdfBytes, flush: true);
    }

    final messageText = formatWhatsAppMessage(sale, productMap);

    final effectiveLauncher = customLauncher ?? testLauncher;
    final effectiveSharer = customSharer ?? testSharer;

    Future<void> doShare() async {
      try {
        if (effectiveSharer != null) {
          await effectiveSharer([XFile(filePath)], text: messageText);
        } else {
          await Share.shareXFiles([XFile(filePath)], text: messageText)
              .timeout(const Duration(milliseconds: 500));
        }
      } catch (e) {
        debugPrint('[WHATSAPP] Share fallback notice: $e');
      }
    }

    if (phone == null || phone.trim().isEmpty) {
      await doShare();
      return WhatsAppResult(
        success: false,
        launchedDirectly: false,
        fallbackToShare: true,
        normalizedPhone: null,
        message:
            'Customer phone number is missing on this bill. Opening system share sheet...',
      );
    }

    final normalizedDigits = normalizePhoneNumber(phone);
    final whatsappUri = Uri.parse(
        'whatsapp://send?phone=$normalizedDigits&text=${Uri.encodeComponent(messageText)}');
    final waMeUri = Uri.parse(
        'https://wa.me/$normalizedDigits?text=${Uri.encodeComponent(messageText)}');

    bool launched = false;
    if (effectiveLauncher != null) {
      launched = await effectiveLauncher(whatsappUri);
      if (!launched) {
        launched = await effectiveLauncher(waMeUri);
      }
    } else {
      if (await canLaunchUrl(whatsappUri)) {
        launched = await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(waMeUri)) {
        launched = await launchUrl(waMeUri, mode: LaunchMode.externalApplication);
      }
    }

    if (launched) {
      await doShare();
      return WhatsAppResult(
        success: true,
        launchedDirectly: true,
        fallbackToShare: false,
        normalizedPhone: displayPhone,
        message:
            'WhatsApp opened for $displayPhone. Please tap Send to deliver the bill.',
      );
    } else {
      await doShare();
      return WhatsAppResult(
        success: false,
        launchedDirectly: false,
        fallbackToShare: true,
        normalizedPhone: displayPhone,
        message:
            'WhatsApp is not installed on this device. Opening system share sheet...',
      );
    }
  }
}
