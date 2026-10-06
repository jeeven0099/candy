-- Per-user Gmail ingestion and private email deal storage.

begin;

create table if not exists gmail_connections (
  user_id             uuid        primary key references users(id) on delete cascade,
  google_email        text,
  google_subject      text,
  scopes              jsonb       not null default '[]',
  status              text        not null default 'connected',
  connected_at        timestamptz not null default now(),
  disconnected_at     timestamptz,
  last_sync_at        timestamptz,
  last_history_id     text,
  watch_expiration_at timestamptz,
  sync_error          text,
  updated_at          timestamptz not null default now()
);

create table if not exists gmail_connection_tokens (
  user_id                 uuid        primary key references users(id) on delete cascade,
  access_token            text,
  refresh_token           text,
  access_token_expires_at timestamptz,
  token_type              text,
  updated_at              timestamptz not null default now()
);

create table if not exists email_sync_jobs (
  id               uuid        primary key default gen_random_uuid(),
  user_id          uuid        not null references users(id) on delete cascade,
  status           text        not null default 'queued',
  requested_reason text,
  started_at       timestamptz,
  finished_at      timestamptz,
  messages_seen    integer     not null default 0,
  deals_extracted  integer     not null default 0,
  error            text,
  created_at       timestamptz not null default now()
);

create index if not exists email_sync_jobs_user_created
  on email_sync_jobs (user_id, created_at desc);

create table if not exists user_email_deals (
  id                    uuid             primary key default gen_random_uuid(),
  user_id               uuid             not null references users(id) on delete cascade,
  gmail_message_id      text             not null,
  gmail_thread_id       text,
  content_hash          text             not null,
  deal_fingerprint      text             not null,
  brand                 text,
  category              text,
  promotion_title       text,
  sender_email          text,
  email_subject         text,
  email_date            timestamptz,
  visibility            text             not null default 'unknown',
  promotion_json        jsonb            not null default '{}',
  extraction_model      text,
  personal_rank_model   text,
  personal_rank_score   double precision not null default 0,
  personal_rank_reasons jsonb            not null default '[]',
  personal_rank_summary text,
  status                text             not null default 'active',
  expires_at            timestamptz,
  received_at           timestamptz,
  extracted_at          timestamptz      not null default now(),
  created_at            timestamptz      not null default now(),
  updated_at            timestamptz      not null default now(),
  unique (user_id, deal_fingerprint)
);

create index if not exists user_email_deals_user_rank
  on user_email_deals (user_id, status, personal_rank_score desc);

create index if not exists user_email_deals_message
  on user_email_deals (user_id, gmail_message_id);

alter table gmail_connections       enable row level security;
alter table gmail_connection_tokens enable row level security;
alter table email_sync_jobs         enable row level security;
alter table user_email_deals        enable row level security;

create or replace function own_user_id()
returns uuid language sql stable as $$
  select id from users where auth_id = auth.uid() limit 1
$$;

drop policy if exists "gmail_connections_own_select" on gmail_connections;
create policy "gmail_connections_own_select" on gmail_connections
  for select using (user_id = own_user_id());

drop policy if exists "gmail_connections_own_update" on gmail_connections;
create policy "gmail_connections_own_update" on gmail_connections
  for update using (user_id = own_user_id());

drop policy if exists "email_sync_jobs_own_select" on email_sync_jobs;
create policy "email_sync_jobs_own_select" on email_sync_jobs
  for select using (user_id = own_user_id());

drop policy if exists "user_email_deals_own_select" on user_email_deals;
create policy "user_email_deals_own_select" on user_email_deals
  for select using (user_id = own_user_id());

commit;
