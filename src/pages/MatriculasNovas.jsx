import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Badge, Chips, Field, KpiRow } from '../components/ui';
import DataState from '../components/DataState';
import { useAsyncData } from '../hooks/useAsyncData';
import { createStaffEnrollment, getEnrollments, getPublicOfferings } from '../services/data';
import { dateTime, formatCpf, money, statusTone } from '../lib/format';

const emptyForm = {
  guardianCpf: '', guardianName: '', phone: '', email: '', address: '',
  studentName: '', gradeId: '', birthDate: '', currentSchool: '',
  relationship: '', source: 'outro', notes: ''
};

function isValidCpf(value) {
  const cpf = String(value || '').replace(/\D/g, '');
  if (!/^\d{11}$/.test(cpf) || /^(\d)\1{10}$/.test(cpf)) return false;
  const digit = (length) => {
    const total = cpf.slice(0, length - 1).split('').reduce((sum, item, index) => sum + Number(item) * (length - index), 0);
    const result = (total * 10) % 11;
    return result === 10 ? 0 : result;
  };
  return digit(10) === Number(cpf[9]) && digit(11) === Number(cpf[10]);
}

function FamilyModal({ form, onChange, onClear, onClose, onSubmit, saving, message, createdLink, onOpenFamily, gradeOptions }) {
  const update = (field) => (value) => onChange((current) => ({ ...current, [field]: value }));
  const cpfInvalid = form.guardianCpf.length > 0 && !isValidCpf(form.guardianCpf);
  return <div className="modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !saving) onClose(); }}>
    <section className="modal-card" role="dialog" aria-modal="true" aria-labelledby="family-modal-title">
      <div className="modal-head"><div><h2 id="family-modal-title">Cadastrar família</h2><p>Os campos obrigatórios são necessários para iniciar a matrícula.</p></div><button className="modal-close" type="button" aria-label="Fechar" onClick={onClose} disabled={saving}>×</button></div>
      <form onSubmit={onSubmit} className="modal-form">
        <div className="modal-section"><h3>Responsável</h3><div className="grid grid--2">
          <div><Field label="CPF do responsável" ph="000.000.000-00" value={form.guardianCpf} onChange={(value) => update('guardianCpf')(formatCpf(value))} inputMode="numeric" maxLength={14} required />{cpfInvalid ? <small className="field-error">CPF inválido. Confira os dígitos.</small> : null}</div>
          <Field label="Nome completo do responsável" ph="Nome completo" value={form.guardianName} onChange={update('guardianName')} required />
          <Field label="WhatsApp do responsável" ph="(83) 9 0000-0000" value={form.phone} onChange={update('phone')} required />
          <Field label="E-mail do responsável" ph="nome@email.com" value={form.email} onChange={update('email')} type="email" required />
          <div style={{ gridColumn: '1 / -1' }}><Field label="Endereço do responsável" ph="Rua, número, bairro, cidade e CEP" value={form.address} onChange={update('address')} required /></div>
        </div></div>
        <div className="modal-section"><h3>Aluno</h3><div className="grid grid--2">
          <Field label="Nome completo do aluno/filho" ph="Nome completo" value={form.studentName} onChange={update('studentName')} required />
          <Field label="Série pretendida" ph="Selecionar série" value={form.gradeId} onChange={update('gradeId')} type="select" options={gradeOptions} required />
        </div></div>
        <details className="modal-details"><summary>Informações complementares</summary><div className="grid grid--2" style={{ marginTop: 14 }}>
          <Field label="Data de nascimento do aluno/filho" value={form.birthDate} onChange={update('birthDate')} type="date" />
          <Field label="Escola atual" ph="Opcional" value={form.currentSchool} onChange={update('currentSchool')} />
          <Field label="Parentesco" ph="Ex.: mãe, pai, responsável legal" value={form.relationship} onChange={update('relationship')} />
          <Field label="Origem" value={form.source} onChange={update('source')} type="select" options={[{ value: 'indicacao', label: 'Indicação' }, { value: 'instagram', label: 'Instagram' }, { value: 'visita_presencial', label: 'Visita presencial' }, { value: 'telefone', label: 'Telefone' }, { value: 'whatsapp', label: 'WhatsApp' }, { value: 'outro', label: 'Outra' }]} />
          <div style={{ gridColumn: '1 / -1' }}><Field label="Observações" ph="Opcional" value={form.notes} onChange={update('notes')} /></div>
        </div></details>
        {message ? <div className="notice">{message}</div> : null}
        {createdLink ? <div className="notice" style={{ marginTop: 14, alignItems: 'flex-start', flexDirection: 'column' }}><span>Link individual criado para esta matrícula:</span><code style={{ overflowWrap: 'anywhere' }}>{createdLink}</code><div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}><button type="button" className="btn" onClick={() => navigator.clipboard?.writeText(createdLink)}>Copiar link</button><button type="button" className="btn btn--primary" onClick={onOpenFamily}>Abrir família</button></div></div> : null}
        <div className="modal-actions">{createdLink ? <button type="button" className="btn" onClick={onClear}>Cadastrar outra família</button> : <><button type="button" className="btn" onClick={onClear} disabled={saving}>Limpar dados</button><button type="button" className="btn" onClick={onClose} disabled={saving}>Cancelar</button><button type="submit" className="btn btn--primary" disabled={saving}>{saving ? 'Cadastrando…' : 'Cadastrar família'}</button></>}</div>
      </form>
    </section>
  </div>;
}

export default function MatriculasNovas() {
  const navigate = useNavigate();
  const [filter, setFilter] = useState('Todas');
  const [form, setForm] = useState(emptyForm);
  const [message, setMessage] = useState('');
  const [saving, setSaving] = useState(false);
  const [showModal, setShowModal] = useState(false);
  const [created, setCreated] = useState(null);
  const enrollments = useAsyncData(() => getEnrollments({ kind: 'matricula_nova' }), []);
  const offerings = useAsyncData(getPublicOfferings, []);
  const rows = (enrollments.data || []).filter((item) => filter === 'Todas' || item.status_label === filter);
  const gradeOptions = (offerings.data?.offerings || []).map((item) => ({ value: item.grade_id, label: `${item.grades?.name} · ${money(item.amount_cents)}` }));
  const stats = [{ label: 'Pré-matrículas', value: (enrollments.data || []).filter((item) => item.status === 'pre_matricula').length, sub: 'formulário público' }, { label: 'Jornadas em andamento', value: (enrollments.data || []).filter((item) => !item.completed_at && item.status !== 'pre_matricula').length, sub: 'cadastros ativos' }, { label: 'Matrículas efetivadas', value: (enrollments.data || []).filter((item) => item.completed_at).length, sub: 'concluídas' }, { label: 'Total da campanha', value: enrollments.data?.length || 0, sub: 'dados reais' }];
  function openModal() { setMessage(''); setCreated(null); setShowModal(true); }
  function closeModal() { if (!saving) { setShowModal(false); setMessage(''); setCreated(null); } }
  function clearModal() { if (!saving) { setForm(emptyForm); setMessage(''); setCreated(null); } }
  async function submit(event) {
    event.preventDefault(); setSaving(true); setMessage('');
    if (!isValidCpf(form.guardianCpf)) { setSaving(false); setMessage('CPF inválido. Confira os 11 dígitos antes de cadastrar.'); return; }
    try {
      const result = await createStaffEnrollment(form);
      const link = result.link_token ? `${window.location.origin}/matricula/${result.link_token}` : null;
      setCreated({ id: result.id, link }); setMessage(link ? 'Família cadastrada. O link individual já está pronto.' : 'Família cadastrada.'); await enrollments.refresh();
    } catch (err) { setMessage(err.message || 'Não foi possível cadastrar a família.'); } finally { setSaving(false); }
  }
  return <><KpiRow items={stats} cls="grid--4" valueSize={30} /><div className="page-actions"><button type="button" className="btn btn--primary" onClick={openModal}>Cadastrar família</button></div><div className="stack" style={{ gap: 14 }}><div className="chip-row"><Chips items={['Todas', 'Pré-matrícula', 'Em fila', 'Concluída']} active={filter} onSelect={setFilter} /></div><DataState loading={enrollments.loading} error={enrollments.error} empty={!enrollments.loading && !enrollments.error && !enrollments.data?.length}><div className="table"><div className="table-head cols-novas"><div>Responsável</div><div>Aluno</div><div>Série pretendida</div><div>Etapa</div><div>Origem</div><div /></div>{rows.map((item) => <div className="table-row cols-novas" key={item.id} onClick={() => navigate(`/familias/${item.id}`)}><div className="cell-stack"><strong className="cell-strong">{item.guardian_name}</strong><span>{item.guardian_phone}</span></div><div className="cell-stack"><span className="cell">{item.student_name}</span><span>{dateTime(item.created_at)}</span></div><div className="cell is-secondary">{item.target_grade_name}</div><div><Badge tone={statusTone(item.status)}>{item.status_label}</Badge></div><div className="cell is-secondary">{item.origin}</div><div className="cell-open is-secondary">Abrir →</div></div>)}</div></DataState></div>{showModal ? <FamilyModal form={form} onChange={setForm} onClear={clearModal} onClose={closeModal} onSubmit={submit} saving={saving} message={message} createdLink={created?.link} onOpenFamily={() => navigate(`/familias/${created.id}`)} gradeOptions={gradeOptions} /> : null}</>;
}
