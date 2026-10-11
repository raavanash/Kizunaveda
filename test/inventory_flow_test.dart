import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kizuna_veda/app/providers/inventory_provider.dart';
import 'package:kizuna_veda/app/routes/app_routes.dart';
import 'package:kizuna_veda/features/auth/data/repositories/unconnected_auth_repository.dart';
import 'package:kizuna_veda/features/auth/data/services/local_session_storage.dart';
import 'package:kizuna_veda/features/auth/presentation/controllers/auth_notifier.dart';
import 'package:kizuna_veda/features/inventory/data/repositories/unconnected_inventory_repository.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/product.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/product_inventory_summary.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/stock_transfer.dart';
import 'package:kizuna_veda/features/inventory/presentation/controllers/inventory_notifier.dart';
import 'package:kizuna_veda/features/owner/presentation/screens/in_transit_stock_screen.dart';
import 'package:kizuna_veda/features/owner/presentation/screens/jaipur_stock_screen.dart';
import 'package:kizuna_veda/features/owner/presentation/screens/neemrana_stock_screen.dart';
import 'package:kizuna_veda/features/owner/presentation/screens/owner_home_screen.dart';

void main() {
  group('V1 Inventory Flow Business Calculations & Location Separation', () {
    test('Exact calculation test: Packed=1000, Dispatched=980, Received=975, Sold=300', () {
      final product = Product(
        id: 'prod-spec-1',
        name: 'Tulsi Extract',
        packageSize: '100g',
        sku: 'TULSI-100G',
        createdAt: DateTime.now(),
      );

      final summary = ProductInventorySummary(
        product: product,
        totalPacked: 1000,
        totalDispatched: 980,
        totalReceived: 975,
        totalSold: 300,
      );

      expect(summary.neemranaFinishedStock, 20); // 1000 - 980
      expect(summary.jaipurFinishedStock, 675); // 975 - 300
      expect(summary.transferDiscrepancy, 5); // 980 - 975
    });

    test('Neemrana and Jaipur inventory remain strictly separate', () {
      final product = Product(
        id: 'prod-sep-1',
        name: 'Neem Powder',
        packageSize: '250g',
        sku: 'NEEM-250G',
        createdAt: DateTime.now(),
      );

      // Scenario: Neemrana packs 500, dispatches 300. Jaipur has received 0, sold 0.
      final summaryBeforeReceipt = ProductInventorySummary(
        product: product,
        totalPacked: 500,
        totalDispatched: 300,
        totalReceived: 0,
        totalSold: 0,
      );

      expect(summaryBeforeReceipt.neemranaFinishedStock, 200); // 500 - 300
      expect(summaryBeforeReceipt.jaipurFinishedStock, 0); // Not received yet!
      expect(summaryBeforeReceipt.transferDiscrepancy, 300); // Pending/discrepancy
    });

    test('Raw material stock remains independent from finished-product stock', () async {
      final repository = UnconnectedInventoryRepository();
      final notifier = InventoryNotifier(repository: repository);
      await notifier.loadInventoryData();

      final rawMats = notifier.rawMaterials;
      final rawReceipts = notifier.rawMaterialReceipts;

      expect(rawMats.isNotEmpty, isTrue);
      expect(rawReceipts.isNotEmpty, isTrue);

      final firstRawId = rawMats.first.id;
      final totalRawReceived = rawReceipts
          .where((r) => r.rawMaterialId == firstRawId)
          .fold(0.0, (sum, item) => sum + item.quantity);

      expect(totalRawReceived, 500.0);
      notifier.dispose();
    });
  });

  group('Inventory Operations & Domain Validation Rules', () {
    late UnconnectedInventoryRepository repository;
    late InventoryNotifier notifier;

    setUp(() {
      repository = UnconnectedInventoryRepository();
      notifier = InventoryNotifier(repository: repository);
    });

    tearDown(() {
      notifier.dispose();
    });

    test('Add Product increases product list count', () async {
      final initialCount = notifier.products.length;

      final success = await notifier.addProduct(
        name: 'Brahmi Churna',
        packageSize: '100g',
        sku: 'KV-BRA-100',
      );

      expect(success, isTrue);
      expect(notifier.products.length, initialCount + 1);
    });

    test('Add Raw Material and Raw Material Receipt succeeds at Neemrana', () async {
      final successMat = await notifier.addRawMaterial(
        name: 'Guduchi Stem Powder',
        unitOfMeasure: 'KG',
      );
      expect(successMat, isTrue);

      final newMat = notifier.rawMaterials.firstWhere((r) => r.name == 'Guduchi Stem Powder');
      final successReceipt = await notifier.addRawMaterialReceipt(
        rawMaterialId: newMat.id,
        quantity: 100.0,
        cost: 4500.0,
        supplierReference: 'SUP-GUD-01',
      );

      expect(successReceipt, isTrue);
    });

    test('Jaipur cannot receive more than dispatched quantity', () async {
      final product = notifier.products.first;

      final transfer = await repository.createTransfer(
        productId: product.id,
        dispatchedQuantity: 50,
      );

      // Attempting to receive 60 (> 50) must throw exception
      expect(
        () => repository.confirmTransferReceipt(
          transferId: transfer.id,
          receivedQuantity: 60,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('Discrepancy reason is required when received != dispatched', () async {
      final product = notifier.products.first;

      final transfer = await repository.createTransfer(
        productId: product.id,
        dispatchedQuantity: 50,
      );

      // Attempting to confirm receipt with received=45 and null discrepancyReason must fail
      expect(
        () => repository.confirmTransferReceipt(
          transferId: transfer.id,
          receivedQuantity: 45,
          discrepancyReason: null,
        ),
        throwsA(isA<Exception>()),
      );

      // Confirming with valid discrepancy reason succeeds
      final confirmed = await repository.confirmTransferReceipt(
        transferId: transfer.id,
        receivedQuantity: 45,
        discrepancyReason: '5 packets damaged in transit',
      );
      expect(confirmed.isReceived, isTrue);
      expect(confirmed.discrepancy, 5);
      expect(confirmed.status, TransferStatus.discrepancy);
    });

    test('Transfer remains pending until receipt is confirmed', () async {
      final product = notifier.products.first;

      final transfer = await repository.createTransfer(
        productId: product.id,
        dispatchedQuantity: 100,
      );

      expect(transfer.isPending, isTrue);
      expect(transfer.isReceived, isFalse);
      expect(transfer.receivedQuantity, isNull);
      expect(transfer.status, TransferStatus.dispatched);
    });

    test('Jaipur sale cannot exceed available Jaipur finished stock', () async {
      await notifier.loadInventoryData();
      final summary = notifier.inventorySummaries.first;
      final availableStock = summary.jaipurFinishedStock;

      // Attempting to sell more than available Jaipur stock fails validation
      final createdSale = await notifier.recordSale(
        productId: summary.product.id,
        quantity: availableStock + 999,
      );

      expect(createdSale, isNull);
      expect(notifier.errorMessage, contains('Cannot record sale'));
    });

    test('Neemrana dispatch cannot exceed available Neemrana finished stock', () async {
      await notifier.loadInventoryData();
      final summary = notifier.inventorySummaries.first;
      final availableNeemranaStock = summary.neemranaFinishedStock;

      // Attempting to dispatch more than available Neemrana stock fails validation
      final success = await notifier.createTransfer(
        productId: summary.product.id,
        dispatchedQuantity: availableNeemranaStock + 999,
      );

      expect(success, isFalse);
      expect(notifier.errorMessage, contains('Cannot dispatch'));
    });
  });

  group('Inventory Flow Widgets & Screen UI Tests', () {
    late UnconnectedInventoryRepository repository;
    late InventoryNotifier notifier;

    setUp(() {
      repository = UnconnectedInventoryRepository();
      notifier = InventoryNotifier(repository: repository);
    });

    tearDown(() {
      notifier.dispose();
    });

    Widget buildTestApp(Widget screen) {
      return InventoryProvider(
        notifier: notifier,
        child: MaterialApp(
          routes: AppRoutes.routes,
          home: screen,
        ),
      );
    }

    testWidgets('NeemranaStockScreen displays Neemrana location headers and buttons',
        (tester) async {
      await tester.pumpWidget(buildTestApp(const NeemranaStockScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Neemrana Store & Billing'), findsWidgets);
      expect(find.text('Add Product'), findsOneWidget);
      expect(find.text('Stock Entry / Edit'), findsOneWidget);
      expect(find.text('Create Bill'), findsOneWidget);
      expect(find.text('Neemrana Store Performance'), findsOneWidget);
    });

    testWidgets('JaipurStockScreen displays Jaipur retail headers and confirmation actions',
        (tester) async {
      await tester.pumpWidget(buildTestApp(const JaipurStockScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Jaipur Store & Billing'), findsWidgets);
      expect(find.text('Jaipur Store Performance'), findsOneWidget);
      expect(find.text('Stock Entry / Edit'), findsOneWidget);
      expect(find.text('Record POS Sale'), findsOneWidget);
    });

    testWidgets('InTransitStockScreen displays transfer status badges and metrics',
        (tester) async {
      await tester.pumpWidget(buildTestApp(const InTransitStockScreen()));
      await tester.pumpAndSettle();

      expect(find.text('In-Transit Stock & Discrepancies'), findsWidgets);
      expect(find.text('Inter-Unit Transfer Control'), findsOneWidget);
      expect(find.text('Pending Receipt'), findsWidgets);
    });

    testWidgets('OwnerHomeScreen displays product inventory summary with location separation',
        (tester) async {
      final authRepo =
          UnconnectedAuthRepository(sessionStorage: LocalSessionStorage());
      final authNotifier = AuthNotifier(authRepository: authRepo);

      await tester.pumpWidget(
        InventoryProvider(
          notifier: notifier,
          child: MaterialApp(
            routes: AppRoutes.routes,
            home: OwnerHomeScreen(authNotifier: authNotifier),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final summaryHeader = find.text('Combined Product Inventory');
      expect(summaryHeader, findsOneWidget);
      await tester.ensureVisible(summaryHeader);
      expect(find.text('Neemrana'), findsWidgets);
      expect(find.text('Jaipur'), findsWidgets);

      authNotifier.dispose();
      authRepo.dispose();
    });

  });
}
