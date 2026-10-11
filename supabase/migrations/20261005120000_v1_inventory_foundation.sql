-- Kizuna Veda Production-Grade V1 Inventory Migration
-- Locations: NEEMRANA (PRODUCTION), JAIPUR (RETAIL)
-- Roles: OWNER, NEEMRANA, JAIPUR (strictly checked via app_metadata.role)
-- Domains: locations, products, raw_materials, raw_material_receipts, packing_records, transfers, sales, sale_items

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- 1. LOCATIONS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.locations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    location_type TEXT NOT NULL,
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_location_type CHECK (location_type IN ('PRODUCTION', 'RETAIL'))
);

-- Seed physical company locations
INSERT INTO public.locations (id, code, name, location_type)
VALUES
    ('11111111-1111-1111-1111-111111111111', 'NEEMRANA', 'Neemrana Production Facility', 'PRODUCTION'),
    ('22222222-2222-2222-2222-222222222222', 'JAIPUR', 'Jaipur Retail Outlet', 'RETAIL')
ON CONFLICT (code) DO NOTHING;

-- ============================================================================
-- 2. PRODUCTS TABLE (Finished product/package SKU variants)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    package_size TEXT NOT NULL,
    sku TEXT UNIQUE NOT NULL,
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 3. RAW MATERIALS DOMAIN (Neemrana operational inventory & cost tracking)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.raw_materials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT UNIQUE NOT NULL,
    unit_of_measure TEXT NOT NULL,
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.raw_material_receipts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    raw_material_id UUID NOT NULL REFERENCES public.raw_materials(id),
    location_id UUID NOT NULL REFERENCES public.locations(id),
    quantity NUMERIC(12, 3) NOT NULL CHECK (quantity > 0),
    unit_cost NUMERIC(12, 2) NOT NULL CHECK (unit_cost >= 0),
    total_cost NUMERIC(12, 2) GENERATED ALWAYS AS (round(quantity * unit_cost, 2)) STORED,
    supplier_reference TEXT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_raw_material_receipt_location CHECK (location_id = '11111111-1111-1111-1111-111111111111'::uuid)
);

-- ============================================================================
-- 4. PACKING_RECORDS TABLE (Neemrana production, raw consumption & wastage)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.packing_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    location_id UUID NOT NULL REFERENCES public.locations(id),
    product_id UUID NOT NULL REFERENCES public.products(id),
    raw_material_id UUID NULL REFERENCES public.raw_materials(id),
    raw_material_consumed NUMERIC(12, 3) NOT NULL DEFAULT 0 CHECK (raw_material_consumed >= 0),
    packed_quantity INTEGER NOT NULL CHECK (packed_quantity > 0),
    wastage_quantity NUMERIC(12, 3) NOT NULL DEFAULT 0 CHECK (wastage_quantity >= 0),
    packed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_packing_location CHECK (location_id = '11111111-1111-1111-1111-111111111111'::uuid)
);

-- ============================================================================
-- 5. TRANSFERS TABLE (Neemrana -> Jaipur inter-facility transfers only)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.transfers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES public.products(id),
    from_location_id UUID NOT NULL REFERENCES public.locations(id),
    to_location_id UUID NOT NULL REFERENCES public.locations(id),
    dispatched_quantity INTEGER NOT NULL CHECK (dispatched_quantity > 0),
    received_quantity INTEGER NULL CHECK (received_quantity >= 0),
    dispatched_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    received_at TIMESTAMPTZ NULL,
    discrepancy_reason TEXT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_transfer_from_location CHECK (from_location_id = '11111111-1111-1111-1111-111111111111'::uuid),
    CONSTRAINT chk_transfer_to_location CHECK (to_location_id = '22222222-2222-2222-2222-222222222222'::uuid),
    CONSTRAINT chk_transfer_receipt_timestamps CHECK (
        (received_quantity IS NULL AND received_at IS NULL) OR
        (received_quantity IS NOT NULL AND received_at IS NOT NULL)
    ),
    CONSTRAINT chk_transfer_received_le_dispatched CHECK (
        received_quantity IS NULL OR received_quantity <= dispatched_quantity
    ),
    CONSTRAINT chk_transfer_discrepancy CHECK (
        received_quantity IS NULL OR (
            (received_quantity <> dispatched_quantity AND discrepancy_reason IS NOT NULL AND length(trim(discrepancy_reason)) > 0) OR
            (received_quantity = dispatched_quantity AND (discrepancy_reason IS NULL OR length(trim(discrepancy_reason)) = 0))
        )
    )
);

-- ============================================================================
-- 6. JAIPUR SALES & BILLING DOMAIN (Parent Retail Sale/Bill & Line Items)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.sales (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    location_id UUID NOT NULL REFERENCES public.locations(id),
    bill_number TEXT UNIQUE NOT NULL,
    customer_phone TEXT NULL,
    whatsapp_status TEXT NOT NULL DEFAULT 'NOT_SENT' CHECK (whatsapp_status IN ('NOT_SENT', 'QUEUED', 'SENT', 'FAILED')),
    total_amount NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    sold_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_sale_location CHECK (location_id = '22222222-2222-2222-2222-222222222222'::uuid)
);

CREATE TABLE IF NOT EXISTS public.sale_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sale_id UUID NOT NULL REFERENCES public.sales(id),
    product_id UUID NOT NULL REFERENCES public.products(id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (unit_price >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- PERFORMANCE INDEXES
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_raw_material_receipts_raw_mat ON public.raw_material_receipts(raw_material_id, location_id);
CREATE INDEX IF NOT EXISTS idx_packing_records_location_product ON public.packing_records(location_id, product_id);
CREATE INDEX IF NOT EXISTS idx_transfers_locations_product ON public.transfers(from_location_id, to_location_id, product_id);
CREATE INDEX IF NOT EXISTS idx_sales_location ON public.sales(location_id, sold_at);
CREATE INDEX IF NOT EXISTS idx_sale_items_sale_product ON public.sale_items(sale_id, product_id);

-- ============================================================================
-- RESTRICT JAIPUR TRANSFER UPDATES TO RECEIPT FIELDS ONLY
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_restrict_jaipur_transfer_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF public.get_current_user_role() = 'jaipur' THEN
        IF NEW.product_id <> OLD.product_id OR
           NEW.from_location_id <> OLD.from_location_id OR
           NEW.to_location_id <> OLD.to_location_id OR
           NEW.dispatched_quantity <> OLD.dispatched_quantity OR
           NEW.dispatched_at <> OLD.dispatched_at THEN
            RAISE EXCEPTION 'Jaipur role can only confirm receipt fields (received_quantity, received_at, discrepancy_reason).';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_restrict_jaipur_transfer_update ON public.transfers;
CREATE TRIGGER trg_restrict_jaipur_transfer_update
BEFORE UPDATE ON public.transfers
FOR EACH ROW
EXECUTE FUNCTION public.fn_restrict_jaipur_transfer_update();

-- ============================================================================
-- ABSOLUTE HISTORICAL DELETION PREVENTION (NO BYPASS)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_prevent_historical_deletion()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'Deletion of historical transaction logs is strictly prohibited. Deactivation / archiving is enforced.';
END;
$$;

DROP TRIGGER IF EXISTS trg_no_delete_packing ON public.packing_records;
CREATE TRIGGER trg_no_delete_packing BEFORE DELETE ON public.packing_records FOR EACH STATEMENT EXECUTE FUNCTION public.fn_prevent_historical_deletion();

DROP TRIGGER IF EXISTS trg_no_delete_transfers ON public.transfers;
CREATE TRIGGER trg_no_delete_transfers BEFORE DELETE ON public.transfers FOR EACH STATEMENT EXECUTE FUNCTION public.fn_prevent_historical_deletion();

DROP TRIGGER IF EXISTS trg_no_delete_sales ON public.sales;
CREATE TRIGGER trg_no_delete_sales BEFORE DELETE ON public.sales FOR EACH STATEMENT EXECUTE FUNCTION public.fn_prevent_historical_deletion();

DROP TRIGGER IF EXISTS trg_no_delete_sale_items ON public.sale_items;
CREATE TRIGGER trg_no_delete_sale_items BEFORE DELETE ON public.sale_items FOR EACH STATEMENT EXECUTE FUNCTION public.fn_prevent_historical_deletion();

DROP TRIGGER IF EXISTS trg_no_delete_raw_receipts ON public.raw_material_receipts;
CREATE TRIGGER trg_no_delete_raw_receipts BEFORE DELETE ON public.raw_material_receipts FOR EACH STATEMENT EXECUTE FUNCTION public.fn_prevent_historical_deletion();

-- ============================================================================
-- DATABASE-LEVEL STOCK PROTECTION TRIGGERS (CONCURRENCY SAFE)
-- ============================================================================

-- Trigger 1: Validate Neemrana Raw Material Stock
CREATE OR REPLACE FUNCTION public.fn_check_neemrana_raw_material_stock()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_raw_received NUMERIC(12, 3) := 0;
    v_total_raw_consumed NUMERIC(12, 3) := 0;
    v_available_raw_stock NUMERIC(12, 3) := 0;
    v_requested_consumption NUMERIC(12, 3) := 0;
BEGIN
    IF NEW.raw_material_id IS NULL THEN
        RETURN NEW;
    END IF;

    PERFORM 1 FROM public.raw_materials WHERE id = NEW.raw_material_id FOR UPDATE;

    SELECT COALESCE(SUM(quantity), 0)
    INTO v_total_raw_received
    FROM public.raw_material_receipts
    WHERE raw_material_id = NEW.raw_material_id
      AND location_id = '11111111-1111-1111-1111-111111111111'::uuid;

    SELECT COALESCE(SUM(raw_material_consumed + wastage_quantity), 0)
    INTO v_total_raw_consumed
    FROM public.packing_records
    WHERE raw_material_id = NEW.raw_material_id
      AND location_id = '11111111-1111-1111-1111-111111111111'::uuid
      AND id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid);

    v_available_raw_stock := v_total_raw_received - v_total_raw_consumed;
    v_requested_consumption := NEW.raw_material_consumed + NEW.wastage_quantity;

    IF v_requested_consumption > v_available_raw_stock THEN
        RAISE EXCEPTION 'Raw material consumption (%) exceeds available Neemrana raw material stock (%). Raw Material ID: %',
            v_requested_consumption, v_available_raw_stock, NEW.raw_material_id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_neemrana_raw_material_stock ON public.packing_records;
CREATE TRIGGER trg_check_neemrana_raw_material_stock
BEFORE INSERT OR UPDATE OF raw_material_id, raw_material_consumed, wastage_quantity
ON public.packing_records
FOR EACH ROW
EXECUTE FUNCTION public.fn_check_neemrana_raw_material_stock();

-- Trigger 2: Validate Neemrana Dispatch Stock (INSERT & UPDATE)
CREATE OR REPLACE FUNCTION public.fn_check_neemrana_dispatch_stock()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_packed INT := 0;
    v_total_dispatched INT := 0;
    v_available_stock INT := 0;
BEGIN
    PERFORM 1 FROM public.products WHERE id = NEW.product_id FOR UPDATE;

    SELECT COALESCE(SUM(packed_quantity), 0)
    INTO v_total_packed
    FROM public.packing_records
    WHERE product_id = NEW.product_id
      AND location_id = '11111111-1111-1111-1111-111111111111'::uuid;

    SELECT COALESCE(SUM(dispatched_quantity), 0)
    INTO v_total_dispatched
    FROM public.transfers
    WHERE product_id = NEW.product_id
      AND from_location_id = '11111111-1111-1111-1111-111111111111'::uuid
      AND id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid);

    v_available_stock := v_total_packed - v_total_dispatched;

    IF NEW.dispatched_quantity > v_available_stock THEN
        RAISE EXCEPTION 'Neemrana dispatch quantity (%) exceeds available finished stock (%). Product ID: %',
            NEW.dispatched_quantity, v_available_stock, NEW.product_id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_neemrana_dispatch_stock ON public.transfers;
CREATE TRIGGER trg_check_neemrana_dispatch_stock
BEFORE INSERT OR UPDATE OF product_id, dispatched_quantity, from_location_id
ON public.transfers
FOR EACH ROW
EXECUTE FUNCTION public.fn_check_neemrana_dispatch_stock();

-- Trigger 3: Validate Jaipur Sale Stock (INSERT & UPDATE on sale_items)
CREATE OR REPLACE FUNCTION public.fn_check_jaipur_sale_stock()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_received INT := 0;
    v_total_sold INT := 0;
    v_available_stock INT := 0;
BEGIN
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
-- STRICT ROLE-AWARE ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_current_user_role()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
    SELECT lower(coalesce(
        auth.jwt() -> 'app_metadata' ->> 'role',
        ''
    ));
$$;

ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.raw_materials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.raw_material_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.packing_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;

-- Drop existing policies safely
DROP POLICY IF EXISTS "locations_select_policy" ON public.locations;
DROP POLICY IF EXISTS "products_select_policy" ON public.products;
DROP POLICY IF EXISTS "products_insert_update_policy" ON public.products;
DROP POLICY IF EXISTS "raw_materials_select_policy" ON public.raw_materials;
DROP POLICY IF EXISTS "raw_materials_insert_update_policy" ON public.raw_materials;
DROP POLICY IF EXISTS "raw_material_receipts_select_policy" ON public.raw_material_receipts;
DROP POLICY IF EXISTS "raw_material_receipts_insert_policy" ON public.raw_material_receipts;
DROP POLICY IF EXISTS "packing_records_select_policy" ON public.packing_records;
DROP POLICY IF EXISTS "packing_records_insert_policy" ON public.packing_records;
DROP POLICY IF EXISTS "transfers_select_policy" ON public.transfers;
DROP POLICY IF EXISTS "transfers_insert_policy" ON public.transfers;
DROP POLICY IF EXISTS "transfers_update_policy" ON public.transfers;
DROP POLICY IF EXISTS "sales_select_policy" ON public.sales;
DROP POLICY IF EXISTS "sales_insert_policy" ON public.sales;
DROP POLICY IF EXISTS "sale_items_select_policy" ON public.sale_items;
DROP POLICY IF EXISTS "sale_items_insert_policy" ON public.sale_items;

-- 1. LOCATIONS (Read-only for recognized roles ONLY)
CREATE POLICY "locations_select_policy" ON public.locations
FOR SELECT TO authenticated
USING (public.get_current_user_role() IN ('owner', 'neemrana', 'jaipur'));

-- 2. PRODUCTS
CREATE POLICY "products_select_policy" ON public.products
FOR SELECT TO authenticated
USING (public.get_current_user_role() IN ('owner', 'neemrana', 'jaipur'));

CREATE POLICY "products_insert_update_policy" ON public.products
FOR ALL TO authenticated
USING (public.get_current_user_role() IN ('owner', 'neemrana'))
WITH CHECK (public.get_current_user_role() IN ('owner', 'neemrana'));

-- 3. RAW MATERIALS & RECEIPTS (Neemrana & Owner ONLY)
CREATE POLICY "raw_materials_select_policy" ON public.raw_materials
FOR SELECT TO authenticated
USING (public.get_current_user_role() IN ('owner', 'neemrana'));

CREATE POLICY "raw_materials_insert_update_policy" ON public.raw_materials
FOR ALL TO authenticated
USING (public.get_current_user_role() IN ('owner', 'neemrana'))
WITH CHECK (public.get_current_user_role() IN ('owner', 'neemrana'));

CREATE POLICY "raw_material_receipts_select_policy" ON public.raw_material_receipts
FOR SELECT TO authenticated
USING (public.get_current_user_role() IN ('owner', 'neemrana'));

CREATE POLICY "raw_material_receipts_insert_policy" ON public.raw_material_receipts
FOR INSERT TO authenticated
WITH CHECK (
    public.get_current_user_role() IN ('owner', 'neemrana')
    AND location_id = '11111111-1111-1111-1111-111111111111'::uuid
);

-- 4. PACKING RECORDS (Neemrana & Owner ONLY)
CREATE POLICY "packing_records_select_policy" ON public.packing_records
FOR SELECT TO authenticated
USING (public.get_current_user_role() IN ('owner', 'neemrana'));

CREATE POLICY "packing_records_insert_policy" ON public.packing_records
FOR INSERT TO authenticated
WITH CHECK (
    public.get_current_user_role() IN ('owner', 'neemrana')
    AND location_id = '11111111-1111-1111-1111-111111111111'::uuid
);

-- 5. TRANSFERS (Neemrana dispatches, Jaipur confirms receipt)
CREATE POLICY "transfers_select_policy" ON public.transfers
FOR SELECT TO authenticated
USING (public.get_current_user_role() IN ('owner', 'neemrana', 'jaipur'));

CREATE POLICY "transfers_insert_policy" ON public.transfers
FOR INSERT TO authenticated
WITH CHECK (
    public.get_current_user_role() IN ('owner', 'neemrana')
    AND from_location_id = '11111111-1111-1111-1111-111111111111'::uuid
    AND to_location_id = '22222222-2222-2222-2222-222222222222'::uuid
);

CREATE POLICY "transfers_update_policy" ON public.transfers
FOR UPDATE TO authenticated
USING (public.get_current_user_role() IN ('owner', 'jaipur'))
WITH CHECK (public.get_current_user_role() IN ('owner', 'jaipur'));

-- 6. SALES & SALE ITEMS (Jaipur & Owner ONLY)
CREATE POLICY "sales_select_policy" ON public.sales
FOR SELECT TO authenticated
USING (public.get_current_user_role() IN ('owner', 'jaipur'));

CREATE POLICY "sales_insert_policy" ON public.sales
FOR INSERT TO authenticated
WITH CHECK (
    public.get_current_user_role() IN ('owner', 'jaipur')
    AND location_id = '22222222-2222-2222-2222-222222222222'::uuid
);

CREATE POLICY "sale_items_select_policy" ON public.sale_items
FOR SELECT TO authenticated
USING (public.get_current_user_role() IN ('owner', 'jaipur'));

CREATE POLICY "sale_items_insert_policy" ON public.sale_items
FOR INSERT TO authenticated
WITH CHECK (public.get_current_user_role() IN ('owner', 'jaipur'));
