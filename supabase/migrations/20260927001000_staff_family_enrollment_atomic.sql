-- Cadastro manual de família em uma única transação. O painel chama somente
-- esta RPC: se qualquer validação ou inserção falhar, nada é persistido.

create or replace function public.staff_create_family_enrollment(
  p_guardian_cpf text,
  p_guardian_name text,
  p_guardian_phone text,
  p_guardian_email text,
  p_guardian_address text,
  p_student_name text,
  p_target_grade_id uuid,
  p_target_shift public.shift,
  p_student_birth_date date default null,
  p_current_school text default null,
  p_source public.enrollment_origin default 'outro',
  p_relationship text default null,
  p_guardian_notes text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_cpf text := regexp_replace(coalesce(p_guardian_cpf, ''), '\\D', '', 'g');
  v_phone text := public.normalize_phone_br(p_guardian_phone);
  v_campaign public.campaigns;
  v_offering public.grade_offerings;
  v_guardian_by_cpf uuid;
  v_guardian_by_phone uuid;
  v_guardian_id uuid;
  v_student_id uuid;
  v_enrollment_id uuid;
begin
  if not public.is_staff() then
    raise exception 'Apenas a equipe pode cadastrar famílias' using errcode = '42501';
  end if;
  if v_cpf !~ '^[0-9]{11}$' then
    raise exception 'Informe um CPF válido com 11 dígitos' using errcode = '22023';
  end if;
  if v_phone is null then
    raise exception 'Informe um WhatsApp válido' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_guardian_name, ''))) < 3
     or length(trim(coalesce(p_student_name, ''))) < 3 then
    raise exception 'Informe o nome completo do responsável e do aluno' using errcode = '22023';
  end if;
  if nullif(trim(coalesce(p_guardian_email, '')), '') is null then
    raise exception 'Informe o e-mail do responsável' using errcode = '22023';
  end if;
  if nullif(trim(coalesce(p_guardian_address, '')), '') is null then
    raise exception 'Informe o endereço do responsável' using errcode = '22023';
  end if;
  if p_target_grade_id is null or p_target_shift is null then
    raise exception 'Informe a série pretendida e o turno' using errcode = '22023';
  end if;

  select * into v_campaign
    from public.campaigns
   where kind = 'matricula_nova' and status = 'ativa'
     and starts_on <= public.local_today()
     and (ends_on is null or ends_on >= public.local_today())
   order by starts_on desc
   limit 1;
  if not found then
    raise exception 'Não há campanha de matrícula nova ativa no momento' using errcode = 'P0001';
  end if;

  select * into v_offering
    from public.grade_offerings
   where academic_year = v_campaign.academic_year and grade_id = p_target_grade_id;
  if not found or not p_target_shift = any(v_offering.shifts) then
    raise exception 'A série ou o turno não está disponível nesta campanha' using errcode = '22023';
  end if;
  if p_source is null or p_source not in ('indicacao', 'instagram', 'visita_presencial', 'telefone', 'whatsapp', 'outro') then
    p_source := 'outro';
  end if;

  -- CPF e WhatsApp são chaves de identificação. Se apontarem para pessoas
  -- diferentes, interrompe para a secretaria resolver o cadastro com segurança.
  select id into v_guardian_by_cpf from public.guardians where cpf = v_cpf for update;
  select id into v_guardian_by_phone from public.guardians where phone = v_phone for update;
  if v_guardian_by_cpf is not null and v_guardian_by_phone is not null
     and v_guardian_by_cpf <> v_guardian_by_phone then
    raise exception 'O CPF e o WhatsApp já pertencem a responsáveis diferentes. Revise os dados antes de continuar.' using errcode = '23505';
  end if;
  v_guardian_id := coalesce(v_guardian_by_cpf, v_guardian_by_phone);

  if v_guardian_id is null then
    insert into public.guardians (cpf, full_name, phone, email, address, whatsapp_consent_at, notes)
    values (v_cpf, trim(p_guardian_name), v_phone, lower(trim(p_guardian_email)), trim(p_guardian_address), now(), nullif(trim(p_guardian_notes), ''))
    returning id into v_guardian_id;
  else
    update public.guardians
       set cpf = v_cpf,
           full_name = trim(p_guardian_name),
           phone = v_phone,
           email = lower(trim(p_guardian_email)),
           address = trim(p_guardian_address),
           whatsapp_consent_at = coalesce(whatsapp_consent_at, now()),
           notes = coalesce(nullif(trim(p_guardian_notes), ''), notes)
     where id = v_guardian_id;
  end if;

  -- A mesma criança associada ao responsável é reaproveitada, em vez de gerar
  -- uma duplicata. O vínculo permite que um responsável tenha vários filhos.
  select s.id into v_student_id
    from public.students s
    join public.student_guardians sg on sg.student_id = s.id
   where sg.guardian_id = v_guardian_id
     and lower(trim(s.full_name)) = lower(trim(p_student_name))
   order by s.created_at
   limit 1
   for update of s;

  if v_student_id is not null and exists (
    select 1 from public.enrollments
     where campaign_id = v_campaign.id and student_id = v_student_id
  ) then
    raise exception 'Este aluno já possui uma matrícula nesta campanha. Nenhum dado foi alterado.' using errcode = '23505';
  end if;

  if v_student_id is null then
    insert into public.students (full_name, birth_date, previous_school)
    values (trim(p_student_name), p_student_birth_date, nullif(trim(p_current_school), ''))
    returning id into v_student_id;

    insert into public.student_guardians (student_id, guardian_id, relationship, is_financial, is_primary_contact)
    values (v_student_id, v_guardian_id, nullif(trim(p_relationship), ''), true, true);
  else
    update public.students
       set birth_date = coalesce(p_student_birth_date, birth_date),
           previous_school = coalesce(nullif(trim(p_current_school), ''), previous_school)
     where id = v_student_id;
  end if;

  insert into public.enrollments (
    campaign_id, student_id, guardian_id, origin, target_grade_id, target_shift, status, amount_cents, created_by
  ) values (
    v_campaign.id, v_student_id, v_guardian_id, p_source, p_target_grade_id, p_target_shift, 'em_fila', v_offering.amount_cents, public.current_profile_id()
  ) returning id into v_enrollment_id;

  insert into public.enrollment_events (enrollment_id, code, title, body, actor, actor_id)
  values (v_enrollment_id, 'STAFF_CREATED', 'Cadastro criado pela equipe',
          'Família cadastrada manualmente e adicionada à esteira de atendimento.', 'equipe', public.current_profile_id());

  -- Mantém a régua existente: o worker encontrará a primeira mensagem quando
  -- estiver configurado, sem duplicar uma tentativa pendente.
  insert into public.message_queue (campaign_id, enrollment_id, guardian_id, template_id, attempt_number)
  select v_campaign.id, v_enrollment_id, v_guardian_id, t.id, 1
    from public.message_templates t
   where t.campaign_id = v_campaign.id and t.attempt_number = 1 and t.active
  on conflict do nothing;

  return jsonb_build_object('id', v_enrollment_id, 'guardian_id', v_guardian_id, 'student_id', v_student_id);
end $$;

revoke execute on function public.staff_create_family_enrollment(text, text, text, text, text, text, uuid, public.shift, date, text, public.enrollment_origin, text, text) from public, anon, authenticated;
grant execute on function public.staff_create_family_enrollment(text, text, text, text, text, text, uuid, public.shift, date, text, public.enrollment_origin, text, text) to authenticated;
