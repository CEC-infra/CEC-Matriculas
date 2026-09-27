import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Badge, Chips, Field, KpiRow } from '../components/ui';
import DataState from '../components/DataState';
import { useAsyncData } from '../hooks/useAsyncData';
import { createStaffEnrollment, getEnrollments, getPublicOfferings } from '../services/data';
import { dateTime, money, shiftLabel, statusTone } from '../lib/format';

const emptyForm = {
  guardianCpf: '', guardianName: '', phone: '', email: '', address: '',
  studentName: '', gradeId: '', shift: '', birthDate: '', currentSchool: '',
  relationship: '', source: 'outro', notes: ''
};

function FamilyModal({ form, onChange, onClose, onSubmit, saving, message, gradeOptions, shiftOptions }) {
  const update = (field) => (value) => onChange((current) => ({ ...current, [field]: value }));
  return <div className="modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !saving) onClose(); }}>
    <section className="modal-card" role="dialog" aria-modal="true" aria-labelledby="family-modal-title">
      <div className="modal-head"><div><h2 id="family-modal-title">Cadastrar família</h2><p>Os campos obrigatórios são necessários para iniciar a matrícula.</p></div><button className="modal-close" type="button" aria-label="Fechar" onClick={onClose} disabled={saving}>×</button></div>
      <form onSubmit={onSubmit} className="modal-form">
        <div className="modal-section"><h3>Responsável</h3><div className="grid grid--2">
          <Field label="CPF do responsável" ph="000.000.000-00" value={form.guardianCpf} onChange={update('guardianCpf')} required />
          <Field label="Nome completo do responsável" ph="Nome completo" value={form.guardianName} onChange={update('guardianName')} required />
          <Field label="WhatsApp do responsável" ph="(83) 9 0000-0000" value={form.phone} onChange={update('phone')} required />
          <Field label="E-mail do responsável" ph="nome@email.com" value={form.email} onChange={update('email')} type="email" required />
          <div style={{ gridColumn: '1 / -1' }}><Field label="Endereço do responsável" ph="Rua, número, bairro, cidade e CEP" value={form.address} onChange={update('address')} required /></div>
        </div></div>
        <div className="modal-section"><h3>Aluno</h3><div className="grid grid--2">
          <Field label="Nome completo do aluno/filho" ph="Nome completo" value={form.studentName} onChange={update('studentName')} required />
          <Field label="Série pretendida" ph="Selecionar série" value={form.gradeId} onChange={(value) => onChange((current) => ({ ...current, gradeId: value, shift: '' }))} type="select" options={gradeOptions} required />
          <Field label="Turno" ph="Selecionar turno" value={form.shift} onChange={update('shift')} type="select" options={shiftOptions} disabled={!form.gradeId} required />
        </div></div>
        <details className="modal-details"><summary>Informações complementares</summary><div className="grid grid--2" style={{ marginTop: 14 }}>
          <Field label="Data de nascimento" value={form.birthDate} onChange={update('birthDate')} type="date" />
          <Field label="Escola atual" ph="Opcional" value={form.currentSchool} onChange={update('currentSchool')} />
          <Field label="Parentesco" ph="Ex.: mãe, pai, responsável legal" value={form.relationship} onChange={update('relationship')} />
          <Field label="Origem" value={form.source} onChange={update('source')} type="select" options={[{ value: 'indicacao', label: 'Indicação' }, { value: 'instagram', label: 'Instagram' }, { value: 'visita_presencial', label: 'Visita presencial' }, { value: 'telefone', label: 'Telefone' }, { value: 'whatsapp', label: 'WhatsApp' }, { value: 'outro', label: 'Outra' }]} />
          <div style={{ gridColumn: '1 / -1' }}><Field label="Observações" ph="Opcional" value={form.notes} onChange={update('notes')} /></div>
        </div></details>
        {message ? <div className="notice">{message}</div> : null}
        <div className="modal-actions"><button type="button" className="btn" onClick={onClose} disabled={saving}>Cancelar</button><button type="submit" className="btn btn--primary" disabled={saving}>{saving ? 'Cadastrando…' : 'Cadastrar e iniciar atendimento'}</button></div>
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
  const enrollments = useAsyncData(() => getEnrollments({ kind: 'matricula_nova' }), []);
  const offerings = useAsyncData(getPublicOfferings, []);
  const rows = (enrollments.data || []).filter((item) => filter === 'Todas' || item.status_label === filter);
  const selected = offerings.data?.offerings.find((item) => item.grade_id === form.gradeId);
  const gradeOptions = (offerings.data?.offerings || []).map((item) => ({ value: item.grade_id, label: `${item.grades?.name} · ${money(item.amount_cents)}` }));
  const shiftOptions = (selected?.shifts || []).map((item) => ({ value: item, label: shiftLabel(item) }));
  const stats = [{ label: 'Pré-matrículas', value: (enrollments.data || []).filter((item) => item.status === 'pre_matricula').length, sub: 'formulário público' }, { label: 'Em atendimento', value: (enrollments.data || []).filter((item) => !item.completed_at && item.status !== 'pre_matricula').length, sub: 'jornadas ativas' }, { label: 'Matrículas efetivadas', value: (enrollments.data || []).filter((item) => item.completed_at).length, sub: 'concluídas' }, { label: 'Total da campanha', value: enrollments.data?.length || 0, sub: 'dados reais' }];
  function openModal() { setMessage(''); setShowModal(true); }
  function closeModal() { if (!saving) { setShowModal(false); setMessage(''); } }
  async function submit(event) {
    event.preventDefault(); setSaving(true); setMessage('');
    try {
      const result = await createStaffEnrollment(form);
      setForm(emptyForm); setShowModal(false); await enrollments.refresh(); navigate(`/familias/${result.id}`);
    } catch (err) { setMessage(err.message || 'Não foi possível cadastrar a família.'); } finally { setSaving(false); }
  }
  return <><KpiRow items={stats} cls="grid--4" valueSize={30} /><div className="page-actions"><button type="button" className="btn btn--primary" onClick={openModal}>Cadastrar família</button></div><div className="stack" style={{ gap: 14 }}><div className="chip-row"><Chips items={['Todas', 'Pré-matrícula', 'Em fila', 'Concluída']} active={filter} onSelect={setFilter} /></div><DataState loading={enrollments.loading} error={enrollments.error} empty={!enrollments.loading && !enrollments.error && !enrollments.data?.length}><div className="table"><div className="table-head cols-novas"><div>Responsável</div><div>Aluno</div><div>Série pretendida</div><div>Etapa</div><div>Origem</div><div /></div>{rows.map((item) => <div className="table-row cols-novas" key={item.id} onClick={() => navigate(`/familias/${item.id}`)}><div className="cell-stack"><strong className="cell-strong">{item.guardian_name}</strong><span>{item.guardian_phone}</span></div><div className="cell-stack"><span className="cell">{item.student_name}</span><span>{dateTime(item.created_at)}</span></div><div className="cell is-secondary">{item.target_grade_name} · {shiftLabel(item.target_shift)}</div><div><Badge tone={statusTone(item.status)}>{item.status_label}</Badge></div><div className="cell is-secondary">{item.origin}</div><div className="cell-open is-secondary">Abrir →</div></div>)}</div></DataState></div>{showModal ? <FamilyModal form={form} onChange={setForm} onClose={closeModal} onSubmit={submit} saving={saving} message={message} gradeOptions={gradeOptions} shiftOptions={shiftOptions} /> : null}</>;
}
