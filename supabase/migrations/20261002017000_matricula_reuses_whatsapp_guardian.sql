-- Matrícula nova reaproveita o cadastro criado pelo WhatsApp.
--
-- Quem fala primeiro com a IA ganha um responsável só com telefone (sem CPF).
-- Ao preencher a matrícula no site, o responsável era procurado só pelo CPF e
-- um segundo cadastro com o mesmo número era criado: a conversa ficava num e a
-- jornada no outro. Agora, sem cadastro com o CPF, o cadastro do WhatsApp com
-- o mesmo número (e sem CPF) recebe os dados e segue como o responsável.

CREATE OR REPLACE FUNCTION public.onboarding_create_matricula(p_token text, p_guardian_cpf text, p_guardian_name text, p_phone text, p_email text, p_address text, p_children jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_session public.enrollment_onboarding_sessions;
  v_guardian public.guardians;
  v_child jsonb;
  v_student_id uuid;
  v_enrollment_id uuid;
  v_grade_id uuid;
  v_amount integer;
  v_cpf text := regexp_replace(coalesce(p_guardian_cpf, ''), '\D', '', 'g');
  v_phone text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  v_e164 text;
begin
  select * into v_session from public.enrollment_onboarding_sessions
   where token = p_token and flow = 'matricula_nova' and status <> 'cancelada' for update;
  if not found then raise exception 'Jornada inválida ou expirada' using errcode = 'P0002'; end if;
  perform public.onboarding_campaign('matricula_nova');
  if v_cpf !~ '^[0-9]{11}$' then raise exception 'Informe um CPF válido' using errcode = '22023'; end if;
  if nullif(trim(p_guardian_name), '') is null or nullif(trim(p_email), '') is null or nullif(trim(p_address), '') is null then raise exception 'Preencha nome, e-mail e endereço do responsável' using errcode = '22023'; end if;
  if v_phone !~ '^[0-9]{10,13}$' then raise exception 'Informe um WhatsApp válido' using errcode = '22023'; end if;
  v_e164 := '+' || case when left(v_phone, 2) = '55' then v_phone else '55' || v_phone end;
  if jsonb_typeof(p_children) <> 'array' or jsonb_array_length(p_children) = 0 then raise exception 'Informe pelo menos um aluno' using errcode = '22023'; end if;
  select * into v_guardian from public.guardians where cpf = v_cpf for update;
  if not found then
    -- Cadastro aberto pelo WhatsApp: mesmo número, ainda sem CPF.
    select * into v_guardian from public.guardians
     where cpf is null and regexp_replace(coalesce(phone, ''), '\D', '', 'g') = substr(v_e164, 2)
     order by updated_at desc limit 1 for update;
  end if;
  if not found then
    insert into public.guardians(full_name, cpf, phone, email, address, whatsapp_consent_at)
    values(trim(p_guardian_name), v_cpf, v_e164, lower(trim(p_email)), trim(p_address), now()) returning * into v_guardian;
  else
    update public.guardians set full_name = trim(p_guardian_name), cpf = v_cpf, phone = v_e164, email = lower(trim(p_email)), address = trim(p_address),
           whatsapp_consent_at = coalesce(whatsapp_consent_at, now()), updated_at = now()
     where id = v_guardian.id returning * into v_guardian;
  end if;
  delete from public.enrollment_onboarding_items where onboarding_session_id = v_session.id;
  for v_child in select value from jsonb_array_elements(p_children) loop
    v_grade_id := nullif(v_child ->> 'gradeId', '')::uuid;
    if nullif(trim(v_child ->> 'name'), '') is null or v_grade_id is null then raise exception 'Cada aluno precisa de nome completo e série pretendida' using errcode = '22023'; end if;
    select amount_cents into v_amount from public.grade_offerings where academic_year = (select academic_year from public.campaigns where id = v_session.campaign_id) and grade_id = v_grade_id;
    if v_amount is null then raise exception 'Uma das séries escolhidas não está disponível' using errcode = 'P0001'; end if;
    select s.id into v_student_id from public.students s join public.student_guardians sg on sg.student_id = s.id
     where sg.guardian_id = v_guardian.id and lower(s.full_name) = lower(trim(v_child ->> 'name'))
       and (nullif(v_child ->> 'birthDate', '') is null or s.birth_date = (v_child ->> 'birthDate')::date)
     limit 1;
    if v_student_id is null then
      insert into public.students(full_name, birth_date, previous_school)
      values(trim(v_child ->> 'name'), nullif(v_child ->> 'birthDate', '')::date, nullif(trim(v_child ->> 'previousSchool'), '')) returning id into v_student_id;
      insert into public.student_guardians(student_id, guardian_id, relationship, is_financial, is_primary_contact)
      values(v_student_id, v_guardian.id, 'responsável', true, true);
    end if;
    insert into public.enrollments(campaign_id, student_id, guardian_id, origin, target_grade_id, status, amount_cents, form_started_at)
    values(v_session.campaign_id, v_student_id, v_guardian.id, 'site', v_grade_id, 'aguardando_assinatura', v_amount, now())
    on conflict (campaign_id, student_id) do update set guardian_id = excluded.guardian_id, target_grade_id = excluded.target_grade_id, amount_cents = coalesce(public.enrollments.amount_cents, excluded.amount_cents), form_started_at = coalesce(public.enrollments.form_started_at, now())
    returning id into v_enrollment_id;
    insert into public.enrollment_onboarding_items(onboarding_session_id, enrollment_id) values(v_session.id, v_enrollment_id);
  end loop;
  update public.enrollment_onboarding_sessions set guardian_id = v_guardian.id, status = 'contratos', current_step = 3, context = (context - 'values_confirmed_at' - 'plan_choice') || jsonb_build_object('identified_at', now()), last_opened_at = now() where id = v_session.id;
  return public.onboarding_open(p_token);
end $function$;
