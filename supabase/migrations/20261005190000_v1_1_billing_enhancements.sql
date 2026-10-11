-- Kizuna Veda V1.1 Jaipur Retail Invoice & Billing Enhancements Migration
-- 
-- IMPORTANT:
-- 1. This is a NEW additive migration. Existing foundation & atomic RPC migrations remain untouched.
-- 2. DO NOT EXECUTE AGAINST PRODUCTION SUPABASE AUTOMATICALLY.
-- 3. Drops all legacy overloaded signatures of fn_create_pos_sale to prevent RPC resolution ambiguity.
-- 4. Deterministically backfills historical sales with customer_name ('Walk-in Customer') and payment_method ('CASH').
-- 5. Enforces NOT NULL constraints and payment_method IN ('CASH', 'UPI') check constraint.
-- 6. Defines single authoritative atomic V1.1 fn_create_pos_sale(TEXT, TEXT, TEXT, JSONB) requiring customer_name, customer_phone, payment_method, and items.
-- 7. Hardcodes fixed Jaipur location ID ('22222222-2222-2222-2222-222222222222') for POS sales; does not accept location_id from client.
-- 8. Preserves bill_number sequence, RLS policies, SECURITY DEFINER, search_path = public, and stock validation triggers.

-- ============================================================================
-- 1. CLEANUP LEGACY OVERLOADED RPC SIGNATURES TO PREVENT RESOLUTION AMBIGUITY
-- ============================================================================
DROP FUNCTION IF EXISTS public.fn_create_pos_sale(TEXT, JSONB);
DROP FUNCTION IF EXISTS public.fn_create_pos_sale(TEXT, JSONB, TEXT);
DROP FUNCTION IF EXISTS public.fn_create_pos_sale(TEXT, TEXT, TEXT, JSONB);
DROP FUNCTION IF EXISTS public.fn_create_pos_sale(TEXT, TEXT, TEXT, TEXT, JSONB);

-- ============================================================================
-- 2. ADD COLUMNS & DETERMINISTIC HISTORICAL DATA BACKFILL
-- ============================================================================
ALTER TABLE public.sales
ADD COLUMN IF NOT EXISTS customer_name TEXT NULL,
ADD COLUMN IF NOT EXISTS payment_method TEXT NULL;

-- Backfill existing historical records safely
UPDATE public.sales
SET payment_method = 'CASH'
WHERE payment_method IS NULL;

UPDATE public.sales
SET customer_name = 'Walk-in Customer'
WHERE customer_name IS NULL;

-- Enforce default values & NOT NULL constraints
ALTER TABLE public.sales
ALTER COLUMN payment_method SET DEFAULT 'CASH',
ALTER COLUMN payment_method SET NOT NULL,
ALTER COLUMN customer_name SET DEFAULT 'Walk-in Customer',
ALTER COLUMN customer_name SET NOT NULL;

-- Apply check constraint for allowed payment methods
ALTER TABLE public.sales
DROP CONSTRAINT IF EXISTS chk_payment_method;

ALTER TABLE public.sales
ADD CONSTRAINT chk_payment_method CHECK (payment_method IN ('CASH', 'UPI'));

-- ============================================================================
-- 3. DEFINE SINGLE AUTHORITATIVE V1.1 ATOMIC POS SALE RPC FUNCTION (4 PARAMS)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_create_pos_sale(
    p_customer_name TEXT,
    p_customer_phone TEXT,
    p_payment_method TEXT,
    p_items JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role TEXT;
    v_sale_id UUID;
    v_bill_number TEXT;
    v_total_amount NUMERIC(12, 2) := 0;
    v_item JSONB;
    v_product_id UUID;
    v_quantity INT;
    v_unit_price NUMERIC(12, 2);
    v_item_total NUMERIC(12, 2);
    v_clean_name TEXT;
    v_clean_phone TEXT;
    v_clean_method TEXT;
    v_created_sale JSONB;
    c_jaipur_location_id CONSTANT UUID := '22222222-2222-2222-2222-222222222222'::uuid;
BEGIN
    -- 1. Role verification using app_metadata.role
    v_role := public.get_current_user_role();
    IF v_role NOT IN ('owner', 'jaipur') THEN
        RAISE EXCEPTION 'Unauthorized: Only OWNER or JAIPUR roles can create POS sales.';
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

    -- 3. Line items payload validation
    IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'POS sale must contain at least one line item.';
    END IF;

    -- 4. Calculate total amount server-side & validate each item
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

        -- Verify product exists and is active
        IF NOT EXISTS (SELECT 1 FROM public.products WHERE id = v_product_id AND active = true) THEN
            RAISE EXCEPTION 'Product with ID % does not exist or is inactive.', v_product_id;
        END IF;

        v_item_total := round(v_quantity * v_unit_price, 2);
        v_total_amount := v_total_amount + v_item_total;
    END LOOP;

    -- 5. Generate unique bill number server-side
    v_bill_number := 'BILL-' || lpad(nextval('public.seq_bill_number')::text, 6, '0');

    -- 6. Insert parent sale header with hardcoded Jaipur location ID
    INSERT INTO public.sales (
        location_id,
        bill_number,
        customer_name,
        customer_phone,
        payment_method,
        whatsapp_status,
        total_amount,
        status,
        sold_at
    ) VALUES (
        c_jaipur_location_id,
        v_bill_number,
        v_clean_name,
        v_clean_phone,
        v_clean_method,
        'NOT_SENT',
        v_total_amount,
        'COMPLETED',
        now()
    )
    RETURNING id INTO v_sale_id;

    -- 7. Insert line items (triggers fn_check_jaipur_sale_stock for stock validation)
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

    -- 8. Build and return created sale payload
    SELECT jsonb_build_object(
        'id', s.id,
        'location_id', s.location_id,
        'bill_number', s.bill_number,
        'customer_name', s.customer_name,
        'customer_phone', s.customer_phone,
        'payment_method', s.payment_method,
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
REVOKE ALL ON FUNCTION public.fn_create_pos_sale(TEXT, TEXT, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_create_pos_sale(TEXT, TEXT, TEXT, JSONB) TO authenticated;


