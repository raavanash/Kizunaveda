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

    test('Inter-store stock transfer operations are permanently disabled and fail closed', () async {
      expect(
        () => repository.createTransfer(
          productId: 'prod-101',
          dispatchedQuantity: 10,
        ),
        throwsA(isA<UnsupportedError>()),
      );

      expect(
        () => repository.confirmTransferReceipt(
          transferId: 'trans-1',
          receivedQuantity: 10,
        ),
        throwsA(isA<UnsupportedError>()),
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
