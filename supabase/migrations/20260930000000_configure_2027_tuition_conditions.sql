-- Valores da matrícula 2027. O preço é definido no fechamento do contrato:
-- até 31/10/2026 vale a tabela de 2026; a partir de 01/11/2026 vale 2027.

alter table public.grade_offerings
  add column if not exists early_amount_cents integer check (early_amount_cents >= 0),
  add column if not exists early_amount_until date;

comment on column public.grade_offerings.early_amount_cents is 'Valor de matrícula válido até early_amount_until, antes da virada anual de preços.';
comment on column public.grade_offerings.early_amount_until is 'Último dia inclusivo de validade do valor antecipado de matrícula.';

update public.grades
   set name = case code
     when 'grupo_2' then 'Maternal G 2'
     when 'grupo_3' then 'Maternal G 3'
     when 'infantil_4' then 'G 4 (1º período)'
     when 'infantil_5' then 'G 5 (2º período)'
     else name
   end
 where code in ('grupo_2', 'grupo_3', 'infantil_4', 'infantil_5');

-- Apenas as séries cuja tabela foi informada ficam disponíveis para 2027.
-- Grupo 1 e 1ª série não recebem valor até que a escola os defina.
delete from public.grade_offerings o
 using public.grades g
 where o.grade_id = g.id
   and o.academic_year = 2027
   and g.code in ('grupo_1', 'serie_1');

with prices(code, early_amount_cents, amount_cents) as (
  values
    ('grupo_2',     61500, 68000),
    ('grupo_3',     61500, 68000),
    ('infantil_4',  68000, 75000),
    ('infantil_5',  68000, 75000),
    ('ano_1',       79000, 87000),
    ('ano_2',       79000, 87000),
    ('ano_3',       79000, 87000),
    ('ano_4',       79000, 87000),
    ('ano_5',       79000, 87000),
    ('ano_6',       82000, 92000),
    ('ano_7',       82000, 92000),
    ('ano_8',       82000, 92000),
    ('ano_9',       82000, 92000)
)
insert into public.grade_offerings (
  academic_year, grade_id, shifts, amount_cents, cash_amount_cents,
  early_amount_cents, early_amount_until, seats_total
)
select 2027, g.id, array['manha'::public.shift], p.amount_cents, null,
       p.early_amount_cents, '2026-10-31'::date, 0
  from prices p
  join public.grades g on g.code = p.code
on conflict (academic_year, grade_id) do update
  set amount_cents = excluded.amount_cents,
      cash_amount_cents = null,
      early_amount_cents = excluded.early_amount_cents,
      early_amount_until = excluded.early_amount_until,
      updated_at = now();

-- A rematrícula precisa permanecer aberta após outubro para permitir o
-- fechamento pelo valor 2027 e o parcelamento de novembro a janeiro.
update public.campaigns
   set ends_on = '2027-01-31'::date
 where name = 'Rematrícula 2027'
   and kind = 'rematricula'
   and academic_year = 2027;

create or replace function public.offering_amount_for_date(
  p_academic_year smallint,
  p_grade_id uuid,
  p_reference_date date default public.local_today()
)
returns integer language sql stable security definer set search_path = '' as $$
  select case
    when o.early_amount_cents is not null
      and o.early_amount_until is not null
      and p_reference_date <= o.early_amount_until
      then o.early_amount_cents
    else o.amount_cents
  end
  from public.grade_offerings o
  where o.academic_year = p_academic_year
    and o.grade_id = p_grade_id
$$;

create or replace function public.assign_current_enrollment_price()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_academic_year smallint;
  v_amount integer;
begin
  if new.signed_at is not null or new.target_grade_id is null then
    return new;
  end if;

  select c.academic_year into v_academic_year
    from public.campaigns c where c.id = new.campaign_id;
  v_amount := public.offering_amount_for_date(v_academic_year, new.target_grade_id, public.local_today());
  if v_amount is not null then
    new.amount_cents := v_amount;
  end if;
  return new;
end $$;

drop trigger if exists enrollments_assign_current_price on public.enrollments;
create trigger enrollments_assign_current_price
  before insert or update of campaign_id, target_grade_id on public.enrollments
  for each row execute function public.assign_current_enrollment_price();

create or replace function public.lock_enrollment_effective_amount(
  p_enrollment_id uuid,
  p_closed_on date default public.local_today()
)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  v_enrollment public.enrollments;
  v_academic_year smallint;
  v_amount integer;
begin
  select e.* into v_enrollment
    from public.enrollments e
   where e.id = p_enrollment_id
   for update of e;
  if not found then
    raise exception 'Matrícula não encontrada' using errcode = 'P0002';
  end if;
  select c.academic_year into v_academic_year
    from public.campaigns c where c.id = v_enrollment.campaign_id;

  if v_enrollment.signed_at is not null
     or exists (select 1 from public.installments i where i.enrollment_id = v_enrollment.id and i.status <> 'cancelado') then
    return v_enrollment.amount_cents;
  end if;

  v_amount := public.offering_amount_for_date(v_academic_year, v_enrollment.target_grade_id, p_closed_on);
  if v_amount is null then
    raise exception 'A série desta matrícula não possui valor configurado' using errcode = 'P0001';
  end if;
  update public.enrollments set amount_cents = v_amount where id = v_enrollment.id;
  return v_amount;
end $$;

-- Corrige jornadas de 2027 ainda não assinadas para que a cotação exibida hoje
-- use a tabela vigente, sem alterar contratos ou parcelas já consolidados.
update public.enrollments e
   set amount_cents = public.offering_amount_for_date(c.academic_year, e.target_grade_id, public.local_today())
  from public.campaigns c
 where c.id = e.campaign_id
   and c.academic_year = 2027
   and e.signed_at is null
   and not exists (select 1 from public.installments i where i.enrollment_id = e.id and i.status <> 'cancelado')
   and public.offering_amount_for_date(c.academic_year, e.target_grade_id, public.local_today()) is not null;

create or replace view public.v_grade_offerings with (security_invoker = true) as
select
  o.id                 as offering_id,
  o.academic_year,
  g.id                 as grade_id,
  g.name               as grade_name,
  g.sort_order,
  pg.name              as from_grade_name,
  o.shifts,
  o.amount_cents,
  o.cash_amount_cents,
  o.seats_total,
  coalesce(t.taken, 0)::int                              as seats_taken,
  greatest(o.seats_total - coalesce(t.taken, 0), 0)::int as seats_available,
  o.early_amount_cents,
  o.early_amount_until,
  public.offering_amount_for_date(o.academic_year, o.grade_id, public.local_today()) as current_amount_cents
from public.grade_offerings o
join public.grades g on g.id = o.grade_id
left join public.grades pg on pg.next_grade_id = g.id
left join lateral (
  select count(*) as taken
  from public.enrollments e
  join public.campaigns c on c.id = e.campaign_id
  where c.academic_year = o.academic_year
    and e.target_grade_id = o.grade_id
    and e.signed_at is not null
    and e.lost_at is null
) t on true;

create or replace function public.public_grade_offerings()
returns table (
  offering_id uuid,
  grade_id uuid,
  amount_cents integer,
  cash_amount_cents integer,
  seats_total smallint,
  early_amount_cents integer,
  early_amount_until date,
  grade_name text,
  sort_order smallint
) language sql stable security definer set search_path = '' as $$
  select o.id, o.grade_id,
         public.offering_amount_for_date(o.academic_year, o.grade_id, public.local_today()),
         o.cash_amount_cents, o.seats_total, o.early_amount_cents, o.early_amount_until,
         g.name, g.sort_order
    from public.grade_offerings o
    join public.grades g on g.id = o.grade_id
   where o.academic_year = 2027
     and exists (
       select 1 from public.campaigns c
        where c.academic_year = o.academic_year
          and c.status = 'ativa'
          and c.starts_on <= public.local_today()
          and (c.ends_on is null or c.ends_on >= public.local_today())
     )
   order by g.sort_order
$$;

revoke execute on function public.public_grade_offerings() from public;
grant execute on function public.public_grade_offerings() to anon, authenticated;

create or replace function public.contract_open(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session public.contract_sessions; v_out jsonb;
begin
  select * into v_session from public.contract_sessions where token = trim(p_token) and status not in ('cancelada', 'expirada') and expires_at > now();
  if not found then raise exception 'Link de contrato inválido ou expirado' using errcode = 'P0002'; end if;
  update public.contract_sessions set first_opened_at = coalesce(first_opened_at, now()), last_opened_at = now(), open_count = open_count + 1 where id = v_session.id;
  if v_session.first_opened_at is null then
    insert into public.enrollment_events(enrollment_id, code, title, body, actor, metadata)
    select cse.enrollment_id, 'CONTRACT_OPENED', 'Página de contrato visitada', 'A família acessou a página de assinatura.', 'responsavel', jsonb_build_object('contract_session_id', v_session.id)
      from public.contract_session_enrollments cse where cse.contract_session_id = v_session.id;
  end if;
  select jsonb_build_object(
    'status', v_session.status,
    'email_masked', regexp_replace(v_session.confirmation_email, '^(.{1,2}).*(@.*)$', '\\1***\\2'),
    'email_verified', v_session.verification_verified_at is not null,
    'verification_sent_at', v_session.verification_sent_at,
    'email_delivery_status', (select q.status from public.email_queue q where q.contract_session_id = v_session.id order by q.created_at desc limit 1),
    'expires_at', v_session.expires_at,
    'guardian', jsonb_build_object('name', g.full_name),
    'required_data', public.contract_required_data(v_session.id),
    'enrollments', coalesce(jsonb_agg(jsonb_build_object(
      'id', e.id, 'student_name', s.full_name, 'grade', gr.name, 'shift', e.target_shift,
      'amount_cents', case when e.signed_at is not null then e.amount_cents else public.offering_amount_for_date(c.academic_year, e.target_grade_id, public.local_today()) end,
      'payment_plan', pp.name,
      'contract_generated', da.generated_storage_path is not null and da.generated_document_hash is not null,
      'contract', jsonb_build_object('title', ddoc.title, 'version', ddoc.version)
    ) order by s.full_name), '[]'::jsonb)
  ) into v_out
    from public.contract_session_enrollments cse
    join public.enrollments e on e.id = cse.enrollment_id
    join public.campaigns c on c.id = e.campaign_id
    join public.students s on s.id = e.student_id
    join public.grades gr on gr.id = e.target_grade_id
    join public.guardians g on g.id = v_session.guardian_id
    left join public.payment_plans pp on pp.id = e.payment_plan_id
    left join lateral (
      select da.generated_storage_path, da.generated_document_hash
        from public.document_acceptances da
       where da.enrollment_id = e.id and da.contract_session_id = v_session.id
       order by da.generated_at desc nulls last, da.created_at desc
       limit 1
    ) da on true
    join lateral (
      select d.id, d.title, dv.version
        from public.campaign_documents cd
        join public.documents d on d.id = cd.document_id and d.kind = 'contrato'
        join public.document_versions dv on dv.document_id = d.id and dv.is_current
       where cd.campaign_id = e.campaign_id and (dv.grade_id is null or dv.grade_id = e.target_grade_id)
       order by case when dv.grade_id = e.target_grade_id then 0 else 1 end limit 1
    ) ddoc on true
   where cse.contract_session_id = v_session.id group by g.full_name;
  return v_out;
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
    select * into v_acceptance from public.document_acceptances da
     where da.enrollment_id = v_enrollment.id and da.contract_session_id = v_session.id
       and da.generated_storage_path is not null and da.generated_document_hash is not null
       and da.signed_storage_path is not null and da.signed_document_hash is not null for update;
    if not found then raise exception 'O PDF assinado deste contrato não foi encontrado' using errcode = 'P0001'; end if;
    update public.document_acceptances set status = 'assinado', provider = 'cec_assinatura_interna', signer_full_name = trim(p_signer_full_name), signer_email = v_session.confirmation_email, email_verified_at = v_session.verification_verified_at, signature_image_data = p_signature_image_data, signature_image_sha256 = v_signature_hash, document_hash = v_acceptance.signed_document_hash, completed_at = now(), ip = v_ip, user_agent = p_user_agent, device = p_device, updated_at = now() where id = v_acceptance.id;
    if v_enrollment.payment_plan_id is not null and not exists(select 1 from public.installments where enrollment_id = v_enrollment.id and status <> 'cancelado') then perform public.generate_installments(v_enrollment.id); end if;
    update public.enrollments set signed_at = now(), status = case when payment_plan_id is null then 'aguardando_pagamento' else status end where id = v_enrollment.id;
    insert into public.enrollment_events(enrollment_id, code, title, body, actor, metadata)
    values(v_enrollment.id, 'CONTRACT_SIGNED', 'Contrato assinado', 'PDF individual assinado após confirmação por e-mail.', 'responsavel', jsonb_build_object('contract_session_id', v_session.id, 'signature_sha256', v_signature_hash, 'document_sha256', v_acceptance.signed_document_hash, 'signed_pdf_at', v_acceptance.signed_pdf_at, 'effective_amount_cents', v_effective_amount));
  end loop;
  update public.contract_sessions set status = 'assinada', signed_at = now() where id = v_session.id;
  return jsonb_build_object('ok', true, 'signed_at', now());
end $$;

revoke execute on function public.lock_enrollment_effective_amount(uuid, date) from public, anon, authenticated;
grant execute on function public.lock_enrollment_effective_amount(uuid, date) to service_role;
revoke execute on function public.contract_finalize_signed_pdf(text, text, text, boolean, text, text, text) from public, anon, authenticated;
grant execute on function public.contract_finalize_signed_pdf(text, text, text, boolean, text, text, text) to service_role;
