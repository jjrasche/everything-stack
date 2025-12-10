-- ============================================================
-- Everything Stack - Supabase Schema Setup
-- ============================================================
-- Run this SQL in your Supabase project's SQL Editor.
-- This creates the generic sync infrastructure tables.
--
-- Design philosophy:
-- - Generic entities table with JSONB data (apps customize via type)
-- - Blobs stored in Supabase Storage, only metadata here
-- - Last-write-wins via updated_at timestamp
-- - owner_id ready for future multi-user support
-- ============================================================

-- ============ ENTITIES TABLE ============
-- Generic entity storage with JSONB for flexible schema.
-- Each app defines entity types; structure stored in data column.

CREATE TABLE IF NOT EXISTS entities (
    -- Primary identifier (matches client-side uuid)
    uuid UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Entity type discriminator (e.g., 'Note', 'Task', 'Project')
    -- Indexed for efficient type-specific queries
    type TEXT NOT NULL,

    -- Entity data as JSONB (schema-per-type)
    -- Client serializes entity fields here
    data JSONB NOT NULL DEFAULT '{}',

    -- Timestamps for sync
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Owner ID for future multi-user support
    -- NULL = system/shared entity
    owner_id UUID NULL,

    -- Soft delete support
    deleted_at TIMESTAMPTZ NULL
);

-- Index on type for filtered queries
CREATE INDEX IF NOT EXISTS idx_entities_type ON entities(type);

-- Index on updated_at for sync delta queries
CREATE INDEX IF NOT EXISTS idx_entities_updated_at ON entities(updated_at);

-- Index on owner_id for user-scoped queries
CREATE INDEX IF NOT EXISTS idx_entities_owner_id ON entities(owner_id);

-- Composite index for efficient "my entities of type X" queries
CREATE INDEX IF NOT EXISTS idx_entities_owner_type ON entities(owner_id, type);


-- ============ BLOB METADATA TABLE ============
-- Metadata for blobs stored in Supabase Storage.
-- Actual bytes stored in Storage bucket, not database.

CREATE TABLE IF NOT EXISTS blob_metadata (
    -- Blob identifier (matches client-side blob id)
    uuid UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Reference to owning entity (optional)
    entity_uuid UUID NULL REFERENCES entities(uuid) ON DELETE SET NULL,

    -- Storage path in Supabase Storage bucket
    storage_path TEXT NOT NULL,

    -- Original filename (for display)
    filename TEXT NULL,

    -- MIME type
    content_type TEXT NULL,

    -- File size in bytes
    size_bytes BIGINT NULL,

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Owner for multi-user support
    owner_id UUID NULL
);

-- Index on entity_uuid for "get blobs for entity" queries
CREATE INDEX IF NOT EXISTS idx_blob_metadata_entity ON blob_metadata(entity_uuid);

-- Index on owner_id for user-scoped queries
CREATE INDEX IF NOT EXISTS idx_blob_metadata_owner ON blob_metadata(owner_id);


-- ============ STORAGE BUCKET ============
-- Create storage bucket for blob data.
-- Run in Supabase Dashboard > Storage > Create Bucket or via API.

-- Note: Bucket creation via SQL is not directly supported.
-- Use Supabase Dashboard or API to create:
--   Bucket name: blobs
--   Public: false (private by default)
--   File size limit: 50MB (adjust as needed)


-- ============ ROW LEVEL SECURITY (RLS) ============
-- Enable RLS for future multi-user support.
-- Initially permissive; tighten when auth is implemented.

ALTER TABLE entities ENABLE ROW LEVEL SECURITY;
ALTER TABLE blob_metadata ENABLE ROW LEVEL SECURITY;

-- Permissive policy for development (allows all operations)
-- IMPORTANT: Replace with proper policies before production!

-- Entities: Allow all for now
CREATE POLICY "Allow all entity operations (dev)" ON entities
    FOR ALL
    USING (true)
    WITH CHECK (true);

-- Blob metadata: Allow all for now
CREATE POLICY "Allow all blob_metadata operations (dev)" ON blob_metadata
    FOR ALL
    USING (true)
    WITH CHECK (true);


-- ============ FUNCTIONS ============

-- Function to auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for entities table
DROP TRIGGER IF EXISTS entities_updated_at ON entities;
CREATE TRIGGER entities_updated_at
    BEFORE UPDATE ON entities
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();


-- ============ EXAMPLE: TYPE-SPECIFIC VIEW ============
-- Apps can create views for typed access to entities.
-- This is an example for a 'Note' entity type.

-- CREATE VIEW notes AS
-- SELECT
--     uuid,
--     data->>'title' AS title,
--     data->>'content' AS content,
--     data->'tags' AS tags,
--     (data->>'isPinned')::boolean AS is_pinned,
--     created_at,
--     updated_at,
--     owner_id
-- FROM entities
-- WHERE type = 'Note' AND deleted_at IS NULL;


-- ============ SYNC HELPER QUERIES ============
-- These are example queries for common sync operations.
-- Implement in client code, not as stored procedures.

-- Get entities modified since last sync:
-- SELECT * FROM entities
-- WHERE updated_at > $last_sync_timestamp
-- AND (owner_id = $user_id OR owner_id IS NULL)
-- ORDER BY updated_at ASC;

-- Get entities by type:
-- SELECT * FROM entities
-- WHERE type = $entity_type
-- AND deleted_at IS NULL;

-- Upsert entity (last-write-wins):
-- INSERT INTO entities (uuid, type, data, updated_at, owner_id)
-- VALUES ($uuid, $type, $data, $updated_at, $owner_id)
-- ON CONFLICT (uuid) DO UPDATE SET
--     data = EXCLUDED.data,
--     updated_at = EXCLUDED.updated_at
-- WHERE entities.updated_at < EXCLUDED.updated_at;
