-- Impede novos CPFs inválidos, inclusive quando a API for chamada fora do modal.

create or replace function public.is_valid_cpf(p_cpf text)
returns boolean language plpgsql immutable set search_path = '' as $$
declare
  v_cpf text := regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g');
  v_sum integer;
  v_digit integer;
  v_index integer;
begin
  if v_cpf !~ '^[0-9]{11}$' or v_cpf ~ '^([0-9])\1{10}$' then return false; end if;
  v_sum := 0;
  for v_index in 1..9 loop v_sum := v_sum + substring(v_cpf, v_index, 1)::integer * (11 - v_index); end loop;
  v_digit := (v_sum * 10) % 11;
  if v_digit = 10 then v_digit := 0; end if;
  if v_digit <> substring(v_cpf, 10, 1)::integer then return false; end if;
  v_sum := 0;
  for v_index in 1..10 loop v_sum := v_sum + substring(v_cpf, v_index, 1)::integer * (12 - v_index); end loop;
  v_digit := (v_sum * 10) % 11;
  if v_digit = 10 then v_digit := 0; end if;
  return v_digit = substring(v_cpf, 11, 1)::integer;
end $$;

create or replace function public.guardians_validate_cpf()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.cpf is not null and not public.is_valid_cpf(new.cpf) then
    raise exception 'CPF inválido. Confira os dígitos informados.' using errcode = '22023';
  end if;
  return new;
end $$;

create trigger guardians_validate_cpf
  before insert or update of cpf on public.guardians
  for each row execute function public.guardians_validate_cpf();
