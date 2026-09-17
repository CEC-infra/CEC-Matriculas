-- CEC · Matrícula Inteligente — esquema principal.
-- Dinheiro em centavos (integer); datas em timestamptz; fuso operacional America/Fortaleza.

-- Tipos ---------------------------------------------------------------------

create type public.staff_role           as enum ('admin', 'coordenacao', 'secretaria', 'atendente');
create type public.school_stage         as enum ('infantil', 'fundamental_1', 'fundamental_2', 'medio');
create type public.shift                as enum ('manha', 'tarde', 'integral');
create type public.campaign_kind        as enum ('rematricula', 'matricula_nova');
create type public.campaign_status      as enum ('rascunho', 'ativa', 'pausada', 'encerrada');
create type public.enrollment_origin    as enum ('base_secretaria', 'site', 'indicacao', 'instagram', 'visita_presencial', 'telefone', 'whatsapp', 'outro');
create type public.journey_status       as enum (
  'pre_matricula', 'em_fila', 'contatada', 'conversando', 'precisa_humano',
  'link_enviado', 'link_aberto', 'formulario_iniciado', 'aguardando_assinatura',
  'aguardando_pagamento', 'pagamento_vencido', 'concluida',
  'sem_interesse', 'opt_out', 'fora_campanha'
);
create type public.payment_method       as enum ('cartao', 'boleto', 'pix');
create type public.installment_status   as enum ('pendente', 'pago', 'vencido', 'cancelado', 'estornado');
create type public.document_kind        as enum ('contrato', 'termo_imagem', 'regimento', 'lista_material', 'outro');
create type public.document_requirement as enum ('assinatura_obrigatoria', 'aceite_obrigatorio', 'opcional', 'anexo');
create type public.acceptance_status    as enum ('pendente', 'enviado', 'assinado', 'aceito', 'recusado', 'expirado');
create type public.conversation_handler as enum ('fila', 'ia', 'humano', 'encerrada');
create type public.message_direction    as enum ('entrada', 'saida');
create type public.actor_kind           as enum ('responsavel', 'ia', 'equipe', 'sistema');
create type public.message_status       as enum ('recebida', 'na_fila', 'enviada', 'entregue', 'lida', 'falhou');
create type public.queue_status         as enum ('pendente', 'processando', 'enviada', 'falhou', 'cancelada');
create type public.webhook_source       as enum ('whatsapp', 'assinatura', 'pagamento', 'outro');
create type public.webhook_status       as enum ('recebido', 'processado', 'falhou', 'ignorado');

-- Equipe --------------------------------------------------------------------

create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text not null,
  role        public.staff_role not null default 'atendente',
  active      boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
comment on table public.profiles is 'Usuários do painel. Criado no cadastro do auth, inativo até um admin liberar.';

-- Catálogo acadêmico --------------------------------------------------------

create table public.grades (
  id             uuid primary key default gen_random_uuid(),
  code           text not null unique,
  name           text not null unique,
  stage          public.school_stage not null,
  sort_order     smallint not null unique,
  next_grade_id  uuid references public.grades (id) on delete set null,
  active         boolean not null default true
);
comment on table public.grades is 'Séries. next_grade_id é a regra de transição usada na rematrícula.';

create table public.classes (
  id             uuid primary key default gen_random_uuid(),
  grade_id       uuid not null references public.grades (id) on delete restrict,
  academic_year  smallint not null check (academic_year between 2000 and 2100),
  name           text not null,
  shift          public.shift not null,
  capacity       smallint check (capacity > 0),
  created_at     timestamptz not null default now(),
  unique (academic_year, name)
);
comment on table public.classes is 'Turmas por ano letivo (ex.: 5º ano A · 2026).';

create table public.grade_offerings (
  id                 uuid primary key default gen_random_uuid(),
  academic_year      smallint not null check (academic_year between 2000 and 2100),
  grade_id           uuid not null references public.grades (id) on delete restrict,
  shifts             public.shift[] not null default '{manha}' check (cardinality(shifts) > 0),
  amount_cents       integer not null check (amount_cents >= 0),
  cash_amount_cents  integer check (cash_amount_cents >= 0),
  seats_total        smallint not null default 0 check (seats_total >= 0),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (academic_year, grade_id)
);
comment on table public.grade_offerings is 'Séries ofertadas no ano letivo: turnos, valor e vagas.';
comment on column public.grade_offerings.amount_cents is 'Valor da (re)matrícula cobrado na campanha — equivale a uma mensalidade da série.';

-- Campanhas e regras --------------------------------------------------------

create table public.campaigns (
  id                       uuid primary key default gen_random_uuid(),
  name                     text not null unique,
  kind                     public.campaign_kind not null,
  academic_year            smallint not null check (academic_year between 2000 and 2100),
  status                   public.campaign_status not null default 'rascunho',
  starts_on                date not null,
  ends_on                  date,
  send_window_start        time not null default '08:00',
  send_window_end          time not null default '19:30',
  min_interval_seconds     smallint not null default 40 check (min_interval_seconds >= 0),
  max_interval_seconds     smallint not null default 90,
  hourly_cap               smallint not null default 25 check (hourly_cap > 0),
  daily_cap                smallint not null default 150 check (daily_cap > 0),
  max_attempts             smallint not null default 5 check (max_attempts > 0),
  link_resend_after_hours  smallint not null default 48 check (link_resend_after_hours > 0),
  link_ttl_days            smallint not null default 30 check (link_ttl_days > 0),
  queue_paused             boolean not null default false,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  check (ends_on is null or ends_on >= starts_on),
  check (send_window_end > send_window_start),
  check (max_interval_seconds >= min_interval_seconds)
);
comment on table public.campaigns is 'Campanhas (Rematrícula 2027, Matrículas novas 2027) com os limites da régua de WhatsApp.';

create table public.payment_policies (
  campaign_id                   uuid primary key references public.campaigns (id) on delete cascade,
  cash_discount_pct             numeric(5,2) not null default 0 check (cash_discount_pct between 0 and 100),
  max_installments              smallint not null default 1 check (max_installments between 1 and 12),
  last_due_date                 date,
  accepted_methods              public.payment_method[] not null default '{cartao,boleto,pix}',
  sibling_discount_pct          numeric(5,2) not null default 0 check (sibling_discount_pct between 0 and 100),
  late_fee_pct                  numeric(5,2) not null default 0 check (late_fee_pct >= 0),
  monthly_interest_pct          numeric(5,2) not null default 0 check (monthly_interest_pct >= 0),
  boleto_due_business_days      smallint not null default 3 check (boleto_due_business_days >= 0),
  scholarship_requires_handoff  boolean not null default true,
  updated_at                    timestamptz not null default now()
);
comment on table public.payment_policies is 'Condições de pagamento da campanha (desconto à vista, parcelamento, irmãos, multa).';

create table public.payment_plans (
  id            uuid primary key default gen_random_uuid(),
  campaign_id   uuid not null references public.campaigns (id) on delete cascade,
  name          text not null,
  description   text,
  installments  smallint not null check (installments between 1 and 12),
  discount_pct  numeric(5,2) not null default 0 check (discount_pct between 0 and 100),
  due_dates     date[] not null,
  sort_order    smallint not null default 0,
  active        boolean not null default true,
  unique (campaign_id, name),
  check (cardinality(due_dates) = installments)
);
comment on table public.payment_plans is 'Opções exibidas ao responsável (À vista, 3x, 2x) com as datas de vencimento.';

create table public.documents (
  id           uuid primary key default gen_random_uuid(),
  code         text not null unique,
  title        text not null,
  kind         public.document_kind not null,
  requirement  public.document_requirement not null,
  per_grade    boolean not null default false,
  created_at   timestamptz not null default now()
);

create table public.document_versions (
  id            uuid primary key default gen_random_uuid(),
  document_id   uuid not null references public.documents (id) on delete cascade,
  version       text not null,
  grade_id      uuid references public.grades (id) on delete restrict,
  pages         smallint check (pages > 0),
  storage_path  text,
  sha256        text check (sha256 ~ '^[0-9a-f]{64}$'),
  is_current    boolean not null default false,
  published_at  timestamptz,
  created_at    timestamptz not null default now(),
  unique nulls not distinct (document_id, version, grade_id)
);
create unique index document_versions_one_current
  on public.document_versions (document_id, grade_id) nulls not distinct
  where is_current;

create table public.campaign_documents (
  campaign_id  uuid not null references public.campaigns (id) on delete cascade,
  document_id  uuid not null references public.documents (id) on delete restrict,
  sort_order   smallint not null default 0,
  primary key (campaign_id, document_id)
);

-- Famílias ------------------------------------------------------------------

create table public.guardians (
  id                   uuid primary key default gen_random_uuid(),
  full_name            text not null,
  cpf                  text unique check (cpf ~ '^[0-9]{11}$'),
  email                text check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  phone                text not null unique check (phone ~ '^\+[1-9][0-9]{7,14}$'),
  whatsapp_consent_at  timestamptz,
  opted_out_at         timestamptz,
  notes                text,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);
comment on table public.guardians is 'Responsáveis. phone em E.164 (+5583...) — é a chave do WhatsApp.';

create table public.students (
  id                uuid primary key default gen_random_uuid(),
  full_name         text not null,
  birth_date        date,
  current_class_id  uuid references public.classes (id) on delete set null,
  previous_school   text,
  external_ref      text unique,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
comment on column public.students.external_ref is 'Código do aluno no sistema da secretaria (para importação/sincronização).';

create table public.student_guardians (
  student_id          uuid not null references public.students (id) on delete cascade,
  guardian_id         uuid not null references public.guardians (id) on delete cascade,
  relationship        text,
  is_financial        boolean not null default false,
  is_primary_contact  boolean not null default false,
  created_at          timestamptz not null default now(),
  primary key (student_id, guardian_id)
);
create unique index student_guardians_one_primary on public.student_guardians (student_id) where is_primary_contact;

-- Jornada -------------------------------------------------------------------

create table public.enrollments (
  id                 uuid primary key default gen_random_uuid(),
  campaign_id        uuid not null references public.campaigns (id) on delete restrict,
  student_id         uuid not null references public.students (id) on delete restrict,
  guardian_id        uuid not null references public.guardians (id) on delete restrict,
  origin             public.enrollment_origin not null,
  from_class_id      uuid references public.classes (id) on delete set null,
  target_grade_id    uuid not null references public.grades (id) on delete restrict,
  target_shift       public.shift,
  target_class_id    uuid references public.classes (id) on delete set null,
  status             public.journey_status not null default 'em_fila',
  amount_cents       integer check (amount_cents >= 0),
  discount_pct       numeric(5,2) not null default 0 check (discount_pct between 0 and 100),
  payment_plan_id    uuid references public.payment_plans (id) on delete set null,
  attempts           smallint not null default 0 check (attempts >= 0),
  next_action        text,
  next_action_at     timestamptz,
  automation_paused  boolean not null default false,
  assigned_to        uuid references public.profiles (id) on delete set null,
  lost_reason        text,
  contacted_at       timestamptz,
  replied_at         timestamptz,
  link_sent_at       timestamptz,
  link_opened_at     timestamptz,
  form_started_at    timestamptz,
  signed_at          timestamptz,
  paid_at            timestamptz,
  completed_at       timestamptz,
  lost_at            timestamptz,
  created_by         uuid references public.profiles (id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (campaign_id, student_id)
);
comment on table public.enrollments is 'Caso de (re)matrícula: um aluno + responsável dentro de uma campanha. É a "família" do painel.';
comment on column public.enrollments.discount_pct is 'Desconto individual (irmãos, bolsa) aplicado sobre amount_cents.';
comment on column public.enrollments.completed_at is 'Matriculado: documentos obrigatórios assinados e primeiro pagamento confirmado.';

create table public.enrollment_links (
  id               uuid primary key default gen_random_uuid(),
  enrollment_id    uuid not null references public.enrollments (id) on delete cascade,
  token            text not null unique default encode(extensions.gen_random_bytes(16), 'hex'),
  expires_at       timestamptz not null default now() + interval '30 days',
  sent_at          timestamptz,
  first_opened_at  timestamptz,
  last_opened_at   timestamptz,
  open_count       integer not null default 0,
  revoked_at       timestamptz,
  created_at       timestamptz not null default now()
);
create unique index enrollment_links_one_active on public.enrollment_links (enrollment_id) where revoked_at is null;
comment on table public.enrollment_links is 'Link individual cec.app/rematricula/{token}.';

create table public.enrollment_events (
  id             bigint generated always as identity primary key,
  enrollment_id  uuid not null references public.enrollments (id) on delete cascade,
  code           text not null check (code ~ '^[A-Z][A-Z0-9_]*$'),
  title          text not null,
  body           text,
  actor          public.actor_kind not null default 'sistema',
  actor_id       uuid references public.profiles (id) on delete set null,
  metadata       jsonb not null default '{}'::jsonb,
  created_at     timestamptz not null default now()
);
comment on table public.enrollment_events is 'Linha do tempo da jornada (MSG_SENT, LINK_OPENED, SIGNED...). Somente inserção.';

create table public.pre_enrollment_submissions (
  id               uuid primary key default gen_random_uuid(),
  campaign_id      uuid not null references public.campaigns (id) on delete restrict,
  guardian_name    text not null,
  phone            text not null check (phone ~ '^\+[1-9][0-9]{7,14}$'),
  student_name     text not null,
  target_grade_id  uuid not null references public.grades (id) on delete restrict,
  preferred_shift  public.shift,
  current_school   text,
  whatsapp_consent boolean not null check (whatsapp_consent),
  source           public.enrollment_origin not null default 'site',
  utm              jsonb,
  ip               text,
  user_agent       text,
  enrollment_id    uuid references public.enrollments (id) on delete set null,
  created_at       timestamptz not null default now()
);
comment on table public.pre_enrollment_submissions is 'Envios brutos do formulário público cec.app/matricula.';

-- Assinatura e pagamento ----------------------------------------------------

create table public.document_acceptances (
  id                    uuid primary key default gen_random_uuid(),
  enrollment_id         uuid not null references public.enrollments (id) on delete cascade,
  document_version_id   uuid not null references public.document_versions (id) on delete restrict,
  status                public.acceptance_status not null default 'pendente',
  provider              text,
  provider_envelope_id  text,
  sent_at               timestamptz,
  completed_at          timestamptz,
  ip                    inet,
  user_agent            text,
  device                text,
  document_hash         text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  unique (enrollment_id, document_version_id)
);
create unique index document_acceptances_provider_ref
  on public.document_acceptances (provider, provider_envelope_id)
  where provider_envelope_id is not null;
comment on table public.document_acceptances is 'Assinatura/aceite de cada documento, com evidências (IP, dispositivo, hash).';

create table public.installments (
  id                  uuid primary key default gen_random_uuid(),
  enrollment_id       uuid not null references public.enrollments (id) on delete cascade,
  number              smallint not null check (number > 0),
  amount_cents        integer not null check (amount_cents > 0),
  due_date            date not null,
  status              public.installment_status not null default 'pendente',
  method              public.payment_method,
  provider            text,
  provider_charge_id  text,
  payment_url         text,
  boleto_line         text,
  pix_code            text,
  paid_at             timestamptz,
  paid_amount_cents   integer check (paid_amount_cents >= 0),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (enrollment_id, number)
);
create unique index installments_provider_ref
  on public.installments (provider, provider_charge_id)
  where provider_charge_id is not null;

-- WhatsApp e automação ------------------------------------------------------

create table public.whatsapp_instances (
  id                    uuid primary key default gen_random_uuid(),
  name                  text not null unique,
  phone                 text check (phone ~ '^\+[1-9][0-9]{7,14}$'),
  provider              text,
  connected             boolean not null default false,
  paused                boolean not null default false,
  last_health_check_at  timestamptz,
  last_sent_at          timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create table public.conversations (
  id                    uuid primary key default gen_random_uuid(),
  guardian_id           uuid not null unique references public.guardians (id) on delete cascade,
  enrollment_id         uuid references public.enrollments (id) on delete set null,
  instance_id           uuid references public.whatsapp_instances (id) on delete set null,
  handler               public.conversation_handler not null default 'fila',
  assigned_to           uuid references public.profiles (id) on delete set null,
  ai_intent             text,
  ai_sentiment          text,
  ai_summary            text,
  last_message_at       timestamptz,
  last_message_preview  text,
  unread_count          integer not null default 0 check (unread_count >= 0),
  closed_at             timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
comment on column public.conversations.enrollment_id is 'Matrícula em foco na conversa (contexto da IA).';

create table public.messages (
  id                   uuid primary key default gen_random_uuid(),
  conversation_id      uuid not null references public.conversations (id) on delete cascade,
  direction            public.message_direction not null,
  sender               public.actor_kind not null,
  staff_id             uuid references public.profiles (id) on delete set null,
  body                 text,
  media_url            text,
  media_type           text,
  status               public.message_status not null,
  provider_message_id  text unique,
  error                text,
  created_at           timestamptz not null default now(),
  sent_at              timestamptz,
  delivered_at         timestamptz,
  read_at              timestamptz,
  check (body is not null or media_url is not null)
);

create table public.message_templates (
  id              uuid primary key default gen_random_uuid(),
  campaign_id     uuid not null references public.campaigns (id) on delete cascade,
  code            text not null,
  name            text not null,
  attempt_number  smallint check (attempt_number > 0),
  body            text not null,
  wait_hours      smallint not null default 48 check (wait_hours >= 0),
  active          boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (campaign_id, code)
);
create unique index message_templates_attempt on public.message_templates (campaign_id, attempt_number) where attempt_number is not null;
comment on column public.message_templates.wait_hours is 'Horas sem resposta após a tentativa anterior antes de enfileirar esta.';

create table public.message_queue (
  id              uuid primary key default gen_random_uuid(),
  campaign_id     uuid not null references public.campaigns (id) on delete cascade,
  enrollment_id   uuid references public.enrollments (id) on delete cascade,
  guardian_id     uuid not null references public.guardians (id) on delete cascade,
  template_id     uuid references public.message_templates (id) on delete set null,
  attempt_number  smallint check (attempt_number > 0),
  body            text,
  scheduled_for   timestamptz not null default now(),
  status          public.queue_status not null default 'pendente',
  retries         smallint not null default 0 check (retries >= 0),
  last_error      text,
  locked_at       timestamptz,
  message_id      uuid references public.messages (id) on delete set null,
  sent_at         timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create unique index message_queue_one_per_attempt
  on public.message_queue (enrollment_id, attempt_number)
  where status in ('pendente', 'processando', 'enviada') and attempt_number is not null;
comment on table public.message_queue is 'Fila persistente de envio: o worker consome via claim_message_batch().';

-- Integrações ---------------------------------------------------------------

create table public.webhook_events (
  id            bigint generated always as identity primary key,
  source        public.webhook_source not null,
  event_type    text not null,
  external_id   text,
  payload       jsonb not null,
  status        public.webhook_status not null default 'recebido',
  attempts      smallint not null default 0,
  last_error    text,
  received_at   timestamptz not null default now(),
  processed_at  timestamptz,
  unique (source, external_id)
);

-- Índices -------------------------------------------------------------------

create index on public.grades (next_grade_id);
create index on public.classes (grade_id);
create index on public.grade_offerings (grade_id);
create index on public.document_versions (grade_id);
create index on public.campaign_documents (document_id);
create index on public.students (current_class_id);
create index on public.student_guardians (guardian_id);
create index on public.enrollments (campaign_id, status);
create index on public.enrollments (guardian_id);
create index on public.enrollments (student_id);
create index on public.enrollments (from_class_id);
create index on public.enrollments (target_grade_id);
create index on public.enrollments (target_class_id);
create index on public.enrollments (payment_plan_id);
create index on public.enrollments (assigned_to);
create index on public.enrollments (created_by);
create index on public.enrollments (next_action_at) where next_action_at is not null;
create index on public.enrollments (completed_at) where completed_at is not null;
create index on public.enrollment_links (enrollment_id);
create index on public.enrollment_events (enrollment_id, created_at desc);
create index on public.enrollment_events (actor_id);
create index on public.pre_enrollment_submissions (campaign_id);
create index on public.pre_enrollment_submissions (target_grade_id);
create index on public.pre_enrollment_submissions (enrollment_id);
create index on public.pre_enrollment_submissions (phone, created_at);
create index on public.document_acceptances (document_version_id);
create index on public.installments (status, due_date);
create index on public.conversations (enrollment_id);
create index on public.conversations (instance_id);
create index on public.conversations (assigned_to);
create index on public.conversations (last_message_at desc);
create index on public.messages (conversation_id, created_at);
create index on public.messages (staff_id);
create index on public.message_queue (status, scheduled_for) where status in ('pendente', 'processando');
create index on public.message_queue (campaign_id, sent_at);
create index on public.message_queue (enrollment_id);
create index on public.message_queue (guardian_id);
create index on public.message_queue (template_id);
create index on public.message_queue (message_id);
create index on public.webhook_events (status) where status = 'falhou';
