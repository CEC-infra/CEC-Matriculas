-- Fluxo de contrato próprio: uma sessão pode reunir irmãos do mesmo responsável
-- dentro da mesma campanha. Assinaturas continuam registradas em document_acceptances.

create type public.contract_session_status as enum (
  'pronta', 'codigo_enviado', 'verificada', 'assinada', 'expirada', 'cancelada'
);

create table public.contract_sessions (
  id                        uuid primary key default gen_random_uuid(),
  campaign_id               uuid not null references public.campaigns (id) on delete restrict,
  guardian_id               uuid not null references public.guardians (id) on delete restrict,
  token                     text not null unique default encode(extensions.gen_random_bytes(16), 'hex'),
  status                    public.contract_session_status not null default 'pronta',
  confirmation_email        text not null check (confirmation_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  verification_code_hash    text,
  verification_expires_at   timestamptz,
  verification_sent_at      timestamptz,
  verification_verified_at  timestamptz,
  verification_attempts     smallint not null default 0 check (verification_attempts between 0 and 5),
  expires_at                timestamptz not null default now() + interval '7 days',
  first_opened_at           timestamptz,
  last_opened_at            timestamptz,
  open_count                integer not null default 0 check (open_count >= 0),
  signed_at                 timestamptz,
  created_by                uuid references public.profiles (id) on delete set null,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now()
);

create index contract_sessions_guardian_campaign_idx on public.contract_sessions (guardian_id, campaign_id, created_at desc);
create index contract_sessions_follow_up_idx on public.contract_sessions (status, expires_at) where status in ('pronta', 'codigo_enviado', 'verificada');

create table public.contract_session_enrollments (
  contract_session_id  uuid not null references public.contract_sessions (id) on delete cascade,
  enrollment_id        uuid not null references public.enrollments (id) on delete restrict,
  created_at           timestamptz not null default now(),
  primary key (contract_session_id, enrollment_id)
);
create index contract_session_enrollments_enrollment_idx on public.contract_session_enrollments (enrollment_id);

-- A fila é consumida por uma Edge Function/provedor transacional. O código nunca
-- é devolvido por RPC; fica apenas no corpo pendente que o worker precisa enviar.
create table public.email_queue (
  id                    uuid primary key default gen_random_uuid(),
  contract_session_id   uuid not null references public.contract_sessions (id) on delete cascade,
  recipient             text not null check (recipient ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  subject               text not null,
  html_body             text not null,
  status                text not null default 'pendente' check (status in ('pendente', 'processando', 'enviado', 'falhou', 'cancelado')),
  provider              text,
  provider_message_id   text,
  attempts              smallint not null default 0 check (attempts >= 0),
  scheduled_for         timestamptz not null default now(),
  sent_at               timestamptz,
  last_error            text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create index email_queue_pending_idx on public.email_queue (status, scheduled_for) where status in ('pendente', 'processando');
create unique index email_queue_provider_message_idx on public.email_queue (provider, provider_message_id) where provider_message_id is not null;

alter table public.document_acceptances
  add column contract_session_id uuid references public.contract_sessions (id) on delete set null,
  add column signer_full_name text,
  add column signer_email text check (signer_email is null or signer_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  add column email_verified_at timestamptz,
  add column signature_image_data text check (signature_image_data is null or (signature_image_data ~ '^data:image/(png|jpeg);base64,' and length(signature_image_data) between 100 and 500000)),
  add column signature_image_sha256 text check (signature_image_sha256 is null or signature_image_sha256 ~ '^[0-9a-f]{64}$');
create index document_acceptances_contract_session_idx on public.document_acceptances (contract_session_id);

create or replace function public.contract_issue_verification_code(p_session_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_session public.contract_sessions;
  v_code text;
begin
  select * into v_session from public.contract_sessions where id = p_session_id for update;
  if not found or v_session.status in ('assinada', 'cancelada', 'expirada') or v_session.expires_at <= now() then
    raise exception 'Sessão de contrato indisponível' using errcode = 'P0002';
  end if;

  v_code := upper(substr(encode(extensions.gen_random_bytes(4), 'hex'), 1, 6));
  update public.contract_sessions
     set status = 'codigo_enviado',
         verification_code_hash = encode(extensions.digest(v_code || token, 'sha256'), 'hex'),
         verification_expires_at = now() + interval '15 minutes',
         verification_sent_at = now(),
         verification_attempts = 0
   where id = v_session.id;

  insert into public.email_queue (contract_session_id, recipient, subject, html_body)
  values (
    v_session.id,
    v_session.confirmation_email,
    'Confirme seu código para assinar o contrato CEC',
    '<p>Use o código <strong>' || v_code || '</strong> para confirmar sua identidade e assinar o contrato.</p><p>O código expira em 15 minutos.</p>'
  );

  insert into public.enrollment_events (enrollment_id, code, title, body, actor, metadata)
  select cse.enrollment_id, 'CONTRACT_CODE_SENT', 'Código de confirmação enviado',
         'Código de confirmação de e-mail enviado para assinatura do contrato.', 'sistema',
         jsonb_build_object('contract_session_id', v_session.id)
    from public.contract_session_enrollments cse
   where cse.contract_session_id = v_session.id;
end $$;

create or replace function public.contract_create_session(
  p_enrollment_id uuid,
  p_confirmation_email text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_enrollment public.enrollments;
  v_guardian public.guardians;
  v_session_id uuid;
  v_token text;
  v_email text;
begin
  if not public.is_staff() then
    raise exception 'Apenas a equipe pode iniciar contratos' using errcode = '42501';
  end if;

  select * into v_enrollment from public.enrollments where id = p_enrollment_id for update;
  if not found or v_enrollment.status in ('sem_interesse', 'opt_out', 'fora_campanha') or v_enrollment.completed_at is not null then
    raise exception 'Matrícula não está disponível para contrato' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.campaigns where id = v_enrollment.campaign_id and status = 'ativa') then
    raise exception 'A campanha desta matrícula não está ativa' using errcode = 'P0001';
  end if;
  if v_enrollment.payment_plan_id is null or v_enrollment.amount_cents is null then
    raise exception 'Defina valor e condição de pagamento antes de iniciar o contrato' using errcode = 'P0001';
  end if;

  select * into v_guardian from public.guardians where id = v_enrollment.guardian_id for update;
  v_email := lower(trim(coalesce(nullif(p_confirmation_email, ''), v_guardian.email)));
  if v_email is null or v_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Informe um e-mail válido para confirmação da assinatura' using errcode = '22023';
  end if;

  if exists (
    select 1
      from public.enrollments e
     where e.campaign_id = v_enrollment.campaign_id
       and e.guardian_id = v_enrollment.guardian_id
       and e.status not in ('sem_interesse', 'opt_out', 'fora_campanha')
       and e.completed_at is null
       and (e.payment_plan_id is null or e.amount_cents is null)
  ) then
    raise exception 'Todas as matrículas dos filhos incluídos precisam ter valor e condição de pagamento' using errcode = 'P0001';
  end if;

  if exists (
    select 1
      from public.enrollments e
     where e.campaign_id = v_enrollment.campaign_id
       and e.guardian_id = v_enrollment.guardian_id
       and e.status not in ('sem_interesse', 'opt_out', 'fora_campanha')
       and e.completed_at is null
       and not exists (
         select 1
           from public.campaign_documents cd
           join public.documents d on d.id = cd.document_id and d.kind = 'contrato'
           join public.document_versions dv on dv.document_id = d.id and dv.is_current
          where cd.campaign_id = e.campaign_id
            and (dv.grade_id is null or dv.grade_id = e.target_grade_id)
       )
  ) then
    raise exception 'Falta uma versão atual de contrato para pelo menos um aluno' using errcode = 'P0001';
  end if;

  update public.guardians set email = v_email where id = v_guardian.id and email is distinct from v_email;
  update public.contract_sessions
     set status = 'cancelada'
   where campaign_id = v_enrollment.campaign_id
     and guardian_id = v_enrollment.guardian_id
     and status in ('pronta', 'codigo_enviado', 'verificada');

  insert into public.contract_sessions (campaign_id, guardian_id, confirmation_email, created_by)
  values (v_enrollment.campaign_id, v_enrollment.guardian_id, v_email, public.current_profile_id())
  returning id, token into v_session_id, v_token;

  insert into public.contract_session_enrollments (contract_session_id, enrollment_id)
  select v_session_id, e.id
    from public.enrollments e
   where e.campaign_id = v_enrollment.campaign_id
     and e.guardian_id = v_enrollment.guardian_id
     and e.status not in ('sem_interesse', 'opt_out', 'fora_campanha')
     and e.completed_at is null;

  update public.enrollments e
     set status = case when public.journey_rank(e.status) < public.journey_rank('aguardando_assinatura'::public.journey_status)
                       then 'aguardando_assinatura'::public.journey_status else e.status end
    from public.contract_session_enrollments cse
   where cse.contract_session_id = v_session_id and e.id = cse.enrollment_id;

  insert into public.enrollment_events (enrollment_id, code, title, body, actor, metadata)
  select cse.enrollment_id, 'CONTRACT_READY', 'Contrato preparado',
         'A família confirmou a intenção de matrícula e recebeu a etapa de assinatura.', 'sistema',
         jsonb_build_object('contract_session_id', v_session_id)
    from public.contract_session_enrollments cse
   where cse.contract_session_id = v_session_id;

  perform public.contract_issue_verification_code(v_session_id);
  return jsonb_build_object('token', v_token, 'expires_at', (select expires_at from public.contract_sessions where id = v_session_id));
end $$;

create or replace function public.contract_open(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_session public.contract_sessions;
  v_out jsonb;
begin
  select * into v_session from public.contract_sessions
   where token = p_token and status not in ('assinada', 'cancelada', 'expirada') and expires_at > now();
  if not found then raise exception 'Link de contrato inválido ou expirado' using errcode = 'P0002'; end if;

  update public.contract_sessions
     set first_opened_at = coalesce(first_opened_at, now()), last_opened_at = now(), open_count = open_count + 1
   where id = v_session.id;
  if v_session.first_opened_at is null then
    insert into public.enrollment_events (enrollment_id, code, title, body, actor, metadata)
    select cse.enrollment_id, 'CONTRACT_OPENED', 'Página de contrato visitada',
           'A família acessou a página de assinatura.', 'responsavel', jsonb_build_object('contract_session_id', v_session.id)
      from public.contract_session_enrollments cse where cse.contract_session_id = v_session.id;
  end if;

  select jsonb_build_object(
    'status', v_session.status,
    'email_masked', regexp_replace(v_session.confirmation_email, '^(.{1,2}).*(@.*)$', '\\1***\\2'),
    'email_verified', v_session.verification_verified_at is not null,
    'expires_at', v_session.expires_at,
    'guardian', jsonb_build_object('name', g.full_name),
    'enrollments', coalesce(jsonb_agg(jsonb_build_object(
      'id', e.id, 'student_name', s.full_name, 'grade', gr.name, 'shift', e.target_shift,
      'amount_cents', e.amount_cents, 'payment_plan', pp.name,
      'contract', jsonb_build_object('title', ddoc.title, 'version', ddoc.version, 'storage_path', ddoc.storage_path)
    ) order by s.full_name), '[]'::jsonb)
  ) into v_out
    from public.contract_session_enrollments cse
    join public.enrollments e on e.id = cse.enrollment_id
    join public.students s on s.id = e.student_id
    join public.grades gr on gr.id = e.target_grade_id
    join public.guardians g on g.id = v_session.guardian_id
    left join public.payment_plans pp on pp.id = e.payment_plan_id
    join lateral (
      select d.id, d.title, dv.version, dv.storage_path
        from public.campaign_documents cd
        join public.documents d on d.id = cd.document_id and d.kind = 'contrato'
        join public.document_versions dv on dv.document_id = d.id and dv.is_current
       where cd.campaign_id = e.campaign_id and (dv.grade_id is null or dv.grade_id = e.target_grade_id)
       order by case when dv.grade_id = e.target_grade_id then 0 else 1 end
       limit 1
    ) ddoc on true
   where cse.contract_session_id = v_session.id
   group by g.full_name;

  return v_out;
end $$;

create or replace function public.contract_send_email_code(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session_id uuid;
begin
  select id into v_session_id from public.contract_sessions
   where token = p_token and status not in ('assinada', 'cancelada', 'expirada') and expires_at > now();
  if v_session_id is null then raise exception 'Link de contrato inválido ou expirado' using errcode = 'P0002'; end if;
  perform public.contract_issue_verification_code(v_session_id);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.contract_verify_email_code(p_token text, p_code text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session public.contract_sessions;
begin
  select * into v_session from public.contract_sessions where token = p_token for update;
  if not found or v_session.status in ('assinada', 'cancelada', 'expirada') or v_session.expires_at <= now() then
    raise exception 'Link de contrato inválido ou expirado' using errcode = 'P0002';
  end if;
  if v_session.verification_expires_at is null or v_session.verification_expires_at <= now() then
    raise exception 'Código expirado. Solicite um novo código.' using errcode = 'P0001';
  end if;
  if v_session.verification_attempts >= 5 then
    raise exception 'Limite de tentativas atingido. Solicite um novo código.' using errcode = 'P0001';
  end if;
  if encode(extensions.digest(upper(trim(p_code)) || v_session.token, 'sha256'), 'hex') <> v_session.verification_code_hash then
    update public.contract_sessions set verification_attempts = verification_attempts + 1 where id = v_session.id;
    raise exception 'Código inválido' using errcode = '22023';
  end if;
  update public.contract_sessions
     set status = 'verificada', verification_verified_at = now(), verification_attempts = verification_attempts + 1
   where id = v_session.id;
  insert into public.enrollment_events (enrollment_id, code, title, body, actor, metadata)
  select cse.enrollment_id, 'CONTRACT_EMAIL_VERIFIED', 'E-mail confirmado',
         'O responsável confirmou o código de assinatura.', 'responsavel', jsonb_build_object('contract_session_id', v_session.id)
    from public.contract_session_enrollments cse where cse.contract_session_id = v_session.id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.contract_sign(
  p_token text,
  p_signer_full_name text,
  p_signature_image_data text,
  p_accepted boolean
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_session public.contract_sessions;
  v_enrollment record;
  v_document_version_id uuid;
  v_signature_hash text;
begin
  if p_accepted is not true then raise exception 'Confirme a leitura e o aceite do contrato' using errcode = '22023'; end if;
  if nullif(trim(p_signer_full_name), '') is null then raise exception 'Informe o nome de quem assina' using errcode = '22023'; end if;
  if p_signature_image_data is null or p_signature_image_data !~ '^data:image/(png|jpeg);base64,' or length(p_signature_image_data) not between 100 and 500000 then
    raise exception 'A assinatura desenhada é obrigatória' using errcode = '22023';
  end if;

  select * into v_session from public.contract_sessions where token = p_token for update;
  if not found or v_session.status in ('assinada', 'cancelada', 'expirada') or v_session.expires_at <= now() then
    raise exception 'Link de contrato inválido ou expirado' using errcode = 'P0002';
  end if;
  if v_session.verification_verified_at is null then raise exception 'Confirme o código enviado por e-mail antes de assinar' using errcode = 'P0001'; end if;

  v_signature_hash := encode(extensions.digest(p_signature_image_data, 'sha256'), 'hex');
  for v_enrollment in
    select e.* from public.contract_session_enrollments cse join public.enrollments e on e.id = cse.enrollment_id
     where cse.contract_session_id = v_session.id
  loop
    select dv.id into v_document_version_id
      from public.campaign_documents cd
      join public.documents d on d.id = cd.document_id and d.kind = 'contrato'
      join public.document_versions dv on dv.document_id = d.id and dv.is_current
     where cd.campaign_id = v_enrollment.campaign_id and (dv.grade_id is null or dv.grade_id = v_enrollment.target_grade_id)
     order by case when dv.grade_id = v_enrollment.target_grade_id then 0 else 1 end
     limit 1;
    if v_document_version_id is null then raise exception 'Versão do contrato não encontrada' using errcode = 'P0001'; end if;

    insert into public.document_acceptances (
      enrollment_id, document_version_id, status, provider, contract_session_id,
      signer_full_name, signer_email, email_verified_at, signature_image_data, signature_image_sha256, document_hash
    ) values (
      v_enrollment.id, v_document_version_id, 'assinado', 'cec_assinatura_interna', v_session.id,
      trim(p_signer_full_name), v_session.confirmation_email, v_session.verification_verified_at,
      p_signature_image_data, v_signature_hash,
      (select sha256 from public.document_versions where id = v_document_version_id)
    )
    on conflict (enrollment_id, document_version_id) do update set
      status = case when public.document_acceptances.status in ('assinado', 'aceito') then public.document_acceptances.status else excluded.status end,
      provider = case when public.document_acceptances.status in ('assinado', 'aceito') then public.document_acceptances.provider else excluded.provider end,
      contract_session_id = case when public.document_acceptances.status in ('assinado', 'aceito') then public.document_acceptances.contract_session_id else excluded.contract_session_id end,
      signer_full_name = case when public.document_acceptances.status in ('assinado', 'aceito') then public.document_acceptances.signer_full_name else excluded.signer_full_name end,
      signer_email = case when public.document_acceptances.status in ('assinado', 'aceito') then public.document_acceptances.signer_email else excluded.signer_email end,
      email_verified_at = case when public.document_acceptances.status in ('assinado', 'aceito') then public.document_acceptances.email_verified_at else excluded.email_verified_at end,
      signature_image_data = case when public.document_acceptances.status in ('assinado', 'aceito') then public.document_acceptances.signature_image_data else excluded.signature_image_data end,
      signature_image_sha256 = case when public.document_acceptances.status in ('assinado', 'aceito') then public.document_acceptances.signature_image_sha256 else excluded.signature_image_sha256 end;

    if not exists (select 1 from public.installments where enrollment_id = v_enrollment.id and status <> 'cancelado') then
      perform public.generate_installments(v_enrollment.id);
    end if;
  end loop;

  update public.contract_sessions set status = 'assinada', signed_at = now() where id = v_session.id;
  insert into public.enrollment_events (enrollment_id, code, title, body, actor, metadata)
  select cse.enrollment_id, 'CONTRACT_SIGNED', 'Contrato assinado',
         'Contrato assinado após confirmação por e-mail. Parcelas foram geradas.', 'responsavel',
         jsonb_build_object('contract_session_id', v_session.id, 'signature_sha256', v_signature_hash)
    from public.contract_session_enrollments cse where cse.contract_session_id = v_session.id;
  return jsonb_build_object('ok', true, 'signed_at', now());
end $$;

alter table public.contract_sessions enable row level security;
alter table public.contract_session_enrollments enable row level security;
alter table public.email_queue enable row level security;
create policy "equipe lê sessões de contrato" on public.contract_sessions for select to authenticated using ((select public.is_staff()));
create policy "equipe lê vínculos de contrato" on public.contract_session_enrollments for select to authenticated using ((select public.is_staff()));
create policy "equipe lê fila de e-mail" on public.email_queue for select to authenticated using ((select public.is_staff()));

revoke execute on function public.contract_issue_verification_code(uuid), public.contract_create_session(uuid, text), public.contract_open(text), public.contract_send_email_code(text), public.contract_verify_email_code(text, text), public.contract_sign(text, text, text, boolean) from public, anon, authenticated;
grant execute on function public.contract_create_session(uuid, text) to authenticated;
grant execute on function public.contract_open(text), public.contract_send_email_code(text), public.contract_verify_email_code(text, text), public.contract_sign(text, text, text, boolean) to anon, authenticated;
