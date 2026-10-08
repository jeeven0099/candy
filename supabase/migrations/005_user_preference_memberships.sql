begin;

alter table public.user_preferences
  add column if not exists memberships jsonb not null default '[]'::jsonb;

commit;
