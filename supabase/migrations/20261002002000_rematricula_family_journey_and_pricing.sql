-- Rematrícula 2027: uma jornada segura por família, preço coerente em todas
-- as telas e proteção contra a troca silenciosa de responsável da matrícula.
--
-- Esta migração é aditiva. Aplique-a ANTES de publicar a versão correspondente
-- do agente, pois ele passa a chamar create_rematricula_onboarding_link().

create or replace function public.campaign_amount_for_date(
  p_campaign_id uuid,
  p_grade_id uuid,
  p_reference_date date default public.local_today()
)
returns integer language sql stable security definer set search_path = '' as $$
  select case
    -- O valor antecipado até 31/10 é benefício de rematrícula. Matrícula nova
    -- sempre usa a tabela cheia, mesmo que a oferta tenha uma cotação cedo.
    when c.kind = 'rematricula'::public.campaign_kind
      then public.offering_amount_for_date(c.academic_year, p_grade_id, p_reference_date)
    else o.amount_cents
  end
  from public.campaigns c
  join public.grade_offerings o
    on o.academic_year = c.academic_year
   and o.grade_id = p_grade_id
 where c.id = p_campaign_id
$$;

create or replace function public.assign_current_enrollment_price()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_amount integer;
begin
  if new.signed_at is not null or new.target_grade_id is null then return new; end if;
  v_amount := public.campaign_amount_for_date(new.campaign_id, new.target_grade_id, public.local_today());
  if v_amount is not null then new.amount_cents := v_amount; end if;
  return new;
end $$;

create or replace function public.lock_enrollment_effective_amount(
  p_enrollment_id uuid,
  p_closed_on date default public.local_today()
)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_enrollment public.enrollments; v_amount integer;
begin
  select * into v_enrollment from public.enrollments where id = p_enrollment_id for update;
  if not found then raise exception 'Matrícula não encontrada' using errcode = 'P0002'; end if;
  if v_enrollment.signed_at is not null
     or exists (select 1 from public.installments i where i.enrollment_id = v_enrollment.id and i.status <> 'cancelado') then
    return v_enrollment.amount_cents;
  end if;
  v_amount := public.campaign_amount_for_date(v_enrollment.campaign_id, v_enrollment.target_grade_id, p_closed_on);
  if v_amount is null then raise exception 'A série desta matrícula não possui valor configurado' using errcode = 'P0001'; end if;
  update public.enrollments set amount_cents = v_amount where id = v_enrollment.id;
  return v_amount;
end $$;

-- A oferta pública é usada pela matrícula nova; por isso não deve expor o
-- valor antecipado reservado à rematrícula.
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
  select o.id, o.grade_id, o.amount_cents, o.cash_amount_cents, o.seats_total,
         o.early_amount_cents, o.early_amount_until, g.name, g.sort_order
    from public.grade_offerings o
    join public.grades g on g.id = o.grade_id
   where o.academic_year = 2027
     and exists (
       select 1 from public.campaigns c
        where c.kind = 'matricula_nova'::public.campaign_kind
          and c.academic_year = o.academic_year
          and c.status = 'ativa'
          and c.starts_on <= public.local_today()
          and (c.ends_on is null or c.ends_on >= public.local_today())
     )
   order by g.sort_order
$$;

-- A família precisa conseguir avançar com os filhos elegíveis mesmo quando
-- outro cadastro ainda não tem turma atual, próxima série ou valor para 2027.
-- A indisponibilidade é explícita na tela; a seleção continua protegida pela
-- validação em onboarding_select_rematricula_children() abaixo.
create or replace function public.onboarding_open(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session public.enrollment_onboarding_sessions;
begin
  select * into v_session
    from public.enrollment_onboarding_sessions
   where token = trim(p_token) and status <> 'cancelada'
   for update;
  if not found then raise exception 'Jornada inválida ou expirada' using errcode = 'P0002'; end if;

  update public.enrollment_onboarding_sessions
     set last_opened_at = now(), updated_at = now()
   where id = v_session.id;

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

-- O token é gerado somente pelo agente com service_role e já fica ligado ao
-- responsável que conversou no WhatsApp. A página pública não recebe um UUID
-- nem uma busca de família para manipular.
create or replace function public.create_rematricula_onboarding_link(p_guardian_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_campaign public.campaigns; v_guardian public.guardians; v_session public.enrollment_onboarding_sessions;
begin
  select * into v_guardian from public.guardians where id = p_guardian_id;
  if not found then raise exception 'Responsável não encontrado' using errcode = 'P0002'; end if;
  if v_guardian.opted_out_at is not null then raise exception 'Responsável pediu para não receber contatos' using errcode = 'P0001'; end if;

  v_campaign := public.onboarding_campaign('rematricula');
  if not exists (
    select 1
      from public.student_guardians sg
      join public.students s on s.id = sg.student_id
      join public.classes current_class on current_class.id = s.current_class_id
      join public.grades current_grade on current_grade.id = current_class.grade_id
      join public.grades target_grade on target_grade.id = current_grade.next_grade_id
     where sg.guardian_id = p_guardian_id
       and public.campaign_amount_for_date(v_campaign.id, target_grade.id, public.local_today()) is not null
  ) then
    raise exception 'Nenhum aluno deste responsável tem série seguinte e valor configurados' using errcode = 'P0001';
  end if;

  select * into v_session
    from public.enrollment_onboarding_sessions
   where campaign_id = v_campaign.id
     and guardian_id = p_guardian_id
     and flow = 'rematricula'
     and status not in ('cancelada', 'concluida')
   order by updated_at desc
   limit 1
   for update;

  if not found then
    insert into public.enrollment_onboarding_sessions(campaign_id, guardian_id, flow, status, current_step, context)
    values (v_campaign.id, p_guardian_id, 'rematricula', 'filhos', 2,
      jsonb_build_object('created_by', 'whatsapp_agent', 'link_created_at', now()))
    returning * into v_session;
  else
    update public.enrollment_onboarding_sessions
       set status = case when current_step < 2 then 'filhos' else status end,
           current_step = greatest(current_step, 2),
           last_opened_at = now(),
           context = context || jsonb_build_object('last_link_requested_at', now())
     where id = v_session.id
     returning * into v_session;
  end if;

  return jsonb_build_object('token', v_session.token, 'url', '/rematricula?j=' || v_session.token);
end $$;

create or replace function public.mark_rematricula_onboarding_link_sent(p_token text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.enrollment_onboarding_sessions
     set context = context || jsonb_build_object(
           'agent_link_sent_at', now(),
           'agent_link_send_count', coalesce((context ->> 'agent_link_send_count')::integer, 0) + 1
         ),
         updated_at = now()
   where token = trim(p_token)
     and flow = 'rematricula'
     and status not in ('cancelada', 'concluida');
  if not found then raise exception 'Jornada de rematrícula inválida ou encerrada' using errcode = 'P0002'; end if;
end $$;

-- A seleção não pode trocar o responsável de uma matrícula já iniciada. Isso
-- evita que outro contato vinculado acesse ou assine a jornada de terceiros.
create or replace function public.onboarding_select_rematricula_children(p_token text, p_student_ids uuid[])
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_session public.enrollment_onboarding_sessions;
  v_student_id uuid;
  v_target_grade uuid;
  v_enrollment public.enrollments;
  v_amount integer;
begin
  select * into v_session from public.enrollment_onboarding_sessions
   where token = trim(p_token) and flow = 'rematricula' and guardian_id is not null and status <> 'cancelada'
   for update;
  if not found then raise exception 'Identifique primeiro o responsável' using errcode = 'P0001'; end if;
  if coalesce(cardinality(p_student_ids), 0) = 0 then raise exception 'Selecione pelo menos um aluno' using errcode = '22023'; end if;

  delete from public.enrollment_onboarding_items where onboarding_session_id = v_session.id;
  foreach v_student_id in array p_student_ids loop
    select current_grade.next_grade_id into v_target_grade
      from public.student_guardians sg
      join public.students s on s.id = sg.student_id
      join public.classes current_class on current_class.id = s.current_class_id
      join public.grades current_grade on current_grade.id = current_class.grade_id
     where sg.student_id = v_student_id and sg.guardian_id = v_session.guardian_id;
    if v_target_grade is null then raise exception 'Aluno selecionado não possui série seguinte configurada' using errcode = 'P0001'; end if;

    v_amount := public.campaign_amount_for_date(v_session.campaign_id, v_target_grade, public.local_today());
    if v_amount is null then raise exception 'A série pretendida não possui valor configurado' using errcode = 'P0001'; end if;

    select * into v_enrollment from public.enrollments
     where campaign_id = v_session.campaign_id and student_id = v_student_id
     for update;
    if found and v_enrollment.guardian_id <> v_session.guardian_id then
      raise exception 'A rematrícula deste aluno já está vinculada a outro responsável. Fale com a secretaria.' using errcode = 'P0001';
    elsif found then
      if v_enrollment.signed_at is null and not exists (
        select 1 from public.installments i where i.enrollment_id = v_enrollment.id and i.status <> 'cancelado'
      ) then
        update public.enrollments
           set amount_cents = v_amount,
               form_started_at = coalesce(form_started_at, now())
         where id = v_enrollment.id
         returning * into v_enrollment;
      end if;
    else
      insert into public.enrollments(
        campaign_id, student_id, guardian_id, origin, from_class_id,
        target_grade_id, status, amount_cents, form_started_at
      ) values (
        v_session.campaign_id, v_student_id, v_session.guardian_id, 'site',
        (select current_class_id from public.students where id = v_student_id),
        v_target_grade, 'formulario_iniciado', v_amount, now()
      ) returning * into v_enrollment;
    end if;

    -- Uma sessão anterior da MESMA família pode ser retomada; nunca movemos
    -- item de outra família para o token atual.
    delete from public.enrollment_onboarding_items oi
     using public.enrollment_onboarding_sessions previous
     where oi.enrollment_id = v_enrollment.id
       and oi.onboarding_session_id = previous.id
       and previous.guardian_id = v_session.guardian_id;
    insert into public.enrollment_onboarding_items(onboarding_session_id, enrollment_id)
    values (v_session.id, v_enrollment.id);
  end loop;

  update public.enrollment_onboarding_sessions
     set status = 'contratos', current_step = 3, last_opened_at = now()
   where id = v_session.id;
  return public.onboarding_open(v_session.token);
end $$;

revoke all on function public.campaign_amount_for_date(uuid, uuid, date) from public, anon, authenticated;
grant execute on function public.campaign_amount_for_date(uuid, uuid, date) to service_role;
revoke all on function public.create_rematricula_onboarding_link(uuid), public.mark_rematricula_onboarding_link_sent(text) from public, anon, authenticated;
grant execute on function public.create_rematricula_onboarding_link(uuid), public.mark_rematricula_onboarding_link_sent(text) to service_role;
revoke execute on function public.onboarding_select_rematricula_children(text, uuid[]) from public;
grant execute on function public.onboarding_select_rematricula_children(text, uuid[]) to anon, authenticated;
