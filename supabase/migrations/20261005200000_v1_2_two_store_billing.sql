-- Kizuna Veda V1.2 Two-Store Inventory, Billing & GST Migration
-- Locations: NEEMRANA ('11111111-1111-1111-1111-111111111111'), JAIPUR ('22222222-2222-2222-2222-222222222222')
-- Roles: OWNER, NEEMRANA, JAIPUR (strictly verified via trusted app_metadata.role)
-- 
-- IMPORTANT:
-- 1. Additive & safe migration. Does NOT delete historical business data or completed bills.
-- 2. Backfills historical sales as NON_GST without altering past totals or bill numbers.
-- 3. Enforces strict location boundaries for sales, sale_items, and stock triggers.

-- ============================================================================
-- 1. AUTHORIZATION UTILITY & CLEANUP LEGACY OVERLOADED RPC SIGNATURES
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.get_current_user_role()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(
        auth.jwt() -> 'app_metadata' ->> 'role',
        'authenticated'
    );
$$;

GRANT EXECUTE ON FUNCTION public.get_current_user_role() TO authenticated;

-- Drop all possible past overloaded RPC signatures to prevent PostgREST resolution ambiguity
DROP FUNCTION IF EXISTS public.fn_create_pos_sale(TEXT, JSONB);
DROP FUNCTION IF EXISTS public.fn_create_pos_sale(TEXT, JSONB, TEXT);
DROP FUNCTION IF EXISTS public.fn_create_pos_sale(TEXT, TEXT, TEXT, JSONB);
DROP FUNCTION IF EXISTS public.fn_create_pos_sale(TEXT, TEXT, TEXT, TEXT, JSONB);

-- ============================================================================
-- 2. UPDATE LOCATION CHECK & ADD GST COLUMNS TO SALES TABLE
-- ============================================================================
ALTER TABLE public.sales DROP CONSTRAINT IF EXISTS chk_sale_location;

ALTER TABLE public.sales
ADD CONSTRAINT chk_sale_location CHECK (
    location_id IN (
        '11111111-1111-1111-1111-111111111111'::uuid, -- NEEMRANA
        '22222222-2222-2222-2222-222222222222'::uuid  -- JAIPUR
    )
);

ALTER TABLE public.sales
ADD COLUMN IF NOT EXISTS invoice_type TEXT NULL,
ADD COLUMN IF NOT EXISTS gst_rate NUMERIC(5, 2) NULL,
ADD COLUMN IF NOT EXISTS taxable_amount NUMERIC(12, 2) NULL,
ADD COLUMN IF NOT EXISTS cgst_amount NUMERIC(12, 2) NULL,
ADD COLUMN IF NOT EXISTS sgst_amount NUMERIC(12, 2) NULL,
ADD COLUMN IF NOT EXISTS igst_amount NUMERIC(12, 2) NULL;

-- Backfill existing historical records safely (targets only unpopulated historical rows)
UPDATE public.sales
SET invoice_type = 'NON_GST',
    gst_rate = 0.00,
    taxable_amount = total_amount,
    cgst_amount = 0.00,
    sgst_amount = 0.00,
    igst_amount = 0.00
WHERE invoice_type IS NULL;

-- Enforce default values & NOT NULL constraints after backfill
ALTER TABLE public.sales
ALTER COLUMN invoice_type SET DEFAULT 'NON_GST',
ALTER COLUMN invoice_type SET NOT NULL,
ALTER COLUMN gst_rate SET DEFAULT 0.00,
ALTER COLUMN gst_rate SET NOT NULL,
ALTER COLUMN taxable_amount SET DEFAULT 0.00,
ALTER COLUMN taxable_amount SET NOT NULL,
ALTER COLUMN cgst_amount SET DEFAULT 0.00,
ALTER COLUMN cgst_amount SET NOT NULL,
ALTER COLUMN sgst_amount SET DEFAULT 0.00,
ALTER COLUMN sgst_amount SET NOT NULL,
ALTER COLUMN igst_amount SET DEFAULT 0.00,
ALTER COLUMN igst_amount SET NOT NULL;

ALTER TABLE public.sales DROP CONSTRAINT IF EXISTS chk_invoice_type;
ALTER TABLE public.sales
ADD CONSTRAINT chk_invoice_type CHECK (invoice_type IN ('NON_GST', 'GST'));

ALTER TABLE public.sales DROP CONSTRAINT IF EXISTS chk_gst_amounts;
ALTER TABLE public.sales
ADD CONSTRAINT chk_gst_amounts CHECK (
    gst_rate >= 0 AND gst_rate <= 100 AND
    taxable_amount >= 0 AND
    cgst_amount >= 0 AND
    sgst_amount >= 0 AND
    igst_amount >= 0
);

-- ============================================================================
-- 3. STRICT LOCATION-AWARE RLS POLICIES FOR SALES & SALE_ITEMS
-- ============================================================================
DROP POLICY IF EXISTS "sales_select_policy" ON public.sales;
CREATE POLICY "sales_select_policy" ON public.sales
FOR SELECT TO authenticated
USING (
    public.get_current_user_role() = 'owner'
    OR (public.get_current_user_role() = 'neemrana' AND location_id = '11111111-1111-1111-1111-111111111111'::uuid)
    OR (public.get_current_user_role() = 'jaipur' AND location_id = '22222222-2222-2222-2222-222222222222'::uuid)
);

-- Direct client INSERTs on sales table are blocked to enforce creation via fn_create_pos_sale RPC
DROP POLICY IF EXISTS "sales_insert_policy" ON public.sales;
CREATE POLICY "sales_insert_policy" ON public.sales
FOR INSERT TO authenticated
WITH CHECK (false);

-- Only OWNER can void a sale; NEEMRANA and JAIPUR roles cannot update sales
DROP POLICY IF EXISTS "sales_update_policy" ON public.sales;
CREATE POLICY "sales_update_policy" ON public.sales
FOR UPDATE TO authenticated
USING (
    public.get_current_user_role() = 'owner'
);

DROP POLICY IF EXISTS "sale_items_select_policy" ON public.sale_items;
CREATE POLICY "sale_items_select_policy" ON public.sale_items
FOR SELECT TO authenticated
USING (
    public.get_current_user_role() = 'owner'
    OR EXISTS (
        SELECT 1 FROM public.sales s
        WHERE s.id = sale_items.sale_id
        AND (
            (public.get_current_user_role() = 'neemrana' AND s.location_id = '11111111-1111-1111-1111-111111111111'::uuid)
            OR (public.get_current_user_role() = 'jaipur' AND s.location_id = '22222222-2222-2222-2222-222222222222'::uuid)
        )
    )
);

-- Direct client INSERTs on sale_items table are blocked to enforce creation via fn_create_pos_sale RPC
DROP POLICY IF EXISTS "sale_items_insert_policy" ON public.sale_items;
CREATE POLICY "sale_items_insert_policy" ON public.sale_items
FOR INSERT TO authenticated
WITH CHECK (false);

-- ============================================================================
-- 4. SALES IMMUTABILITY & VOID RESTRICTION TRIGGERS
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_restrict_sale_status_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Core fields of a created sale are strictly immutable
    IF NEW.id <> OLD.id OR
       NEW.location_id <> OLD.location_id OR
       NEW.bill_number <> OLD.bill_number OR
       NEW.customer_name IS DISTINCT FROM OLD.customer_name OR
       NEW.customer_phone IS DISTINCT FROM OLD.customer_phone OR
       NEW.payment_method IS DISTINCT FROM OLD.payment_method OR
       NEW.invoice_type IS DISTINCT FROM OLD.invoice_type OR
       NEW.gst_rate IS DISTINCT FROM OLD.gst_rate OR
       NEW.taxable_amount IS DISTINCT FROM OLD.taxable_amount OR
       NEW.cgst_amount IS DISTINCT FROM OLD.cgst_amount OR
       NEW.sgst_amount IS DISTINCT FROM OLD.sgst_amount OR
       NEW.igst_amount IS DISTINCT FROM OLD.igst_amount OR
       NEW.total_amount <> OLD.total_amount OR
       NEW.sold_at <> OLD.sold_at OR
       NEW.created_at <> OLD.created_at THEN
        RAISE EXCEPTION 'Core sale fields (bill_number, total_amount, customer_name, GST breakdown, etc.) are strictly immutable once created.';
    END IF;

    -- A VOIDED sale is strictly immutable and cannot be edited or un-voided
    IF OLD.status = 'VOIDED' THEN
        RAISE EXCEPTION 'A VOIDED sale is strictly immutable and cannot be modified or reverted.';
    END IF;

    -- Only OWNER role can transition a sale from COMPLETED to VOIDED
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
-- 5. CONCURRENCY-SAFE STOCK PROTECTION TRIGGERS (NEEMRANA & JAIPUR)
-- ============================================================================

-- ============================================================================
-- 5. CONCURRENCY-SAFE STOCK PROTECTION TRIGGERS & STOCK-IN LEDGER
-- ============================================================================

-- Stock-In movements ledger table
CREATE TABLE IF NOT EXISTS public.stock_in_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    location_id UUID NOT NULL REFERENCES public.locations(id),
    product_id UUID NOT NULL REFERENCES public.products(id),
    quantity INT NOT NULL CHECK (quantity > 0),
    notes TEXT NULL,
    created_by UUID DEFAULT auth.uid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.stock_in_records ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "stock_in_select_policy" ON public.stock_in_records;
CREATE POLICY "stock_in_select_policy" ON public.stock_in_records
FOR SELECT TO authenticated
USING (
    public.get_current_user_role() = 'owner'
    OR (public.get_current_user_role() = 'neemrana' AND location_id = '11111111-1111-1111-1111-111111111111'::uuid)
    OR (public.get_current_user_role() = 'jaipur' AND location_id = '22222222-2222-2222-2222-222222222222'::uuid)
);

DROP POLICY IF EXISTS "stock_in_insert_policy" ON public.stock_in_records;
CREATE POLICY "stock_in_insert_policy" ON public.stock_in_records
FOR INSERT TO authenticated
WITH CHECK (
    public.get_current_user_role() = 'owner'
    OR (public.get_current_user_role() = 'neemrana' AND location_id = '11111111-1111-1111-1111-111111111111'::uuid)
    OR (public.get_current_user_role() = 'jaipur' AND location_id = '22222222-2222-2222-2222-222222222222'::uuid)
);

-- Update Neemrana dispatch stock trigger with sorted deadlock-free row locking and stock-in ledger integration
CREATE OR REPLACE FUNCTION public.fn_check_neemrana_dispatch_stock()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_packed INT := 0;
    v_total_neemrana_stock_in INT := 0;
    v_total_dispatched INT := 0;
    v_total_neemrana_sold INT := 0;
    v_available_stock INT := 0;
BEGIN
    -- Lock product rows in deterministic UUID order to prevent deadlocks when product_id changes
    IF TG_OP = 'UPDATE' AND OLD.product_id <> NEW.product_id THEN
        IF OLD.product_id < NEW.product_id THEN
            PERFORM 1 FROM public.products WHERE id = OLD.product_id FOR UPDATE;
            PERFORM 1 FROM public.products WHERE id = NEW.product_id FOR UPDATE;
        ELSE
            PERFORM 1 FROM public.products WHERE id = NEW.product_id FOR UPDATE;
            PERFORM 1 FROM public.products WHERE id = OLD.product_id FOR UPDATE;
        END IF;
    ELSE
        PERFORM 1 FROM public.products WHERE id = NEW.product_id FOR UPDATE;
    END IF;

    SELECT COALESCE(SUM(packed_quantity), 0)
    INTO v_total_packed
    FROM public.packing_records
    WHERE product_id = NEW.product_id
      AND location_id = '11111111-1111-1111-1111-111111111111'::uuid;

    SELECT COALESCE(SUM(quantity), 0)
    INTO v_total_neemrana_stock_in
    FROM public.stock_in_records
    WHERE product_id = NEW.product_id
      AND location_id = '11111111-1111-1111-1111-111111111111'::uuid;

    SELECT COALESCE(SUM(dispatched_quantity), 0)
    INTO v_total_dispatched
    FROM public.transfers
    WHERE product_id = NEW.product_id
      AND from_location_id = '11111111-1111-1111-1111-111111111111'::uuid
      AND id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid);

    SELECT COALESCE(SUM(si.quantity), 0)
    INTO v_total_neemrana_sold
    FROM public.sale_items si
    JOIN public.sales s ON s.id = si.sale_id
    WHERE si.product_id = NEW.product_id
      AND s.location_id = '11111111-1111-1111-1111-111111111111'::uuid
      AND s.status = 'COMPLETED';

    v_available_stock := (v_total_packed + v_total_neemrana_stock_in) - v_total_dispatched - v_total_neemrana_sold;

    IF NEW.dispatched_quantity > v_available_stock THEN
        RAISE EXCEPTION 'Neemrana dispatch quantity (%) exceeds available finished stock (%). Product ID: %',
            NEW.dispatched_quantity, v_available_stock, NEW.product_id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_neemrana_dispatch_stock ON public.transfers;
CREATE TRIGGER trg_check_neemrana_dispatch_stock
BEFORE INSERT OR UPDATE OF product_id, dispatched_quantity
ON public.transfers
FOR EACH ROW
EXECUTE FUNCTION public.fn_check_neemrana_dispatch_stock();

-- Unified sale stock validation trigger with sorted deadlock-free row locking
CREATE OR REPLACE FUNCTION public.fn_check_sale_stock()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_sale_location_id UUID;
    v_sale_status TEXT;
    v_total_packed INT := 0;
    v_total_neemrana_stock_in INT := 0;
    v_total_dispatched INT := 0;
    v_total_neemrana_sold INT := 0;
    v_total_received INT := 0;
    v_total_jaipur_stock_in INT := 0;
    v_total_jaipur_sold INT := 0;
    v_available_stock INT := 0;
BEGIN
    SELECT location_id, status INTO v_sale_location_id, v_sale_status
    FROM public.sales WHERE id = NEW.sale_id;

    -- VOIDED sales do not deduct stock
    IF v_sale_status = 'VOIDED' THEN
        RETURN NEW;
    END IF;

    -- Lock product rows in deterministic UUID order to prevent deadlocks when product_id changes
    IF TG_OP = 'UPDATE' AND OLD.product_id <> NEW.product_id THEN
        IF OLD.product_id < NEW.product_id THEN
            PERFORM 1 FROM public.products WHERE id = OLD.product_id FOR UPDATE;
            PERFORM 1 FROM public.products WHERE id = NEW.product_id FOR UPDATE;
        ELSE
            PERFORM 1 FROM public.products WHERE id = NEW.product_id FOR UPDATE;
            PERFORM 1 FROM public.products WHERE id = OLD.product_id FOR UPDATE;
        END IF;
    ELSE
        PERFORM 1 FROM public.products WHERE id = NEW.product_id FOR UPDATE;
    END IF;

    IF v_sale_location_id = '11111111-1111-1111-1111-111111111111'::uuid THEN
        -- Neemrana Sale Stock Check
        SELECT COALESCE(SUM(packed_quantity), 0)
        INTO v_total_packed
        FROM public.packing_records
        WHERE product_id = NEW.product_id
          AND location_id = '11111111-1111-1111-1111-111111111111'::uuid;

        SELECT COALESCE(SUM(quantity), 0)
        INTO v_total_neemrana_stock_in
        FROM public.stock_in_records
        WHERE product_id = NEW.product_id
          AND location_id = '11111111-1111-1111-1111-111111111111'::uuid;

        SELECT COALESCE(SUM(dispatched_quantity), 0)
        INTO v_total_dispatched
        FROM public.transfers
        WHERE product_id = NEW.product_id
          AND from_location_id = '11111111-1111-1111-1111-111111111111'::uuid;

        SELECT COALESCE(SUM(si.quantity), 0)
        INTO v_total_neemrana_sold
        FROM public.sale_items si
        JOIN public.sales s ON s.id = si.sale_id
        WHERE si.product_id = NEW.product_id
          AND s.location_id = '11111111-1111-1111-1111-111111111111'::uuid
          AND s.status = 'COMPLETED'
          AND si.id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid);

        v_available_stock := (v_total_packed + v_total_neemrana_stock_in) - v_total_dispatched - v_total_neemrana_sold;

        IF NEW.quantity > v_available_stock THEN
            RAISE EXCEPTION 'Neemrana sale quantity (%) exceeds available finished stock (%). Product ID: %',
                NEW.quantity, v_available_stock, NEW.product_id;
        END IF;

    ELSIF v_sale_location_id = '22222222-2222-2222-2222-222222222222'::uuid THEN
        -- Jaipur Sale Stock Check
        SELECT COALESCE(SUM(received_quantity), 0)
        INTO v_total_received
        FROM public.transfers
        WHERE product_id = NEW.product_id
          AND to_location_id = '22222222-2222-2222-2222-222222222222'::uuid
          AND received_quantity IS NOT NULL;

        SELECT COALESCE(SUM(quantity), 0)
        INTO v_total_jaipur_stock_in
        FROM public.stock_in_records
        WHERE product_id = NEW.product_id
          AND location_id = '22222222-2222-2222-2222-222222222222'::uuid;

        SELECT COALESCE(SUM(si.quantity), 0)
        INTO v_total_jaipur_sold
        FROM public.sale_items si
        JOIN public.sales s ON s.id = si.sale_id
        WHERE si.product_id = NEW.product_id
          AND s.location_id = '22222222-2222-2222-2222-222222222222'::uuid
          AND s.status = 'COMPLETED'
          AND si.id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid);

        v_available_stock := (v_total_received + v_total_jaipur_stock_in) - v_total_jaipur_sold;

        IF NEW.quantity > v_available_stock THEN
            RAISE EXCEPTION 'Jaipur sale quantity (%) exceeds available finished stock (%). Product ID: %',
                NEW.quantity, v_available_stock, NEW.product_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_jaipur_sale_stock ON public.sale_items;
DROP TRIGGER IF EXISTS trg_check_sale_stock ON public.sale_items;
CREATE TRIGGER trg_check_sale_stock
BEFORE INSERT OR UPDATE OF product_id, quantity
ON public.sale_items
FOR EACH ROW
EXECUTE FUNCTION public.fn_check_sale_stock();

-- ============================================================================
-- 6. ATOMIC V1.2 POS SALE RPC FUNCTION (TWO-STORE & GST SUPPORT)
-- ============================================================================
DROP FUNCTION IF EXISTS public.fn_create_pos_sale(TEXT, JSONB);
DROP FUNCTION IF EXISTS public.fn_create_pos_sale(TEXT, JSONB, TEXT);
DROP FUNCTION IF EXISTS public.fn_create_pos_sale(TEXT, TEXT, TEXT, JSONB);
DROP FUNCTION IF EXISTS public.fn_create_pos_sale(TEXT, TEXT, TEXT, TEXT, JSONB);
DROP FUNCTION IF EXISTS public.fn_create_pos_sale(TEXT, TEXT, TEXT, JSONB, UUID, TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC);

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
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role TEXT;
    v_target_location_id UUID;
    v_sale_id UUID;
    v_bill_number TEXT;
    v_calculated_subtotal NUMERIC(12, 2) := 0;
    v_item JSONB;
    v_product_id UUID;
    v_quantity INT;
    v_unit_price NUMERIC(12, 2);
    v_item_total NUMERIC(12, 2);
    v_clean_name TEXT;
    v_clean_phone TEXT;
    v_clean_method TEXT;
    v_clean_type TEXT;
    v_gst_rate NUMERIC(5, 2);
    v_taxable_amount NUMERIC(12, 2);
    v_cgst_amount NUMERIC(12, 2);
    v_sgst_amount NUMERIC(12, 2);
    v_igst_amount NUMERIC(12, 2);
    v_grand_total NUMERIC(12, 2);
    v_created_sale JSONB;
    c_neemrana_id CONSTANT UUID := '11111111-1111-1111-1111-111111111111'::uuid;
    c_jaipur_id CONSTANT UUID := '22222222-2222-2222-2222-222222222222'::uuid;
BEGIN
    -- 1. Server-side role & location verification via trusted app_metadata.role
    v_role := public.get_current_user_role();
    IF v_role NOT IN ('owner', 'neemrana', 'jaipur') THEN
        RAISE EXCEPTION 'Unauthorized: Only OWNER, NEEMRANA, or JAIPUR roles can create POS sales.';
    END IF;

    IF v_role = 'neemrana' THEN
        v_target_location_id := c_neemrana_id;
    ELSIF v_role = 'jaipur' THEN
        v_target_location_id := c_jaipur_id;
    ELSE
        -- Owner role defaults to Jaipur if location_id not specified
        v_target_location_id := COALESCE(p_location_id, c_jaipur_id);
    END IF;

    IF v_target_location_id NOT IN (c_neemrana_id, c_jaipur_id) THEN
        RAISE EXCEPTION 'Invalid target location ID for sale creation: %', v_target_location_id;
    END IF;

    -- 2. Customer & Payment method validation
    IF p_customer_name IS NULL OR length(trim(p_customer_name)) = 0 THEN
        RAISE EXCEPTION 'Customer name is required for POS sales.';
    END IF;
    v_clean_name := trim(p_customer_name);

    IF p_customer_phone IS NULL OR length(trim(p_customer_phone)) = 0 THEN
        RAISE EXCEPTION 'Customer phone is required for POS sales.';
    END IF;
    v_clean_phone := trim(p_customer_phone);

    IF p_payment_method IS NULL OR length(trim(p_payment_method)) = 0 THEN
        RAISE EXCEPTION 'Payment method is required for POS sales.';
    END IF;
    v_clean_method := upper(trim(p_payment_method));
    IF v_clean_method NOT IN ('CASH', 'UPI') THEN
        RAISE EXCEPTION 'Invalid payment method "%". Allowed values: CASH, UPI.', p_payment_method;
    END IF;

    -- 3. Invoice Mode & GST Server-Side Security Enforcement
    v_clean_type := upper(trim(COALESCE(p_invoice_type, 'NON_GST')));
    IF v_clean_type NOT IN ('NON_GST', 'GST') THEN
        RAISE EXCEPTION 'Invalid invoice type "%". Allowed values: NON_GST, GST.', p_invoice_type;
    END IF;

    IF v_clean_type = 'GST' THEN
        RAISE EXCEPTION 'GST billing is currently disabled until verified business GST configuration is enabled server-side.';
    END IF;

    -- 4. Line items payload validation & calculate subtotal server-side
    IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'POS sale must contain at least one line item.';
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_product_id := (v_item ->> 'product_id')::uuid;
        v_quantity := (v_item ->> 'quantity')::int;
        v_unit_price := COALESCE((v_item ->> 'unit_price')::numeric, 0);

        IF v_product_id IS NULL THEN
            RAISE EXCEPTION 'Invalid line item: product_id is required.';
        END IF;

        IF v_quantity IS NULL OR v_quantity <= 0 THEN
            RAISE EXCEPTION 'Invalid line item quantity (must be > 0). Product ID: %', v_product_id;
        END IF;

        IF v_unit_price < 0 THEN
            RAISE EXCEPTION 'Invalid line item unit price (must be >= 0). Product ID: %', v_product_id;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM public.products WHERE id = v_product_id AND active = true) THEN
            RAISE EXCEPTION 'Product with ID % does not exist or is inactive.', v_product_id;
        END IF;

        v_item_total := round(v_quantity * v_unit_price, 2);
        v_calculated_subtotal := v_calculated_subtotal + v_item_total;
    END LOOP;

    -- 5. Calculate NON_GST invoice amounts server-side to guarantee mathematical integrity
    v_gst_rate := 0.00;
    v_taxable_amount := v_calculated_subtotal;
    v_cgst_amount := 0.00;
    v_sgst_amount := 0.00;
    v_igst_amount := 0.00;
    v_grand_total := v_calculated_subtotal;

    -- 6. Generate unique bill number server-side
    v_bill_number := 'BILL-' || lpad(nextval('public.seq_bill_number')::text, 6, '0');

    -- 7. Insert parent sale header
    INSERT INTO public.sales (
        location_id,
        bill_number,
        customer_name,
        customer_phone,
        payment_method,
        invoice_type,
        gst_rate,
        taxable_amount,
        cgst_amount,
        sgst_amount,
        igst_amount,
        whatsapp_status,
        total_amount,
        status,
        sold_at
    ) VALUES (
        v_target_location_id,
        v_bill_number,
        v_clean_name,
        v_clean_phone,
        v_clean_method,
        v_clean_type,
        v_gst_rate,
        v_taxable_amount,
        v_cgst_amount,
        v_sgst_amount,
        v_igst_amount,
        'NOT_SENT',
        v_grand_total,
        'COMPLETED',
        now()
    )
    RETURNING id INTO v_sale_id;

    -- 8. Insert line items (triggers fn_check_sale_stock for store stock validation)
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_product_id := (v_item ->> 'product_id')::uuid;
        v_quantity := (v_item ->> 'quantity')::int;
        v_unit_price := COALESCE((v_item ->> 'unit_price')::numeric, 0);

        INSERT INTO public.sale_items (
            sale_id,
            product_id,
            quantity,
            unit_price
        ) VALUES (
            v_sale_id,
            v_product_id,
            v_quantity,
            v_unit_price
        );
    END LOOP;

    -- 9. Build and return created sale JSON
    SELECT jsonb_build_object(
        'id', s.id,
        'location_id', s.location_id,
        'bill_number', s.bill_number,
        'customer_name', s.customer_name,
        'customer_phone', s.customer_phone,
        'payment_method', s.payment_method,
        'invoice_type', s.invoice_type,
        'gst_rate', s.gst_rate,
        'taxable_amount', s.taxable_amount,
        'cgst_amount', s.cgst_amount,
        'sgst_amount', s.sgst_amount,
        'igst_amount', s.igst_amount,
        'whatsapp_status', s.whatsapp_status,
        'total_amount', s.total_amount,
        'status', s.status,
        'sold_at', s.sold_at,
        'created_at', s.created_at,
        'product_id', (SELECT si.product_id FROM public.sale_items si WHERE si.sale_id = s.id LIMIT 1),
        'quantity', (SELECT COALESCE(SUM(si.quantity), 0) FROM public.sale_items si WHERE si.sale_id = s.id),
        'sale_items', (
            SELECT jsonb_agg(jsonb_build_object(
                'id', si.id,
                'sale_id', si.sale_id,
                'product_id', si.product_id,
                'quantity', si.quantity,
                'unit_price', si.unit_price,
                'created_at', si.created_at
            ))
            FROM public.sale_items si
            WHERE si.sale_id = s.id
        )
    ) INTO v_created_sale
    FROM public.sales s
    WHERE s.id = v_sale_id;

    RETURN v_created_sale;
END;
$$;

-- Revoke default PUBLIC execution and grant explicitly to authenticated users
REVOKE ALL ON FUNCTION public.fn_create_pos_sale(TEXT, TEXT, TEXT, JSONB, UUID, TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_create_pos_sale(TEXT, TEXT, TEXT, JSONB, UUID, TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC) TO authenticated;

-- ============================================================================
-- 7. RECEIPT CONFIRMATION RPC FUNCTION (JAIPUR STORE)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_confirm_jaipur_receipt(
    p_transfer_id UUID,
    p_received_quantity INT,
    p_discrepancy_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role TEXT;
    v_transfer RECORD;
    v_updated_transfer JSONB;
BEGIN
    v_role := public.get_current_user_role();
    IF v_role NOT IN ('owner', 'jaipur') THEN
        RAISE EXCEPTION 'Unauthorized: Only OWNER or JAIPUR roles can confirm shipment receipts.';
    END IF;

    SELECT * INTO v_transfer
    FROM public.transfers
    WHERE id = p_transfer_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Transfer record not found: %', p_transfer_id;
    END IF;

    IF v_transfer.received_at IS NOT NULL THEN
        RAISE EXCEPTION 'Transfer receipt has already been confirmed on %.', v_transfer.received_at;
    END IF;

    IF p_received_quantity < 0 THEN
        RAISE EXCEPTION 'Received quantity cannot be negative.';
    END IF;

    IF p_received_quantity > v_transfer.dispatched_quantity THEN
        RAISE EXCEPTION 'Received quantity (%) cannot exceed dispatched quantity (%).',
            p_received_quantity, v_transfer.dispatched_quantity;
    END IF;

    IF p_received_quantity <> v_transfer.dispatched_quantity AND (p_discrepancy_reason IS NULL OR length(trim(p_discrepancy_reason)) = 0) THEN
        RAISE EXCEPTION 'A valid discrepancy reason is required when received quantity (%) differs from dispatched quantity (%).',
            p_received_quantity, v_transfer.dispatched_quantity;
    END IF;

    UPDATE public.transfers
    SET received_quantity = p_received_quantity,
        discrepancy_reason = CASE
            WHEN p_received_quantity <> v_transfer.dispatched_quantity THEN trim(p_discrepancy_reason)
            ELSE NULL
        END,
        received_at = now()
    WHERE id = p_transfer_id;

    SELECT jsonb_build_object(
        'id', t.id,
        'product_id', t.product_id,
        'from_location_id', t.from_location_id,
        'to_location_id', t.to_location_id,
        'dispatched_quantity', t.dispatched_quantity,
        'received_quantity', t.received_quantity,
        'discrepancy_reason', t.discrepancy_reason,
        'dispatched_at', t.dispatched_at,
        'received_at', t.received_at,
        'created_at', t.created_at
    ) INTO v_updated_transfer
    FROM public.transfers t
    WHERE t.id = p_transfer_id;

    RETURN v_updated_transfer;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_confirm_jaipur_receipt(UUID, INT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_confirm_jaipur_receipt(UUID, INT, TEXT) TO authenticated;

COMMIT;
