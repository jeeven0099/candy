-- ============================================================
-- Candy Beta — Supabase schema
-- Run this in: Supabase Dashboard → SQL Editor → Run
-- Safe to re-run: all statements are idempotent.
-- ============================================================

-- ── Invite codes (beta gate) ──────────────────────────────────────────────────

create table if not exists invite_codes (
  code        text primary key,
  max_uses    integer     not null default 1000,
  use_count   integer     not null default 0,
  created_at  timestamptz not null default now()
);

insert into invite_codes (code, max_uses)
values ('CANDY2025', 1000)
on conflict (code) do nothing;

-- ── Users ─────────────────────────────────────────────────────────────────────

create table if not exists users (
  id                              uuid        primary key default gen_random_uuid(),
  auth_id                         uuid        unique references auth.users(id) on delete cascade,
  invite_code                     text        references invite_codes(code),
  email                           text,
  display_name                    text,
  created_at                      timestamptz not null default now(),
  updated_at                      timestamptz not null default now(),
  last_active_at                  timestamptz not null default now(),
  last_login_at                   timestamptz,
  onboarding_completed            boolean     not null default false,
  onboarding_completed_at         timestamptz,
  -- beta_group: personal_test | beta_5 | beta_20 | public
  beta_group                      text        not null default 'personal_test',
  -- Location: lat/lng for distance math, readable fields for debugging
  home_location_lat               double precision,
  home_location_lng               double precision,
  home_city                       text,
  home_state                      text,
  radius_miles                    integer     not null default 5,
  -- Permissions
  location_permission_status      text,
  notification_permission_status  text,
  -- app_platform: web | ios | android
  app_platform                    text
);

-- Upgrade existing users table
alter table users add column if not exists email                           text;
alter table users add column if not exists display_name                    text;
alter table users add column if not exists updated_at                      timestamptz not null default now();
alter table users add column if not exists last_login_at                   timestamptz;
alter table users add column if not exists onboarding_completed            boolean     not null default false;
alter table users add column if not exists onboarding_completed_at         timestamptz;
alter table users add column if not exists beta_group                      text        not null default 'personal_test';
alter table users add column if not exists home_city                       text;
alter table users add column if not exists home_state                      text;
alter table users add column if not exists location_permission_status      text;
alter table users add column if not exists notification_permission_status  text;
alter table users add column if not exists app_platform                    text;

-- ── User preferences ──────────────────────────────────────────────────────────
--
-- favorite_categories / favorite_brands / preferred_contexts: arrays today,
-- will evolve to weighted maps {"food": 1.0, "fashion": 0.7} later.
--
-- hidden_brands example: ["SHEIN", "Wish"]
-- deal_type_preferences example: {"free_item": 1.0, "bogo": 0.9, "points": 0.1}

create table if not exists user_preferences (
  id                    uuid        primary key default gen_random_uuid(),
  user_id               uuid        unique not null references users(id) on delete cascade,
  favorite_categories   jsonb       not null default '[]',
  favorite_brands       jsonb       not null default '[]',
  preferred_contexts    jsonb       not null default '[]',
  hidden_categories     jsonb       not null default '[]',
  hidden_brands         jsonb       not null default '[]',
  deal_type_preferences jsonb       not null default '{}',
  birthday_month        integer,
  birthday_day          integer,
  updated_at            timestamptz not null default now()
);

-- Upgrade existing user_preferences table
alter table user_preferences add column if not exists hidden_categories     jsonb    not null default '[]';
alter table user_preferences add column if not exists hidden_brands         jsonb    not null default '[]';
alter table user_preferences add column if not exists deal_type_preferences jsonb    not null default '{}';
alter table user_preferences add column if not exists birthday_month        integer;
alter table user_preferences add column if not exists birthday_day          integer;

-- ── Saved deals ───────────────────────────────────────────────────────────────
--
-- _snapshot fields preserve what the user saved even if the deal is later
-- removed from the pipeline. used_at records when they redeemed.

create table if not exists saved_deals (
  id                   uuid        primary key default gen_random_uuid(),
  user_id              uuid        not null references users(id) on delete cascade,
  promotion_id         text        not null,
  brand                text,
  title_snapshot       text,
  source_url_snapshot  text,
  saved_at             timestamptz not null default now(),
  remind_at            timestamptz,
  reminder_enabled     boolean     not null default false,
  reminder_sent_at     timestamptz,
  status               text        not null default 'active',
  used_at              timestamptz,
  deleted_at           timestamptz,
  unique (user_id, promotion_id)
);

-- Upgrade existing saved_deals table
alter table saved_deals add column if not exists brand               text;
alter table saved_deals add column if not exists title_snapshot      text;
alter table saved_deals add column if not exists source_url_snapshot text;
alter table saved_deals add column if not exists reminder_enabled    boolean not null default false;
alter table saved_deals add column if not exists reminder_sent_at    timestamptz;
alter table saved_deals add column if not exists used_at             timestamptz;
alter table saved_deals add column if not exists deleted_at          timestamptz;

-- ── Deal impressions ──────────────────────────────────────────────────────────
--
-- Every time a deal card appears in a feed or search result — not just clicks.
-- Drives fatigue: "user saw Starbucks deal 4× without clicking → suppress a week."

create table if not exists deal_impressions (
  id                    uuid             primary key default gen_random_uuid(),
  user_id               uuid             not null references users(id) on delete cascade,
  session_id            text,
  promotion_id          text             not null,
  brand                 text,
  category              text,
  context               text,
  rank_position         integer,
  score_at_impression   double precision,
  shown_at              timestamptz      not null default now()
);

create index if not exists deal_impressions_user_promo
  on deal_impressions (user_id, promotion_id);

-- ── User interactions ─────────────────────────────────────────────────────────
--
-- event_type:
--   feed_impression | deal_card_clicked | brand_result_clicked |
--   saved | unsaved | fast_redeem_clicked | search_submitted |
--   search_no_results | context_chip_changed | reported_wrong |
--   reported_expired | not_interested | notification_opened
--
-- metadata examples:
--   {"search_result_count": 12, "selected_chip": "near_me", "distance_miles": 1.2}

create table if not exists user_interactions (
  id              uuid        primary key default gen_random_uuid(),
  user_id         uuid        not null references users(id) on delete cascade,
  session_id      text,
  event_type      text        not null,
  promotion_id    text,
  brand           text,
  category        text,
  query           text,
  context         text,
  rank_position   integer,
  score_at_event  double precision,
  metadata        jsonb,
  created_at      timestamptz not null default now()
);

-- Upgrade existing user_interactions table
alter table user_interactions add column if not exists session_id     text;
alter table user_interactions add column if not exists rank_position  integer;
alter table user_interactions add column if not exists score_at_event double precision;
alter table user_interactions add column if not exists metadata       jsonb;

-- ── Search events ─────────────────────────────────────────────────────────────
--
-- Separate from user_interactions because search is central to Candy.
-- Query "boba" with 0 results from 10 users → add boba pipeline.
-- Query "Sephora" from 5 users → prioritise Sephora scraping.

create table if not exists search_events (
  id                   uuid        primary key default gen_random_uuid(),
  user_id              uuid        references users(id) on delete cascade,
  session_id           text,
  query                text        not null,
  normalized_query     text,
  context              text,
  result_count         integer,
  clicked_brand        text,
  clicked_promotion_id text,
  no_result            boolean     not null default false,
  created_at           timestamptz not null default now()
);

-- Fast lookup for "what did people search that returned nothing?"
create index if not exists search_events_no_result
  on search_events (normalized_query)
  where no_result = true;

-- ── Notification history ──────────────────────────────────────────────────────
--
-- status: scheduled | sent | opened | dismissed | cancelled |
--         blocked_by_rate_limit | blocked_by_quiet_hours

create table if not exists notification_history (
  id                uuid        primary key default gen_random_uuid(),
  user_id           uuid        not null references users(id) on delete cascade,
  promotion_id      text,
  brand             text,
  notification_type text,
  score             double precision,
  signals_json      jsonb,
  sent_at           timestamptz not null default now(),
  opened_at         timestamptz,
  dismissed_at      timestamptz,
  status            text        not null default 'sent'
);

-- Upgrade existing notification_history table
alter table notification_history add column if not exists dismissed_at timestamptz;
alter table notification_history add column if not exists status       text not null default 'sent';

-- ── User brand affinity ───────────────────────────────────────────────────────
--
-- Computed summary from interactions. Drives reranking:
-- "Coach searched 3× + clicked 2× → boost Coach and related handbag brands."

create table if not exists user_brand_affinity (
  user_id           uuid             not null references users(id) on delete cascade,
  brand             text             not null,
  views_count       integer          not null default 0,
  clicks_count      integer          not null default 0,
  saves_count       integer          not null default 0,
  fast_redeem_count integer          not null default 0,
  searches_count    integer          not null default 0,
  ignored_count     integer          not null default 0,
  affinity_score    double precision not null default 0,
  updated_at        timestamptz      not null default now(),
  primary key (user_id, brand)
);

-- ── User category affinity ────────────────────────────────────────────────────
--
-- Useful when user likes "food" broadly but hasn't picked specific brands yet.

create table if not exists user_category_affinity (
  user_id        uuid             not null references users(id) on delete cascade,
  category       text             not null,
  views_count    integer          not null default 0,
  clicks_count   integer          not null default 0,
  saves_count    integer          not null default 0,
  searches_count integer          not null default 0,
  ignored_count  integer          not null default 0,
  affinity_score double precision not null default 0,
  updated_at     timestamptz      not null default now(),
  primary key (user_id, category)
);

-- ── Row Level Security ────────────────────────────────────────────────────────

alter table invite_codes           enable row level security;
alter table users                  enable row level security;
alter table user_preferences       enable row level security;
alter table saved_deals            enable row level security;
alter table deal_impressions       enable row level security;
alter table user_interactions      enable row level security;
alter table search_events          enable row level security;
alter table notification_history   enable row level security;
alter table user_brand_affinity    enable row level security;
alter table user_category_affinity enable row level security;

-- Invite codes: anyone can read (needed before auth during sign-up)
drop policy if exists "invite_codes_select" on invite_codes;
create policy "invite_codes_select" on invite_codes
  for select using (true);

drop policy if exists "invite_codes_update" on invite_codes;
create policy "invite_codes_update" on invite_codes
  for update using (auth.uid() is not null);

-- Users: only own row
drop policy if exists "users_own" on users;
create policy "users_own" on users
  for all using (auth.uid() = auth_id);

-- Helper: resolve auth_id → users.id (used by all other policies)
create or replace function own_user_id()
returns uuid language sql stable as $$
  select id from users where auth_id = auth.uid() limit 1
$$;

drop policy if exists "prefs_own" on user_preferences;
create policy "prefs_own" on user_preferences
  for all using (user_id = own_user_id());

drop policy if exists "saved_own" on saved_deals;
create policy "saved_own" on saved_deals
  for all using (user_id = own_user_id());

drop policy if exists "impressions_own" on deal_impressions;
create policy "impressions_own" on deal_impressions
  for all using (user_id = own_user_id());

drop policy if exists "interactions_own" on user_interactions;
create policy "interactions_own" on user_interactions
  for all using (user_id = own_user_id());

drop policy if exists "search_events_own" on search_events;
create policy "search_events_own" on search_events
  for all using (user_id = own_user_id());

drop policy if exists "notifications_own" on notification_history;
create policy "notifications_own" on notification_history
  for all using (user_id = own_user_id());

drop policy if exists "brand_affinity_own" on user_brand_affinity;
create policy "brand_affinity_own" on user_brand_affinity
  for all using (user_id = own_user_id());

drop policy if exists "category_affinity_own" on user_category_affinity;
create policy "category_affinity_own" on user_category_affinity
  for all using (user_id = own_user_id());

-- ── Affinity increment RPCs ───────────────────────────────────────────────────
--
-- Called from Flutter after each interaction. Atomic upsert-with-increment
-- so concurrent writes never lose a count. Weights mirror feed_ranker.dart.

create or replace function increment_brand_affinity(
  p_user_id      uuid,
  p_brand        text,
  p_views        int default 0,
  p_clicks       int default 0,
  p_saves        int default 0,
  p_fast_redeems int default 0,
  p_searches     int default 0,
  p_ignored      int default 0
) returns void language plpgsql security invoker as $$
begin
  insert into user_brand_affinity
    (user_id, brand, views_count, clicks_count, saves_count,
     fast_redeem_count, searches_count, ignored_count, affinity_score, updated_at)
  values
    (p_user_id, p_brand, p_views, p_clicks, p_saves,
     p_fast_redeems, p_searches, p_ignored, 0, now())
  on conflict (user_id, brand) do update set
    views_count       = user_brand_affinity.views_count       + excluded.views_count,
    clicks_count      = user_brand_affinity.clicks_count      + excluded.clicks_count,
    saves_count       = user_brand_affinity.saves_count       + excluded.saves_count,
    fast_redeem_count = user_brand_affinity.fast_redeem_count + excluded.fast_redeem_count,
    searches_count    = user_brand_affinity.searches_count    + excluded.searches_count,
    ignored_count     = user_brand_affinity.ignored_count     + excluded.ignored_count,
    affinity_score    =
        (user_brand_affinity.views_count       + excluded.views_count)       * 1
      + (user_brand_affinity.clicks_count      + excluded.clicks_count)      * 8
      + (user_brand_affinity.saves_count       + excluded.saves_count)       * 30
      + (user_brand_affinity.fast_redeem_count + excluded.fast_redeem_count) * 20
      + (user_brand_affinity.searches_count    + excluded.searches_count)    * 18
      - (user_brand_affinity.ignored_count     + excluded.ignored_count)     * 3,
    updated_at        = now();
end;
$$;

create or replace function increment_category_affinity(
  p_user_id  uuid,
  p_category text,
  p_views    int default 0,
  p_clicks   int default 0,
  p_saves    int default 0,
  p_searches int default 0,
  p_ignored  int default 0
) returns void language plpgsql security invoker as $$
begin
  insert into user_category_affinity
    (user_id, category, views_count, clicks_count, saves_count,
     searches_count, ignored_count, affinity_score, updated_at)
  values
    (p_user_id, p_category, p_views, p_clicks, p_saves,
     p_searches, p_ignored, 0, now())
  on conflict (user_id, category) do update set
    views_count    = user_category_affinity.views_count    + excluded.views_count,
    clicks_count   = user_category_affinity.clicks_count   + excluded.clicks_count,
    saves_count    = user_category_affinity.saves_count    + excluded.saves_count,
    searches_count = user_category_affinity.searches_count + excluded.searches_count,
    ignored_count  = user_category_affinity.ignored_count  + excluded.ignored_count,
    affinity_score =
        (user_category_affinity.views_count    + excluded.views_count)    * 1
      + (user_category_affinity.clicks_count   + excluded.clicks_count)   * 8
      + (user_category_affinity.saves_count    + excluded.saves_count)    * 30
      + (user_category_affinity.searches_count + excluded.searches_count) * 18
      - (user_category_affinity.ignored_count  + excluded.ignored_count)  * 3,
    updated_at     = now();
end;
$$;

-- ── Triggers ──────────────────────────────────────────────────────────────────

create or replace function touch_last_active()
returns trigger language plpgsql as $$
begin
  update users set last_active_at = now()
  where auth_id = auth.uid();
  return new;
end
$$;

drop trigger if exists on_interaction_insert on user_interactions;
create trigger on_interaction_insert
  after insert on user_interactions
  for each row execute function touch_last_active();
