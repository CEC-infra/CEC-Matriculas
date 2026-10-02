-- Dados de pagamento do Asaas por parcela e taxa do cartão repassada à família.
--
-- Cada cobrança guarda o que a família precisa para pagar sem abrir a página:
-- PDF do boleto, linha digitável e Pix copia e cola. A IA manda esses dados
-- pelo WhatsApp e a página mostra os botões de copiar/baixar.
--
-- Cartão: a escola não absorve a taxa do parcelamento. O valor cobrado no
-- cartão é o líquido acrescido da taxa, para a escola receber o valor cheio.
-- As taxas ficam em card_fees e devem refletir o contrato da conta no Asaas
-- (Minha conta → Taxas). Os valores iniciais são a tabela pública do Asaas.

alter table public.installments add column if not exists bank_slip_url text;

create table if not exists public.card_fees (
  installments  smallint primary key check (installments between 1 and 3),
  percent       numeric(5, 2) not null check (percent >= 0 and percent < 100),
  fixed_cents   integer not null default 0 check (fixed_cents >= 0),
  updated_at    timestamptz not null default now()
);
comment on table public.card_fees is 'Taxa do Asaas por número de parcelas no cartão, repassada à família. Conferir com o contrato da conta.';

insert into public.card_fees (installments, percent, fixed_cents) values
  (1, 2.99, 49),
  (2, 3.49, 49),
  (3, 3.49, 49)
on conflict (installments) do nothing;

alter table public.card_fees enable row level security;
create policy "taxas do cartão são públicas" on public.card_fees for select to anon, authenticated using (true);
create policy "equipe ajusta taxas do cartão" on public.card_fees for all to authenticated
  using ((select public.is_staff())) with check ((select public.is_staff()));

-- Valor bruto no cartão para a escola receber p_net_cents depois da taxa.
create or replace function public.card_total_cents(p_net_cents integer, p_installments integer)
returns integer language sql stable security definer set search_path = '' as $$
  select ceil((p_net_cents + f.fixed_cents) / (1 - f.percent / 100))::integer
    from public.card_fees f
   where f.installments = greatest(1, least(3, p_installments))
$$;

-- Quanto a família paga no cartão, pelo plano escolhido (1x, 2x ou 3x).
create or replace function public.onboarding_card_quote(p_token text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_session public.enrollment_onboarding_sessions; v_net integer; v_count integer; v_total integer;
begin
  select * into v_session from public.enrollment_onboarding_sessions
   where token = trim(p_token) and guardian_id is not null and status <> 'cancelada';
  if not found then raise exception 'Jornada inválida ou expirada' using errcode = 'P0002'; end if;
  select coalesce(sum(i.amount_cents), 0), count(distinct i.due_date)
    into v_net, v_count
    from public.enrollment_onboarding_items oi join public.installments i on i.enrollment_id = oi.enrollment_id
   where oi.onboarding_session_id = v_session.id and i.status = 'pendente';
  if v_net = 0 then return null; end if;
  v_count := greatest(1, least(3, v_count));
  v_total := public.card_total_cents(v_net, v_count);
  return jsonb_build_object(
    'installments', v_count,
    'net_cents', v_net,
    'total_cents', v_total,
    'fee_cents', v_total - v_net,
    'installment_cents', ceil(v_total::numeric / v_count)::integer
  );
end $$;

revoke all on function public.card_total_cents(integer, integer), public.onboarding_card_quote(text) from public;
grant execute on function public.card_total_cents(integer, integer) to service_role;
grant execute on function public.onboarding_card_quote(text) to anon, authenticated, service_role;

-- Cobranças da família agrupadas por vencimento, agora com os dados de
-- pagamento (PDF, linha digitável e Pix) para a página e para a IA.
create or replace function public.onboarding_charges(p_session_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(c order by c ->> 'due_date'), '[]'::jsonb) from (
    select jsonb_build_object(
      'due_date', i.due_date,
      'amount_cents', sum(i.amount_cents),
      'method', max(i.method::text),
      'payment_url', max(i.payment_url),
      'bank_slip_url', max(i.bank_slip_url),
      'boleto_line', max(i.boleto_line),
      'pix_code', max(i.pix_code),
      'provider_charge_id', i.provider_charge_id,
      'status', case when bool_and(i.status = 'pago') then 'pago' when bool_or(i.status = 'vencido') then 'vencido' else 'pendente' end
    ) c
      from public.enrollment_onboarding_items oi join public.installments i on i.enrollment_id = oi.enrollment_id
     where oi.onboarding_session_id = p_session_id and i.status <> 'cancelado'
     group by i.due_date, i.provider_charge_id
  ) x
$$;
