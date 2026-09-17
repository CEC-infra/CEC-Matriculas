-- Funções chamadas pelas páginas públicas (sem login). Rodam como SECURITY DEFINER e só
-- expõem o necessário; o papel anon não tem acesso direto a nenhuma tabela operacional.

-- Formulário público cec.app/matricula.
create or replace function public.pre_matricula_submit(
  p_guardian_name     text,
  p_phone             text,
  p_student_name      text,
  p_target_grade_id   uuid,
  p_whatsapp_consent  boolean,
  p_preferred_shift   public.shift default null,
  p_current_school    text default null,
  p_source            public.enrollment_origin default 'site',
  p_utm               jsonb default null
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_phone       text := public.normalize_phone_br(p_phone);
  v_headers     json := nullif(current_setting('request.headers', true), '')::json;
  v_campaign    uuid;
  v_year        smallint;
  v_guardian    uuid;
  v_student     uuid;
  v_enrollment  uuid;
  v_submission  uuid;
  v_new         boolean := false;
begin
  if p_whatsapp_consent is not true then
    raise exception 'É necessário autorizar o contato pelo WhatsApp' using errcode = '22023';
  end if;
  if v_phone is null then
    raise exception 'Número de WhatsApp inválido' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_guardian_name, ''))) < 3 or length(trim(coalesce(p_student_name, ''))) < 3 then
    raise exception 'Informe o nome do responsável e do aluno' using errcode = '22023';
  end if;
  if p_source is null or p_source not in ('site', 'indicacao', 'instagram', 'outro') then
    p_source := 'site';
  end if;

  select id, academic_year into v_campaign, v_year
  from public.campaigns
  where kind = 'matricula_nova' and status = 'ativa'
    and starts_on <= public.local_today() and (ends_on is null or ends_on >= public.local_today())
  order by starts_on desc
  limit 1;
  if v_campaign is null then
    raise exception 'Não há campanha de matrícula aberta no momento' using errcode = 'P0001';
  end if;

  if not exists (select 1 from public.grades where id = p_target_grade_id and active) then
    raise exception 'Série inválida' using errcode = '22023';
  end if;

  if (select count(*) from public.pre_enrollment_submissions
      where phone = v_phone and created_at > now() - interval '1 day') >= 3 then
    raise exception 'Recebemos vários envios deste número hoje. Aguarde nosso contato.' using errcode = 'P0001';
  end if;

  insert into public.pre_enrollment_submissions
    (campaign_id, guardian_name, phone, student_name, target_grade_id, preferred_shift,
     current_school, whatsapp_consent, source, utm, ip, user_agent)
  values
    (v_campaign, trim(p_guardian_name), v_phone, trim(p_student_name), p_target_grade_id, p_preferred_shift,
     nullif(trim(p_current_school), ''), true, p_source, p_utm,
     nullif(trim(split_part(coalesce(v_headers ->> 'x-forwarded-for', ''), ',', 1)), ''),
     v_headers ->> 'user-agent')
  returning id into v_submission;

  -- Um opt-out anterior é preservado: a equipe decide se retoma o contato.
  insert into public.guardians (full_name, phone, whatsapp_consent_at)
  values (trim(p_guardian_name), v_phone, now())
  on conflict (phone) do update
    set whatsapp_consent_at = coalesce(public.guardians.whatsapp_consent_at, excluded.whatsapp_consent_at)
  returning id into v_guardian;

  select s.id into v_student
  from public.students s
  join public.student_guardians sg on sg.student_id = s.id
  where sg.guardian_id = v_guardian and lower(s.full_name) = lower(trim(p_student_name))
  limit 1;

  if v_student is null then
    insert into public.students (full_name, previous_school)
    values (trim(p_student_name), nullif(trim(p_current_school), ''))
    returning id into v_student;

    insert into public.student_guardians (student_id, guardian_id, is_financial, is_primary_contact)
    values (v_student, v_guardian, true, true);
  end if;

  insert into public.enrollments
    (campaign_id, student_id, guardian_id, origin, target_grade_id, target_shift, status, amount_cents)
  values
    (v_campaign, v_student, v_guardian, p_source, p_target_grade_id, p_preferred_shift, 'pre_matricula',
     (select amount_cents from public.grade_offerings where academic_year = v_year and grade_id = p_target_grade_id))
  on conflict (campaign_id, student_id) do nothing
  returning id into v_enrollment;

  if v_enrollment is null then
    select id into v_enrollment from public.enrollments
    where campaign_id = v_campaign and student_id = v_student;
  else
    v_new := true;
  end if;

  update public.pre_enrollment_submissions set enrollment_id = v_enrollment where id = v_submission;

  insert into public.enrollment_events (enrollment_id, code, title, body, actor)
  values (v_enrollment, 'PRE_ENROLLMENT', 'Pré-matrícula recebida',
          'Formulário público preenchido · origem ' || p_source::text, 'responsavel');

  if v_new then
    insert into public.message_queue (campaign_id, enrollment_id, guardian_id, template_id, attempt_number)
    select v_campaign, v_enrollment, v_guardian, t.id, 1
    from public.message_templates t
    where t.campaign_id = v_campaign and t.attempt_number = 1 and t.active
    on conflict do nothing;
  end if;

  return v_submission;
end $$;

-- Página cec.app/rematricula/{token}: registra a abertura e devolve os dados da jornada.
create or replace function public.rematricula_open(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_link  public.enrollment_links;
  v_e     public.enrollments;
  v_out   jsonb;
begin
  select * into v_link from public.enrollment_links
  where token = p_token and revoked_at is null and expires_at > now();
  if not found then
    raise exception 'Link inválido ou expirado' using errcode = 'P0002';
  end if;

  update public.enrollment_links
     set open_count      = open_count + 1,
         first_opened_at = coalesce(first_opened_at, now()),
         last_opened_at  = now()
   where id = v_link.id;

  select * into v_e from public.enrollments where id = v_link.enrollment_id;

  if v_link.first_opened_at is null then
    insert into public.enrollment_events (enrollment_id, code, title, body, actor, metadata)
    values (v_e.id, 'LINK_OPENED', 'Link aberto', 'Primeira abertura do link individual.', 'responsavel',
            jsonb_build_object('user_agent', nullif(current_setting('request.headers', true), '')::json ->> 'user-agent'));
  end if;

  if coalesce(public.journey_rank(v_e.status) < 4, false) then
    update public.enrollments set status = 'link_aberto' where id = v_e.id;
  end if;

  select jsonb_build_object(
    'enrollment_id',   v_e.id,
    'status',          v_e.status,
    'completed',       v_e.completed_at is not null,
    'campaign',        c.name,
    'academic_year',   c.academic_year,
    'guardian',        jsonb_build_object('name', g.full_name, 'phone', g.phone, 'email', g.email),
    'student',         jsonb_build_object('name', s.full_name),
    'current_class',   fc.name,
    'next_grade',      tg.name,
    'amount_cents',    v_e.amount_cents,
    'discount_pct',    v_e.discount_pct,
    'payment_plan_id', v_e.payment_plan_id,
    'plans', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', p.id, 'name', p.name, 'description', p.description,
               'installments', p.installments, 'discount_pct', p.discount_pct, 'due_dates', p.due_dates,
               'installment_cents', round(v_e.amount_cents * (1 - p.discount_pct / 100) * (1 - v_e.discount_pct / 100) / p.installments)
             ) order by p.sort_order), '[]'::jsonb)
      from public.payment_plans p
      where p.campaign_id = v_e.campaign_id and p.active),
    'documents', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'document_version_id', v.id, 'title', d.title, 'version', v.version,
               'requirement', d.requirement, 'pages', v.pages,
               'status', coalesce(a.status::text, 'pendente')
             ) order by cd.sort_order), '[]'::jsonb)
      from public.campaign_documents cd
      join public.documents d on d.id = cd.document_id
      join public.document_versions v
        on v.document_id = d.id and v.is_current and (v.grade_id is null or v.grade_id = v_e.target_grade_id)
      left join public.document_acceptances a
        on a.enrollment_id = v_e.id and a.document_version_id = v.id
      where cd.campaign_id = v_e.campaign_id)
  ) into v_out
  from public.campaigns c
  join public.guardians g on g.id = v_e.guardian_id
  join public.students s on s.id = v_e.student_id
  join public.grades tg on tg.id = v_e.target_grade_id
  left join public.classes fc on fc.id = v_e.from_class_id
  where c.id = v_e.campaign_id;

  return v_out;
end $$;

-- Etapa "Dados": confirma contato e condição de pagamento.
create or replace function public.rematricula_save(
  p_token            text,
  p_payment_plan_id  uuid,
  p_email            text default null,
  p_phone            text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_enrollment_id  uuid;
  v_e              public.enrollments;
  v_plan           public.payment_plans;
  v_phone          text;
begin
  select l.enrollment_id into v_enrollment_id
  from public.enrollment_links l
  where l.token = p_token and l.revoked_at is null and l.expires_at > now();
  if v_enrollment_id is null then
    raise exception 'Link inválido ou expirado' using errcode = 'P0002';
  end if;

  select * into v_e from public.enrollments where id = v_enrollment_id for update;
  if v_e.completed_at is not null or v_e.status in ('sem_interesse', 'opt_out', 'fora_campanha') then
    raise exception 'Esta matrícula já foi concluída ou encerrada' using errcode = 'P0001';
  end if;

  select * into v_plan from public.payment_plans
  where id = p_payment_plan_id and campaign_id = v_e.campaign_id and active;
  if not found then
    raise exception 'Condição de pagamento inválida' using errcode = '22023';
  end if;

  if nullif(trim(p_phone), '') is not null then
    v_phone := public.normalize_phone_br(p_phone);
    if v_phone is null then
      raise exception 'Telefone inválido' using errcode = '22023';
    end if;
  end if;

  begin
    update public.guardians
       set email = coalesce(nullif(lower(trim(p_email)), ''), email),
           phone = coalesce(v_phone, phone)
     where id = v_e.guardian_id;
  exception
    when unique_violation then
      raise exception 'Este telefone já está cadastrado para outro responsável. Fale com a secretaria.' using errcode = '23505';
    when check_violation then
      raise exception 'E-mail inválido' using errcode = '22023';
  end;

  update public.enrollments
     set payment_plan_id = v_plan.id,
         status = case when coalesce(public.journey_rank(status) < 5, false)
                       then 'formulario_iniciado'::public.journey_status else status end
   where id = v_e.id;

  insert into public.enrollment_events (enrollment_id, code, title, body, actor)
  values (v_e.id, 'FORM_STARTED', 'Dados confirmados pelo responsável', 'Condição escolhida: ' || v_plan.name, 'responsavel');

  return jsonb_build_object('ok', true, 'enrollment_id', v_e.id, 'payment_plan', v_plan.name);
end $$;
