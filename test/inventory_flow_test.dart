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
import 'package:kizuna_veda/features/inventory/presentation/controllers/inventory_notifier.dart';
import 'package:kizuna_veda/features/owner/presentation/screens/in_transit_stock_screen.dart';
import 'package:kizuna_veda/features/owner/presentation/screens/jaipur_stock_screen.dart';
import 'package:kizuna_veda/features/owner/presentation/screens/neemrana_stock_screen.dart';
import 'package:kizuna_veda/features/owner/presentation/screens/owner_home_screen.dart';

void main() {
  group('V1 Inventory Flow Business Calculations & Location Separation', () {
    test('Independent store calculations: Packed=1000, NeemranaStockIn=200, NeemranaSold=300, JaipurStockIn=500, JaipurSold=150', () {
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
        totalNeemranaStockIn: 200,
        totalNeemranaSold: 300,
        totalJaipurStockIn: 500,
        totalJaipurSold: 150,
        totalDispatched: 0,
        totalReceived: 0,
      );

      expect(summary.neemranaFinishedStock, 900); // 1000 + 200 - 300
      expect(summary.jaipurFinishedStock, 350); // 500 - 150
      expect(summary.transferDiscrepancy, 0); // Transfers permanently disabled
    });

    test('Neemrana and Jaipur inventory remain strictly separate and independent', () {
      final product = Product(
        id: 'prod-sep-1',
        name: 'Neem Powder',
        packageSize: '250g',
        sku: 'NEEM-250G',
        createdAt: DateTime.now(),
      );

      final summary = ProductInventorySummary(
        product: product,
        totalPacked: 500,
        totalNeemranaStockIn: 50,
        totalNeemranaSold: 100,
        totalJaipurStockIn: 200,
        totalJaipurSold: 50,
        totalDispatched: 0,
        totalReceived: 0,
      );

      expect(summary.neemranaFinishedStock, 450); // 500 + 50 - 100
      expect(summary.jaipurFinishedStock, 150); // 200 - 50
      expect(summary.transferDiscrepancy, 0);
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

    test('Inter-store stock transfers are permanently disabled on repository', () async {
      final product = notifier.products.first;

      expect(
        () => repository.createTransfer(
          productId: product.id,
          dispatchedQuantity: 50,
        ),
        throwsA(isA<UnsupportedError>()),
      );

      expect(
        () => repository.confirmTransferReceipt(
          transferId: 'trans-1',
          receivedQuantity: 50,
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('Inter-store stock transfers are permanently disabled on notifier', () async {
      final product = notifier.products.first;

      final transferSuccess = await notifier.createTransfer(
        productId: product.id,
        dispatchedQuantity: 10,
      );
      expect(transferSuccess, isFalse);
      expect(
        notifier.errorMessage,
        contains('Inter-store stock transfers are permanently disabled'),
      );

      final receiptSuccess = await notifier.confirmTransferReceipt(
        transferId: 'trans-1',
        receivedQuantity: 10,
      );
      expect(receiptSuccess, isFalse);
      expect(
        notifier.errorMessage,
        contains('Inter-store stock transfers are permanently disabled'),
      );
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
      expect(find.text('Transfers Permanently Disabled'), findsOneWidget);
      expect(find.text('Inter-Unit Transfer Control (Archived)'), findsOneWidget);
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
