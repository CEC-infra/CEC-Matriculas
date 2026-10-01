-- Telefones legados do CEC podem estar sem DDD e/ou sem o nono dígito do
-- celular. A chave abaixo mantém o DDD quando ele foi informado; só usa 33
-- para a forma curta da base local (por exemplo, 9126-9004).
create or replace function public.phone_identity_key(
  p_phone text,
  p_default_area_code text default '33'
)
returns text language plpgsql immutable set search_path = '' as $$
declare
  v_digits text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  v_default_area_code text := regexp_replace(coalesce(p_default_area_code, ''), '\D', '', 'g');
  v_local text;
  v_ddd text;
  v_subscriber text;
begin
  if v_default_area_code !~ '^[0-9]{2}$' then return null; end if;

  if v_digits ~ '^55[0-9]{10,11}$' then
    v_local := substr(v_digits, 3);
  elsif v_digits ~ '^[0-9]{10,11}$' then
    v_local := v_digits;
  elsif v_digits ~ '^[0-9]{8,9}$' then
    v_local := v_default_area_code || v_digits;
  else
    return null;
  end if;

  v_ddd := substr(v_local, 1, 2);
  v_subscriber := substr(v_local, 3);
  if length(v_subscriber) not in (8, 9) then return null; end if;

  -- Telefones fixos (2 a 5) continuam com oito dígitos. Para celulares
  -- legados (6 a 9), acrescentamos o nono dígito que o WhatsApp usa hoje.
  if length(v_subscriber) = 8 and v_subscriber ~ '^[6789]' then
    v_subscriber := '9' || v_subscriber;
  end if;
  return '+55' || v_ddd || v_subscriber;
end $$;

-- Todos os pontos de entrada do banco passam a aceitar a forma local
-- legada e a salvar o E.164 canônico. Números brasileiros que já possuem
-- DDD preservam o DDD informado; somente a forma curta recebe o 33.
create or replace function public.normalize_phone_br(raw text)
returns text language sql immutable set search_path = '' as $$
  select coalesce(
    public.phone_identity_key(raw, '33'),
    case
      when raw ~ '^\s*\+' and d ~ '^[1-9][0-9]{7,14}$' then '+' || d
    end
  )
  from (select regexp_replace(coalesce(raw, ''), '\D', '', 'g') as d) source
$$;

-- A IA chama esta RPC apenas com a chave de serviço. Além de `phone`, ela
-- compara o telefone que veio da planilha original, preservado em
-- `legacy_metadata.source_phone`. Mais de um resultado é tratado pelo
-- agente como ambíguo e nunca associa a conversa automaticamente.
create or replace function public.find_guardians_by_phone_identity(
  p_phone text,
  p_default_area_code text default '33'
)
returns setof public.guardians language sql stable security definer set search_path = '' as $$
  with input as (
    select public.phone_identity_key(p_phone, p_default_area_code) as phone_key
  )
  select guardian.*
    from public.guardians guardian
   cross join input
   where input.phone_key is not null
     and (
       public.phone_identity_key(guardian.phone, p_default_area_code) = input.phone_key
       or public.phone_identity_key(guardian.legacy_metadata ->> 'source_phone', p_default_area_code) = input.phone_key
     )
$$;

revoke all on function public.find_guardians_by_phone_identity(text, text) from public, anon, authenticated;
grant execute on function public.find_guardians_by_phone_identity(text, text) to service_role;
