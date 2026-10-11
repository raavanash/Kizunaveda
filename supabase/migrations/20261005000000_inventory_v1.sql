-- Kizuna Veda V1 Inventory Flow Migration Schema
-- Tables: products, packing_records, transfers, sales
-- Security: Row Level Security (RLS) enabled on all tables

-- 1. Products Table
CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    package_size TEXT NOT NULL,
    sku TEXT NOT NULL UNIQUE,
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. Packing Records Table
CREATE TABLE IF NOT EXISTS public.packing_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    packed_quantity INTEGER NOT NULL CHECK (packed_quantity > 0),
    packed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. Transfers Table
CREATE TABLE IF NOT EXISTS public.transfers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    dispatched_quantity INTEGER NOT NULL CHECK (dispatched_quantity > 0),
    received_quantity INTEGER NULL CHECK (received_quantity >= 0),
    dispatched_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    received_at TIMESTAMPTZ NULL,
    discrepancy_reason TEXT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_received_quantity CHECK (received_quantity IS NULL OR received_quantity <= dispatched_quantity),
    CONSTRAINT chk_discrepancy_reason CHECK (
        received_quantity IS NULL 
        OR received_quantity = dispatched_quantity 
        OR (discrepancy_reason IS NOT NULL AND length(trim(discrepancy_reason)) > 0)
    )
);

-- 4. Sales Table
CREATE TABLE IF NOT EXISTS public.sales (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    sold_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index optimizations for analytical aggregation
CREATE INDEX IF NOT EXISTS idx_packing_records_product_id ON public.packing_records(product_id);
CREATE INDEX IF NOT EXISTS idx_transfers_product_id ON public.transfers(product_id);
CREATE INDEX IF NOT EXISTS idx_sales_product_id ON public.sales(product_id);

-- Enable Row Level Security (RLS) on all tables
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.packing_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;

-- Row Level Security (RLS) Policies for Authenticated Users

-- Products Policies
CREATE POLICY "Allow authenticated read products" ON public.products
    FOR SELECT TO authenticated USING (true);

CREATE POLICY "Allow authenticated insert/update products" ON public.products
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Packing Records Policies
CREATE POLICY "Allow authenticated read packing_records" ON public.packing_records
    FOR SELECT TO authenticated USING (true);

CREATE POLICY "Allow authenticated insert packing_records" ON public.packing_records
    FOR INSERT TO authenticated WITH CHECK (true);

-- Transfers Policies
CREATE POLICY "Allow authenticated read transfers" ON public.transfers
    FOR SELECT TO authenticated USING (true);

CREATE POLICY "Allow authenticated insert/update transfers" ON public.transfers
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Sales Policies
CREATE POLICY "Allow authenticated read sales" ON public.sales
    FOR SELECT TO authenticated USING (true);

CREATE POLICY "Allow authenticated insert sales" ON public.sales
    FOR INSERT TO authenticated WITH CHECK (true);
