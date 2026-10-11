-- ============================================================================
-- KIZUNA VEDA V1.4 READ-ONLY POST-DEPLOYMENT VERIFICATION SCRIPT
-- Strictly read-only; executes zero modifications, deletes, or mutations.
-- ============================================================================

-- 1. Verify Sales Table is Clean (Expected: 0 rows)
SELECT 
    'public.sales count' AS check_item,
    count(*) AS actual_value,
    0 AS expected_value,
    CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM public.sales;

-- 2. Verify Sale Items Table is Clean (Expected: 0 rows)
SELECT 
    'public.sale_items count' AS check_item,
    count(*) AS actual_value,
    0 AS expected_value,
    CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM public.sale_items;

-- 3. Verify Store Inventory Non-Zero Rows (Expected: 0 rows with current_quantity <> 0)
-- Actual timestamp column confirmed from V1.3 schema: `updated_at`.
SELECT 
    'store_inventory non-zero stock count' AS check_item,
    count(*) AS actual_value,
    0 AS expected_value,
    CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM public.store_inventory
WHERE current_quantity <> 0;

-- 4. Verify Store Inventory Total Product Coverage (both stores initialized with 0)
SELECT 
    loc.name AS store_name,
    loc.id AS location_id,
    count(si.id) AS initialized_product_rows,
    count(p.id) AS active_products_count,
    COALESCE(sum(si.current_quantity), 0) AS total_physical_units,
    CASE 
        WHEN count(si.id) = count(p.id) AND COALESCE(sum(si.current_quantity), 0) = 0 THEN 'PASS' 
        ELSE 'FAIL' 
    END AS status
FROM public.locations loc
CROSS JOIN public.products p
LEFT JOIN public.store_inventory si 
    ON si.location_id = loc.id AND si.product_id = p.id
WHERE loc.id IN (
    '11111111-1111-1111-1111-111111111111'::uuid,
    '22222222-2222-2222-2222-222222222222'::uuid
)
AND p.active = true
GROUP BY loc.name, loc.id;

-- 5. Verify Locations: Both Are Independent Retail Outlets (RETAIL type, active)
SELECT 
    code,
    name,
    location_type,
    active,
    CASE 
        WHEN location_type = 'RETAIL' AND active = true THEN 'PASS' 
        ELSE 'FAIL' 
    END AS status
FROM public.locations
WHERE id IN (
    '11111111-1111-1111-1111-111111111111'::uuid,
    '22222222-2222-2222-2222-222222222222'::uuid
)
ORDER BY code;

-- 6. Verify Production Triggers on Sales & Sale Items are Restored to Original States
-- The authorized pre-reset state for all five triggers on the live database was 'O' (Origin/Default Enabled).
-- The migration captures and restores exact catalog states without assuming universal enable.
SELECT 
    n.nspname || '.' || c.relname AS target_table,
    t.tgname AS trigger_name,
    t.tgenabled AS current_trigger_state,
    'O' AS expected_original_state,
    CASE t.tgenabled 
        WHEN 'O' THEN 'ORIGIN (Enabled)'
        WHEN 'A' THEN 'ALWAYS (Enabled)'
        WHEN 'D' THEN 'DISABLED'
        WHEN 'R' THEN 'REPLICA ONLY'
        ELSE 'UNKNOWN'
    END AS state_description,
    CASE 
        WHEN t.tgenabled = 'O' THEN 'PASS (Exact match with pre-reset state O)'
         ELSE 'FAIL (Expected pre-reset state O, found ' || t.tgenabled::text || ')'
    END AS status
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
ORDER BY target_table, trigger_name;

-- 7. Verify Bill Number Sequence is Preserved (Exactly at 10011, Next is BILL-010012)
-- The authorized highest sequential trial bill completed was BILL-010011.
-- The sequence was neither restarted nor advanced by the migration.
-- In PostgreSQL, last_value and is_called are queried directly from the sequence relation public.seq_bill_number.
SELECT 
    'public.seq_bill_number' AS sequence_name,
    last_value AS current_last_value,
    is_called,
    10011 AS expected_preserved_value,
    true AS expected_is_called,
    CASE 
        WHEN last_value = 10011 AND is_called = true THEN 'PASS (Preserved at 10011; next bill will be BILL-010012)'
        ELSE 'FAIL (Expected last_value = 10011 and is_called = true; sequence was altered)'
    END AS status
FROM public.seq_bill_number;

-- 8. Verify Audit Ledger Entries for Reset (Informational Diagnostic with Structural Invariant Verification)
-- Note: Post-deployment data alone cannot prove the exact pre-reset non-zero inventory count.
-- If non-zero stock existed prior to reset, rows with reason 'ADMIN_TRIAL_RESET' were logged.
-- This check validates that all logged reset audit rows satisfy structural zeroing invariants.
SELECT 
    'stock_adjustments ADMIN_TRIAL_RESET audit integrity' AS check_item,
    count(*) AS actual_reset_rows_logged,
    count(*) FILTER (WHERE new_quantity = 0 AND change_quantity = -previous_quantity AND previous_quantity > 0 AND created_by IS NULL) AS structurally_valid_rows,
    CASE 
        WHEN count(*) = 0 THEN 'INFO: 0 reset audit rows (all store inventory was already 0 prior to reset; exact pre-reset count cannot be proven from post-deployment data alone)'
        WHEN count(*) = count(*) FILTER (WHERE new_quantity = 0 AND change_quantity = -previous_quantity AND previous_quantity > 0 AND created_by IS NULL)
            THEN 'INFO: ' || count(*) || ' reset audit row(s) logged; all rows strictly satisfy zeroing invariants (new_quantity=0, change_quantity=-previous_quantity). Note: Expected count cannot be proven from post-deployment data alone.'
        ELSE 'FAIL (Structural invariant violation detected in ADMIN_TRIAL_RESET audit rows)'
    END AS diagnostic_status
FROM public.stock_adjustments
WHERE reason = 'ADMIN_TRIAL_RESET';

-- 9. Verify RPC Signatures & Execution Grants (fn_create_pos_sale & fn_adjust_store_stock)
SELECT 
    p.proname AS function_name,
    pg_get_function_identity_arguments(p.oid) AS arguments,
    CASE WHEN has_function_privilege('authenticated', p.oid, 'EXECUTE') THEN 'PASS' ELSE 'FAIL' END AS execute_grant
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('fn_create_pos_sale', 'fn_adjust_store_stock')
ORDER BY p.proname;
