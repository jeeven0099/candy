create table if not exists notification_log (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references users(id) on delete cascade,
  promo_id    text not null,
  sent_at     timestamptz not null default now()
);

create index if not exists notification_log_user_promo
  on notification_log (user_id, promo_id, sent_at);

alter table notification_log enable row level security;
