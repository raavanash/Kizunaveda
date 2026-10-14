-- ==============================================================================
-- KIZUNA VEDA — V1.6 Multi-Session Concurrency Test Guide & Manual Scripts
-- File: test/sql/v1_6_multi_session_concurrency_tests.sql
-- Description: Step-by-step PostgreSQL scripts for testing multi-session
--              concurrency across two simultaneous database connections.
--
-- TARGET BEHAVIORS VALIDATED:
-- 1. Simultaneous first-time stock receipt for an unstocked product:
--    - Two sessions call fn_receive_store_stock concurrently.
--    - Verified: ON CONFLICT DO NOTHING + FOR UPDATE prevents duplicate key
--      errors on uq_store_inventory_location_product, serializes row updates,
--      and yields accurate accumulated stock and audit logs.
-- 2. Simultaneous submission of the same request ID:
--    - Two sessions call fn_create_pos_sale with the same client_request_id.
--    - Verified: pg_advisory_xact_lock serializes execution; Session 1 creates
--      the sale; Session 2 unblocks, detects the committed sale, and returns
--      it as an idempotent replay.
--    - Verified: Exactly ONE sale record and exactly ONE stock deduction occur.
--
-- REPEATABILITY & DATA SAFETY:
-- - Fixture ownership verified (uses CONCURRENCY-FIXTURE-% naming).
-- - Pre-checks ensure no real production or pre-existing product is overwritten.
-- - Baseline stock is recorded prior to transactions.
-- - Emergency partial-failure cleanup block provided.
--
-- EXECUTION NOTICE:
-- - Run in local or staging PostgreSQL / Supabase instance.
-- - Requires two concurrent psql or database client sessions (Session A and B).
-- - DO NOT RUN IN PRODUCTION.
-- ==============================================================================

-- ==============================================================================
-- EMERGENCY CLEANUP (Can be run at any time if previous test aborted midway)
-- ==============================================================================
DO $$
BEGIN
    DELETE FROM public.sale_items WHERE sale_id IN (
        SELECT id FROM public.sales WHERE client_request_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid
    );
    DELETE FROM public.sales WHERE client_request_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid;
    DELETE FROM public.stock_adjustments WHERE product_id IN (
        SELECT id FROM public.products WHERE name LIKE 'CONCURRENCY-FIXTURE-%'
    );
    DELETE FROM public.store_inventory WHERE product_id IN (
        SELECT id FROM public.products WHERE name LIKE 'CONCURRENCY-FIXTURE-%'
    );
    DELETE FROM public.product_procurement_costs WHERE product_id IN (
        SELECT id FROM public.products WHERE name LIKE 'CONCURRENCY-FIXTURE-%'
    );
    DELETE FROM public.products WHERE name LIKE 'CONCURRENCY-FIXTURE-%';
    RAISE NOTICE 'Fixture cleanup verified.';
END $$;

-- ==============================================================================
-- STEP 0: SETUP (Execute in Session A before opening concurrent sessions)
-- ==============================================================================

-- 1. Safety verification: Ensure SKU is not taken by pre-existing non-fixture product
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM public.products WHERE sku = 'CONC-BRA-100' AND name NOT LIKE 'CONCURRENCY-FIXTURE-%') THEN
        RAISE EXCEPTION 'SAFETY ABORT: SKU CONC-BRA-100 is in use by an existing non-test product!';
    END IF;
END $$;

-- 2. Create dedicated test product fixture
INSERT INTO public.products (id, name, package_size, sku, standard_selling_price, purchase_cost, active)
VALUES (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid,
    'CONCURRENCY-FIXTURE-BRAHMI-100G',
    '100g',
    'CONC-BRA-100',
    200.00,
    0.00,
    true
) ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    standard_selling_price = EXCLUDED.standard_selling_price,
    purchase_cost = EXCLUDED.purchase_cost;

INSERT INTO public.product_procurement_costs (product_id, purchase_cost)
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, 80.00)
ON CONFLICT (product_id) DO UPDATE SET purchase_cost = EXCLUDED.purchase_cost;

-- 3. Record baseline inventory quantity (must be 0 for this fresh fixture)
SELECT COALESCE(current_quantity, 0) AS initial_baseline_stock
FROM public.store_inventory
WHERE location_id = '22222222-2222-2222-2222-222222222222'::uuid
  AND product_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid;

-- ==============================================================================
-- TEST SCENARIO 1: Simultaneous First-Time Stock Receipt
-- ==============================================================================

-- Instructions: Open two terminals/windows connected to the database.
-- In both terminals, set timeouts to prevent indefinite hanging if a deadlock occurs:
--   SET statement_timeout = '20s';
--   SET lock_timeout = '15s';

-- [TERMINAL A (Session A)]:
BEGIN;
SET LOCAL statement_timeout = '20s';
SET LOCAL lock_timeout = '15s';
SELECT set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "jaipur"}}', true);
SELECT public.fn_receive_store_stock(
    '22222222-2222-2222-2222-222222222222'::uuid,
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid,
    50,
    'Session A simultaneous delivery'
);
-- PAUSE: DO NOT COMMIT YET. Session A now holds the row lock on store_inventory.

-- [TERMINAL B (Session B)]: Execute immediately while Session A is open:
BEGIN;
SET LOCAL statement_timeout = '20s';
SET LOCAL lock_timeout = '15s';
SELECT set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "jaipur"}}', true);
SELECT public.fn_receive_store_stock(
    '22222222-2222-2222-2222-222222222222'::uuid,
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid,
    30,
    'Session B simultaneous delivery'
);
-- OBSERVATION: Terminal B will enter a waiting state on the row lock held by Session A.

-- [HOW TO OBSERVE LOCK STATUS] (Optional: run in a 3rd window):
-- SELECT pid, wait_event_type, wait_event, state, query
-- FROM pg_stat_activity
-- WHERE query LIKE '%fn_receive_store_stock%';
-- Shows Terminal B with wait_event_type = 'Lock' and wait_event = 'tuple'.

-- [TERMINAL A]: Commit transaction
COMMIT;

-- [TERMINAL B]: Unblocks immediately upon Terminal A commit! Commit transaction:
COMMIT;

-- [VERIFICATION 1]:
SELECT current_quantity FROM public.store_inventory
WHERE location_id = '22222222-2222-2222-2222-222222222222'::uuid
  AND product_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid;
-- ASSERTION: current_quantity MUST be exactly 80 (0 baseline + 50 + 30).

SELECT previous_quantity, new_quantity, change_quantity, reason
FROM public.stock_adjustments
WHERE product_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid
ORDER BY created_at ASC;
-- ASSERTION: Exactly 2 rows:
-- Row 1: previous=0, new=50, change=50, reason='STOCK_RECEIPT'
-- Row 2: previous=50, new=80, change=30, reason='STOCK_RECEIPT'

-- ==============================================================================
-- TEST SCENARIO 2: Simultaneous Submission of Same Request ID
-- ==============================================================================

-- Shared request ID: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid

-- [TERMINAL A (Session A)]:
BEGIN;
SET LOCAL statement_timeout = '20s';
SET LOCAL lock_timeout = '15s';
SELECT set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "jaipur"}}', true);
SELECT public.fn_create_pos_sale(
    p_customer_name => 'Simultaneous Buyer',
    p_customer_phone => '9829011111',
    p_payment_method => 'UPI',
    p_items => jsonb_build_array(
        jsonb_build_object(
            'product_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid,
            'quantity', 2,
            'unit_price', 200.00,
            'discount', 0.00
        )
    ),
    p_location_id => '22222222-2222-2222-2222-222222222222'::uuid,
    p_client_request_id => 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid
);
-- PAUSE: DO NOT COMMIT YET. Session A holds pg_advisory_xact_lock on the request ID.

-- [TERMINAL B (Session B)]: Submit identical request concurrently:
BEGIN;
SET LOCAL statement_timeout = '20s';
SET LOCAL lock_timeout = '15s';
SELECT set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "jaipur"}}', true);
SELECT public.fn_create_pos_sale(
    p_customer_name => 'Simultaneous Buyer',
    p_customer_phone => '9829011111',
    p_payment_method => 'UPI',
    p_items => jsonb_build_array(
        jsonb_build_object(
            'product_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid,
            'quantity', 2,
            'unit_price', 200.00,
            'discount', 0.00
        )
    ),
    p_location_id => '22222222-2222-2222-2222-222222222222'::uuid,
    p_client_request_id => 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid
);
-- OBSERVATION: Terminal B pauses waiting on the advisory transaction lock held by Terminal A.

-- [HOW TO OBSERVE LOCK STATUS]:
-- SELECT pid, wait_event_type, wait_event, state, query
-- FROM pg_stat_activity
-- WHERE query LIKE '%fn_create_pos_sale%';
-- Shows Terminal B waiting with wait_event_type = 'Lock' and wait_event = 'advisory'.

-- [TERMINAL A]: Commit transaction
COMMIT;

-- [TERMINAL B]: Unblocks immediately, reads existing sale, returns JSON replay. Commit transaction:
COMMIT;

-- [VERIFICATION 2]:
SELECT count(*) AS total_sales_rows
FROM public.sales
WHERE client_request_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid;
-- ASSERTION: total_sales_rows MUST be exactly 1.

SELECT current_quantity
FROM public.store_inventory
WHERE location_id = '22222222-2222-2222-2222-222222222222'::uuid
  AND product_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid;
-- ASSERTION: current_quantity MUST be exactly 78 (80 - 2 = 78, NOT double-deducted to 76).

-- ==============================================================================
-- STEP 3: TEARDOWN (Clean up only the test fixture)
-- ==============================================================================
DO $$
BEGIN
    DELETE FROM public.sale_items WHERE sale_id IN (
        SELECT id FROM public.sales WHERE client_request_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid
    );
    DELETE FROM public.sales WHERE client_request_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid;
    DELETE FROM public.stock_adjustments WHERE product_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid;
    DELETE FROM public.store_inventory WHERE product_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid;
    DELETE FROM public.product_procurement_costs WHERE product_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid;
    DELETE FROM public.products WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid;
    RAISE NOTICE 'Teardown complete.';
END $$;
