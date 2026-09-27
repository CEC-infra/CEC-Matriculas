-- Permite que a equipe defina, de forma validada, a condição necessária antes
-- de iniciar o contrato. Também expõe o progresso de assinatura à lista usada
-- pelas telas do painel.

create or replace function public.staff_set_enrollment_payment_plan(
  p_enrollment_id uuid,
  p_payment_plan_id uuid
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_enrollment public.enrollments;
  v_plan public.payment_plans;
begin
  if not public.is_staff() then
    raise exception 'Apenas a equipe pode definir a condição de pagamento' using errcode = '42501';
  end if;
  select * into v_enrollment from public.enrollments where id = p_enrollment_id for update;
  if not found or v_enrollment.completed_at is not null or v_enrollment.status in ('sem_interesse', 'opt_out', 'fora_campanha') then
    raise exception 'Matrícula indisponível para definir condição de pagamento' using errcode = 'P0001';
  end if;
  select * into v_plan from public.payment_plans
   where id = p_payment_plan_id and campaign_id = v_enrollment.campaign_id and active;
  if not found then
    raise exception 'Condição de pagamento inválida para esta campanha' using errcode = '22023';
  end if;
  update public.enrollments
     set payment_plan_id = v_plan.id,
         status = case when public.journey_rank(status) < public.journey_rank('formulario_iniciado'::public.journey_status)
                       then 'formulario_iniciado'::public.journey_status else status end
   where id = v_enrollment.id;
  insert into public.enrollment_events (enrollment_id, code, title, body, actor, actor_id)
  values (v_enrollment.id, 'PAYMENT_PLAN_SET', 'Condição de pagamento definida',
          'Condição selecionada pela equipe: ' || v_plan.name, 'equipe', public.current_profile_id());
  return jsonb_build_object('ok', true, 'payment_plan_id', v_plan.id, 'payment_plan_name', v_plan.name);
end $$;

revoke execute on function public.staff_set_enrollment_payment_plan(uuid, uuid) from public, anon, authenticated;
grant execute on function public.staff_set_enrollment_payment_plan(uuid, uuid) to authenticated;

create or replace view public.v_enrollment_list with (security_invoker = true) as
select
  e.id,
  e.campaign_id,
  c.name                                   as campaign_name,
  c.kind                                   as campaign_kind,
  e.status,
  public.journey_status_label(e.status)    as status_label,
  e.origin,
  g.id                                     as guardian_id,
  g.full_name                              as guardian_name,
  g.phone                                  as guardian_phone,
  s.id                                     as student_id,
  s.full_name                              as student_name,
  fc.name                                  as from_class_name,
  tg.name                                  as target_grade_name,
  e.target_shift,
  e.attempts,
  c.max_attempts,
  e.next_action,
  e.next_action_at,
  e.automation_paused,
  e.assigned_to,
  e.amount_cents,
  e.discount_pct,
  pp.name                                  as payment_plan_name,
  pp.installments                          as payment_plan_installments,
  e.created_at,
  e.completed_at,
  e.updated_at,
  g.email                                  as guardian_email,
  e.signed_at,
  e.paid_at
from public.enrollments e
join public.campaigns c  on c.id = e.campaign_id
join public.guardians g  on g.id = e.guardian_id
join public.students s   on s.id = e.student_id
join public.grades tg    on tg.id = e.target_grade_id
left join public.classes fc       on fc.id = e.from_class_id
left join public.payment_plans pp on pp.id = e.payment_plan_id;
