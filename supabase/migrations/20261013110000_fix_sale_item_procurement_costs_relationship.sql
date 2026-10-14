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
