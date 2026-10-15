import 'package:flutter/material.dart';
import '../../../../app/routes/app_routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/widgets/kizuna_card.dart';
import '../../../auth/presentation/controllers/auth_notifier.dart';
import '../../../inventory/presentation/screens/unified_inventory_view.dart';
import '../../../onboarding/presentation/screens/help_and_setup_guide_screen.dart';

/// More & Settings Tab inspired by Vyapar:
/// Clean access to user profile, store settings, user management (for owner),
/// system connectivity status, help & setup guide, and logout.
class MoreSettingsView extends StatelessWidget {
  final UserRole role;
  final AuthNotifier authNotifier;
  final VoidCallback? onOpenHelpGuide;

  const MoreSettingsView({
    super.key,
    required this.role,
    required this.authNotifier,
    this.onOpenHelpGuide,
  });

  @override
  Widget build(BuildContext context) {
    final user = authNotifier.currentUser;
    final primaryColor = role == UserRole.neemrana
        ? AppColors.roleNeemrana
        : (role == UserRole.jaipur
            ? AppColors.roleJaipur
            : AppColors.roleOwner);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('More & Settings'),
        backgroundColor: primaryColor,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // User Profile Header Card
              KizunaCard(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: primaryColor.withValues(alpha: 0.15),
                      child: Icon(
                        role == UserRole.owner
                            ? Icons.admin_panel_settings_rounded
                            : Icons.person_rounded,
                        color: primaryColor,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.fullName ?? user?.email ?? 'Authorized Staff',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user?.email ?? '',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: primaryColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              role.displayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Administration Section (Owner Only)
              if (role == UserRole.owner) ...[
                Text(
                  'Administration & Governance',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                      ),
                ),
                const SizedBox(height: 8),
                KizunaCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.roleOwner.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.manage_accounts_rounded,
                              color: AppColors.roleOwner),
                        ),
                        title: const Text('User Management & Security',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: const Text(
                            'Manage authorized staff and role access'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () =>
                            AppRoutes.navigateToUserManagement(context),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.local_shipping_rounded,
                              color: Colors.blue),
                        ),
                        title: const Text('In-Transit Stock Manifests (Archived)',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle:
                            const Text('Historical audit log (transfers disabled)'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () =>
                            AppRoutes.navigateToInTransitStock(context),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        key: const Key('admin_product_pricing_tile'),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.price_change_rounded,
                              color: Colors.purple),
                        ),
                        title: const Text('Product Catalog & Pricing',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: const Text(
                            'Manage standard selling prices and purchase costs'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => Scaffold(
                                appBar: AppBar(
                                  title:
                                      const Text('Product Catalog & Pricing'),
                                ),
                                body: const UnifiedInventoryView(
                                  role: UserRole.owner,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        key: const Key('admin_product_master_tile'),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.teal.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.category_rounded,
                              color: Colors.teal),
                        ),
                        title: const Text('Product Master Management',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: const Text(
                            'Add dry fruits, edit SKUs, pack sizes & active status'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => AppRoutes.navigateToProductMaster(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Business Details Section
              Text(
                'Business Configuration',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
              ),
              const SizedBox(height: 8),
              KizunaCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    _buildConfigRow('Company', 'Kizuna Veda Enterprise'),
                    const SizedBox(height: 8),
                    _buildConfigRow(
                        'GST Mode',
                        AppConfig.isGstConfigured
                            ? 'Enabled (GSTIN: ${AppConfig.gstin})'
                            : 'Disabled (Retail Billing Mode)'),
                    const SizedBox(height: 8),
                    _buildConfigRow('Jaipur Store', 'Independent Retail'),
                    const SizedBox(height: 8),
                    _buildConfigRow('Neemrana Store', 'Independent Retail'),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Application Info & Logout
              KizunaCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.info_outline_rounded,
                          color: AppColors.primary),
                      title: const Text('App Version',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: const Text('v1.4 • High Precision Retail POS'),
                      trailing: const Text('Up to date',
                          style: TextStyle(color: Colors.green, fontSize: 12)),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      key: const Key('tile_help_guide'),
                      leading: const Icon(Icons.help_outline_rounded,
                          color: AppColors.primary),
                      title: const Text('Help & Setup Guide',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: const Text('Role instructions, workflows & FAQ'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        if (onOpenHelpGuide != null) {
                          onOpenHelpGuide!();
                        } else {
                          HelpAndSetupGuideScreen.navigateTo(
                            context,
                            role: role,
                            userId: authNotifier.currentUser?.id ?? role.name,
                          );
                        }
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.logout_rounded,
                          color: AppColors.error),
                      title: const Text('Logout Session',
                          style: TextStyle(
                            color: AppColors.error,
                            fontWeight: FontWeight.bold,
                          )),
                      subtitle: const Text('Sign out of this mobile device'),
                      onTap: () => _confirmLogout(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConfigRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        Text(value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to log out of Kizuna Veda?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              authNotifier.logout();
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}
