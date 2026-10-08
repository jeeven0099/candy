-- Private training export: no email contents, coupon codes, links, or tokens.
select user_id, promotion_id, event_type, created_at, session_id,
  jsonb_build_object(
    'event_sequence', metadata -> 'event_sequence',
    'feature_schema', metadata -> 'feature_schema',
    'preference_features', metadata -> 'preference_features'
  ) as metadata
from public.user_interactions
where created_at >= now() - interval '90 days'
  and event_type in ('deal_saved', 'deal_unsaved', 'not_interested', 'not_interested_undone')
order by created_at, id;
