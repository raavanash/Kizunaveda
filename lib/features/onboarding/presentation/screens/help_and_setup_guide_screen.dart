import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/widgets/kizuna_card.dart';
import '../../data/services/onboarding_storage.dart';
import 'role_onboarding_dialog.dart';

/// Persistent Help & Setup Guide Screen:
/// Accessible from More & Settings and Dashboard.
/// Provides role-specific step-by-step instructions, stock & sales rules,
/// troubleshooting FAQ, direct task navigation shortcuts, and tour restarting.
class HelpAndSetupGuideScreen extends StatelessWidget {
  final UserRole role;
  final String? userId;
  final void Function(int tabIndex)? onNavigateToTab;
  final VoidCallback? onOpenNewSale;

  const HelpAndSetupGuideScreen({
    super.key,
    required this.role,
    this.userId,
    this.onNavigateToTab,
    this.onOpenNewSale,
  });

  /// Navigate helper
  static Future<void> navigateTo(
    BuildContext context, {
    required UserRole role,
    String? userId,
    void Function(int tabIndex)? onNavigateToTab,
    VoidCallback? onOpenNewSale,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HelpAndSetupGuideScreen(
          role: role,
          userId: userId,
          onNavigateToTab: onNavigateToTab,
          onOpenNewSale: onOpenNewSale,
        ),
      ),
    );
  }

  Color get _themeColor {
    switch (role) {
      case UserRole.neemrana:
        return AppColors.roleNeemrana;
      case UserRole.jaipur:
        return AppColors.roleJaipur;
      case UserRole.owner:
        return AppColors.roleOwner;
    }
  }

  void _restartTour(BuildContext context) async {
    if (userId != null && userId!.isNotEmpty) {
      await OnboardingStorage.instance.reset(userId!);
    }
    if (context.mounted) {
      RoleOnboardingDialog.show(
        context,
        role: role,
        onNavigateToTab: onNavigateToTab,
        onOpenNewSale: onOpenNewSale,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Help & Setup Guide'),
        backgroundColor: _themeColor,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Card with Role Badge and Restart Tour
              KizunaCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: _themeColor.withValues(alpha: 0.15),
                          child: Icon(
                            role == UserRole.owner
                                ? Icons.admin_panel_settings_rounded
                                : Icons.storefront_rounded,
                            color: _themeColor,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${role.displayName} Guide',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _getRoleSummary(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        key: const Key('btn_restart_tour'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _themeColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(Icons.replay_rounded, size: 18),
                        label: const Text(
                          'Restart Guided Tour',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => _restartTour(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Quick Actions / Shortcuts
              Text(
                'Direct Task Shortcuts',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildShortcutButton(
                      context,
                      key: const Key('shortcut_dashboard'),
                      icon: Icons.dashboard_rounded,
                      label: 'Dashboard',
                      onTap: () {
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        }
                        onNavigateToTab?.call(0);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildShortcutButton(
                      context,
                      key: const Key('shortcut_inventory'),
                      icon: Icons.inventory_2_rounded,
                      label: 'Inventory',
                      onTap: () {
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        }
                        onNavigateToTab?.call(2);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildShortcutButton(
                      context,
                      key: const Key('shortcut_new_sale'),
                      icon: Icons.add_shopping_cart_rounded,
                      label: 'New Sale',
                      onTap: () {
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        }
                        onOpenNewSale?.call();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildShortcutButton(
                      context,
                      key: const Key('shortcut_sales_history'),
                      icon: Icons.receipt_long_rounded,
                      label: 'Sales History',
                      onTap: () {
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        }
                        onNavigateToTab?.call(1);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Core Operational Workflows
              Text(
                'Core Operational Workflows',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
              ),
              const SizedBox(height: 8),
              ..._buildWorkflowCards(),
              const SizedBox(height: 20),

              // Troubleshooting & FAQ
              Text(
                'Troubleshooting & FAQs',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
              ),
              const SizedBox(height: 8),
              _buildFaqSection(),
              const SizedBox(height: 20),

              // Policy & Compliance Notice Card
              Container(
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueGrey.shade100),
                ),
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.verified_user_rounded,
                        color: Colors.blueGrey, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Audit & Security Standard',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.blueGrey,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'All sales transactions and stock corrections are enforced by secure Supabase server RPCs with atomic ACID isolation. Direct manual table edits are strictly prohibited. Retail billing is configured without GST.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
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

  String _getRoleSummary() {
    switch (role) {
      case UserRole.owner:
        return 'Executive monitoring across Jaipur & Neemrana stores';
      case UserRole.neemrana:
        return 'Dedicated retail counter station for Neemrana outlet';
      case UserRole.jaipur:
        return 'Dedicated retail counter station for Jaipur outlet';
    }
  }

  Widget _buildShortcutButton(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      key: key,
      style: OutlinedButton.styleFrom(
        foregroundColor: _themeColor,
        side: BorderSide(color: _themeColor.withValues(alpha: 0.3)),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
      onPressed: onTap,
    );
  }

  List<Widget> _buildWorkflowCards() {
    if (role == UserRole.owner) {
      return [
        _buildGuideCard(
          title: '1. Executive Metrics & Sales Analysis',
          icon: Icons.analytics_rounded,
          points: [
            'Monitor total revenue, bill count, total packets sold, and Cash vs. UPI collections.',
            'Use date presets (Today, Last 7 Days, This Month, All Time) to observe performance trends.',
            'Filter by outlet: All Outlets, Jaipur Store, or Neemrana Store.',
            'Tap the Refresh button in the top bar anytime to fetch latest live figures.',
          ],
        ),
        _buildGuideCard(
          title: '2. Multi-Store Inventory Governance',
          icon: Icons.inventory_2_rounded,
          points: [
            'View combined finished goods as well as independent Jaipur and Neemrana packet counts.',
            'Combined stock is calculated from both stores and cannot be edited independently.',
            'Physical stock counts must be updated exclusively via approved Stock Adjustments.',
            'Audit reason codes are mandatory on every stock adjustment for full traceability.',
          ],
        ),
        _buildGuideCard(
          title: '3. Bill History & Verification',
          icon: Icons.receipt_long_rounded,
          points: [
            'Search and inspect completed sales across both stores in the Sales tab.',
            'Preview high-precision invoices with customer details and line items.',
            'Re-share formatted invoices to customer WhatsApp numbers directly.',
          ],
        ),
        _buildGuideCard(
          title: '4. User & Security Management',
          icon: Icons.manage_accounts_rounded,
          points: [
            'Access User Management under More & Settings to inspect staff accounts.',
            'Monitor inter-store dispatch and receipt under More → In-Transit Stock.',
          ],
        ),
      ];
    } else {
      final outletName = role == UserRole.neemrana ? 'Neemrana' : 'Jaipur';
      final otherStore = role == UserRole.neemrana ? 'Jaipur' : 'Neemrana';

      return [
        _buildGuideCard(
          title: '1. Confirm Store Identity ($outletName)',
          icon: Icons.storefront_rounded,
          points: [
            'Verify that the top app bar displays $outletName Store.',
            'Your transactions deduct stock exclusively from $outletName inventory.',
            'Operations performed here never modify $otherStore inventory.',
          ],
        ),
        _buildGuideCard(
          title: '2. Check & Update Packet Stock',
          icon: Icons.inventory_rounded,
          points: [
            'Open the Inventory tab to inspect available packets for Tulsi, Triphala, and Ashwa.',
            'To add physical stock or make corrections, tap "Stock In" or "Adjust Stock".',
            'Select an appropriate audit reason (e.g., Initial Stock, Restock, Audit Correction).',
            'Stock counts are validated live during POS checkout to prevent negative stock.',
          ],
        ),
        _buildGuideCard(
          title: '3. Create a New Retail Bill (POS)',
          icon: Icons.point_of_sale_rounded,
          points: [
            'Tap "+ New Sale" to launch the guided 3-stage billing workflow.',
            'Step 1 (Items): Choose product and enter packet quantity.',
            'Step 2 (Customer & Payment): Enter customer name, 10-digit WhatsApp number, and select Cash or UPI.',
            'Step 3 (Review): Check line items, unit rates, and grand total.',
          ],
        ),
        _buildGuideCard(
          title: '4. Complete Sale & Send WhatsApp',
          icon: Icons.mark_chat_read_rounded,
          points: [
            'On Step 3, tap "Complete Sale & Send WhatsApp".',
            'The sale is committed atomically to Supabase via secure RPC, and stock is deducted.',
            'WhatsApp automatically launches with a formatted invoice ready to send.',
            'If WhatsApp fails or is cancelled, the bill is already saved! Find it in Sales tab to retry.',
          ],
        ),
      ];
    }
  }

  Widget _buildGuideCard({
    required String title,
    required IconData icon,
    required List<String> points,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: KizunaCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: _themeColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...points.map((point) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Icon(
                          Icons.circle,
                          size: 6,
                          color: _themeColor.withValues(alpha: 0.8),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          point,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade800,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildFaqSection() {
    return Column(
      children: [
        _buildFaqItem(
          question: 'Why are dashboard metrics showing zero?',
          answer:
              'Check your selected date preset. If "Today" has no completed sales, switch the filter to "This Month" or "All Time". Also verify your outlet filter and tap the Refresh button in the top bar.',
        ),
        _buildFaqItem(
          question: 'What if WhatsApp sharing fails or is cancelled?',
          answer:
              'Do not re-enter the bill! Once you tap "Complete Sale", the sale is already safely recorded in Supabase, and stock is deducted. Simply navigate to the Sales tab, locate the bill, and tap "Share" to retry WhatsApp.',
        ),
        _buildFaqItem(
          question: 'How do Cash and UPI totals get calculated?',
          answer:
              'During Step 2 of POS billing, the payment method (Cash or UPI) is recorded with the sale. The Dashboard aggregates these separately and displays both individual collections and the total sum.',
        ),
        _buildFaqItem(
          question: 'How do I add or correct physical stock?',
          answer:
              'Go to the Inventory tab and tap "Stock In" or "Adjust Stock". Enter the physical packet count and choose a reason code. Combined stock in the Owner view is automatically recalculated as Jaipur stock + Neemrana stock.',
        ),
        _buildFaqItem(
          question: 'What happens if internet is temporarily lost?',
          answer:
              'Sale completion and stock adjustments require active connectivity to ensure immediate database consistency. If a network interruption occurs, the transaction rolls back cleanly so no corrupted records are saved.',
        ),
      ],
    );
  }

  Widget _buildFaqItem({required String question, required String answer}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: KizunaCard(
        padding: const EdgeInsets.all(12),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 8),
          title: Text(
            question,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          children: [
            Text(
              answer,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
