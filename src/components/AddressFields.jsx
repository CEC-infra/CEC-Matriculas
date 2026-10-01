import { useEffect, useRef, useState } from 'react';

// O banco guarda o endereço num campo só. Aqui a pessoa preenche por partes
// (com CEP de Nanuque/MG já sugerido) e o texto final é montado num formato
// único, que também conseguimos ler de volta para editar depois:
//   "Rua A, 123, Apto 2 - Centro, Nanuque/MG, CEP 39860-000"

export const DEFAULT_CEP = '39860-000';

const STATES = [
  ['AC', 'Acre'], ['AL', 'Alagoas'], ['AP', 'Amapá'], ['AM', 'Amazonas'], ['BA', 'Bahia'], ['CE', 'Ceará'],
  ['DF', 'Distrito Federal'], ['ES', 'Espírito Santo'], ['GO', 'Goiás'], ['MA', 'Maranhão'], ['MT', 'Mato Grosso'],
  ['MS', 'Mato Grosso do Sul'], ['MG', 'Minas Gerais'], ['PA', 'Pará'], ['PB', 'Paraíba'], ['PR', 'Paraná'],
  ['PE', 'Pernambuco'], ['PI', 'Piauí'], ['RJ', 'Rio de Janeiro'], ['RN', 'Rio Grande do Norte'],
  ['RS', 'Rio Grande do Sul'], ['RO', 'Rondônia'], ['RR', 'Roraima'], ['SC', 'Santa Catarina'], ['SP', 'São Paulo'],
  ['SE', 'Sergipe'], ['TO', 'Tocantins'],
];

const citiesCache = new Map();

function loadCities(uf) {
  if (!citiesCache.has(uf)) {
    citiesCache.set(uf, fetch(`https://servicodados.ibge.gov.br/api/v1/localidades/estados/${uf}/municipios?orderBy=nome`)
      .then((response) => (response.ok ? response.json() : Promise.reject(new Error('IBGE indisponível'))))
      .then((rows) => rows.map((row) => row.nome))
      .catch((error) => { citiesCache.delete(uf); throw error; }));
  }
  return citiesCache.get(uf);
}

function formatCep(value) {
  const digits = String(value || '').replace(/\D/g, '').slice(0, 8);
  return digits.length > 5 ? `${digits.slice(0, 5)}-${digits.slice(5)}` : digits;
}

const ADDRESS_RE = /^(.+?), ([^,]+?)(?:, (.+?))? - (.+?), (.+?)\/([A-Z]{2}), CEP (\d{5}-\d{3})$/;

export function parseAddress(value) {
  const match = String(value || '').trim().match(ADDRESS_RE);
  if (!match) return null;
  const [, street, number, complement = '', district, city, uf, cep] = match;
  return { street, number, complement, district, city, uf, cep };
}

export function composeAddress(parts) {
  const { street, number, complement, district, city, uf, cep } = parts;
  if (!street?.trim() || !number?.trim() || !district?.trim() || !city || !uf || String(cep).replace(/\D/g, '').length !== 8) return '';
  const extra = complement?.trim() ? `, ${complement.trim()}` : '';
  return `${street.trim()}, ${number.trim()}${extra} - ${district.trim()}, ${city}/${uf}, CEP ${formatCep(cep)}`;
}

export default function AddressFields({ value, onChange, required = true }) {
  const parsed = parseAddress(value);
  const legacy = value && !parsed ? value : '';
  const [parts, setParts] = useState(() => parsed || {
    cep: DEFAULT_CEP, uf: 'MG', city: 'Nanuque', street: '', number: '', district: '', complement: '',
  });
  const [cities, setCities] = useState([]);
  const [citiesError, setCitiesError] = useState(false);
  const [cepStatus, setCepStatus] = useState('');
  const lookedUp = useRef('');
  const touched = useRef(Boolean(parsed));

  useEffect(() => {
    let current = true;
    setCitiesError(false);
    if (!parts.uf) { setCities([]); return undefined; }
    loadCities(parts.uf).then((list) => current && setCities(list)).catch(() => current && setCitiesError(true));
    return () => { current = false; };
  }, [parts.uf]);

  // Só substitui o endereço salvo depois que a pessoa mexe nos campos.
  useEffect(() => {
    if (touched.current) onChange(composeAddress(parts));
  }, [parts]); // eslint-disable-line react-hooks/exhaustive-deps

  function update(next) {
    touched.current = true;
    setParts((current) => ({ ...current, ...next }));
  }

  async function lookupCep(raw) {
    const digits = raw.replace(/\D/g, '');
    if (digits.length !== 8 || lookedUp.current === digits) return;
    lookedUp.current = digits;
    setCepStatus('Buscando CEP…');
    try {
      const response = await fetch(`https://viacep.com.br/ws/${digits}/json/`);
      const data = await response.json();
      if (data.erro) { setCepStatus('CEP não encontrado. Preencha cidade e estado abaixo.'); return; }
      setCepStatus('');
      setParts((current) => ({
        ...current,
        uf: data.uf || current.uf,
        city: data.localidade || current.city,
        street: data.logradouro || current.street,
        district: data.bairro || current.district,
      }));
    } catch {
      setCepStatus('Não conseguimos consultar o CEP agora. Preencha os campos abaixo.');
    }
  }

  return <div className="address-fields">
    {legacy ? <p className="address-fields__legacy">Endereço atual: <strong>{legacy}</strong>. Preencha os campos abaixo para atualizar.</p> : null}
    <div className="field address-fields__cep"><label>CEP</label><input className="control" inputMode="numeric" maxLength={9} required={required} value={parts.cep} placeholder="00000-000"
      onChange={(event) => { const cep = formatCep(event.target.value); update({ cep }); lookupCep(cep); }} />{cepStatus ? <small className="address-fields__hint">{cepStatus}</small> : null}</div>
    <div className="field address-fields__uf"><label>Estado</label><select className="control" required={required} value={parts.uf} onChange={(event) => update({ uf: event.target.value, city: '' })}>
      <option value="">Selecione</option>{STATES.map(([uf, name]) => <option key={uf} value={uf}>{name}</option>)}</select></div>
    <div className="field address-fields__city"><label>Cidade</label>{citiesError
      ? <input className="control" required={required} value={parts.city} onChange={(event) => update({ city: event.target.value })} placeholder="Nome da cidade" />
      : <select className="control" required={required} value={parts.city} onChange={(event) => update({ city: event.target.value })} disabled={!parts.uf}>
        <option value="">{parts.uf ? (cities.length ? 'Selecione' : 'Carregando…') : 'Escolha o estado'}</option>
        {parts.city && !cities.includes(parts.city) ? <option value={parts.city}>{parts.city}</option> : null}
        {cities.map((city) => <option key={city} value={city}>{city}</option>)}</select>}</div>
    <div className="field address-fields__street"><label>Rua</label><input className="control" required={required} value={parts.street} onChange={(event) => update({ street: event.target.value })} placeholder="Rua, avenida, travessa…" /></div>
    <div className="field address-fields__number"><label>Número</label><input className="control" required={required} value={parts.number} onChange={(event) => update({ number: event.target.value })} placeholder="Ex.: 120 ou S/N" /></div>
    <div className="field address-fields__district"><label>Bairro</label><input className="control" required={required} value={parts.district} onChange={(event) => update({ district: event.target.value })} /></div>
    <div className="field address-fields__complement"><label>Complemento (opcional)</label><input className="control" value={parts.complement} onChange={(event) => update({ complement: event.target.value })} placeholder="Apto, bloco, casa…" /></div>
  </div>;
}
