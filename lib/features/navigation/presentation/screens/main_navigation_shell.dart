import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../auth/presentation/controllers/auth_notifier.dart';
import '../../../dashboard/presentation/screens/vyapar_dashboard_view.dart';
import '../../../inventory/presentation/screens/unified_inventory_view.dart';
import '../../../more/presentation/screens/more_settings_view.dart';
import '../../../onboarding/data/services/onboarding_storage.dart';
import '../../../onboarding/presentation/screens/help_and_setup_guide_screen.dart';
import '../../../onboarding/presentation/screens/role_onboarding_dialog.dart';
import '../../../sales/presentation/screens/dedicated_sales_view.dart';
import '../../../sales/presentation/screens/guided_new_sale_screen.dart';

/// Centralized Navigation Shell inspired by Vyapar:
/// Provides bottom navigation across Dashboard, Sales, Inventory, and More,
/// eliminates back-and-forth navigation, preserves tab state via IndexedStack,
/// includes a prominent "+ New Sale" FAB that launches the guided sale workflow,
/// and automatically presents a role-tailored onboarding walkthrough for first-time users.
class MainNavigationShell extends StatefulWidget {
  final UserRole role;
  final AuthNotifier authNotifier;
  final int initialIndex;
  final bool autoShowOnboarding;

  const MainNavigationShell({
    super.key,
    required this.role,
    required this.authNotifier,
    this.initialIndex = 0,
    this.autoShowOnboarding = true,
  });

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    if (widget.autoShowOnboarding) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndShowOnboarding());
    }
  }

  Future<void> _checkAndShowOnboarding() async {
    final userId = widget.authNotifier.currentUser?.id ?? widget.role.name;
    final isDone = await OnboardingStorage.instance.isCompleted(userId);
    if (!isDone && mounted) {
      RoleOnboardingDialog.show(
        context,
        role: widget.role,
        onNavigateToTab: _onTabSelected,
        onOpenNewSale: _openNewSale,
        onOpenHelpGuide: _openHelpGuide,
        onFinish: () => OnboardingStorage.instance.markCompleted(userId),
      );
    }
  }

  void _openHelpGuide() {
    HelpAndSetupGuideScreen.navigateTo(
      context,
      role: widget.role,
      userId: widget.authNotifier.currentUser?.id ?? widget.role.name,
      onNavigateToTab: _onTabSelected,
      onOpenNewSale: _openNewSale,
    );
  }

  void _onTabSelected(int index) {
    if (_currentIndex != index) {
      setState(() => _currentIndex = index);
    }
  }

  void _openNewSale() async {
    final defaultLocation = widget.role == UserRole.neemrana
        ? LocationConstants.neemranaId
        : LocationConstants.jaipurId;

    final sale = await GuidedNewSaleScreen.navigateTo(
      context,
      initialLocationId: defaultLocation,
      role: widget.role,
    );

    // If sale completed, automatically switch to the Sales tab to view the bill
    if (sale != null && mounted) {
      setState(() => _currentIndex = 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.role == UserRole.neemrana
        ? AppColors.roleNeemrana
        : (widget.role == UserRole.jaipur
            ? AppColors.roleJaipur
            : AppColors.roleOwner);

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // Tab 0: Vyapar-Inspired Dashboard
          VyaparDashboardView(
            role: widget.role,
            authNotifier: widget.authNotifier,
            onNavigateToSales: () => _onTabSelected(1),
            onOpenHelpGuide: _openHelpGuide,
          ),
          // Tab 1: Dedicated Sales List & Bill History
          DedicatedSalesView(
            role: widget.role,
            authNotifier: widget.authNotifier,
          ),
          // Tab 2: Inventory & Store Stock On Hand
          UnifiedInventoryView(
            role: widget.role,
          ),
          // Tab 3: More & Settings
          MoreSettingsView(
            role: widget.role,
            authNotifier: widget.authNotifier,
            onOpenHelpGuide: _openHelpGuide,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('fab_new_sale'),
        backgroundColor: activeColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_shopping_cart_rounded),
        label: const Text('New Sale',
            style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: _openNewSale,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabSelected,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: activeColor,
        unselectedItemColor: Colors.grey.shade600,
        selectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_rounded),
            label: 'Sales',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.inventory_2_rounded),
            label: 'Inventory',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.more_horiz_rounded),
            label: 'More',
          ),
        ],
      ),
    );
  }
}
