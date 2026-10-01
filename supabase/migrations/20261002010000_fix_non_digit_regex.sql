-- Corrige o regex que remove a máscara de CPF/telefone. O padrão estava como
-- '\\D' (barra invertida literal + D), então "123.456.789-09" não virava
-- "12345678909" e todo CPF/telefone formatado era recusado.
do $$
declare v_oid oid; v_def text;
begin
  for v_oid in
    select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('onboarding_create_matricula', 'onboarding_identify_rematricula', 'staff_create_family_enrollment')
  loop
    v_def := pg_get_functiondef(v_oid);
    if position($x$'\\D'$x$ in v_def) > 0 then
      execute replace(v_def, $x$'\\D'$x$, $x$'\D'$x$);
    end if;
  end loop;
end $$;
