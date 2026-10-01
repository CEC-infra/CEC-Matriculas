import { useEffect, useMemo, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { Field, LogoBlocks } from '../components/ui';
import DataState from '../components/DataState';
import cecLogo from '../assets/cec-logo.png';
import AddressFields from '../components/AddressFields';
import { PaymentChoiceBar, SignedContracts, ValuesStep } from '../components/RematriculaValues';
import { formatCpf, formatPhoneBr, isValidCpf, isValidEmail, isValidPhoneBr, money } from '../lib/format';
import {
  chooseOnboardingPayment, chooseRematriculaPaymentOption, createMatriculaOnboarding, getPublicOfferings,
  identifyRematriculaOnboarding, openEnrollmentOnboarding, prepareOnboardingContract,
  lookupExistingFamilyForNewEnrollment, prepareFamilyContract, selectRematriculaChildren, startEnrollmentOnboarding,
  startRematriculaFromNewEnrollment
} from '../services/data';

const emptyChild = { name: '', birthDate: '', birthParts: { day: '', month: '', year: '' }, gradeId: '', previousSchool: '' };
const newFamily = { cpf: '', fullName: '', phone: '', email: '', address: '', children: [{ ...emptyChild }] };

// Erros do formulário de matrícula nova. Só aparecem depois que a pessoa sai
// do campo (touched) ou tenta enviar, para não acusar erro no meio da digitação.
function newFamilyErrors(family) {
  const today = new Date();
  const oldest = new Date(today.getFullYear() - 25, today.getMonth(), today.getDate());
  return {
    cpf: !isValidCpf(family.cpf) ? (family.cpf ? 'Esse CPF não existe. Confira os 11 dígitos.' : 'Informe o CPF do responsável.') : '',
    phone: !isValidPhoneBr(family.phone) ? 'Informe o WhatsApp com DDD, ex.: (33) 9 9999-9999.' : '',
    email: !isValidEmail(family.email) ? 'Informe um e-mail válido, ex.: nome@gmail.com.' : '',
    address: !family.address ? 'Complete o endereço: CEP, cidade, rua, número e bairro.' : '',
    children: family.children.map((child) => {
      const { day, month, year } = child.birthParts || {};
      const filled = [day, month, year].filter(Boolean).length;
      if (filled === 0) return '';
      if (filled < 3) return 'Complete dia, mês e ano.';
      const value = new Date(Number(year), Number(month) - 1, Number(day));
      if (value > today) return 'A data de nascimento não pode ser no futuro.';
      if (value < oldest) return 'Confira o ano de nascimento.';
      return '';
    }),
  };
}

const MONTHS = ['Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho', 'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'];

// Data de nascimento em três listas: o ano começa pelo mais recente (crianças)
// e nada depois de hoje aparece como opção.
function BirthDateSelect({ parts, onChange }) {
  const today = new Date();
  const { day = '', month = '', year = '' } = parts || {};
  const years = Array.from({ length: 21 }, (_, index) => String(today.getFullYear() - index));
  const isCurrentYear = Number(year) === today.getFullYear();
  const maxMonth = isCurrentYear ? today.getMonth() + 1 : 12;
  const daysInMonth = month ? new Date(Number(year) || 2000, Number(month), 0).getDate() : 31;
  const maxDay = isCurrentYear && Number(month) === today.getMonth() + 1 ? today.getDate() : daysInMonth;
  function update(next) {
    const merged = { day, month, year, ...next };
    // Ajusta o que ficou impossível depois de trocar ano ou mês (ex.: 31 → fevereiro).
    const mergedCurrentYear = Number(merged.year) === today.getFullYear();
    if (mergedCurrentYear && Number(merged.month) > today.getMonth() + 1) merged.month = '';
    const limit = merged.month
      ? (mergedCurrentYear && Number(merged.month) === today.getMonth() + 1 ? today.getDate() : new Date(Number(merged.year) || 2000, Number(merged.month), 0).getDate())
      : 31;
    if (Number(merged.day) > limit) merged.day = '';
    const iso = merged.day && merged.month && merged.year ? `${merged.year}-${merged.month.padStart(2, '0')}-${merged.day.padStart(2, '0')}` : '';
    onChange(merged, iso);
  }
  return <div className="field"><label>Data de nascimento</label><div className="birth-select">
    <select className="control" aria-label="Dia" value={day} onChange={(event) => update({ day: event.target.value })}><option value="">Dia</option>{Array.from({ length: maxDay }, (_, index) => String(index + 1)).map((item) => <option key={item} value={item}>{item}</option>)}</select>
    <select className="control" aria-label="Mês" value={month} onChange={(event) => update({ month: event.target.value })}><option value="">Mês</option>{MONTHS.slice(0, maxMonth).map((label, index) => <option key={label} value={String(index + 1)}>{label}</option>)}</select>
    <select className="control" aria-label="Ano" value={year} onChange={(event) => update({ year: event.target.value })}><option value="">Ano</option>{years.map((item) => <option key={item} value={item}>{item}</option>)}</select>
  </div></div>;
}

function FieldError({ show, message }) {
  return show && message ? <small className="field-error">{message}</small> : null;
}

function Stepper({ step, flow }) {
  const labels = flow === 'rematricula' ? ['Identificação', 'Alunos', 'Valores', 'Assinaturas', 'Concluir'] : ['Dados', 'Assinaturas', 'Cobrança'];
  // Matrícula nova: o banco usa 1 (dados), 3 (contratos) e 4+ (cobrança).
  const position = flow === 'rematricula' ? step : step >= 4 ? 3 : step === 3 ? 2 : 1;
  return <div className="steps onboarding-steps">{labels.map((label, index) => <div className={`step${index + 1 <= position ? ' is-done' : ''}`} key={label}><i /><span>{label}</span></div>)}</div>;
}

function Title({ flow, step, multi }) {
  const remat = flow === 'rematricula';
  const heading = remat
    ? (step <= 1 ? 'Vamos encontrar sua família' : step === 2 ? 'Confirme quem vai continuar em 2027' : step === 3 ? 'Confira os valores e monte seu pagamento' : step === 4 ? (multi ? 'Assine os contratos de uma vez' : 'Assine o contrato') : 'Tudo pronto para concluir')
    : (step <= 1 ? 'Comece a matrícula da sua família' : step === 3 ? (multi ? 'Assine os contratos de uma vez' : 'Assine o contrato') : 'Como prefere receber a cobrança?');
  return <div className="public-head--navy onboarding-head"><div style={{ display: 'flex', alignItems: 'center', gap: 12 }}><LogoBlocks /><span className="public-kicker">{remat ? 'Rematrícula 2027' : 'Matrícula 2027'}</span></div><h2>{heading}</h2><p>Você pode fechar esta página e continuar depois pelo mesmo link. Seus avanços ficam salvos com segurança.</p></div>;
}

function ExistingFamilyMatch({ match, busy, onStartRematricula, onContinueNewEnrollment }) {
  if (!match?.found) return null;
  const children = match.children || [];
  return <div className="onboarding-existing-family-modal" role="dialog" aria-modal="true" aria-labelledby="existing-family-title">
    <div className="onboarding-existing-family-modal__backdrop" />
    <section className="onboarding-existing-family">
      <span className="onboarding-existing-family__eyebrow">Cadastro localizado</span>
      <h3 id="existing-family-title">{match.guardian?.name}, este é o seu nome?</h3>
      <p>Encontramos este responsável usando o CPF ou WhatsApp informado.</p>
      {children.length ? <div className="onboarding-existing-family__children"><strong>Estes alunos estão vinculados a este cadastro:</strong>{children.map((child) => <div key={`${child.name}-${child.current_grade || ''}`}><span>{child.name}</span><small>{child.current_grade ? `${child.current_grade} → ${child.target_grade || 'série a confirmar'}` : 'Série a confirmar'}</small></div>)}</div> : null}
      <p className="onboarding-existing-family__question">{children.length ? 'Você deseja fazer a rematrícula de algum deles?' : 'Quer usar este cadastro para uma rematrícula?'}</p>
      <div className="onboarding-existing-family__actions">
        <button type="button" className="btn btn--primary" onClick={onStartRematricula} disabled={busy}>{busy ? 'Abrindo rematrícula…' : 'Sim, quero fazer rematrícula'}</button>
        <button type="button" className="btn" onClick={onContinueNewEnrollment} disabled={busy}>Não, quero matricular outro filho</button>
      </div>
    </section>
  </div>;
}

export default function EnrollmentOnboarding({ initialFlow = null }) {
  const navigate = useNavigate();
  const [params, setParams] = useSearchParams();
  // Com só ?j= na URL (ex.: depois de um F5), a própria jornada diz se é
  // matrícula nova ou rematrícula.
  const [flow, setFlow] = useState(initialFlow || params.get('f') || (params.get('j') ? 'auto' : null));
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(Boolean(initialFlow));
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState('');
  const [lookup, setLookup] = useState({ cpf: '', fullName: '', phone: '' });
  const [family, setFamily] = useState(newFamily);
  const [touched, setTouched] = useState({});
  const [triedSubmit, setTriedSubmit] = useState(false);
  const [existingFamily, setExistingFamily] = useState(null);
  const [existingFamilyLoading, setExistingFamilyLoading] = useState(false);
  const [selected, setSelected] = useState([]);
  const [email, setEmail] = useState('');
  const [payment, setPayment] = useState({ method: 'pix' });
  const [offerings, setOfferings] = useState([]);
  const [editing, setEditing] = useState(null); // 'children' | 'values' — volta a uma etapa já concluída
  const [finishing, setFinishing] = useState(false);
  const [oneByOne, setOneByOne] = useState(false);
  const token = params.get('j');

  const gradeOptions = useMemo(() => offerings.map((item) => ({ value: item.grade_id, label: `${item.grades?.name || 'Série'} · ${money(item.amount_cents)}` })), [offerings]);

  useEffect(() => { getPublicOfferings().then((result) => setOfferings(result.offerings || [])).catch(() => {}); }, []);
  useEffect(() => {
    if (!flow) return undefined;
    let current = true;
    setLoading(true); setError('');
    const request = token ? openEnrollmentOnboarding(token) : startEnrollmentOnboarding(flow);
    request.then((result) => {
      if (!current) return;
      if (flow === 'auto' && result?.flow) setFlow(result.flow);
      if (!token && result?.token) setParams({ j: result.token, f: flow }, { replace: true });
      setData(result);
      if (result?.guardian?.email) setEmail(result.guardian.email);
      if (result?.children) setSelected(result.children.filter((item) => item.selected && item.eligible !== false).map((item) => item.student_id));
    }).catch((reason) => current && setError(reason.message || 'Não foi possível abrir esta jornada.')).finally(() => current && setLoading(false));
    return () => { current = false; };
  }, [flow, token, setParams]);
  useEffect(() => {
    const cpf = family.cpf.replace(/\D/g, '');
    const phone = family.phone.replace(/\D/g, '');
    if (flow !== 'matricula_nova' || !token || (cpf.length !== 11 && phone.length < 10)) {
      setExistingFamily(null);
      setExistingFamilyLoading(false);
      return undefined;
    }
    let current = true;
    const timer = window.setTimeout(() => {
      setExistingFamilyLoading(true);
      lookupExistingFamilyForNewEnrollment(token, family)
        .then((result) => current && setExistingFamily(result?.found ? result : null))
        .catch(() => current && setExistingFamily(null))
        .finally(() => current && setExistingFamilyLoading(false));
    }, 500);
    return () => { current = false; window.clearTimeout(timer); };
  }, [flow, token, family.cpf, family.phone]);

  function chooseFlow(nextFlow) {
    setFlow(nextFlow);
    setParams({}, { replace: true });
  }
  function apply(next) {
    setData(next); setError(''); setEditing(null);
    if (next?.guardian?.email) setEmail(next.guardian.email);
    if (next?.children) setSelected(next.children.filter((item) => item.selected && item.eligible !== false).map((item) => item.student_id));
  }
  async function identify(event) {
    event.preventDefault(); setBusy(true); setNotice('');
    try { apply(await identifyRematriculaOnboarding(token, lookup)); }
    catch (reason) { setNotice(reason.message || 'Não foi possível localizar a família.'); }
    finally { setBusy(false); }
  }
  async function selectChildren(event) {
    event.preventDefault(); setBusy(true); setNotice('');
    try { apply(await selectRematriculaChildren(token, selected)); }
    catch (reason) { setNotice(reason.message || 'Não foi possível salvar os alunos selecionados.'); }
    finally { setBusy(false); }
  }
  async function saveNewFamily(event) {
    event.preventDefault();
    setTriedSubmit(true);
    const errors = newFamilyErrors(family);
    if (errors.cpf || errors.phone || errors.email || errors.address || errors.children.some(Boolean)) {
      setNotice('Confira os campos destacados antes de continuar.');
      return;
    }
    setBusy(true); setNotice('');
    try { apply(await createMatriculaOnboarding(token, family)); }
    catch (reason) { setNotice(reason.message || 'Não foi possível salvar a matrícula.'); }
    finally { setBusy(false); }
  }
  async function startMatchedRematricula() {
    setBusy(true); setNotice('');
    try {
      const result = await startRematriculaFromNewEnrollment(token, family);
      navigate(`/rematricula?j=${encodeURIComponent(result.token)}`);
    } catch (reason) { setNotice(reason.message || 'Não foi possível abrir a rematrícula desta família.'); }
    finally { setBusy(false); }
  }
  function continueWithNewChild() {
    setFamily((current) => ({
      ...current,
      cpf: formatCpf(existingFamily?.guardian?.cpf || current.cpf),
      fullName: existingFamily?.guardian?.name || current.fullName,
      phone: formatPhoneBr(existingFamily?.guardian?.phone || current.phone),
      email: existingFamily?.guardian?.email || current.email,
      address: existingFamily?.guardian?.address || current.address
    }));
    setExistingFamily(null);
  }
  function updateNewFamily(field, value) {
    setFamily((current) => ({ ...current, [field]: value }));
    if (field === 'cpf' || field === 'phone') setExistingFamily(null);
  }
  async function prepareContract(enrollmentId) {
    setBusy(true); setNotice('');
    try {
      const result = await prepareOnboardingContract(token, enrollmentId, email || data.guardian?.email);
      navigate(`${result.url}?j=${encodeURIComponent(token)}&f=${encodeURIComponent(flow)}`);
    } catch (reason) { setNotice(reason.message || 'Não foi possível preparar o contrato.'); }
    finally { setBusy(false); }
  }
  async function confirmValues(option) {
    setBusy(true); setNotice('');
    try { apply(await chooseRematriculaPaymentOption(token, option)); window.scrollTo({ top: 0, behavior: 'smooth' }); }
    catch (reason) { setNotice(reason.message || 'Não foi possível salvar a forma de pagamento.'); }
    finally { setBusy(false); }
  }
  async function concludeRematricula() {
    setBusy(true); setNotice('');
    try { apply(await chooseOnboardingPayment(token, null, data.payment_choice?.method || 'pix')); }
    catch (reason) { setNotice(reason.message || 'Não foi possível concluir a rematrícula.'); }
    finally { setBusy(false); }
  }
  async function prepareAllContracts() {
    setBusy(true); setNotice('');
    try {
      const result = await prepareFamilyContract(token, email || data.guardian?.email);
      navigate(`${result.url}?j=${encodeURIComponent(token)}&f=${encodeURIComponent(flow)}`);
    } catch (reason) { setNotice(reason.message || 'Não foi possível preparar os contratos.'); }
    finally { setBusy(false); }
  }
  async function choosePayment(event) {
    event.preventDefault(); setBusy(true); setNotice('');
    try { apply(await chooseOnboardingPayment(token, null, payment.method)); setNotice('Preferência registrada. A escola enviará a cobrança pelo meio escolhido.'); }
    catch (reason) { setNotice(reason.message || 'Não foi possível registrar a opção de pagamento.'); }
    finally { setBusy(false); }
  }
  function updateChild(index, key, value) {
    setFamily((current) => ({ ...current, children: current.children.map((child, childIndex) => childIndex === index ? { ...child, [key]: value } : child) }));
  }
  function updateBirthDate(index, parts, iso) {
    setFamily((current) => ({ ...current, children: current.children.map((child, childIndex) => childIndex === index ? { ...child, birthParts: parts, birthDate: iso } : child) }));
  }
  function removeChild(index) { setFamily((current) => ({ ...current, children: current.children.filter((_, childIndex) => childIndex !== index) })); }

  if (!flow) return <main className="onboarding-page"><section className="onboarding-shell"><div className="onboarding-choice"><img className="onboarding-choice-logo" src={cecLogo} alt="Centro Educacional Cristão" /><span>CEC · 2027</span><h1>Como podemos ajudar?</h1><p>Escolha a jornada para começar. Você receberá um link seguro para continuar de onde parou.</p><div className="onboarding-choice-actions"><button type="button" className="cta" onClick={() => chooseFlow('matricula_nova')}>Quero fazer uma matrícula nova</button><button type="button" className="btn" onClick={() => chooseFlow('rematricula')}>Quero fazer uma rematrícula</button></div></div></section></main>;

  const serverStep = data?.step || 1;
  const remat = flow === 'rematricula';
  // Rematrícula: a etapa Valores (3) fica entre Alunos e Assinaturas. O banco
  // guarda as assinaturas como passo 3; a escolha de pagamento marca values_confirmed.
  const step = !remat ? serverStep
    : editing === 'children' ? 2
    : editing === 'values' ? 3
    : data?.status === 'concluida' ? 5
    : serverStep >= 4 || finishing ? 5
    : serverStep === 3 ? (data?.values_confirmed ? 4 : 3)
    : serverStep;
  const selectedChildren = (data?.children || []).filter((child) => child.selected);
  const eligibleChildren = (data?.children || []).filter((child) => child.eligible !== false);
  const selectedEligibleChildren = selected.filter((studentId) => eligibleChildren.some((child) => child.student_id === studentId));
  const allSigned = selectedChildren.length > 0 && selectedChildren.every((child) => child.contract_status === 'assinada');
  const pendingChildren = selectedChildren.filter((child) => child.contract_status !== 'assinada');
  const pendingTokens = [...new Set(pendingChildren.map((child) => child.contract_token).filter(Boolean))];
  // Um token comum a todos os pendentes = já existe uma sessão de família aberta.
  const sharedContractToken = pendingChildren.length > 1 && pendingTokens.length === 1 && pendingChildren.every((child) => child.contract_token) ? pendingTokens[0] : null;
  const familySign = pendingChildren.length > 1 && !oneByOne;
  // Assinaturas: igual na matrícula nova e na rematrícula. Com 2+ filhos
  // pendentes, a família assina todos de uma vez (cada um com seu PDF).
  const signingSection = (withPaymentBar) => <section className="onboarding-form">
    {withPaymentBar ? <PaymentChoiceBar data={data} onChange={() => setEditing('values')} /> : null}
    {familySign ? null : <div className="onboarding-guardian"><strong>Assinaturas pendentes</strong><span>{pendingChildren.length > 1 ? 'Você assinará um contrato por aluno.' : 'Confira o e-mail e prepare o contrato.'} Depois volte para este mesmo link para acompanhar.</span></div>}
    <Field label="E-mail para confirmação das assinaturas" type="email" value={email} onChange={setEmail} required />
    {familySign ? <div className="family-sign"><div className="family-sign__head"><strong>Assine os {pendingChildren.length} contratos de uma vez</strong><span>Um código por e-mail e uma assinatura só, aplicada em cada contrato. Cada aluno continua com o seu PDF.</span></div><ul>{pendingChildren.map((child) => <li key={child.enrollment_id}><span>{child.name}<small>{child.target_grade}</small></span><b>{money(child.amount_cents)}</b></li>)}<li className="family-sign__total"><span>Total</span><b>{money(pendingChildren.reduce((sum, child) => sum + (Number(child.amount_cents) || 0), 0))}</b></li></ul><button className="cta" onClick={() => sharedContractToken ? navigate(`/contrato/${sharedContractToken}?j=${encodeURIComponent(token)}&f=${flow}`) : prepareAllContracts()} disabled={busy}>{busy ? 'Preparando…' : sharedContractToken ? 'Continuar assinatura dos contratos →' : `Assinar os ${pendingChildren.length} contratos juntos →`}</button><button type="button" className="text-link" onClick={() => setOneByOne(true)}>Prefiro assinar um por vez</button></div>
      : <div className="onboarding-contract-list">{pendingChildren.length > 1 ? <button type="button" className="btn family-sign__switch" onClick={() => setOneByOne(false)}>Assinar os {pendingChildren.length} contratos juntos</button> : null}{selectedChildren.map((child) => <article className="onboarding-contract-card" key={child.enrollment_id}><div><strong>{child.name}</strong><span>{child.target_grade}{child.amount_cents ? ` · ${money(child.amount_cents)}` : ''}</span></div>{child.contract_status === 'assinada' ? <span className="badge badge--green">Assinado</span> : <button className="btn btn--primary" onClick={() => child.contract_token ? navigate(`/contrato/${child.contract_token}?j=${encodeURIComponent(token)}&f=${flow}`) : prepareContract(child.enrollment_id)} disabled={busy}>{child.contract_token ? 'Continuar assinatura' : 'Preparar contrato'}</button>}</article>)}</div>}
    {allSigned ? (withPaymentBar
      ? <button className="cta" onClick={() => setFinishing(true)}>Seguir para concluir →</button>
      : <button className="cta" onClick={() => apply({ ...data, step: 4, status: 'pagamento' })}>Seguir para pagamento →</button>) : null}
  </section>;
  return <DataState loading={loading} error={error} empty={false}>{data ? <main className="onboarding-page"><section className="public onboarding-shell"><Title flow={flow} step={step} multi={familySign} /><Stepper flow={flow} step={step} /><div className="public-body onboarding-body">
    {flow === 'rematricula' && step <= 1 ? <form onSubmit={identify} className="onboarding-form"><p className="meta">Para proteger os dados da família, confirmamos CPF e WhatsApp antes de apresentar os alunos vinculados.</p><div className="grid grid--2"><Field label="CPF do responsável" ph="000.000.000-00" value={lookup.cpf} onChange={(value) => setLookup((v) => ({ ...v, cpf: formatCpf(value) }))} inputMode="numeric" maxLength={14} required /><Field label="WhatsApp" ph="(33) 9 9999-9999" value={lookup.phone} onChange={(value) => setLookup((v) => ({ ...v, phone: formatPhoneBr(value) }))} inputMode="tel" maxLength={16} required /><Field label="Nome completo" ph="Opcional, para confirmar" value={lookup.fullName} onChange={(value) => setLookup((v) => ({ ...v, fullName: value }))} /></div><button className="cta" disabled={busy}>{busy ? 'Localizando…' : 'Continuar →'}</button></form> : null}
    {flow === 'matricula_nova' && step <= 1 ? (() => {
      const errors = newFamilyErrors(family);
      const show = (field) => triedSubmit || touched[field];
      const touch = (field) => () => setTouched((current) => ({ ...current, [field]: true }));
      return <form onSubmit={saveNewFamily} className="onboarding-form" noValidate><div className="grid grid--2">
        <div onBlur={touch('cpf')}><Field label="CPF do responsável" ph="000.000.000-00" value={family.cpf} onChange={(value) => updateNewFamily('cpf', formatCpf(value))} inputMode="numeric" maxLength={14} required /><FieldError show={show('cpf') || family.cpf.length === 14} message={errors.cpf} /></div>
        <Field label="Nome completo do responsável" value={family.fullName} onChange={(value) => updateNewFamily('fullName', value)} required />
        <div onBlur={touch('phone')}><Field label="WhatsApp" ph="(33) 9 9999-9999" value={family.phone} onChange={(value) => updateNewFamily('phone', formatPhoneBr(value))} inputMode="tel" maxLength={16} required /><FieldError show={show('phone')} message={errors.phone} /></div>
        <div onBlur={touch('email')}><Field label="E-mail" type="email" ph="nome@gmail.com" value={family.email} onChange={(value) => updateNewFamily('email', value.trim())} inputMode="email" required /><FieldError show={show('email')} message={errors.email} /></div>
      </div>
      <div className="onboarding-address" onBlur={touch('address')}><h3>Endereço do responsável</h3><AddressFields key={existingFamily ? 'existente' : 'novo'} value={family.address} onChange={(value) => updateNewFamily('address', value)} /><FieldError show={show('address')} message={errors.address} /></div>{existingFamilyLoading ? <span className="meta">Verificando se já existe um cadastro com estes dados…</span> : null}<ExistingFamilyMatch match={existingFamily} busy={busy} onStartRematricula={startMatchedRematricula} onContinueNewEnrollment={continueWithNewChild} /><div className="onboarding-child-editor"><div><h3>Alunos</h3><p>Inclua todos os filhos que deseja matricular agora.</p></div>{family.children.map((child, index) => <div className="onboarding-child-fields" key={index}>
        <Field label="Nome completo do aluno" value={child.name} onChange={(value) => updateChild(index, 'name', value)} required />
        <Field label="Série pretendida" type="select" options={gradeOptions} value={child.gradeId} onChange={(value) => updateChild(index, 'gradeId', value)} required />
        <div onBlur={touch(`birth${index}`)}><BirthDateSelect parts={child.birthParts} onChange={(parts, iso) => updateBirthDate(index, parts, iso)} /><FieldError show={show(`birth${index}`)} message={errors.children[index]} /></div>
        <Field label="Escola anterior (opcional)" ph="Se o aluno já estudou em outra escola" value={child.previousSchool} onChange={(value) => updateChild(index, 'previousSchool', value)} />
        {family.children.length > 1 ? <button type="button" className="text-link" onClick={() => removeChild(index)}>Remover aluno</button> : null}</div>)}<button type="button" className="btn" onClick={() => setFamily((v) => ({ ...v, children: [...v.children, { ...emptyChild }] }))}>+ Adicionar outro filho</button></div><button className="cta" disabled={busy}>{busy ? 'Salvando…' : 'Continuar para contratos →'}</button></form>;
    })() : null}
    {flow === 'rematricula' && step === 2 ? <form onSubmit={selectChildren} className="onboarding-form"><div className="onboarding-guardian"><strong>{data.guardian?.name}</strong><span>Estes alunos foram encontrados como vinculados ao seu cadastro.</span></div><div className="onboarding-children">{data.children?.map((child) => <label className={`onboarding-child-card${selected.includes(child.student_id) ? ' is-selected' : ''}${child.eligible === false ? ' is-unavailable' : ''}`} key={child.student_id}><input type="checkbox" disabled={child.eligible === false} checked={selected.includes(child.student_id)} onChange={(event) => setSelected((items) => event.target.checked ? [...items, child.student_id] : items.filter((id) => id !== child.student_id))} /><span><strong>{child.name}</strong><small>{child.current_grade ? `${child.current_grade} → ` : ''}{child.target_grade || 'Série a confirmar'}</small>{child.eligible === false ? <small>{child.eligibility_reason}</small> : null}</span></label>)}</div>{!eligibleChildren.length ? <div className="notice"><span>Nenhum aluno deste cadastro está pronto para a rematrícula. Fale com a secretaria para corrigir a turma ou o valor de 2027.</span></div> : null}<button className="cta" disabled={busy || !selectedEligibleChildren.length}>{busy ? 'Salvando…' : 'Confirmar alunos →'}</button></form> : null}
    {!remat && step === 3 ? signingSection(false) : null}
    {!remat && data.status === 'concluida' ? <div className="notice"><span>Matrícula concluída. A cobrança ainda será enviada pela escola pelo meio escolhido.</span></div> : null}
    {!remat && step >= 4 && data.status !== 'concluida' ? <form onSubmit={choosePayment} className="onboarding-form"><div className="onboarding-guardian"><strong>Forma de pagamento</strong><span>Na rematrícula concluída até 31/10, o valor promocional é dividido em novembro, dezembro e janeiro. Depois, vale a tabela de 2027 com pagamento único em janeiro. Informe sua preferência; você não será cobrado nesta etapa.</span></div><div className="onboarding-methods"><button type="button" className={`btn${payment.method === 'cartao' ? ' btn--primary' : ''}`} onClick={() => setPayment({ method: 'cartao' })}>Cartão</button><button type="button" className={`btn${payment.method === 'pix' ? ' btn--primary' : ''}`} onClick={() => setPayment({ method: 'pix' })}>Pix</button></div><button className="cta" disabled={busy}>{busy ? 'Registrando…' : 'Registrar preferência'}</button></form> : null}
    {remat && step === 3 ? <ValuesStep key={data.payment_choice?.option || 'novo'} data={data} busy={busy} onConfirm={confirmValues} onEditChildren={() => setEditing('children')} /> : null}
    {remat && step === 4 ? signingSection(true) : null}
    {remat && step === 5 ? <section className="onboarding-form values-finish">{data.status === 'concluida' ? <div className="values-done"><strong>Rematrícula concluída 🎉</strong><span>Seus contratos estão assinados e a forma de pagamento foi registrada. O link de pagamento será enviado aqui na página e pelo WhatsApp.</span></div> : <div className="onboarding-guardian"><strong>Contratos assinados</strong><span>Confira a forma de pagamento e conclua. Você pode baixar uma cópia de cada contrato assinado.</span></div>}<PaymentChoiceBar data={data} /><SignedContracts data={data} />{data.status === 'concluida' ? <div className="values-checkout"><strong>Pagamento</strong><span>O checkout ainda não está disponível. Assim que for liberado, o botão de pagamento aparecerá aqui.</span><button type="button" className="btn" disabled>Ir para o pagamento</button></div> : <button className="cta" disabled={busy} onClick={concludeRematricula}>{busy ? 'Concluindo…' : 'Concluir rematrícula →'}</button>}</section> : null}
    {notice ? <div className="notice"><span>{notice}</span></div> : null}
  </div></section></main> : null}</DataState>;
}
