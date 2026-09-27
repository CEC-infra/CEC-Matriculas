import { useEffect, useMemo, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { Field, LogoBlocks } from '../components/ui';
import DataState from '../components/DataState';
import { money } from '../lib/format';
import {
  chooseOnboardingPayment, createMatriculaOnboarding, getPublicOfferings,
  identifyRematriculaOnboarding, openEnrollmentOnboarding, prepareOnboardingContract,
  selectRematriculaChildren, startEnrollmentOnboarding
} from '../services/data';

const newFamily = { cpf: '', fullName: '', phone: '', email: '', address: '', children: [{ name: '', birthDate: '', gradeId: '', previousSchool: '' }] };

function Stepper({ step, flow }) {
  const labels = flow === 'rematricula' ? ['Identificação', 'Alunos', 'Assinaturas', 'Pagamento'] : ['Dados', 'Assinaturas', 'Pagamento'];
  return <div className="steps onboarding-steps">{labels.map((label, index) => <div className={`step${index + 1 <= step ? ' is-done' : ''}`} key={label}><i /><span>{label}</span></div>)}</div>;
}

function Title({ flow, step }) {
  const remat = flow === 'rematricula';
  const heading = remat
    ? (step <= 1 ? 'Vamos encontrar sua família' : step === 2 ? 'Confirme quem vai continuar em 2027' : step === 3 ? 'Uma assinatura para cada aluno' : 'Escolha como prefere pagar')
    : (step <= 1 ? 'Comece a matrícula da sua família' : step === 3 ? 'Uma assinatura para cada aluno' : 'Escolha como prefere pagar');
  return <div className="public-head--navy onboarding-head"><div style={{ display: 'flex', alignItems: 'center', gap: 12 }}><LogoBlocks /><span className="public-kicker">{remat ? 'Rematrícula 2027' : 'Matrícula 2027'}</span></div><h2>{heading}</h2><p>Você pode fechar esta página e continuar depois pelo mesmo link. Seus avanços ficam salvos com segurança.</p></div>;
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
  const [selected, setSelected] = useState([]);
  const [email, setEmail] = useState('');
  const [payment, setPayment] = useState({ planId: '', method: 'boleto' });
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
      if (result?.children) setSelected(result.children.filter((item) => item.selected).map((item) => item.student_id));
    }).catch((reason) => current && setError(reason.message || 'Não foi possível abrir esta jornada.')).finally(() => current && setLoading(false));
    return () => { current = false; };
  }, [flow, token, setParams]);

  function chooseFlow(nextFlow) {
    setFlow(nextFlow);
    setParams({}, { replace: true });
  }
  function apply(next) {
    setData(next); setError('');
    if (next?.guardian?.email) setEmail(next.guardian.email);
    if (next?.children) setSelected(next.children.filter((item) => item.selected).map((item) => item.student_id));
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
    try { apply(await chooseOnboardingPayment(token, payment.planId, payment.method)); setNotice('Pagamento registrado. A escola enviará a cobrança no meio escolhido.'); }
    catch (reason) { setNotice(reason.message || 'Não foi possível registrar a opção de pagamento.'); }
    finally { setBusy(false); }
  }
  function updateChild(index, key, value) {
    setFamily((current) => ({ ...current, children: current.children.map((child, childIndex) => childIndex === index ? { ...child, [key]: value } : child) }));
  }
  function removeChild(index) { setFamily((current) => ({ ...current, children: current.children.filter((_, childIndex) => childIndex !== index) })); }

  if (!flow) return <main className="onboarding-page"><section className="onboarding-shell"><div className="onboarding-choice"><LogoBlocks /><span>CEC · 2027</span><h1>Como podemos ajudar?</h1><p>Escolha a jornada para começar. Você receberá um link seguro para continuar de onde parou.</p><div className="onboarding-choice-actions"><button className="cta" onClick={() => chooseFlow('matricula_nova')}>Quero fazer uma matrícula nova</button><button className="btn" onClick={() => chooseFlow('rematricula')}>Quero fazer uma rematrícula</button></div><button className="text-link" onClick={() => navigate('/rematricula')}>Já sou responsável e quero rematricular</button></div></section></main>;

  const step = data?.step || (flow === 'rematricula' ? 1 : 1);
  const selectedChildren = (data?.children || []).filter((child) => child.selected);
  const allSigned = selectedChildren.length > 0 && selectedChildren.every((child) => child.contract_status === 'assinada');
  return <DataState loading={loading} error={error} empty={false}>{data ? <main className="onboarding-page"><section className="public onboarding-shell"><Title flow={flow} step={step} /><Stepper flow={flow} step={step} /><div className="public-body onboarding-body">
    {flow === 'rematricula' && step <= 1 ? <form onSubmit={identify} className="onboarding-form"><p className="meta">Para proteger os dados da família, confirmamos CPF e WhatsApp antes de apresentar os alunos vinculados.</p><div className="grid grid--2"><Field label="CPF do responsável" ph="000.000.000-00" value={lookup.cpf} onChange={(value) => setLookup((v) => ({ ...v, cpf: value }))} required /><Field label="WhatsApp" ph="(83) 9 0000-0000" value={lookup.phone} onChange={(value) => setLookup((v) => ({ ...v, phone: value }))} required /><Field label="Nome completo" ph="Opcional, para confirmar" value={lookup.fullName} onChange={(value) => setLookup((v) => ({ ...v, fullName: value }))} /></div><button className="cta" disabled={busy}>{busy ? 'Localizando…' : 'Continuar →'}</button></form> : null}
    {flow === 'matricula_nova' && step <= 1 ? <form onSubmit={saveNewFamily} className="onboarding-form"><div className="grid grid--2"><Field label="CPF do responsável" value={family.cpf} onChange={(value) => setFamily((v) => ({ ...v, cpf: value }))} required /><Field label="Nome completo do responsável" value={family.fullName} onChange={(value) => setFamily((v) => ({ ...v, fullName: value }))} required /><Field label="WhatsApp" value={family.phone} onChange={(value) => setFamily((v) => ({ ...v, phone: value }))} required /><Field label="E-mail" type="email" value={family.email} onChange={(value) => setFamily((v) => ({ ...v, email: value }))} required /><Field label="Endereço" value={family.address} onChange={(value) => setFamily((v) => ({ ...v, address: value }))} required /></div><div className="onboarding-child-editor"><div><h3>Alunos</h3><p>Inclua todos os filhos que deseja matricular agora.</p></div>{family.children.map((child, index) => <div className="onboarding-child-fields" key={index}><Field label="Nome completo do aluno" value={child.name} onChange={(value) => updateChild(index, 'name', value)} required /><Field label="Série pretendida" type="select" options={gradeOptions} value={child.gradeId} onChange={(value) => updateChild(index, 'gradeId', value)} required /><Field label="Data de nascimento" type="date" value={child.birthDate} onChange={(value) => updateChild(index, 'birthDate', value)} /><Field label="Escola anterior" value={child.previousSchool} onChange={(value) => updateChild(index, 'previousSchool', value)} />{family.children.length > 1 ? <button type="button" className="text-link" onClick={() => removeChild(index)}>Remover aluno</button> : null}</div>)}<button type="button" className="btn" onClick={() => setFamily((v) => ({ ...v, children: [...v.children, { name: '', birthDate: '', gradeId: '', previousSchool: '' }] }))}>+ Adicionar outro filho</button></div><button className="cta" disabled={busy}>{busy ? 'Salvando…' : 'Continuar para contratos →'}</button></form> : null}
    {flow === 'rematricula' && step === 2 ? <form onSubmit={selectChildren} className="onboarding-form"><div className="onboarding-guardian"><strong>{data.guardian?.name}</strong><span>Estes alunos foram encontrados como vinculados ao seu cadastro.</span></div><div className="onboarding-children">{data.children?.map((child) => <label className={`onboarding-child-card${selected.includes(child.student_id) ? ' is-selected' : ''}`} key={child.student_id}><input type="checkbox" checked={selected.includes(child.student_id)} onChange={(event) => setSelected((items) => event.target.checked ? [...items, child.student_id] : items.filter((id) => id !== child.student_id))} /><span><strong>{child.name}</strong><small>{child.current_grade ? `${child.current_grade} → ` : ''}{child.target_grade || 'Série a confirmar'}</small></span></label>)}</div><button className="cta" disabled={busy || !selected.length}>{busy ? 'Salvando…' : 'Confirmar alunos →'}</button></form> : null}
    {step === 3 ? <section className="onboarding-form"><div className="onboarding-guardian"><strong>Assinaturas pendentes</strong><span>Você fará uma assinatura por aluno. Depois volte para este mesmo link para acompanhar.</span></div><Field label="E-mail para confirmação das assinaturas" type="email" value={email} onChange={setEmail} required /><div className="onboarding-contract-list">{selectedChildren.map((child) => <article className="onboarding-contract-card" key={child.enrollment_id}><div><strong>{child.name}</strong><span>{child.target_grade}</span></div>{child.contract_status === 'assinada' ? <span className="badge badge--green">Assinado</span> : <button className="btn btn--primary" onClick={() => child.contract_token ? navigate(`/contrato/${child.contract_token}`) : prepareContract(child.enrollment_id)} disabled={busy}>{child.contract_token ? 'Continuar assinatura' : 'Preparar contrato'}</button>}</article>)}</div>{allSigned ? <button className="cta" onClick={() => apply({ ...data, step: 4, status: 'pagamento' })}>Seguir para pagamento →</button> : null}</section> : null}
    {data.status === 'concluida' ? <div className="notice"><span>Pagamento confirmado nesta jornada. A escola enviará a cobrança pelo meio escolhido.</span></div> : null}
    {step >= 4 && data.status !== 'concluida' ? <form onSubmit={choosePayment} className="onboarding-form"><div className="onboarding-guardian"><strong>Pagamento</strong><span>As cobranças serão geradas após esta confirmação. Você poderá receber boleto ou link de cartão.</span></div><div className="onboarding-contract-list">{(data.payment_options || []).map((plan) => <label className={`onboarding-child-card${payment.planId === plan.id ? ' is-selected' : ''}`} key={plan.id}><input type="radio" name="payment-plan" value={plan.id} checked={payment.planId === plan.id} onChange={() => setPayment((v) => ({ ...v, planId: plan.id }))} /><span><strong>{plan.name}</strong><small>{plan.description} · vencimentos: {(plan.due_dates || []).map((date) => new Date(`${date}T12:00:00`).toLocaleDateString('pt-BR')).join(', ')}</small></span></label>)}</div><div className="onboarding-methods"><button type="button" className={`btn${payment.method === 'boleto' ? ' btn--primary' : ''}`} onClick={() => setPayment((v) => ({ ...v, method: 'boleto' }))}>Boleto</button><button type="button" className={`btn${payment.method === 'cartao' ? ' btn--primary' : ''}`} onClick={() => setPayment((v) => ({ ...v, method: 'cartao' }))}>Cartão</button></div><button className="cta" disabled={busy || !payment.planId}>{busy ? 'Registrando…' : 'Confirmar forma de pagamento'}</button></form> : null}
    {notice ? <div className="notice"><span>{notice}</span></div> : null}
  </div></section></main> : null}</DataState>;
}
