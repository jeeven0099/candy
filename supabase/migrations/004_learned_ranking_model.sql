-- One replaceable beta model, with no user history or email content in it.
create table if not exists public.learned_ranking_model (
  id text primary key check (id = 'beta'),
  version text not null,
  artifact jsonb not null check (
    jsonb_typeof(artifact) = 'object' and octet_length(artifact::text) <= 1048576
  ),
  updated_at timestamptz not null default now()
);

alter table public.learned_ranking_model enable row level security;
revoke all on public.learned_ranking_model from anon, authenticated;
grant select on public.learned_ranking_model to authenticated;
grant all on public.learned_ranking_model to service_role;
drop policy if exists learned_model_read on public.learned_ranking_model;
create policy learned_model_read on public.learned_ranking_model
  for select to authenticated using (true);
