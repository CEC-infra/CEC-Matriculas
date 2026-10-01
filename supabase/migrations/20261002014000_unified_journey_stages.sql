-- Jornada única de matrícula nova e rematrícula, com a etapa derivada dos
-- dados (não de um contador): o link sempre reabre no ponto certo e o agente
-- lê a mesma informação.
--
--   matrícula nova: dados → condicoes → assinatura → cobranca → pagamento → concluida
--   rematrícula:    identificacao → alunos → condicoes → assinatura → cobranca → pagamento → concluida
--
-- condicoes  = quantas vezes e quando pagar (plano), antes do contrato
-- assinatura = todos os contratos pendentes numa sessão só
-- cobranca   = boleto, cartão ou Pix, depois de assinar
-- pagamento  = cobranças geradas no Asaas (links por vencimento)

-- ── Irmão novo adicionado na rematrícula: paga a tabela cheia ─────────────
alter table public.enrollments add column if not exists is_new_student boolean not null default false;
alter table public.guardians add column if not exists asaas_customer_id text;

create or replace function public.enrollment_amount_for_date(
  p_campaign_id uuid, p_grade_id uuid, p_is_new_student boolean, p_reference_date date default public.local_today()
)
returns integer language sql stable security definer set search_path = '' as $$
  select case
    when p_is_new_student then (
      select o.amount_cents from public.grade_offerings o join public.campaigns c on c.academic_year = o.academic_year
       where c.id = p_campaign_id and o.grade_id = p_grade_id)
    else public.campaign_amount_for_date(p_campaign_id, p_grade_id, p_reference_date)
  end
$$;

create or replace function public.assign_current_enrollment_price()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_amount integer;
begin
  if new.signed_at is not null or new.target_grade_id is null then return new; end if;
  v_amount := public.enrollment_amount_for_date(new.campaign_id, new.target_grade_id, coalesce(new.is_new_student, false), public.local_today());
  if v_amount is not null then new.amount_cents := v_amount; end if;
  return new;
end $$;

create or replace function public.lock_enrollment_effective_amount(p_enrollment_id uuid, p_closed_on date default public.local_today())
returns integer language plpgsql security definer set search_path = '' as $$
declare v_enrollment public.enrollments; v_amount integer;
begin
  select * into v_enrollment from public.enrollments where id = p_enrollment_id for update;
  if not found then raise exception 'Matrícula não encontrada' using errcode = 'P0002'; end if;
  if v_enrollment.signed_at is not null
     or exists (select 1 from public.installments i where i.enrollment_id = v_enrollment.id and i.status <> 'cancelado') then
    return v_enrollment.amount_cents;
  end if;
  v_amount := public.enrollment_amount_for_date(v_enrollment.campaign_id, v_enrollment.target_grade_id, v_enrollment.is_new_student, p_closed_on);
  if v_amount is null then raise exception 'A série desta matrícula não possui valor configurado' using errcode = 'P0001'; end if;
  update public.enrollments set amount_cents = v_amount where id = v_enrollment.id;
  return v_amount;
end $$;

-- ── Condições: planos que podem ser escolhidos numa data ──────────────────
create or replace function public.payment_plan_choices(p_campaign_id uuid, p_reference_date date default public.local_today())
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'installments', p.installments, 'payment_plan_id', p.id, 'name', p.name,
           'description', p.description, 'due_dates', p.due_dates
         ) order by p.installments desc), '[]'::jsonb)
    from public.payment_plans p
   where p.campaign_id = p_campaign_id and p.active
     and (p.available_until is null or p_reference_date <= p.available_until)
$$;

-- O plano escolhido vale se ainda estiver disponível no dia da assinatura;
-- senão, a regra padrão por data.
create or replace function public.enrollment_plan_at_closing(p_enrollment_id uuid, p_closed_on date default public.local_today())
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare v_e public.enrollments;
begin
  select * into v_e from public.enrollments where id = p_enrollment_id;
  if not found then raise exception 'Matrícula não encontrada' using errcode = 'P0002'; end if;
  if v_e.payment_plan_id is not null and exists (
    select 1 from public.payment_plans p
     where p.id = v_e.payment_plan_id and p.campaign_id = v_e.campaign_id and p.active
       and (p.available_until is null or p_closed_on <= p.available_until)
  ) then
    return v_e.payment_plan_id;
  end if;
  return public.payment_plan_for_closing(v_e.campaign_id, p_closed_on);
end $$;

create or replace function public.onboarding_choose_plan(p_token text, p_installments smallint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session public.enrollment_onboarding_sessions; v_choice jsonb; v_enrollment record;
begin
  select * into v_session from public.enrollment_onboarding_sessions
   where token = trim(p_token) and guardian_id is not null and status not in ('cancelada', 'concluida') for update;
  if not found then raise exception 'Jornada inválida ou expirada' using errcode = 'P0002'; end if;
  if not exists (select 1 from public.enrollment_onboarding_items where onboarding_session_id = v_session.id) then
    raise exception 'Selecione os alunos antes de escolher as condições' using errcode = 'P0001';
  end if;
  select o into v_choice from jsonb_array_elements(public.payment_plan_choices(v_session.campaign_id, public.local_today())) o
   where (o ->> 'installments')::int = p_installments;
  if v_choice is null then raise exception 'Esta condição de pagamento não está disponível hoje' using errcode = '22023'; end if;

  for v_enrollment in
    select e.id from public.enrollment_onboarding_items oi join public.enrollments e on e.id = oi.enrollment_id
     where oi.onboarding_session_id = v_session.id and e.guardian_id = v_session.guardian_id and e.signed_at is null
       and not exists (select 1 from public.installments i where i.enrollment_id = e.id and i.status <> 'cancelado')
  loop
    update public.enrollments set payment_plan_id = (v_choice ->> 'payment_plan_id')::uuid where id = v_enrollment.id;
    insert into public.enrollment_events(enrollment_id, code, title, body, actor, metadata)
    values (v_enrollment.id, 'PAYMENT_PLAN_CHOSEN', 'Condição de pagamento escolhida',
            'Família escolheu ' || (v_choice ->> 'installments') || 'x antes de assinar.', 'responsavel', v_choice);
  end loop;

  update public.enrollment_onboarding_sessions
     set context = context || jsonb_build_object('plan_choice', v_choice || jsonb_build_object('chosen_at', now()), 'values_confirmed_at', now()),
         last_opened_at = now()
   where id = v_session.id;
  return public.onboarding_open(v_session.token);
end $$;

-- ── Assinatura: sem forma de pagamento ainda (ela vem na cobrança) ────────
create or replace function public.contract_finalize_signed_pdf(
  p_token text, p_signer_full_name text, p_signature_image_data text, p_accepted boolean,
  p_ip text default null, p_user_agent text default null, p_device text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_session public.contract_sessions;
  v_enrollment record;
  v_acceptance public.document_acceptances;
  v_signature_hash text;
  v_ip inet;
  v_effective_amount integer;
  v_plan_id uuid;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'Finalização disponível somente pelo serviço de assinatura' using errcode = '42501'; end if;
  if p_accepted is not true then raise exception 'Confirme a leitura e o aceite do contrato' using errcode = '22023'; end if;
  if nullif(trim(p_signer_full_name), '') is null then raise exception 'Informe o nome de quem assina' using errcode = '22023'; end if;
  if p_signature_image_data is null or p_signature_image_data !~ '^data:image/(png|jpeg);base64,' or length(p_signature_image_data) not between 100 and 500000 then raise exception 'A assinatura desenhada é obrigatória' using errcode = '22023'; end if;
  select * into v_session from public.contract_sessions where token = trim(p_token) for update;
  if not found or v_session.status in ('assinada', 'cancelada', 'expirada') or v_session.expires_at <= now() then raise exception 'Link de contrato inválido ou expirado' using errcode = 'P0002'; end if;
  if v_session.verification_verified_at is null then raise exception 'Confirme o código enviado por e-mail antes de assinar' using errcode = 'P0001'; end if;
  if coalesce((public.contract_required_data(v_session.id) ->> 'ready')::boolean, false) is not true then raise exception 'Conclua os dados obrigatórios antes de assinar' using errcode = 'P0001'; end if;
  begin v_ip := nullif(split_part(coalesce(p_ip, ''), ',', 1), '')::inet; exception when others then v_ip := null; end;
  v_signature_hash := encode(extensions.digest(p_signature_image_data, 'sha256'), 'hex');

  for v_enrollment in select e.* from public.contract_session_enrollments cse join public.enrollments e on e.id = cse.enrollment_id where cse.contract_session_id = v_session.id loop
    v_effective_amount := public.lock_enrollment_effective_amount(v_enrollment.id, public.local_today());
    v_plan_id := public.enrollment_plan_at_closing(v_enrollment.id, public.local_today());
    select * into v_acceptance from public.document_acceptances da
     where da.enrollment_id = v_enrollment.id and da.contract_session_id = v_session.id
       and da.generated_storage_path is not null and da.generated_document_hash is not null
       and da.signed_storage_path is not null and da.signed_document_hash is not null for update;
    if not found then raise exception 'O PDF assinado deste contrato não foi encontrado' using errcode = 'P0001'; end if;
    update public.document_acceptances set status = 'assinado', provider = 'cec_assinatura_interna', signer_full_name = trim(p_signer_full_name), signer_email = v_session.confirmation_email, email_verified_at = v_session.verification_verified_at, signature_image_data = p_signature_image_data, signature_image_sha256 = v_signature_hash, document_hash = v_acceptance.signed_document_hash, completed_at = now(), ip = v_ip, user_agent = p_user_agent, device = p_device, updated_at = now() where id = v_acceptance.id;
    update public.enrollments set payment_plan_id = v_plan_id where id = v_enrollment.id;
    if not exists(select 1 from public.installments where enrollment_id = v_enrollment.id and status <> 'cancelado') then perform public.generate_installments(v_enrollment.id); end if;
    update public.enrollments set signed_at = now(), status = 'aguardando_pagamento' where id = v_enrollment.id;
    insert into public.enrollment_events(enrollment_id, code, title, body, actor, metadata)
    values(v_enrollment.id, 'CONTRACT_SIGNED', 'Contrato assinado', 'PDF individual assinado após confirmação por e-mail.', 'responsavel', jsonb_build_object('contract_session_id', v_session.id, 'signature_sha256', v_signature_hash, 'document_sha256', v_acceptance.signed_document_hash, 'signed_pdf_at', v_acceptance.signed_pdf_at, 'effective_amount_cents', v_effective_amount, 'payment_plan_id', v_plan_id));
  end loop;
  update public.contract_sessions set status = 'assinada', signed_at = now() where id = v_session.id;
  return jsonb_build_object('ok', true, 'signed_at', now());
end $$;

-- ── Cobrança: forma de pagamento depois de assinar ─────────────────────────
create or replace function public.onboarding_choose_billing(p_token text, p_method public.payment_method)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session public.enrollment_onboarding_sessions; v_enrollment record;
begin
  select * into v_session from public.enrollment_onboarding_sessions
   where token = trim(p_token) and guardian_id is not null and status <> 'cancelada' for update;
  if not found then raise exception 'Jornada inválida ou expirada' using errcode = 'P0002'; end if;
  if exists (
    select 1 from public.enrollment_onboarding_items oi join public.enrollments e on e.id = oi.enrollment_id
     where oi.onboarding_session_id = v_session.id and e.signed_at is null
  ) then raise exception 'Assine os contratos antes de escolher a forma de pagamento' using errcode = 'P0001'; end if;
  if exists (
    select 1 from public.enrollment_onboarding_items oi join public.installments i on i.enrollment_id = oi.enrollment_id
     where oi.onboarding_session_id = v_session.id and i.provider_charge_id is not null and i.status <> 'cancelado'
  ) then raise exception 'As cobranças já foram geradas. Use os links de pagamento.' using errcode = 'P0001'; end if;

  for v_enrollment in select oi.enrollment_id id from public.enrollment_onboarding_items oi where oi.onboarding_session_id = v_session.id loop
    update public.enrollments set preferred_payment_method = p_method, status = 'aguardando_pagamento' where id = v_enrollment.id;
    update public.installments set method = p_method where enrollment_id = v_enrollment.id and status = 'pendente';
    insert into public.enrollment_events(enrollment_id, code, title, body, actor, metadata)
    values (v_enrollment.id, 'PAYMENT_CHOICE_CONFIRMED', 'Forma de pagamento escolhida', 'Família escolheu como pagar depois de assinar.', 'responsavel', jsonb_build_object('method', p_method));
  end loop;
  update public.enrollment_onboarding_sessions
     set context = context || jsonb_build_object('billing_method', p_method, 'billing_chosen_at', now()), last_opened_at = now()
   where id = v_session.id;
  return public.onboarding_open(v_session.token);
end $$;

-- ── Rematrícula: marcar/desmarcar alunos da base e adicionar um novo ─────
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

create or replace function public.onboarding_add_child(
  p_token text, p_name text, p_grade_id uuid, p_birth_date date default null, p_previous_school text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_session public.enrollment_onboarding_sessions;
  v_year smallint;
  v_student_id uuid;
  v_shift public.shift;
  v_amount integer;
begin
  select * into v_session from public.enrollment_onboarding_sessions
   where token = trim(p_token) and flow = 'rematricula' and guardian_id is not null and status not in ('cancelada', 'concluida') for update;
  if not found then raise exception 'Jornada inválida ou expirada' using errcode = 'P0002'; end if;
  if nullif(trim(p_name), '') is null or p_grade_id is null then raise exception 'Informe o nome completo e a série do aluno' using errcode = '22023'; end if;
  if p_birth_date is not null and p_birth_date > public.local_today() then raise exception 'A data de nascimento não pode ser no futuro' using errcode = '22023'; end if;
  select academic_year into v_year from public.campaigns where id = v_session.campaign_id;
  v_amount := public.enrollment_amount_for_date(v_session.campaign_id, p_grade_id, true);
  if v_amount is null then raise exception 'Esta série não está disponível para 2027' using errcode = 'P0001'; end if;
  v_shift := public.automatic_shift_for_grade(v_year, p_grade_id);
  if v_shift is null then raise exception 'A turma desta série precisa ter um único turno configurado pela escola' using errcode = 'P0001'; end if;

  insert into public.students(full_name, birth_date, previous_school)
  values (trim(p_name), p_birth_date, nullif(trim(p_previous_school), '')) returning id into v_student_id;
  insert into public.student_guardians(student_id, guardian_id, relationship, is_financial, is_primary_contact)
  values (v_student_id, v_session.guardian_id, 'responsável', true, true);
  insert into public.enrollments(campaign_id, student_id, guardian_id, origin, target_grade_id, target_shift, status, amount_cents, form_started_at, is_new_student)
  values (v_session.campaign_id, v_student_id, v_session.guardian_id, 'site', p_grade_id, v_shift, 'formulario_iniciado', v_amount, now(), true);

  update public.enrollment_onboarding_sessions
     set context = jsonb_set(context, '{added_students}', coalesce(context -> 'added_students', '[]'::jsonb) || to_jsonb(v_student_id::text)),
         last_opened_at = now()
   where id = v_session.id;
  return public.onboarding_open(v_session.token) || jsonb_build_object('added_student_id', v_student_id);
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

-- ── Matrícula nova: RG na primeira página ──────────────────────────────────
create or replace function public.onboarding_set_guardian_rg(p_token text, p_rg text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_session public.enrollment_onboarding_sessions;
begin
  select * into v_session from public.enrollment_onboarding_sessions where token = trim(p_token) and guardian_id is not null and status <> 'cancelada';
  if not found then raise exception 'Jornada inválida ou expirada' using errcode = 'P0002'; end if;
  if nullif(trim(p_rg), '') is null then raise exception 'Informe o RG do responsável' using errcode = '22023'; end if;
  update public.guardians set rg = trim(p_rg) where id = v_session.guardian_id;
end $$;

-- Reenviar os dados da matrícula nova refaz os alunos: as condições voltam a ser escolhidas.
do $$
declare v_def text;
begin
  v_def := pg_get_functiondef('public.onboarding_create_matricula(text,text,text,text,text,text,jsonb)'::regprocedure);
  if position($x$context = context || jsonb_build_object('identified_at', now())$x$ in v_def) > 0 and position('plan_choice' in v_def) = 0 then
    execute replace(v_def,
      $x$context = context || jsonb_build_object('identified_at', now())$x$,
      $x$context = (context - 'values_confirmed_at' - 'plan_choice') || jsonb_build_object('identified_at', now())$x$);
  end if;
end $$;

-- ── Etapa atual (fonte única para a página e o agente) ────────────────────
create or replace function public.onboarding_stage(p_session_id uuid)
returns text language plpgsql stable security definer set search_path = '' as $$
declare v_session public.enrollment_onboarding_sessions; v_items integer; v_unsigned integer; v_open integer; v_paid integer;
begin
  select * into v_session from public.enrollment_onboarding_sessions where id = p_session_id;
  if not found or v_session.status = 'cancelada' then return 'cancelada'; end if;
  if v_session.guardian_id is null then return case when v_session.flow = 'rematricula' then 'identificacao' else 'dados' end; end if;
  select count(*), count(*) filter (where e.signed_at is null)
    into v_items, v_unsigned
    from public.enrollment_onboarding_items oi join public.enrollments e on e.id = oi.enrollment_id
   where oi.onboarding_session_id = v_session.id;
  if v_items = 0 then return case when v_session.flow = 'rematricula' then 'alunos' else 'dados' end; end if;
  if v_unsigned > 0 and not (v_session.context ? 'values_confirmed_at') then return 'condicoes'; end if;
  if v_unsigned > 0 then return 'assinatura'; end if;
  if not (v_session.context ? 'billing_method') then return 'cobranca'; end if;
  select count(*) filter (where i.status in ('pendente', 'vencido')), count(*) filter (where i.status = 'pago')
    into v_open, v_paid
    from public.enrollment_onboarding_items oi join public.installments i on i.enrollment_id = oi.enrollment_id
   where oi.onboarding_session_id = v_session.id and i.status <> 'cancelado';
  if v_open = 0 and v_paid > 0 then return 'concluida'; end if;
  return 'pagamento';
end $$;

-- Cobranças da família agrupadas por vencimento (uma cobrança Asaas pode
-- cobrir a parcela de vários irmãos).
create or replace function public.onboarding_charges(p_session_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(c order by c ->> 'due_date'), '[]'::jsonb) from (
    select jsonb_build_object(
      'due_date', i.due_date,
      'amount_cents', sum(i.amount_cents),
      'method', max(i.method::text),
      'payment_url', max(i.payment_url),
      'provider_charge_id', i.provider_charge_id,
      'status', case when bool_and(i.status = 'pago') then 'pago' when bool_or(i.status = 'vencido') then 'vencido' else 'pendente' end
    ) c
      from public.enrollment_onboarding_items oi join public.installments i on i.enrollment_id = oi.enrollment_id
     where oi.onboarding_session_id = p_session_id and i.status <> 'cancelado'
     group by i.due_date, i.provider_charge_id
  ) x
$$;

create or replace function public.onboarding_open(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session public.enrollment_onboarding_sessions; v_early_until date; v_added jsonb;
begin
  select * into v_session from public.enrollment_onboarding_sessions where token = trim(p_token) and status <> 'cancelada' for update;
  if not found then raise exception 'Jornada inválida ou expirada' using errcode = 'P0002'; end if;
  update public.enrollment_onboarding_sessions set last_opened_at = now(), updated_at = now() where id = v_session.id;
  v_early_until := public.rematricula_early_until(v_session.campaign_id);
  v_added := coalesce(v_session.context -> 'added_students', '[]'::jsonb);

  return jsonb_build_object(
    'token', v_session.token,
    'flow', v_session.flow,
    'status', v_session.status,
    'step', v_session.current_step,
    'stage', public.onboarding_stage(v_session.id),
    'campaign', (select name from public.campaigns where id = v_session.campaign_id),
    'guardian', case when v_session.guardian_id is null then null else (
      select jsonb_build_object('name', g.full_name, 'email', g.email, 'phone', g.phone, 'rg', g.rg)
        from public.guardians g where g.id = v_session.guardian_id
    ) end,
    'pricing', jsonb_build_object(
      'today', public.local_today(),
      'early_until', v_early_until,
      'early_active', v_session.flow = 'rematricula' and v_early_until is not null and public.local_today() <= v_early_until
    ),
    'values_confirmed', v_session.context ? 'values_confirmed_at',
    'plan_choice', v_session.context -> 'plan_choice',
    'plan_choices', public.payment_plan_choices(v_session.campaign_id, public.local_today()),
    'billing_method', v_session.context ->> 'billing_method',
    'charges', public.onboarding_charges(v_session.id),
    'children', coalesce((
      select jsonb_agg(jsonb_build_object(
        'student_id', s.id,
        'name', s.full_name,
        'is_new', v_added ? s.id::text,
        'current_grade', current_grade.name,
        'target_grade_id', target_grade.id,
        'target_grade', target_grade.name,
        'eligible', (enrollment_case.id is null or enrollment_case.guardian_id = v_session.guardian_id)
          and target_grade.id is not null
          and public.enrollment_amount_for_date(v_session.campaign_id, target_grade.id, coalesce(enrollment_case.is_new_student, false), public.local_today()) is not null,
        'eligibility_reason', case
          when enrollment_case.id is not null and enrollment_case.guardian_id <> v_session.guardian_id
            then 'A rematrícula deste aluno já foi iniciada por outro responsável. Fale com a secretaria.'
          when target_grade.id is null then 'Não foi possível identificar a próxima série deste aluno. Fale com a secretaria.'
          when public.enrollment_amount_for_date(v_session.campaign_id, target_grade.id, coalesce(enrollment_case.is_new_student, false), public.local_today()) is null
            then 'A próxima série deste aluno ainda não tem valor configurado. Fale com a secretaria.'
          else null
        end,
        'amount_cents', case
          when enrollment_case.guardian_id = v_session.guardian_id and enrollment_case.signed_at is not null then enrollment_case.amount_cents
          else public.enrollment_amount_for_date(v_session.campaign_id, target_grade.id, coalesce(enrollment_case.is_new_student, false), public.local_today())
        end,
        'full_amount_cents', offering.amount_cents,
        'early_amount_cents', case when v_session.flow = 'rematricula' and not coalesce(enrollment_case.is_new_student, false) then offering.early_amount_cents end,
        'selected', oi.enrollment_id is not null,
        'enrollment_id', case when enrollment_case.guardian_id = v_session.guardian_id then oi.enrollment_id else null end,
        'contract_token', cs.token,
        'contract_status', cs.status,
        'signed_at', coalesce(cs.signed_at, case when enrollment_case.guardian_id = v_session.guardian_id then enrollment_case.signed_at end)
      ) order by (v_added ? s.id::text), s.full_name)
        from public.student_guardians sg
        join public.students s on s.id = sg.student_id
        left join public.classes current_class on current_class.id = s.current_class_id
        left join public.grades current_grade on current_grade.id = current_class.grade_id
        left join lateral (
          select e.* from public.enrollments e where e.campaign_id = v_session.campaign_id and e.student_id = s.id limit 1
        ) enrollment_case on true
        left join public.grades target_grade
          on target_grade.id = coalesce(
            case when enrollment_case.guardian_id = v_session.guardian_id then enrollment_case.target_grade_id end,
            current_grade.next_grade_id
          )
        left join public.campaigns campaign on campaign.id = v_session.campaign_id
        left join public.grade_offerings offering on offering.academic_year = campaign.academic_year and offering.grade_id = target_grade.id
        left join public.enrollment_onboarding_items oi
          on oi.onboarding_session_id = v_session.id
         and oi.enrollment_id = case when enrollment_case.guardian_id = v_session.guardian_id then enrollment_case.id else null end
        left join lateral (
          select cs.* from public.contract_session_enrollments cse join public.contract_sessions cs on cs.id = cse.contract_session_id
           where cse.enrollment_id = oi.enrollment_id and cs.status <> 'cancelada'
           order by cs.created_at desc limit 1
        ) cs on true
       where sg.guardian_id = v_session.guardian_id
         and (v_session.flow = 'rematricula' or oi.enrollment_id is not null)
    ), '[]'::jsonb)
  );
end $$;

revoke all on function public.enrollment_amount_for_date(uuid, uuid, boolean, date), public.payment_plan_choices(uuid, date),
  public.onboarding_stage(uuid), public.onboarding_charges(uuid) from public, anon, authenticated;
grant execute on function public.enrollment_amount_for_date(uuid, uuid, boolean, date), public.payment_plan_choices(uuid, date),
  public.onboarding_stage(uuid), public.onboarding_charges(uuid) to service_role;
revoke all on function public.onboarding_choose_plan(text, smallint), public.onboarding_choose_billing(text, public.payment_method),
  public.onboarding_add_child(text, text, uuid, date, text), public.onboarding_remove_added_child(text, uuid),
  public.onboarding_set_guardian_rg(text, text) from public;
grant execute on function public.onboarding_choose_plan(text, smallint), public.onboarding_choose_billing(text, public.payment_method),
  public.onboarding_add_child(text, text, uuid, date, text), public.onboarding_remove_added_child(text, uuid),
  public.onboarding_set_guardian_rg(text, text) to anon, authenticated;
revoke execute on function public.contract_finalize_signed_pdf(text, text, text, boolean, text, text, text) from public, anon, authenticated;
grant execute on function public.contract_finalize_signed_pdf(text, text, text, boolean, text, text, text) to service_role;
