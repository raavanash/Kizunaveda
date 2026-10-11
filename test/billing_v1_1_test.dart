import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kizuna_veda/app/providers/inventory_provider.dart';
import 'package:kizuna_veda/core/services/pdf_invoice_service.dart';
import 'package:kizuna_veda/features/inventory/data/repositories/unconnected_inventory_repository.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/sale.dart';
import 'package:kizuna_veda/features/inventory/presentation/controllers/inventory_notifier.dart';
import 'package:kizuna_veda/features/jaipur/presentation/screens/ebill_history_screen.dart';
import 'package:kizuna_veda/features/jaipur/presentation/screens/invoice_preview_screen.dart';
import 'package:kizuna_veda/features/owner/presentation/screens/jaipur_stock_screen.dart';

void main() {
  group('V1.1 Billing Repository & RPC Contract Validation', () {
    late UnconnectedInventoryRepository repository;
    late InventoryNotifier notifier;

    setUp(() async {
      repository = UnconnectedInventoryRepository();
      notifier = InventoryNotifier(repository: repository);
      await notifier.loadInventoryData();
    });

    tearDown(() {
      notifier.dispose();
    });

    test('recordSale persists customerName and paymentMethod accurately', () async {
      final product = notifier.products.first;
      final createdSale = await notifier.recordSale(
        productId: product.id,
        quantity: 2,
        customerName: 'Rahul Sharma',
        customerPhone: '9876543210',
        paymentMethod: 'UPI',
      );

      expect(createdSale, isNotNull);
      expect(createdSale!.customerName, equals('Rahul Sharma'));
      expect(createdSale.customerPhone, equals('9876543210'));
      expect(createdSale.paymentMethod, equals('UPI'));
      expect(createdSale.billNumber, startsWith('BILL-'));
      expect(createdSale.status, equals('COMPLETED'));
      expect(notifier.lastCreatedSale, equals(createdSale));
    });

    test('recordSale rejects invalid payment method', () async {
      final product = notifier.products.first;
      final createdSale = await notifier.recordSale(
        productId: product.id,
        quantity: 1,
        customerName: 'Test User',
        customerPhone: '9999999999',
        paymentMethod: 'CRYPTO', // Invalid method
      );

      expect(createdSale, isNull);
      expect(notifier.errorMessage, contains('Invalid payment method'));
    });

    test('recordSale fails if quantity is zero or negative', () async {
      final product = notifier.products.first;
      final createdSale = await notifier.recordSale(
        productId: product.id,
        quantity: 0,
        customerName: 'Test User',
        customerPhone: '9999999999',
        paymentMethod: 'CASH',
      );

      expect(createdSale, isNull);
      expect(notifier.errorMessage, contains('Quantity must be greater than zero'));
    });
  });

  group('V1.1 Invoice Preview & PDF Generation', () {
    final sampleSale = Sale(
      id: 'sale-test-101',
      locationId: 'loc-jaipur',
      productId: 'prod-1',
      quantity: 4,
      billNumber: 'BILL-010001',
      customerPhone: '9876543210',
      customerName: 'Amit Verma',
      paymentMethod: 'CASH',
      totalAmount: 480.0,
      soldAt: DateTime(2026, 10, 5, 14, 30),
      createdAt: DateTime(2026, 10, 5, 14, 30),
      status: 'COMPLETED',
      items: [
        SaleItem(
          id: 'item-101',
          saleId: 'sale-test-101',
          productId: 'prod-1',
          quantity: 4,
          unitPrice: 120.0,
          createdAt: DateTime(2026, 10, 5, 14, 30),
        ),
      ],
    );

    testWidgets('InvoicePreviewScreen displays all invoice data accurately', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: InvoicePreviewScreen(sale: sampleSale),
        ),
      );

      expect(find.textContaining('INVOICE'), findsWidgets);
      expect(find.text('KIZUNA VEDA'), findsWidgets);
      expect(find.text('BILL-010001'), findsOneWidget);
      expect(find.text('Amit Verma'), findsOneWidget);
      expect(find.text('9876543210'), findsOneWidget);
      expect(find.textContaining('CASH'), findsWidgets);
      expect(find.text('₹480.00'), findsWidgets);
      expect(find.text('GST'), findsNothing);
      expect(find.text('Tax'), findsNothing);
    });

    test('PdfInvoiceService builds 80mm PDF for single item sale', () async {
      final pdfBytes = await PdfInvoiceService.buildPdf(sampleSale);
      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes.length, greaterThan(500));
    });

    test('PdfInvoiceService builds 80mm PDF for multi-item sale', () async {
      final multiItemSale = Sale(
        id: 'sale-test-102',
        locationId: 'loc-jaipur',
        productId: 'prod-1',
        quantity: 3,
        billNumber: 'BILL-010002',
        customerPhone: '9123456789',
        customerName: 'Sita Ram',
        paymentMethod: 'UPI',
        totalAmount: 950.0,
        soldAt: DateTime.now(),
        createdAt: DateTime.now(),
        status: 'COMPLETED',
        items: [
          SaleItem(
            id: 'item-102a',
            saleId: 'sale-test-102',
            productId: 'prod-1',
            quantity: 2,
            unitPrice: 120.0,
            createdAt: DateTime.now(),
          ),
          SaleItem(
            id: 'item-102b',
            saleId: 'sale-test-102',
            productId: 'prod-2',
            quantity: 1,
            unitPrice: 710.0,
            createdAt: DateTime.now(),
          ),
        ],
      );

      final pdfBytes = await PdfInvoiceService.buildPdf(multiItemSale);
      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes.length, greaterThan(800));
    });

    test('PdfInvoiceService.normalizePhoneNumber formats Indian phone numbers to E.164 digits', () {
      expect(PdfInvoiceService.normalizePhoneNumber('9876543210'), equals('919876543210'));
      expect(PdfInvoiceService.normalizePhoneNumber('09876543210'), equals('919876543210'));
      expect(PdfInvoiceService.normalizePhoneNumber('+91 98765 43210'), equals('919876543210'));
      expect(PdfInvoiceService.normalizePhoneNumber('919876543210'), equals('919876543210'));
    });

    test('PdfInvoiceService.formatDisplayPhone formats phone digits for display', () {
      expect(PdfInvoiceService.formatDisplayPhone('9876543210'), equals('+91 98765 43210'));
      expect(PdfInvoiceService.formatDisplayPhone('+919876543210'), equals('+91 98765 43210'));
    });

    test('sendBillOnWhatsApp launches direct chat when WhatsApp is available', () async {
      String? launchedUrl;
      List<String>? sharedFiles;

      final result = await PdfInvoiceService.sendBillOnWhatsApp(
        sampleSale,
        const {},
        (uri) async {
          launchedUrl = uri.toString();
          return true; // Simulate WhatsApp installed and launched
        },
        (files, {text}) async {
          sharedFiles = files.map((f) => f.path).toList();
        },
        () async => Directory.systemTemp,
      );

      expect(result.success, isTrue);
      expect(result.launchedDirectly, isTrue);
      expect(result.fallbackToShare, isFalse);
      expect(result.message, contains('WhatsApp opened for +91 98765 43210'));
      expect(launchedUrl, startsWith('whatsapp://send?phone=919876543210'));
      expect(launchedUrl, contains('BILL-010001'));
      expect(sharedFiles, isNotNull);
      expect(sharedFiles!.first, contains('KizunaVeda_BILL-010001.pdf'));
    });

    test('sendBillOnWhatsApp falls back to share sheet when WhatsApp is unavailable', () async {
      String? launchedUrl;
      List<String>? sharedFiles;

      final result = await PdfInvoiceService.sendBillOnWhatsApp(
        sampleSale,
        const {},
        (uri) async {
          launchedUrl = uri.toString();
          return false; // Simulate WhatsApp not installed
        },
        (files, {text}) async {
          sharedFiles = files.map((f) => f.path).toList();
        },
        () async => Directory.systemTemp,
      );

      expect(result.success, isFalse);
      expect(result.launchedDirectly, isFalse);
      expect(result.fallbackToShare, isTrue);
      expect(result.message, contains('WhatsApp is not installed on this device'));
      expect(launchedUrl, contains('https://wa.me/919876543210'));
      expect(sharedFiles, isNotNull);
      expect(sharedFiles!.first, contains('KizunaVeda_BILL-010001.pdf'));
    });
  });

  group('V1.1 E-Bill History & Voided Bills Tab', () {
    late UnconnectedInventoryRepository repository;
    late InventoryNotifier notifier;

    setUp(() async {
      repository = UnconnectedInventoryRepository();
      notifier = InventoryNotifier(repository: repository);
      await notifier.loadInventoryData();
    });

    tearDown(() {
      notifier.dispose();
    });

    testWidgets('EBillHistoryScreen separates active completed bills and voided bills', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: InventoryProvider(
            notifier: notifier,
            child: const EBillHistoryScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('Active Bills'), findsOneWidget);
      expect(find.textContaining('Voided Bills'), findsOneWidget);

      // Verify active tab shows completed bills
      expect(find.text('BILL-1001'), findsOneWidget);

      // Switch to Voided Bills tab
      await tester.tap(find.textContaining('Voided Bills'));
      await tester.pumpAndSettle();

      // Verify Voided tab shows voided empty message
      expect(find.text('No voided bill records found.'), findsOneWidget);
    });
  });

  group('V1.1 POS Sale Form Validation', () {
    late UnconnectedInventoryRepository repository;
    late InventoryNotifier notifier;

    setUp(() async {
      repository = UnconnectedInventoryRepository();
      notifier = InventoryNotifier(repository: repository);
      await notifier.loadInventoryData();
    });

    tearDown(() {
      notifier.dispose();
    });

    testWidgets('JaipurStockScreen opens POS modal and enforces required fields', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: InventoryProvider(
            notifier: notifier,
            child: const JaipurStockScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Record POS Sale button
      final recordSaleBtn = find.text('Record POS Sale');
      expect(recordSaleBtn, findsOneWidget);
      await tester.tap(recordSaleBtn);
      await tester.pumpAndSettle();

      // Verify dialog title
      expect(find.textContaining('Create Bill'), findsOneWidget);

      // Submit without filling customer name or phone
      final submitBtn = find.byKey(const Key('submit_sale_button'));
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Check validation error messages
      expect(find.text('Customer name is required'), findsOneWidget);
      expect(find.text('Customer phone is required'), findsOneWidget);
    });
  });
}
