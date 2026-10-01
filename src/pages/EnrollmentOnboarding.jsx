import { useEffect, useMemo, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { Field, LogoBlocks } from '../components/ui';
import DataState from '../components/DataState';
import cecLogo from '../assets/cec-logo.png';
import { formatCpf, formatPhoneBr, money } from '../lib/format';
import {
  chooseOnboardingPayment, createMatriculaOnboarding, getPublicOfferings,
  identifyRematriculaOnboarding, openEnrollmentOnboarding, prepareOnboardingContract,
  lookupExistingFamilyForNewEnrollment, selectRematriculaChildren, startEnrollmentOnboarding,
  startRematriculaFromNewEnrollment
} from '../services/data';

const newFamily = { cpf: '', fullName: '', phone: '', email: '', address: '', children: [{ name: '', birthDate: '', gradeId: '', previousSchool: '' }] };

function Stepper({ step, flow }) {
  const labels = flow === 'rematricula' ? ['Identificação', 'Alunos', 'Assinaturas', 'Cobrança'] : ['Dados', 'Assinaturas', 'Cobrança'];
  return <div className="steps onboarding-steps">{labels.map((label, index) => <div className={`step${index + 1 <= step ? ' is-done' : ''}`} key={label}><i /><span>{label}</span></div>)}</div>;
}

function Title({ flow, step }) {
  const remat = flow === 'rematricula';
  const heading = remat
    ? (step <= 1 ? 'Vamos encontrar sua família' : step === 2 ? 'Confirme quem vai continuar em 2027' : step === 3 ? 'Uma assinatura para cada aluno' : 'Como prefere receber a cobrança?')
    : (step <= 1 ? 'Comece a matrícula da sua família' : step === 3 ? 'Uma assinatura para cada aluno' : 'Como prefere receber a cobrança?');
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
  const [flow, setFlow] = useState(initialFlow || params.get('f') || null);
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(Boolean(initialFlow));
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState('');
  const [lookup, setLookup] = useState({ cpf: '', fullName: '', phone: '' });
  const [family, setFamily] = useState(newFamily);
  const [existingFamily, setExistingFamily] = useState(null);
  const [existingFamilyLoading, setExistingFamilyLoading] = useState(false);
  const [selected, setSelected] = useState([]);
  const [email, setEmail] = useState('');
  const [payment, setPayment] = useState({ method: 'pix' });
  const [offerings, setOfferings] = useState([]);
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
      if (!token && result?.token) setParams({ j: result.token }, { replace: true });
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
    setData(next); setError('');
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
    event.preventDefault(); setBusy(true); setNotice('');
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
  async function choosePayment(event) {
    event.preventDefault(); setBusy(true); setNotice('');
    try { apply(await chooseOnboardingPayment(token, null, payment.method)); setNotice('Preferência registrada. A escola enviará a cobrança pelo meio escolhido.'); }
    catch (reason) { setNotice(reason.message || 'Não foi possível registrar a opção de pagamento.'); }
    finally { setBusy(false); }
  }
  function updateChild(index, key, value) {
    setFamily((current) => ({ ...current, children: current.children.map((child, childIndex) => childIndex === index ? { ...child, [key]: value } : child) }));
  }
  function removeChild(index) { setFamily((current) => ({ ...current, children: current.children.filter((_, childIndex) => childIndex !== index) })); }

  if (!flow) return <main className="onboarding-page"><section className="onboarding-shell"><div className="onboarding-choice"><img className="onboarding-choice-logo" src={cecLogo} alt="Centro Educacional Cristão" /><span>CEC · 2027</span><h1>Como podemos ajudar?</h1><p>Escolha a jornada para começar. Você receberá um link seguro para continuar de onde parou.</p><div className="onboarding-choice-actions"><button type="button" className="cta" onClick={() => chooseFlow('matricula_nova')}>Quero fazer uma matrícula nova</button><button type="button" className="btn" onClick={() => chooseFlow('rematricula')}>Quero fazer uma rematrícula</button></div></div></section></main>;

  const step = data?.step || (flow === 'rematricula' ? 1 : 1);
  const selectedChildren = (data?.children || []).filter((child) => child.selected);
  const eligibleChildren = (data?.children || []).filter((child) => child.eligible !== false);
  const selectedEligibleChildren = selected.filter((studentId) => eligibleChildren.some((child) => child.student_id === studentId));
  const allSigned = selectedChildren.length > 0 && selectedChildren.every((child) => child.contract_status === 'assinada');
  return <DataState loading={loading} error={error} empty={false}>{data ? <main className="onboarding-page"><section className="public onboarding-shell"><Title flow={flow} step={step} /><Stepper flow={flow} step={step} /><div className="public-body onboarding-body">
    {flow === 'rematricula' && step <= 1 ? <form onSubmit={identify} className="onboarding-form"><p className="meta">Para proteger os dados da família, confirmamos CPF e WhatsApp antes de apresentar os alunos vinculados.</p><div className="grid grid--2"><Field label="CPF do responsável" ph="000.000.000-00" value={lookup.cpf} onChange={(value) => setLookup((v) => ({ ...v, cpf: formatCpf(value) }))} inputMode="numeric" maxLength={14} required /><Field label="WhatsApp" ph="(83) 9 0000-0000" value={lookup.phone} onChange={(value) => setLookup((v) => ({ ...v, phone: value }))} required /><Field label="Nome completo" ph="Opcional, para confirmar" value={lookup.fullName} onChange={(value) => setLookup((v) => ({ ...v, fullName: value }))} /></div><button className="cta" disabled={busy}>{busy ? 'Localizando…' : 'Continuar →'}</button></form> : null}
    {flow === 'matricula_nova' && step <= 1 ? <form onSubmit={saveNewFamily} className="onboarding-form"><div className="grid grid--2"><Field label="CPF do responsável" ph="000.000.000-00" value={family.cpf} onChange={(value) => updateNewFamily('cpf', formatCpf(value))} inputMode="numeric" maxLength={14} required /><Field label="Nome completo do responsável" value={family.fullName} onChange={(value) => updateNewFamily('fullName', value)} required /><Field label="WhatsApp" value={family.phone} onChange={(value) => updateNewFamily('phone', value)} required /><Field label="E-mail" type="email" value={family.email} onChange={(value) => updateNewFamily('email', value)} required /><Field label="Endereço" value={family.address} onChange={(value) => updateNewFamily('address', value)} required /></div>{existingFamilyLoading ? <span className="meta">Verificando se já existe um cadastro com estes dados…</span> : null}<ExistingFamilyMatch match={existingFamily} busy={busy} onStartRematricula={startMatchedRematricula} onContinueNewEnrollment={continueWithNewChild} /><div className="onboarding-child-editor"><div><h3>Alunos</h3><p>Inclua todos os filhos que deseja matricular agora.</p></div>{family.children.map((child, index) => <div className="onboarding-child-fields" key={index}><Field label="Nome completo do aluno" value={child.name} onChange={(value) => updateChild(index, 'name', value)} required /><Field label="Série pretendida" type="select" options={gradeOptions} value={child.gradeId} onChange={(value) => updateChild(index, 'gradeId', value)} required /><Field label="Data de nascimento" type="date" value={child.birthDate} onChange={(value) => updateChild(index, 'birthDate', value)} /><Field label="Escola anterior" value={child.previousSchool} onChange={(value) => updateChild(index, 'previousSchool', value)} />{family.children.length > 1 ? <button type="button" className="text-link" onClick={() => removeChild(index)}>Remover aluno</button> : null}</div>)}<button type="button" className="btn" onClick={() => setFamily((v) => ({ ...v, children: [...v.children, { name: '', birthDate: '', gradeId: '', previousSchool: '' }] }))}>+ Adicionar outro filho</button></div><button className="cta" disabled={busy}>{busy ? 'Salvando…' : 'Continuar para contratos →'}</button></form> : null}
    {flow === 'rematricula' && step === 2 ? <form onSubmit={selectChildren} className="onboarding-form"><div className="onboarding-guardian"><strong>{data.guardian?.name}</strong><span>Estes alunos foram encontrados como vinculados ao seu cadastro.</span></div><div className="onboarding-children">{data.children?.map((child) => <label className={`onboarding-child-card${selected.includes(child.student_id) ? ' is-selected' : ''}${child.eligible === false ? ' is-unavailable' : ''}`} key={child.student_id}><input type="checkbox" disabled={child.eligible === false} checked={selected.includes(child.student_id)} onChange={(event) => setSelected((items) => event.target.checked ? [...items, child.student_id] : items.filter((id) => id !== child.student_id))} /><span><strong>{child.name}</strong><small>{child.current_grade ? `${child.current_grade} → ` : ''}{child.target_grade || 'Série a confirmar'}</small>{child.eligible === false ? <small>{child.eligibility_reason}</small> : null}</span></label>)}</div>{!eligibleChildren.length ? <div className="notice"><span>Nenhum aluno deste cadastro está pronto para a rematrícula. Fale com a secretaria para corrigir a turma ou o valor de 2027.</span></div> : null}<button className="cta" disabled={busy || !selectedEligibleChildren.length}>{busy ? 'Salvando…' : 'Confirmar alunos →'}</button></form> : null}
    {step === 3 ? <section className="onboarding-form"><div className="onboarding-guardian"><strong>Assinaturas pendentes</strong><span>Você fará uma assinatura por aluno. Depois volte para este mesmo link para acompanhar.</span></div><Field label="E-mail para confirmação das assinaturas" type="email" value={email} onChange={setEmail} required /><div className="onboarding-contract-list">{selectedChildren.map((child) => <article className="onboarding-contract-card" key={child.enrollment_id}><div><strong>{child.name}</strong><span>{child.target_grade}</span></div>{child.contract_status === 'assinada' ? <span className="badge badge--green">Assinado</span> : <button className="btn btn--primary" onClick={() => child.contract_token ? navigate(`/contrato/${child.contract_token}`) : prepareContract(child.enrollment_id)} disabled={busy}>{child.contract_token ? 'Continuar assinatura' : 'Preparar contrato'}</button>}</article>)}</div>{allSigned ? <button className="cta" onClick={() => apply({ ...data, step: 4, status: 'pagamento' })}>Seguir para pagamento →</button> : null}</section> : null}
    {data.status === 'concluida' ? <div className="notice"><span>Matrícula concluída. A cobrança ainda será enviada pela escola pelo meio escolhido.</span></div> : null}
    {step >= 4 && data.status !== 'concluida' ? <form onSubmit={choosePayment} className="onboarding-form"><div className="onboarding-guardian"><strong>Forma de pagamento</strong><span>Na rematrícula concluída até 31/10, o valor promocional é dividido em novembro, dezembro e janeiro. Depois, vale a tabela de 2027 com pagamento único em janeiro. Informe sua preferência; você não será cobrado nesta etapa.</span></div><div className="onboarding-methods"><button type="button" className={`btn${payment.method === 'cartao' ? ' btn--primary' : ''}`} onClick={() => setPayment({ method: 'cartao' })}>Cartão</button><button type="button" className={`btn${payment.method === 'pix' ? ' btn--primary' : ''}`} onClick={() => setPayment({ method: 'pix' })}>Pix</button></div><button className="cta" disabled={busy}>{busy ? 'Registrando…' : 'Registrar preferência'}</button></form> : null}
    {notice ? <div className="notice"><span>{notice}</span></div> : null}
  </div></section></main> : null}</DataState>;
}
