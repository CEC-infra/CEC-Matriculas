-- Uma solicitação por matrícula assinada. O worker do provedor usa esta fila para
-- criar cobranças, preencher installments.payment_url/boleto_line e enviar o boleto.
create table public.payment_dispatches (
  id                  uuid primary key default gen_random_uuid(),
  enrollment_id       uuid not null references public.enrollments (id) on delete cascade,
  contract_session_id uuid references public.contract_sessions (id) on delete set null,
  status              text not null default 'pendente' check (status in ('pendente', 'processando', 'enviado', 'falhou', 'cancelado')),
  provider            text,
  attempts            smallint not null default 0 check (attempts >= 0),
  scheduled_for       timestamptz not null default now(),
  dispatched_at       timestamptz,
  last_error          text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (enrollment_id)
);
create index payment_dispatches_pending_idx on public.payment_dispatches (status, scheduled_for) where status in ('pendente', 'processando');

create or replace function public.contract_sessions_queue_payment_dispatch()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.status = 'assinada' and old.status is distinct from 'assinada' then
    insert into public.payment_dispatches (enrollment_id, contract_session_id)
    select cse.enrollment_id, new.id
      from public.contract_session_enrollments cse
     where cse.contract_session_id = new.id
    on conflict (enrollment_id) do update set
      contract_session_id = excluded.contract_session_id,
      status = case when public.payment_dispatches.status = 'falhou' then 'pendente' else public.payment_dispatches.status end,
      scheduled_for = case when public.payment_dispatches.status = 'falhou' then now() else public.payment_dispatches.scheduled_for end,
      last_error = case when public.payment_dispatches.status = 'falhou' then null else public.payment_dispatches.last_error end;
  end if;
  return null;
end $$;

create trigger contract_sessions_queue_payment_dispatch_on_signed
  after update of status on public.contract_sessions
  for each row execute function public.contract_sessions_queue_payment_dispatch();

alter table public.payment_dispatches enable row level security;
create policy "equipe lê despachos de cobrança" on public.payment_dispatches for select to authenticated using ((select public.is_staff()));

revoke execute on function public.contract_sessions_queue_payment_dispatch() from public, anon, authenticated;
