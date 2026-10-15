import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';

enum OnboardingShortcutType {
  dashboard,
  inventory,
  pos,
  sales,
  help,
}

class OnboardingStep {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> bulletPoints;
  final String? shortcutLabel;
  final OnboardingShortcutType? shortcutType;

  const OnboardingStep({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.bulletPoints,
    this.shortcutLabel,
    this.shortcutType,
  });

  /// Generate steps tailored specifically for the authenticated user's role.
  static List<OnboardingStep> getStepsForRole(UserRole role) {
    switch (role) {
      case UserRole.owner:
        return const [
          OnboardingStep(
            title: 'Welcome to Owner Portal',
            subtitle:
                'Executive governance across Jaipur and Neemrana retail outlets.',
            icon: Icons.admin_panel_settings_rounded,
            bulletPoints: [
              'Complete multi-outlet oversight with live sales and inventory figures.',
              'Automated transaction handling through secure Supabase database RPCs.',
              'All sales and inventory changes must follow approved in-app workflows.',
              'Direct database mutations or unauthorized manual edits are strictly avoided.',
            ],
            shortcutLabel: 'Open Dashboard',
            shortcutType: OnboardingShortcutType.dashboard,
          ),
          OnboardingStep(
            title: 'Business Metrics & Analytics',
            subtitle:
                'Monitor revenue, completed bills, packets sold, and cash/UPI splits.',
            icon: Icons.analytics_rounded,
            bulletPoints: [
              'Dynamic date presets: Today, Last 7 Days, This Month, and All Time.',
              'Filter by outlet (All, Jaipur, Neemrana) to compare store performance.',
              'View Cash vs. UPI collections side-by-side with grand totals.',
              'Tap the refresh icon anytime in the top bar to update live figures.',
            ],
            shortcutLabel: 'Open Dashboard',
            shortcutType: OnboardingShortcutType.dashboard,
          ),
          OnboardingStep(
            title: 'Two Independent Store Inventories',
            subtitle:
                'Separate finished goods stock for Jaipur and Neemrana stores.',
            icon: Icons.inventory_2_rounded,
            bulletPoints: [
              'Combined stock is calculated from both stores, never edited independently.',
              'Physical stock counts are updated exclusively via approved Stock Adjustments.',
              'Neemrana and Jaipur retail stores maintain strictly independent inventories.',
            ],
            shortcutLabel: 'Open Inventory',
            shortcutType: OnboardingShortcutType.inventory,
          ),
          OnboardingStep(
            title: 'Bill History & Governance',
            subtitle:
                'Inspect completed sales, share bills, and govern staff credentials.',
            icon: Icons.receipt_long_rounded,
            bulletPoints: [
              'Search past bills by customer name or bill number in the Sales tab.',
              'View digital invoices or share formatted receipts via WhatsApp.',
              'Manage staff credentials and role permissions in More → User Management.',
              'Access the persistent Help Guide anytime from More & Settings.',
            ],
            shortcutLabel: 'View Sales History',
            shortcutType: OnboardingShortcutType.sales,
          ),
        ];

      case UserRole.neemrana:
        return const [
          OnboardingStep(
            title: 'Welcome to Neemrana Store',
            subtitle:
                'Dedicated retail counter station for Neemrana outlet staff.',
            icon: Icons.storefront_rounded,
            bulletPoints: [
              'Assigned Outlet: Neemrana Store (identified by the green theme).',
              'Sales recorded here deduct stock exclusively from Neemrana finished goods.',
              'Your sales and inventory updates never alter Jaipur stock or data.',
              'Keep your session active on this counter device during store hours.',
            ],
            shortcutLabel: 'Open Dashboard',
            shortcutType: OnboardingShortcutType.dashboard,
          ),
          OnboardingStep(
            title: 'Neemrana Inventory & Stock Count',
            subtitle:
                'Check on-hand finished goods and record physical adjustments.',
            icon: Icons.inventory_rounded,
            bulletPoints: [
              'Open Inventory to review available packets for Tulsi, Triphala, and Ashwa.',
              'Enter physical counts or corrections through the approved Stock In flow.',
              'Always specify an accurate adjustment reason for accountability.',
              'Stock counts display live on the POS screen to prevent stockouts.',
            ],
            shortcutLabel: 'Open Inventory',
            shortcutType: OnboardingShortcutType.inventory,
          ),
          OnboardingStep(
            title: 'Fast Guided New Sale (POS)',
            subtitle:
                'Mistake-free 3-step billing for quick customer turnaround.',
            icon: Icons.point_of_sale_rounded,
            bulletPoints: [
              'Tap "+ New Sale" to launch the guided retail billing workflow.',
              'Step 1 (Items): Pick product and packets; available stock is verified live.',
              'Step 2 (Customer & Pay): Enter name, 10-digit WhatsApp number, and Cash/UPI.',
              'Step 3 (Review): Check unit prices, line totals, and grand total.',
            ],
            shortcutLabel: 'Create New Sale',
            shortcutType: OnboardingShortcutType.pos,
          ),
          OnboardingStep(
            title: 'Complete Sale & WhatsApp Handoff',
            subtitle:
                'Save the sale once and deliver an instant digital invoice.',
            icon: Icons.mark_chat_read_rounded,
            bulletPoints: [
              'Tap "Complete Sale & Send WhatsApp" to commit via secure Supabase RPC.',
              'Neemrana stock is deducted exactly once with double-tap protection.',
              'WhatsApp automatically opens with a pre-formatted invoice for the customer.',
              'If WhatsApp is cancelled, the bill is safely stored in Sales history to retry.',
            ],
            shortcutLabel: 'View Sales History',
            shortcutType: OnboardingShortcutType.sales,
          ),
        ];

      case UserRole.jaipur:
        return const [
          OnboardingStep(
            title: 'Welcome to Jaipur Store',
            subtitle:
                'Dedicated retail billing station for Jaipur outlet staff.',
            icon: Icons.storefront_rounded,
            bulletPoints: [
              'Assigned Outlet: Jaipur Store (identified by the warm amber theme).',
              'Sales recorded here deduct stock exclusively from Jaipur finished goods.',
              'Your transactions never directly modify Neemrana store inventory.',
              'Perform daily retail sales and customer billing with speed and accuracy.',
            ],
            shortcutLabel: 'Open Dashboard',
            shortcutType: OnboardingShortcutType.dashboard,
          ),
          OnboardingStep(
            title: 'Jaipur Inventory & Stock Count',
            subtitle:
                'Check on-hand finished goods and maintain accurate packet counts.',
            icon: Icons.inventory_rounded,
            bulletPoints: [
              'Inspect live finished stock counts in the Inventory tab.',
              'Record physical stock additions or corrections through Stock Adjustment.',
              'Select an accurate reason code for every adjustment.',
              'Available stock is checked live during sale creation.',
            ],
            shortcutLabel: 'Open Inventory',
            shortcutType: OnboardingShortcutType.inventory,
          ),
          OnboardingStep(
            title: 'Guided Retail Billing (POS)',
            subtitle:
                'Simple 3-stage billing workflow designed for fast service.',
            icon: Icons.point_of_sale_rounded,
            bulletPoints: [
              'Tap "+ New Sale" to start a new retail bill.',
              'Step 1 (Items): Select product and packets; rates are applied automatically.',
              'Step 2 (Customer & Pay): Enter name, 10-digit mobile, and select Cash or UPI.',
              'Step 3 (Review): Verify customer details, line items, and total amount.',
            ],
            shortcutLabel: 'Create New Sale',
            shortcutType: OnboardingShortcutType.pos,
          ),
          OnboardingStep(
            title: 'Complete Sale & WhatsApp Handoff',
            subtitle:
                'One-tap sale persistence and instant customer sharing.',
            icon: Icons.mark_chat_read_rounded,
            bulletPoints: [
              'Tap "Complete Sale & Send WhatsApp" to record the sale via secure Supabase RPC.',
              'Stock is deducted from Jaipur outlet only, with double-submission guards.',
              'Launches WhatsApp with the customer invoice pre-formatted.',
              'View past bills in the Sales tab to reprint or re-share anytime.',
            ],
            shortcutLabel: 'View Sales History',
            shortcutType: OnboardingShortcutType.sales,
          ),
        ];
    }
  }
}
