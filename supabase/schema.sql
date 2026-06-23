-- ============================================================
-- Candy Beta — Supabase schema
-- Run this in: Supabase Dashboard → SQL Editor → Run
-- ============================================================

-- Invite codes (beta gate)
create table if not exists invite_codes (
  code        text primary key,
  max_uses    integer     not null default 1000,
  use_count   integer     not null default 0,
  created_at  timestamptz not null default now()
);

-- Insert the default beta code (change "CANDY2025" as needed)
insert into invite_codes (code, max_uses)
values ('CANDY2025', 1000)
on conflict (code) do nothing;

-- Users (mirrors auth.users with profile data)
create table if not exists users (
  id                  uuid        primary key default gen_random_uuid(),
  auth_id             uuid        unique references auth.users(id) on delete cascade,
  invite_code         text        references invite_codes(code),
  created_at          timestamptz not null default now(),
  last_active_at      timestamptz not null default now(),
  home_location_lat   double precision,
  home_location_lng   double precision,
  radius_miles        integer     not null default 5
);

-- User preferences (categories + brands as JSON arrays)
create table if not exists user_preferences (
  id                    uuid        primary key default gen_random_uuid(),
  user_id               uuid        unique not null references users(id) on delete cascade,
  favorite_categories   jsonb       not null default '[]',
  favorite_brands       jsonb       not null default '[]',
  preferred_contexts    jsonb       not null default '[]',
  updated_at            timestamptz not null default now()
);

-- Saved deals
create table if not exists saved_deals (
  id            uuid        primary key default gen_random_uuid(),
  user_id       uuid        not null references users(id) on delete cascade,
  promotion_id  text        not null,
  saved_at      timestamptz not null default now(),
  remind_at     timestamptz,
  status        text        not null default 'active',
  unique (user_id, promotion_id)
);

-- User interactions
-- event_type: viewed | clicked | saved | fast_redeem_clicked | dismissed
--             searched | reported_wrong | reported_expired
create table if not exists user_interactions (
  id            uuid        primary key default gen_random_uuid(),
  user_id       uuid        not null references users(id) on delete cascade,
  promotion_id  text,
  event_type    text        not null,
  brand         text,
  category      text,
  query         text,
  context       text,
  created_at    timestamptz not null default now()
);

-- Notification history (for cooldown logic)
create table if not exists notification_history (
  id                uuid        primary key default gen_random_uuid(),
  user_id           uuid        not null references users(id) on delete cascade,
  promotion_id      text,
  brand             text,
  notification_type text,
  sent_at           timestamptz not null default now(),
  opened_at         timestamptz,
  score             double precision,
  signals_json      jsonb
);

-- ── Row Level Security ────────────────────────────────────────────────────────

alter table invite_codes        enable row level security;
alter table users               enable row level security;
alter table user_preferences    enable row level security;
alter table saved_deals         enable row level security;
alter table user_interactions   enable row level security;
alter table notification_history enable row level security;

-- Invite codes: anyone can read (needed during sign-up before auth)
create policy "invite_codes_select" on invite_codes
  for select using (true);

-- Users: only own row
create policy "users_own" on users
  for all using (auth.uid() = auth_id);

-- Helper: resolve auth_id → users.id
create or replace function own_user_id()
returns uuid language sql stable as $$
  select id from users where auth_id = auth.uid() limit 1
$$;

create policy "prefs_own" on user_preferences
  for all using (user_id = own_user_id());

create policy "saved_own" on saved_deals
  for all using (user_id = own_user_id());

create policy "interactions_own" on user_interactions
  for all using (user_id = own_user_id());

create policy "notifications_own" on notification_history
  for all using (user_id = own_user_id());

-- ── Trigger: auto-touch last_active_at ───────────────────────────────────────

create or replace function touch_last_active()
returns trigger language plpgsql as $$
begin
  update users set last_active_at = now()
  where auth_id = auth.uid();
  return new;
end
$$;

create trigger on_interaction_insert
  after insert on user_interactions
  for each row execute function touch_last_active();
