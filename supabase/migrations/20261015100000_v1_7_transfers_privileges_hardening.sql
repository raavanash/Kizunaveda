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
