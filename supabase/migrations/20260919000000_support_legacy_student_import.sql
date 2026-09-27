-- Amplia o modelo existente para preservar os dados da base escolar legada.
-- Não cria entidades novas: aluno, responsável, turma e matrícula já são as
-- entidades corretas para esses dados.

alter table public.students
  add column if not exists rg text,
  add column if not exists social_name text,
  add column if not exists gender text,
  add column if not exists email text,
  add column if not exists phone text,
  add column if not exists reported_age_years smallint check (reported_age_years is null or reported_age_years >= 0),
  add column if not exists reported_age_months smallint check (reported_age_months is null or reported_age_months between 0 and 11);

alter table public.guardians
  alter column phone drop not null,
  add column if not exists rg text,
  add column if not exists rg_issuer text,
  add column if not exists birth_date date,
  add column if not exists profession text,
  add column if not exists religion text,
  add column if not exists deceased boolean,
  add column if not exists address text,
  add column if not exists legacy_metadata jsonb not null default '{}'::jsonb;

alter table public.classes
  add column if not exists campus_name text,
  add column if not exists campus_city text,
  add column if not exists campus_state text;

alter table public.enrollments
  add column if not exists source_enrollment_status text,
  add column if not exists source_class_status text,
  add column if not exists legacy_metadata jsonb not null default '{}'::jsonb;

-- A base legada possui Grupos 1 a 3, anteriores ao Infantil IV já existente.
-- Reordena a sequência e recompõe a progressão sem alterar os identificadores.
update public.grades set sort_order = sort_order + 100;
update public.grades set sort_order = sort_order - 97;

insert into public.grades (code, name, stage, sort_order)
values
  ('grupo_1', 'Grupo 1', 'infantil', 1),
  ('grupo_2', 'Grupo 2', 'infantil', 2),
  ('grupo_3', 'Grupo 3', 'infantil', 3)
on conflict (code) do nothing;

update public.grades g
set next_grade_id = (
  select n.id from public.grades n where n.sort_order = g.sort_order + 1
);
