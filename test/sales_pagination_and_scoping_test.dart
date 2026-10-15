import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kizuna_veda/app/providers/inventory_provider.dart';
import 'package:kizuna_veda/core/constants/app_constants.dart';
import 'package:kizuna_veda/features/inventory/data/repositories/unconnected_inventory_repository.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/location.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/product.dart';
import 'package:kizuna_veda/features/inventory/domain/entities/sale.dart';
import 'package:kizuna_veda/features/inventory/presentation/controllers/inventory_notifier.dart';
import 'package:kizuna_veda/features/sales/presentation/screens/dedicated_sales_view.dart';

class PaginatedMockInventoryRepository extends UnconnectedInventoryRepository {
  final List<Sale> allMockSales = [];
  bool shouldThrowError = false;
  String? lastQueriedLocationId;
  int? lastQueriedLimit;
  int? lastQueriedOffset;
  int getSalesCallCount = 0;

  void populateSales({
    required int neemranaCount,
    required int jaipurCount,
  }) {
    allMockSales.clear();
    final now = DateTime.now();

    for (int i = 0; i < neemranaCount; i++) {
      allMockSales.add(
        Sale(
          id: 'neemrana-sale-$i',
          billNumber: 'N-BILL-${1000 + i}',
          productId: 'prod-tulsi',
          quantity: 2,
          totalAmount: 200.0,
          paymentMethod: 'CASH',
          soldAt: now.subtract(Duration(minutes: i * 10)),
          createdAt: now.subtract(Duration(minutes: i * 10)),
          locationId: LocationConstants.neemranaId,
          customerName: 'Neemrana Customer $i',
          customerPhone: '98765432${(10 + i).toString().padLeft(2, '0')}',
        ),
      );
    }

    for (int i = 0; i < jaipurCount; i++) {
      allMockSales.add(
        Sale(
          id: 'jaipur-sale-$i',
          billNumber: 'J-BILL-${2000 + i}',
          productId: 'prod-almond',
          quantity: 1,
          totalAmount: 450.0,
          paymentMethod: 'UPI',
          soldAt: now.subtract(Duration(minutes: (i * 10) + 5)),
          createdAt: now.subtract(Duration(minutes: (i * 10) + 5)),
          locationId: LocationConstants.jaipurId,
          customerName: 'Jaipur Customer $i',
          customerPhone: '91234567${(10 + i).toString().padLeft(2, '0')}',
        ),
      );
    }

    // Sort by soldAt descending (newest first)
    allMockSales.sort((a, b) => b.soldAt.compareTo(a.soldAt));
  }

  @override
  Future<List<Location>> getLocations() async {
    final now = DateTime.now();
    return [
      Location(
        id: LocationConstants.neemranaId,
        code: 'NEEMRANA',
        name: 'Neemrana Outlet',
        locationType: 'RETAIL',
        createdAt: now,
      ),
      Location(
        id: LocationConstants.jaipurId,
        code: 'JAIPUR',
        name: 'Jaipur Outlet',
        locationType: 'RETAIL',
        createdAt: now,
      ),
    ];
  }

  @override
  Future<List<Product>> getProducts() async {
    final now = DateTime.now();
    return [
      Product(
        id: 'prod-tulsi',
        name: 'Tulsi Ark',
        packageSize: '50ml',
        sku: 'TUL-50',
        standardSellingPrice: 100.0,
        purchaseCost: 45.0,
        active: true,
        createdAt: now,
      ),
      Product(
        id: 'prod-almond',
        name: 'Mamra Almonds',
        packageSize: '500g',
        sku: 'ALM-500',
        standardSellingPrice: 450.0,
        purchaseCost: 320.0,
        active: true,
        createdAt: now,
      ),
    ];
  }

  @override
  Future<List<Sale>> getSales({
    int limit = 50,
    int offset = 0,
    String? locationId,
  }) async {
    getSalesCallCount++;
    lastQueriedLimit = limit;
    lastQueriedOffset = offset;
    lastQueriedLocationId = locationId;

    if (shouldThrowError) {
      throw Exception('Database connection timeout during sales pagination');
    }

    Iterable<Sale> filtered = allMockSales;
    if (locationId != null) {
      filtered = filtered.where((s) => s.locationId == locationId);
    }

    final list = filtered.toList();
    if (offset >= list.length) {
      return [];
    }
    final end = (offset + limit < list.length) ? offset + limit : list.length;
    return list.sublist(offset, end);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('REP-001 Server-Side Sales Pagination & Location Scoping Tests', () {
    late PaginatedMockInventoryRepository repository;
    late InventoryNotifier notifier;

    setUp(() {
      repository = PaginatedMockInventoryRepository();
      notifier = InventoryNotifier(repository: repository);
    });

    test('1. Multiple pages: Loads 50 per page and traverses sequential pages without record loss', () async {
      // 120 total sales (60 Neemrana + 60 Jaipur)
      repository.populateSales(neemranaCount: 60, jaipurCount: 60);
      repository.getSalesCallCount = 0;

      // Initial load: loads first page of 50
      await notifier.loadInventoryData();
      expect(repository.getSalesCallCount, 1);
      expect(repository.lastQueriedLimit, 50);
      expect(repository.lastQueriedOffset, 0);
      expect(notifier.sales.length, 50);
      expect(notifier.hasMoreSales, true);
      expect(notifier.isLoadingMoreSales, false);
      expect(notifier.salesPaginationError, isNull);

      // Load page 2 (offset: 50, limit: 50)
      final page2Success = await notifier.loadMoreSales();
      expect(page2Success, true);
      expect(repository.getSalesCallCount, 2);
      expect(repository.lastQueriedLimit, 50);
      expect(repository.lastQueriedOffset, 50);
      expect(notifier.sales.length, 100);
      expect(notifier.hasMoreSales, true);

      // Load page 3 (offset: 100, limit: 50) -> returns remaining 20 records
      final page3Success = await notifier.loadMoreSales();
      expect(page3Success, true);
      expect(repository.getSalesCallCount, 3);
      expect(repository.lastQueriedLimit, 50);
      expect(repository.lastQueriedOffset, 100);
      expect(notifier.sales.length, 120);
      // Since 20 < 50 (page size), hasMoreSales is now false
      expect(notifier.hasMoreSales, false);

      // Subsequent call does nothing because hasMoreSales is false
      final page4Success = await notifier.loadMoreSales();
      expect(page4Success, false);
      expect(repository.getSalesCallCount, 3); // no new query sent
      expect(notifier.sales.length, 120);
    });

    test('2. No duplicate records: Deduplicates records when overlap occurs during paging', () async {
      repository.populateSales(neemranaCount: 40, jaipurCount: 20); // 60 total
      await notifier.loadInventoryData();
      expect(notifier.sales.length, 50);

      // Inject a local sale that has an ID matching a server-side record in page 2
      final duplicateSale = repository.allMockSales[52];
      notifier.sales.add(duplicateSale);
      expect(notifier.sales.length, 51);

      // Now load page 2
      await notifier.loadMoreSales();

      // Total records in repository was 60.
      // Every ID in notifier.sales must be unique
      final ids = notifier.sales.map((s) => s.id).toList();
      final uniqueIds = ids.toSet();
      expect(ids.length, uniqueIds.length, reason: 'No duplicate sales should exist after pagination');
      expect(notifier.sales.length, 60);
    });

    test('3. Store scoping: Scopes sales query to Neemrana or Jaipur strictly', () async {
      repository.populateSales(neemranaCount: 30, jaipurCount: 30);

      // Query Neemrana explicitly
      await notifier.refreshSales(locationId: LocationConstants.neemranaId);
      expect(repository.lastQueriedLocationId, LocationConstants.neemranaId);
      expect(notifier.sales.length, 30);
      expect(notifier.sales.every((s) => s.locationId == LocationConstants.neemranaId), true);
      expect(notifier.hasMoreSales, false); // 30 < 50

      // Query Jaipur explicitly
      await notifier.refreshSales(locationId: LocationConstants.jaipurId);
      expect(repository.lastQueriedLocationId, LocationConstants.jaipurId);
      expect(notifier.sales.length, 30);
      expect(notifier.sales.every((s) => s.locationId == LocationConstants.jaipurId), true);
      expect(notifier.hasMoreSales, false); // 30 < 50

      // Query All (Owner overview with locationId == null)
      await notifier.refreshSales(locationId: null);
      expect(repository.lastQueriedLocationId, isNull);
      expect(notifier.sales.length, 50);
      expect(notifier.hasMoreSales, true);
      // Load remaining 10 sales
      await notifier.loadMoreSales(locationId: null);
      expect(notifier.sales.length, 60);
      expect(notifier.hasMoreSales, false);
      expect(notifier.sales.any((s) => s.locationId == LocationConstants.neemranaId), true);
      expect(notifier.sales.any((s) => s.locationId == LocationConstants.jaipurId), true);
    });

    test('4. Empty results: Correctly sets flags when no sales exist or page ends exactly on boundary', () async {
      // 0 sales
      repository.populateSales(neemranaCount: 0, jaipurCount: 0);
      await notifier.loadInventoryData();
      expect(notifier.sales.isEmpty, true);
      expect(notifier.hasMoreSales, false);
      expect(notifier.isLoadingMoreSales, false);

      // Exactly 50 sales (boundary condition)
      repository.populateSales(neemranaCount: 25, jaipurCount: 25);
      await notifier.refreshSales();
      expect(notifier.sales.length, 50);
      expect(notifier.hasMoreSales, true); // 50 returned, might have more

      // Next page query returns empty list
      await notifier.loadMoreSales();
      expect(notifier.sales.length, 50);
      expect(notifier.hasMoreSales, false); // empty page marks end of history
    });

    test('5. Pagination errors & recovery: Retains loaded records on error and recovers on retry', () async {
      repository.populateSales(neemranaCount: 50, jaipurCount: 50); // 100 total
      await notifier.loadInventoryData();
      expect(notifier.sales.length, 50);
      expect(notifier.salesPaginationError, isNull);

      // Simulate network / server error on page 2
      repository.shouldThrowError = true;
      final failed = await notifier.loadMoreSales();
      expect(failed, false);
      expect(notifier.isLoadingMoreSales, false);
      expect(notifier.salesPaginationError, isNotNull);
      expect(notifier.salesPaginationError, contains('Database connection timeout'));
      // Critical check: page 1 sales must NOT be lost or wiped out!
      expect(notifier.sales.length, 50);

      // Recover: simulate network restored
      repository.shouldThrowError = false;
      final recovered = await notifier.loadMoreSales();
      expect(recovered, true);
      expect(notifier.salesPaginationError, isNull);
      expect(notifier.sales.length, 100);
      expect(notifier.hasMoreSales, true); // 50 items returned (full page)

      // Query again to reach end
      await notifier.loadMoreSales();
      expect(notifier.hasMoreSales, false);
      expect(notifier.sales.length, 100);
    });

    test('6. PostgREST range calculation: Inclusive range boundary check', () {
      // PostgREST header: Range: 0-49 gives 50 rows
      int offset = 0;
      int limit = 50;
      int to = offset + limit - 1;
      expect(to, 49);
      expect(to - offset + 1, 50);

      // Next page: Range: 50-99 gives 50 rows
      offset = 50;
      to = offset + limit - 1;
      expect(to, 99);
      expect(to - offset + 1, 50);
    });

    testWidgets('7. DedicatedSalesView UI: Displays paginated list, footer indicators, and triggers load more', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      repository.populateSales(neemranaCount: 3, jaipurCount: 3); // 6 total
      final testNotifier = InventoryNotifier(
        repository: repository,
        salesPageSize: 4,
      );
      await testNotifier.loadInventoryData();

      await tester.pumpWidget(
        MaterialApp(
          home: InventoryProvider(
            notifier: testNotifier,
            child: const Scaffold(
              body: DedicatedSalesView(role: UserRole.owner),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify page 1 rendered (4 bills)
      expect(find.text('4 Bills Listed'), findsOneWidget);
      expect(find.byKey(const Key('sales_load_more_btn')), findsOneWidget);

      // Tap "Load More Bills"
      await tester.tap(find.byKey(const Key('sales_load_more_btn')));
      await tester.pumpAndSettle();

      // Now all 6 bills listed
      expect(find.text('6 Bills Listed'), findsOneWidget);
      expect(testNotifier.sales.length, 6);

      // Reached end of history
      expect(find.byKey(const Key('sales_pagination_end')), findsOneWidget);
      expect(find.text('All records loaded (6 bills shown)'), findsOneWidget);
      expect(find.byKey(const Key('sales_load_more_btn')), findsNothing);
    });

    testWidgets('8. DedicatedSalesView UI: Shows retry button on pagination error and successfully recovers', (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      repository.populateSales(neemranaCount: 4, jaipurCount: 4); // 8 total
      final testNotifier = InventoryNotifier(
        repository: repository,
        salesPageSize: 4,
      );
      await testNotifier.loadInventoryData();

      await tester.pumpWidget(
        MaterialApp(
          home: InventoryProvider(
            notifier: testNotifier,
            child: const Scaffold(
              body: DedicatedSalesView(role: UserRole.owner),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger error on load more
      repository.shouldThrowError = true;
      await tester.tap(find.byKey(const Key('sales_load_more_btn')));
      await tester.pumpAndSettle();

      // Error UI visible with Retry button
      expect(find.byKey(const Key('sales_pagination_error')), findsOneWidget);
      expect(find.byKey(const Key('sales_pagination_retry_btn')), findsOneWidget);
      expect(find.text('4 Bills Listed'), findsOneWidget); // Previous records preserved!

      // Restore network and tap Retry
      repository.shouldThrowError = false;
      await tester.tap(find.byKey(const Key('sales_pagination_retry_btn')));
      await tester.pumpAndSettle();

      // Recovered successfully
      expect(find.byKey(const Key('sales_pagination_error')), findsNothing);
      expect(find.text('8 Bills Listed'), findsOneWidget);
    });
  });
}
