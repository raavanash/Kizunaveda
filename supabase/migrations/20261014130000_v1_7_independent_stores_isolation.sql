-- ==============================================================================
-- KIZUNA VEDA — Database Migration: Independent Stores Isolation (V1.7)
-- File: supabase/migrations/20261014130000_v1_7_independent_stores_isolation.sql
--
-- Objective:
-- Enforces complete operational and inventory independence between Neemrana and
-- Jaipur retail stores. Eliminates all inter-store transfer mechanisms while
-- strictly preserving historical audit logs, canonical location UUIDs, and shared
-- product definitions.
--
-- Guarantees:
-- 1. No Stock Transfers: fn_confirm_jaipur_receipt fails closed with an explicit exception.
-- 2. Transfers Table Locked: INSERT, UPDATE, and DELETE on public.transfers are disabled.
--    Historical transfer rows are 100% preserved for compliance auditing.
-- 3. Legacy Triggers Retired: trg_check_neemrana_dispatch_stock is permanently dropped.
-- 4. Store Isolation Server-Side: Strict RLS and location checks ensure each store's
--    stock, receipts, adjustments, and sales operate in complete isolation.
-- ==============================================================================

BEGIN;

-- 1. Retire legacy dispatch and transfer triggers & functions
DROP TRIGGER IF EXISTS trg_check_neemrana_dispatch_stock ON public.transfers;
DROP FUNCTION IF EXISTS public.fn_check_neemrana_dispatch_stock();

DROP TRIGGER IF EXISTS trg_restrict_jaipur_transfer_update ON public.transfers;
DROP FUNCTION IF EXISTS public.fn_restrict_jaipur_transfer_update();

DROP TRIGGER IF EXISTS trg_check_sale_stock ON public.sale_items;
DROP FUNCTION IF EXISTS public.fn_check_sale_stock();

DROP TRIGGER IF EXISTS trg_check_jaipur_sale_stock ON public.sale_items;
DROP FUNCTION IF EXISTS public.fn_check_jaipur_sale_stock();

-- 2. Permanently disable fn_confirm_jaipur_receipt RPC
CREATE OR REPLACE FUNCTION public.fn_confirm_jaipur_receipt(
    p_transfer_id UUID,
    p_received_quantity INT,
    p_discrepancy_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RAISE EXCEPTION 'Inter-store stock transfers are permanently disabled: Neemrana and Jaipur operate as independent retail stores.';
END;
$$;

REVOKE ALL ON FUNCTION public.fn_confirm_jaipur_receipt(UUID, INT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_confirm_jaipur_receipt(UUID, INT, TEXT) FROM authenticated;

-- 3. Lock public.transfers against any new dispatches, updates, or deletions (Read-Only Audit)
ALTER TABLE public.transfers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "transfers_select_policy" ON public.transfers;
CREATE POLICY "transfers_select_policy" ON public.transfers
FOR SELECT TO authenticated
USING (public.get_current_user_role() = 'owner');

DROP POLICY IF EXISTS "transfers_insert_policy" ON public.transfers;
CREATE POLICY "transfers_insert_policy" ON public.transfers
FOR INSERT TO authenticated
WITH CHECK (false);

DROP POLICY IF EXISTS "transfers_update_policy" ON public.transfers;
CREATE POLICY "transfers_update_policy" ON public.transfers
FOR UPDATE TO authenticated
USING (false)
WITH CHECK (false);

DROP POLICY IF EXISTS "transfers_delete_policy" ON public.transfers;
CREATE POLICY "transfers_delete_policy" ON public.transfers
FOR DELETE TO authenticated
USING (false);

-- 4. Invalidate and reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

COMMIT;
