-- Regras de negócio: helpers, gatilhos da jornada e rotinas da fila.

-- Helpers -------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['profiles', 'grade_offerings', 'campaigns', 'payment_policies', 'guardians', 'students',
                           'enrollments', 'document_acceptances', 'installments', 'whatsapp_instances',
                           'conversations', 'message_templates', 'message_queue']
  loop
    execute format('create trigger %I before update on public.%I for each row execute function public.set_updated_at()',
                   t || '_set_updated_at', t);
  end loop;
end $$;

create or replace function public.local_today()
returns date language sql stable set search_path = '' as $$
  select (now() at time zone 'America/Fortaleza')::date
$$;

create or replace function public.local_day_start()
returns timestamptz language sql stable set search_path = '' as $$
  select date_trunc('day', now() at time zone 'America/Fortaleza') at time zone 'America/Fortaleza'
$$;

-- "(83) 99812-4471" → "+5583998124471"
create or replace function public.normalize_phone_br(raw text)
returns text language sql immutable set search_path = '' as $$
  select case
    when raw ~ '^\s*\+' and d ~ '^[1-9][0-9]{7,14}$' then '+' || d
    when d ~ '^55[0-9]{10,11}$' then '+' || d
    when d ~ '^[0-9]{10,11}$' then '+55' || d
  end
  from (select regexp_replace(coalesce(raw, ''), '\D', '', 'g') as d) s
$$;

create or replace function public.format_brl(cents bigint)
returns text language sql immutable set search_path = '' as $$
  select 'R$ ' || translate(to_char(cents / 100.0, 'FM999,999,990.00'), ',.', '.,')
$$;

-- Ordem das etapas do funil; status de perda não têm posição.
create or replace function public.journey_rank(s public.journey_status)
returns smallint language sql immutable set search_path = '' as $$
  select (case s
    when 'pre_matricula'         then 0
    when 'em_fila'               then 0
    when 'contatada'             then 1
    when 'conversando'           then 2
    when 'precisa_humano'        then 2
    when 'link_enviado'          then 3
    when 'link_aberto'           then 4
    when 'formulario_iniciado'   then 5
    when 'aguardando_assinatura' then 5
    when 'aguardando_pagamento'  then 6
    when 'pagamento_vencido'     then 6
    when 'concluida'             then 7
  end)::smallint
$$;

create or replace function public.journey_status_label(s public.journey_status)
returns text language sql immutable set search_path = '' as $$
  select case s
    when 'pre_matricula'         then 'Pré-matrícula'
    when 'em_fila'               then 'Em fila'
    when 'contatada'             then 'Contatada'
    when 'conversando'           then 'Conversando'
    when 'precisa_humano'        then 'Precisa de humano'
    when 'link_enviado'          then 'Link enviado'
    when 'link_aberto'           then 'Link aberto'
    when 'formulario_iniciado'   then 'Formulário iniciado'
    when 'aguardando_assinatura' then 'Aguardando assinatura'
    when 'aguardando_pagamento'  then 'Aguardando pagamento'
    when 'pagamento_vencido'     then 'Pagamento vencido'
    when 'concluida'             then 'Concluída'
    when 'sem_interesse'         then 'Sem interesse'
    when 'opt_out'               then 'Opt-out'
    when 'fora_campanha'         then 'Fora da campanha'
  end
$$;

create or replace function public.current_profile_id()
returns uuid language sql stable set search_path = '' as $$
  select p.id from public.profiles p where p.id = auth.uid()
$$;

-- Perfil da equipe criado no cadastro, sempre inativo.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, full_name, active)
  values (new.id,
          coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''), split_part(new.email, '@', 1), 'Usuário'),
          false)
  on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Jornada: marcos do funil e linha do tempo --------------------------------

-- Preenche os marcos de forma cumulativa: quem chegou a "link aberto" também conta como contatada, respondeu etc.
create or replace function public.enrollments_track_status()
returns trigger language plpgsql set search_path = '' as $$
declare r smallint := public.journey_rank(new.status);
begin
  if tg_op = 'UPDATE' and new.status is not distinct from old.status then
    return new;
  end if;
  if r >= 1 then new.contacted_at    := coalesce(new.contacted_at, now()); end if;
  if r >= 2 then new.replied_at      := coalesce(new.replied_at, now()); end if;
  if r >= 3 then new.link_sent_at    := coalesce(new.link_sent_at, now()); end if;
  if r >= 4 then new.link_opened_at  := coalesce(new.link_opened_at, now()); end if;
  if r >= 5 then new.form_started_at := coalesce(new.form_started_at, now()); end if;
  if r >= 6 then new.signed_at       := coalesce(new.signed_at, now()); end if;
  if r >= 7 then
    new.paid_at      := coalesce(new.paid_at, now());
    new.completed_at := coalesce(new.completed_at, now());
  end if;
  if new.status in ('sem_interesse', 'opt_out', 'fora_campanha') then
    new.lost_at := coalesce(new.lost_at, now());
  else
    new.lost_at := null;
  end if;
  return new;
end $$;

create trigger enrollments_track_status
  before insert or update of status on public.enrollments
  for each row execute function public.enrollments_track_status();

create or replace function public.enrollments_log_status()
returns trigger language plpgsql set search_path = '' as $$
begin
  insert into public.enrollment_events (enrollment_id, code, title, actor, actor_id, metadata)
  values (
    new.id,
    case when tg_op = 'INSERT' then 'CREATED' else 'STATUS_CHANGED' end,
    case when tg_op = 'INSERT' then 'Entrou na campanha · ' else 'Status alterado para ' end
      || public.journey_status_label(new.status),
    (case when auth.uid() is null then 'sistema' else 'equipe' end)::public.actor_kind,
    public.current_profile_id(),
    case when tg_op = 'INSERT'
      then jsonb_build_object('status', new.status, 'origem', new.origin)
      else jsonb_build_object('de', old.status, 'para', new.status)
    end
  );
  return null;
end $$;

create trigger enrollments_log_insert
  after insert on public.enrollments
  for each row execute function public.enrollments_log_status();

create trigger enrollments_log_status
  after update of status on public.enrollments
  for each row when (old.status is distinct from new.status)
  execute function public.enrollments_log_status();

-- Recalcula assinatura/pagamento. Regra de "matriculado": todos os documentos obrigatórios
-- da campanha assinados/aceitos + ao menos uma parcela paga.
create or replace function public.recompute_enrollment_progress(p_enrollment_id uuid)
returns void language plpgsql set search_path = '' as $$
declare
  v_e             public.enrollments;
  v_required      integer;
  v_done          integer;
  v_pending_docs  integer;
  v_total         integer;
  v_paid          integer;
  v_overdue       integer;
  v_first_paid    timestamptz;
  v_signed        boolean;
  v_new           public.journey_status;
begin
  select * into v_e from public.enrollments where id = p_enrollment_id for update;
  if not found or v_e.status in ('sem_interesse', 'opt_out', 'fora_campanha') then
    return;
  end if;

  select count(*),
         count(*) filter (where exists (
           select 1
           from public.document_acceptances a
           join public.document_versions v on v.id = a.document_version_id
           where a.enrollment_id = v_e.id and v.document_id = d.id and a.status in ('assinado', 'aceito')))
    into v_required, v_done
  from public.campaign_documents cd
  join public.documents d on d.id = cd.document_id
  where cd.campaign_id = v_e.campaign_id
    and d.requirement in ('assinatura_obrigatoria', 'aceite_obrigatorio');

  select count(*) into v_pending_docs
  from public.document_acceptances a
  where a.enrollment_id = v_e.id and a.status in ('pendente', 'enviado');

  select count(*),
         count(*) filter (where i.status = 'pago'),
         count(*) filter (where i.status = 'vencido'),
         min(i.paid_at) filter (where i.status = 'pago')
    into v_total, v_paid, v_overdue, v_first_paid
  from public.installments i
  where i.enrollment_id = v_e.id and i.status <> 'cancelado';

  v_signed := (v_required > 0 and v_done = v_required) or (v_required = 0 and v_total > 0);

  v_new := case
    when v_signed and v_overdue > 0 then 'pagamento_vencido'::public.journey_status
    when v_signed and v_paid > 0    then 'concluida'::public.journey_status
    when v_signed                   then 'aguardando_pagamento'::public.journey_status
    when v_pending_docs > 0 and coalesce(public.journey_rank(v_e.status) <= 5, false)
                                    then 'aguardando_assinatura'::public.journey_status
    else v_e.status
  end;

  update public.enrollments
     set status       = v_new,
         paid_at      = coalesce(paid_at, v_first_paid),
         signed_at    = case when v_signed then coalesce(signed_at, now()) else signed_at end,
         completed_at = case when v_signed and v_paid > 0 then coalesce(completed_at, now()) else completed_at end
   where id = v_e.id
     and (status is distinct from v_new
          or (v_first_paid is not null and paid_at is null)
          or (v_signed and signed_at is null)
          or (v_signed and v_paid > 0 and completed_at is null));
end $$;

-- Documentos ----------------------------------------------------------------

create or replace function public.document_acceptances_before()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.status in ('assinado', 'aceito') then new.completed_at := coalesce(new.completed_at, now()); end if;
  if new.status = 'enviado' then new.sent_at := coalesce(new.sent_at, now()); end if;
  return new;
end $$;

create trigger document_acceptances_before
  before insert or update on public.document_acceptances
  for each row execute function public.document_acceptances_before();

create or replace function public.document_acceptances_after()
returns trigger language plpgsql set search_path = '' as $$
declare v_doc text;
begin
  if tg_op <> 'DELETE' and (tg_op = 'INSERT' or new.status is distinct from old.status) then
    select d.title || ' · ' || v.version into v_doc
    from public.document_versions v join public.documents d on d.id = v.document_id
    where v.id = new.document_version_id;

    insert into public.enrollment_events (enrollment_id, code, title, body, actor, metadata)
    values (
      new.enrollment_id,
      case new.status
        when 'assinado' then 'SIGNED'           when 'aceito'   then 'TERMS_ACCEPTED'
        when 'enviado'  then 'SIGNATURE_PENDING' when 'recusado' then 'SIGNATURE_DECLINED'
        when 'expirado' then 'SIGNATURE_EXPIRED' else 'DOCUMENT_CREATED'
      end,
      case new.status
        when 'assinado' then 'Documento assinado'  when 'aceito'   then 'Termos aceitos'
        when 'enviado'  then 'Assinatura pendente' when 'recusado' then 'Assinatura recusada'
        when 'expirado' then 'Assinatura expirada' else 'Documento gerado'
      end,
      v_doc || coalesce(' · IP ' || host(new.ip), ''),
      (case when new.status in ('assinado', 'aceito', 'recusado') then 'responsavel' else 'sistema' end)::public.actor_kind,
      jsonb_build_object('document_version_id', new.document_version_id, 'provider', new.provider)
    );
  end if;
  perform public.recompute_enrollment_progress(coalesce(new.enrollment_id, old.enrollment_id));
  return null;
end $$;

create trigger document_acceptances_after
  after insert or update or delete on public.document_acceptances
  for each row execute function public.document_acceptances_after();

-- Parcelas ------------------------------------------------------------------

create or replace function public.installments_before()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.status = 'pago' then
    new.paid_at           := coalesce(new.paid_at, now());
    new.paid_amount_cents := coalesce(new.paid_amount_cents, new.amount_cents);
  end if;
  return new;
end $$;

create trigger installments_before
  before insert or update on public.installments
  for each row execute function public.installments_before();

create or replace function public.installments_after()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and new.status is distinct from old.status and new.status in ('pago', 'vencido', 'estornado') then
    insert into public.enrollment_events (enrollment_id, code, title, body, actor, metadata)
    values (
      new.enrollment_id,
      case new.status when 'pago' then 'PAYMENT_CONFIRMED' when 'vencido' then 'PAYMENT_OVERDUE' else 'PAYMENT_REFUNDED' end,
      'Parcela ' || new.number || case new.status when 'pago' then ' paga' when 'vencido' then ' vencida' else ' estornada' end,
      public.format_brl(coalesce(new.paid_amount_cents, new.amount_cents))
        || coalesce(' · ' || new.method::text, '') || ' · vencimento ' || to_char(new.due_date, 'DD/MM/YYYY'),
      'sistema',
      jsonb_build_object('installment_id', new.id, 'provider', new.provider)
    );
  end if;
  perform public.recompute_enrollment_progress(coalesce(new.enrollment_id, old.enrollment_id));
  return null;
end $$;

create trigger installments_after
  after insert or update or delete on public.installments
  for each row execute function public.installments_after();

-- Gera as parcelas a partir do plano escolhido; o resto da divisão fica na 1ª parcela.
create or replace function public.generate_installments(p_enrollment_id uuid)
returns setof public.installments language plpgsql set search_path = '' as $$
declare
  v_e       public.enrollments;
  v_plan    public.payment_plans;
  v_total   integer;
  v_base    integer;
  v_offset  integer;
  i         integer;
begin
  select * into v_e from public.enrollments where id = p_enrollment_id for update;
  if not found then
    raise exception 'Matrícula não encontrada' using errcode = 'P0002';
  end if;
  if v_e.payment_plan_id is null or v_e.amount_cents is null then
    raise exception 'Defina a condição de pagamento e o valor antes de gerar as parcelas' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.installments where enrollment_id = v_e.id and status <> 'cancelado') then
    raise exception 'As parcelas desta matrícula já foram geradas' using errcode = 'P0001';
  end if;

  select * into v_plan from public.payment_plans where id = v_e.payment_plan_id;
  v_total  := round(v_e.amount_cents * (1 - v_plan.discount_pct / 100) * (1 - v_e.discount_pct / 100));
  v_base   := v_total / v_plan.installments;
  v_offset := coalesce((select max(number) from public.installments where enrollment_id = v_e.id), 0);

  for i in 1 .. v_plan.installments loop
    insert into public.installments (enrollment_id, number, amount_cents, due_date)
    values (v_e.id, v_offset + i,
            v_base + case when i = 1 then v_total - v_base * v_plan.installments else 0 end,
            v_plan.due_dates[i]);
  end loop;

  return query
    select * from public.installments
    where enrollment_id = v_e.id and status <> 'cancelado'
    order by number;
end $$;

create or replace function public.mark_overdue_installments()
returns integer language plpgsql set search_path = '' as $$
declare n integer;
begin
  update public.installments
     set status = 'vencido'
   where status = 'pendente' and due_date < public.local_today();
  get diagnostics n = row_count;
  return n;
end $$;

-- Links individuais ---------------------------------------------------------

-- Revoga o link ativo e emite um novo token.
create or replace function public.create_enrollment_link(p_enrollment_id uuid)
returns text language plpgsql set search_path = '' as $$
declare
  v_ttl    smallint;
  v_token  text;
begin
  select c.link_ttl_days into v_ttl
  from public.enrollments e join public.campaigns c on c.id = e.campaign_id
  where e.id = p_enrollment_id;
  if not found then
    raise exception 'Matrícula não encontrada' using errcode = 'P0002';
  end if;

  update public.enrollment_links set revoked_at = now()
   where enrollment_id = p_enrollment_id and revoked_at is null;

  insert into public.enrollment_links (enrollment_id, expires_at)
  values (p_enrollment_id, now() + make_interval(days => v_ttl))
  returning token into v_token;

  return v_token;
end $$;

create or replace function public.enrollment_links_sent()
returns trigger language plpgsql set search_path = '' as $$
begin
  update public.enrollments
     set status = 'link_enviado'
   where id = new.enrollment_id and coalesce(public.journey_rank(status) < 3, false);

  insert into public.enrollment_events (enrollment_id, code, title, body, actor, metadata)
  values (new.enrollment_id, 'LINK_SENT', 'Link enviado', 'Token individual enviado ao responsável.', 'ia',
          jsonb_build_object('link_id', new.id));
  return null;
end $$;

create trigger enrollment_links_sent_on_insert
  after insert on public.enrollment_links
  for each row when (new.sent_at is not null)
  execute function public.enrollment_links_sent();

create trigger enrollment_links_sent_on_update
  after update of sent_at on public.enrollment_links
  for each row when (old.sent_at is null and new.sent_at is not null)
  execute function public.enrollment_links_sent();

-- Opt-out -------------------------------------------------------------------

create or replace function public.guardians_opt_out()
returns trigger language plpgsql set search_path = '' as $$
begin
  update public.message_queue
     set status = 'cancelada', last_error = 'Opt-out do responsável'
   where guardian_id = new.id and status in ('pendente', 'processando');

  update public.enrollments
     set status = 'opt_out',
         automation_paused = true,
         lost_reason = coalesce(lost_reason, 'Opt-out solicitado pelo responsável')
   where guardian_id = new.id
     and completed_at is null
     and status not in ('sem_interesse', 'opt_out', 'fora_campanha');

  update public.conversations
     set handler = 'encerrada', closed_at = coalesce(closed_at, now())
   where guardian_id = new.id;
  return null;
end $$;

create trigger guardians_opt_out
  after update of opted_out_at on public.guardians
  for each row when (old.opted_out_at is null and new.opted_out_at is not null)
  execute function public.guardians_opt_out();

-- Conversas e handoff -------------------------------------------------------

create or replace function public.messages_after_insert()
returns trigger language plpgsql set search_path = '' as $$
declare v_enrollment uuid;
begin
  update public.conversations
     set last_message_at      = new.created_at,
         last_message_preview = left(coalesce(new.body, '[mídia]'), 140),
         unread_count         = unread_count + case when new.direction = 'entrada' then 1 else 0 end
   where id = new.conversation_id
  returning enrollment_id into v_enrollment;

  if new.direction = 'entrada' and v_enrollment is not null then
    update public.enrollments
       set status = 'conversando'
     where id = v_enrollment and status in ('pre_matricula', 'em_fila', 'contatada');
  end if;
  return null;
end $$;

create trigger messages_after_insert
  after insert on public.messages
  for each row execute function public.messages_after_insert();

create or replace function public.conversations_handler_change()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.enrollment_id is null then
    return null;
  end if;

  if new.handler = 'humano' then
    update public.enrollments
       set automation_paused = true, assigned_to = coalesce(new.assigned_to, assigned_to)
     where id = new.enrollment_id;
    insert into public.enrollment_events (enrollment_id, code, title, body, actor, actor_id)
    values (new.enrollment_id, 'HANDOFF_HUMAN', 'Conversa assumida pela equipe',
            'A IA para de responder até o atendimento ser devolvido.', 'equipe', public.current_profile_id());
  elsif new.handler = 'ia' and old.handler = 'humano' then
    update public.enrollments set automation_paused = false where id = new.enrollment_id;
    insert into public.enrollment_events (enrollment_id, code, title, actor, actor_id)
    values (new.enrollment_id, 'HANDOFF_AI', 'Atendimento devolvido para a IA', 'equipe', public.current_profile_id());
  end if;
  return null;
end $$;

create trigger conversations_handler_change
  after update of handler on public.conversations
  for each row when (old.handler is distinct from new.handler)
  execute function public.conversations_handler_change();

-- Fila de mensagens ---------------------------------------------------------

create or replace function public.message_queue_before()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.status = 'enviada' then
    new.sent_at   := coalesce(new.sent_at, now());
    new.locked_at := null;
  end if;
  return new;
end $$;

create trigger message_queue_before
  before insert or update on public.message_queue
  for each row execute function public.message_queue_before();

create or replace function public.message_queue_sent()
returns trigger language plpgsql set search_path = '' as $$
declare v_template text;
begin
  update public.whatsapp_instances set last_sent_at = new.sent_at where connected;

  if new.enrollment_id is null then
    return null;
  end if;

  select name into v_template from public.message_templates where id = new.template_id;

  update public.enrollments
     set attempts = greatest(attempts, coalesce(new.attempt_number, attempts + 1)),
         status   = case when status = 'em_fila' then 'contatada'::public.journey_status else status end
   where id = new.enrollment_id;

  insert into public.enrollment_events (enrollment_id, code, title, body, actor, metadata)
  values (new.enrollment_id, 'MSG_SENT', coalesce(v_template, 'Mensagem enviada'),
          'Tentativa ' || coalesce(new.attempt_number::text, '—') || ' da régua', 'ia',
          jsonb_build_object('queue_id', new.id, 'message_id', new.message_id));
  return null;
end $$;

create trigger message_queue_sent
  after update of status on public.message_queue
  for each row when (new.status = 'enviada' and old.status is distinct from new.status)
  execute function public.message_queue_sent();

-- Régua: enfileira a próxima tentativa de quem não respondeu dentro do prazo do template.
create or replace function public.schedule_follow_ups()
returns integer language plpgsql set search_path = '' as $$
declare n integer;
begin
  insert into public.message_queue (campaign_id, enrollment_id, guardian_id, template_id, attempt_number, scheduled_for)
  select e.campaign_id, e.id, e.guardian_id, t.id, t.attempt_number, now()
  from public.enrollments e
  join public.campaigns c on c.id = e.campaign_id
  join public.guardians g on g.id = e.guardian_id
  join public.message_templates t
    on t.campaign_id = e.campaign_id and t.active and t.attempt_number = e.attempts + 1
  where c.status = 'ativa'
    and not c.queue_paused
    and e.attempts < c.max_attempts
    and not e.automation_paused
    and e.completed_at is null
    and e.status in ('pre_matricula', 'em_fila', 'contatada', 'link_enviado', 'link_aberto', 'formulario_iniciado')
    and g.opted_out_at is null
    and not exists (
      select 1 from public.message_queue q
      where q.enrollment_id = e.id and q.status in ('pendente', 'processando'))
    and (e.attempts = 0 or exists (
      select 1 from public.message_queue q
      where q.enrollment_id = e.id and q.status = 'enviada' and q.attempt_number = e.attempts
        and q.sent_at <= now() - make_interval(hours => t.wait_hours)))
    and not exists (
      select 1 from public.conversations cv
      join public.messages m on m.conversation_id = cv.id
      where cv.guardian_id = e.guardian_id and m.direction = 'entrada'
        and m.created_at > now() - make_interval(hours => t.wait_hours))
  on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end $$;

-- Worker de envio: reserva itens respeitando janela, tetos por hora/dia, pausa e conexão.
-- Itens presos em "processando" há mais de 10 min voltam a ser elegíveis (fila não perde nada).
create or replace function public.claim_message_batch(p_limit integer default 1)
returns setof public.message_queue language sql security definer set search_path = '' as $$
  with eligible as (
    select q.id
    from public.message_queue q
    join public.campaigns c on c.id = q.campaign_id
    join public.guardians g on g.id = q.guardian_id
    left join public.enrollments e on e.id = q.enrollment_id
    where (q.status = 'pendente' or (q.status = 'processando' and q.locked_at < now() - interval '10 minutes'))
      and q.scheduled_for <= now()
      and c.status = 'ativa'
      and not c.queue_paused
      and g.opted_out_at is null
      and not coalesce(e.automation_paused, false)
      and (now() at time zone 'America/Fortaleza')::time between c.send_window_start and c.send_window_end
      and exists (select 1 from public.whatsapp_instances w where w.connected and not w.paused)
      and (select count(*) from public.message_queue s
           where s.campaign_id = c.id and s.status = 'enviada' and s.sent_at >= now() - interval '1 hour') < c.hourly_cap
      and (select count(*) from public.message_queue s
           where s.campaign_id = c.id and s.status = 'enviada' and s.sent_at >= public.local_day_start()) < c.daily_cap
    order by q.scheduled_for
    limit greatest(p_limit, 1)
    for update of q skip locked
  )
  update public.message_queue q
     set status = 'processando', locked_at = now()
    from eligible
   where q.id = eligible.id
  returning q.*;
$$;
