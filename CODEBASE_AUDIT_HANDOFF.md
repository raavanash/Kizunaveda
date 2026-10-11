# KIZUNA VEDA — FULL CODEBASE AUDIT & TECHNICAL HANDOFF REPORT

**Workspace:** `F:\kizuna-veda`  
**Framework:** Flutter (Dart)  
**Backend:** Supabase (PostgreSQL + RLS + PostgREST RPC)  
**Target Migration:** `supabase/migrations/20261005200000_v1_2_two_store_billing.sql`  
**Supabase Project Ref:** `gdxufikrumhxovmtavwj`  
**Audit Timestamp:** October 10, 2026  

---

## 1. EXECUTIVE SUMMARY

Kizuna Veda is a private mobile enterprise application designed for managing inventory, store-level stock intake, and POS billing across two primary facility locations:
1. **Neemrana Facility** (`11111111-1111-1111-1111-111111111111`): Finished goods stock-in, finished inventory tracking, and POS bill creation.
2. **Jaipur Outlet** (`22222222-2222-2222-2222-222222222222`): Finished goods stock-in, transfer receipt confirmation, finished inventory tracking, and POS bill creation.
3. **Owner Portal / HQ**: Oversight of combined inventory across both stores, individual store stock, combined sales revenue, user role management, and bill voiding.

### Current Implementation Status
- **UI & Workflows**: Streamlined V1.2 UI focuses strictly on Stock In, Inventory Tracking, POS Billing (Cash/UPI), PDF Invoice Generation, and WhatsApp sharing. Legacy raw material intake, batch processing, packaging, and wastage screens are hidden from active user navigation while keeping underlying database tables dormant.
- **Data Safety**: All direct REST table insertions (`sales`, `sale_items`) are blocked by `WITH CHECK (false)` RLS policies. All write operations occur exclusively through server-side `SECURITY DEFINER` RPC functions (`fn_create_pos_sale`, `fn_confirm_jaipur_receipt`, `fn_void_bill`).
- **Static Analysis**: `flutter analyze` completed with **0 issues found**.
- **Automated Tests**: All **64 out of 64 unit and widget tests passed**.
- **Build Status**: Android Debug APK successfully generated at [`build/app/outputs/flutter-apk/app-debug.apk`](file:///f:/kizuna-veda/build/app/outputs/flutter-apk/app-debug.apk).

---

## 2. SECTION 1 — PROJECT STRUCTURE & FILE MAP

```
f:\kizuna-veda\
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
│   │   └── widgets/         # KizunaCard & shared UI components
│   └── features/
│       ├── auth/
│       │   ├── data/        # SupabaseAuthRepository, UnconnectedAuthRepository, LocalSessionStorage
│       │   ├── domain/      # AuthUser, AuthSession entities & contracts
│       │   └── presentation/# AuthGate, LoginScreen, AuthNotifier
│       ├── inventory/
│       │   ├── data/        # SupabaseInventoryRepository, UnconnectedInventoryRepository
│       │   ├── domain/      # Product, StockInRecord, Sale, SaleItem, ProductInventorySummary
│       │   └── presentation/# InventoryNotifier, StockInDialog, RecordPosSaleDialog
│       ├── neemrana/
│       │   └── presentation/# NeemranaHomeScreen
│       ├── jaipur/
│       │   └── presentation/# JaipurHomeScreen, InvoicePreviewScreen, EBillHistoryScreen
│       └── owner/
│           └── presentation/# OwnerHomeScreen, NeemranaStockScreen, JaipurStockScreen, UserManagementScreen
├── test/                    # 64 unit and widget test files
├── supabase/
│   └── migrations/          # Chronological PostgreSQL migrations
│       ├── 20261005120000_v1_inventory_foundation.sql
│       ├── 20261005170000_v1_sales_void_lifecycle.sql
│       ├── 20261005180000_v1_atomic_transactions.sql
│       ├── 20261005190000_v1_1_billing_enhancements.sql
│       └── 20261005200000_v1_2_two_store_billing.sql
├── pubspec.yaml             # Dependencies: supabase_flutter, pdf, printing, share_plus, url_launcher
└── supabase.local.json      # Local environment configuration file (Supabase URL & Anon Key)
```

---

## 3. SECTION 2 — ARCHITECTURE AND DATA FLOW

The application follows a **Clean Architecture with Repository Pattern** using Flutter's native `ChangeNotifier` and `InheritedWidget` state management (`AuthNotifier`, `InventoryNotifier`, `InventoryProvider`).

### Workflow Traces

1. **Authentication & Startup**:
   - `AuthGate` ([`lib/features/auth/presentation/screens/auth_gate.dart`](file:///f:/kizuna-veda/lib/features/auth/presentation/screens/auth_gate.dart)) listens to `AuthNotifier`.
   - On launch, `SupabaseAuthRepository` reads active JWT session.
   - If unauthenticated -> displays `LoginScreen`.
   - If authenticated -> inspects `app_metadata.role` on JWT.
     - `owner` -> `OwnerHomeScreen`
     - `neemrana` -> `NeemranaHomeScreen`
     - `jaipur` -> `JaipurHomeScreen`

2. **Stock-In Operation**:
   - User opens `StockInDialog` ([`lib/features/inventory/presentation/widgets/stock_in_dialog.dart`](file:///f:/kizuna-veda/lib/features/inventory/presentation/widgets/stock_in_dialog.dart)).
   - Selects product/SKU, enters quantity and optional notes. Store location is auto-locked for store roles (`NEEMRANA` or `JAIPUR`) or selectable by `OWNER`.
   - Submits -> calls `InventoryNotifier.addStockIn()`.
   - Calls `SupabaseInventoryRepository.addStockIn()`.
   - Inserts row into `public.stock_in_records` table via Supabase REST client.
   - Trigger `trg_check_sale_stock` and triggers update inventory levels dynamically.

3. **POS Sale Creation**:
   - User opens `RecordPosSaleDialog` ([`lib/features/inventory/presentation/widgets/record_pos_sale_dialog.dart`](file:///f:/kizuna-veda/lib/features/inventory/presentation/widgets/record_pos_sale_dialog.dart)).
   - Selects product, quantity, customer name, customer phone, and Cash/UPI payment.
   - Submits -> calls `InventoryNotifier.recordSale()`.
   - Calls `SupabaseInventoryRepository.recordSale()`.
   - Invokes Supabase RPC `public.fn_create_pos_sale(...)`.
   - PostgreSQL RPC validates stock (`FOR UPDATE` locks), checks user role, generates bill number (`BILL-XXXXXX`), calculates line totals, creates `sales` and `sale_items` rows atomically, and returns created sale JSON object.
   - On success -> opens `InvoicePreviewScreen` for PDF invoice preview and WhatsApp/Share sheet trigger.

4. **Bill Voiding**:
   - Owner views completed sale in `EBillHistoryScreen` or `JaipurStockScreen`.
   - Taps "Void Bill" -> prompts confirmation dialog requiring reason.
   - Calls `InventoryNotifier.voidSale()`.
   - Invokes Supabase RPC `public.fn_void_bill(...)`.
   - PostgreSQL updates `sales.status = 'VOIDED'`. Trigger `trg_check_sale_stock` adjusts active stock deduction so stock is instantly restored to store inventory.

---

## 4. SECTION 3 — AUTHENTICATION AND AUTHORIZATION

### Role Matrix & Casing
Authorization is driven exclusively by trusted JWT claims (`app_metadata.role`), evaluated server-side in PostgreSQL via helper function `public.get_current_user_role()`.

| Role Key (JSON/SQL) | Enum Name (`UserRole`) | Display Name | UI Access Boundary | Supabase RLS Access Boundary |
| :--- | :--- | :--- | :--- | :--- |
| `'owner'` | `UserRole.owner` | Owner / Admin | Combined & Store-wise Inventory, User Mgmt, Bill Voiding, Stock In | Select/Insert all locations, void sales, manage users |
| `'neemrana'` | `UserRole.neemrana` | Neemrana Store | Neemrana Stock In, Inventory, POS Billing, Bill History | Select/Insert Neemrana stock-in & POS sales only |
| `'jaipur'` | `UserRole.jaipur` | Jaipur Store | Jaipur Stock In, Confirm Receipts, POS Billing, Bill History | Select/Insert Jaipur stock-in, receipts & POS sales only |

### Security Safeguards
- **Role Spoofing Prevention**: Client cannot pass role in request payload. `public.get_current_user_role()` reads directly from `auth.jwt() -> 'app_metadata' ->> 'role'`.
- **Credential Protection**: No service-role keys or passwords are stored in Dart source code. Supabase URL and Anon Key are loaded via `supabase.local.json`.

---

## 5. SECTION 4 — DATABASE AND MIGRATION AUDIT

### Chronological Migration History

1. **`20261005120000_v1_inventory_foundation.sql`**:
   - Creates baseline schema: `locations`, `products`, `raw_materials`, `raw_material_receipts`, `packing_records`, `transfers`, `sales`, `sale_items`.
   - Sets up initial RLS policies and `get_current_user_role()` helper.

2. **`20261005170000_v1_sales_void_lifecycle.sql`**:
   - Introduces bill voiding lifecycle (`status IN ('COMPLETED', 'VOIDED')`).
   - Creates sequence `seq_bill_number` and void RPC `fn_void_bill`.

3. **`20261005180000_v1_atomic_transactions.sql`**:
   - Introduces atomic `fn_create_pos_sale(TEXT, JSONB)` and `fn_confirm_jaipur_receipt(UUID, INT, TEXT)`.
   - Tightens RLS policies on `sales` and `sale_items`.

4. **`20261005190000_v1_1_billing_enhancements.sql`**:
   - Adds `customer_name` and `payment_method` to `sales`.
   - Backfills historical sales data deterministically.
   - Updates RPC `fn_create_pos_sale` to accept 4 parameters (`p_customer_name`, `p_customer_phone`, `p_payment_method`, `p_items`).

5. **`20261005200000_v1_2_two_store_billing.sql`**:
   - Adds `stock_in_records` table for direct store stock-in logging.
   - Updates `fn_check_neemrana_dispatch_stock` and `fn_check_sale_stock` triggers to incorporate `stock_in_records` into stock calculations.
   - Adds deterministic UUID locking order (`ORDER BY product_id`) to prevent concurrency deadlocks.
   - Blocks direct REST table inserts on `sales` and `sale_items` via `WITH CHECK (false)`.
   - Replaces `fn_create_pos_sale` with 11-parameter V1.2 signature with server-side GST block (`p_invoice_type = 'GST'` error).

### Key RPC Function Signatures (PostgreSQL)

```sql
-- POS Sale Creation RPC
CREATE OR REPLACE FUNCTION public.fn_create_pos_sale(
    p_customer_name TEXT,
    p_customer_phone TEXT,
    p_payment_method TEXT,
    p_items JSONB,
    p_location_id UUID DEFAULT NULL,
    p_invoice_type TEXT DEFAULT 'NON_GST',
    p_gst_rate NUMERIC DEFAULT 0.00,
    p_taxable_amount NUMERIC DEFAULT NULL,
    p_cgst_amount NUMERIC DEFAULT 0.00,
    p_sgst_amount NUMERIC DEFAULT 0.00,
    p_igst_amount NUMERIC DEFAULT 0.00
) RETURNS JSONB SECURITY DEFINER SET search_path = public;

-- Bill Voiding RPC
CREATE OR REPLACE FUNCTION public.fn_void_bill(
    p_sale_id UUID,
    p_void_reason TEXT
) RETURNS JSONB SECURITY DEFINER SET search_path = public;

-- Jaipur Receipt Confirmation RPC
CREATE OR REPLACE FUNCTION public.fn_confirm_jaipur_receipt(
    p_transfer_id UUID,
    p_received_quantity INT,
    p_discrepancy_reason TEXT DEFAULT NULL
) RETURNS JSONB SECURITY DEFINER SET search_path = public;
```

---

## 6. SECTION 5 — INVENTORY MODEL & FORMULAS

Stock balances are calculated dynamically from immutable ledger tables to prevent stock drift.

### Accounting Formulas

1. **Neemrana Store Stock**:
   $$\text{Neemrana Stock} = \text{Packed} + \text{Neemrana StockIn} - \text{Dispatched} - \text{Neemrana Sold}$$

2. **Jaipur Store Stock**:
   $$\text{Jaipur Stock} = \text{Received} + \text{Jaipur StockIn} - \text{Jaipur Sold}$$

3. **Combined Inventory (Owner View)**:
   $$\text{Combined Stock} = \text{Neemrana Stock} + \text{Jaipur Stock}$$

### Concurrency & Overselling Safeguards
- **Row Locking**: During POS sale execution, `fn_check_sale_stock()` locks product stock rows `FOR UPDATE` in deterministic UUID order (`ORDER BY product_id`) before validating line item availability.
- **Atomic Deduction**: Deduction occurs inside the POS sale transaction block. If available stock is less than requested quantity, the RPC raises an exception and rolls back the entire transaction.
- **Void Restoration**: When a sale is voided (`status = 'VOIDED'`), `fn_check_sale_stock()` ignores voided sale items (`sales.status = 'COMPLETED'`), restoring stock immediately.

---

## 7. SECTION 6 — POS RPC ERROR DIAGNOSTIC: `PGRST202`

### Observed Runtime Error
`PostgrestException (PGRST202): Could not find the function public.fn_create_pos_sale with the parameters p_customer_name, p_customer_phone, p_gst_rate, p_invoice_type, p_items, p_location_id, p_payment_method, p_cgst_amount, p_sgst_amount, p_igst_amount, p_taxable_amount in the schema cache.`

### Root Cause Analysis (Verified Findings)

1. **Remote Database Missing V1.2 Migration**:
   - The remote Supabase instance `gdxufikrumhxovmtavwj` currently runs **V1.1** schema, where `fn_create_pos_sale` has **4 parameters**.
   - The V1.2 Flutter client sends **11 parameter keys**.
   - PostgREST inspects its schema cache for a function matching all 11 parameter names and fails to find one on the remote database, throwing `PGRST202`.

2. **Local Client & Migration Fixes Implemented**:
   - In [`SupabaseInventoryRepository`](file:///f:/kizuna-veda/lib/features/inventory/data/repositories/supabase_inventory_repository.dart), `params` map was updated to explicitly pass all 11 parameter keys (`p_location_id` and `p_taxable_amount` included explicitly even when `null`).
   - In [`20261005200000_v1_2_two_store_billing.sql`](file:///f:/kizuna-veda/supabase/migrations/20261005200000_v1_2_two_store_billing.sql), explicit `DROP FUNCTION IF EXISTS` statements were added for all legacy overload signatures to ensure clean replacement upon migration deployment.

### Operator Diagnostic Step
To inspect the live remote function signature in Supabase SQL Editor:
```sql
SELECT p.proname, pg_catalog.pg_get_function_arguments(p.oid)
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'fn_create_pos_sale';
```

---

## 8. SECTION 7 — BILLING & FINANCIAL INTEGRITY

- **Bill Numbers**: Generated server-side using sequence `public.seq_bill_number` formatted as `BILL-XXXXXX` (e.g. `BILL-010001`).
- **Server-Side Pricing**: Unit prices and line totals are validated and calculated on the server. Client-provided subtotals are not trusted.
- **Payment Methods**: Validated against `CHECK (payment_method IN ('CASH', 'UPI'))`.
- **Server-Side GST Block**: Until official business GSTIN configuration is completed, passing `p_invoice_type = 'GST'` triggers an explicit server-side exception in `fn_create_pos_sale`. `NON_GST` billing is fully active.
- **PDF & Sharing**: Invoices are generated locally using the `pdf` and `printing` packages and shared via native Android share sheet or WhatsApp URL launcher (`https://wa.me/91XXXXXXXXXX?text=...`).

---

## 9. SECTION 8 — TEST & BUILD SUITE RESULTS

Fresh verification execution output on October 10, 2026:

### 1. `flutter analyze`
- **Result**: `No issues found! (ran in 5.7s)`
- **Exit Code**: `0`

### 2. `flutter test`
- **Result**: `All 64 tests passed!`
- **Exit Code**: `0`
- **Coverage**: Auth domain, role routing, stock-in dialogs, POS sale validation, combined inventory calculations, PDF invoice generation, WhatsApp fallbacks, bill voiding.

### 3. `flutter build apk --debug`
- **Result**: `√ Built build\app\outputs\flutter-apk\app-debug.apk`
- **Exit Code**: `0`

---

## 10. SECTION 9 — SECURITY & RISK ASSESSMENT

| Severity | Category | Risk Description | Status | Recommendation |
| :--- | :--- | :--- | :--- | :--- |
| **LOW** | Remote Deployment | Remote database `gdxufikrumhxovmtavwj` requires V1.2 migration execution to clear `PGRST202`. | Un-deployed | Run `supabase db push` or apply [`20261005200000_v1_2_two_store_billing.sql`](file:///f:/kizuna-veda/supabase/migrations/20261005200000_v1_2_two_store_billing.sql) in Supabase SQL Editor. |
| **INFORMATIONAL**| Plugin Warning | `share_plus` plugin KGP migration warning during Gradle build. | Non-blocking | Upgrade `share_plus` in future maintenance release. |

---

## 11. SECTION 10 — DEPLOYMENT ACTION PLAN

To deploy Kizuna Veda V1.2 to production:

1. Connect to Supabase project `gdxufikrumhxovmtavwj`.
2. Apply migration [`supabase/migrations/20261005200000_v1_2_two_store_billing.sql`](file:///f:/kizuna-veda/supabase/migrations/20261005200000_v1_2_two_store_billing.sql) using Supabase CLI (`supabase db push`) or SQL Editor.
3. Verify remote RPC signature:
   ```sql
   SELECT p.proname, pg_catalog.pg_get_function_arguments(p.oid)
   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'fn_create_pos_sale';
   ```
4. Install generated APK [`build/app/outputs/flutter-apk/app-debug.apk`](file:///f:/kizuna-veda/build/app/outputs/flutter-apk/app-debug.apk) on store devices.
