-- Communication events received via webhooks.
-- Edge function inserts rows; desktop app subscribes via Realtime.

create table if not exists comm_events (
  id uuid primary key default gen_random_uuid(),
  source_type text not null,
  source_id text not null,
  channel_id text,
  channel_name text,
  sender_id text,
  sender_name text,
  content_text text not null,
  content_type text not null default 'message',
  raw_payload jsonb,
  received_at timestamptz not null default now()
);

-- Index for polling fallback: "give me everything since X"
create index if not exists idx_comm_events_received_at
  on comm_events (received_at desc);

-- Index for source filtering
create index if not exists idx_comm_events_source_type
  on comm_events (source_type);

-- Prevent duplicate ingestion of the same external event
create unique index if not exists idx_comm_events_source_unique
  on comm_events (source_type, source_id);

-- Enable Realtime on this table
alter publication supabase_realtime add table comm_events;
