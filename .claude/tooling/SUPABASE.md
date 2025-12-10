# Supabase CLI Operations

## Overview

This document captures how to interact with Supabase from the command line without using the Supabase Dashboard. Useful for automation, CI/CD, and Claude Code skills.

## Prerequisites

```bash
# .env file with credentials
SUPABASE_URL=https://[PROJECT_REF].supabase.co
SUPABASE_ANON_KEY=eyJ...  # For client operations
SUPABASE_DATABASE_PASSWORD=...  # For direct DB access
SUPABASE_SERVICE_ROLE_KEY=eyJ...  # For admin operations (optional)
```

## Connection Methods

### 1. Direct PostgreSQL Connection (DDL Operations)

Best for: Creating tables, indexes, triggers, RLS policies

```javascript
const { Client } = require('pg');

const client = new Client({
  host: 'db.[PROJECT_REF].supabase.co',
  port: 5432,
  database: 'postgres',
  user: 'postgres',
  password: process.env.SUPABASE_DATABASE_PASSWORD,
  ssl: { rejectUnauthorized: false }
});

await client.connect();
await client.query(sql);
await client.end();
```

**Important:** Use direct connection (port 5432), NOT the pooler (port 6543) for DDL operations.

### 2. Supabase REST API (CRUD Operations)

Best for: Reading/writing data from application code

```dart
// Dart/Flutter
final client = SupabaseClient(supabaseUrl, supabaseAnonKey);
await client.from('entities').insert({...});
await client.from('entities').select().eq('uuid', id);
```

### 3. Supabase Storage API (Blob Operations)

Best for: File uploads/downloads

```dart
await client.storage.from('bucket').uploadBinary(path, bytes);
await client.storage.from('bucket').download(path);
```

## Common Operations

### Execute SQL Script

```javascript
// run_sql.js
const { Client } = require('pg');
const fs = require('fs');

async function runSQL(sqlFile) {
  const sql = fs.readFileSync(sqlFile, 'utf8');
  const client = new Client({
    host: `db.${process.env.SUPABASE_PROJECT_REF}.supabase.co`,
    port: 5432,
    database: 'postgres',
    user: 'postgres',
    password: process.env.SUPABASE_DATABASE_PASSWORD,
    ssl: { rejectUnauthorized: false }
  });

  await client.connect();
  const result = await client.query(sql);
  console.log('Executed:', result.command);
  await client.end();
}
```

### Create Storage Bucket

```javascript
// Buckets are stored in storage.buckets table
const sql = `
  INSERT INTO storage.buckets (id, name, public, file_size_limit)
  VALUES ('my-bucket', 'my-bucket', false, 52428800)
  ON CONFLICT (id) DO NOTHING;
`;
```

### Add Storage RLS Policy

```javascript
const sql = `
  CREATE POLICY "Allow all operations (dev)"
  ON storage.objects
  FOR ALL
  USING (bucket_id = 'my-bucket')
  WITH CHECK (bucket_id = 'my-bucket');
`;
```

### Check Table Exists

```javascript
const sql = `
  SELECT EXISTS (
    SELECT FROM information_schema.tables
    WHERE table_schema = 'public'
    AND table_name = 'entities'
  );
`;
```

### List All Tables

```javascript
const sql = `
  SELECT table_name
  FROM information_schema.tables
  WHERE table_schema = 'public';
`;
```

### List Storage Buckets

```javascript
const sql = `SELECT id, name, public FROM storage.buckets;`;
```

## Schema Patterns

### Generic Entity Table (JSONB)

```sql
CREATE TABLE entities (
    uuid UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type TEXT NOT NULL,
    data JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    owner_id UUID NULL
);

CREATE INDEX idx_entities_type ON entities(type);
CREATE INDEX idx_entities_updated_at ON entities(updated_at);
```

### Blob Metadata Table

```sql
CREATE TABLE blob_metadata (
    uuid UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_uuid UUID REFERENCES entities(uuid) ON DELETE SET NULL,
    storage_path TEXT NOT NULL,
    filename TEXT,
    content_type TEXT,
    size_bytes BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### Auto-Update Timestamp Trigger

```sql
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER entities_updated_at
    BEFORE UPDATE ON entities
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
```

### Permissive RLS Policy (Dev)

```sql
ALTER TABLE entities ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow all (dev)" ON entities
    FOR ALL USING (true) WITH CHECK (true);
```

## Troubleshooting

### "Tenant or user not found"
- Using pooler connection for DDL - switch to direct connection (port 5432)
- Wrong user format - use `postgres` not `postgres.[project_ref]`

### "Could not find table in schema cache"
- Table doesn't exist - run schema SQL first
- Wrong schema - ensure table is in `public` schema

### "invalid input syntax for type uuid"
- Passing non-UUID string to UUID column
- Use proper UUID format: `550e8400-e29b-41d4-a716-446655440000`

### "new row violates row-level security policy"
- RLS enabled but no policy allows the operation
- Add appropriate policy or use service role key

### "Bucket not found"
- Storage bucket doesn't exist
- Create via SQL: `INSERT INTO storage.buckets...`

## Environment Variables

| Variable | Purpose | Where to Find |
|----------|---------|---------------|
| `SUPABASE_URL` | API endpoint | Dashboard → Settings → API |
| `SUPABASE_ANON_KEY` | Public client key | Dashboard → Settings → API |
| `SUPABASE_SERVICE_ROLE_KEY` | Admin key (secret!) | Dashboard → Settings → API |
| `SUPABASE_DATABASE_PASSWORD` | Direct DB access | Dashboard → Settings → Database |
| `SUPABASE_PROJECT_REF` | Project identifier | From URL: `[ref].supabase.co` |

## Quick Reference

```bash
# Extract project ref from URL
echo "https://abc123xyz.supabase.co" | sed 's|https://\(.*\)\.supabase\.co|\1|'

# Test database connection
PGPASSWORD='your-password' psql -h db.abc123xyz.supabase.co -U postgres -d postgres -c "SELECT 1"

# Run SQL file (if psql available)
PGPASSWORD='your-password' psql -h db.abc123xyz.supabase.co -U postgres -d postgres -f schema.sql
```
