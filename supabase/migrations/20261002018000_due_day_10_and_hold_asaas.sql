-- 1) Vencimentos passam do dia 20 para o dia 10 do mês.
-- 2) Pagamento online fica em espera: a família escolhe a forma de pagamento,
--    a matrícula fica concluída aguardando pagamento e a escola envia o link
--    depois. As cobranças geradas no Asaas sandbox para famílias reais saem
--    das parcelas (eram de teste) e os avisos com esses links não são enviados.

-- Planos: datas e nomes
update public.payment_plans
   set due_dates = (select array_agg(make_date(extract(year from d)::int, extract(month from d)::int, 10) order by d)
                      from unnest(due_dates) d),
       name = replace(name, '20/', '10/')
 where exists (select 1 from unnest(due_dates) d where extract(day from d) = 20);

-- Parcelas ainda não pagas
update public.installments
   set due_date = make_date(extract(year from due_date)::int, extract(month from due_date)::int, 10)
 where status = 'pendente' and extract(day from due_date) = 20;

-- Cobranças do sandbox saem das parcelas: o envio real gera outras.
update public.installments
   set provider = null, provider_charge_id = null, payment_url = null,
       bank_slip_url = null, boleto_line = null, pix_code = null
 where status = 'pendente' and provider = 'asaas';

update public.guardians set asaas_customer_id = null where asaas_customer_id is not null;

-- Avisos "sua cobrança está pronta" com link do sandbox não saem.
update public.message_queue
   set status = 'cancelada', last_error = 'Link do Asaas sandbox: pagamento online em espera'
 where status in ('pendente', 'processando') and body like 'Sua cobrança no %';

-- Prazos de fechamento por plano, agora no dia 10
CREATE OR REPLACE FUNCTION public.payment_plan_for_closing(p_campaign_id uuid, p_closed_on date DEFAULT local_today())
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_installments smallint;
  v_plan_id uuid;
  v_campaign_kind public.campaign_kind;
begin
  select c.kind into v_campaign_kind from public.campaigns c where c.id = p_campaign_id;
  v_installments := case
    when v_campaign_kind = 'rematricula'::public.campaign_kind and p_closed_on <= '2026-10-31'::date then 3
    when v_campaign_kind = 'rematricula'::public.campaign_kind and p_closed_on <= '2027-01-10'::date then 1
    when v_campaign_kind <> 'rematricula'::public.campaign_kind and p_closed_on <= '2026-11-10'::date then 3
    when v_campaign_kind <> 'rematricula'::public.campaign_kind and p_closed_on <= '2026-12-10'::date then 2
    when v_campaign_kind <> 'rematricula'::public.campaign_kind and p_closed_on <= '2027-01-10'::date then 1
    else null
  end;
  if v_installments is null then
    raise exception 'O prazo de pagamento desta campanha terminou em 10/01/2027' using errcode = 'P0001';
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
end $function$;
