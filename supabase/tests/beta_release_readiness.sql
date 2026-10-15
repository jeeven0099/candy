-- Read-only deployed-schema audit. No user rows or credentials are returned.
with expected(name) as (
  values ('users'), ('user_preferences'), ('saved_deals'),
         ('user_interactions'), ('device_tokens'), ('learned_ranking_model')
)
select e.name as table_name,
       c.oid is not null as table_exists,
       coalesce(c.relrowsecurity, false) as row_security_enabled,
       coalesce((
         select jsonb_agg(jsonb_build_object(
           'name', p.policyname, 'roles', p.roles, 'command', p.cmd,
           'using', p.qual, 'check', p.with_check
         ) order by p.policyname)
         from pg_policies p where p.schemaname = 'public' and p.tablename = e.name
       ), '[]'::jsonb) as policies
from expected e
left join pg_class c on c.relname = e.name and c.relnamespace = 'public'::regnamespace
order by e.name;

select exists (
  select 1 from information_schema.columns
  where table_schema = 'public' and table_name = 'user_preferences' and column_name = 'memberships'
) as memberships_deployed,
exists (
  select 1 from information_schema.columns
  where table_schema = 'public' and table_name = 'user_interactions' and column_name = 'metadata'
) as feedback_snapshot_column_deployed,
case when to_regclass('public.learned_ranking_model') is null then null else
  has_table_privilege('authenticated', 'public.learned_ranking_model', 'INSERT')
  or has_table_privilege('authenticated', 'public.learned_ranking_model', 'UPDATE')
  or has_table_privilege('authenticated', 'public.learned_ranking_model', 'DELETE')
end as client_can_write_learned_model;
