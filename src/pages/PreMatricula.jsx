import { useState } from 'react';
import { Field, LogoBlocks } from '../components/ui';
import DataState from '../components/DataState';
import { useAsyncData } from '../hooks/useAsyncData';
import { getPublicOfferings, submitPreEnrollment } from '../services/data';
import { money } from '../lib/format';

const initialForm = { guardianName: '', phone: '', studentName: '', gradeId: '', currentSchool: '', consent: false };

export default function PreMatricula() {
  const { loading, data, error } = useAsyncData(getPublicOfferings, []);
  const [form, setForm] = useState(initialForm);
  const [sending, setSending] = useState(false);
  const [message, setMessage] = useState('');
  const update = (name) => (value) => setForm((current) => ({ ...current, [name]: value }));
  const gradeOptions = (data?.offerings || []).map((item) => ({ value: item.grade_id, label: `${item.grades?.name || 'Série'} · ${money(item.amount_cents)}` }));

  async function submit(event) {
    event.preventDefault();
    if (!form.consent) { setMessage('Confirme a autorização para contato pelo WhatsApp.'); return; }
    setSending(true); setMessage('');
    try {
      await submitPreEnrollment(form);
      setForm(initialForm);
      setMessage('Recebemos sua pré-matrícula. A equipe entrará em contato pelo WhatsApp.');
    } catch (err) { setMessage(err.message || 'Não foi possível enviar agora.'); }
    finally { setSending(false); }
  }

  return (
    <div className="grid" style={{ gridTemplateColumns: '1fr 360px', gap: 28, alignItems: 'start' }}>
      <div className="public">
        <div className="public-head--navy"><div style={{ display: 'flex', alignItems: 'center', gap: 12 }}><LogoBlocks /><span className="public-kicker">Matrículas 2027</span></div><h2>Comece a matrícula do seu filho em dois minutos</h2><p>Preencha os dados básicos para iniciar a jornada de matrícula, com valores e vagas disponíveis.</p></div>
        <div className="public-body" style={{ padding: '30px 32px' }}>
          <DataState loading={loading} error={error} empty={!loading && !error && !data?.offerings?.length}>
            <form onSubmit={submit}>
              <div className="grid grid--2">
                <Field label="Nome do responsável" ph="Como podemos te chamar?" value={form.guardianName} onChange={update('guardianName')} required />
                <Field label="WhatsApp" ph="(83) 9 0000-0000" value={form.phone} onChange={update('phone')} required />
                <Field label="Nome do aluno" ph="Nome completo" value={form.studentName} onChange={update('studentName')} required />
                <Field label="Série pretendida em 2027" ph="Selecionar série" value={form.gradeId} onChange={update('gradeId')} type="select" options={gradeOptions} required />
                <Field label="Escola atual" ph="Opcional" value={form.currentSchool} onChange={update('currentSchool')} />
              </div>
              <label className="consent"><input type="checkbox" checked={form.consent} onChange={(event) => update('consent')(event.target.checked)} /><span>Autorizo o CEC a entrar em contato pelo WhatsApp sobre a matrícula.</span></label>
              {message ? <div className="notice" style={{ marginTop: 16 }}>{message}</div> : null}
              <div className="public-foot"><span>Sem compromisso. Você pode encerrar o cadastro a qualquer momento.</span><button type="submit" className="cta" disabled={sending}>{sending ? 'Enviando…' : 'Continuar matrícula →'}</button></div>
            </form>
          </DataState>
        </div>
      </div>
      <div className="stack" style={{ gap: 16 }}><div className="card"><div className="card-title" style={{ marginBottom: 14 }}>O que acontece depois</div><div className="bullet-list">{['Cadastro registrado na campanha', 'Valores e vagas atualizados', 'Visita agendada conforme disponibilidade', 'Matrícula concluída online, com assinatura digital'].map((item) => <div className="bullet" key={item}><i /><span>{item}</span></div>)}</div></div><div className="card card--navy"><div className="card-title" style={{ marginBottom: 10 }}>Dados protegidos</div><p style={{ fontSize: 13, color: 'var(--navy-soft)', lineHeight: 1.6 }}>Seu envio é registrado diretamente na campanha e tratado pela equipe da escola.</p></div></div>
    </div>
  );
}
