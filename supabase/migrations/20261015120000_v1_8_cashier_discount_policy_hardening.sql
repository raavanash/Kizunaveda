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
