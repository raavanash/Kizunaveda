# KIZUNA VEDA — Enterprise Retail POS & Multi-Store Inventory Management

A robust, offline-resilient, and role-based mobile retail Point-of-Sale (POS) and inventory management system built with **Flutter** and **Supabase (PostgreSQL + RLS + RPC)**. Designed specifically for Ayurvedic and wellness retail enterprises operating across multiple production and retail outlet locations.

---

## 🌟 Key Features

### 🛒 1. Guided 3-Stage POS Billing
- **Streamlined Workflow**: Move cleanly through **1. Items** → **2. Customer & Pay** → **3. Review Bill** without back-and-forth friction.
- **Editable Selling Price (₹ per packet)**:
  - Automatically prefills with the catalog standard selling price.
  - Authorized store operators can adjust unit prices per transaction.
  - Instant indicator badge: `Authorized Price Override (Catalog: ₹X.XX)`.
- **Line-Item Discounts**: Real-time discount calculation: `Subtotal = (Quantity × Unit Price) − Discount`.
- **Immediate Stock Validation**: Verifies outlet inventory in real-time before advancing.
- **State Preservation**: Entered prices, quantities, discounts, and customer details remain intact across all steps and back navigation.

### 🧾 2. Thermal Invoicing & Resilient WhatsApp Sharing
- **80mm Thermal PDF Invoices**: Generates professional receipt invoices with company branding, tax breakdown, unit rate, discounts, and totals.
- **Instant WhatsApp Bills**: Formats and dispatches formatted customer receipts via WhatsApp.
- **Fault-Tolerant Retry**: If messaging is cancelled or fails, the bill remains securely saved with its official bill number, allowing one-tap retry without creating duplicate bills or deducting stock twice.

### 📊 3. Cost Accounting & Profit Intelligence
- **Snapshotted Unit Costs**: Captures purchase cost per item at the exact moment of sale.
- **Historical Profit Preservation**: Future catalog price or cost adjustments never alter historical bills or past margin calculations.
- **Revenue ≠ Profit**: Explicitly separates and tracks:
  - **Revenue**: Total net sales collections.
  - **Cost of Goods Sold (COGS)**: `Σ (Quantity × Snapshotted Cost)`.
  - **Gross Profit**: Net Revenue minus COGS.
- **Honest Legacy Handling**: Historical sales lacking cost data display an honest `Unavailable` indicator rather than fabricating profit figures.

### 🏪 4. Multi-Store Inventory & Outlet Isolation
- **Independent Locations**:
  - **Neemrana Facility**: Finished goods stock-in, local inventory tracking, and outlet POS.
  - **Jaipur Outlet**: Stock intake, transfer receipts, outlet inventory, and outlet POS.
  - **Owner / HQ Portal**: Global visibility across all outlets, inter-store transfers, catalog pricing, user role management, and bill voiding.
- **Live Stock Alerts**: Instant color-coded badges for Out of Stock, Low Stock, and In Stock items.

### 🛡️ 5. Zero-Direct-Write Security & Permissions
- **Row Level Security (RLS)**: Direct REST `INSERT` / `UPDATE` on `sales` and `sale_items` tables are blocked via `WITH CHECK (false)`.
- **Atomic Database RPC**: All critical state changes execute exclusively through trusted PostgreSQL `SECURITY DEFINER` functions:
  - `fn_create_pos_sale`: Atomically creates bill, verifies stock, snapshots costs, deducts inventory, and records audit trails.
  - `fn_void_bill`: Authorizes bill voiding and reverses stock deduction atomically.

### 🧭 6. Vyapar-Inspired Navigation & User Onboarding
- **Bottom Navigation**: Fast single-tap switching between **Dashboard**, **Sales**, **Inventory**, and **More**.
- **Role-Based Onboarding**: Guided, interactive walkthrough upon first login for Owner, Neemrana Retail, and Jaipur Retail roles.
- **Contextual Actions**: Dedicated outlet filters, date preset filters (Today, This Week, This Month, All Time), and quick-action bill creation.

---

## 🏗️ Architecture & Technology Stack

- **Frontend**: Flutter 3.x / Dart (Sound Null Safety)
- **State Management**: Clean Architecture using `ChangeNotifier` and `InheritedWidget` (`InventoryNotifier`, `AuthNotifier`, `InventoryProvider`)
- **Backend & Database**: Supabase (PostgreSQL 15+, PostgREST, Database Triggers, Row Level Security, Custom RPC functions)
- **PDF & Thermal Printing**: `pdf` & `printing`
- **Sharing & Intents**: `url_launcher` & `share_plus`
- **Local Storage**: `shared_preferences` for session management and onboarding state

---

## 📁 Project Structure

```
kizuna-veda/
├── lib/
│   ├── app/
│   │   ├── config/          # AppConfig & environment setup
│   │   ├── providers/       # InheritedWidgets for global dependency injection
│   │   ├── routes/          # Named route definitions & AppRoutes
│   │   └── theme/           # AppColors, typography & high-contrast themes
│   ├── core/
│   │   ├── constants/       # AppConstants, LocationConstants, UserRole enum
│   │   ├── error/           # AuthException & domain error handles
│   │   ├── services/        # PdfInvoiceService, WhatsApp share helpers
│   │   └── widgets/         # KizunaCard, KizunaBrandHeader & shared UI components
│   └── features/
│       ├── auth/            # SupabaseAuthRepository, AuthGate, LoginScreen
│       ├── dashboard/       # VyaparDashboardView & analytics widgets
│       ├── inventory/       # Stock tracking, StockInDialog, EditProductPricingDialog
│       ├── jaipur/          # Jaipur home screen & history views
│       ├── more/            # Settings, administration & configuration navigation
│       ├── navigation/      # MainNavigationShell bottom bar
│       ├── neemrana/        # Neemrana facility screens
│       ├── onboarding/      # Role-based guides & interactive walkthroughs
│       ├── owner/           # Owner metrics calculator & store management
│       └── sales/           # GuidedNewSaleScreen (3-step POS) & DedicatedSalesView
├── supabase/
│   └── migrations/          # Chronological database migrations
│       ├── 20261005000000_inventory_v1.sql
│       ├── 20261005120000_v1_inventory_foundation.sql
│       ├── 20261005170000_v1_sales_void_lifecycle.sql
│       ├── 20261005180000_v1_atomic_transactions.sql
│       ├── 20261005190000_v1_1_billing_enhancements.sql
│       ├── 20261005200000_v1_2_two_store_billing.sql
│       ├── 20261011130000_v1_3_two_independent_stores.sql
│       ├── 20261011140000_v1_4_reset_and_repair.sql
│       └── 20261011150000_v1_5_editable_pricing_and_cost.sql
├── test/                    # Comprehensive unit and widget test suite (121 tests)
└── pubspec.yaml             # Project dependencies & assets
```

---

## 🚀 Getting Started

### Prerequisites
- **Flutter SDK**: `>= 3.3.0`
- **Dart SDK**: `>= 3.0.0`
- **Android SDK**: API 34+ / Android Studio or VS Code
- **Supabase Project**: With PostgreSQL instance

### 1. Clone the Repository
```bash
git clone https://github.com/raavanash/Kizunaveda.git
cd Kizunaveda
```

### 2. Install Dependencies
```bash
flutter pub get
```

### 3. Environment Configuration
Create a `supabase.local.json` file in the root directory (ignored by git):
```json
{
  "SUPABASE_URL": "https://your-project-id.supabase.co",
  "SUPABASE_ANON_KEY": "your-anon-key"
}
```

### 4. Database Setup
Apply the migrations located in [`supabase/migrations/`](supabase/migrations/) sequentially to your Supabase project using the Supabase CLI or SQL Editor.

### 5. Run the Application
```bash
# Debug run on connected device/emulator
flutter run --dart-define-from-file=supabase.local.json
```

---

## 🧪 Testing & Code Quality

The codebase enforces strict unit, widget, and integration coverage:

```bash
# Run static analysis (0 warnings/errors)
flutter analyze

# Run full test suite (121 passing tests)
flutter test
```

### Test Coverage Highlights:
- **POS Calculations**: Prefilled pricing, custom price overrides, discount calculation, stock boundary assertions.
- **Navigation & Workflow**: State preservation across multi-step wizard, double-tap submission guards.
- **Cost & Margin Preservation**: Verifies historical bills and profits remain untouched when standard catalog prices change.
- **WhatsApp Dispatch**: Tests bill number delivery, formatting, and retry handling upon launch failure.

---

## 👥 User Roles & Permissions

| Feature | Owner / HQ | Neemrana Retail | Jaipur Retail |
|---|:---:|:---:|:---:|
| **POS Billing (New Retail Bill)** | ✅ All Stores | ✅ Neemrana Only | ✅ Jaipur Only |
| **Editable Selling Price in POS** | ✅ | ✅ | ✅ |
| **Product Standard Price & Cost Setup**| ✅ | ❌ | ❌ |
| **Gross Profit & COGS Reports** | ✅ | ❌ | ❌ |
| **Stock-In Intake** | ✅ All Stores | ✅ Neemrana Only | ✅ Jaipur Only |
| **Void Bills / Reverse Sales** | ✅ | ❌ | ❌ |
| **User Management** | ✅ | ❌ | ❌ |

---

## 📄 License

Private enterprise application. All rights reserved by **KIZUNA VEDA**.
