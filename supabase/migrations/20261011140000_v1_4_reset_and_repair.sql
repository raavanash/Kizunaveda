-- Kizuna Veda V1.4 Reset and Repair Migration
-- ============================================================================
-- MIGRATION POLICY: STRICT ONE-TIME EXECUTION (NON-IDEMPOTENT BY DESIGN)
-- This migration is strictly designed to execute ONCE on a target database
-- that contains the 16 authorized production trial sales.
-- If rerun, precondition checks will safely abort execution immediately.
--
-- Confirmed Reset Scope:
-- 1. Permanently remove the 16 authorized trial sales (verified individually:
--    4 VOIDED: BILL-99699714, BILL-99725584, BILL-99791843, BILL-03461546
--    12 COMPLETED: BILL-04542542, BILL-010001 through BILL-010011) and their line items.
-- 2. Zero out store_inventory (current_quantity = 0, updated_at = now()) for all products
--    at both Neemrana and Jaipur.
-- 3. Change Neemrana location_type to 'RETAIL' (both stores are independent retail outlets).
-- 4. Preserve each trigger's original enabled state (capture state before, assert all 5 captured, restore exact state after).
-- 5. Preserve all products, users, locations, sequences (seq_bill_number preserved at current position 10011), and audit records.
-- 6. Retain server-side GST block.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. PRECONDITION ASSERTIONS: INDIVIDUAL VERIFICATION OF 16 TRIAL BILLS & STATUSES
-- ============================================================================
DO $$
DECLARE
    c_expected_voided_bills CONSTANT TEXT[] := ARRAY[
        'BILL-99699714',
        'BILL-99725584',
        'BILL-99791843',
        'BILL-03461546'
    ];
    c_expected_completed_bills CONSTANT TEXT[] := ARRAY[
        'BILL-04542542',
        'BILL-010001',
        'BILL-010002',
        'BILL-010003',
        'BILL-010004',
        'BILL-010005',
        'BILL-010006',
        'BILL-010007',
        'BILL-010008',
        'BILL-010009',
        'BILL-010010',
        'BILL-010011'
    ];
    c_all_expected_bills CONSTANT TEXT[] := ARRAY[
        'BILL-99699714',
        'BILL-99725584',
        'BILL-99791843',
        'BILL-03461546',
        'BILL-04542542',
        'BILL-010001',
        'BILL-010002',
        'BILL-010003',
        'BILL-010004',
        'BILL-010005',
        'BILL-010006',
        'BILL-010007',
        'BILL-010008',
        'BILL-010009',
        'BILL-010010',
        'BILL-010011'
    ];
    v_bill TEXT;
    v_total_sales INT;
    v_completed_sales INT;
    v_voided_sales INT;
    v_unauthorized_sales INT;
    v_neemrana_exists BOOLEAN;
    v_jaipur_exists BOOLEAN;
    v_active_products INT;
    v_seq_last_value BIGINT;
    v_seq_is_called BOOLEAN;
BEGIN
    -- A. Verify total sales count
    SELECT count(*) INTO v_total_sales FROM public.sales;
    IF v_total_sales = 0 THEN
        RAISE EXCEPTION 'Precondition Failed: public.sales table has 0 rows. This one-time migration has already been executed or trial sales are already cleared.';
    ELSIF v_total_sales <> 16 THEN
        RAISE EXCEPTION 'Precondition Failed: Expected exactly 16 trial sales in public.sales, but found %.', v_total_sales;
    END IF;

    -- B. Verify overall status breakdown (12 COMPLETED, 4 VOIDED)
    SELECT count(*) INTO v_completed_sales FROM public.sales WHERE status = 'COMPLETED';
    SELECT count(*) INTO v_voided_sales FROM public.sales WHERE status = 'VOIDED';

    IF v_completed_sales <> 12 OR v_voided_sales <> 4 THEN
        RAISE EXCEPTION 'Precondition Failed: Expected 12 COMPLETED and 4 VOIDED trial sales, but found % completed and % voided.',
            v_completed_sales, v_voided_sales;
    END IF;

    -- C. Individually verify existence and VOIDED status of each expected voided trial bill
    FOREACH v_bill IN ARRAY c_expected_voided_bills
    LOOP
        IF NOT EXISTS (SELECT 1 FROM public.sales WHERE bill_number = v_bill AND status = 'VOIDED') THEN
            RAISE EXCEPTION 'Precondition Failed: Expected VOIDED trial bill "%" was not found with status VOIDED in public.sales.', v_bill;
        END IF;
    END LOOP;

    -- D. Individually verify existence and COMPLETED status of each expected completed trial bill
    FOREACH v_bill IN ARRAY c_expected_completed_bills
    LOOP
        IF NOT EXISTS (SELECT 1 FROM public.sales WHERE bill_number = v_bill AND status = 'COMPLETED') THEN
            RAISE EXCEPTION 'Precondition Failed: Expected COMPLETED trial bill "%" was not found with status COMPLETED in public.sales.', v_bill;
        END IF;
    END LOOP;

    -- E. Verify no sales exist outside the authorized 16 trial bills
    SELECT count(*) INTO v_unauthorized_sales 
    FROM public.sales 
    WHERE NOT (bill_number = ANY(c_all_expected_bills));

    IF v_unauthorized_sales > 0 THEN
        RAISE EXCEPTION 'Precondition Failed: Detected % unauthorized bill(s) outside the 16 authorized trial bills. Aborting to protect live sales data.',
            v_unauthorized_sales;
    END IF;

    -- F. Assert canonical locations exist
    SELECT EXISTS (SELECT 1 FROM public.locations WHERE id = '11111111-1111-1111-1111-111111111111'::uuid) INTO v_neemrana_exists;
    SELECT EXISTS (SELECT 1 FROM public.locations WHERE id = '22222222-2222-2222-2222-222222222222'::uuid) INTO v_jaipur_exists;

    IF NOT v_neemrana_exists OR NOT v_jaipur_exists THEN
        RAISE EXCEPTION 'Precondition Failed: One or both canonical location UUIDs are missing in public.locations.';
    END IF;

    -- G. Assert active products exist
    SELECT count(*) INTO v_active_products FROM public.products WHERE active = true;
    IF v_active_products = 0 THEN
        RAISE EXCEPTION 'Precondition Failed: No active products found in public.products.';
    END IF;

    -- H. Assert seq_bill_number is at expected position (last_value = 10011, is_called = true)
    SELECT last_value, is_called INTO v_seq_last_value, v_seq_is_called
    FROM public.seq_bill_number;

    IF v_seq_last_value <> 10011 OR v_seq_is_called <> true THEN
        RAISE EXCEPTION 'Precondition Failed: seq_bill_number is not at authorized state (expected last_value = 10011, is_called = true, found last_value = %, is_called = %).',
            v_seq_last_value, v_seq_is_called;
    END IF;

    RAISE NOTICE 'Preconditions verified: All 16 authorized trial bills (4 VOIDED, 12 COMPLETED) exist individually with exact expected statuses. Zero unexpected bills found. Sequence seq_bill_number verified at last_value 10011.';
END;
$$;

-- ============================================================================
-- 2. CAPTURE & ASSERT ORIGINAL TRIGGER STATES (BEFORE ANY DISABLE ACTION)
-- ============================================================================
CREATE TEMP TABLE _temp_pre_reset_trigger_states ON COMMIT DROP AS
SELECT 
    n.nspname::text AS schema_name,
    c.relname::text AS table_name,
    t.tgname::text AS trigger_name,
    t.tgenabled::text AS original_state
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('sales', 'sale_items')
  AND t.tgname IN (
      'trg_no_delete_sales',
      'trg_no_delete_sale_items',
      'trg_restore_voided_sale_stock',
      'trg_restrict_sale_status_update',
      'trg_restrict_voided_sale_items'
  )
  AND NOT t.tgisinternal;

-- Assert snapshot completeness: all 5 required triggers must be captured on their expected tables
DO $$
DECLARE
    v_sales_triggers INT;
    v_item_triggers INT;
    v_total_triggers INT;
BEGIN
    SELECT count(*) INTO v_sales_triggers
    FROM _temp_pre_reset_trigger_states
    WHERE schema_name = 'public' AND table_name = 'sales'
      AND trigger_name IN ('trg_no_delete_sales', 'trg_restore_voided_sale_stock', 'trg_restrict_sale_status_update');

    SELECT count(*) INTO v_item_triggers
    FROM _temp_pre_reset_trigger_states
    WHERE schema_name = 'public' AND table_name = 'sale_items'
      AND trigger_name IN ('trg_no_delete_sale_items', 'trg_restrict_voided_sale_items');

    SELECT count(*) INTO v_total_triggers
    FROM _temp_pre_reset_trigger_states;

    IF v_sales_triggers <> 3 OR v_item_triggers <> 2 OR v_total_triggers <> 5 THEN
        RAISE EXCEPTION 'Precondition Failed: Trigger snapshot incomplete. Expected 3 triggers on public.sales and 2 on public.sale_items (total 5), but captured sales=%, sale_items=%, total=%. Aborting before disabling any triggers.',
            v_sales_triggers, v_item_triggers, v_total_triggers;
    END IF;

    RAISE NOTICE 'Trigger snapshot verified: Exactly 5 required triggers captured with their pre-reset states (sales: %, sale_items: %).',
        v_sales_triggers, v_item_triggers;
END;
$$;

-- Temporarily disable deletion-blocking and void-restoring triggers strictly for this transaction
ALTER TABLE public.sale_items DISABLE TRIGGER trg_no_delete_sale_items;
ALTER TABLE public.sales DISABLE TRIGGER trg_no_delete_sales;
ALTER TABLE public.sales DISABLE TRIGGER trg_restore_voided_sale_stock;
ALTER TABLE public.sales DISABLE TRIGGER trg_restrict_sale_status_update;
ALTER TABLE public.sale_items DISABLE TRIGGER trg_restrict_voided_sale_items;

-- ============================================================================
-- 3. CONTROLLED DELETION OF EXACT AUTHORIZED TRIAL SALES & SALE_ITEMS
-- ============================================================================
-- Delete sale_items strictly belonging to the 16 authorized trial bills
DELETE FROM public.sale_items
WHERE sale_id IN (
    SELECT id FROM public.sales
    WHERE bill_number IN (
        'BILL-99699714', 'BILL-99725584', 'BILL-99791843', 'BILL-03461546',
        'BILL-04542542', 'BILL-010001', 'BILL-010002', 'BILL-010003',
        'BILL-010004', 'BILL-010005', 'BILL-010006', 'BILL-010007',
        'BILL-010008', 'BILL-010009', 'BILL-010010', 'BILL-010011'
    )
);

-- Delete parent trial sales records strictly by authorized bill numbers
DELETE FROM public.sales
WHERE bill_number IN (
    'BILL-99699714', 'BILL-99725584', 'BILL-99791843', 'BILL-03461546',
    'BILL-04542542', 'BILL-010001', 'BILL-010002', 'BILL-010003',
    'BILL-010004', 'BILL-010005', 'BILL-010006', 'BILL-010007',
    'BILL-010008', 'BILL-010009', 'BILL-010010', 'BILL-010011'
);

-- ============================================================================
-- 4. RESTORE EXACT ORIGINAL TRIGGER STATES
-- ============================================================================
DO $$
DECLARE
    r RECORD;
    v_restored_count INT := 0;
BEGIN
    FOR r IN SELECT schema_name, table_name, trigger_name, original_state FROM _temp_pre_reset_trigger_states
    LOOP
        IF r.original_state = 'D' THEN
            EXECUTE format('ALTER TABLE %I.%I DISABLE TRIGGER %I', r.schema_name, r.table_name, r.trigger_name);
        ELSIF r.original_state = 'O' THEN
            EXECUTE format('ALTER TABLE %I.%I ENABLE TRIGGER %I', r.schema_name, r.table_name, r.trigger_name);
        ELSIF r.original_state = 'A' THEN
            EXECUTE format('ALTER TABLE %I.%I ENABLE ALWAYS TRIGGER %I', r.schema_name, r.table_name, r.trigger_name);
        ELSIF r.original_state = 'R' THEN
            EXECUTE format('ALTER TABLE %I.%I ENABLE REPLICA TRIGGER %I', r.schema_name, r.table_name, r.trigger_name);
        ELSE
            RAISE EXCEPTION 'Restoration Failed: Unknown trigger state "%" for trigger %.%', r.original_state, r.table_name, r.trigger_name;
        END IF;
        v_restored_count := v_restored_count + 1;
    END LOOP;

    IF v_restored_count <> 5 THEN
        RAISE EXCEPTION 'Restoration Failed: Expected to restore 5 triggers, but processed %.', v_restored_count;
    END IF;

    RAISE NOTICE 'Trigger restoration complete: Exactly % triggers restored to their exact original states.', v_restored_count;
END;
$$;

-- ============================================================================
-- 5. AUDIT & ZERO STORE INVENTORY
-- ============================================================================
-- Log an auditable ledger entry for any products with non-zero stock before zeroing.
-- Note: stock_adjustments.created_by permits NULL (migration context).
-- Reason 'ADMIN_TRIAL_RESET' is valid under CHECK (length(trim(reason)) > 0).
DO $$
DECLARE
    v_audit_rows_logged INT := 0;
BEGIN
    INSERT INTO public.stock_adjustments (
        location_id,
        product_id,
        previous_quantity,
        new_quantity,
        change_quantity,
        reason,
        notes,
        created_by,
        created_at
    )
    SELECT
        si.location_id,
        si.product_id,
        si.current_quantity,
        0,
        -si.current_quantity,
        'ADMIN_TRIAL_RESET',
        'Administrative reset: Trial inventory zeroed to establish initial physical stock entry baseline',
        NULL,
        timezone('utc'::text, now())
    FROM public.store_inventory si
    WHERE si.current_quantity > 0;

    GET DIAGNOSTICS v_audit_rows_logged = ROW_COUNT;
    RAISE NOTICE 'Audit ledger: % row(s) logged in stock_adjustments for products with non-zero stock.', v_audit_rows_logged;
END;
$$;

-- Ensure every active product has a canonical store_inventory row initialized to 0 for both stores.
-- Actual timestamp column confirmed from V1.3 schema: `updated_at`.
INSERT INTO public.store_inventory (location_id, product_id, current_quantity, updated_at)
SELECT loc.id, p.id, 0, timezone('utc'::text, now())
FROM (
    VALUES
        ('11111111-1111-1111-1111-111111111111'::uuid),
        ('22222222-2222-2222-2222-222222222222'::uuid)
) AS loc(id)
CROSS JOIN public.products p
WHERE p.active = true
ON CONFLICT (location_id, product_id)
DO UPDATE SET current_quantity = 0, updated_at = timezone('utc'::text, now());

-- Ensure all store_inventory rows are set to zero
UPDATE public.store_inventory
SET current_quantity = 0,
    updated_at = timezone('utc'::text, now());

-- ============================================================================
-- 6. UPDATE LOCATIONS: TWO INDEPENDENT RETAIL OUTLETS
-- ============================================================================
-- Update Neemrana to RETAIL location_type and normalize store names
UPDATE public.locations
SET location_type = 'RETAIL',
    name = 'Neemrana Retail Outlet',
    active = true
WHERE id = '11111111-1111-1111-1111-111111111111'::uuid;

UPDATE public.locations
SET location_type = 'RETAIL',
    name = 'Jaipur Retail Outlet',
    active = true
WHERE id = '22222222-2222-2222-2222-222222222222'::uuid;

-- ============================================================================
-- 7. POSTCONDITION ASSERTIONS
-- ============================================================================
DO $$
DECLARE
    v_remaining_sales INT;
    v_remaining_items INT;
    v_non_zero_stock INT;
    v_neemrana_type TEXT;
    v_neemrana_name TEXT;
    v_jaipur_type TEXT;
    v_jaipur_name TEXT;
    v_neemrana_rows INT;
    v_jaipur_rows INT;
    v_active_products INT;
    v_seq_post_value BIGINT;
    v_seq_post_called BOOLEAN;
    v_mismatched_triggers INT;
BEGIN
    -- 1. Assert sales and sale_items are 0
    SELECT count(*) INTO v_remaining_sales FROM public.sales;
    SELECT count(*) INTO v_remaining_items FROM public.sale_items;

    IF v_remaining_sales <> 0 OR v_remaining_items <> 0 THEN
        RAISE EXCEPTION 'Postcondition Failed: Tables not empty (remaining sales: %, items: %)',
            v_remaining_sales, v_remaining_items;
    END IF;

    -- 2. Assert all store_inventory rows have current_quantity = 0
    SELECT count(*) INTO v_non_zero_stock FROM public.store_inventory WHERE current_quantity <> 0;
    IF v_non_zero_stock <> 0 THEN
        RAISE EXCEPTION 'Postcondition Failed: % store_inventory rows have non-zero stock', v_non_zero_stock;
    END IF;

    -- 3. Assert complete product coverage in store_inventory for both locations
    SELECT count(*) INTO v_active_products FROM public.products WHERE active = true;
    SELECT count(*) INTO v_neemrana_rows FROM public.store_inventory WHERE location_id = '11111111-1111-1111-1111-111111111111'::uuid;
    SELECT count(*) INTO v_jaipur_rows FROM public.store_inventory WHERE location_id = '22222222-2222-2222-2222-222222222222'::uuid;

    IF v_neemrana_rows < v_active_products OR v_jaipur_rows < v_active_products THEN
        RAISE EXCEPTION 'Postcondition Failed: Incomplete store_inventory coverage (active products: %, Neemrana: %, Jaipur: %)',
            v_active_products, v_neemrana_rows, v_jaipur_rows;
    END IF;

    -- 4. Assert location records are RETAIL and names are normalized
    SELECT location_type, name INTO v_neemrana_type, v_neemrana_name FROM public.locations WHERE id = '11111111-1111-1111-1111-111111111111'::uuid;
    SELECT location_type, name INTO v_jaipur_type, v_jaipur_name FROM public.locations WHERE id = '22222222-2222-2222-2222-222222222222'::uuid;

    IF v_neemrana_type <> 'RETAIL' OR v_jaipur_type <> 'RETAIL' THEN
        RAISE EXCEPTION 'Postcondition Failed: Locations not set to RETAIL (Neemrana: %, Jaipur: %)',
            v_neemrana_type, v_jaipur_type;
    END IF;

    IF v_neemrana_name <> 'Neemrana Retail Outlet' OR v_jaipur_name <> 'Jaipur Retail Outlet' THEN
        RAISE EXCEPTION 'Postcondition Failed: Location names mismatch (Neemrana: %, Jaipur: %)',
            v_neemrana_name, v_jaipur_name;
    END IF;

    -- 5. Assert seq_bill_number was NOT modified or reset by migration
    SELECT last_value, is_called INTO v_seq_post_value, v_seq_post_called
    FROM public.seq_bill_number;

    IF v_seq_post_value <> 10011 OR v_seq_post_called <> true THEN
        RAISE EXCEPTION 'Postcondition Failed: seq_bill_number was modified (expected last_value = 10011, is_called = true, found last_value = %, is_called = %).',
            v_seq_post_value, v_seq_post_called;
    END IF;

    -- 6. Assert all 5 triggers in pg_trigger match their captured original states
    SELECT count(*) INTO v_mismatched_triggers
    FROM _temp_pre_reset_trigger_states s
    JOIN pg_class c ON c.relname = s.table_name
    JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = s.schema_name
    JOIN pg_trigger t ON t.tgrelid = c.oid AND t.tgname = s.trigger_name
    WHERE t.tgenabled::text <> s.original_state;

    IF v_mismatched_triggers > 0 THEN
        RAISE EXCEPTION 'Postcondition Failed: % trigger(s) failed to match their captured pre-reset states.',
            v_mismatched_triggers;
    END IF;

    RAISE NOTICE 'Postconditions verified: 0 sales, 0 sale_items, all % inventory rows are 0, both locations are active RETAIL outlets, sequence seq_bill_number preserved at 10011, all 5 triggers restored to exact pre-reset states.',
        (v_neemrana_rows + v_jaipur_rows);
END;
$$;

COMMIT;
