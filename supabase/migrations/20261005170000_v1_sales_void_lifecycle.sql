-- Kizuna Veda V1 Sales Void Lifecycle & Immutability Migration
-- 
-- IMPORTANT:
-- 1. This is a NEW additive migration. Existing foundation migration (20261005120000_v1_inventory_foundation.sql) remains untouched.
-- 2. DO NOT EXECUTE AGAINST PRODUCTION SUPABASE AUTOMATICALLY.
-- 3. Adds sales.status ('COMPLETED', 'VOIDED').
-- 4. Ensures inventory stock triggers and calculations ONLY deduct COMPLETED sales.
-- 5. Restricts sale voiding to OWNER role only. Prevents un-voiding a VOIDED sale.
-- 6. Enforces strict immutability: core sale fields cannot be edited, and VOIDED sales reject new/modified sale_items.

-- ============================================================================
-- 1. ADD STATUS COLUMN TO SALES TABLE
-- ============================================================================
ALTER TABLE public.sales
ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'COMPLETED';

ALTER TABLE public.sales
DROP CONSTRAINT IF EXISTS chk_sale_status;

ALTER TABLE public.sales
ADD CONSTRAINT chk_sale_status CHECK (status IN ('COMPLETED', 'VOIDED'));

-- ============================================================================
-- 2. RESTRICT SALE UPDATE & VOID TRANSITIONS TRIGGER
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_restrict_sale_status_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Core fields of a completed/created sale are strictly immutable
    IF NEW.id <> OLD.id OR
       NEW.location_id <> OLD.location_id OR
       NEW.bill_number <> OLD.bill_number OR
       NEW.customer_phone IS DISTINCT FROM OLD.customer_phone OR
       NEW.total_amount <> OLD.total_amount OR
       NEW.sold_at <> OLD.sold_at OR
       NEW.created_at <> OLD.created_at THEN
        RAISE EXCEPTION 'Core sale fields (bill_number, total_amount, customer_phone, etc.) are strictly immutable once created.';
    END IF;

    -- Cannot un-void a VOIDED sale
    IF OLD.status = 'VOIDED' AND NEW.status <> 'VOIDED' THEN
        RAISE EXCEPTION 'A VOIDED sale cannot be reverted to COMPLETED.';
    END IF;

    -- Only OWNER role can void a completed sale
    IF OLD.status = 'COMPLETED' AND NEW.status = 'VOIDED' THEN
        IF public.get_current_user_role() <> 'owner' THEN
            RAISE EXCEPTION 'Only OWNER role is authorized to void completed sales.';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_restrict_sale_status_update ON public.sales;
CREATE TRIGGER trg_restrict_sale_status_update
BEFORE UPDATE ON public.sales
FOR EACH ROW
EXECUTE FUNCTION public.fn_restrict_sale_status_update();

-- ============================================================================
-- 3. VOIDED SALE ITEMS IMMUTABILITY TRIGGER
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_restrict_voided_sale_items()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_status TEXT;
BEGIN
    -- Check parent sale status for INSERT or UPDATE
    SELECT status INTO v_status FROM public.sales WHERE id = NEW.sale_id;
    IF v_status = 'VOIDED' THEN
        RAISE EXCEPTION 'Cannot add or modify line items belonging to a VOIDED sale.';
    END IF;

    IF TG_OP = 'UPDATE' THEN
        SELECT status INTO v_status FROM public.sales WHERE id = OLD.sale_id;
        IF v_status = 'VOIDED' THEN
            RAISE EXCEPTION 'Cannot modify line items belonging to a VOIDED sale.';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_restrict_voided_sale_items ON public.sale_items;
CREATE TRIGGER trg_restrict_voided_sale_items
BEFORE INSERT OR UPDATE ON public.sale_items
FOR EACH ROW
EXECUTE FUNCTION public.fn_restrict_voided_sale_items();

-- ============================================================================
-- 4. UPDATE JAIPUR SALE STOCK CHECK TRIGGER (COMPLETED SALES ONLY)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_check_jaipur_sale_stock()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_received INT := 0;
    v_total_sold INT := 0;
    v_available_stock INT := 0;
    v_sale_status TEXT;
BEGIN
    -- Check parent sale status
    SELECT status INTO v_sale_status FROM public.sales WHERE id = NEW.sale_id;
    IF v_sale_status = 'VOIDED' THEN
        RETURN NEW; -- Voided sales do not deduct stock
    END IF;

    PERFORM 1 FROM public.products WHERE id = NEW.product_id FOR UPDATE;

    SELECT COALESCE(SUM(received_quantity), 0)
    INTO v_total_received
    FROM public.transfers
    WHERE product_id = NEW.product_id
      AND to_location_id = '22222222-2222-2222-2222-222222222222'::uuid
      AND received_quantity IS NOT NULL;

    SELECT COALESCE(SUM(si.quantity), 0)
    INTO v_total_sold
    FROM public.sale_items si
    JOIN public.sales s ON s.id = si.sale_id
    WHERE si.product_id = NEW.product_id
      AND s.location_id = '22222222-2222-2222-2222-222222222222'::uuid
      AND s.status = 'COMPLETED'
      AND si.id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid);

    v_available_stock := v_total_received - v_total_sold;

    IF NEW.quantity > v_available_stock THEN
        RAISE EXCEPTION 'Jaipur sale quantity (%) exceeds available finished stock (%). Product ID: %',
            NEW.quantity, v_available_stock, NEW.product_id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_jaipur_sale_stock ON public.sale_items;
CREATE TRIGGER trg_check_jaipur_sale_stock
BEFORE INSERT OR UPDATE OF product_id, quantity
ON public.sale_items
FOR EACH ROW
EXECUTE FUNCTION public.fn_check_jaipur_sale_stock();

-- ============================================================================
-- 5. UPDATE POLICY FOR SALES STATUS MODIFICATION
-- ============================================================================
DROP POLICY IF EXISTS "sales_update_policy" ON public.sales;
CREATE POLICY "sales_update_policy" ON public.sales
FOR UPDATE TO authenticated
USING (public.get_current_user_role() = 'owner')
WITH CHECK (public.get_current_user_role() = 'owner');

-- ============================================================================
-- 6. CONTROLLED OWNER SCRIPT FOR VOIDING PRODUCTION TEST SALES
-- ============================================================================
-- To void the 3 duplicate production test sales safely without deleting historical logs:
-- 
-- 1. Identify the bill_numbers or IDs of the test sales:
--    SELECT id, bill_number, total_amount, created_at FROM public.sales WHERE location_id = '22222222-2222-2222-2222-222222222222' ORDER BY created_at DESC LIMIT 5;
-- 
-- 2. Execute as OWNER role:
--    UPDATE public.sales SET status = 'VOIDED' WHERE bill_number IN ('<BILL_1>', '<BILL_2>', '<BILL_3>');
-- ============================================================================
