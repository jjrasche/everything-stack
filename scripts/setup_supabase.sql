-- # Supabase Sync Setup
--
-- Minimal schema for SupabaseSyncService to work.
-- Creates entities table for offline-first sync.
--
-- Run this script via Supabase Dashboard SQL Editor or via psql:
--   psql "postgresql://postgres:[PASSWORD]@db.[PROJECT_REF].supabase.co:5432/postgres" -f scripts/setup_supabase.sql

-- Create entities table (generic storage for all entity types)
CREATE TABLE IF NOT EXISTS public.entities (
  uuid TEXT PRIMARY KEY,
  type TEXT NOT NULL,
  data JSONB NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for faster queries by type
CREATE INDEX IF NOT EXISTS idx_entities_type ON public.entities(type);

-- Index for faster queries by update time (sync)
CREATE INDEX IF NOT EXISTS idx_entities_updated_at ON public.entities(updated_at);

-- Enable Row Level Security (RLS)
ALTER TABLE public.entities ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Allow all operations for authenticated users
-- TODO: Tighten this policy based on user_id once auth is implemented
CREATE POLICY "Allow authenticated users full access"
  ON public.entities
  FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- Grant access to authenticated role
GRANT ALL ON public.entities TO authenticated;
GRANT ALL ON public.entities TO service_role;

-- Done!
--
-- Next steps:
-- 1. Add SUPABASE_URL and SUPABASE_ANON_KEY to .env
-- 2. App will automatically use SupabaseSyncService if hasSyncConfig is true
-- 3. Test with: await SyncService.instance.syncAll();
