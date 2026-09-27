-- Onboarding público: o link inicial é único por modalidade. Após a identificação,
-- o token da jornada é a chave de retomada, acompanhamento e recuperação.

create table public.enrollment_onboarding_sessions (
  id uuid primary key default gen_random_uuid(),
  token text not null unique default encode(extensions.gen_random_bytes(24), 'hex'),
  campaign_id uuid not null references public.campaigns(id) on delete restrict,
  guardian_id uuid references public.guardians(id) on delete set null,
  flow public.campaign_kind not null,
  status text not null default 'identificacao' check (status in ('identificacao', 'filhos', 'contratos', 'pagamento', 'concluida', 'cancelada')),
  current_step smallint not null default 1 check (current_step between 1 and 5),
  context jsonb not null default '{}'::jsonb,
  first_opened_at timestamptz not null default now(),
  last_opened_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index enrollment_onboarding_sessions_recovery_idx
  on public.enrollment_onboarding_sessions (campaign_id, status, last_opened_at desc);
create index enrollment_onboarding_sessions_guardian_idx
  on public.enrollment_onboarding_sessions (guardian_id, campaign_id, updated_at desc);

create table public.enrollment_onboarding_items (
  onboarding_session_id uuid not null references public.enrollment_onboarding_sessions(id) on delete cascade,
  enrollment_id uuid not null references public.enrollments(id) on delete restrict,
  selected_at timestamptz not null default now(),
  primary key (onboarding_session_id, enrollment_id),
  unique (enrollment_id)
);

-- A data-limite e o percentual seguem configuráveis; o percentual já definido
-- na política/planos não é substituído por um valor arbitrário nesta migração.
alter table public.payment_policies
  add column if not exists enrollment_discount_deadline date;

update public.campaigns
   set ends_on = '2026-10-31'
 where name = 'Rematrícula 2027' and kind = 'rematricula' and academic_year = 2027;

update public.payment_policies pp
   set enrollment_discount_deadline = '2026-10-31',
       last_due_date = '2027-01-20'
  from public.campaigns c
 where c.id = pp.campaign_id and c.academic_year = 2027;

update public.payment_plans p
   set due_dates = case p.installments
     when 1 then array['2026-11-20'::date]
     when 2 then array['2026-12-20'::date, '2027-01-20'::date]
     when 3 then array['2026-11-20'::date, '2026-12-20'::date, '2027-01-20'::date]
     else p.due_dates end,
       available_until = case when p.installments = 3 then '2026-11-20'::date else p.available_until end
  from public.campaigns c
 where c.id = p.campaign_id and c.academic_year = 2027;

create or replace function public.onboarding_campaign(p_flow public.campaign_kind)
returns public.campaigns language plpgsql security definer set search_path = '' as $$
declare v_campaign public.campaigns;
begin
  select * into v_campaign
    from public.campaigns
   where kind = p_flow and status = 'ativa' and starts_on <= public.local_today()
     and (ends_on is null or ends_on >= public.local_today())
   order by starts_on desc
   limit 1;
  if not found then raise exception 'Não há campanha aberta para esta modalidade' using errcode = 'P0001'; end if;
  return v_campaign;
end $$;

create or replace function public.onboarding_start(p_flow public.campaign_kind, p_token text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session public.enrollment_onboarding_sessions; v_campaign public.campaigns;
begin
  if nullif(trim(p_token), '') is not null then
    select * into v_session from public.enrollment_onboarding_sessions
     where token = trim(p_token) and flow = p_flow and status <> 'cancelada' for update;
    if found then
      update public.enrollment_onboarding_sessions set last_opened_at = now() where id = v_session.id returning * into v_session;
      return jsonb_build_object('token', v_session.token, 'flow', v_session.flow, 'status', v_session.status, 'step', v_session.current_step, 'identified', v_session.guardian_id is not null);
    end if;
  end if;
  v_campaign := public.onboarding_campaign(p_flow);
  insert into public.enrollment_onboarding_sessions(campaign_id, flow)
  values (v_campaign.id, p_flow) returning * into v_session;
  return jsonb_build_object('token', v_session.token, 'flow', v_session.flow, 'status', v_session.status, 'step', v_session.current_step, 'identified', false);
end $$;

create or replace function public.onboarding_identify_rematricula(
  p_token text, p_cpf text, p_phone text, p_full_name text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session public.enrollment_onboarding_sessions; v_guardian public.guardians; v_cpf text; v_phone text;
begin
  v_cpf := regexp_replace(coalesce(p_cpf, ''), '\\D', '', 'g');
  v_phone := regexp_replace(coalesce(p_phone, ''), '\\D', '', 'g');
  if v_cpf !~ '^[0-9]{11}$' or length(v_phone) < 8 then
    raise exception 'Informe CPF e WhatsApp para localizar sua família' using errcode = '22023';
  end if;
  select * into v_session from public.enrollment_onboarding_sessions
   where token = p_token and flow = 'rematricula' and status <> 'cancelada' for update;
  if not found then raise exception 'Jornada inválida ou expirada' using errcode = 'P0002'; end if;
  perform public.onboarding_campaign('rematricula');
  select * into v_guardian from public.guardians
   where cpf = v_cpf and right(regexp_replace(phone, '\\D', '', 'g'), 8) = right(v_phone, 8)
     and (nullif(trim(p_full_name), '') is null or lower(full_name) = lower(trim(p_full_name)))
   limit 1;
  if not found then raise exception 'Não localizamos uma família com esses dados. Confira CPF e WhatsApp ou inicie uma matrícula nova.' using errcode = 'P0002'; end if;
  update public.enrollment_onboarding_sessions
     set guardian_id = v_guardian.id, status = 'filhos', current_step = 2,
         context = context || jsonb_build_object('identified_at', now()), last_opened_at = now()
   where id = v_session.id;
  return public.onboarding_open(p_token);
end $$;

create or replace function public.onboarding_open(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session public.enrollment_onboarding_sessions;
begin
  select * into v_session from public.enrollment_onboarding_sessions
   where token = p_token and status <> 'cancelada' for update;
  if not found then raise exception 'Jornada inválida ou expirada' using errcode = 'P0002'; end if;
  update public.enrollment_onboarding_sessions set last_opened_at = now() where id = v_session.id;
  return jsonb_build_object(
    'token', v_session.token, 'flow', v_session.flow, 'status', v_session.status, 'step', v_session.current_step,
    'campaign', (select name from public.campaigns where id = v_session.campaign_id),
    'guardian', case when v_session.guardian_id is null then null else (select jsonb_build_object('name', g.full_name, 'email', g.email, 'phone', g.phone) from public.guardians g where g.id = v_session.guardian_id) end,
    'children', coalesce((
      select jsonb_agg(jsonb_build_object(
        'student_id', s.id, 'name', s.full_name, 'current_grade', current_grade.name, 'target_grade_id', target_grade.id, 'target_grade', target_grade.name,
        'selected', oi.enrollment_id is not null, 'enrollment_id', oi.enrollment_id,
        'contract_token', cs.token, 'contract_status', cs.status, 'signed_at', cs.signed_at
      ) order by s.full_name)
      from public.student_guardians sg
      join public.students s on s.id = sg.student_id
      left join public.classes current_class on current_class.id = s.current_class_id
      left join public.grades current_grade on current_grade.id = current_class.grade_id
      left join public.grades target_grade on target_grade.id = current_grade.next_grade_id
      left join lateral (
        select e.id from public.enrollments e
         where e.campaign_id = v_session.campaign_id and e.student_id = s.id and e.guardian_id = v_session.guardian_id
         limit 1
      ) existing_enrollment on true
      left join public.enrollment_onboarding_items oi on oi.onboarding_session_id = v_session.id and oi.enrollment_id = existing_enrollment.id
      left join lateral (
        select cs.* from public.contract_session_enrollments cse join public.contract_sessions cs on cs.id = cse.contract_session_id
         where cse.enrollment_id = oi.enrollment_id and cs.status <> 'cancelada' order by cs.created_at desc limit 1
      ) cs on true
      where sg.guardian_id = v_session.guardian_id and target_grade.id is not null
    ), '[]'::jsonb),
    'payment_options', coalesce((
      select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'description', p.description, 'installments', p.installments, 'discount_pct', p.discount_pct, 'due_dates', p.due_dates) order by p.sort_order)
      from public.payment_plans p
      where p.campaign_id = v_session.campaign_id and p.active
        and (p.available_until is null or public.local_today() <= p.available_until)
        and not (public.local_today() > '2026-11-20'::date and p.installments <> 2)
    ), '[]'::jsonb)
  );
end $$;

create or replace function public.onboarding_select_rematricula_children(p_token text, p_student_ids uuid[])
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session public.enrollment_onboarding_sessions; v_student_id uuid; v_current_grade uuid; v_target_grade uuid; v_enrollment_id uuid; v_amount integer;
begin
  select * into v_session from public.enrollment_onboarding_sessions
   where token = p_token and flow = 'rematricula' and guardian_id is not null and status <> 'cancelada' for update;
  if not found then raise exception 'Identifique primeiro o responsável' using errcode = 'P0001'; end if;
  if coalesce(cardinality(p_student_ids), 0) = 0 then raise exception 'Selecione pelo menos um aluno' using errcode = '22023'; end if;
  delete from public.enrollment_onboarding_items where onboarding_session_id = v_session.id;
  foreach v_student_id in array p_student_ids loop
    select cc.grade_id, gr.next_grade_id into v_current_grade, v_target_grade
      from public.student_guardians sg join public.students s on s.id = sg.student_id
      join public.classes cc on cc.id = s.current_class_id join public.grades gr on gr.id = cc.grade_id
     where sg.student_id = v_student_id and sg.guardian_id = v_session.guardian_id;
    if v_target_grade is null then raise exception 'Aluno selecionado não possui série seguinte configurada' using errcode = 'P0001'; end if;
    select amount_cents into v_amount from public.grade_offerings where academic_year = (select academic_year from public.campaigns where id = v_session.campaign_id) and grade_id = v_target_grade;
    if v_amount is null then raise exception 'A série pretendida não possui valor configurado' using errcode = 'P0001'; end if;
    insert into public.enrollments(campaign_id, student_id, guardian_id, origin, from_class_id, target_grade_id, status, amount_cents, form_started_at)
    values (v_session.campaign_id, v_student_id, v_session.guardian_id, 'site', (select current_class_id from public.students where id = v_student_id), v_target_grade, 'aguardando_assinatura', v_amount, now())
    on conflict (campaign_id, student_id) do update set guardian_id = excluded.guardian_id, target_grade_id = excluded.target_grade_id, amount_cents = coalesce(public.enrollments.amount_cents, excluded.amount_cents), form_started_at = coalesce(public.enrollments.form_started_at, now())
    returning id into v_enrollment_id;
    insert into public.enrollment_onboarding_items(onboarding_session_id, enrollment_id) values (v_session.id, v_enrollment_id);
  end loop;
  update public.enrollment_onboarding_sessions set status = 'contratos', current_step = 3, last_opened_at = now() where id = v_session.id;
  return public.onboarding_open(p_token);
end $$;

create or replace function public.onboarding_prepare_individual_contract(p_token text, p_enrollment_id uuid, p_confirmation_email text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session public.enrollment_onboarding_sessions; v_enrollment public.enrollments; v_contract_id uuid; v_contract_token text; v_email text;
begin
  select * into v_session from public.enrollment_onboarding_sessions where token = p_token and status <> 'cancelada' for update;
  if not found then raise exception 'Jornada inválida ou expirada' using errcode = 'P0002'; end if;
  if not exists (select 1 from public.enrollment_onboarding_items where onboarding_session_id = v_session.id and enrollment_id = p_enrollment_id) then raise exception 'Este aluno não pertence a esta jornada' using errcode = '42501'; end if;
  select * into v_enrollment from public.enrollments where id = p_enrollment_id for update;
  v_email := lower(trim(coalesce(nullif(p_confirmation_email, ''), (select email from public.guardians where id = v_session.guardian_id))));
  if v_email is null or v_email !~* '^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$' then raise exception 'Informe um e-mail válido para confirmação' using errcode = '22023'; end if;
  if not exists (
    select 1 from public.campaign_documents cd join public.documents d on d.id = cd.document_id and d.kind = 'contrato'
      join public.document_versions dv on dv.document_id = d.id and dv.is_current and dv.storage_path is not null and dv.sha256 is not null
     where cd.campaign_id = v_enrollment.campaign_id and (dv.grade_id is null or dv.grade_id = v_enrollment.target_grade_id)
  ) then raise exception 'O PDF definitivo do contrato ainda não foi publicado pela escola' using errcode = 'P0001'; end if;
  update public.guardians set email = v_email where id = v_session.guardian_id and email is distinct from v_email;
  update public.contract_sessions cs set status = 'cancelada'
   from public.contract_session_enrollments cse
   where cse.contract_session_id = cs.id and cse.enrollment_id = v_enrollment.id and cs.status in ('pronta', 'codigo_enviado', 'verificada');
  insert into public.contract_sessions(campaign_id, guardian_id, confirmation_email)
  values(v_enrollment.campaign_id, v_session.guardian_id, v_email) returning id, token into v_contract_id, v_contract_token;
  insert into public.contract_session_enrollments(contract_session_id, enrollment_id) values(v_contract_id, v_enrollment.id);
  update public.enrollments set status = 'aguardando_assinatura' where id = v_enrollment.id;
  perform public.contract_issue_verification_code(v_contract_id);
  return jsonb_build_object('token', v_contract_token, 'url', '/contrato/' || v_contract_token);
end $$;

create or replace function public.onboarding_choose_payment(p_token text, p_payment_plan_id uuid, p_method public.payment_method)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session public.enrollment_onboarding_sessions; v_plan public.payment_plans; v_enrollment record;
begin
  select * into v_session from public.enrollment_onboarding_sessions where token = p_token and status <> 'cancelada' for update;
  if not found then raise exception 'Jornada inválida ou expirada' using errcode = 'P0002'; end if;
  if exists (
    select 1 from public.enrollment_onboarding_items oi
      left join public.document_acceptances da on da.enrollment_id = oi.enrollment_id and da.status = 'assinado'
     where oi.onboarding_session_id = v_session.id group by oi.enrollment_id having count(da.id) = 0
  ) then raise exception 'Conclua todas as assinaturas antes de escolher o pagamento' using errcode = 'P0001'; end if;
  select * into v_plan from public.payment_plans where id = p_payment_plan_id and campaign_id = v_session.campaign_id and active;
  if not found or (v_plan.available_until is not null and public.local_today() > v_plan.available_until) or (public.local_today() > '2026-11-20'::date and v_plan.installments <> 2) then
    raise exception 'Esta condição de parcelamento não está disponível nesta data' using errcode = '22023'; end if;
  for v_enrollment in select e.id from public.enrollment_onboarding_items oi join public.enrollments e on e.id = oi.enrollment_id where oi.onboarding_session_id = v_session.id loop
    update public.enrollments set payment_plan_id = v_plan.id, status = 'aguardando_pagamento' where id = v_enrollment.id;
    if not exists (select 1 from public.installments where enrollment_id = v_enrollment.id and status <> 'cancelado') then perform public.generate_installments(v_enrollment.id); end if;
    update public.installments set method = p_method where enrollment_id = v_enrollment.id and status = 'pendente';
    insert into public.enrollment_events(enrollment_id, code, title, body, actor, metadata)
    values(v_enrollment.id, 'PAYMENT_CHOICE_CONFIRMED', 'Forma de pagamento escolhida', 'Aguardando a emissão da cobrança.', 'responsavel', jsonb_build_object('method', p_method, 'payment_plan_id', v_plan.id));
  end loop;
  update public.enrollment_onboarding_sessions set status = 'concluida', current_step = 5, completed_at = now(), last_opened_at = now() where id = v_session.id;
  return public.onboarding_open(p_token);
end $$;

-- Limite de reenvio também é imposto no banco, não apenas na tela.
create or replace function public.contract_send_email_code(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session public.contract_sessions;
begin
  select * into v_session from public.contract_sessions where token = p_token for update;
  if not found or v_session.status in ('assinada', 'cancelada', 'expirada') or v_session.expires_at <= now() then raise exception 'Link de contrato inválido ou expirado' using errcode = 'P0002'; end if;
  if v_session.verification_sent_at is not null and v_session.verification_sent_at > now() - interval '1 minute' then
    raise exception 'Aguarde um minuto para reenviar o código' using errcode = 'P0001';
  end if;
  perform public.contract_issue_verification_code(v_session.id);
  return jsonb_build_object('ok', true, 'resend_after_seconds', 60);
end $$;

-- Só gera parcelas se o pagamento já foi definido. Isso permite contratos por filho
-- antes da escolha posterior de boleto/cartão, sem perder a trilha jurídica.
create or replace function public.contract_sign(p_token text, p_signer_full_name text, p_signature_image_data text, p_accepted boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session public.contract_sessions; v_enrollment record; v_document_version_id uuid; v_signature_hash text; v_headers jsonb := coalesce(current_setting('request.headers', true), '{}')::jsonb; v_ip inet;
begin
  if p_accepted is not true then raise exception 'Confirme a leitura e o aceite do contrato' using errcode = '22023'; end if;
  if nullif(trim(p_signer_full_name), '') is null then raise exception 'Informe o nome de quem assina' using errcode = '22023'; end if;
  if p_signature_image_data is null or p_signature_image_data !~ '^data:image/(png|jpeg);base64,' or length(p_signature_image_data) not between 100 and 500000 then raise exception 'A assinatura desenhada é obrigatória' using errcode = '22023'; end if;
  select * into v_session from public.contract_sessions where token = p_token for update;
  if not found or v_session.status in ('assinada', 'cancelada', 'expirada') or v_session.expires_at <= now() then raise exception 'Link de contrato inválido ou expirado' using errcode = 'P0002'; end if;
  if v_session.verification_verified_at is null then raise exception 'Confirme o código enviado por e-mail antes de assinar' using errcode = 'P0001'; end if;
  begin v_ip := nullif(split_part(coalesce(v_headers ->> 'x-forwarded-for', ''), ',', 1), '')::inet; exception when others then v_ip := null; end;
  v_signature_hash := encode(extensions.digest(p_signature_image_data, 'sha256'), 'hex');
  for v_enrollment in select e.* from public.contract_session_enrollments cse join public.enrollments e on e.id = cse.enrollment_id where cse.contract_session_id = v_session.id loop
    select dv.id into v_document_version_id from public.campaign_documents cd join public.documents d on d.id = cd.document_id and d.kind = 'contrato'
      join public.document_versions dv on dv.document_id = d.id and dv.is_current and dv.storage_path is not null and dv.sha256 is not null
     where cd.campaign_id = v_enrollment.campaign_id and (dv.grade_id is null or dv.grade_id = v_enrollment.target_grade_id)
     order by case when dv.grade_id = v_enrollment.target_grade_id then 0 else 1 end limit 1;
    if v_document_version_id is null then raise exception 'O PDF definitivo do contrato não foi encontrado' using errcode = 'P0001'; end if;
    insert into public.document_acceptances(enrollment_id, document_version_id, status, provider, contract_session_id, signer_full_name, signer_email, email_verified_at, signature_image_data, signature_image_sha256, document_hash, completed_at, ip, user_agent, device)
    values(v_enrollment.id, v_document_version_id, 'assinado', 'cec_assinatura_interna', v_session.id, trim(p_signer_full_name), v_session.confirmation_email, v_session.verification_verified_at, p_signature_image_data, v_signature_hash, (select sha256 from public.document_versions where id = v_document_version_id), now(), v_ip, v_headers ->> 'user-agent', v_headers ->> 'sec-ch-ua-mobile')
    on conflict (enrollment_id, document_version_id) do nothing;
    if v_enrollment.payment_plan_id is not null and not exists(select 1 from public.installments where enrollment_id = v_enrollment.id and status <> 'cancelado') then perform public.generate_installments(v_enrollment.id); end if;
    update public.enrollments set signed_at = now(), status = case when payment_plan_id is null then 'aguardando_pagamento' else status end where id = v_enrollment.id;
    insert into public.enrollment_events(enrollment_id, code, title, body, actor, metadata)
    values(v_enrollment.id, 'CONTRACT_SIGNED', 'Contrato assinado', 'Contrato assinado após confirmação por e-mail.', 'responsavel', jsonb_build_object('contract_session_id', v_session.id, 'signature_sha256', v_signature_hash));
  end loop;
  update public.contract_sessions set status = 'assinada', signed_at = now() where id = v_session.id;
  return jsonb_build_object('ok', true, 'signed_at', now());
end $$;

alter table public.enrollment_onboarding_sessions enable row level security;
alter table public.enrollment_onboarding_items enable row level security;
create policy "equipe lê jornadas públicas" on public.enrollment_onboarding_sessions for select to authenticated using ((select public.is_staff()));
create policy "equipe lê itens das jornadas públicas" on public.enrollment_onboarding_items for select to authenticated using ((select public.is_staff()));

revoke execute on function public.onboarding_campaign(public.campaign_kind), public.onboarding_start(public.campaign_kind, text), public.onboarding_identify_rematricula(text, text, text, text), public.onboarding_open(text), public.onboarding_select_rematricula_children(text, uuid[]), public.onboarding_prepare_individual_contract(text, uuid, text), public.onboarding_choose_payment(text, uuid, public.payment_method) from public;
grant execute on function public.onboarding_start(public.campaign_kind, text), public.onboarding_identify_rematricula(text, text, text, text), public.onboarding_open(text), public.onboarding_select_rematricula_children(text, uuid[]), public.onboarding_prepare_individual_contract(text, uuid, text), public.onboarding_choose_payment(text, uuid, public.payment_method) to anon, authenticated;
