-- O turno vem da única turma ofertada para a série. A família não escolhe
-- manhã/tarde na rematrícula; o banco grava o valor derivado e o contrato
-- usa a mesma fonte de verdade.

create or replace function public.onboarding_select_rematricula_children(p_token text, p_student_ids uuid[])
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_session public.enrollment_onboarding_sessions;
  v_student_id uuid;
  v_target_grade uuid;
  v_enrollment public.enrollments;
  v_amount integer;
  v_shift public.shift;
begin
  select * into v_session from public.enrollment_onboarding_sessions
   where token = trim(p_token) and flow = 'rematricula' and guardian_id is not null and status <> 'cancelada'
   for update;
  if not found then raise exception 'Identifique primeiro o responsável' using errcode = 'P0001'; end if;
  if coalesce(cardinality(p_student_ids), 0) = 0 then raise exception 'Selecione pelo menos um aluno' using errcode = '22023'; end if;

  delete from public.enrollment_onboarding_items where onboarding_session_id = v_session.id;
  foreach v_student_id in array p_student_ids loop
    select current_grade.next_grade_id into v_target_grade
      from public.student_guardians sg
      join public.students s on s.id = sg.student_id
      join public.classes current_class on current_class.id = s.current_class_id
      join public.grades current_grade on current_grade.id = current_class.grade_id
     where sg.student_id = v_student_id and sg.guardian_id = v_session.guardian_id;
    if v_target_grade is null then raise exception 'Aluno selecionado não possui série seguinte configurada' using errcode = 'P0001'; end if;

    v_amount := public.campaign_amount_for_date(v_session.campaign_id, v_target_grade, public.local_today());
    if v_amount is null then raise exception 'A série pretendida não possui valor configurado' using errcode = 'P0001'; end if;
    v_shift := public.automatic_shift_for_grade((select academic_year from public.campaigns where id = v_session.campaign_id), v_target_grade);
    if v_shift is null then raise exception 'A turma desta série precisa ter um único turno configurado pela escola' using errcode = 'P0001'; end if;

    select * into v_enrollment from public.enrollments
     where campaign_id = v_session.campaign_id and student_id = v_student_id
     for update;
    if found and v_enrollment.guardian_id <> v_session.guardian_id then
      raise exception 'A rematrícula deste aluno já está vinculada a outro responsável. Fale com a secretaria.' using errcode = 'P0001';
    elsif found then
      if v_enrollment.signed_at is null and not exists (
        select 1 from public.installments i where i.enrollment_id = v_enrollment.id and i.status <> 'cancelado'
      ) then
        update public.enrollments
           set target_grade_id = v_target_grade,
               target_shift = v_shift,
               amount_cents = v_amount,
               form_started_at = coalesce(form_started_at, now())
         where id = v_enrollment.id
         returning * into v_enrollment;
      end if;
    else
      insert into public.enrollments(
        campaign_id, student_id, guardian_id, origin, from_class_id,
        target_grade_id, target_shift, status, amount_cents, form_started_at
      ) values (
        v_session.campaign_id, v_student_id, v_session.guardian_id, 'site',
        (select current_class_id from public.students where id = v_student_id),
        v_target_grade, v_shift, 'formulario_iniciado', v_amount, now()
      ) returning * into v_enrollment;
    end if;

    delete from public.enrollment_onboarding_items oi
     using public.enrollment_onboarding_sessions previous
     where oi.enrollment_id = v_enrollment.id
       and oi.onboarding_session_id = previous.id
       and previous.guardian_id = v_session.guardian_id;
    insert into public.enrollment_onboarding_items(onboarding_session_id, enrollment_id)
    values (v_session.id, v_enrollment.id);
  end loop;

  update public.enrollment_onboarding_sessions
     set status = 'contratos', current_step = 3, last_opened_at = now()
   where id = v_session.id;
  return public.onboarding_open(v_session.token);
end $$;

revoke execute on function public.onboarding_select_rematricula_children(text, uuid[]) from public;
grant execute on function public.onboarding_select_rematricula_children(text, uuid[]) to anon, authenticated;
