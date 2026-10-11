-- Kizuna Veda V1.3 Two Independent Retail Stores Architecture Migration
-- Canonical Store Stock, Audited Stock Adjustments & Two-Store POS Billing
-- Locations: NEEMRANA ('11111111-1111-1111-1111-111111111111'), JAIPUR ('22222222-2222-2222-2222-222222222222')
-- Roles: OWNER, NEEMRANA, JAIPUR (strictly verified via trusted app_metadata.role)
--
-- IMPORTANT PRINCIPLES:
-- 1. Neemrana and Jaipur are independent stores. Neemrana is NOT a godown or factory.
-- 2. Store inventory is maintained in canonical table `store_inventory` per store and per product.
-- 3. Stock adjustments (initial count and corrections) are logged in `stock_adjustments`.
-- 4. Initial store stock is reconciled from existing balances without double-counting.
-- 5. Atomic POS sales deduct exact quantities (1, 2, 10 units) from selling store only.
-- 6. Voiding a sale restores inventory exactly once with audit logging.
-- 7. Combined stock is dynamically calculated and never manually editable.
-- 8. Existing bills, products, users, sequences, and historical tables are fully preserved.

BEGIN;

-- ============================================================================
-- 1. CANONICAL STORE INVENTORY TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.store_inventory (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    location_id UUID NOT NULL REFERENCES public.locations(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    current_quantity INTEGER NOT NULL DEFAULT 0 CHECK (current_quantity >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT uq_store_inventory_location_product UNIQUE (location_id, product_id),
    CONSTRAINT chk_store_inventory_location CHECK (
        location_id IN (
            '11111111-1111-1111-1111-111111111111'::uuid, -- NEEMRANA
            '22222222-2222-2222-2222-222222222222'::uuid  -- JAIPUR
        )
    )
);

CREATE INDEX IF NOT EXISTS idx_store_inventory_location ON public.store_inventory(location_id);
CREATE INDEX IF NOT EXISTS idx_store_inventory_product ON public.store_inventory(product_id);

-- ============================================================================
-- 2. AUDITABLE STOCK ADJUSTMENTS LEDGER
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.stock_adjustments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    location_id UUID NOT NULL REFERENCES public.locations(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    previous_quantity INTEGER NOT NULL CHECK (previous_quantity >= 0),
    new_quantity INTEGER NOT NULL CHECK (new_quantity >= 0),
    change_quantity INTEGER NOT NULL,
    reason TEXT NOT NULL CHECK (length(trim(reason)) > 0),
    notes TEXT,
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT chk_stock_adjustments_location CHECK (
        location_id IN (
            '11111111-1111-1111-1111-111111111111'::uuid,
            '22222222-2222-2222-2222-222222222222'::uuid
        )
    )
);

CREATE INDEX IF NOT EXISTS idx_stock_adjustments_location ON public.stock_adjustments(location_id);
CREATE INDEX IF NOT EXISTS idx_stock_adjustments_product ON public.stock_adjustments(product_id);
CREATE INDEX IF NOT EXISTS idx_stock_adjustments_created_at ON public.stock_adjustments(created_at DESC);

-- ============================================================================
-- 3. RECONCILIATION INITIALIZATION (AVOID DOUBLE-COUNTING)
-- ============================================================================
-- Initialize store_inventory from current calculated balances once.
-- For Neemrana: packed + stock_in - dispatched - sold
-- For Jaipur: received + stock_in - sold
DO $$
DECLARE
    r_prod RECORD;
    v_neemrana_id CONSTANT UUID := '11111111-1111-1111-1111-111111111111'::uuid;
    v_jaipur_id CONSTANT UUID := '22222222-2222-2222-2222-222222222222'::uuid;
    v_packed INT;
    v_neemrana_stock_in INT;
    v_dispatched INT;
    v_neemrana_sold INT;
    v_neemrana_bal INT;
    v_received INT;
    v_jaipur_stock_in INT;
    v_jaipur_sold INT;
    v_jaipur_bal INT;
BEGIN
    FOR r_prod IN SELECT id FROM public.products WHERE active = true
    LOOP
        -- Calculate Neemrana balance at cut-off
        SELECT COALESCE(SUM(packed_quantity), 0) INTO v_packed
        FROM public.packing_records
        WHERE product_id = r_prod.id AND location_id = v_neemrana_id;

        SELECT COALESCE(SUM(quantity), 0) INTO v_neemrana_stock_in
        FROM public.stock_in_records
        WHERE product_id = r_prod.id AND location_id = v_neemrana_id;

        SELECT COALESCE(SUM(dispatched_quantity), 0) INTO v_dispatched
        FROM public.transfers
        WHERE product_id = r_prod.id AND from_location_id = v_neemrana_id;

        SELECT COALESCE(SUM(si.quantity), 0) INTO v_neemrana_sold
        FROM public.sale_items si
        JOIN public.sales s ON s.id = si.sale_id
        WHERE si.product_id = r_prod.id
          AND s.location_id = v_neemrana_id
          AND s.status = 'COMPLETED';

        v_neemrana_bal := GREATEST(0, (v_packed + v_neemrana_stock_in) - v_dispatched - v_neemrana_sold);

        INSERT INTO public.store_inventory (location_id, product_id, current_quantity)
        VALUES (v_neemrana_id, r_prod.id, v_neemrana_bal)
        ON CONFLICT (location_id, product_id) DO NOTHING;

        -- Calculate Jaipur balance at cut-off
        SELECT COALESCE(SUM(received_quantity), 0) INTO v_received
        FROM public.transfers
        WHERE product_id = r_prod.id AND to_location_id = v_jaipur_id AND received_quantity IS NOT NULL;

        SELECT COALESCE(SUM(quantity), 0) INTO v_jaipur_stock_in
        FROM public.stock_in_records
        WHERE product_id = r_prod.id AND location_id = v_jaipur_id;

        SELECT COALESCE(SUM(si.quantity), 0) INTO v_jaipur_sold
        FROM public.sale_items si
        JOIN public.sales s ON s.id = si.sale_id
        WHERE si.product_id = r_prod.id
          AND s.location_id = v_jaipur_id
          AND s.status = 'COMPLETED';

        v_jaipur_bal := GREATEST(0, (v_received + v_jaipur_stock_in) - v_jaipur_sold);

        INSERT INTO public.store_inventory (location_id, product_id, current_quantity)
        VALUES (v_jaipur_id, r_prod.id, v_jaipur_bal)
        ON CONFLICT (location_id, product_id) DO NOTHING;
    END LOOP;
END;
$$;

-- ============================================================================
-- 4. ROW LEVEL SECURITY ON STORE INVENTORY & STOCK ADJUSTMENTS
-- ============================================================================
ALTER TABLE public.store_inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_adjustments ENABLE ROW LEVEL SECURITY;

-- store_inventory select policy
DROP POLICY IF EXISTS "store_inventory_select_policy" ON public.store_inventory;
CREATE POLICY "store_inventory_select_policy" ON public.store_inventory
FOR SELECT TO authenticated
USING (
    public.get_current_user_role() = 'owner'
    OR (public.get_current_user_role() = 'neemrana' AND location_id = '11111111-1111-1111-1111-111111111111'::uuid)
    OR (public.get_current_user_role() = 'jaipur' AND location_id = '22222222-2222-2222-2222-222222222222'::uuid)
);

-- store_inventory direct mutation disabled to enforce SECURITY DEFINER RPCs
DROP POLICY IF EXISTS "store_inventory_insert_policy" ON public.store_inventory;
CREATE POLICY "store_inventory_insert_policy" ON public.store_inventory
FOR INSERT TO authenticated
WITH CHECK (false);

DROP POLICY IF EXISTS "store_inventory_update_policy" ON public.store_inventory;
CREATE POLICY "store_inventory_update_policy" ON public.store_inventory
FOR UPDATE TO authenticated
USING (false)
WITH CHECK (false);

DROP POLICY IF EXISTS "store_inventory_delete_policy" ON public.store_inventory;
CREATE POLICY "store_inventory_delete_policy" ON public.store_inventory
FOR DELETE TO authenticated
USING (false);

-- stock_adjustments select policy
DROP POLICY IF EXISTS "stock_adjustments_select_policy" ON public.stock_adjustments;
CREATE POLICY "stock_adjustments_select_policy" ON public.stock_adjustments
FOR SELECT TO authenticated
USING (
    public.get_current_user_role() = 'owner'
    OR (public.get_current_user_role() = 'neemrana' AND location_id = '11111111-1111-1111-1111-111111111111'::uuid)
    OR (public.get_current_user_role() = 'jaipur' AND location_id = '22222222-2222-2222-2222-222222222222'::uuid)
);

DROP POLICY IF EXISTS "stock_adjustments_insert_policy" ON public.stock_adjustments;
CREATE POLICY "stock_adjustments_insert_policy" ON public.stock_adjustments
FOR INSERT TO authenticated
WITH CHECK (false);

-- Explicit table-level SELECT grants for authenticated users (RLS strictly enforced)
GRANT SELECT ON public.store_inventory TO authenticated;
GRANT SELECT ON public.stock_adjustments TO authenticated;

-- ============================================================================
-- 5. RPC FUNCTION: MANUAL STORE STOCK ENTRY / ADJUSTMENT
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_adjust_store_stock(
    p_location_id UUID,
    p_product_id UUID,
    p_new_quantity INT,
    p_reason TEXT DEFAULT 'STOCK_ENTRY',
    p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role TEXT;
    v_prev_qty INT := 0;
    v_change_qty INT := 0;
    v_clean_reason TEXT;
    v_inv_id UUID;
    v_adjustment_id UUID;
    c_neemrana_id CONSTANT UUID := '11111111-1111-1111-1111-111111111111'::uuid;
    c_jaipur_id CONSTANT UUID := '22222222-2222-2222-2222-222222222222'::uuid;
BEGIN
    -- 1. Role verification
    v_role := public.get_current_user_role();
    IF v_role NOT IN ('owner', 'neemrana', 'jaipur') THEN
        RAISE EXCEPTION 'Unauthorized: Only OWNER, NEEMRANA, or JAIPUR roles can adjust stock.';
    END IF;

    -- 2. Store location authorization boundary
    IF v_role = 'neemrana' AND p_location_id <> c_neemrana_id THEN
        RAISE EXCEPTION 'Neemrana operators can only adjust stock for Neemrana store.';
    END IF;

    IF v_role = 'jaipur' AND p_location_id <> c_jaipur_id THEN
        RAISE EXCEPTION 'Jaipur operators can only adjust stock for Jaipur store.';
    END IF;

    IF p_location_id NOT IN (c_neemrana_id, c_jaipur_id) THEN
        RAISE EXCEPTION 'Invalid store location: %', p_location_id;
    END IF;

    -- 3. Quantity and parameter validation
    IF p_new_quantity IS NULL OR p_new_quantity < 0 THEN
        RAISE EXCEPTION 'Stock quantity cannot be negative (provided: %).', p_new_quantity;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.products WHERE id = p_product_id AND active = true) THEN
        RAISE EXCEPTION 'Product with ID % does not exist or is inactive.', p_product_id;
    END IF;

    v_clean_reason := COALESCE(trim(p_reason), 'STOCK_ENTRY');
    IF length(v_clean_reason) = 0 THEN
        v_clean_reason := 'STOCK_ENTRY';
    END IF;

    -- 4. Atomically acquire lock and update store_inventory
    SELECT current_quantity, id INTO v_prev_qty, v_inv_id
    FROM public.store_inventory
    WHERE location_id = p_location_id AND product_id = p_product_id
    FOR UPDATE;

    IF NOT FOUND THEN
        v_prev_qty := 0;
        INSERT INTO public.store_inventory (location_id, product_id, current_quantity)
        VALUES (p_location_id, p_product_id, p_new_quantity)
        RETURNING id INTO v_inv_id;
    ELSE
        UPDATE public.store_inventory
        SET current_quantity = p_new_quantity,
            updated_at = now()
        WHERE id = v_inv_id;
    END IF;

    v_change_qty := p_new_quantity - v_prev_qty;

    -- 5. Record auditable stock adjustment ledger entry
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
    ) VALUES (
        p_location_id,
        p_product_id,
        v_prev_qty,
        p_new_quantity,
        v_change_qty,
        v_clean_reason,
        trim(p_notes),
        auth.uid(),
        now()
    )
    RETURNING id INTO v_adjustment_id;

    RETURN jsonb_build_object(
        'success', true,
        'location_id', p_location_id,
        'product_id', p_product_id,
        'previous_quantity', v_prev_qty,
        'new_quantity', p_new_quantity,
        'change_quantity', v_change_qty,
        'reason', v_clean_reason,
        'notes', trim(p_notes),
        'adjustment_id', v_adjustment_id,
        'updated_at', now()
    );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_adjust_store_stock(UUID, UUID, INT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_adjust_store_stock(UUID, UUID, INT, TEXT, TEXT) TO authenticated;

-- ============================================================================
-- 6. POS SALE STOCK DEDUCTION RPC (EXACT ATOMIC DEDUCTION)
-- ============================================================================
-- Drop legacy stock validation triggers on sale_items so that they do not conflict
-- with the canonical store_inventory validation performed inside fn_create_pos_sale.
-- (fn_check_sale_stock function is preserved for historical reference).
DROP TRIGGER IF EXISTS trg_check_sale_stock ON public.sale_items;
DROP TRIGGER IF EXISTS trg_check_jaipur_sale_stock ON public.sale_items;

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
    v_available_stock INT;
    c_neemrana_id CONSTANT UUID := '11111111-1111-1111-1111-111111111111'::uuid;
    c_jaipur_id CONSTANT UUID := '22222222-2222-2222-2222-222222222222'::uuid;
BEGIN
    -- 1. Server-side role & location verification
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

    -- 4. Line items payload validation & calculate subtotal
    IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'POS sale must contain at least one line item.';
    END IF;

    -- 5. Atomically validate and deduct stock from store_inventory
    -- Process items in deterministic order to prevent deadlocks
    FOR v_item IN
        SELECT elem
        FROM jsonb_array_elements(p_items) elem
        ORDER BY (elem ->> 'product_id')::uuid
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

        -- Acquire exclusive row lock on store_inventory for target location
        SELECT current_quantity INTO v_available_stock
        FROM public.store_inventory
        WHERE location_id = v_target_location_id AND product_id = v_product_id
        FOR UPDATE;

        IF v_available_stock IS NULL OR v_available_stock < v_quantity THEN
            RAISE EXCEPTION 'Insufficient stock for product ID % at % store. Available: %, Requested: %',
                v_product_id,
                CASE WHEN v_target_location_id = c_neemrana_id THEN 'Neemrana' ELSE 'Jaipur' END,
                COALESCE(v_available_stock, 0),
                v_quantity;
        END IF;

        -- Exact stock deduction: 1 packet -> -1, 2 packets -> -2, 10 packets -> -10
        UPDATE public.store_inventory
        SET current_quantity = current_quantity - v_quantity,
            updated_at = now()
        WHERE location_id = v_target_location_id AND product_id = v_product_id;

        v_item_total := round(v_quantity * v_unit_price, 2);
        v_calculated_subtotal := v_calculated_subtotal + v_item_total;
    END LOOP;

    -- 6. Calculate NON_GST invoice amounts
    v_gst_rate := 0.00;
    v_taxable_amount := v_calculated_subtotal;
    v_cgst_amount := 0.00;
    v_sgst_amount := 0.00;
    v_igst_amount := 0.00;
    v_grand_total := v_calculated_subtotal;

    -- 7. Generate unique bill number
    v_bill_number := 'BILL-' || lpad(nextval('public.seq_bill_number')::text, 6, '0');

    -- 8. Insert parent sale record
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

    -- 9. Insert line items
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

    -- 10. Build and return created sale JSON
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

REVOKE ALL ON FUNCTION public.fn_create_pos_sale(TEXT, TEXT, TEXT, JSONB, UUID, TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_create_pos_sale(TEXT, TEXT, TEXT, JSONB, UUID, TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC) TO authenticated;

-- ============================================================================
-- 7. VOID SALE TRIGGER: RESTORE STOCK EXACTLY ONCE WITH AUDITING
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_restore_voided_sale_stock()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_item RECORD;
    v_prev_qty INT;
    v_new_qty INT;
BEGIN
    -- Only restore when transitioning from COMPLETED to VOIDED
    IF OLD.status = 'COMPLETED' AND NEW.status = 'VOIDED' THEN
        FOR v_item IN
            SELECT product_id, quantity
            FROM public.sale_items
            WHERE sale_id = NEW.id
            ORDER BY product_id
        LOOP
            -- Acquire row lock and restore store stock
            SELECT current_quantity INTO v_prev_qty
            FROM public.store_inventory
            WHERE location_id = NEW.location_id AND product_id = v_item.product_id
            FOR UPDATE;

            IF v_prev_qty IS NULL THEN
                v_prev_qty := 0;
                v_new_qty := v_item.quantity;
                INSERT INTO public.store_inventory (location_id, product_id, current_quantity)
                VALUES (NEW.location_id, v_item.product_id, v_new_qty);
            ELSE
                v_new_qty := v_prev_qty + v_item.quantity;
                UPDATE public.store_inventory
                SET current_quantity = v_new_qty,
                    updated_at = now()
                WHERE location_id = NEW.location_id AND product_id = v_item.product_id;
            END IF;

            -- Audit the stock restoration in ledger
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
            ) VALUES (
                NEW.location_id,
                v_item.product_id,
                v_prev_qty,
                v_new_qty,
                v_item.quantity,
                'BILL_VOID',
                'Stock restored from voided bill ' || NEW.bill_number,
                auth.uid(),
                now()
            );
        END LOOP;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_restore_voided_sale_stock ON public.sales;
CREATE TRIGGER trg_restore_voided_sale_stock
AFTER UPDATE OF status ON public.sales
FOR EACH ROW
EXECUTE FUNCTION public.fn_restore_voided_sale_stock();

-- ============================================================================
-- 8. DYNAMIC COMBINED STORE INVENTORY VIEW
-- ============================================================================
-- Combined total stock = Neemrana available stock + Jaipur available stock
-- Strictly read-only; dynamically calculated.
CREATE OR REPLACE VIEW public.v_store_inventory_summary AS
SELECT
    p.id AS product_id,
    p.name AS product_name,
    p.sku,
    p.package_size,
    COALESCE(neem.current_quantity, 0) AS neemrana_stock,
    COALESCE(jaip.current_quantity, 0) AS jaipur_stock,
    (COALESCE(neem.current_quantity, 0) + COALESCE(jaip.current_quantity, 0)) AS combined_stock
FROM public.products p
LEFT JOIN public.store_inventory neem
    ON neem.product_id = p.id AND neem.location_id = '11111111-1111-1111-1111-111111111111'::uuid
LEFT JOIN public.store_inventory jaip
    ON jaip.product_id = p.id AND jaip.location_id = '22222222-2222-2222-2222-222222222222'::uuid
WHERE p.active = true;

GRANT SELECT ON public.v_store_inventory_summary TO authenticated;

COMMIT;
