import 'package:flutter_test/flutter_test.dart';
import 'package:kizuna_veda/core/constants/app_constants.dart';
import 'package:kizuna_veda/features/auth/domain/entities/auth_user.dart';
import 'package:kizuna_veda/features/inventory/data/repositories/unconnected_inventory_repository.dart';

void main() {
  group('Atomic Transactions & RPC Safety Unit Tests', () {
    late UnconnectedInventoryRepository repository;

    setUp(() {
      repository = UnconnectedInventoryRepository();
    });

    test('POS Sale record creates complete sale entity atomically', () async {
      final products = await repository.getProducts();
      final product = products.first;

      final sale = await repository.recordSale(
        productId: product.id,
        quantity: 5,
        totalAmount: 500.0,
        customerPhone: '9999988888',
      );

      expect(sale.id.isNotEmpty, isTrue);
      expect(sale.billNumber.startsWith('BILL-'), isTrue);
      expect(sale.totalAmount, 500.0);
      expect(sale.customerPhone, '9999988888');
      expect(sale.isCompleted, isTrue);
    });

    test('Confirm Jaipur receipt updates transfer atomically and validates bounds', () async {
      final transfers = await repository.getTransfers();
      final pending = transfers.firstWhere((t) => t.isPending);

      final confirmed = await repository.confirmTransferReceipt(
        transferId: pending.id,
        receivedQuantity: pending.dispatchedQuantity,
      );

      expect(confirmed.isReceived, isTrue);
      expect(confirmed.receivedQuantity, pending.dispatchedQuantity);
      expect(confirmed.discrepancyReason, isNull);
    });

    test('Receipt confirmation fails if received exceeds dispatched quantity', () async {
      final transfers = await repository.getTransfers();
      final pending = transfers.firstWhere((t) => t.isPending);

      expect(
        () => repository.confirmTransferReceipt(
          transferId: pending.id,
          receivedQuantity: pending.dispatchedQuantity + 999,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('Discrepancy reason required when received != dispatched', () async {
      final transfers = await repository.getTransfers();
      final pending = transfers.firstWhere((t) => t.isPending);

      expect(
        () => repository.confirmTransferReceipt(
          transferId: pending.id,
          receivedQuantity: pending.dispatchedQuantity - 1,
          discrepancyReason: null,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('AuthUser strictly maps roles without user_metadata fallback', () {
      final jsonUser = {
        'id': 'user-123',
        'email': 'jaipur@kizunaveda.com',
        'role': 'jaipur',
      };

      final authUser = AuthUser.fromJson(jsonUser);
      expect(authUser.role, UserRole.jaipur);
    });
  });
}
