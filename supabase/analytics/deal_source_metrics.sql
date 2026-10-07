-- Run in the Supabase SQL editor. Only source-tagged events from the last
-- 30 days are included; cached deals never count as impressions.
with events as (
  select id, user_id, session_id, promotion_id, event_type, created_at,
    coalesce(context, metadata ->> 'ranking_mode') as feed,
    metadata ->> 'source_group' as source_group,
    metadata ->> 'deal_source' as deal_source,
    metadata ->> 'ranking_version' as ranking_version,
    coalesce(case when metadata ->> 'event_sequence' ~ '^[0-9]{1,18}$'
      then (metadata ->> 'event_sequence')::bigint end,
      (extract(epoch from created_at) * 1000000)::bigint) as event_sequence,
    rank_position
  from public.user_interactions
  where created_at >= now() - interval '30 days'
    and metadata ->> 'source_group' in ('email', 'public')
    and metadata ->> 'ranking_version' is not null
), exposures as (
  select distinct on (user_id, session_id, promotion_id, feed, source_group, deal_source, ranking_version)
    *
  from events
  where event_type = 'feed_impression' and feed in ('for_you', 'near_me')
  order by user_id, session_id, promotion_id, feed, source_group, deal_source, ranking_version, created_at
), actions as (
  -- Attribute an action once. Detail actions without a feed inherit the
  -- most recent matching exposure in that user's session.
  select e.event_type, e.created_at, e.event_sequence, e.id, x.id as exposure_id
  from events e
  join lateral (
    select x.id from exposures x
    where x.user_id = e.user_id and x.session_id = e.session_id
      and x.promotion_id = e.promotion_id and x.source_group = e.source_group
      and x.deal_source = e.deal_source
      and x.ranking_version = e.ranking_version
      and (e.feed is null or e.feed = x.feed)
      and (e.feed is not null or x.event_sequence <= e.event_sequence)
    order by x.event_sequence desc limit 1
  ) x on true
  where e.event_type <> 'feed_impression'
), outcomes as (
  select exposure_id,
    bool_or(event_type in ('deal_card_opened', 'deal_card_clicked')) as opened,
    bool_or(event_type = 'deal_saved') as saved,
    bool_or(event_type in ('fast_redeem_clicked', 'redeem_clicked')) as redemption_intent,
    (array_agg(event_type order by event_sequence desc, id desc)
      filter (where event_type in ('not_interested', 'not_interested_undone')))[1]
      = 'not_interested' as dismissed
  from actions group by exposure_id
)
select x.ranking_version, x.feed, x.source_group, x.deal_source,
  case when x.rank_position <= 3 then '1-3'
       when x.rank_position <= 7 then '4-7' else '8-10' end as position_band,
  count(*) as viewed_deals,
  count(distinct x.user_id) as users,
  count(*) filter (where o.opened) as opened_deals,
  count(*) filter (where o.saved) as saved_deals,
  count(*) filter (where o.dismissed) as dismissed_deals,
  count(*) filter (where o.redemption_intent) as redemption_intents,
  round(100.0 * count(*) filter (where o.opened) / nullif(count(*), 0), 1) as open_rate_pct,
  round(100.0 * count(*) filter (where o.saved) / nullif(count(*), 0), 1) as save_rate_pct,
  round(100.0 * count(*) filter (where o.dismissed) / nullif(count(*), 0), 1) as dismiss_rate_pct,
  round(100.0 * count(*) filter (where o.redemption_intent) / nullif(count(*), 0), 1) as redemption_intent_rate_pct
from exposures x left join outcomes o on o.exposure_id = x.id
group by x.ranking_version, x.feed, x.source_group, x.deal_source, position_band
order by x.ranking_version, x.feed, position_band, x.source_group, x.deal_source;

-- Current ingestion yield and reach, including connected users with no
-- qualifying offers. A completed sync's extraction count is not a purchase.
with latest_sync as (
  select distinct on (user_id) user_id, messages_seen, deals_extracted
  from public.email_sync_jobs
  where status = 'completed'
  order by user_id, finished_at desc
), eligible as (
  select user_id, count(*) as deals
  from public.user_email_deals
  where status = 'active' and personal_rank_score >= 70
    and received_at >= now() - interval '14 days'
    and (expires_at is null or expires_at > now())
  group by user_id
)
select count(*) as connected_users,
  count(s.user_id) as users_synced,
  coalesce(sum(s.messages_seen), 0) as messages_in_latest_syncs,
  coalesce(sum(s.deals_extracted), 0) as candidates_in_latest_syncs,
  count(e.user_id) as users_with_eligible_email_deals,
  coalesce(sum(e.deals), 0) as eligible_email_deals
from public.gmail_connections c
left join latest_sync s on s.user_id = c.user_id
left join eligible e on e.user_id = c.user_id
where c.status = 'connected';
