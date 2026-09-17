import { useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { Field, LogoBlocks } from '../components/ui';
import DataState from '../components/DataState';
import { useAsyncData } from '../hooks/useAsyncData';
import { openRematricula, saveRematricula } from '../services/data';
import { money } from '../lib/format';

export default function LinkRematricula() {
  const { token } = useParams();
  const navigate = useNavigate();
  const [tokenInput, setTokenInput] = useState(token || '');
  const { loading, data, error, refresh } = useAsyncData(() => token ? openRematricula(token) : Promise.resolve(null), [token]);
  const [form, setForm] = useState({ email: '', phone: '', planId: '' });
  const [message, setMessage] = useState('');
  const [saving, setSaving] = useState(false);
  const planId = form.planId || data?.payment_plan_id || data?.plans?.[0]?.id;

  if (!token) {
    return <main className="auth-page"><section className="auth-card"><h1>Abrir rematrícula</h1><p>Informe o código recebido no link da escola.</p><form className="auth-form" onSubmit={(event) => { event.preventDefault(); navigate(`/rematricula/${tokenInput.trim()}`); }}><label>Código do link<input required value={tokenInput} onChange={(event) => setTokenInput(event.target.value)} /></label><button className="btn btn--primary">Abrir link</button></form></section></main>;
  }

  async function submit(event) {
    event.preventDefault(); setSaving(true); setMessage('');
    try {
      await saveRematricula(token, { ...form, planId });
      setMessage('Dados confirmados. A equipe dará sequência à assinatura e ao pagamento.');
      await refresh();
    } catch (err) { setMessage(err.message || 'Não foi possível salvar seus dados.'); }
    finally { setSaving(false); }
  }

  return <DataState loading={loading} error={error} empty={!loading && !error && !data}>{data ? <div className="public public--single"><div className="public-head public-head--orange"><div style={{ display: 'flex', alignItems: 'center', gap: 12 }}><LogoBlocks /><strong>{data.campaign}</strong></div><span>Link individual</span></div><div className="public-body"><h2>Confirme os dados de {data.student?.name}</h2><p style={{ marginTop: 6 }}>Confira seus dados e escolha a condição de pagamento para seguir com a rematrícula.</p><form onSubmit={submit}><div className="grid grid--2" style={{ marginTop: 22 }}><Field label="Responsável" value={data.guardian?.name} /><Field label="Aluno" value={data.student?.name} /><Field label="E-mail" ph="Seu melhor e-mail" value={form.email || data.guardian?.email || ''} onChange={(value) => setForm((item) => ({ ...item, email: value }))} type="email" /><Field label="Telefone" ph="(83) 9 0000-0000" value={form.phone || data.guardian?.phone || ''} onChange={(value) => setForm((item) => ({ ...item, phone: value }))} /></div><div style={{ border: '1px solid var(--line)', borderRadius: 'var(--r-lg)', padding: '18px 20px', display: 'flex', flexDirection: 'column', gap: 14, marginTop: 20 }}><strong style={{ fontSize: 14 }}>Condição de pagamento</strong>{data.plans.map((plan) => <button type="button" className={`plan${plan.id === planId ? ' is-active' : ''}`} key={plan.id} onClick={() => setForm((item) => ({ ...item, planId: plan.id }))}><div className="plan-left"><div className="plan-radio" /><div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}><strong>{plan.name}</strong><span>{plan.description}</span></div></div><span className="plan-price">{money(plan.installment_cents)}</span></button>)}</div>{message ? <div className="notice" style={{ marginTop: 16 }}>{message}</div> : null}<div className="public-foot"><span>Ao continuar você confirma os dados e a condição escolhida.</span><button type="submit" className="cta" disabled={saving}>{saving ? 'Salvando…' : 'Confirmar dados →'}</button></div></form></div></div> : null}</DataState>;
}
