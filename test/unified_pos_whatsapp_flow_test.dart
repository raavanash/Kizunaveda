import 'package:kizuna_veda/features/sales/domain/entities/cart_item.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kizuna_veda/app/providers/inventory_provider.dart';
import 'package:kizuna_veda/core/services/pdf_invoice_service.dart';
import 'package:kizuna_veda/features/inventory/data/repositories/unconnected_inventory_repository.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/location.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/sale.dart';
import 'package:kizuna_veda/features/inventory/presentation/controllers/inventory_notifier.dart';
import 'package:kizuna_veda/features/inventory/presentation/widgets/record_pos_sale_dialog.dart';
import 'package:share_plus/share_plus.dart';

class DelayedInventoryRepository extends UnconnectedInventoryRepository {
  Completer<void>? inFlightCompleter;

  @override
  Future<Sale> recordSale({
    String? productId,
    int? quantity,
    List<CartItem>? items,
    String? clientRequestId,
    String? customerName,
    String? customerPhone,
    String paymentMethod = 'CASH',
    String? locationId,
    String invoiceType = 'NON_GST',
    double gstRate = 0.0,
    double? taxableAmount,
    double cgstAmount = 0.0,
    double sgstAmount = 0.0,
    double igstAmount = 0.0,
    double totalAmount = 0.0,
    double? unitPrice,
    double discount = 0.0,
    DateTime? soldAt,
    String? callerRole,
  }) async {
    final sale = await super.recordSale(
      productId: productId,
      quantity: quantity,
      items: items,
      clientRequestId: clientRequestId,
      customerName: customerName,
      customerPhone: customerPhone,
      paymentMethod: paymentMethod,
      locationId: locationId,
      invoiceType: invoiceType,
      gstRate: gstRate,
      taxableAmount: taxableAmount,
      cgstAmount: cgstAmount,
      sgstAmount: sgstAmount,
      igstAmount: igstAmount,
      totalAmount: totalAmount,
      unitPrice: unitPrice,
      discount: discount,
      soldAt: soldAt,
      callerRole: callerRole,
    );

    if (inFlightCompleter != null) {
      await inFlightCompleter!.future;
    }
    return sale;
  }
}

void main() {
  group('Unified Complete Sale & Send WhatsApp Workflow Tests', () {
    late DelayedInventoryRepository repository;
    late InventoryNotifier notifier;
    late List<Uri> launchedUris;
    late List<String> sharedTexts;

    setUp(() async {
      launchedUris = [];
      sharedTexts = [];
      PdfInvoiceService.testTempDir = () async => Directory.systemTemp;
      PdfInvoiceService.testLauncher = (uri) async {
        launchedUris.add(uri);
        return true;
      };
      PdfInvoiceService.testSharer = (files, {text}) async {
        if (text != null) sharedTexts.add(text);
      };

      repository = DelayedInventoryRepository();
      notifier = InventoryNotifier(repository: repository);
      await notifier.loadInventoryData();
    });

    tearDown(() {
      PdfInvoiceService.testLauncher = null;
      PdfInvoiceService.testSharer = null;
      notifier.dispose();
    });

    Widget buildTestHost({
      Future<bool> Function(Uri uri)? customLauncher,
      Future<void> Function(List<XFile> files, {String? text})? customSharer,
    }) {
      return MaterialApp(
        home: InventoryProvider(
          notifier: notifier,
          child: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  key: const Key('open_pos_dialog'),
                  onPressed: () {
                    RecordPosSaleDialog.show(
                      ctx,
                      targetLocationId: Location.jaipurId,
                      locationName: 'Jaipur Store',
                      notifier: notifier,
                      customLauncher: customLauncher,
                      customSharer: customSharer,
                    );
                  },
                  child: const Text('Open POS'),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
        '1. Complete Sale & Send WhatsApp succeeds, creates sale once, and launches WhatsApp with formatted bill',
        (tester) async {
      await tester.pumpWidget(buildTestHost());
      await tester.pumpAndSettle();

      // Open unified POS dialog
      await tester.tap(find.byKey(const Key('open_pos_dialog')));
      await tester.pumpAndSettle();

      final initialStock = notifier.inventorySummaries.first.jaipurFinishedStock;
      final initialSalesCount = notifier.sales.length;

      // Fill customer info and quantity
      await tester.enterText(
          find.byKey(const Key('customer_name_field')), 'Ramesh Kumar');
      await tester.enterText(
          find.byKey(const Key('customer_phone_field')), '9876543210');
      await tester.enterText(find.byKey(const Key('quantity_field')), '3');
      await tester.pump();

      // Ensure unified primary button is present
      final submitBtn =
          find.byKey(const Key('complete_sale_send_whatsapp_button'));
      expect(submitBtn, findsOneWidget);
      expect(find.text('Complete Sale & Send WhatsApp'), findsOneWidget);

      // Tap Complete Sale & Send WhatsApp
      await tester.tap(submitBtn);
      await tester.pump();
      await tester.pumpAndSettle();

      // 1. Verify sale persisted exactly once
      expect(notifier.sales.length, initialSalesCount + 1);
      final createdSale = notifier.sales.first;
      expect(createdSale.customerName, 'Ramesh Kumar');
      expect(createdSale.customerPhone, '9876543210');
      expect(createdSale.quantity, 3);
      expect(createdSale.locationId, Location.jaipurId);

      // 2. Verify stock deducted from Jaipur outlet exactly once
      final updatedStock =
          notifier.inventorySummaries.first.jaipurFinishedStock;
      expect(updatedStock, initialStock - 3);

      // 3. Verify WhatsApp launched with proper URL and formatted bill text
      expect(launchedUris.isNotEmpty, isTrue);
      final whatsappUri = launchedUris.first;
      expect(whatsappUri.toString(), contains('phone=919876543210'));
      final decodedUri = Uri.decodeFull(whatsappUri.toString());
      expect(decodedUri, contains('Kizuna Veda Retail Invoice:'));
      expect(decodedUri, contains(createdSale.billNumber));
      expect(decodedUri, contains('Outlet: Jaipur Store'));
      expect(decodedUri, contains('Customer: Ramesh Kumar'));
      expect(decodedUri, contains('Qty: 3'));
      expect(decodedUri, contains('Payment Method: CASH'));

      // 4. Verify post-sale completion UI is displayed with bill details and action buttons
      expect(find.text('Sale Completed!'), findsOneWidget);
      expect(find.text(createdSale.billNumber), findsOneWidget);
      expect(find.byKey(const Key('retry_whatsapp_button')), findsOneWidget);
      expect(find.byKey(const Key('view_invoice_button')), findsOneWidget);
      expect(find.byKey(const Key('done_button')), findsOneWidget);

      // Tap Done to dismiss
      await tester.tap(find.byKey(const Key('done_button')));
      await tester.pumpAndSettle();
      expect(find.text('Open POS'), findsOneWidget);
    });

    testWidgets(
        '2. Double-tap protection prevents duplicate sale submission while processing',
        (tester) async {
      final completer = Completer<void>();
      repository.inFlightCompleter = completer;

      await tester.pumpWidget(buildTestHost());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open_pos_dialog')));
      await tester.pumpAndSettle();

      final initialStock = notifier.inventorySummaries.first.jaipurFinishedStock;
      final initialSalesCount = notifier.sales.length;

      await tester.enterText(
          find.byKey(const Key('customer_name_field')), 'Amit Sharma');
      await tester.enterText(
          find.byKey(const Key('customer_phone_field')), '9876543210');
      await tester.enterText(find.byKey(const Key('quantity_field')), '2');
      await tester.pump();

      final submitBtn =
          find.byKey(const Key('complete_sale_send_whatsapp_button'));

      // Initial tap triggers sale submission
      await tester.tap(submitBtn);
      await tester.pump();

      // Verify button enters disabled processing state with progress indicator
      expect(find.text('Processing...'), findsOneWidget);
      final elevatedButton = tester.widget<ElevatedButton>(submitBtn);
      expect(elevatedButton.onPressed, isNull);

      // Attempt second tap while in-flight
      await tester.tap(submitBtn, warnIfMissed: false);
      await tester.pump();

      // Release backend sale completion
      completer.complete();
      await tester.pumpAndSettle();

      // Verify sale recorded strictly ONCE, not duplicated
      expect(notifier.sales.length, initialSalesCount + 1);
      final finalStock =
          notifier.inventorySummaries.first.jaipurFinishedStock;
      expect(finalStock, initialStock - 2);
    });

    testWidgets(
        '3. WhatsApp failure/cancellation preserves saved bill and presents retry action',
        (tester) async {
      // Simulate WhatsApp launch failure
      Future<bool> failingLauncher(Uri uri) async => false;

      await tester.pumpWidget(buildTestHost(customLauncher: failingLauncher));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open_pos_dialog')));
      await tester.pumpAndSettle();

      final initialStock = notifier.inventorySummaries.first.jaipurFinishedStock;
      final initialSalesCount = notifier.sales.length;

      await tester.enterText(
          find.byKey(const Key('customer_name_field')), 'Sunil Verma');
      await tester.enterText(
          find.byKey(const Key('customer_phone_field')), '9876543210');
      await tester.enterText(find.byKey(const Key('quantity_field')), '1');
      await tester.pump();

      final submitBtn =
          find.byKey(const Key('complete_sale_send_whatsapp_button'));
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // 1. The sale IS preserved in database/state even though WhatsApp failed!
      expect(notifier.sales.length, initialSalesCount + 1);
      expect(
          notifier.inventorySummaries.first.jaipurFinishedStock, initialStock - 1);

      // 2. Completion UI shows fallback notice and retry button
      expect(find.text('Sale Completed!'), findsOneWidget);
      expect(find.text('WhatsApp Handoff Notice'), findsOneWidget);
      expect(find.byKey(const Key('retry_whatsapp_button')), findsOneWidget);
    });

    testWidgets(
        '4. Retry WhatsApp delivers message without duplicate sale or second stock deduction',
        (tester) async {
      bool shouldFailWhatsApp = true;
      Future<bool> retryLauncher(Uri uri) async {
        launchedUris.add(uri);
        return !shouldFailWhatsApp;
      }

      await tester.pumpWidget(buildTestHost(customLauncher: retryLauncher));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open_pos_dialog')));
      await tester.pumpAndSettle();

      final initialStock = notifier.inventorySummaries.first.jaipurFinishedStock;
      final initialSalesCount = notifier.sales.length;

      await tester.enterText(
          find.byKey(const Key('customer_name_field')), 'Pooja Gupta');
      await tester.enterText(
          find.byKey(const Key('customer_phone_field')), '9876543210');
      await tester.enterText(find.byKey(const Key('quantity_field')), '4');
      await tester.pump();

      // Initial submit -> first attempt fails WhatsApp
      await tester.tap(find.byKey(const Key('complete_sale_send_whatsapp_button')));
      await tester.pumpAndSettle();

      expect(notifier.sales.length, initialSalesCount + 1);
      final committedSaleId = notifier.sales.first.id;
      expect(
          notifier.inventorySummaries.first.jaipurFinishedStock, initialStock - 4);
      expect(find.text('WhatsApp Handoff Notice'), findsOneWidget);

      // Enable WhatsApp to succeed on retry
      shouldFailWhatsApp = false;

      // Tap Retry WhatsApp
      final retryBtn = find.byKey(const Key('retry_whatsapp_button'));
      expect(retryBtn, findsOneWidget);
      await tester.tap(retryBtn);
      await tester.pumpAndSettle();

      // 1. NO new sale created (count remains initial + 1)
      expect(notifier.sales.length, initialSalesCount + 1);
      expect(notifier.sales.first.id, committedSaleId);

      // 2. NO additional stock deducted (remains initialStock - 4)
      expect(
          notifier.inventorySummaries.first.jaipurFinishedStock, initialStock - 4);

      // 3. WhatsApp retry succeeded
      expect(find.text('WhatsApp Handoff Successful'), findsOneWidget);
    });
  });
}
