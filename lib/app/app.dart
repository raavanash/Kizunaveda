import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';
import '../features/auth/data/repositories/supabase_auth_repository.dart';
import '../features/auth/data/services/local_session_storage.dart';
import '../features/auth/domain/repositories/auth_repository.dart';
import '../features/auth/presentation/controllers/auth_notifier.dart';
import '../features/auth/presentation/screens/auth_gate.dart';
import '../features/inventory/data/repositories/supabase_inventory_repository.dart';
import '../features/inventory/domain/repositories/inventory_repository.dart';
import '../features/inventory/presentation/controllers/inventory_notifier.dart';
import 'providers/inventory_provider.dart';
import 'routes/app_routes.dart';
import 'theme/app_theme.dart';

/// Root Widget for Kizuna Veda Mobile App.
class KizunaVedaApp extends StatefulWidget {
  final IAuthRepository? authRepository;
  final IInventoryRepository? inventoryRepository;

  const KizunaVedaApp({
    super.key,
    this.authRepository,
    this.inventoryRepository,
  });

  @override
  State<KizunaVedaApp> createState() => _KizunaVedaAppState();
}

class _KizunaVedaAppState extends State<KizunaVedaApp> {
  late final IAuthRepository _authRepository;
  late final AuthNotifier _authNotifier;

  late final IInventoryRepository _inventoryRepository;
  late final InventoryNotifier _inventoryNotifier;

  @override
  void initState() {
    super.initState();
    _authRepository = widget.authRepository ??
        SupabaseAuthRepository(
          sessionStorage: LocalSessionStorage(),
        );
    _authNotifier = AuthNotifier(authRepository: _authRepository);

    _inventoryRepository =
        widget.inventoryRepository ?? SupabaseInventoryRepository();
    _inventoryNotifier = InventoryNotifier(repository: _inventoryRepository);

    _authNotifier.addListener(() {
      if (_authNotifier.isAuthenticated) {
        _inventoryNotifier.loadInventoryData();
      }
    });
  }

  @override
  void dispose() {
    _inventoryNotifier.dispose();
    _authNotifier.dispose();
    final repo = _authRepository;
    if (widget.authRepository == null && repo is SupabaseAuthRepository) {
      repo.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InventoryProvider(
      notifier: _inventoryNotifier,
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        routes: AppRoutes.routes,
        home: AuthGate(authNotifier: _authNotifier),
      ),
    );
  }
}
