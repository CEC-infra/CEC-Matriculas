-- Rematrícula 2027: etapa "Valores" antes das assinaturas.
--
-- Fechando até 31/10, a família mantém o valor de outubro e MONTA o pagamento:
--   * boleto ou cartão em 3x (20/11, 20/12, 20/01)
--   * boleto ou cartão em 2x (20/12, 20/01)
--   * Pix à vista, parcela única (20/01)
-- Códigos de opção: boleto_3x, cartao_3x, boleto_2x, cartao_2x, pix_1x.
-- A partir de 01/11 vale a tabela cheia de 2027, somente Pix em parcela única
-- em 20/01. A escolha é gravada antes da assinatura; a assinatura revalida a
-- data e, se o prazo de outubro passou, aplica a regra de novembro.
-- As cobranças em si (Asaas) ficam para depois e leem installments.method.

alter table public.enrollments
  add column if not exists preferred_payment_method public.payment_method;

update public.payment_policies pp
   set accepted_methods = array['boleto'::public.payment_method, 'cartao'::public.payment_method, 'pix'::public.payment_method]
  from public.campaigns c
 where c.id = pp.campaign_id and c.academic_year = 2027 and c.kind = 'rematricula';

update public.payment_plans p
   set name = case p.installments
         when 3 then '3x — boleto ou cartão (nov, dez e jan)'
         when 2 then '2x — boleto ou cartão (dez e jan)'
         else 'Pix à vista em janeiro'
       end,
       description = case p.installments
         when 3 then 'Fechando até 31/10/2026 · valor de outubro · vencimentos 20/11, 20/12 e 20/01'
         when 2 then 'Fechando até 31/10/2026 · valor de outubro · vencimentos 20/12 e 20/01'
         else 'Pix em parcela única com vencimento em 20/01/2027 · valor de outubro até 31/10, tabela 2027 depois'
       end,
       active = true,
       sort_order = case p.installments when 3 then 1 when 2 then 2 else 3 end
  from public.campaigns c
 where c.id = p.campaign_id and c.academic_year = 2027 and c.kind = 'rematricula'
   and p.installments in (1, 2, 3);

-- Data-limite do valor de outubro para a campanha (mesma vigência do plano 3x).
create or replace function public.rematricula_early_until(p_campaign_id uuid)
returns date language sql stable security definer set search_path = '' as $$
  select max(p.available_until)
    from public.payment_plans p
   where p.campaign_id = p_campaign_id and p.active and p.installments = 3
$$;

-- Opções que a família pode escolher numa data. Fonte única para tela,
-- validação e assinatura. Parcelado (2x/3x) só até o fim do valor de outubro,
-- em boleto ou cartão; Pix é sempre à vista.
create or replace function public.rematricula_payment_options(p_campaign_id uuid, p_reference_date date default public.local_today())
returns jsonb language sql stable security definer set search_path = '' as $$
  with early as (select public.rematricula_early_until(p_campaign_id) as until),
  plans as (
    select p.* from public.payment_plans p
     where p.campaign_id = p_campaign_id and p.active and p.installments in (1, 2, 3)
       and (p.available_until is null or p_reference_date <= p.available_until)
  ),
  methods(method, label, sort) as (values ('boleto', 'Boleto', 1), ('cartao', 'Cartão', 2))
  select coalesce(jsonb_agg(o.item order by o.sort1, o.sort2), '[]'::jsonb)
    from (
      select -p.installments as sort1, m.sort as sort2,
             jsonb_build_object('option', m.method || '_' || p.installments || 'x', 'method', m.method,
               'installments', p.installments, 'payment_plan_id', p.id,
               'label', m.label || ' em ' || p.installments || 'x', 'due_dates', p.due_dates) as item
        from plans p cross join methods m cross join early
       where p.installments > 1 and early.until is not null and p_reference_date <= early.until
      union all
      select 0, 3, jsonb_build_object('option', 'pix_1x', 'method', 'pix', 'installments', 1,
               'payment_plan_id', p.id, 'label', 'Pix à vista', 'due_dates', p.due_dates)
        from plans p where p.installments = 1
    ) o
$$;

-- Plano efetivo no fechamento: respeita a escolha da família quando ela ainda
-- vale na data da assinatura; senão cai na regra padrão por data.
create or replace function public.enrollment_plan_at_closing(p_enrollment_id uuid, p_closed_on date default public.local_today())
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare v_e public.enrollments; v_kind public.campaign_kind;
begin
  select * into v_e from public.enrollments where id = p_enrollment_id;
  if not found then raise exception 'Matrícula não encontrada' using errcode = 'P0002'; end if;
  select kind into v_kind from public.campaigns where id = v_e.campaign_id;
  if v_kind = 'rematricula'::public.campaign_kind and v_e.payment_plan_id is not null and exists (
    select 1 from jsonb_array_elements(public.rematricula_payment_options(v_e.campaign_id, p_closed_on)) o
     where (o ->> 'payment_plan_id')::uuid = v_e.payment_plan_id
       and (v_e.preferred_payment_method is null or (o ->> 'method') = v_e.preferred_payment_method::text)
  ) then
    return v_e.payment_plan_id;
  end if;
  return public.payment_plan_for_closing(v_e.campaign_id, p_closed_on);
end $$;

create or replace function public.onboarding_choose_payment_option(p_token text, p_option text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_session public.enrollment_onboarding_sessions;
  v_choice jsonb;
  v_enrollment record;
begin
  select * into v_session from public.enrollment_onboarding_sessions
   where token = trim(p_token) and flow = 'rematricula' and guardian_id is not null and status not in ('cancelada', 'concluida')
   for update;
  if not found then raise exception 'Jornada inválida ou expirada' using errcode = 'P0002'; end if;
  if not exists (select 1 from public.enrollment_onboarding_items where onboarding_session_id = v_session.id) then
    raise exception 'Selecione os alunos antes de escolher o pagamento' using errcode = 'P0001';
  end if;

  select o into v_choice
    from jsonb_array_elements(public.rematricula_payment_options(v_session.campaign_id, public.local_today())) o
   where o ->> 'option' = p_option;
  if v_choice is null then raise exception 'Esta forma de pagamento não está disponível hoje' using errcode = '22023'; end if;

  for v_enrollment in
    select e.id from public.enrollment_onboarding_items oi
      join public.enrollments e on e.id = oi.enrollment_id
     where oi.onboarding_session_id = v_session.id
       and e.guardian_id = v_session.guardian_id
       and e.signed_at is null
       and not exists (select 1 from public.installments i where i.enrollment_id = e.id and i.status <> 'cancelado')
  loop
    update public.enrollments
       set payment_plan_id = (v_choice ->> 'payment_plan_id')::uuid,
           preferred_payment_method = (v_choice ->> 'method')::public.payment_method
     where id = v_enrollment.id;
    insert into public.enrollment_events(enrollment_id, code, title, body, actor, metadata)
    values (v_enrollment.id, 'PAYMENT_OPTION_CHOSEN', 'Forma de pagamento escolhida',
            'Família conferiu os valores e escolheu: ' || (v_choice ->> 'label') || '.', 'responsavel', v_choice);
  end loop;

  update public.enrollment_onboarding_sessions
     set context = context || jsonb_build_object('payment_choice', v_choice || jsonb_build_object('chosen_at', now()), 'values_confirmed_at', now()),
         last_opened_at = now()
   where id = v_session.id;
  return public.onboarding_open(v_session.token);
end $$;

create or replace function public.contract_finalize_signed_pdf(
  p_token text,
  p_signer_full_name text,
  p_signature_image_data text,
  p_accepted boolean,
  p_ip text default null,
  p_user_agent text default null,
  p_device text default null
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
    -- Forma escolhida na etapa Valores. Se o 3x expirou e caiu no pagamento
    -- único, a parcela única é Pix (única forma oferecida a partir de 01/11).
    update public.installments i
       set method = case
             when (select installments from public.payment_plans where id = v_plan_id) = 1 then 'pix'::public.payment_method
             else v_enrollment.preferred_payment_method
           end
     where i.enrollment_id = v_enrollment.id and i.status = 'pendente'
       and (v_enrollment.preferred_payment_method is not null or (select installments from public.payment_plans where id = v_plan_id) = 1);
    update public.enrollments set signed_at = now(), status = 'aguardando_pagamento' where id = v_enrollment.id;
    insert into public.enrollment_events(enrollment_id, code, title, body, actor, metadata)
    values(v_enrollment.id, 'CONTRACT_SIGNED', 'Contrato assinado', 'PDF individual assinado após confirmação por e-mail.', 'responsavel', jsonb_build_object('contract_session_id', v_session.id, 'signature_sha256', v_signature_hash, 'document_sha256', v_acceptance.signed_document_hash, 'signed_pdf_at', v_acceptance.signed_pdf_at, 'effective_amount_cents', v_effective_amount, 'payment_plan_id', v_plan_id));
  end loop;
  update public.contract_sessions set status = 'assinada', signed_at = now() where id = v_session.id;
  return jsonb_build_object('ok', true, 'signed_at', now());
end $$;

-- Etapa final: confirma a escolha já feita (ou registra uma, para sessões
-- antigas). Aceita boleto além de Pix e cartão.
create or replace function public.onboarding_choose_payment(
  p_token text,
  p_payment_plan_id uuid,
  p_method public.payment_method
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_session public.enrollment_onboarding_sessions;
  v_enrollment record;
  v_plan_id uuid;
  v_method public.payment_method;
begin
  select * into v_session from public.enrollment_onboarding_sessions where token = p_token and status <> 'cancelada' for update;
  if not found then raise exception 'Jornada inválida ou expirada' using errcode = 'P0002'; end if;
  if exists (
    select 1 from public.enrollment_onboarding_items oi
      left join public.document_acceptances da on da.enrollment_id = oi.enrollment_id and da.status = 'assinado'
     where oi.onboarding_session_id = v_session.id group by oi.enrollment_id having count(da.id) = 0
  ) then raise exception 'Conclua todas as assinaturas antes de escolher o pagamento' using errcode = 'P0001'; end if;

  for v_enrollment in
    select e.id, e.signed_at, e.payment_plan_id, e.preferred_payment_method
      from public.enrollment_onboarding_items oi
      join public.enrollments e on e.id = oi.enrollment_id
     where oi.onboarding_session_id = v_session.id
  loop
    if exists (select 1 from public.installments where enrollment_id = v_enrollment.id and status <> 'cancelado') then
      -- Parcelas já geradas na assinatura: o plano fica como está.
      v_plan_id := v_enrollment.payment_plan_id;
    else
      v_plan_id := public.enrollment_plan_at_closing(v_enrollment.id, coalesce(v_enrollment.signed_at::date, public.local_today()));
      update public.enrollments set payment_plan_id = v_plan_id where id = v_enrollment.id;
      perform public.generate_installments(v_enrollment.id);
    end if;
    v_method := case
      when (select installments from public.payment_plans where id = v_plan_id) = 1 then 'pix'::public.payment_method
      else coalesce(v_enrollment.preferred_payment_method, p_method)
    end;
    if v_method is null then raise exception 'Escolha a forma de pagamento' using errcode = '22023'; end if;
    update public.enrollments set status = 'aguardando_pagamento', preferred_payment_method = v_method where id = v_enrollment.id;
    update public.installments set method = v_method where enrollment_id = v_enrollment.id and status = 'pendente';
    insert into public.enrollment_events(enrollment_id, code, title, body, actor, metadata)
    values(v_enrollment.id, 'PAYMENT_CHOICE_CONFIRMED', 'Forma de pagamento confirmada', 'Rematrícula concluída; aguardando a emissão da cobrança.', 'responsavel', jsonb_build_object('method', v_method, 'payment_plan_id', v_plan_id));
  end loop;
  update public.enrollment_onboarding_sessions set status = 'concluida', current_step = 5, completed_at = now(), last_opened_at = now() where id = v_session.id;
  return public.onboarding_open(p_token);
end $$;

-- onboarding_open: inclui valores por filho, opções de pagamento do dia e a
-- escolha já feita, para a etapa Valores e para o agente.
create or replace function public.onboarding_open(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session public.enrollment_onboarding_sessions; v_early_until date;
begin
  select * into v_session
    from public.enrollment_onboarding_sessions
   where token = trim(p_token) and status <> 'cancelada'
   for update;
  if not found then raise exception 'Jornada inválida ou expirada' using errcode = 'P0002'; end if;

  update public.enrollment_onboarding_sessions
     set last_opened_at = now(), updated_at = now()
   where id = v_session.id;

  v_early_until := public.rematricula_early_until(v_session.campaign_id);

  return jsonb_build_object(
    'token', v_session.token,
    'flow', v_session.flow,
    'status', v_session.status,
    'step', v_session.current_step,
    'campaign', (select name from public.campaigns where id = v_session.campaign_id),
    'guardian', case when v_session.guardian_id is null then null else (
      select jsonb_build_object('name', g.full_name, 'email', g.email, 'phone', g.phone)
        from public.guardians g where g.id = v_session.guardian_id
    ) end,
    'pricing', jsonb_build_object(
      'today', public.local_today(),
      'early_until', v_early_until,
      'early_active', v_session.flow = 'rematricula' and v_early_until is not null and public.local_today() <= v_early_until
    ),
    'values_confirmed', v_session.context ? 'values_confirmed_at',
    'payment_choice', v_session.context -> 'payment_choice',
    'payment_choices', case when v_session.flow = 'rematricula'
      then public.rematricula_payment_options(v_session.campaign_id, public.local_today()) else '[]'::jsonb end,
    'children', coalesce((
      select jsonb_agg(jsonb_build_object(
        'student_id', s.id,
        'name', s.full_name,
        'current_grade', current_grade.name,
        'target_grade_id', target_grade.id,
        'target_grade', target_grade.name,
        'eligible', (enrollment_case.id is null or enrollment_case.guardian_id = v_session.guardian_id)
          and target_grade.id is not null
          and public.campaign_amount_for_date(v_session.campaign_id, target_grade.id, public.local_today()) is not null,
        'eligibility_reason', case
          when enrollment_case.id is not null and enrollment_case.guardian_id <> v_session.guardian_id
            then 'A rematrícula deste aluno já foi iniciada por outro responsável. Fale com a secretaria.'
          when target_grade.id is null then 'Não foi possível identificar a próxima série deste aluno. Fale com a secretaria.'
          when public.campaign_amount_for_date(v_session.campaign_id, target_grade.id, public.local_today()) is null
            then 'A próxima série deste aluno ainda não tem valor configurado. Fale com a secretaria.'
          else null
        end,
        -- Valor vigente hoje; depois da assinatura, o valor travado.
        'amount_cents', case
          when enrollment_case.guardian_id = v_session.guardian_id and enrollment_case.signed_at is not null
            then enrollment_case.amount_cents
          else public.campaign_amount_for_date(v_session.campaign_id, target_grade.id, public.local_today())
        end,
        'full_amount_cents', offering.amount_cents,
        'early_amount_cents', case when v_session.flow = 'rematricula' then offering.early_amount_cents end,
        'selected', oi.enrollment_id is not null,
        'enrollment_id', case when enrollment_case.guardian_id = v_session.guardian_id then oi.enrollment_id else null end,
        'contract_token', cs.token,
        'contract_status', cs.status,
        'signed_at', cs.signed_at
      ) order by s.full_name)
        from public.student_guardians sg
        join public.students s on s.id = sg.student_id
        left join public.classes current_class on current_class.id = s.current_class_id
        left join public.grades current_grade on current_grade.id = current_class.grade_id
        left join lateral (
          select e.*
            from public.enrollments e
           where e.campaign_id = v_session.campaign_id
             and e.student_id = s.id
           limit 1
        ) enrollment_case on true
        left join public.grades target_grade
          on target_grade.id = coalesce(
            case when enrollment_case.guardian_id = v_session.guardian_id then enrollment_case.target_grade_id end,
            current_grade.next_grade_id
          )
        left join public.campaigns campaign on campaign.id = v_session.campaign_id
        left join public.grade_offerings offering
          on offering.academic_year = campaign.academic_year and offering.grade_id = target_grade.id
        left join public.enrollment_onboarding_items oi
          on oi.onboarding_session_id = v_session.id
         and oi.enrollment_id = case when enrollment_case.guardian_id = v_session.guardian_id then enrollment_case.id else null end
        left join lateral (
          select cs.*
            from public.contract_session_enrollments cse
            join public.contract_sessions cs on cs.id = cse.contract_session_id
           where cse.enrollment_id = oi.enrollment_id and cs.status <> 'cancelada'
           order by cs.created_at desc
           limit 1
        ) cs on true
       where sg.guardian_id = v_session.guardian_id
    ), '[]'::jsonb),
    'payment_options', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'name', p.name, 'description', p.description,
        'installments', p.installments, 'discount_pct', p.discount_pct,
        'due_dates', p.due_dates
      ) order by p.sort_order)
        from public.payment_plans p
       where p.campaign_id = v_session.campaign_id
         and p.active
         and (p.available_until is null or public.local_today() <= p.available_until)
    ), '[]'::jsonb)
  );
end $$;

revoke all on function public.rematricula_early_until(uuid), public.rematricula_payment_options(uuid, date), public.enrollment_plan_at_closing(uuid, date) from public, anon, authenticated;
grant execute on function public.rematricula_early_until(uuid), public.rematricula_payment_options(uuid, date), public.enrollment_plan_at_closing(uuid, date) to service_role;
revoke all on function public.onboarding_choose_payment_option(text, text) from public;
grant execute on function public.onboarding_choose_payment_option(text, text) to anon, authenticated;
revoke execute on function public.contract_finalize_signed_pdf(text, text, text, boolean, text, text, text) from public, anon, authenticated;
grant execute on function public.contract_finalize_signed_pdf(text, text, text, boolean, text, text, text) to service_role;
