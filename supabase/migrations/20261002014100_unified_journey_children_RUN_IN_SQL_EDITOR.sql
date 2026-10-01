-- Rodar no SQL Editor do Supabase (contém DELETE dentro das funções).

create or replace function public.onboarding_select_rematricula_children(p_token text, p_student_ids uuid[])
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_session public.enrollment_onboarding_sessions;
  v_student_id uuid;
  v_target_grade uuid;
  v_enrollment public.enrollments;
  v_is_new boolean;
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
    if not exists (select 1 from public.student_guardians where student_id = v_student_id and guardian_id = v_session.guardian_id) then
      raise exception 'Aluno não pertence a esta família' using errcode = '42501';
    end if;
    select * into v_enrollment from public.enrollments
     where campaign_id = v_session.campaign_id and student_id = v_student_id
     for update;
    if found and v_enrollment.guardian_id <> v_session.guardian_id then
      raise exception 'A rematrícula deste aluno já está vinculada a outro responsável. Fale com a secretaria.' using errcode = 'P0001';
    end if;
    v_is_new := coalesce(v_enrollment.is_new_student, false);

    -- Aluno da base: próxima série pela turma atual. Irmão novo: a série
    -- escolhida ao adicioná-lo já está na matrícula.
    select current_grade.next_grade_id into v_target_grade
      from public.students s
      join public.classes current_class on current_class.id = s.current_class_id
      join public.grades current_grade on current_grade.id = current_class.grade_id
     where s.id = v_student_id;
    if v_is_new or v_target_grade is null then v_target_grade := coalesce(v_enrollment.target_grade_id, v_target_grade); end if;
    if v_target_grade is null then raise exception 'Aluno selecionado não possui série seguinte configurada' using errcode = 'P0001'; end if;

    v_amount := public.enrollment_amount_for_date(v_session.campaign_id, v_target_grade, v_is_new, public.local_today());
    if v_amount is null then raise exception 'A série pretendida não possui valor configurado' using errcode = 'P0001'; end if;
    v_shift := public.automatic_shift_for_grade((select academic_year from public.campaigns where id = v_session.campaign_id), v_target_grade);
    if v_shift is null then raise exception 'A turma desta série precisa ter um único turno configurado pela escola' using errcode = 'P0001'; end if;

    if v_enrollment.id is not null then
      if v_enrollment.signed_at is null and not exists (
        select 1 from public.installments i where i.enrollment_id = v_enrollment.id and i.status <> 'cancelado'
      ) then
        update public.enrollments
           set target_grade_id = v_target_grade, target_shift = v_shift, amount_cents = v_amount,
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
    insert into public.enrollment_onboarding_items(onboarding_session_id, enrollment_id) values (v_session.id, v_enrollment.id);
    v_enrollment := null;
  end loop;

  update public.enrollment_onboarding_sessions
     set status = 'contratos', current_step = 3, last_opened_at = now(),
         context = context - 'values_confirmed_at' - 'payment_choice' - 'plan_choice'
   where id = v_session.id;
  return public.onboarding_open(v_session.token);
end $$;

-- Só remove quem foi adicionado nesta jornada e ainda não assinou. Alunos da
-- base nunca são apagados: a família apenas os desmarca.
create or replace function public.onboarding_remove_added_child(p_token text, p_student_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session public.enrollment_onboarding_sessions; v_enrollment public.enrollments;
begin
  select * into v_session from public.enrollment_onboarding_sessions
   where token = trim(p_token) and flow = 'rematricula' and guardian_id is not null and status not in ('cancelada', 'concluida') for update;
  if not found then raise exception 'Jornada inválida ou expirada' using errcode = 'P0002'; end if;
  if not coalesce(v_session.context -> 'added_students', '[]'::jsonb) ? p_student_id::text then
    raise exception 'Somente alunos adicionados agora podem ser removidos' using errcode = '42501';
  end if;
  select * into v_enrollment from public.enrollments where student_id = p_student_id and campaign_id = v_session.campaign_id for update;
  if found and v_enrollment.signed_at is not null then raise exception 'O contrato deste aluno já foi assinado' using errcode = 'P0001'; end if;
  if found then
    update public.contract_sessions cs set status = 'cancelada'
      from public.contract_session_enrollments cse
     where cse.contract_session_id = cs.id and cse.enrollment_id = v_enrollment.id and cs.status in ('pronta', 'codigo_enviado', 'verificada');
    delete from public.contract_session_enrollments where enrollment_id = v_enrollment.id;
    delete from public.document_acceptances where enrollment_id = v_enrollment.id;
    delete from public.enrollment_onboarding_items where enrollment_id = v_enrollment.id;
    delete from public.enrollments where id = v_enrollment.id;
  end if;
  delete from public.student_guardians where student_id = p_student_id and guardian_id = v_session.guardian_id;
  delete from public.students s where s.id = p_student_id and not exists (select 1 from public.student_guardians sg where sg.student_id = s.id);
  update public.enrollment_onboarding_sessions
     set context = (context - 'values_confirmed_at' - 'plan_choice')
                   || jsonb_build_object('added_students', coalesce(context -> 'added_students', '[]'::jsonb) - p_student_id::text),
         last_opened_at = now()
   where id = v_session.id;
  return public.onboarding_open(v_session.token);
end $$;

revoke all on function public.onboarding_remove_added_child(text, uuid) from public;
grant execute on function public.onboarding_remove_added_child(text, uuid) to anon, authenticated;
