-- Segurança: RLS em todas as tabelas + permissões de execução.
-- Equipe = perfil ativo em public.profiles. Público (anon) só usa as RPCs e lê séries/valores.

create or replace function public.is_staff()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where id = auth.uid() and active)
$$;

create or replace function public.has_role(p_roles public.staff_role[])
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where id = auth.uid() and active and role = any (p_roles))
$$;

-- Operacionais: equipe lê/cria/edita; exclusão só admin e coordenação.
do $$
declare t text;
begin
  foreach t in array array['guardians', 'students', 'student_guardians', 'enrollments', 'enrollment_links',
                           'pre_enrollment_submissions', 'document_acceptances', 'installments',
                           'conversations', 'messages', 'message_queue']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy "equipe lê" on public.%I for select to authenticated using ((select public.is_staff()))', t);
    execute format('create policy "equipe cria" on public.%I for insert to authenticated with check ((select public.is_staff()))', t);
    execute format('create policy "equipe edita" on public.%I for update to authenticated using ((select public.is_staff())) with check ((select public.is_staff()))', t);
    execute format('create policy "gestão exclui" on public.%I for delete to authenticated using ((select public.has_role(''{admin,coordenacao}''::public.staff_role[])))', t);
  end loop;
end $$;

-- Cadastros da campanha: equipe lê; só admin e coordenação alteram.
do $$
declare t text;
begin
  foreach t in array array['classes', 'campaigns', 'payment_policies', 'payment_plans', 'documents',
                           'document_versions', 'campaign_documents', 'message_templates', 'whatsapp_instances']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy "equipe lê" on public.%I for select to authenticated using ((select public.is_staff()))', t);
    execute format('create policy "gestão cria" on public.%I for insert to authenticated with check ((select public.has_role(''{admin,coordenacao}''::public.staff_role[])))', t);
    execute format('create policy "gestão edita" on public.%I for update to authenticated using ((select public.has_role(''{admin,coordenacao}''::public.staff_role[]))) with check ((select public.has_role(''{admin,coordenacao}''::public.staff_role[])))', t);
    execute format('create policy "gestão exclui" on public.%I for delete to authenticated using ((select public.has_role(''{admin,coordenacao}''::public.staff_role[])))', t);
  end loop;
end $$;

-- Séries e valores são públicos (o formulário de pré-matrícula lista as séries).
do $$
declare t text;
begin
  foreach t in array array['grades', 'grade_offerings']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy "todos leem" on public.%I for select to anon, authenticated using (true)', t);
    execute format('create policy "gestão cria" on public.%I for insert to authenticated with check ((select public.has_role(''{admin,coordenacao}''::public.staff_role[])))', t);
    execute format('create policy "gestão edita" on public.%I for update to authenticated using ((select public.has_role(''{admin,coordenacao}''::public.staff_role[]))) with check ((select public.has_role(''{admin,coordenacao}''::public.staff_role[])))', t);
    execute format('create policy "gestão exclui" on public.%I for delete to authenticated using ((select public.has_role(''{admin,coordenacao}''::public.staff_role[])))', t);
  end loop;
end $$;

-- Linha do tempo é só de inserção.
alter table public.enrollment_events enable row level security;
create policy "equipe lê" on public.enrollment_events for select to authenticated using ((select public.is_staff()));
create policy "equipe cria" on public.enrollment_events for insert to authenticated with check ((select public.is_staff()));

-- Webhooks chegam pelo service_role; a equipe consulta e marca para reprocessar.
alter table public.webhook_events enable row level security;
create policy "equipe lê" on public.webhook_events for select to authenticated using ((select public.is_staff()));
create policy "equipe edita" on public.webhook_events for update to authenticated
  using ((select public.is_staff())) with check ((select public.is_staff()));

-- Perfis: cada um vê o próprio; equipe vê todos; só admin altera (evita autopromoção).
alter table public.profiles enable row level security;
create policy "lê perfis" on public.profiles for select to authenticated
  using (id = (select auth.uid()) or (select public.is_staff()));
create policy "admin cria" on public.profiles for insert to authenticated
  with check ((select public.has_role('{admin}'::public.staff_role[])));
create policy "admin edita" on public.profiles for update to authenticated
  using ((select public.has_role('{admin}'::public.staff_role[])))
  with check ((select public.has_role('{admin}'::public.staff_role[])));
create policy "admin exclui" on public.profiles for delete to authenticated
  using ((select public.has_role('{admin}'::public.staff_role[])));

-- Views: só a equipe (anon não precisa de nenhuma).
revoke all on public.v_enrollment_list, public.v_campaign_funnel, public.v_campaign_finance,
              public.v_dashboard_alerts, public.v_queue_stats, public.v_hourly_throughput,
              public.v_queue_upcoming, public.v_conversation_list, public.v_grade_offerings
  from anon;

-- Funções: nada executável por padrão; libera por papel.
revoke execute on all functions in schema public from public, anon, authenticated;

grant execute on function
  public.is_staff(),
  public.has_role(public.staff_role[]),
  public.current_profile_id(),
  public.local_today(),
  public.local_day_start(),
  public.normalize_phone_br(text),
  public.format_brl(bigint),
  public.journey_rank(public.journey_status),
  public.journey_status_label(public.journey_status),
  public.recompute_enrollment_progress(uuid),
  public.create_enrollment_link(uuid),
  public.generate_installments(uuid)
to authenticated;

grant execute on function
  public.pre_matricula_submit(text, text, text, uuid, boolean, public.shift, text, public.enrollment_origin, jsonb),
  public.rematricula_open(text),
  public.rematricula_save(text, uuid, text, text)
to anon, authenticated;

grant execute on function
  public.claim_message_batch(integer),
  public.schedule_follow_ups(),
  public.mark_overdue_installments()
to service_role;
