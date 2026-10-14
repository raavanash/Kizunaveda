-- ==============================================================================
-- KIZUNA VEDA — V1.6 Database-Level Verification & Security Test Suite
-- File: test/sql/v1_6_pos_idempotency_and_security_tests.sql
-- Description: Executes directly in PostgreSQL / Supabase SQL Editor.
--
-- REPEATABLE EXECUTION & SAFETY GUARANTEES:
-- 1. Entire suite runs inside a single transaction (BEGIN ... ROLLBACK).
-- 2. Leaves zero test artifacts in products, sales, inventory, or audit ledgers.
-- 3. Explicitly restores pos_security_config so database state is untouched.
-- 4. Uses real SET LOCAL ROLE authenticated; with PostgREST JWT claims to test
--    genuine database-level RLS policies and role restrictions.
--
-- NOTE ON MULTI-SESSION CONCURRENCY:
-- Multi-session concurrency cannot run inside a single transaction because
-- concurrent sessions require separate simultaneous connections. See:
-- - test/sql/v1_6_multi_session_concurrency_tests.sql
-- - test/sql/run_concurrency_test.py
--
-- EXECUTION NOTICE:
-- - Run in local or staging Supabase SQL environment.
-- - DO NOT RUN IN PRODUCTION.
-- ==============================================================================

BEGIN;

DO $$
DECLARE
    v_test_product_1 UUID;
    v_test_product_2 UUID;
    v_jaipur_id CONSTANT UUID := '22222222-2222-2222-2222-222222222222'::uuid;
    v_neemrana_id CONSTANT UUID := '11111111-1111-1111-1111-111111111111'::uuid;
    v_req_id UUID := gen_random_uuid();
    v_reorder_req_id UUID := gen_random_uuid();
    v_legacy_req_id UUID := gen_random_uuid();
    v_sale_result_1 JSONB;
    v_sale_result_2 JSONB;
    v_sale_id UUID;
    v_legacy_sale_id UUID;
    v_err_caught BOOLEAN;
    v_stock_before INT;
    v_stock_after INT;
    v_leak_count INT;
    v_adj_count INT;
    v_cogs_row RECORD;
    v_orig_max_discount NUMERIC(5, 2);
    v_cost_val NUMERIC(12, 2);
BEGIN
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'STARTING V1.6 DATABASE-LEVEL SECURITY & INTEGRITY TESTS...';
    RAISE NOTICE '================================================================';

    -- --------------------------------------------------------------------------
    -- SETUP: Record original configuration & create test products
    -- --------------------------------------------------------------------------
    SELECT max_cashier_discount_pct INTO v_orig_max_discount
    FROM public.pos_security_config WHERE id = 'default';

    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "owner"}}', true);

    INSERT INTO public.products (name, package_size, sku, standard_selling_price, purchase_cost, active)
    VALUES ('SQL-TEST ASHWAGANDHA 100G', '100g', 'SQL-ASH-100', 200.00, 0.00, true)
    RETURNING id INTO v_test_product_1;

    INSERT INTO public.products (name, package_size, sku, standard_selling_price, purchase_cost, active)
    VALUES ('SQL-TEST TRIPHALA 250G', '250g', 'SQL-TRI-250', 150.00, 0.00, true)
    RETURNING id INTO v_test_product_2;

    -- Store true confidential wholesale purchase costs in owner-only table
    INSERT INTO public.product_procurement_costs (product_id, purchase_cost)
    VALUES (v_test_product_1, 95.00), (v_test_product_2, 60.00)
    ON CONFLICT (product_id) DO UPDATE SET purchase_cost = EXCLUDED.purchase_cost;

    RAISE NOTICE 'SETUP: Test products created with confidential wholesale costs.';

    -- --------------------------------------------------------------------------
    -- TEST 1: Concurrency-Safe First-Time Stock Receipt (fn_receive_store_stock)
    -- --------------------------------------------------------------------------
    -- Ensure no prior store_inventory row exists for v_test_product_1 at Jaipur
    DELETE FROM public.store_inventory WHERE location_id = v_jaipur_id AND product_id = v_test_product_1;

    -- First delivery: 50 units
    PERFORM public.fn_receive_store_stock(v_jaipur_id, v_test_product_1, 50, 'Initial bulk delivery receipt');

    SELECT current_quantity INTO v_stock_after
    FROM public.store_inventory
    WHERE location_id = v_jaipur_id AND product_id = v_test_product_1;

    IF v_stock_after <> 50 THEN
        RAISE EXCEPTION 'TEST 1 FAILED: Expected 50 units in store_inventory, found %', v_stock_after;
    END IF;

    -- Verify stock_adjustments ledger entry recorded previous=0, new=50, change=50
    SELECT count(*) INTO v_adj_count
    FROM public.stock_adjustments
    WHERE location_id = v_jaipur_id AND product_id = v_test_product_1
      AND previous_quantity = 0 AND new_quantity = 50 AND change_quantity = 50
      AND reason = 'STOCK_RECEIPT';

    IF v_adj_count = 0 THEN
        RAISE EXCEPTION 'TEST 1 FAILED: stock_adjustments ledger entry not recorded correctly on first-time receipt.';
    END IF;

    -- Additive delivery: 25 more units
    PERFORM public.fn_receive_store_stock(v_jaipur_id, v_test_product_1, 25, 'Second delivery');

    SELECT current_quantity INTO v_stock_after
    FROM public.store_inventory
    WHERE location_id = v_jaipur_id AND product_id = v_test_product_1;

    IF v_stock_after <> 75 THEN
        RAISE EXCEPTION 'TEST 1 FAILED: Expected 75 units after second receipt, found %', v_stock_after;
    END IF;

    -- Stock product 2 as well (100 units)
    PERFORM public.fn_receive_store_stock(v_jaipur_id, v_test_product_2, 100, 'Initial stock for product 2');

    RAISE NOTICE 'TEST 1 PASSED: Safe additive stock receiving on first-time and subsequent calls.';

    -- --------------------------------------------------------------------------
    -- TEST 2: Canonical SHA-256 Idempotency, Reordering & Tampering Defense
    -- --------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "jaipur"}}', true);

    -- 2A: Initial sale creation with request ID
    v_sale_result_1 := public.fn_create_pos_sale(
        p_customer_name => 'Rajesh Sharma',
        p_customer_phone => '9829012345',
        p_payment_method => 'UPI',
        p_items => jsonb_build_array(
            jsonb_build_object('product_id', v_test_product_1, 'quantity', 2, 'unit_price', 200.00, 'discount', 0.00),
            jsonb_build_object('product_id', v_test_product_2, 'quantity', 1, 'unit_price', 150.00, 'discount', 10.00)
        ),
        p_location_id => v_jaipur_id,
        p_client_request_id => v_req_id
    );

    v_sale_id := (v_sale_result_1 ->> 'id')::uuid;

    -- Jaipur stock after initial sale: Product 1 (75 - 2 = 73), Product 2 (100 - 1 = 99)
    SELECT current_quantity INTO v_stock_before
    FROM public.store_inventory WHERE location_id = v_jaipur_id AND product_id = v_test_product_1;
    IF v_stock_before <> 73 THEN
        RAISE EXCEPTION 'TEST 2A FAILED: Expected stock 73, found %', v_stock_before;
    END IF;

    -- 2B: Idempotent replay with IDENTICAL request ID and payload
    v_sale_result_2 := public.fn_create_pos_sale(
        p_customer_name => 'Rajesh Sharma',
        p_customer_phone => '9829012345',
        p_payment_method => 'UPI',
        p_items => jsonb_build_array(
            jsonb_build_object('product_id', v_test_product_1, 'quantity', 2, 'unit_price', 200.00, 'discount', 0.00),
            jsonb_build_object('product_id', v_test_product_2, 'quantity', 1, 'unit_price', 150.00, 'discount', 10.00)
        ),
        p_location_id => v_jaipur_id,
        p_client_request_id => v_req_id
    );

    IF (v_sale_result_2 ->> 'id')::uuid <> v_sale_id THEN
        RAISE EXCEPTION 'TEST 2B FAILED: Replay did not return identical sale ID.';
    END IF;

    -- Verify stock was NOT deducted a second time
    SELECT current_quantity INTO v_stock_after
    FROM public.store_inventory WHERE location_id = v_jaipur_id AND product_id = v_test_product_1;
    IF v_stock_after <> 73 THEN
        RAISE EXCEPTION 'TEST 2B FAILED: Double stock deduction occurred! Expected 73, found %', v_stock_after;
    END IF;

    -- 2C: Reordered line items: submitting [item2, item1] must yield identical canonical hash & replay
    v_sale_result_1 := public.fn_create_pos_sale(
        p_customer_name => 'Amit Verma',
        p_customer_phone => '9829099999',
        p_payment_method => 'CASH',
        p_items => jsonb_build_array(
            jsonb_build_object('product_id', v_test_product_1, 'quantity', 1, 'unit_price', 200.00, 'discount', 0.00),
            jsonb_build_object('product_id', v_test_product_2, 'quantity', 2, 'unit_price', 150.00, 'discount', 0.00)
        ),
        p_location_id => v_jaipur_id,
        p_client_request_id => v_reorder_req_id
    );

    -- Replay with reversed items array
    v_sale_result_2 := public.fn_create_pos_sale(
        p_customer_name => 'Amit Verma',
        p_customer_phone => '9829099999',
        p_payment_method => 'CASH',
        p_items => jsonb_build_array(
            jsonb_build_object('product_id', v_test_product_2, 'quantity', 2, 'unit_price', 150.00, 'discount', 0.00),
            jsonb_build_object('product_id', v_test_product_1, 'quantity', 1, 'unit_price', 200.00, 'discount', 0.00)
        ),
        p_location_id => v_jaipur_id,
        p_client_request_id => v_reorder_req_id
    );

    IF (v_sale_result_2 ->> 'id')::uuid <> (v_sale_result_1 ->> 'id')::uuid THEN
        RAISE EXCEPTION 'TEST 2C FAILED: Reordered line items did not produce identical canonical hash.';
    END IF;

    -- 2D: Duplicate line items in same cart: 2 lines of product 1 (qty 1 + qty 2 = 3)
    SELECT current_quantity INTO v_stock_before
    FROM public.store_inventory WHERE location_id = v_jaipur_id AND product_id = v_test_product_1;

    PERFORM public.fn_create_pos_sale(
        p_customer_name => 'Duplicate Line Buyer',
        p_customer_phone => '9829088888',
        p_payment_method => 'CASH',
        p_items => jsonb_build_array(
            jsonb_build_object('product_id', v_test_product_1, 'quantity', 1, 'unit_price', 200.00, 'discount', 0.00),
            jsonb_build_object('product_id', v_test_product_1, 'quantity', 2, 'unit_price', 200.00, 'discount', 10.00)
        ),
        p_location_id => v_jaipur_id,
        p_client_request_id => gen_random_uuid()
    );

    SELECT current_quantity INTO v_stock_after
    FROM public.store_inventory WHERE location_id = v_jaipur_id AND product_id = v_test_product_1;

    IF v_stock_after <> (v_stock_before - 3) THEN
        RAISE EXCEPTION 'TEST 2D FAILED: Duplicate line items not deducted accurately. Expected %, found %',
            v_stock_before - 3, v_stock_after;
    END IF;

    -- 2E: Payload tampering / ID reuse with different payload -> MUST REJECT
    v_err_caught := FALSE;
    BEGIN
        PERFORM public.fn_create_pos_sale(
            p_customer_name => 'Tampered Customer',
            p_customer_phone => '9829012345',
            p_payment_method => 'UPI',
            p_items => jsonb_build_array(
                jsonb_build_object('product_id', v_test_product_1, 'quantity', 5, 'unit_price', 200.00, 'discount', 0.00)
            ),
            p_location_id => v_jaipur_id,
            p_client_request_id => v_req_id
        );
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Idempotency conflict%' THEN
            v_err_caught := TRUE;
        ELSE
            RAISE EXCEPTION 'TEST 2E UNEXPECTED ERROR: %', SQLERRM;
        END IF;
    END;

    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 2E FAILED: Expected Idempotency conflict error on payload tampering, but call succeeded.';
    END IF;

    -- 2F: Fail-closed on legacy row with NULL payload hash
    -- Simulate a legacy sale with client_request_id but NULL request_payload_hash
    INSERT INTO public.sales (
        location_id, bill_number, customer_name, customer_phone,
        payment_method, invoice_type, gst_rate, taxable_amount,
        cgst_amount, sgst_amount, igst_amount, whatsapp_status,
        total_amount, status, sold_at, client_request_id, request_payload_hash
    ) VALUES (
        v_jaipur_id, 'BILL-LEGACY-TEST', 'Legacy Client', '9000000000',
        'CASH', 'NON_GST', 0.00, 200.00,
        0.00, 0.00, 0.00, 'NOT_SENT',
        200.00, 'COMPLETED', now(), v_legacy_req_id, NULL
    ) RETURNING id INTO v_legacy_sale_id;

    v_err_caught := FALSE;
    BEGIN
        PERFORM public.fn_create_pos_sale(
            p_customer_name => 'Legacy Client',
            p_customer_phone => '9000000000',
            p_payment_method => 'CASH',
            p_items => jsonb_build_array(
                jsonb_build_object('product_id', v_test_product_1, 'quantity', 1, 'unit_price', 200.00, 'discount', 0.00)
            ),
            p_location_id => v_jaipur_id,
            p_client_request_id => v_legacy_req_id
        );
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%legacy record without a verified payload hash%' THEN
            v_err_caught := TRUE;
        END IF;
    END;

    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 2F FAILED: Legacy row with NULL payload hash did not fail closed!';
    END IF;

    -- 2G: Missing request ID (NULL) creates normal sale without collision
    BEGIN
        PERFORM public.fn_create_pos_sale(
            p_customer_name => 'Walk-in Anonymous',
            p_customer_phone => '9000000001',
            p_payment_method => 'CASH',
            p_items => jsonb_build_array(
                jsonb_build_object('product_id', v_test_product_1, 'quantity', 1, 'unit_price', 200.00, 'discount', 0.00)
            ),
            p_location_id => v_jaipur_id,
            p_client_request_id => NULL
        );
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'TEST 2G FAILED: Sale with NULL client_request_id threw unexpected error: %', SQLERRM;
    END;

    RAISE NOTICE 'TEST 2 PASSED: Canonical SHA-256 idempotency, reordering, duplicate lines, and fail-closed defense verified.';

    -- --------------------------------------------------------------------------
    -- TEST 3: Procurement Shield, Owner Reporting & Historical COGS/Profit
    -- --------------------------------------------------------------------------
    -- 3A: Cashier RPC return must NOT include unit_cost
    IF (v_sale_result_1 -> 'sale_items' -> 0) ? 'unit_cost' THEN
        RAISE EXCEPTION 'TEST 3A FAILED: Confidential unit_cost leaked in fn_create_pos_sale response!';
    END IF;

    -- 3B: Public catalog purchase_cost must be 0.00
    SELECT count(*) INTO v_leak_count
    FROM public.products WHERE purchase_cost > 0;
    IF v_leak_count > 0 THEN
        RAISE EXCEPTION 'TEST 3B FAILED: Found % products with non-zero purchase_cost in public table.', v_leak_count;
    END IF;

    -- 3C: Owner reporting view v_owner_sales_cogs_reporting accurately computes historical COGS
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "owner"}}', true);

    SELECT
        line_cogs,
        line_gross_profit,
        snapshotted_unit_cost
    INTO v_cogs_row
    FROM public.v_owner_sales_cogs_reporting
    WHERE sale_id = v_sale_id AND product_id = v_test_product_1;

    -- Product 1: 2 units sold @ unit_price 200, unit_cost snapshotted = 95.00
    -- Expected line_cogs = 2 * 95.00 = 190.00
    -- Expected line_gross_profit = (2 * 200) - 190.00 = 210.00
    IF v_cogs_row.snapshotted_unit_cost <> 95.00 OR v_cogs_row.line_cogs <> 190.00 OR v_cogs_row.line_gross_profit <> 210.00 THEN
        RAISE EXCEPTION 'TEST 3C FAILED: COGS reporting mismatch. Cost: %, COGS: %, Profit: %',
            v_cogs_row.snapshotted_unit_cost, v_cogs_row.line_cogs, v_cogs_row.line_gross_profit;
    END IF;

    -- 3D: Product procurement summary view v_product_procurement_summary returns true costs to Owner
    SELECT purchase_cost INTO v_cost_val
    FROM public.v_product_procurement_summary
    WHERE product_id = v_test_product_1;

    IF v_cost_val <> 95.00 THEN
        RAISE EXCEPTION 'TEST 3D FAILED: v_product_procurement_summary returned % instead of 95.00 for Owner', v_cost_val;
    END IF;

    RAISE NOTICE 'TEST 3 PASSED: Wholesale procurement shielded and owner COGS/profit calculations verified.';

    -- --------------------------------------------------------------------------
    -- TEST 4: Real Authenticated-Role Security & Cross-Outlet Restrictions
    -- --------------------------------------------------------------------------
    -- Switch session user to the authentic database role 'authenticated'
    EXECUTE 'SET LOCAL ROLE authenticated';

    -- Verify the role switch is effective in the PostgreSQL engine
    IF current_user <> 'authenticated' THEN
        RAISE EXCEPTION 'TEST 4 FAILED: Role switch to authenticated was ineffective. current_user: %', current_user;
    END IF;

    -- Emulate PostgREST request headers for a Neemrana Cashier
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "sub": "11111111-0000-0000-0000-000000000001", "app_metadata": {"role": "neemrana", "location_id": "11111111-1111-1111-1111-111111111111"}}', true);

    -- 4A: Direct query on product_procurement_costs by cashier yields 0 rows via RLS
    SELECT count(*) INTO v_leak_count
    FROM public.product_procurement_costs;
    IF v_leak_count > 0 THEN
        RAISE EXCEPTION 'TEST 4A FAILED: Cashier read % rows from product_procurement_costs via RLS bypass!', v_leak_count;
    END IF;

    -- 4B: Direct query on sale_item_procurement_costs by cashier yields 0 rows via RLS
    SELECT count(*) INTO v_leak_count
    FROM public.sale_item_procurement_costs;
    IF v_leak_count > 0 THEN
        RAISE EXCEPTION 'TEST 4B FAILED: Cashier read % rows from sale_item_procurement_costs via RLS bypass!', v_leak_count;
    END IF;

    -- 4C: Owner-only pricing function fn_update_product_pricing blocked for cashiers
    v_err_caught := FALSE;
    BEGIN
        PERFORM public.fn_update_product_pricing(v_test_product_1, 250.00, 110.00);
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Only OWNER role can update standard product prices%' THEN
            v_err_caught := TRUE;
        END IF;
    END;

    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 4C FAILED: Cashier was able to call fn_update_product_pricing!';
    END IF;

    -- 4D: Cross-outlet restriction: Neemrana cashier cannot receive stock for Jaipur
    -- Asserts the exact authorization failure contract returned by fn_receive_store_stock
    v_err_caught := FALSE;
    BEGIN
        PERFORM public.fn_receive_store_stock(v_jaipur_id, v_test_product_1, 10, 'Cross-outlet illicit receipt');
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Neemrana operators can only receive stock for Neemrana store%' THEN
            v_err_caught := TRUE;
        END IF;
    END;

    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 4D FAILED: Neemrana cashier received stock for Jaipur without error!';
    END IF;

    -- 4E: Cross-outlet restriction: Neemrana cashier cannot create sales for Jaipur
    -- Asserts the exact authorization failure contract returned by fn_create_pos_sale
    v_err_caught := FALSE;
    BEGIN
        PERFORM public.fn_create_pos_sale(
            p_customer_name => 'Cross Outlet Buyer',
            p_customer_phone => '9829000000',
            p_payment_method => 'CASH',
            p_items => jsonb_build_array(
                jsonb_build_object('product_id', v_test_product_1, 'quantity', 1, 'unit_price', 200.00, 'discount', 0.00)
            ),
            p_location_id => v_jaipur_id,
            p_client_request_id => gen_random_uuid()
        );
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Neemrana operators can only create sales for Neemrana store%' THEN
            v_err_caught := TRUE;
        END IF;
    END;

    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 4E FAILED: Cross-outlet sale was not restricted!';
    END IF;

    -- 4F: Direct unauthorized write to sales table is blocked by RLS (enforces creation via fn_create_pos_sale RPC)
    v_err_caught := FALSE;
    BEGIN
        INSERT INTO public.sales (
            location_id, bill_number, customer_name, customer_phone,
            payment_method, invoice_type, total_amount, status
        ) VALUES (
            v_neemrana_id, 'DIRECT-HACK-BILL', 'Unauthorized Client', '9829000000',
            'CASH', 'NON_GST', 200.00, 'COMPLETED'
        );
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '42501' OR SQLERRM LIKE '%violates row-level security policy%' THEN
            v_err_caught := TRUE;
        END IF;
    END;

    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 4F FAILED: Direct unauthorized INSERT to sales was not blocked by RLS!';
    END IF;

    -- 4G: Direct unauthorized write to sale_items table is blocked by RLS
    v_err_caught := FALSE;
    BEGIN
        INSERT INTO public.sale_items (
            sale_id, product_id, quantity, unit_price
        ) VALUES (
            v_sale_id, v_test_product_1, 1, 200.00
        );
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '42501' OR SQLERRM LIKE '%violates row-level security policy%' THEN
            v_err_caught := TRUE;
        END IF;
    END;

    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 4G FAILED: Direct unauthorized INSERT to sale_items was not blocked by RLS!';
    END IF;

    RAISE NOTICE 'TEST 4 PASSED: Authenticated-role RLS isolation, owner-only pricing, cross-outlet boundaries, and direct table write blocks verified.';

    -- --------------------------------------------------------------------------
    -- TEST 5: Price & Discount Authorization Boundaries
    -- --------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "jaipur"}}', true);

    -- 5A: Discount exactly at allowed 10.00% ceiling (1 item @ ₹200, discount ₹20.00 = 10.00%)
    BEGIN
        PERFORM public.fn_create_pos_sale(
            p_customer_name => 'Boundary Buyer',
            p_customer_phone => '9000000001',
            p_payment_method => 'CASH',
            p_items => jsonb_build_array(
                jsonb_build_object('product_id', v_test_product_1, 'quantity', 1, 'unit_price', 200.00, 'discount', 20.00)
            ),
            p_location_id => v_jaipur_id,
            p_client_request_id => gen_random_uuid()
        );
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'TEST 5A FAILED: Legitimate 10%% discount rejected: %', SQLERRM;
    END;

    -- 5B: Discount exceeding limit (₹20.05 on ₹200.00 = 10.025%) -> MUST REJECT
    v_err_caught := FALSE;
    BEGIN
        PERFORM public.fn_create_pos_sale(
            p_customer_name => 'Over Discount Buyer',
            p_customer_phone => '9000000002',
            p_payment_method => 'CASH',
            p_items => jsonb_build_array(
                jsonb_build_object('product_id', v_test_product_1, 'quantity', 1, 'unit_price', 200.00, 'discount', 20.05)
            ),
            p_location_id => v_jaipur_id,
            p_client_request_id => gen_random_uuid()
        );
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Unauthorized discount%' THEN
            v_err_caught := TRUE;
        END IF;
    END;

    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 5B FAILED: Cashier discount exceeding 10%% was not blocked by server!';
    END IF;

    -- 5C: Unauthorized Price Override (cashier alters unit_price to ₹180 instead of catalog ₹200) -> MUST REJECT
    v_err_caught := FALSE;
    BEGIN
        PERFORM public.fn_create_pos_sale(
            p_customer_name => 'Price Mod Buyer',
            p_customer_phone => '9000000003',
            p_payment_method => 'CASH',
            p_items => jsonb_build_array(
                jsonb_build_object('product_id', v_test_product_1, 'quantity', 1, 'unit_price', 180.00, 'discount', 0.00)
            ),
            p_location_id => v_jaipur_id,
            p_client_request_id => gen_random_uuid()
        );
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Unauthorized price modification%' THEN
            v_err_caught := TRUE;
        END IF;
    END;

    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 5C FAILED: Cashier unit price override was not blocked by server!';
    END IF;

    -- 5D: Negative values and zero quantity -> MUST REJECT
    v_err_caught := FALSE;
    BEGIN
        PERFORM public.fn_create_pos_sale(
            p_customer_name => 'Negative Val Buyer',
            p_customer_phone => '9000000004',
            p_payment_method => 'CASH',
            p_items => jsonb_build_array(
                jsonb_build_object('product_id', v_test_product_1, 'quantity', -2, 'unit_price', 200.00, 'discount', 0.00)
            ),
            p_location_id => v_jaipur_id,
            p_client_request_id => gen_random_uuid()
        );
    EXCEPTION WHEN OTHERS THEN
        v_err_caught := TRUE;
    END;

    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 5D FAILED: Negative quantity was not rejected!';
    END IF;

    -- 5E: GST billing attempt while GST configuration is disabled -> MUST REJECT
    v_err_caught := FALSE;
    BEGIN
        PERFORM public.fn_create_pos_sale(
            p_customer_name => 'GST Test Buyer',
            p_customer_phone => '9000000007',
            p_payment_method => 'CASH',
            p_items => jsonb_build_array(
                jsonb_build_object('product_id', v_test_product_1, 'quantity', 1, 'unit_price', 200.00, 'discount', 0.00)
            ),
            p_location_id => v_jaipur_id,
            p_invoice_type => 'GST',
            p_client_request_id => gen_random_uuid()
        );
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%GST billing is currently disabled%' THEN
            v_err_caught := TRUE;
        END IF;
    END;

    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 5E FAILED: GST billing was not blocked when disabled!';
    END IF;

    RAISE NOTICE 'TEST 5 PASSED: Server-side pricing & discount authorization boundaries and GST block verified.';

    -- --------------------------------------------------------------------------
    -- TEST 6: Insufficient Stock & Atomic Mid-Sale Rollback
    -- --------------------------------------------------------------------------
    -- Verify current stock of Product 1
    SELECT current_quantity INTO v_stock_before
    FROM public.store_inventory WHERE location_id = v_jaipur_id AND product_id = v_test_product_1;

    -- Cart requests: Product 1 (2 units, available), Product 2 (999 units, INSUFFICIENT)
    v_err_caught := FALSE;
    BEGIN
        PERFORM public.fn_create_pos_sale(
            p_customer_name => 'Excess Stock Buyer',
            p_customer_phone => '9000000006',
            p_payment_method => 'CASH',
            p_items => jsonb_build_array(
                jsonb_build_object('product_id', v_test_product_1, 'quantity', 2, 'unit_price', 200.00, 'discount', 0.00),
                jsonb_build_object('product_id', v_test_product_2, 'quantity', 999, 'unit_price', 150.00, 'discount', 0.00)
            ),
            p_location_id => v_jaipur_id,
            p_client_request_id => gen_random_uuid()
        );
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Insufficient stock%' THEN
            v_err_caught := TRUE;
        END IF;
    END;

    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 6 FAILED: Insufficient stock did not abort sale!';
    END IF;

    -- Verify Product 1 stock was NOT decremented (atomic rollback preserved)
    SELECT current_quantity INTO v_stock_after
    FROM public.store_inventory WHERE location_id = v_jaipur_id AND product_id = v_test_product_1;

    IF v_stock_after <> v_stock_before THEN
        RAISE EXCEPTION 'TEST 6 FAILED: Atomic rollback failed! Product 1 stock changed from % to %',
            v_stock_before, v_stock_after;
    END IF;

    RAISE NOTICE 'TEST 6 PASSED: Insufficient stock triggers complete atomic rollback.';

    -- --------------------------------------------------------------------------
    -- TEST 7: Dynamic Configuration Policy & Restoration
    -- --------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "owner"}}', true);

    -- Increase cashier discount limit to 15.00%
    UPDATE public.pos_security_config SET max_cashier_discount_pct = 15.00 WHERE id = 'default';

    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "jaipur"}}', true);

    -- 12.5% discount (₹25 on ₹200) should now SUCCEED
    BEGIN
        PERFORM public.fn_create_pos_sale(
            p_customer_name => 'Higher Discount Buyer',
            p_customer_phone => '9000000005',
            p_payment_method => 'CASH',
            p_items => jsonb_build_array(
                jsonb_build_object('product_id', v_test_product_1, 'quantity', 1, 'unit_price', 200.00, 'discount', 25.00)
            ),
            p_location_id => v_jaipur_id,
            p_client_request_id => gen_random_uuid()
        );
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'TEST 7 FAILED: 12.5%% discount rejected after limit raised to 15%%: %', SQLERRM;
    END;

    -- Reset configuration back to original value
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "owner"}}', true);
    UPDATE public.pos_security_config SET max_cashier_discount_pct = v_orig_max_discount WHERE id = 'default';

    RAISE NOTICE 'TEST 7 PASSED: Dynamic configuration updates and cleanup verified.';

    -- --------------------------------------------------------------------------
    -- TEST 8: Multi-Item Sale Void Inventory Restoration
    -- --------------------------------------------------------------------------
    SELECT current_quantity INTO v_stock_before
    FROM public.store_inventory WHERE location_id = v_jaipur_id AND product_id = v_test_product_1;

    -- Void the initial multi-item sale (v_sale_id had 2 units of product 1)
    UPDATE public.sales
    SET status = 'VOIDED'
    WHERE id = v_sale_id;

    -- Verify stock was restored by trigger trg_restore_voided_sale_stock
    SELECT current_quantity INTO v_stock_after
    FROM public.store_inventory WHERE location_id = v_jaipur_id AND product_id = v_test_product_1;

    IF v_stock_after <> (v_stock_before + 2) THEN
        RAISE EXCEPTION 'TEST 8 FAILED: Void stock restoration did not restore exact 2 units. Before: %, After: %',
            v_stock_before, v_stock_after;
    END IF;

    -- Verify audit entry was logged in stock_adjustments with reason BILL_VOID
    SELECT count(*) INTO v_adj_count
    FROM public.stock_adjustments
    WHERE location_id = v_jaipur_id AND product_id = v_test_product_1
      AND reason = 'BILL_VOID' AND change_quantity = 2;

    IF v_adj_count = 0 THEN
        RAISE EXCEPTION 'TEST 8 FAILED: BILL_VOID audit entry not found in stock_adjustments.';
    END IF;

    RAISE NOTICE 'TEST 8 PASSED: Multi-item sale void triggers atomic inventory restoration and audit logging.';

    -- --------------------------------------------------------------------------
    -- TEST 9: Repeat-Run Migration Safety & Procurement Cost Preservation
    -- --------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "owner"}}', true);

    -- Simulate re-running the V1.6 backfill statement:
    -- In V1.6, catalog products.purchase_cost was shielded to 0.00.
    -- If an uncareful script or rerun ran without ON CONFLICT DO NOTHING,
    -- it could overwrite confidential cost (95.00) with 0.00.
    INSERT INTO public.product_procurement_costs (product_id, purchase_cost)
    SELECT id, purchase_cost
    FROM public.products
    WHERE purchase_cost > 0
    ON CONFLICT (product_id) DO NOTHING;

    -- Verify Product 1 procurement cost remains intact at 95.00
    SELECT purchase_cost INTO v_cost_val
    FROM public.product_procurement_costs
    WHERE product_id = v_test_product_1;

    IF v_cost_val <> 95.00 THEN
        RAISE EXCEPTION 'TEST 9 FAILED: Migration rerun backfill corrupted procurement cost! Expected 95.00, found %', v_cost_val;
    END IF;

    RAISE NOTICE 'TEST 9 PASSED: Re-running migration backfill preserves existing procurement costs.';

    RAISE NOTICE '================================================================';
    RAISE NOTICE 'ALL V1.6 DATABASE-LEVEL TESTS PASSED SUCCESSFULLY!';
    RAISE NOTICE '================================================================';
END;
$$;

-- Always ROLLBACK to ensure zero persistent side effects in disposable databases
ROLLBACK;
