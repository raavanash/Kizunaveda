-- Kizuna Veda V1 Inventory Database Verification & Client RLS Testing Suite
-- 
-- IMPORTANT ARCHITECTURAL & SECURITY NOTICE:
-- 1. DATABASE CONSTRAINT & TRIGGER VERIFICATION (THIS SCRIPT):
--    This SQL script executes in a database session to validate SQL-level rules,
--    CHECK constraints, stock validation triggers (concurrency safe), transfer update
--    restrictions, and absolute historical transaction log deletion prevention.
--    In SQL-editor / superuser sessions, PL/pgSQL function set_config('request.jwt.claims', ...)
--    tests simulated database-session role checks (get_current_user_role()), but DOES NOT PROVE
--    client RLS enforcement because database superusers bypass RLS policies by default.
--
-- 2. REAL AUTHENTICATED CLIENT RLS VERIFICATION:
--    Production RLS policies must be verified using real authenticated HTTP client connections
--    (e.g., Supabase Flutter/JS SDK or PostgREST REST API) using JWTs signed by Supabase Auth
--    with app_metadata role claims: OWNER, NEEMRANA, JAIPUR.
--    See the bottom of this file for the complete Client RLS Verification Guide.

DO $$
DECLARE
    v_test_raw_mat_id UUID;
    v_test_product_id UUID;
    v_transfer_id UUID;
    v_sale_id UUID;
    v_err_caught BOOLEAN;
    v_neemrana_finished INT;
    v_jaipur_finished INT;
    v_discrepancy INT;
BEGIN
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'STARTING STRENGTHENED V1 INVENTORY DATABASE & TRIGGER TESTS...';
    RAISE NOTICE '================================================================';

    -- Simulate OWNER role for initial test dataset setup via GUC helper
    PERFORM set_config('request.jwt.claims', '{"app_metadata": {"role": "OWNER"}}', true);

    -- Setup: Create test raw material & finished product variant
    INSERT INTO public.raw_materials (name, unit_of_measure)
    VALUES ('VERIF TULSI LEAVES V3', 'KG')
    RETURNING id INTO v_test_raw_mat_id;

    INSERT INTO public.products (name, package_size, sku)
    VALUES ('VERIF TULSI PACKET V3', '100g', 'VERIF-TULSI-100G-V3')
    RETURNING id INTO v_test_product_id;

    -- Receive 200.0 KG raw material at Neemrana (unit_cost = 50.00, total_cost = 10000.00)
    INSERT INTO public.raw_material_receipts (raw_material_id, location_id, quantity, unit_cost, supplier_reference)
    VALUES (v_test_raw_mat_id, '11111111-1111-1111-1111-111111111111'::uuid, 200.0, 50.00, 'INV-SUP-303');
    RAISE NOTICE 'SETUP PASSED: Raw material received at Neemrana.';

    -- ------------------------------------------------------------------------
    -- TEST 1: RAW MATERIAL STOCK PROTECTION
    -- Attempting to consume 250.0 KG (exceeds available 200.0 KG)
    -- ------------------------------------------------------------------------
    v_err_caught := FALSE;
    BEGIN
        INSERT INTO public.packing_records (location_id, product_id, raw_material_id, raw_material_consumed, packed_quantity)
        VALUES ('11111111-1111-1111-1111-111111111111'::uuid, v_test_product_id, v_test_raw_mat_id, 250.0, 1000);
    EXCEPTION WHEN OTHERS THEN
        v_err_caught := TRUE;
    END;
    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 1 FAILED: Over-consumption of raw material was not blocked!';
    ELSE
        RAISE NOTICE 'TEST 1 PASSED: Over-consumption of raw material blocked by database trigger.';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 2: BUSINESS HAPPY PATH - NEEMRANA PACKING
    -- Neemrana packs 1,000 finished packets (consuming 100.0 KG raw material)
    -- ------------------------------------------------------------------------
    INSERT INTO public.packing_records (location_id, product_id, raw_material_id, raw_material_consumed, packed_quantity)
    VALUES ('11111111-1111-1111-1111-111111111111'::uuid, v_test_product_id, v_test_raw_mat_id, 100.0, 1000);
    RAISE NOTICE 'TEST 2 PASSED: Packed 1,000 finished packets at Neemrana.';

    -- ------------------------------------------------------------------------
    -- TEST 3: OVER-DISPATCH PROTECTION AT NEEMRANA (INSERT & UPDATE)
    -- Total packed = 1000. Attempt to dispatch 1050 packets.
    -- ------------------------------------------------------------------------
    v_err_caught := FALSE;
    BEGIN
        INSERT INTO public.transfers (product_id, from_location_id, to_location_id, dispatched_quantity)
        VALUES (v_test_product_id, '11111111-1111-1111-1111-111111111111'::uuid, '22222222-2222-2222-2222-222222222222'::uuid, 1050);
    EXCEPTION WHEN OTHERS THEN
        v_err_caught := TRUE;
    END;
    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 3 FAILED: Neemrana over-dispatch (INSERT) was not blocked!';
    ELSE
        RAISE NOTICE 'TEST 3 PASSED: Neemrana over-dispatch (INSERT) blocked by trigger.';
    END IF;

    -- Dispatch valid 980 packets from Neemrana
    INSERT INTO public.transfers (product_id, from_location_id, to_location_id, dispatched_quantity)
    VALUES (v_test_product_id, '11111111-1111-1111-1111-111111111111'::uuid, '22222222-2222-2222-2222-222222222222'::uuid, 980)
    RETURNING id INTO v_transfer_id;
    RAISE NOTICE 'SETUP PASSED: Dispatched 980 packets from Neemrana to Jaipur.';

    -- ------------------------------------------------------------------------
    -- TEST 4: JAIPUR ROLE TRANSFER UPDATE RESTRICTION
    -- Jaipur role attempting to modify dispatched_quantity (should fail)
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claims', '{"app_metadata": {"role": "JAIPUR"}}', true);

    v_err_caught := FALSE;
    BEGIN
        UPDATE public.transfers
        SET dispatched_quantity = 900
        WHERE id = v_transfer_id;
    EXCEPTION WHEN OTHERS THEN
        v_err_caught := TRUE;
    END;
    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 4 FAILED: Jaipur altering dispatch quantity was not blocked!';
    ELSE
        RAISE NOTICE 'TEST 4 PASSED: Jaipur modifying dispatch fields blocked by trigger.';
    END IF;

    -- Confirm valid receipt as JAIPUR role (Received 975, Reason: '5 damaged in transit')
    UPDATE public.transfers
    SET received_quantity = 975, received_at = now(), discrepancy_reason = '5 damaged in transit'
    WHERE id = v_transfer_id;
    RAISE NOTICE 'TEST 4B PASSED: Jaipur successfully updated receipt confirmation fields.';

    -- ------------------------------------------------------------------------
    -- TEST 5: SIMULATED DATABASE-SESSION ROLE HELPER CHECK
    -- (Note: Real client RLS policy enforcement requires Authenticated Client JWT verification)
    -- ------------------------------------------------------------------------

    -- 5A: get_current_user_role() function returns lowercased role
    IF public.get_current_user_role() <> 'jaipur' THEN
        RAISE EXCEPTION 'TEST 5A FAILED: Expected role jaipur, got %', public.get_current_user_role();
    ELSE
        RAISE NOTICE 'TEST 5A PASSED: Role helper correctly extracted "jaipur".';
    END IF;

    -- Switch to NEEMRANA role
    PERFORM set_config('request.jwt.claims', '{"app_metadata": {"role": "NEEMRANA"}}', true);
    IF public.get_current_user_role() <> 'neemrana' THEN
        RAISE EXCEPTION 'TEST 5B FAILED: Expected role neemrana, got %', public.get_current_user_role();
    ELSE
        RAISE NOTICE 'TEST 5B PASSED: Role helper correctly extracted "neemrana".';
    END IF;

    -- Switch back to OWNER role
    PERFORM set_config('request.jwt.claims', '{"app_metadata": {"role": "OWNER"}}', true);
    IF public.get_current_user_role() <> 'owner' THEN
        RAISE EXCEPTION 'TEST 5C FAILED: Expected role owner, got %', public.get_current_user_role();
    ELSE
        RAISE NOTICE 'TEST 5C PASSED: Role helper correctly extracted "owner".';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 6: JAIPUR POS SALE & OVER-SELLING PROTECTION
    -- Confirmed received = 975. Sell 300 packets.
    -- ------------------------------------------------------------------------
    INSERT INTO public.sales (location_id, bill_number, customer_phone, total_amount)
    VALUES ('22222222-2222-2222-2222-222222222222'::uuid, 'BILL-VERIF-303', '9876543210', 4500.00)
    RETURNING id INTO v_sale_id;

    INSERT INTO public.sale_items (sale_id, product_id, quantity, unit_price)
    VALUES (v_sale_id, v_test_product_id, 300, 15.00);
    RAISE NOTICE 'TEST 6 PASSED: Recorded sale of 300 packets at Jaipur.';

    -- Over-sell test (Attempting to sell 700 additional packets when only 675 remain)
    v_err_caught := FALSE;
    BEGIN
        INSERT INTO public.sale_items (sale_id, product_id, quantity, unit_price)
        VALUES (v_sale_id, v_test_product_id, 700, 15.00);
    EXCEPTION WHEN OTHERS THEN
        v_err_caught := TRUE;
    END;
    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 6B FAILED: Jaipur over-selling (INSERT) was not blocked!';
    ELSE
        RAISE NOTICE 'TEST 6B PASSED: Jaipur over-selling (INSERT) blocked by trigger.';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 7: HISTORICAL TRANSACTION DELETION PREVENTION (PERMANENTLY BLOCKED)
    -- Deletion of packing records, transfers, sales, sale_items, raw receipts
    -- must ALWAYS raise an exception without exception or bypass.
    -- ------------------------------------------------------------------------
    v_err_caught := FALSE;
    BEGIN
        DELETE FROM public.packing_records WHERE product_id = v_test_product_id;
    EXCEPTION WHEN OTHERS THEN
        v_err_caught := TRUE;
    END;
    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 7 FAILED: Deleting historical packing records was not blocked!';
    ELSE
        RAISE NOTICE 'TEST 7 PASSED: Deleting historical packing records strictly blocked by deletion trigger.';
    END IF;

    v_err_caught := FALSE;
    BEGIN
        DELETE FROM public.transfers WHERE product_id = v_test_product_id;
    EXCEPTION WHEN OTHERS THEN
        v_err_caught := TRUE;
    END;
    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'TEST 7B FAILED: Deleting historical transfer records was not blocked!';
    ELSE
        RAISE NOTICE 'TEST 7B PASSED: Deleting historical transfer records strictly blocked by deletion trigger.';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 8: BUSINESS FORMULA EXACT VERIFICATION
    -- Packed = 1000, Dispatched = 980, Received = 975, Sold = 300
    -- Expected: Neemrana finished = 20, Jaipur finished = 675, Discrepancy = 5
    -- ------------------------------------------------------------------------
    SELECT (COALESCE(SUM(packed_quantity), 0) - (SELECT COALESCE(SUM(dispatched_quantity), 0) FROM public.transfers WHERE product_id = v_test_product_id))
    INTO v_neemrana_finished
    FROM public.packing_records WHERE product_id = v_test_product_id;

    SELECT (COALESCE(SUM(received_quantity), 0) - (SELECT COALESCE(SUM(si.quantity), 0) FROM public.sale_items si JOIN public.sales s ON s.id = si.sale_id WHERE si.product_id = v_test_product_id))
    INTO v_jaipur_finished
    FROM public.transfers WHERE product_id = v_test_product_id AND received_quantity IS NOT NULL;

    SELECT COALESCE(SUM(dispatched_quantity - received_quantity), 0)
    INTO v_discrepancy
    FROM public.transfers WHERE product_id = v_test_product_id AND received_quantity IS NOT NULL;

    IF v_neemrana_finished <> 20 THEN
        RAISE EXCEPTION 'BUSINESS CALC FAILED: Expected Neemrana finished=20, got %', v_neemrana_finished;
    END IF;

    IF v_jaipur_finished <> 675 THEN
        RAISE EXCEPTION 'BUSINESS CALC FAILED: Expected Jaipur finished=675, got %', v_jaipur_finished;
    END IF;

    IF v_discrepancy <> 5 THEN
        RAISE EXCEPTION 'BUSINESS CALC FAILED: Expected Discrepancy=5, got %', v_discrepancy;
    END IF;

    RAISE NOTICE 'TEST 8 PASSED: Business formula exact match! Neemrana finished=20, Jaipur finished=675, Discrepancy=5.';

    -- Safe teardown of verification test fixtures (prevents test data from polluting subsequent migrations)
    EXECUTE 'ALTER TABLE public.sale_items DISABLE TRIGGER trg_no_delete_sale_items';
    EXECUTE 'ALTER TABLE public.sales DISABLE TRIGGER trg_no_delete_sales';
    EXECUTE 'ALTER TABLE public.transfers DISABLE TRIGGER trg_no_delete_transfers';
    EXECUTE 'ALTER TABLE public.packing_records DISABLE TRIGGER trg_no_delete_packing';
    EXECUTE 'ALTER TABLE public.raw_material_receipts DISABLE TRIGGER trg_no_delete_raw_receipts';

    DELETE FROM public.sale_items WHERE sale_id = v_sale_id;
    DELETE FROM public.sales WHERE id = v_sale_id;
    DELETE FROM public.transfers WHERE id = v_transfer_id;
    DELETE FROM public.packing_records WHERE product_id = v_test_product_id;
    DELETE FROM public.raw_material_receipts WHERE raw_material_id = v_test_raw_mat_id;
    DELETE FROM public.products WHERE id = v_test_product_id;
    DELETE FROM public.raw_materials WHERE id = v_test_raw_mat_id;

    EXECUTE 'ALTER TABLE public.sale_items ENABLE TRIGGER trg_no_delete_sale_items';
    EXECUTE 'ALTER TABLE public.sales ENABLE TRIGGER trg_no_delete_sales';
    EXECUTE 'ALTER TABLE public.transfers ENABLE TRIGGER trg_no_delete_transfers';
    EXECUTE 'ALTER TABLE public.packing_records ENABLE TRIGGER trg_no_delete_packing';
    EXECUTE 'ALTER TABLE public.raw_material_receipts ENABLE TRIGGER trg_no_delete_raw_receipts';

    RAISE NOTICE '================================================================';
    RAISE NOTICE 'ALL DATABASE CONSTRAINT & TRIGGER VERIFICATION TESTS PASSED!';
    RAISE NOTICE '================================================================';
END;
$$;

/*
================================================================================
AUTHENTICATED CLIENT RLS VERIFICATION SUITE GUIDE
================================================================================

To execute REAL production RLS policy testing against a Supabase environment:

1. Create 3 test accounts in Supabase Auth (or test environment):
   - owner@kizunaveda.test (app_metadata: {"role": "OWNER"})
   - neemrana@kizunaveda.test (app_metadata: {"role": "NEEMRANA"})
   - jaipur@kizunaveda.test (app_metadata: {"role": "JAIPUR"})

2. Test matrix using Supabase Flutter / JS SDK or PostgREST HTTP calls:

   A) OWNER ROLE TEST:
      - Authenticate as owner@kizunaveda.test
      - Verify SELECT/INSERT/UPDATE on products, raw_materials, packing_records, transfers, sales.
      - Expected result: 200 OK for all authorized operations.

   B) NEEMRANA ROLE TEST:
      - Authenticate as neemrana@kizunaveda.test
      - Attempt SELECT on raw_materials, packing_records, transfers -> 200 OK.
      - Attempt INSERT into packing_records (Neemrana location) -> 200 OK.
      - Attempt INSERT into sales (Jaipur location) -> 403 Forbidden / 42501 RLS Policy Violation.
      - Attempt UPDATE on sales -> 403 Forbidden / 42501 RLS Policy Violation.

   C) JAIPUR ROLE TEST:
      - Authenticate as jaipur@kizunaveda.test
      - Attempt SELECT on transfers, sales -> 200 OK.
      - Attempt INSERT into sales (Jaipur location) -> 200 OK.
      - Attempt SELECT or INSERT on raw_materials -> empty response / 403 Forbidden.
      - Attempt INSERT into packing_records -> 403 Forbidden / 42501 RLS Policy Violation.
      - Attempt INSERT into transfers (Neemrana dispatch) -> 403 Forbidden / 42501 RLS Policy Violation.
      - Attempt UPDATE on transfers (received_quantity, received_at, discrepancy_reason) -> 200 OK.
      - Attempt UPDATE on transfers (dispatched_quantity) -> 403 Forbidden / Database trigger error.

   D) UNAUTHENTICATED / INVALID ROLE TEST:
      - Anonymous connection or user with app_metadata role = "INVALID"
      - Attempt SELECT/INSERT on any table -> empty list or 403 Forbidden.

================================================================================
*/