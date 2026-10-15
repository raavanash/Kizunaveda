-- ==============================================================================
-- KIZUNA VEDA — PRODUCTION DEPLOYMENT BUNDLE (V1.5 through V1.8)
-- Target Project: gdxufikrumhxovmtavwj
-- Safe for execution in Supabase Dashboard SQL Editor
-- ==============================================================================


-- >>> START MIGRATION: f:\kizuna-veda\supabase\migrations\20261011150000_v1_5_editable_pricing_and_cost.sql >>>

-- ==============================================================================
-- KIZUNA VEDA — Database Migration V1.5
-- File: 20261011150000_v1_5_editable_pricing_and_cost.sql
-- Description: Editable Selling Price, Product Purchase Cost Management,
--              Snapshotted COGS/Historical Gross Profit, and Line Item Discounts.
--
-- IMPACT & SAFETY ASSESSMENT:
-- 1. Non-breaking: Uses ADD COLUMN IF NOT EXISTS with safe defaults for products
--    (standard_selling_price DEFAULT 100.00, purchase_cost DEFAULT 0.00).
-- 2. Non-breaking for sale_items: discount_amount defaults to 0.00; unit_cost is
--    nullable so legacy historical bills honestly reflect missing cost snapshots
--    without fabricating historical accounting numbers.
-- 3. Atomic RPC Update: fn_create_pos_sale snapshots current product purchase_cost
--    into sale_items.unit_cost at the exact moment of sale. Changing catalog prices
--    or purchase costs tomorrow will NEVER recalculate or alter past sales profits.
-- 4. Server-Side Permission Guard: Only OWNER role can update standard product prices
--    and purchase costs in public.products.
-- ==============================================================================

BEGIN;

-- ------------------------------------------------------------------------------
-- 1. Add Standard Selling Price & Purchase Cost to Products Catalog
-- ------------------------------------------------------------------------------
ALTER TABLE public.products
    ADD COLUMN IF NOT EXISTS standard_selling_price NUMERIC(12, 2) NOT NULL DEFAULT 100.00 CHECK (standard_selling_price >= 0),
    ADD COLUMN IF NOT EXISTS purchase_cost NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (purchase_cost >= 0);

-- Backfill existing standard catalog prices & production purchase costs for known SKUs
UPDATE public.products
SET standard_selling_price = 100.00,
    purchase_cost = 45.00
WHERE lower(sku) LIKE '%tulsi%' AND purchase_cost = 0;

UPDATE public.products
SET standard_selling_price = 120.00,
    purchase_cost = 55.00
WHERE (lower(sku) LIKE '%triphala%' OR lower(sku) LIKE '%tri%') AND purchase_cost = 0;

UPDATE public.products
SET standard_selling_price = 150.00,
    purchase_cost = 70.00
WHERE (lower(sku) LIKE '%ashwa%' OR lower(sku) LIKE '%ash%') AND purchase_cost = 0;

UPDATE public.products
SET standard_selling_price = 200.00,
    purchase_cost = 90.00
WHERE lower(sku) LIKE '%chy%' AND purchase_cost = 0;

-- ------------------------------------------------------------------------------
-- 2. Add Discount Amount and Snapshotted Unit Cost to Sale Items
-- ------------------------------------------------------------------------------
ALTER TABLE public.sale_items
    ADD COLUMN IF NOT EXISTS discount_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (discount_amount >= 0),
    ADD COLUMN IF NOT EXISTS unit_cost NUMERIC(12, 2) CHECK (unit_cost >= 0);

COMMENT ON COLUMN public.sale_items.discount_amount IS 'Discounts applied to this line item (>= 0).';
COMMENT ON COLUMN public.sale_items.unit_cost IS 'Snapshotted purchase cost per packet at the time of sale. NULL for legacy sales with missing cost data.';

-- ------------------------------------------------------------------------------
-- 3. RLS Security: Restrict Product Price/Cost Updates to OWNER Role Only
-- ------------------------------------------------------------------------------
DROP POLICY IF EXISTS "products_update_owner_policy" ON public.products;
CREATE POLICY "products_update_owner_policy" ON public.products
    FOR UPDATE
    TO authenticated
    USING (public.get_current_user_role() = 'owner')
    WITH CHECK (public.get_current_user_role() = 'owner');

-- ------------------------------------------------------------------------------
-- 4. Atomic POS Sale RPC: Support Editable Unit Price, Discounts & Cost Snapshots
-- ------------------------------------------------------------------------------
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
    v_discount NUMERIC(12, 2);
    v_unit_cost NUMERIC(12, 2);
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

    -- 3. Invoice Mode & GST Security Enforcement
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
    FOR v_item IN
        SELECT elem
        FROM jsonb_array_elements(p_items) elem
        ORDER BY (elem ->> 'product_id')::uuid
    LOOP
        v_product_id := (v_item ->> 'product_id')::uuid;
        v_quantity := (v_item ->> 'quantity')::int;
        v_unit_price := COALESCE((v_item ->> 'unit_price')::numeric, 0);
        v_discount := COALESCE((v_item ->> 'discount')::numeric, (v_item ->> 'discount_amount')::numeric, 0);

        IF v_product_id IS NULL THEN
            RAISE EXCEPTION 'Invalid line item: product_id is required.';
        END IF;

        IF v_quantity IS NULL OR v_quantity <= 0 THEN
            RAISE EXCEPTION 'Invalid line item quantity (must be > 0). Product ID: %', v_product_id;
        END IF;

        IF v_unit_price <= 0 THEN
            RAISE EXCEPTION 'Invalid line item unit price (must be > 0). Product ID: %', v_product_id;
        END IF;

        IF v_discount < 0 THEN
            RAISE EXCEPTION 'Invalid line item discount (must be >= 0). Product ID: %', v_product_id;
        END IF;

        IF v_discount > (v_quantity * v_unit_price) THEN
            RAISE EXCEPTION 'Discount cannot exceed line item total. Product ID: %', v_product_id;
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

        -- Exact stock deduction
        UPDATE public.store_inventory
        SET current_quantity = current_quantity - v_quantity,
            updated_at = now()
        WHERE location_id = v_target_location_id AND product_id = v_product_id;

        v_item_total := round((v_quantity * v_unit_price) - v_discount, 2);
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

    -- 9. Insert line items with snapshotted purchase cost from products catalog
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_product_id := (v_item ->> 'product_id')::uuid;
        v_quantity := (v_item ->> 'quantity')::int;
        v_unit_price := COALESCE((v_item ->> 'unit_price')::numeric, 0);
        v_discount := COALESCE((v_item ->> 'discount')::numeric, (v_item ->> 'discount_amount')::numeric, 0);

        -- Snapshot product purchase cost at time of sale
        SELECT purchase_cost INTO v_unit_cost
        FROM public.products
        WHERE id = v_product_id;

        INSERT INTO public.sale_items (
            sale_id,
            product_id,
            quantity,
            unit_price,
            discount_amount,
            unit_cost
        ) VALUES (
            v_sale_id,
            v_product_id,
            v_quantity,
            v_unit_price,
            v_discount,
            v_unit_cost
        );
    END LOOP;

    -- 10. Build and return created sale JSON
    RETURN (
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
                    'discount_amount', si.discount_amount,
                    'unit_cost', si.unit_cost,
                    'created_at', si.created_at
                ))
                FROM public.sale_items si
                WHERE si.sale_id = s.id
            )
        )
        FROM public.sales s
        WHERE s.id = v_sale_id
    );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_create_pos_sale(TEXT, TEXT, TEXT, JSONB, UUID, TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_create_pos_sale(TEXT, TEXT, TEXT, JSONB, UUID, TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC) TO authenticated;

COMMIT;


-- <<< END MIGRATION: f:\kizuna-veda\supabase\migrations\20261011150000_v1_5_editable_pricing_and_cost.sql <<<


-- >>> START MIGRATION: f:\kizuna-veda\supabase\migrations\20261012160000_v1_6_pos_idempotency_and_security.sql >>>

-- ==============================================================================
-- KIZUNA VEDA — Database Migration V1.6
-- File: 20261012160000_v1_6_pos_idempotency_and_security.sql
-- Description: POS Multi-Item Idempotency, Canonical SHA-256 Tampering Defense,
--              Server-Enforced Price & Discount Authorization, Wholesale Purchase
--              Cost Confidentiality Shield, and Concurrency-Safe Additive Stock
--              Receiving RPC.
--
-- GOVERNING REVIEWS:
-- - KIZUNA_VEDA_COUNCIL_AUDIT.md
-- - KIZUNA_VEDA_REMEDIATION_PLAN.md
--
-- ARCHITECTURAL INTEGRITY & SAFETY:
-- 1. Migration Ordering: Follows YYYYMMDDHHMMSS format strictly (20261012160000).
-- 2. Non-breaking Schema Additions: Uses IF NOT EXISTS and non-destructive columns.
-- 3. Idempotency Concurrency: Uses pg_advisory_xact_lock(hashtext(p_client_request_id::text)).
-- 4. Canonical Hashing: SHA-256 over normalized sale attributes (customer, phone,
--    payment, location, invoice type, sorted and normalized line items).
-- 5. Wholesale Cost Confidentiality:
--    - Catalog purchase costs isolated in owner-only product_procurement_costs.
--    - Historical sale purchase costs isolated in owner-only sale_item_procurement_costs.
--    - unit_cost removed from cashier-facing POS sale RPC returns.
-- 6. Concurrency-Safe Stock Receiving: fn_receive_store_stock uses an ON CONFLICT
--    DO NOTHING initialization followed by SELECT ... FOR UPDATE to eliminate
--    unique constraint race conditions while guaranteeing exact ledger auditing.
-- 7. Void Restoration: Multi-item voiding is preserved via existing trigger
--    trg_restore_voided_sale_stock on public.sales (no duplicate/ghost RPC declared).
-- ==============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ------------------------------------------------------------------------------
-- 1. POS Security & Discount Configuration Table
-- Note: 10.00% is an initial configurable technical default, NOT an approved business policy.
-- The Owner has full authority to modify max_cashier_discount_pct or allow_cashier_price_override
-- dynamically in this table at any time without database migrations.
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.pos_security_config (
    id TEXT PRIMARY KEY DEFAULT 'default',
    max_cashier_discount_pct NUMERIC(5, 2) NOT NULL DEFAULT 10.00 CHECK (max_cashier_discount_pct >= 0 AND max_cashier_discount_pct <= 100),
    allow_cashier_price_override BOOLEAN NOT NULL DEFAULT false,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by UUID REFERENCES auth.users(id)
);

ALTER TABLE public.pos_security_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "pos_security_config_read" ON public.pos_security_config;
CREATE POLICY "pos_security_config_read" ON public.pos_security_config
    FOR SELECT TO authenticated
    USING (true);

DROP POLICY IF EXISTS "pos_security_config_owner_update" ON public.pos_security_config;
CREATE POLICY "pos_security_config_owner_update" ON public.pos_security_config
    FOR ALL TO authenticated
    USING (public.get_current_user_role() = 'owner')
    WITH CHECK (public.get_current_user_role() = 'owner');

-- Ensure default configuration row exists (initial technical defaults; awaiting Owner business signoff)
INSERT INTO public.pos_security_config (id, max_cashier_discount_pct, allow_cashier_price_override)
VALUES ('default', 10.00, false)
ON CONFLICT (id) DO NOTHING;

-- ------------------------------------------------------------------------------
-- 2. Wholesale Purchase Cost Confidentiality Shield
-- ------------------------------------------------------------------------------
-- Catalog Wholesale Procurement Costs (Owner Only)
CREATE TABLE IF NOT EXISTS public.product_procurement_costs (
    product_id UUID PRIMARY KEY REFERENCES public.products(id) ON DELETE CASCADE,
    purchase_cost NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (purchase_cost >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.product_procurement_costs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "product_procurement_costs_owner_all" ON public.product_procurement_costs;
CREATE POLICY "product_procurement_costs_owner_all" ON public.product_procurement_costs
    FOR ALL TO authenticated
    USING (public.get_current_user_role() = 'owner')
    WITH CHECK (public.get_current_user_role() = 'owner');

-- Backfill from products.purchase_cost if records exist (rerun-safe: ignores 0.00 masked costs and never overwrites existing records)
INSERT INTO public.product_procurement_costs (product_id, purchase_cost, updated_at)
SELECT id, purchase_cost, now()
FROM public.products
WHERE purchase_cost > 0
ON CONFLICT (product_id) DO NOTHING;

-- Mask purchase_cost in public.products so cashiers querying products get 0.00
UPDATE public.products
SET purchase_cost = 0.00
WHERE purchase_cost > 0;

-- Sale Item Historical Procurement Costs (Owner Only)
CREATE TABLE IF NOT EXISTS public.sale_item_procurement_costs (
    sale_item_id UUID PRIMARY KEY REFERENCES public.sale_items(id) ON DELETE CASCADE,
    unit_cost NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (unit_cost >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.sale_item_procurement_costs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "sale_item_procurement_costs_owner_all" ON public.sale_item_procurement_costs;
CREATE POLICY "sale_item_procurement_costs_owner_all" ON public.sale_item_procurement_costs
    FOR ALL TO authenticated
    USING (public.get_current_user_role() = 'owner')
    WITH CHECK (public.get_current_user_role() = 'owner');

-- Backfill from existing sale_items.unit_cost if any
INSERT INTO public.sale_item_procurement_costs (sale_item_id, unit_cost, created_at)
SELECT id, COALESCE(unit_cost, 0.00), created_at
FROM public.sale_items
WHERE unit_cost IS NOT NULL AND unit_cost > 0
ON CONFLICT (sale_item_id) DO NOTHING;

-- Mask unit_cost on sale_items table to prevent direct table exposure to cashiers
UPDATE public.sale_items
SET unit_cost = 0.00
WHERE unit_cost > 0;

-- ------------------------------------------------------------------------------
-- 3. Idempotency Columns on public.sales
-- ------------------------------------------------------------------------------
ALTER TABLE public.sales
    ADD COLUMN IF NOT EXISTS client_request_id UUID UNIQUE,
    ADD COLUMN IF NOT EXISTS request_payload_hash TEXT;

CREATE INDEX IF NOT EXISTS idx_sales_client_request_id ON public.sales(client_request_id);

-- ------------------------------------------------------------------------------
-- 4. Audit & Price Override Columns on public.sale_items
-- ------------------------------------------------------------------------------
ALTER TABLE public.sale_items
    ADD COLUMN IF NOT EXISTS catalog_price NUMERIC(12, 2),
    ADD COLUMN IF NOT EXISTS is_price_override BOOLEAN DEFAULT false,
    ADD COLUMN IF NOT EXISTS override_reason TEXT;

-- ------------------------------------------------------------------------------
-- 5. Owner Product Pricing & Cost Update RPC
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_update_product_pricing(
    p_product_id UUID,
    p_standard_selling_price NUMERIC,
    p_purchase_cost NUMERIC
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF public.get_current_user_role() <> 'owner' THEN
        RAISE EXCEPTION 'Unauthorized: Only OWNER role can update standard product prices and procurement costs.';
    END IF;

    IF p_standard_selling_price < 0 THEN
        RAISE EXCEPTION 'Standard selling price cannot be negative.';
    END IF;

    IF p_purchase_cost < 0 THEN
        RAISE EXCEPTION 'Purchase cost cannot be negative.';
    END IF;

    UPDATE public.products
    SET standard_selling_price = p_standard_selling_price
    WHERE id = p_product_id;

    INSERT INTO public.product_procurement_costs (product_id, purchase_cost, updated_at)
    VALUES (p_product_id, p_purchase_cost, now())
    ON CONFLICT (product_id) DO UPDATE
    SET purchase_cost = EXCLUDED.purchase_cost,
        updated_at = now();

    RETURN jsonb_build_object(
        'success', true,
        'product_id', p_product_id,
        'standard_selling_price', p_standard_selling_price,
        'purchase_cost', p_purchase_cost
    );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_update_product_pricing(UUID, NUMERIC, NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_update_product_pricing(UUID, NUMERIC, NUMERIC) TO authenticated, service_role;

-- ------------------------------------------------------------------------------
-- 6. Concurrency-Safe Additive Stock Receiving RPC
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_receive_store_stock(
    p_location_id UUID,
    p_product_id UUID,
    p_quantity INT,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_role TEXT;
    v_prev_qty INT := 0;
    v_new_qty INT := 0;
    v_inv_id UUID;
    v_adj_id UUID;
    c_neemrana_id CONSTANT UUID := '11111111-1111-1111-1111-111111111111'::uuid;
    c_jaipur_id CONSTANT UUID := '22222222-2222-2222-2222-222222222222'::uuid;
BEGIN
    -- 1. Role verification
    v_role := public.get_current_user_role();
    IF v_role NOT IN ('owner', 'neemrana', 'jaipur') THEN
        RAISE EXCEPTION 'Unauthorized: Only OWNER, NEEMRANA, or JAIPUR roles can receive stock.';
    END IF;

    -- 2. Store location authorization boundary
    IF v_role = 'neemrana' AND p_location_id <> c_neemrana_id THEN
        RAISE EXCEPTION 'Neemrana operators can only receive stock for Neemrana store.';
    END IF;

    IF v_role = 'jaipur' AND p_location_id <> c_jaipur_id THEN
        RAISE EXCEPTION 'Jaipur operators can only receive stock for Jaipur store.';
    END IF;

    IF p_location_id NOT IN (c_neemrana_id, c_jaipur_id) THEN
        RAISE EXCEPTION 'Invalid store location for stock receipt: %', p_location_id;
    END IF;

    -- 3. Quantity validation
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Received stock quantity must be greater than zero (provided: %).', p_quantity;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.products WHERE id = p_product_id AND active = true) THEN
        RAISE EXCEPTION 'Product with ID % does not exist or is inactive.', p_product_id;
    END IF;

    -- 4. Concurrency-safe initialization: Ensure row exists under concurrent first-time inserts
    INSERT INTO public.store_inventory (location_id, product_id, current_quantity)
    VALUES (p_location_id, p_product_id, 0)
    ON CONFLICT (location_id, product_id) DO NOTHING;

    -- 5. Atomically acquire exclusive row lock and read accurate baseline quantity
    SELECT current_quantity, id INTO v_prev_qty, v_inv_id
    FROM public.store_inventory
    WHERE location_id = p_location_id AND product_id = p_product_id
    FOR UPDATE;

    -- 6. Additively increment stock
    v_new_qty := v_prev_qty + p_quantity;
    UPDATE public.store_inventory
    SET current_quantity = v_new_qty,
        updated_at = now()
    WHERE id = v_inv_id;

    -- 7. Atomically record immutable audit ledger entry in stock_adjustments
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
        v_new_qty,
        p_quantity,
        'STOCK_RECEIPT',
        COALESCE(trim(p_notes), 'Stock received into store'),
        auth.uid(),
        now()
    )
    RETURNING id INTO v_adj_id;

    RETURN jsonb_build_object(
        'success', true,
        'location_id', p_location_id,
        'product_id', p_product_id,
        'previous_quantity', v_prev_qty,
        'new_quantity', v_new_qty,
        'change_quantity', p_quantity,
        'adjustment_id', v_adj_id
    );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_receive_store_stock(UUID, UUID, INT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_receive_store_stock(UUID, UUID, INT, TEXT) TO authenticated, service_role;

-- ------------------------------------------------------------------------------
-- 7. Enhanced POS Sale RPC: Multi-Item, SHA-256 Idempotency, and Cost Shield
-- ------------------------------------------------------------------------------
-- Drop legacy 11-argument overload to prevent PostgREST PGRST203 function ambiguity
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
    p_igst_amount NUMERIC DEFAULT 0.00,
    p_client_request_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_role TEXT;
    v_target_location_id UUID;
    v_sale_id UUID;
    v_existing_sale_id UUID;
    v_existing_payload_hash TEXT;
    v_canonical_items_json JSONB;
    v_canonical_json JSONB;
    v_incoming_payload_hash TEXT;
    v_bill_number TEXT;
    v_calculated_subtotal NUMERIC(12, 2) := 0;
    v_item JSONB;
    v_product_id UUID;
    v_quantity INT;
    v_unit_price NUMERIC(12, 2);
    v_discount NUMERIC(12, 2);
    v_catalog_price NUMERIC(12, 2);
    v_unit_cost NUMERIC(12, 2);
    v_item_total NUMERIC(12, 2);
    v_item_gross NUMERIC(12, 2);
    v_discount_pct NUMERIC(7, 4);
    v_is_override BOOLEAN;
    v_override_reason TEXT;
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
    v_available_stock INT;
    v_max_cashier_discount_pct NUMERIC(5, 2) := 10.00;
    v_allow_cashier_price_override BOOLEAN := false;
    v_sale_item_id UUID;
    c_neemrana_id CONSTANT UUID := '11111111-1111-1111-1111-111111111111'::uuid;
    c_jaipur_id CONSTANT UUID := '22222222-2222-2222-2222-222222222222'::uuid;
BEGIN
    -- 1. Server-side role & location verification
    v_role := public.get_current_user_role();
    IF v_role NOT IN ('owner', 'neemrana', 'jaipur') THEN
        RAISE EXCEPTION 'Unauthorized: Only OWNER, NEEMRANA, or JAIPUR roles can create POS sales.';
    END IF;

    IF v_role = 'neemrana' THEN
        IF p_location_id IS NOT NULL AND p_location_id <> c_neemrana_id THEN
            RAISE EXCEPTION 'Neemrana operators can only create sales for Neemrana store.';
        END IF;
        v_target_location_id := c_neemrana_id;
    ELSIF v_role = 'jaipur' THEN
        IF p_location_id IS NOT NULL AND p_location_id <> c_jaipur_id THEN
            RAISE EXCEPTION 'Jaipur operators can only create sales for Jaipur store.';
        END IF;
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

    -- 3. Invoice Mode & GST Security Enforcement
    v_clean_type := upper(trim(COALESCE(p_invoice_type, 'NON_GST')));
    IF v_clean_type NOT IN ('NON_GST', 'GST') THEN
        RAISE EXCEPTION 'Invalid invoice type "%". Allowed values: NON_GST, GST.', p_invoice_type;
    END IF;

    IF v_clean_type = 'GST' THEN
        RAISE EXCEPTION 'GST billing is currently disabled until verified business GST configuration is enabled server-side.';
    END IF;

    -- 4. Line items payload validation
    IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'POS sale must contain at least one line item.';
    END IF;

    -- 5. Concurrency Control & Unambiguous Canonical SHA-256 Idempotency Verification
    IF p_client_request_id IS NOT NULL THEN
        -- Acquire transaction-level advisory lock on client request ID to serialize concurrent requests
        PERFORM pg_advisory_xact_lock(hashtext(p_client_request_id::text));

        -- Construct unambiguous canonical JSON representation of line items
        -- Normalizes and sorts deterministically by (product_id, quantity, unit_price, discount)
        -- to eliminate any delimiter ambiguity or duplicate product line ordering variations.
        SELECT jsonb_agg(
            jsonb_build_object(
                'discount', round(COALESCE((item ->> 'discount')::numeric, (item ->> 'discount_amount')::numeric, 0), 2),
                'product_id', (item ->> 'product_id')::uuid,
                'quantity', (item ->> 'quantity')::int,
                'unit_price', round(COALESCE((item ->> 'unit_price')::numeric, 0), 2)
            )
        )
        INTO v_canonical_items_json
        FROM (
            SELECT elem AS item
            FROM jsonb_array_elements(p_items) elem
            ORDER BY 
                (elem ->> 'product_id')::uuid ASC,
                (elem ->> 'quantity')::int ASC,
                round(COALESCE((elem ->> 'unit_price')::numeric, 0), 2) ASC,
                round(COALESCE((elem ->> 'discount')::numeric, (elem ->> 'discount_amount')::numeric, 0), 2) ASC
        ) sorted_items;

        v_canonical_json := jsonb_build_object(
            'canonical_version', 1,
            'customer_name', v_clean_name,
            'customer_phone', v_clean_phone,
            'invoice_type', v_clean_type,
            'items', COALESCE(v_canonical_items_json, '[]'::jsonb),
            'location_id', v_target_location_id,
            'payment_method', v_clean_method
        );

        -- Compute cryptographic SHA-256 hash over canonical JSON representation
        v_incoming_payload_hash := encode(digest(convert_to(v_canonical_json::text, 'UTF8'), 'sha256'), 'hex');

        -- Check if request ID has already been committed
        SELECT id, request_payload_hash INTO v_existing_sale_id, v_existing_payload_hash
        FROM public.sales
        WHERE client_request_id = p_client_request_id;

        IF FOUND THEN
            -- Check for legacy unhashed record or payload tampering
            IF v_existing_payload_hash IS NULL THEN
                -- Explicit fail-closed policy: legacy record without hash cannot be safely verified for replay
                RAISE EXCEPTION 'Idempotency conflict: Client request ID % exists on a legacy record without a verified payload hash. Request cannot be safely replayed.', p_client_request_id;
            ELSIF v_existing_payload_hash <> v_incoming_payload_hash THEN
                RAISE EXCEPTION 'Idempotency conflict: client_request_id % was already used with a different request payload.', p_client_request_id;
            END IF;

            -- Return previously committed sale JSON WITHOUT unit_cost to prevent cost leakage
            RETURN (
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
                    'client_request_id', s.client_request_id,
                    'product_id', (SELECT si.product_id FROM public.sale_items si WHERE si.sale_id = s.id LIMIT 1),
                    'quantity', (SELECT COALESCE(SUM(si.quantity), 0) FROM public.sale_items si WHERE si.sale_id = s.id),
                    'sale_items', (
                        SELECT jsonb_agg(jsonb_build_object(
                            'id', si.id,
                            'sale_id', si.sale_id,
                            'product_id', si.product_id,
                            'quantity', si.quantity,
                            'unit_price', si.unit_price,
                            'discount_amount', si.discount_amount,
                            'catalog_price', si.catalog_price,
                            'is_price_override', si.is_price_override,
                            'override_reason', si.override_reason,
                            'created_at', si.created_at
                        ))
                        FROM public.sale_items si
                        WHERE si.sale_id = s.id
                    )
                )
                FROM public.sales s
                WHERE s.id = v_existing_sale_id
            );
        END IF;
    END IF;

    -- 6. Load isolated security policy configuration
    SELECT max_cashier_discount_pct, allow_cashier_price_override
    INTO v_max_cashier_discount_pct, v_allow_cashier_price_override
    FROM public.pos_security_config
    WHERE id = 'default';

    IF v_max_cashier_discount_pct IS NULL THEN
        v_max_cashier_discount_pct := 10.00;
    END IF;
    IF v_allow_cashier_price_override IS NULL THEN
        v_allow_cashier_price_override := false;
    END IF;

    -- 7. Validate line items, enforce pricing rules, and lock/deduct store stock
    FOR v_item IN
        SELECT elem
        FROM jsonb_array_elements(p_items) elem
        ORDER BY (elem ->> 'product_id')::uuid
    LOOP
        v_product_id := (v_item ->> 'product_id')::uuid;
        v_quantity := (v_item ->> 'quantity')::int;
        v_unit_price := COALESCE((v_item ->> 'unit_price')::numeric, 0);
        v_discount := COALESCE((v_item ->> 'discount')::numeric, (v_item ->> 'discount_amount')::numeric, 0);

        IF v_product_id IS NULL THEN
            RAISE EXCEPTION 'Invalid line item: product_id is required.';
        END IF;

        IF v_quantity IS NULL OR v_quantity <= 0 THEN
            RAISE EXCEPTION 'Invalid line item quantity (must be > 0). Product ID: %', v_product_id;
        END IF;

        IF v_unit_price <= 0 THEN
            RAISE EXCEPTION 'Invalid line item unit price (must be > 0). Product ID: %', v_product_id;
        END IF;

        IF v_discount < 0 THEN
            RAISE EXCEPTION 'Invalid line item discount (must be >= 0). Product ID: %', v_product_id;
        END IF;

        -- Fetch official catalog price
        SELECT standard_selling_price INTO v_catalog_price
        FROM public.products
        WHERE id = v_product_id AND active = true;

        IF NOT FOUND OR v_catalog_price IS NULL THEN
            RAISE EXCEPTION 'Product with ID % does not exist or is inactive.', v_product_id;
        END IF;

        -- Server-side Cashier Authorization Checks
        IF v_role IN ('neemrana', 'jaipur') THEN
            -- Price Override Check
            IF abs(v_unit_price - v_catalog_price) > 0.001 AND NOT v_allow_cashier_price_override THEN
                RAISE EXCEPTION 'Unauthorized price modification: Cashier role "%" cannot modify catalog price (Catalog: %, Provided: %). Owner authorization required.',
                    v_role, v_catalog_price, v_unit_price;
            END IF;

            -- Discount Percentage Check (gross catalog value = quantity * catalog_price)
            v_item_gross := round(v_quantity * v_catalog_price, 2);
            IF v_discount > 0 AND v_item_gross > 0 THEN
                v_discount_pct := round((v_discount / v_item_gross) * 100.0, 4);
                IF v_discount_pct > v_max_cashier_discount_pct THEN
                    RAISE EXCEPTION 'Unauthorized discount: Cashier discount (% pct) exceeds allowed maximum of % pct. Owner authorization required.',
                        round(v_discount_pct, 1), v_max_cashier_discount_pct;
                END IF;
            END IF;
        END IF;

        IF v_discount > (v_quantity * v_unit_price) THEN
            RAISE EXCEPTION 'Discount cannot exceed line item total. Product ID: %', v_product_id;
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

        -- Exact stock deduction
        UPDATE public.store_inventory
        SET current_quantity = current_quantity - v_quantity,
            updated_at = now()
        WHERE location_id = v_target_location_id AND product_id = v_product_id;

        v_item_total := round((v_quantity * v_unit_price) - v_discount, 2);
        v_calculated_subtotal := v_calculated_subtotal + v_item_total;
    END LOOP;

    -- 8. Calculate invoice amounts
    v_gst_rate := 0.00;
    v_taxable_amount := v_calculated_subtotal;
    v_cgst_amount := 0.00;
    v_sgst_amount := 0.00;
    v_igst_amount := 0.00;
    v_grand_total := v_calculated_subtotal;

    -- 9. Generate unique bill number
    v_bill_number := 'BILL-' || lpad(nextval('public.seq_bill_number')::text, 6, '0');

    -- 10. Insert parent sale record with request token
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
        sold_at,
        client_request_id,
        request_payload_hash
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
        now(),
        p_client_request_id,
        v_incoming_payload_hash
    )
    RETURNING id INTO v_sale_id;

    -- 11. Insert line items & store confidential cost in owner-only procurement table
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_product_id := (v_item ->> 'product_id')::uuid;
        v_quantity := (v_item ->> 'quantity')::int;
        v_unit_price := COALESCE((v_item ->> 'unit_price')::numeric, 0);
        v_discount := COALESCE((v_item ->> 'discount')::numeric, (v_item ->> 'discount_amount')::numeric, 0);

        -- Fetch official catalog price
        SELECT standard_selling_price INTO v_catalog_price
        FROM public.products
        WHERE id = v_product_id;

        -- Snapshot confidential procurement cost from owner-restricted table
        SELECT purchase_cost INTO v_unit_cost
        FROM public.product_procurement_costs
        WHERE product_id = v_product_id;

        IF v_unit_cost IS NULL THEN
            v_unit_cost := 0.00;
        END IF;

        v_is_override := abs(v_unit_price - v_catalog_price) > 0.001;
        v_override_reason := CASE
            WHEN v_is_override THEN COALESCE(v_item ->> 'override_reason', 'AUTHORIZED_PRICE_OVERRIDE')
            ELSE NULL
        END;

        -- Insert sale item without storing plaintext unit_cost in public table
        INSERT INTO public.sale_items (
            sale_id,
            product_id,
            quantity,
            unit_price,
            discount_amount,
            unit_cost,
            catalog_price,
            is_price_override,
            override_reason
        ) VALUES (
            v_sale_id,
            v_product_id,
            v_quantity,
            v_unit_price,
            v_discount,
            0.00, -- Masked to 0.00 for cashier queries
            v_catalog_price,
            v_is_override,
            v_override_reason
        )
        RETURNING id INTO v_sale_item_id;

        -- Store confidential snapshotted cost in owner-restricted table
        INSERT INTO public.sale_item_procurement_costs (
            sale_item_id,
            unit_cost,
            created_at
        ) VALUES (
            v_sale_item_id,
            v_unit_cost,
            now()
        );
    END LOOP;

    -- 12. Build and return created sale JSON (unit_cost omitted to prevent leakage)
    RETURN (
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
            'client_request_id', s.client_request_id,
            'product_id', (SELECT si.product_id FROM public.sale_items si WHERE si.sale_id = s.id LIMIT 1),
            'quantity', (SELECT COALESCE(SUM(si.quantity), 0) FROM public.sale_items si WHERE si.sale_id = s.id),
            'sale_items', (
                SELECT jsonb_agg(jsonb_build_object(
                    'id', si.id,
                    'sale_id', si.sale_id,
                    'product_id', si.product_id,
                    'quantity', si.quantity,
                    'unit_price', si.unit_price,
                    'discount_amount', si.discount_amount,
                    'catalog_price', si.catalog_price,
                    'is_price_override', si.is_price_override,
                    'override_reason', si.override_reason,
                    'created_at', si.created_at
                ))
                FROM public.sale_items si
                WHERE si.sale_id = s.id
            )
        )
        FROM public.sales s
        WHERE s.id = v_sale_id
    );
END;
$$;

-- Grant execute permissions to authenticated and service_role
REVOKE ALL ON FUNCTION public.fn_create_pos_sale(TEXT, TEXT, TEXT, JSONB, UUID, TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_create_pos_sale(TEXT, TEXT, TEXT, JSONB, UUID, TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, UUID) TO authenticated, service_role;

-- ------------------------------------------------------------------------------
-- 7. Owner Reporting Views (COGS, Historical Unit Costs, and Catalog Margins)
-- ------------------------------------------------------------------------------
-- These views join public product/sales data with confidential procurement tables.
-- With security_invoker = true, PostgreSQL evaluates RLS policies against the
-- querying user:
--   - OWNER role sees snapshotted procurement costs, COGS, and gross profit.
--   - CASHIER roles see NULL / 0.00 procurement costs due to RLS isolation.

CREATE OR REPLACE VIEW public.v_product_procurement_summary
WITH (security_invoker = true) AS
SELECT
    p.id AS product_id,
    p.name AS product_name,
    p.sku,
    p.package_size,
    p.active,
    p.standard_selling_price,
    COALESCE(ppc.purchase_cost, 0.00) AS purchase_cost,
    ppc.updated_at AS cost_last_updated_at
FROM public.products p
LEFT JOIN public.product_procurement_costs ppc ON ppc.product_id = p.id;

GRANT SELECT ON public.v_product_procurement_summary TO authenticated, service_role;

CREATE OR REPLACE VIEW public.v_owner_sales_cogs_reporting
WITH (security_invoker = true) AS
SELECT
    s.id AS sale_id,
    s.location_id,
    s.bill_number,
    s.customer_name,
    s.customer_phone,
    s.payment_method,
    s.invoice_type,
    s.taxable_amount AS subtotal,
    round(s.cgst_amount + s.sgst_amount + s.igst_amount, 2) AS tax_amount,
    s.total_amount,
    s.status,
    s.created_at AS sale_created_at,
    si.id AS sale_item_id,
    si.product_id,
    si.quantity,
    si.unit_price,
    si.discount_amount AS item_discount_amount,
    round((si.quantity * si.unit_price) - si.discount_amount, 2) AS item_total_amount,
    sipc.unit_cost AS snapshotted_unit_cost,
    round(si.quantity * sipc.unit_cost, 2) AS line_cogs,
    round(((si.quantity * si.unit_price) - si.discount_amount) - (si.quantity * sipc.unit_cost), 2) AS line_gross_profit
FROM public.sales s
JOIN public.sale_items si ON si.sale_id = s.id
LEFT JOIN public.sale_item_procurement_costs sipc ON sipc.sale_item_id = si.id;

GRANT SELECT ON public.v_owner_sales_cogs_reporting TO authenticated, service_role;

-- Notify PostgREST to reload its schema cache
NOTIFY pgrst, 'reload schema';

COMMIT;



-- <<< END MIGRATION: f:\kizuna-veda\supabase\migrations\20261012160000_v1_6_pos_idempotency_and_security.sql <<<


-- >>> START MIGRATION: f:\kizuna-veda\supabase\migrations\20261013110000_fix_sale_item_procurement_costs_relationship.sql >>>

-- ==============================================================================
-- KIZUNA VEDA — Database Migration: Fix Sale Item Procurement Costs Relationship
-- File: supabase/migrations/20261013110000_fix_sale_item_procurement_costs_relationship.sql
--
-- Objective:
-- Resolves PGRST200 ("Could not find a relationship between 'sale_items' and
-- 'sale_item_procurement_costs' in the schema cache") by establishing the verified,
-- idempotent foreign key relationship between sale_items and sale_item_procurement_costs,
-- enforcing Owner-only Row Level Security (RLS), and refreshing the PostgREST schema cache.
--
-- Safety & Idempotency Guarantees:
-- 1. Uses CREATE TABLE IF NOT EXISTS and DO $$ blocks for repeatable execution.
-- 2. Checks and resolves orphan records before adding foreign key constraints.
-- 3. Retains strict Owner-only RLS: Cashiers cannot read or leak wholesale procurement costs.
-- 4. Sends NOTIFY pgrst, 'reload schema' to force PostgREST cache invalidation.
-- 5. Safe for execution in local/staging Supabase environments.
-- ==============================================================================

BEGIN;

-- 1. Ensure the parent sale_items table exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'sale_items'
    ) THEN
        RAISE EXCEPTION 'Parent table public.sale_items must exist before creating sale_item_procurement_costs.';
    END IF;
END $$;

-- 2. Create public.sale_item_procurement_costs if it does not yet exist
CREATE TABLE IF NOT EXISTS public.sale_item_procurement_costs (
    sale_item_id UUID PRIMARY KEY,
    unit_cost NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (unit_cost >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. Clean up any existing orphan rows before establishing Foreign Key constraint
DELETE FROM public.sale_item_procurement_costs
WHERE sale_item_id NOT IN (SELECT id FROM public.sale_items);

-- 4. Idempotently add the foreign key constraint referencing public.sale_items(id)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = 'public'
          AND t.relname = 'sale_item_procurement_costs'
          AND c.contype = 'f'
          AND c.conname = 'sale_item_procurement_costs_sale_item_id_fkey'
    ) THEN
        ALTER TABLE public.sale_item_procurement_costs
            ADD CONSTRAINT sale_item_procurement_costs_sale_item_id_fkey
            FOREIGN KEY (sale_item_id)
            REFERENCES public.sale_items(id)
            ON DELETE CASCADE;
    END IF;
END $$;

-- 5. Create index on the foreign key column if not already present
CREATE INDEX IF NOT EXISTS idx_sale_item_procurement_costs_sale_item_id
    ON public.sale_item_procurement_costs(sale_item_id);

-- 6. Enforce Row Level Security (RLS) — Owner-Only Access
ALTER TABLE public.sale_item_procurement_costs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "sale_item_procurement_costs_owner_all" ON public.sale_item_procurement_costs;
CREATE POLICY "sale_item_procurement_costs_owner_all" ON public.sale_item_procurement_costs
    FOR ALL TO authenticated
    USING (public.get_current_user_role() = 'owner')
    WITH CHECK (public.get_current_user_role() = 'owner');

-- 7. Grant permissions: authenticated users may access subject to RLS; service_role has full access
GRANT ALL ON public.sale_item_procurement_costs TO authenticated, service_role;

-- 8. Backfill historical costs from sale_items.unit_cost if present
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'sale_items'
          AND column_name = 'unit_cost'
    ) THEN
        INSERT INTO public.sale_item_procurement_costs (sale_item_id, unit_cost, created_at)
        SELECT id, COALESCE(unit_cost, 0.00), created_at
        FROM public.sale_items
        WHERE unit_cost IS NOT NULL AND unit_cost > 0
        ON CONFLICT (sale_item_id) DO NOTHING;
    END IF;
END $$;

-- 9. Refresh PostgREST schema cache so the relationship is instantly recognized
NOTIFY pgrst, 'reload schema';

COMMIT;


-- <<< END MIGRATION: f:\kizuna-veda\supabase\migrations\20261013110000_fix_sale_item_procurement_costs_relationship.sql <<<


-- >>> START MIGRATION: f:\kizuna-veda\supabase\migrations\20261014130000_v1_7_independent_stores_isolation.sql >>>

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


-- <<< END MIGRATION: f:\kizuna-veda\supabase\migrations\20261014130000_v1_7_independent_stores_isolation.sql <<<


-- >>> START MIGRATION: f:\kizuna-veda\supabase\migrations\20261015100000_v1_7_transfers_privileges_hardening.sql >>>

-- ==============================================================================
-- KIZUNA VEDA — Database Migration: Transfers Privilege Hardening (V1.7)
-- File: supabase/migrations/20261015100000_v1_7_transfers_privileges_hardening.sql
--
-- Objective:
-- Hardens public.transfers table-level grants by revoking all mutation privileges
-- (INSERT, UPDATE, DELETE, TRUNCATE, TRIGGER, REFERENCES) from 'authenticated',
-- 'anon', and 'PUBLIC'.
--
-- Defense-in-Depth Architecture:
-- 1. Table Grants: Revoke all mutation privileges from authenticated, anon, and PUBLIC.
-- 2. Table Grants: Revoke SELECT from anon and PUBLIC. Only authenticated and service_role
--    retain table-level SELECT privilege.
-- 3. Row Level Security: Deny-all mutation policies (WITH CHECK (false), USING (false))
--    remain active on public.transfers.
-- 4. Row Level Security: SELECT is strictly scoped to owner (public.get_current_user_role() = 'owner').
-- 5. Immutability Trigger: trg_no_delete_transfers trigger guarantees zero historical deletions.
-- ==============================================================================

BEGIN;

-- 1. Revoke all table-level mutation privileges on public.transfers
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, TRIGGER, REFERENCES ON public.transfers FROM authenticated, anon, PUBLIC;

-- 2. Revoke SELECT from anon and PUBLIC (unauthenticated actors cannot view transfer audit logs)
REVOKE SELECT ON public.transfers FROM anon, PUBLIC;

-- 3. Explicitly grant SELECT to authenticated and service_role
GRANT SELECT ON public.transfers TO authenticated, service_role;

-- 4. Invalidate and reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

COMMIT;


-- <<< END MIGRATION: f:\kizuna-veda\supabase\migrations\20261015100000_v1_7_transfers_privileges_hardening.sql <<<


-- >>> START MIGRATION: f:\kizuna-veda\supabase\migrations\20261015120000_v1_8_cashier_discount_policy_hardening.sql >>>

-- ==============================================================================
-- Migration: 20261015120000_v1_8_cashier_discount_policy_hardening.sql
-- Description: Authoritative Database Enforcement of Cashier Discount Ceiling (Max 10%)
--
-- Business Rules & Safety Contracts:
-- 1. Cashiers (neemrana, jaipur) may apply a maximum discount of 10.00% per sale line.
-- 2. Discounts above 10% are strictly rejected server-side in fn_create_pos_sale.
-- 3. Negative, malformed, non-finite (NaN), or exceeding-line-total discounts are rejected.
-- 4. Multi-item bills are validated on every line; no partial commits or silent clamping.
-- 5. Owner permissions are preserved: Owner is authorized to apply custom discounts (> 10%),
--    update pos_security_config, and update product catalog prices.
-- 6. Direct table writes to sales / sale_items are blocked by RLS to prevent API bypass.
-- ==============================================================================

-- 1. POS Security Configuration Table
CREATE TABLE IF NOT EXISTS public.pos_security_config (
    id TEXT PRIMARY KEY DEFAULT 'default',
    max_cashier_discount_pct NUMERIC(5, 2) NOT NULL DEFAULT 10.00 CHECK (max_cashier_discount_pct >= 0 AND max_cashier_discount_pct <= 100),
    allow_cashier_price_override BOOLEAN NOT NULL DEFAULT false,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by UUID REFERENCES auth.users(id)
);

ALTER TABLE public.pos_security_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "pos_security_config_read" ON public.pos_security_config;
CREATE POLICY "pos_security_config_read" ON public.pos_security_config
    FOR SELECT TO authenticated
    USING (true);

DROP POLICY IF EXISTS "pos_security_config_owner_update" ON public.pos_security_config;
CREATE POLICY "pos_security_config_owner_update" ON public.pos_security_config
    FOR ALL TO authenticated
    USING (public.get_current_user_role() = 'owner')
    WITH CHECK (public.get_current_user_role() = 'owner');

-- Ensure default configuration row exists with approved 10.00% maximum cashier discount ceiling
INSERT INTO public.pos_security_config (id, max_cashier_discount_pct, allow_cashier_price_override)
VALUES ('default', 10.00, false)
ON CONFLICT (id) DO UPDATE
SET max_cashier_discount_pct = EXCLUDED.max_cashier_discount_pct
WHERE public.pos_security_config.max_cashier_discount_pct IS NULL;

-- 2. Hardened fn_create_pos_sale Function
CREATE OR REPLACE FUNCTION public.fn_create_pos_sale(
    p_customer_name TEXT,
    p_customer_phone TEXT,
    p_payment_method TEXT,
    p_items JSONB,
    p_location_id UUID DEFAULT NULL,
    p_invoice_type TEXT DEFAULT 'NON_GST',
    p_gst_rate NUMERIC DEFAULT 0.0,
    p_taxable_amount NUMERIC DEFAULT NULL,
    p_cgst_amount NUMERIC DEFAULT 0.0,
    p_sgst_amount NUMERIC DEFAULT 0.0,
    p_igst_amount NUMERIC DEFAULT 0.0,
    p_client_request_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_role TEXT;
    v_target_location_id UUID;
    v_sale_id UUID;
    v_bill_number TEXT;
    v_existing_sale_id UUID;
    v_existing_payload_hash TEXT;
    v_incoming_payload_hash TEXT;
    v_canonical_json JSONB;
    v_canonical_items_json JSONB;
    v_calculated_subtotal NUMERIC(12, 2) := 0.00;
    v_item JSONB;
    v_product_id UUID;
    v_quantity INT;
    v_unit_price NUMERIC(12, 2);
    v_discount NUMERIC(12, 2);
    v_catalog_price NUMERIC(12, 2);
    v_procurement_cost NUMERIC(12, 2);
    v_item_total NUMERIC(12, 2);
    v_item_gross NUMERIC(12, 2);
    v_discount_pct NUMERIC(7, 4);
    v_is_override BOOLEAN;
    v_override_reason TEXT;
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
    v_available_stock INT;
    v_max_cashier_discount_pct NUMERIC(5, 2) := 10.00;
    v_allow_cashier_price_override BOOLEAN := false;
    v_sale_item_id UUID;
    c_neemrana_id CONSTANT UUID := '11111111-1111-1111-1111-111111111111'::uuid;
    c_jaipur_id CONSTANT UUID := '22222222-2222-2222-2222-222222222222'::uuid;
BEGIN
    -- 1. Server-side role & location verification
    v_role := public.get_current_user_role();
    IF v_role NOT IN ('owner', 'neemrana', 'jaipur') THEN
        RAISE EXCEPTION 'Unauthorized: Only OWNER, NEEMRANA, or JAIPUR roles can create POS sales.';
    END IF;

    IF v_role = 'neemrana' THEN
        IF p_location_id IS NOT NULL AND p_location_id <> c_neemrana_id THEN
            RAISE EXCEPTION 'Neemrana operators can only create sales for Neemrana store.';
        END IF;
        v_target_location_id := c_neemrana_id;
    ELSIF v_role = 'jaipur' THEN
        IF p_location_id IS NOT NULL AND p_location_id <> c_jaipur_id THEN
            RAISE EXCEPTION 'Jaipur operators can only create sales for Jaipur store.';
        END IF;
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

    -- 3. Invoice Mode & GST Security Enforcement
    v_clean_type := upper(trim(COALESCE(p_invoice_type, 'NON_GST')));
    IF v_clean_type NOT IN ('NON_GST', 'GST') THEN
        RAISE EXCEPTION 'Invalid invoice type "%". Allowed values: NON_GST, GST.', p_invoice_type;
    END IF;

    IF v_clean_type = 'GST' THEN
        RAISE EXCEPTION 'GST billing is currently disabled until verified business GST configuration is enabled server-side.';
    END IF;

    -- 4. Line items payload validation
    IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'POS sale must contain at least one line item.';
    END IF;

    -- 5. Concurrency Control & Canonical SHA-256 Idempotency Verification
    IF p_client_request_id IS NOT NULL THEN
        PERFORM pg_advisory_xact_lock(hashtext(p_client_request_id::text));

        SELECT jsonb_agg(
            jsonb_build_object(
                'discount', round(COALESCE((item ->> 'discount')::numeric, (item ->> 'discount_amount')::numeric, 0), 2),
                'product_id', (item ->> 'product_id')::uuid,
                'quantity', (item ->> 'quantity')::int,
                'unit_price', round(COALESCE((item ->> 'unit_price')::numeric, 0), 2)
            )
        )
        INTO v_canonical_items_json
        FROM (
            SELECT elem AS item
            FROM jsonb_array_elements(p_items) elem
            ORDER BY 
                (elem ->> 'product_id')::uuid ASC,
                (elem ->> 'quantity')::int ASC,
                round(COALESCE((elem ->> 'unit_price')::numeric, 0), 2) ASC,
                round(COALESCE((elem ->> 'discount')::numeric, (elem ->> 'discount_amount')::numeric, 0), 2) ASC
        ) sorted_items;

        v_canonical_json := jsonb_build_object(
            'canonical_version', 1,
            'customer_name', v_clean_name,
            'customer_phone', v_clean_phone,
            'invoice_type', v_clean_type,
            'items', COALESCE(v_canonical_items_json, '[]'::jsonb),
            'location_id', v_target_location_id,
            'payment_method', v_clean_method
        );

        v_incoming_payload_hash := encode(extensions.digest(convert_to(v_canonical_json::text, 'UTF8'), 'sha256'), 'hex');

        SELECT id, request_payload_hash INTO v_existing_sale_id, v_existing_payload_hash
        FROM public.sales
        WHERE client_request_id = p_client_request_id;

        IF FOUND THEN
            IF v_existing_payload_hash IS NULL THEN
                RAISE EXCEPTION 'Idempotency conflict: Client request ID % exists on a legacy record without a verified payload hash. Request cannot be safely replayed.', p_client_request_id;
            ELSIF v_existing_payload_hash <> v_incoming_payload_hash THEN
                RAISE EXCEPTION 'Idempotency conflict: client_request_id % was already used with a different request payload.', p_client_request_id;
            END IF;

            RETURN (
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
                    'client_request_id', s.client_request_id,
                    'product_id', (SELECT si.product_id FROM public.sale_items si WHERE si.sale_id = s.id LIMIT 1),
                    'quantity', (SELECT COALESCE(SUM(si.quantity), 0) FROM public.sale_items si WHERE si.sale_id = s.id),
                    'sale_items', (
                        SELECT jsonb_agg(jsonb_build_object(
                            'id', si.id,
                            'sale_id', si.sale_id,
                            'product_id', si.product_id,
                            'quantity', si.quantity,
                            'unit_price', si.unit_price,
                            'discount_amount', si.discount_amount,
                            'catalog_price', si.catalog_price,
                            'is_price_override', si.is_price_override,
                            'override_reason', si.override_reason,
                            'created_at', si.created_at
                        ))
                        FROM public.sale_items si
                        WHERE si.sale_id = s.id
                    )
                )
                FROM public.sales s
                WHERE s.id = v_existing_sale_id
            );
        END IF;
    END IF;

    -- 6. Load isolated security policy configuration
    SELECT max_cashier_discount_pct, allow_cashier_price_override
    INTO v_max_cashier_discount_pct, v_allow_cashier_price_override
    FROM public.pos_security_config
    WHERE id = 'default';

    IF v_max_cashier_discount_pct IS NULL THEN
        v_max_cashier_discount_pct := 10.00;
    END IF;
    IF v_allow_cashier_price_override IS NULL THEN
        v_allow_cashier_price_override := false;
    END IF;

    -- 7. Validate line items, enforce pricing rules, and lock/deduct store stock
    FOR v_item IN
        SELECT elem
        FROM jsonb_array_elements(p_items) elem
        ORDER BY (elem ->> 'product_id')::uuid
    LOOP
        v_product_id := (v_item ->> 'product_id')::uuid;
        v_quantity := (v_item ->> 'quantity')::int;
        v_unit_price := COALESCE((v_item ->> 'unit_price')::numeric, 0);
        v_discount := COALESCE((v_item ->> 'discount')::numeric, (v_item ->> 'discount_amount')::numeric, 0);

        IF v_product_id IS NULL THEN
            RAISE EXCEPTION 'Invalid line item: product_id is required.';
        END IF;

        IF v_quantity IS NULL OR v_quantity <= 0 THEN
            RAISE EXCEPTION 'Invalid line item quantity (must be positive integer > 0). Product ID: %', v_product_id;
        END IF;

        IF v_unit_price IS NULL OR v_unit_price <= 0 OR v_unit_price = 'NaN'::numeric THEN
            RAISE EXCEPTION 'Invalid line item unit price (must be positive finite numeric > 0). Product ID: %', v_product_id;
        END IF;

        IF v_discount IS NULL OR v_discount < 0 OR v_discount = 'NaN'::numeric THEN
            RAISE EXCEPTION 'Invalid line item discount (must be non-negative finite numeric >= 0). Product ID: %', v_product_id;
        END IF;

        -- Fetch official catalog price
        SELECT standard_selling_price INTO v_catalog_price
        FROM public.products
        WHERE id = v_product_id AND active = true;

        IF NOT FOUND OR v_catalog_price IS NULL THEN
            RAISE EXCEPTION 'Product with ID % does not exist or is inactive.', v_product_id;
        END IF;

        -- Server-side Cashier Authorization Checks
        IF v_role IN ('neemrana', 'jaipur') THEN
            -- Price Override Check
            IF abs(v_unit_price - v_catalog_price) > 0.001 AND NOT v_allow_cashier_price_override THEN
                RAISE EXCEPTION 'Unauthorized price modification: Cashier role "%" cannot modify catalog price (Catalog: %, Provided: %). Owner authorization required.',
                    v_role, v_catalog_price, v_unit_price;
            END IF;

            -- Discount Percentage Check (gross catalog value = quantity * catalog_price)
            v_item_gross := round(v_quantity * v_catalog_price, 2);
            IF v_discount > 0 AND v_item_gross > 0 THEN
                v_discount_pct := round((v_discount / v_item_gross) * 100.0, 4);
                IF v_discount_pct > v_max_cashier_discount_pct THEN
                    RAISE EXCEPTION 'Unauthorized discount: Cashier discount (% pct) exceeds allowed maximum of % pct. Owner authorization required.',
                        round(v_discount_pct, 1), v_max_cashier_discount_pct;
                END IF;
            END IF;
        END IF;

        IF v_discount > (v_quantity * v_unit_price) THEN
            RAISE EXCEPTION 'Discount cannot exceed line item total. Product ID: %', v_product_id;
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

        -- Exact stock deduction
        UPDATE public.store_inventory
        SET current_quantity = current_quantity - v_quantity,
            updated_at = now()
        WHERE location_id = v_target_location_id AND product_id = v_product_id;

        v_item_total := round((v_quantity * v_unit_price) - v_discount, 2);
        v_calculated_subtotal := v_calculated_subtotal + v_item_total;
    END LOOP;

    -- 8. Calculate invoice amounts
    v_gst_rate := 0.00;
    v_taxable_amount := v_calculated_subtotal;
    v_cgst_amount := 0.00;
    v_sgst_amount := 0.00;
    v_igst_amount := 0.00;
    v_grand_total := v_calculated_subtotal;

    -- 9. Generate unique bill number
    v_bill_number := 'BILL-' || lpad(nextval('public.seq_bill_number')::text, 6, '0');

    -- 10. Insert parent sale record with request token
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
        sold_at,
        client_request_id,
        request_payload_hash
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
        now(),
        p_client_request_id,
        v_incoming_payload_hash
    ) RETURNING id INTO v_sale_id;

    -- 11. Insert sale line items and confidential COGS snapshots
    FOR v_item IN
        SELECT elem
        FROM jsonb_array_elements(p_items) elem
    LOOP
        v_product_id := (v_item ->> 'product_id')::uuid;
        v_quantity := (v_item ->> 'quantity')::int;
        v_unit_price := (v_item ->> 'unit_price')::numeric;
        v_discount := COALESCE((v_item ->> 'discount')::numeric, (v_item ->> 'discount_amount')::numeric, 0);
        v_override_reason := (v_item ->> 'override_reason');

        SELECT standard_selling_price INTO v_catalog_price
        FROM public.products
        WHERE id = v_product_id;

        v_is_override := abs(v_unit_price - v_catalog_price) > 0.001;

        SELECT purchase_cost INTO v_procurement_cost
        FROM public.product_procurement_costs
        WHERE product_id = v_product_id;

        IF v_procurement_cost IS NULL THEN
            v_procurement_cost := 0.00;
        END IF;

        INSERT INTO public.sale_items (
            sale_id,
            product_id,
            quantity,
            unit_price,
            discount_amount,
            catalog_price,
            is_price_override,
            override_reason
        ) VALUES (
            v_sale_id,
            v_product_id,
            v_quantity,
            v_unit_price,
            v_discount,
            v_catalog_price,
            v_is_override,
            CASE WHEN v_is_override THEN COALESCE(v_override_reason, 'PRICE_OVERRIDE') ELSE NULL END
        ) RETURNING id INTO v_sale_item_id;

        INSERT INTO public.sale_item_procurement_costs (
            sale_item_id,
            unit_cost
        ) VALUES (
            v_sale_item_id,
            v_procurement_cost
        );
    END LOOP;

    -- 12. Return completed sale response
    RETURN (
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
            'client_request_id', s.client_request_id,
            'product_id', (SELECT si.product_id FROM public.sale_items si WHERE si.sale_id = s.id LIMIT 1),
            'quantity', (SELECT COALESCE(SUM(si.quantity), 0) FROM public.sale_items si WHERE si.sale_id = s.id),
            'sale_items', (
                SELECT jsonb_agg(jsonb_build_object(
                    'id', si.id,
                    'sale_id', si.sale_id,
                    'product_id', si.product_id,
                    'quantity', si.quantity,
                    'unit_price', si.unit_price,
                    'discount_amount', si.discount_amount,
                    'catalog_price', si.catalog_price,
                    'is_price_override', si.is_price_override,
                    'override_reason', si.override_reason,
                    'created_at', si.created_at
                ))
                FROM public.sale_items si
                WHERE si.sale_id = s.id
            )
        )
        FROM public.sales s
        WHERE s.id = v_sale_id
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_create_pos_sale(
    TEXT, TEXT, TEXT, JSONB, UUID, TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, UUID
) TO authenticated;


-- <<< END MIGRATION: f:\kizuna-veda\supabase\migrations\20261015120000_v1_8_cashier_discount_policy_hardening.sql <<<


-- ==============================================================================
-- FINAL VERIFICATION QUERY BLOCK
-- ==============================================================================
SELECT 
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'products' AND column_name = 'standard_selling_price') as has_v1_5_products,
    (SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'pos_security_config') as has_v1_6_pos_config,
    (SELECT COUNT(*) FROM pg_constraint WHERE conname = 'sale_item_procurement_costs_sale_item_id_fkey') as has_fk_relationship,
    (SELECT COUNT(*) FROM pg_proc WHERE proname = 'fn_create_pos_sale' AND pronargs = 12) as has_12_param_pos_rpc;
