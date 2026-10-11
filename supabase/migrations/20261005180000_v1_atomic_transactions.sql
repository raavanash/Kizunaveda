-- Kizuna Veda V1 Atomic Transactions & RLS Hardening Migration
-- 
-- IMPORTANT:
-- 1. This is a NEW additive migration. Existing foundations remain untouched.
-- 2. DO NOT EXECUTE AGAINST PRODUCTION SUPABASE AUTOMATICALLY.
-- 3. Provides atomic RPC functions:
--    - fn_create_pos_sale: Single-transaction POS sale creation & stock check.
--    - fn_confirm_jaipur_receipt: Single-transaction transfer receipt confirmation & validation.
-- 4. Hardens RLS on public.transfers so JAIPUR role must confirm receipts via fn_confirm_jaipur_receipt RPC.

-- ============================================================================
-- 1. BILL NUMBER SEQUENCE
-- ============================================================================
CREATE SEQUENCE IF NOT EXISTS public.seq_bill_number START WITH 10001 INCREMENT BY 1;

-- ============================================================================
-- 2. ATOMIC POS SALE RPC FUNCTION
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_create_pos_sale(
    p_customer_phone TEXT DEFAULT NULL,
    p_items JSONB DEFAULT '[]'::jsonb
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
    v_created_sale JSONB;
BEGIN
    -- 1. Role verification
    v_role := public.get_current_user_role();
    IF v_role NOT IN ('owner', 'jaipur') THEN
        RAISE EXCEPTION 'Unauthorized: Only OWNER or JAIPUR roles can create POS sales.';
    END IF;

    -- 2. Line items payload validation
    IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'POS sale must contain at least one line item.';
    END IF;

    -- 3. Calculate total amount server-side & validate each item
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

    -- 4. Generate unique bill number server-side
    v_bill_number := 'BILL-' || lpad(nextval('public.seq_bill_number')::text, 6, '0');

    -- 5. Insert parent sale header
    INSERT INTO public.sales (
        location_id,
        bill_number,
        customer_phone,
        whatsapp_status,
        total_amount,
        status,
        sold_at
    ) VALUES (
        '22222222-2222-2222-2222-222222222222'::uuid,
        v_bill_number,
        CASE WHEN p_customer_phone IS NOT NULL AND length(trim(p_customer_phone)) > 0 THEN trim(p_customer_phone) ELSE NULL END,
        'NOT_SENT',
        v_total_amount,
        'COMPLETED',
        now()
    )
    RETURNING id INTO v_sale_id;

    -- 6. Insert line items (triggers fn_check_jaipur_sale_stock for stock validation)
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

    -- 7. Build and return created sale payload
    SELECT jsonb_build_object(
        'id', s.id,
        'location_id', s.location_id,
        'bill_number', s.bill_number,
        'customer_phone', s.customer_phone,
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

-- Grant execution privileges on fn_create_pos_sale
GRANT EXECUTE ON FUNCTION public.fn_create_pos_sale TO authenticated;

-- ============================================================================
-- 3. ATOMIC JAIPUR RECEIPT RPC FUNCTION
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
    v_clean_reason TEXT;
BEGIN
    -- 1. Role verification
    v_role := public.get_current_user_role();
    IF v_role NOT IN ('owner', 'jaipur') THEN
        RAISE EXCEPTION 'Unauthorized: Only OWNER or JAIPUR roles can confirm Jaipur receipts.';
    END IF;

    -- 2. Lock the transfer row FOR UPDATE and verify eligibility
    SELECT * INTO v_transfer
    FROM public.transfers
    WHERE id = p_transfer_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Transfer with ID % not found.', p_transfer_id;
    END IF;

    IF v_transfer.from_location_id <> '11111111-1111-1111-1111-111111111111'::uuid OR
       v_transfer.to_location_id <> '22222222-2222-2222-2222-222222222222'::uuid THEN
        RAISE EXCEPTION 'Only Neemrana -> Jaipur dispatches can be confirmed at Jaipur.';
    END IF;

    -- Prevent double confirmation
    IF v_transfer.received_quantity IS NOT NULL OR v_transfer.received_at IS NOT NULL THEN
        RAISE EXCEPTION 'Transfer has already been received/confirmed.';
    END IF;

    -- 3. Validate received quantity bounds
    IF p_received_quantity IS NULL OR p_received_quantity < 0 THEN
        RAISE EXCEPTION 'Received quantity must be non-negative (>= 0).';
    END IF;

    IF p_received_quantity > v_transfer.dispatched_quantity THEN
        RAISE EXCEPTION 'Received quantity (%) cannot exceed dispatched quantity (%).',
            p_received_quantity, v_transfer.dispatched_quantity;
    END IF;

    -- 4. Discrepancy validation
    v_clean_reason := CASE
        WHEN p_discrepancy_reason IS NOT NULL AND length(trim(p_discrepancy_reason)) > 0
        THEN trim(p_discrepancy_reason)
        ELSE NULL
    END;

    IF p_received_quantity <> v_transfer.dispatched_quantity THEN
        IF v_clean_reason IS NULL THEN
            RAISE EXCEPTION 'Discrepancy reason is required when received quantity (%) differs from dispatched quantity (%).',
                p_received_quantity, v_transfer.dispatched_quantity;
        END IF;
    ELSE
        v_clean_reason := NULL;
    END IF;

    -- 5. Atomic update of receipt fields
    UPDATE public.transfers
    SET received_quantity = p_received_quantity,
        received_at = now(),
        discrepancy_reason = v_clean_reason
    WHERE id = p_transfer_id;

    -- 6. Build and return updated transfer object
    SELECT jsonb_build_object(
        'id', t.id,
        'product_id', t.product_id,
        'from_location_id', t.from_location_id,
        'to_location_id', t.to_location_id,
        'dispatched_quantity', t.dispatched_quantity,
        'received_quantity', t.received_quantity,
        'dispatched_at', t.dispatched_at,
        'received_at', t.received_at,
        'discrepancy_reason', t.discrepancy_reason,
        'created_at', t.created_at
    ) INTO v_updated_transfer
    FROM public.transfers t
    WHERE t.id = p_transfer_id;

    RETURN v_updated_transfer;
END;
$$;

-- Grant execution privileges on fn_confirm_jaipur_receipt
GRANT EXECUTE ON FUNCTION public.fn_confirm_jaipur_receipt TO authenticated;

-- ============================================================================
-- 4. RLS DIRECT UPDATE HARDENING
-- ============================================================================
-- Restrict direct transfers UPDATE policy to OWNER only.
-- JAIPUR role must confirm receipts via SECURITY DEFINER function fn_confirm_jaipur_receipt.
DROP POLICY IF EXISTS "transfers_update_policy" ON public.transfers;
CREATE POLICY "transfers_update_policy" ON public.transfers
FOR UPDATE TO authenticated
USING (public.get_current_user_role() = 'owner')
WITH CHECK (public.get_current_user_role() = 'owner');
