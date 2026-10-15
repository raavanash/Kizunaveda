-- ==============================================================================
-- KIZUNA VEDA — V1.7 Store Isolation & Transfers Hardening Database Test Suite
-- File: test/sql/v1_7_store_isolation_and_security_tests.sql
-- Description: Executes directly in PostgreSQL / Supabase SQL Editor.
--
-- REPEATABLE EXECUTION & SAFETY GUARANTEES:
-- 1. Entire suite runs inside a single transaction (BEGIN ... ROLLBACK).
-- 2. Leaves zero test artifacts in products, sales, inventory, or audit ledgers.
-- 3. Uses authentic SET LOCAL ROLE authenticated; with PostgREST JWT claims to
--    rigorously test real PostgreSQL engine privileges, RLS policies, and RPC contracts.
--
-- TEST MATRIX:
-- 1. Effective table-level privilege verification (anon / authenticated).
-- 2. Owner-only historical transfer read access & Cashier RLS filtering.
-- 3. Total rejection of transfer mutations (INSERT, UPDATE, DELETE).
-- 4. Fail-closed behavior & privilege revocation on fn_confirm_jaipur_receipt.
-- 5. Complete operational and inventory isolation (receipts, sales, voids, adjustments).
-- 6. Cross-store role spoofing rejection (receipts, sales, voids, direct table writes).
-- 7. Zero cross-store inventory contamination and clean rollback.
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
    v_neemrana_stock INT;
    v_jaipur_stock INT;
    v_neemrana_sale_res JSONB;
    v_jaipur_sale_res JSONB;
    v_neemrana_sale_id UUID;
    v_jaipur_sale_id UUID;
    v_err_caught BOOLEAN;
    v_rows_read INT;
    v_adj_count INT;
    v_historical_transfer_id UUID;
    v_dummy_id UUID := gen_random_uuid();
BEGIN
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'STARTING V1.7 STORE ISOLATION & TRANSFERS SECURITY TESTS...';
    RAISE NOTICE '================================================================';

    -- --------------------------------------------------------------------------
    -- SETUP: Insert a historical transfer fixture for audit read testing
    -- --------------------------------------------------------------------------
    -- Ensure test products exist in shared catalogue
    INSERT INTO public.products (name, package_size, sku, standard_selling_price, purchase_cost, active)
    VALUES ('V1.7 TEST BRAHMI VATI 60T', '60 tablets', 'V17-BRAHMI-' || gen_random_uuid()::text, 250.00, 0.00, true)
    RETURNING id INTO v_test_product_1;

    INSERT INTO public.products (name, package_size, sku, standard_selling_price, purchase_cost, active)
    VALUES ('V1.7 TEST SHATAVARI CHURNA 100G', '100g', 'V17-SHATAVARI-' || gen_random_uuid()::text, 180.00, 0.00, true)
    RETURNING id INTO v_test_product_2;

    -- Insert one historical transfer row directly as table owner (postgres)
    -- This simulates legacy historical dispatches that must remain readable by owner only
    INSERT INTO public.transfers (
        product_id, from_location_id, to_location_id, dispatched_quantity,
        received_quantity, dispatched_at, received_at, discrepancy_reason
    ) VALUES (
        v_test_product_1, v_neemrana_id, v_jaipur_id, 10,
        10, now() - INTERVAL '30 days', now() - INTERVAL '28 days', NULL
    )
    RETURNING id INTO v_historical_transfer_id;

    RAISE NOTICE 'SETUP: Test catalogue products and historical transfer fixture created.';

    -- --------------------------------------------------------------------------
    -- TEST 1: Table-Level Grants & Effective Privilege Verification
    -- --------------------------------------------------------------------------
    -- Verify anon has ZERO privileges on public.transfers
    IF has_table_privilege('anon', 'public.transfers', 'SELECT') OR
       has_table_privilege('anon', 'public.transfers', 'INSERT') OR
       has_table_privilege('anon', 'public.transfers', 'UPDATE') OR
       has_table_privilege('anon', 'public.transfers', 'DELETE') THEN
        RAISE EXCEPTION 'TEST 1 FAILED: anon role retains unexpected privileges on public.transfers!';
    END IF;

    -- Verify authenticated has ONLY SELECT privilege on public.transfers
    IF NOT has_table_privilege('authenticated', 'public.transfers', 'SELECT') THEN
        RAISE EXCEPTION 'TEST 1 FAILED: authenticated role lacks SELECT privilege on public.transfers!';
    END IF;

    IF has_table_privilege('authenticated', 'public.transfers', 'INSERT') OR
       has_table_privilege('authenticated', 'public.transfers', 'UPDATE') OR
       has_table_privilege('authenticated', 'public.transfers', 'DELETE') THEN
        RAISE EXCEPTION 'TEST 1 FAILED: authenticated role retains mutation privileges (INSERT/UPDATE/DELETE) on public.transfers!';
    END IF;

    RAISE NOTICE 'TEST 1 PASSED: Table grants strictly hardened. anon=0 privs, authenticated=SELECT only.';

    -- --------------------------------------------------------------------------
    -- Switch session user to authentic 'authenticated' database role
    -- --------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE authenticated';

    IF current_user <> 'authenticated' THEN
        RAISE EXCEPTION 'TEST SETUP FAILED: Role switch to authenticated was ineffective. current_user: %', current_user;
    END IF;

    -- --------------------------------------------------------------------------
    -- TEST 2: Owner-Only Historical Transfer Read Access & Cashier RLS Filtering
    -- --------------------------------------------------------------------------
    -- 2A: Owner query can see historical transfers
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "sub": "00000000-0000-0000-0000-000000000001", "app_metadata": {"role": "owner"}}', true);

    SELECT count(*) INTO v_rows_read
    FROM public.transfers
    WHERE id = v_historical_transfer_id;

    IF v_rows_read <> 1 THEN
        RAISE EXCEPTION 'TEST 2A FAILED: Owner was unable to read historical transfer fixture!';
    END IF;

    -- 2B: Neemrana Cashier query returns 0 rows via RLS
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "sub": "11111111-0000-0000-0000-000000000001", "app_metadata": {"role": "neemrana", "location_id": "11111111-1111-1111-1111-111111111111"}}', true);

    SELECT count(*) INTO v_rows_read
    FROM public.transfers
    WHERE id = v_historical_transfer_id;

    IF v_rows_read <> 0 THEN
        RAISE EXCEPTION 'TEST 2B FAILED: Neemrana Cashier read % transfer rows via RLS leak!', v_rows_read;
    END IF;

    -- 2C: Jaipur Cashier query returns 0 rows via RLS
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "sub": "22222222-0000-0000-0000-000000000002", "app_metadata": {"role": "jaipur", "location_id": "22222222-2222-2222-2222-222222222222"}}', true);

    SELECT count(*) INTO v_rows_read
    FROM public.transfers
    WHERE id = v_historical_transfer_id;

    IF v_rows_read <> 0 THEN
        RAISE EXCEPTION 'TEST 2C FAILED: Jaipur Cashier read % transfer rows via RLS leak!', v_rows_read;
    END IF;

    RAISE NOTICE 'TEST 2 PASSED: Owner historical transfer read verified; Cashier roles isolated (0 rows via RLS).';

    -- --------------------------------------------------------------------------
    -- TEST 3: Total Rejection of Transfer Mutations (INSERT, UPDATE, DELETE)
    -- --------------------------------------------------------------------------
    -- 3A: Owner attempt to INSERT into public.transfers is blocked
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "owner"}}', true);
    v_err_caught := FALSE;
    BEGIN
        INSERT INTO public.transfers (product_id, from_location_id, to_location_id, dispatched_quantity)
        VALUES (v_test_product_1, v_neemrana_id, v_jaipur_id, 5);
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '42501' OR SQLERRM LIKE '%permission denied%' OR SQLERRM LIKE '%violates row-level security policy%' THEN
            v_err_caught := TRUE;
        END IF;
    END;
    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 3A FAILED: Owner was able to INSERT into public.transfers!';
    END IF;

    -- 3B: Cashier attempt to INSERT into public.transfers is blocked
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "neemrana", "location_id": "11111111-1111-1111-1111-111111111111"}}', true);
    v_err_caught := FALSE;
    BEGIN
        INSERT INTO public.transfers (product_id, from_location_id, to_location_id, dispatched_quantity)
        VALUES (v_test_product_1, v_neemrana_id, v_jaipur_id, 5);
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '42501' OR SQLERRM LIKE '%permission denied%' OR SQLERRM LIKE '%violates row-level security policy%' THEN
            v_err_caught := TRUE;
        END IF;
    END;
    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 3B FAILED: Cashier was able to INSERT into public.transfers!';
    END IF;

    -- 3C: Owner attempt to UPDATE public.transfers is blocked
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "owner"}}', true);
    v_err_caught := FALSE;
    BEGIN
        UPDATE public.transfers
        SET received_quantity = 10
        WHERE id = v_historical_transfer_id;
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '42501' OR SQLERRM LIKE '%permission denied%' OR SQLERRM LIKE '%violates row-level security policy%' THEN
            v_err_caught := TRUE;
        END IF;
    END;
    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 3C FAILED: Owner was able to UPDATE public.transfers!';
    END IF;

    -- 3D: Cashier attempt to UPDATE public.transfers is blocked
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "jaipur", "location_id": "22222222-2222-2222-2222-222222222222"}}', true);
    v_err_caught := FALSE;
    BEGIN
        UPDATE public.transfers
        SET received_quantity = 10
        WHERE id = v_historical_transfer_id;
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '42501' OR SQLERRM LIKE '%permission denied%' OR SQLERRM LIKE '%violates row-level security policy%' THEN
            v_err_caught := TRUE;
        END IF;
    END;
    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 3D FAILED: Cashier was able to UPDATE public.transfers!';
    END IF;

    -- 3E: Owner attempt to DELETE from public.transfers is blocked
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "owner"}}', true);
    v_err_caught := FALSE;
    BEGIN
        DELETE FROM public.transfers WHERE id = v_historical_transfer_id;
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '42501' OR SQLERRM LIKE '%permission denied%' OR SQLERRM LIKE '%violates row-level security policy%' THEN
            v_err_caught := TRUE;
        END IF;
    END;
    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 3E FAILED: Owner was able to DELETE from public.transfers!';
    END IF;

    -- 3F: Cashier attempt to DELETE from public.transfers is blocked
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "neemrana", "location_id": "11111111-1111-1111-1111-111111111111"}}', true);
    v_err_caught := FALSE;
    BEGIN
        DELETE FROM public.transfers WHERE id = v_historical_transfer_id;
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '42501' OR SQLERRM LIKE '%permission denied%' OR SQLERRM LIKE '%violates row-level security policy%' THEN
            v_err_caught := TRUE;
        END IF;
    END;
    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 3F FAILED: Cashier was able to DELETE from public.transfers!';
    END IF;

    -- Switch back to postgres superuser to test trigger-level deletion block
    EXECUTE 'RESET ROLE';

    -- 3G: Even superuser attempt to DELETE is blocked by trg_no_delete_transfers
    v_err_caught := FALSE;
    BEGIN
        DELETE FROM public.transfers WHERE id = v_historical_transfer_id;
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Deletion of historical transaction logs is strictly prohibited%' OR
           SQLERRM LIKE '%Historical transfer records cannot be deleted%' THEN
            v_err_caught := TRUE;
        END IF;
    END;
    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 3G FAILED: Superuser was able to bypass historical transfer deletion trigger! Caught: %', SQLERRM;
    END IF;

    RAISE NOTICE 'TEST 3 PASSED: Total rejection of transfer mutations (INSERT, UPDATE, DELETE) verified.';

    -- Switch back to authenticated role for remaining tests
    EXECUTE 'SET LOCAL ROLE authenticated';

    -- --------------------------------------------------------------------------
    -- TEST 4: Fail-Closed Behavior & Privilege Revocation of fn_confirm_jaipur_receipt
    -- --------------------------------------------------------------------------
    -- 4A: Authenticated cashier calling fn_confirm_jaipur_receipt is denied (execute privilege revoked)
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "jaipur", "location_id": "22222222-2222-2222-2222-222222222222"}}', true);
    v_err_caught := FALSE;
    BEGIN
        PERFORM public.fn_confirm_jaipur_receipt(v_historical_transfer_id, 10, 'Test receipt attempt');
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '42501' OR SQLERRM LIKE '%permission denied%' OR SQLERRM LIKE '%Inter-store stock transfers are permanently disabled%' THEN
            v_err_caught := TRUE;
        END IF;
    END;
    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 4A FAILED: Cashier was able to execute fn_confirm_jaipur_receipt without error!';
    END IF;

    -- 4B: Even when executed by postgres role, the function body fails closed with explicit message
    EXECUTE 'RESET ROLE';
    v_err_caught := FALSE;
    BEGIN
        PERFORM public.fn_confirm_jaipur_receipt(v_historical_transfer_id, 10, 'Superuser receipt attempt');
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Inter-store stock transfers are permanently disabled: Neemrana and Jaipur operate as independent retail stores%' THEN
            v_err_caught := TRUE;
        END IF;
    END;
    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 4B FAILED: fn_confirm_jaipur_receipt did not fail closed with the expected message!';
    END IF;

    RAISE NOTICE 'TEST 4 PASSED: fn_confirm_jaipur_receipt fails closed and execution privileges are revoked.';

    -- --------------------------------------------------------------------------
    -- TEST 5: Complete Operational & Inventory Isolation Between Neemrana and Jaipur
    -- --------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE authenticated';

    -- 5A: Independent Stock Receipts
    -- Neemrana receives 50 units of Product 1
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "neemrana", "location_id": "11111111-1111-1111-1111-111111111111"}}', true);
    PERFORM public.fn_receive_store_stock(v_neemrana_id, v_test_product_1, 50, 'Neemrana bulk delivery');

    -- Jaipur receives 30 units of Product 1
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "jaipur", "location_id": "22222222-2222-2222-2222-222222222222"}}', true);
    PERFORM public.fn_receive_store_stock(v_jaipur_id, v_test_product_1, 30, 'Jaipur bulk delivery');

    -- Verify Neemrana stock is exactly 50
    SELECT current_quantity INTO v_neemrana_stock
    FROM public.store_inventory WHERE location_id = v_neemrana_id AND product_id = v_test_product_1;

    -- Verify Jaipur stock is exactly 30
    SELECT current_quantity INTO v_jaipur_stock
    FROM public.store_inventory WHERE location_id = v_jaipur_id AND product_id = v_test_product_1;

    IF v_neemrana_stock <> 50 OR v_jaipur_stock <> 30 THEN
        RAISE EXCEPTION 'TEST 5A FAILED: Initial receipts not isolated. Neemrana: %, Jaipur: %',
            v_neemrana_stock, v_jaipur_stock;
    END IF;

    -- Verify ledger entries in stock_adjustments are independently scoped
    -- 5A-1: Owner can see both stores' ledger entries
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "owner"}}', true);

    SELECT count(*) INTO v_adj_count
    FROM public.stock_adjustments
    WHERE location_id = v_neemrana_id AND product_id = v_test_product_1 AND reason = 'STOCK_RECEIPT';
    IF v_adj_count <> 1 THEN
        RAISE EXCEPTION 'TEST 5A FAILED: Neemrana stock receipt ledger missing or duplicated for Owner! Count: %', v_adj_count;
    END IF;

    SELECT count(*) INTO v_adj_count
    FROM public.stock_adjustments
    WHERE location_id = v_jaipur_id AND product_id = v_test_product_1 AND reason = 'STOCK_RECEIPT';
    IF v_adj_count <> 1 THEN
        RAISE EXCEPTION 'TEST 5A FAILED: Jaipur stock receipt ledger missing or duplicated for Owner! Count: %', v_adj_count;
    END IF;

    -- 5A-2: Neemrana cashier sees Neemrana ledger (1) but 0 for Jaipur via RLS
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "neemrana", "location_id": "11111111-1111-1111-1111-111111111111"}}', true);
    SELECT count(*) INTO v_adj_count
    FROM public.stock_adjustments
    WHERE location_id = v_jaipur_id AND product_id = v_test_product_1;
    IF v_adj_count <> 0 THEN
        RAISE EXCEPTION 'TEST 5A FAILED: Neemrana cashier leaked Jaipur stock_adjustments rows! Count: %', v_adj_count;
    END IF;

    -- 5A-3: Jaipur cashier sees Jaipur ledger (1) but 0 for Neemrana via RLS
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "jaipur", "location_id": "22222222-2222-2222-2222-222222222222"}}', true);
    SELECT count(*) INTO v_adj_count
    FROM public.stock_adjustments
    WHERE location_id = v_neemrana_id AND product_id = v_test_product_1;
    IF v_adj_count <> 0 THEN
        RAISE EXCEPTION 'TEST 5A FAILED: Jaipur cashier leaked Neemrana stock_adjustments rows! Count: %', v_adj_count;
    END IF;

    -- 5B: Independent POS Sales
    -- Sale of 5 units at Neemrana
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "neemrana", "location_id": "11111111-1111-1111-1111-111111111111"}}', true);
    v_neemrana_sale_res := public.fn_create_pos_sale(
        p_customer_name => 'Neemrana Customer',
        p_customer_phone => '9829111111',
        p_payment_method => 'CASH',
        p_items => jsonb_build_array(
            jsonb_build_object('product_id', v_test_product_1, 'quantity', 5, 'unit_price', 250.00, 'discount', 0.00)
        ),
        p_location_id => v_neemrana_id,
        p_client_request_id => gen_random_uuid()
    );
    v_neemrana_sale_id := (v_neemrana_sale_res ->> 'id')::uuid;

    -- Check stocks: Neemrana should be 45, Jaipur MUST be strictly 30 (untouched)
    SELECT current_quantity INTO v_neemrana_stock
    FROM public.store_inventory WHERE location_id = v_neemrana_id AND product_id = v_test_product_1;

    SELECT current_quantity INTO v_jaipur_stock
    FROM public.store_inventory WHERE location_id = v_jaipur_id AND product_id = v_test_product_1;

    IF v_neemrana_stock <> 45 OR v_jaipur_stock <> 30 THEN
        RAISE EXCEPTION 'TEST 5B FAILED: Neemrana sale contaminated Jaipur stock! Neemrana: %, Jaipur: %',
            v_neemrana_stock, v_jaipur_stock;
    END IF;

    -- Sale of 10 units at Jaipur
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "jaipur", "location_id": "22222222-2222-2222-2222-222222222222"}}', true);
    v_jaipur_sale_res := public.fn_create_pos_sale(
        p_customer_name => 'Jaipur Customer',
        p_customer_phone => '9829222222',
        p_payment_method => 'UPI',
        p_items => jsonb_build_array(
            jsonb_build_object('product_id', v_test_product_1, 'quantity', 10, 'unit_price', 250.00, 'discount', 0.00)
        ),
        p_location_id => v_jaipur_id,
        p_client_request_id => gen_random_uuid()
    );
    v_jaipur_sale_id := (v_jaipur_sale_res ->> 'id')::uuid;

    -- Check stocks: Neemrana MUST be strictly 45 (untouched), Jaipur should be 20
    SELECT current_quantity INTO v_neemrana_stock
    FROM public.store_inventory WHERE location_id = v_neemrana_id AND product_id = v_test_product_1;

    SELECT current_quantity INTO v_jaipur_stock
    FROM public.store_inventory WHERE location_id = v_jaipur_id AND product_id = v_test_product_1;

    IF v_neemrana_stock <> 45 OR v_jaipur_stock <> 20 THEN
        RAISE EXCEPTION 'TEST 5B FAILED: Jaipur sale contaminated Neemrana stock! Neemrana: %, Jaipur: %',
            v_neemrana_stock, v_jaipur_stock;
    END IF;

    -- 5C: Independent POS Voids
    -- Owner voids the Neemrana sale (restores 5 units to Neemrana)
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "owner"}}', true);
    UPDATE public.sales SET status = 'VOIDED' WHERE id = v_neemrana_sale_id;

    -- Check stocks: Neemrana restored to 50, Jaipur MUST remain strictly 20 (untouched)
    SELECT current_quantity INTO v_neemrana_stock
    FROM public.store_inventory WHERE location_id = v_neemrana_id AND product_id = v_test_product_1;

    SELECT current_quantity INTO v_jaipur_stock
    FROM public.store_inventory WHERE location_id = v_jaipur_id AND product_id = v_test_product_1;

    IF v_neemrana_stock <> 50 OR v_jaipur_stock <> 20 THEN
        RAISE EXCEPTION 'TEST 5C FAILED: Neemrana void contaminated Jaipur stock! Neemrana: %, Jaipur: %',
            v_neemrana_stock, v_jaipur_stock;
    END IF;

    -- 5D: Insufficient Stock Isolation
    -- Jaipur has 20 units. Neemrana has 50 units.
    -- Attempting to sell 25 units at Jaipur MUST fail with Insufficient stock.
    -- Neemrana's 50 units MUST NOT be used to fulfill the Jaipur shortfall!
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "jaipur", "location_id": "22222222-2222-2222-2222-222222222222"}}', true);
    v_err_caught := FALSE;
    BEGIN
        PERFORM public.fn_create_pos_sale(
            p_customer_name => 'Shortfall Customer',
            p_customer_phone => '9829333333',
            p_payment_method => 'CASH',
            p_items => jsonb_build_array(
                jsonb_build_object('product_id', v_test_product_1, 'quantity', 25, 'unit_price', 250.00, 'discount', 0.00)
            ),
            p_location_id => v_jaipur_id,
            p_client_request_id => gen_random_uuid()
        );
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Insufficient stock%' AND SQLERRM LIKE '%Available: 20%' THEN
            v_err_caught := TRUE;
        END IF;
    END;
    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 5D FAILED: Jaipur sold 25 units when only 20 were available! Cross-store stock tap detected!';
    END IF;

    -- Verify Neemrana stock remains untouched at 50
    SELECT current_quantity INTO v_neemrana_stock
    FROM public.store_inventory WHERE location_id = v_neemrana_id AND product_id = v_test_product_1;
    IF v_neemrana_stock <> 50 THEN
        RAISE EXCEPTION 'TEST 5D FAILED: Neemrana stock altered during Jaipur shortfall rejection! Found: %', v_neemrana_stock;
    END IF;

    RAISE NOTICE 'TEST 5 PASSED: Complete operational and inventory isolation verified (receipts, sales, voids, shortfalls).';

    -- --------------------------------------------------------------------------
    -- TEST 6: Cross-Store Role Spoofing & Authorization Boundary Rejection
    -- --------------------------------------------------------------------------
    -- 6A: Cross-Store Stock Receipt Spoofing
    -- Neemrana cashier attempts to receive stock for Jaipur -> REJECTED
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "neemrana", "location_id": "11111111-1111-1111-1111-111111111111"}}', true);
    v_err_caught := FALSE;
    BEGIN
        PERFORM public.fn_receive_store_stock(v_jaipur_id, v_test_product_2, 10, 'Spoofed Jaipur receipt');
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Neemrana operators can only receive stock for Neemrana store%' THEN
            v_err_caught := TRUE;
        END IF;
    END;
    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 6A FAILED: Neemrana cashier received stock for Jaipur!';
    END IF;

    -- Jaipur cashier attempts to receive stock for Neemrana -> REJECTED
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "jaipur", "location_id": "22222222-2222-2222-2222-222222222222"}}', true);
    v_err_caught := FALSE;
    BEGIN
        PERFORM public.fn_receive_store_stock(v_neemrana_id, v_test_product_2, 10, 'Spoofed Neemrana receipt');
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Jaipur operators can only receive stock for Jaipur store%' THEN
            v_err_caught := TRUE;
        END IF;
    END;
    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 6A FAILED: Jaipur cashier received stock for Neemrana!';
    END IF;

    -- 6B: Cross-Store POS Sale Spoofing
    -- Neemrana cashier attempts to create sale for Jaipur -> REJECTED
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "neemrana", "location_id": "11111111-1111-1111-1111-111111111111"}}', true);
    v_err_caught := FALSE;
    BEGIN
        PERFORM public.fn_create_pos_sale(
            p_customer_name => 'Spoofed Jaipur Buyer',
            p_customer_phone => '9829444444',
            p_payment_method => 'CASH',
            p_items => jsonb_build_array(
                jsonb_build_object('product_id', v_test_product_1, 'quantity', 1, 'unit_price', 250.00, 'discount', 0.00)
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
        RAISE EXCEPTION 'TEST 6B FAILED: Neemrana cashier created sale for Jaipur!';
    END IF;

    -- Jaipur cashier attempts to create sale for Neemrana -> REJECTED
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "jaipur", "location_id": "22222222-2222-2222-2222-222222222222"}}', true);
    v_err_caught := FALSE;
    BEGIN
        PERFORM public.fn_create_pos_sale(
            p_customer_name => 'Spoofed Neemrana Buyer',
            p_customer_phone => '9829555555',
            p_payment_method => 'CASH',
            p_items => jsonb_build_array(
                jsonb_build_object('product_id', v_test_product_1, 'quantity', 1, 'unit_price', 250.00, 'discount', 0.00)
            ),
            p_location_id => v_neemrana_id,
            p_client_request_id => gen_random_uuid()
        );
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Jaipur operators can only create sales for Jaipur store%' THEN
            v_err_caught := TRUE;
        END IF;
    END;
    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 6B FAILED: Jaipur cashier created sale for Neemrana!';
    END IF;

    -- 6C: Cashier Unauthorized Sale Void Rejection
    -- Cashier cannot void sales: RLS sales_update_policy restricts UPDATE to owner (0 rows updated)
    -- and fn_restrict_sale_status_update trigger guards status transitions
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "jaipur", "location_id": "22222222-2222-2222-2222-222222222222"}}', true);
    UPDATE public.sales SET status = 'VOIDED' WHERE id = v_jaipur_sale_id;
    GET DIAGNOSTICS v_rows_read = ROW_COUNT;

    IF v_rows_read <> 0 THEN
        RAISE EXCEPTION 'TEST 6C FAILED: Jaipur cashier was able to update % sales rows via RLS bypass!', v_rows_read;
    END IF;

    -- Verify sale status remains strictly COMPLETED under owner inspection
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "owner"}}', true);
    IF (SELECT status FROM public.sales WHERE id = v_jaipur_sale_id) <> 'COMPLETED' THEN
        RAISE EXCEPTION 'TEST 6C FAILED: Sale status was altered by cashier void attempt!';
    END IF;

    -- 6D: Direct Store Inventory Write Rejection
    -- Authenticated users cannot directly tamper with store_inventory balances;
    -- RLS store_inventory_update_policy enforces USING (false), rendering 0 rows modifiable.
    PERFORM set_config('request.jwt.claims', '{"role": "authenticated", "app_metadata": {"role": "jaipur", "location_id": "22222222-2222-2222-2222-222222222222"}}', true);
    UPDATE public.store_inventory
    SET current_quantity = 999
    WHERE location_id = v_jaipur_id AND product_id = v_test_product_1;
    GET DIAGNOSTICS v_rows_read = ROW_COUNT;

    IF v_rows_read <> 0 THEN
        RAISE EXCEPTION 'TEST 6D FAILED: Direct UPDATE on store_inventory modified % rows via RLS bypass!', v_rows_read;
    END IF;

    -- Verify stock remained untouched (20 units)
    SELECT current_quantity INTO v_jaipur_stock
    FROM public.store_inventory WHERE location_id = v_jaipur_id AND product_id = v_test_product_1;
    IF v_jaipur_stock <> 20 THEN
        RAISE EXCEPTION 'TEST 6D FAILED: Store inventory quantity was corrupted! Expected 20, got: %', v_jaipur_stock;
    END IF;

    -- Direct INSERT on store_inventory is rejected with RLS check violation
    v_err_caught := FALSE;
    BEGIN
        INSERT INTO public.store_inventory (location_id, product_id, current_quantity)
        VALUES (v_jaipur_id, v_test_product_2, 999);
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '42501' OR SQLERRM LIKE '%violates row-level security policy%' THEN
            v_err_caught := TRUE;
        END IF;
    END;
    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 6D FAILED: Direct INSERT to store_inventory was not blocked by RLS!';
    END IF;

    RAISE NOTICE 'TEST 6 PASSED: Cross-store role spoofing and unauthorized operations strictly rejected.';

    -- --------------------------------------------------------------------------
    -- TEST 7: Zero Cross-Store Contamination & Clean State
    -- --------------------------------------------------------------------------
    -- Confirm zero transfers exist from our operational tests
    SELECT count(*) INTO v_rows_read
    FROM public.transfers
    WHERE product_id IN (v_test_product_1, v_test_product_2)
      AND id <> v_historical_transfer_id;

    IF v_rows_read <> 0 THEN
        RAISE EXCEPTION 'TEST 7 FAILED: Found % new transfer rows created during store operations!', v_rows_read;
    END IF;

    RAISE NOTICE 'TEST 7 PASSED: Zero transfer records created; perfect operational isolation verified.';

    RAISE NOTICE '================================================================';
    RAISE NOTICE 'ALL V1.7 DATABASE-LEVEL ISOLATION & SECURITY TESTS PASSED!';
    RAISE NOTICE '================================================================';
END;
$$;

ROLLBACK;
