create view public.v_contract_sessions with (security_invoker = true) as
select
  cs.id,
  cs.campaign_id,
  cs.guardian_id,
  cs.status,
  cs.confirmation_email,
  cs.verification_sent_at,
  cs.verification_verified_at,
  cs.first_opened_at,
  cs.last_opened_at,
  cs.open_count,
  cs.signed_at,
  cs.expires_at,
  cs.created_at,
  cs.updated_at,
  g.full_name as guardian_name,
  c.name as campaign_name,
  count(cse.enrollment_id)::integer as students_count
from public.contract_sessions cs
join public.guardians g on g.id = cs.guardian_id
join public.campaigns c on c.id = cs.campaign_id
left join public.contract_session_enrollments cse on cse.contract_session_id = cs.id
group by cs.id, g.full_name, c.name;

revoke all on public.v_contract_sessions from anon;
grant select on public.v_contract_sessions to authenticated;
