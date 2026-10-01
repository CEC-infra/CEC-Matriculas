-- Um WhatsApp pode pertencer a mais de um responsável (pai e mãe dividem o
-- número, ou um número muda de dono). O CPF continua identificando a pessoa.
-- A pré-matrícula usava "on conflict (phone)": passa a reutilizar o cadastro
-- mais recente com aquele número.
do $$
declare v_def text; v_old text; v_new text;
begin
  v_def := pg_get_functiondef('public.pre_matricula_submit'::regproc);
  v_old := E'  insert into public.guardians (full_name, phone, whatsapp_consent_at)\n'
        || E'  values (trim(p_guardian_name), v_phone, now())\n'
        || E'  on conflict (phone) do update\n'
        || E'    set whatsapp_consent_at = coalesce(public.guardians.whatsapp_consent_at, excluded.whatsapp_consent_at)\n'
        || E'  returning id into v_guardian;';
  v_new := E'  select id into v_guardian from public.guardians where phone = v_phone order by updated_at desc limit 1;\n'
        || E'  if v_guardian is null then\n'
        || E'    insert into public.guardians (full_name, phone, whatsapp_consent_at)\n'
        || E'    values (trim(p_guardian_name), v_phone, now())\n'
        || E'    returning id into v_guardian;\n'
        || E'  else\n'
        || E'    update public.guardians set whatsapp_consent_at = coalesce(whatsapp_consent_at, now()) where id = v_guardian;\n'
        || E'  end if;';
  if position(v_old in v_def) > 0 then
    execute replace(v_def, v_old, v_new);
  elsif position('on conflict (phone)' in v_def) > 0 then
    raise exception 'pre_matricula_submit mudou; revise este patch';
  end if;
end $$;

alter table public.guardians drop constraint if exists guardians_phone_key;
drop index if exists public.guardians_phone_key;
create index if not exists guardians_phone_idx on public.guardians (phone);
