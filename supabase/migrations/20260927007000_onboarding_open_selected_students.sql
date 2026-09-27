-- A jornada de matrícula nova não tem turma atual; os itens já criados devem
-- aparecer no mesmo retorno usado pela rematrícula.
create or replace function public.onboarding_open(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session public.enrollment_onboarding_sessions;
begin
  select * into v_session from public.enrollment_onboarding_sessions where token = p_token and status <> 'cancelada' for update;
  if not found then raise exception 'Jornada inválida ou expirada' using errcode = 'P0002'; end if;
  update public.enrollment_onboarding_sessions set last_opened_at = now() where id = v_session.id;
  return jsonb_build_object(
    'token', v_session.token, 'flow', v_session.flow, 'status', v_session.status, 'step', v_session.current_step,
    'campaign', (select name from public.campaigns where id = v_session.campaign_id),
    'guardian', case when v_session.guardian_id is null then null else (select jsonb_build_object('name', g.full_name, 'email', g.email, 'phone', g.phone) from public.guardians g where g.id = v_session.guardian_id) end,
    'children', coalesce((
      select jsonb_agg(jsonb_build_object(
        'student_id', s.id, 'name', s.full_name, 'current_grade', current_grade.name,
        'target_grade_id', target_grade.id, 'target_grade', target_grade.name,
        'selected', oi.enrollment_id is not null, 'enrollment_id', oi.enrollment_id,
        'contract_token', cs.token, 'contract_status', cs.status, 'signed_at', cs.signed_at
      ) order by s.full_name)
      from public.student_guardians sg
      join public.students s on s.id = sg.student_id
      left join public.classes current_class on current_class.id = s.current_class_id
      left join public.grades current_grade on current_grade.id = current_class.grade_id
      left join lateral (
        select e.* from public.enrollments e where e.campaign_id = v_session.campaign_id and e.student_id = s.id and e.guardian_id = v_session.guardian_id limit 1
      ) enrollment_case on true
      left join public.grades target_grade on target_grade.id = coalesce(enrollment_case.target_grade_id, current_grade.next_grade_id)
      left join public.enrollment_onboarding_items oi on oi.onboarding_session_id = v_session.id and oi.enrollment_id = enrollment_case.id
      left join lateral (
        select cs.* from public.contract_session_enrollments cse join public.contract_sessions cs on cs.id = cse.contract_session_id
         where cse.enrollment_id = oi.enrollment_id and cs.status <> 'cancelada' order by cs.created_at desc limit 1
      ) cs on true
      where sg.guardian_id = v_session.guardian_id and target_grade.id is not null
    ), '[]'::jsonb),
    'payment_options', coalesce((
      select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'description', p.description, 'installments', p.installments, 'discount_pct', p.discount_pct, 'due_dates', p.due_dates) order by p.sort_order)
      from public.payment_plans p where p.campaign_id = v_session.campaign_id and p.active
       and (p.available_until is null or public.local_today() <= p.available_until)
       and not (public.local_today() > '2026-11-20'::date and p.installments <> 2)
    ), '[]'::jsonb)
  );
end $$;
