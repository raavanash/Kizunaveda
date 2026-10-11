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
