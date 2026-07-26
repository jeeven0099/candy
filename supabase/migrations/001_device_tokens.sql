-- Run this in Supabase Dashboard → SQL Editor

create table if not exists device_tokens (
  id         uuid        primary key default gen_random_uuid(),
  user_id    uuid        not null references users(id) on delete cascade,
  token      text        not null,
  platform   text        not null default 'ios',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, token)
);

create index if not exists device_tokens_user_id_idx on device_tokens (user_id);

alter table device_tokens enable row level security;

-- Users can only manage their own tokens
create policy "users manage own tokens"
  on device_tokens for all
  using (
    user_id = (select id from users where auth_id = auth.uid())
  )
  with check (
    user_id = (select id from users where auth_id = auth.uid())
  );
