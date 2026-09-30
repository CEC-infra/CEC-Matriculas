-- Regras de pagamento 2027: sem descontos, sem boleto e sem multa/juros.
-- A quantidade de parcelas é travada pela data em que o contrato é assinado.

update public.payment_policies pp
   set cash_discount_pct = 0,
       sibling_discount_pct = 0,
       late_fee_pct = 0,
       monthly_interest_pct = 0,
       boleto_due_business_days = 0,
       accepted_methods = array['cartao'::public.payment_method, 'pix'::public.payment_method],
       max_installments = 3,
       last_due_date = '2027-01-20'::date
  from public.campaigns c
 where c.id = pp.campaign_id
   and c.academic_year = 2027;

update public.payment_plans p
       set name = case p.installments
         when 3 then 'Fechamento até 20/11'
         when 2 then 'Fechamento até 20/12'
         else 'Fechamento até 20/01'
       end,
       description = case p.installments
         when 3 then 'Contrato assinado até 20/11 · novembro, dezembro e janeiro'
         when 2 then 'Contrato assinado de 21/11 a 20/12 · dezembro e janeiro'
         else 'Contrato assinado de 21/12 a 20/01 · janeiro'
       end,
       discount_pct = 0,
       due_dates = case p.installments
         when 3 then array['2026-11-20'::date, '2026-12-20'::date, '2027-01-20'::date]
         when 2 then array['2026-12-20'::date, '2027-01-20'::date]
         else array['2027-01-20'::date]
       end,
       available_until = case p.installments
         when 3 then '2026-11-20'::date
         when 2 then '2026-12-20'::date
         else '2027-01-20'::date
       end,
       sort_order = case p.installments when 3 then 1 when 2 then 2 else 3 end
  from public.campaigns c
 where c.id = p.campaign_id
   and c.academic_year = 2027;

-- Não há desconto individual em novas matrículas. Contratos e pagamentos já
-- consolidados não são alterados para preservar o histórico financeiro.
update public.enrollments e
   set discount_pct = 0
  from public.campaigns c
 where c.id = e.campaign_id
   and c.academic_year = 2027
   and e.signed_at is null
   and not exists (
     select 1 from public.installments i
      where i.enrollment_id = e.id and i.status <> 'cancelado'
   );

create or replace function public.payment_plan_for_closing(
  p_campaign_id uuid,
  p_closed_on date default public.local_today()
)
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare
  v_installments smallint;
  v_plan_id uuid;
begin
  v_installments := case
    when p_closed_on <= '2026-11-20'::date then 3
    when p_closed_on <= '2026-12-20'::date then 2
    when p_closed_on <= '2027-01-20'::date then 1
    else null
  end;
  if v_installments is null then
    raise exception 'O prazo de pagamento desta campanha terminou em 20/01/2027' using errcode = 'P0001';
  end if;
  select p.id into v_plan_id
    from public.payment_plans p
   where p.campaign_id = p_campaign_id
     and p.installments = v_installments
     and p.active
   order by p.sort_order
   limit 1;
  if v_plan_id is null then
    raise exception 'A condição de pagamento desta campanha não está configurada' using errcode = 'P0001';
  end if;
  return v_plan_id;
end $$;

create or replace function public.generate_installments(p_enrollment_id uuid)
returns setof public.installments language plpgsql set search_path = '' as $$
declare
  v_e public.enrollments;
  v_plan public.payment_plans;
  v_total integer;
  v_base integer;
  v_offset integer;
  i integer;
begin
  select * into v_e from public.enrollments where id = p_enrollment_id for update;
  if not found then raise exception 'Matrícula não encontrada' using errcode = 'P0002'; end if;
  if v_e.payment_plan_id is null or v_e.amount_cents is null then raise exception 'Defina a condição de pagamento e o valor antes de gerar as parcelas' using errcode = 'P0001'; end if;
  if exists (select 1 from public.installments where enrollment_id = v_e.id and status <> 'cancelado') then raise exception 'As parcelas desta matrícula já foram geradas' using errcode = 'P0001'; end if;
  select * into v_plan from public.payment_plans where id = v_e.payment_plan_id;
  if not found then raise exception 'Condição de pagamento inválida' using errcode = 'P0001'; end if;

  v_total := v_e.amount_cents;
  v_base := v_total / v_plan.installments;
  v_offset := coalesce((select max(number) from public.installments where enrollment_id = v_e.id), 0);
  for i in 1 .. v_plan.installments loop
    insert into public.installments (enrollment_id, number, amount_cents, due_date)
    values (v_e.id, v_offset + i, v_base + case when i = 1 then v_total - v_base * v_plan.installments else 0 end, v_plan.due_dates[i]);
  end loop;
  return query select * from public.installments where enrollment_id = v_e.id and status <> 'cancelado' order by number;
end $$;

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
begin
  if p_method not in ('cartao'::public.payment_method, 'pix'::public.payment_method) then
    raise exception 'Escolha Cartão ou Pix para o pagamento' using errcode = '22023';
  end if;
  select * into v_session from public.enrollment_onboarding_sessions where token = p_token and status <> 'cancelada' for update;
  if not found then raise exception 'Jornada inválida ou expirada' using errcode = 'P0002'; end if;
  if exists (
    select 1 from public.enrollment_onboarding_items oi
      left join public.document_acceptances da on da.enrollment_id = oi.enrollment_id and da.status = 'assinado'
     where oi.onboarding_session_id = v_session.id group by oi.enrollment_id having count(da.id) = 0
  ) then raise exception 'Conclua todas as assinaturas antes de escolher o pagamento' using errcode = 'P0001'; end if;

  for v_enrollment in
    select e.id, e.signed_at
      from public.enrollment_onboarding_items oi
      join public.enrollments e on e.id = oi.enrollment_id
     where oi.onboarding_session_id = v_session.id
  loop
    v_plan_id := public.payment_plan_for_closing(v_session.campaign_id, coalesce(v_enrollment.signed_at::date, public.local_today()));
    update public.enrollments set payment_plan_id = v_plan_id, status = 'aguardando_pagamento' where id = v_enrollment.id;
    if not exists (select 1 from public.installments where enrollment_id = v_enrollment.id and status <> 'cancelado') then perform public.generate_installments(v_enrollment.id); end if;
    update public.installments set method = p_method where enrollment_id = v_enrollment.id and status = 'pendente';
    insert into public.enrollment_events(enrollment_id, code, title, body, actor, metadata)
    values(v_enrollment.id, 'PAYMENT_CHOICE_CONFIRMED', 'Forma de pagamento escolhida', 'Parcelamento definido pela data de assinatura; aguardando a cobrança.', 'responsavel', jsonb_build_object('method', p_method, 'payment_plan_id', v_plan_id));
  end loop;
  update public.enrollment_onboarding_sessions set status = 'concluida', current_step = 5, completed_at = now(), last_opened_at = now() where id = v_session.id;
  return public.onboarding_open(p_token);
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
    v_plan_id := public.payment_plan_for_closing(v_enrollment.campaign_id, public.local_today());
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

create or replace view public.v_campaign_finance with (security_invoker = true) as
select
  c.id as campaign_id,
  c.name as campaign_name,
  (select coalesce(sum(e.amount_cents), 0) from public.enrollments e where e.campaign_id = c.id)::bigint as previsto_cents,
  (select coalesce(sum(i.amount_cents), 0) from public.installments i join public.enrollments e on e.id = i.enrollment_id where e.campaign_id = c.id and e.signed_at is not null and i.status <> 'cancelado')::bigint as contratado_cents,
  (select coalesce(sum(coalesce(i.paid_amount_cents, i.amount_cents)), 0) from public.installments i join public.enrollments e on e.id = i.enrollment_id where e.campaign_id = c.id and i.status = 'pago')::bigint as recebido_cents,
  (select coalesce(sum(i.amount_cents), 0) from public.installments i join public.enrollments e on e.id = i.enrollment_id where e.campaign_id = c.id and i.status = 'vencido')::bigint as em_atraso_cents,
  (select count(*) from public.installments i join public.enrollments e on e.id = i.enrollment_id where e.campaign_id = c.id and i.status = 'vencido') as parcelas_vencidas,
  (select count(*) from public.enrollments e where e.campaign_id = c.id and e.signed_at is not null) as contratos_assinados,
  (select count(distinct i.enrollment_id) from public.installments i join public.enrollments e on e.id = i.enrollment_id where e.campaign_id = c.id and i.status = 'pago') as familias_pagantes
from public.campaigns c;

revoke execute on function public.payment_plan_for_closing(uuid, date) from public, anon, authenticated;
grant execute on function public.payment_plan_for_closing(uuid, date) to service_role;
revoke execute on function public.contract_finalize_signed_pdf(text, text, text, boolean, text, text, text) from public, anon, authenticated;
grant execute on function public.contract_finalize_signed_pdf(text, text, text, boolean, text, text, text) to service_role;
