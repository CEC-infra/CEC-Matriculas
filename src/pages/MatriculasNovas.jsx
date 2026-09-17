import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Badge, Chips, Field, KpiRow } from '../components/ui';
import DataState from '../components/DataState';
import { useAsyncData } from '../hooks/useAsyncData';
import { createStaffEnrollment, getEnrollments, getPublicOfferings } from '../services/data';
import { dateTime, money, shiftLabel, statusTone } from '../lib/format';

const emptyForm = { guardianName: '', phone: '', studentName: '', gradeId: '', shift: '', currentSchool: '', source: 'outro' };

export default function MatriculasNovas() {
  const navigate = useNavigate();
  const [filter, setFilter] = useState('Todas');
  const [form, setForm] = useState(emptyForm);
  const [message, setMessage] = useState('');
  const [saving, setSaving] = useState(false);
  const enrollments = useAsyncData(() => getEnrollments({ kind: 'matricula_nova' }), []);
  const offerings = useAsyncData(getPublicOfferings, []);
  const rows = (enrollments.data || []).filter((item) => filter === 'Todas' || item.status_label === filter);
  const selected = offerings.data?.offerings.find((item) => item.grade_id === form.gradeId);
  const update = (field) => (value) => setForm((current) => ({ ...current, [field]: value }));
  const gradeOptions = (offerings.data?.offerings || []).map((item) => ({ value: item.grade_id, label: `${item.grades?.name} · ${money(item.amount_cents)}` }));
  const shiftOptions = (selected?.shifts || []).map((item) => ({ value: item, label: shiftLabel(item) }));
  const stats = [{ label: 'Pré-matrículas', value: (enrollments.data || []).filter((item) => item.status === 'pre_matricula').length, sub: 'formulário público' }, { label: 'Em atendimento', value: (enrollments.data || []).filter((item) => !item.completed_at && item.status !== 'pre_matricula').length, sub: 'jornadas ativas' }, { label: 'Matrículas efetivadas', value: (enrollments.data || []).filter((item) => item.completed_at).length, sub: 'concluídas' }, { label: 'Total da campanha', value: enrollments.data?.length || 0, sub: 'dados reais' }];
  async function submit(event) { event.preventDefault(); setSaving(true); setMessage(''); try { const result = await createStaffEnrollment(form); setForm(emptyForm); setMessage('Família cadastrada e adicionada à esteira de atendimento.'); await enrollments.refresh(); navigate(`/familias/${result.id}`); } catch (err) { setMessage(err.message || 'Não foi possível cadastrar a família.'); } finally { setSaving(false); } }
  return <><KpiRow items={stats} cls="grid--4" valueSize={30} /><div className="grid grid--wide"><div className="stack" style={{ gap: 14 }}><div className="chip-row"><Chips items={['Todas', 'Pré-matrícula', 'Em fila', 'Concluída']} active={filter} onSelect={setFilter} /></div><DataState loading={enrollments.loading} error={enrollments.error} empty={!enrollments.loading && !enrollments.error && !enrollments.data?.length}><div className="table"><div className="table-head cols-novas"><div>Responsável</div><div>Aluno</div><div>Série pretendida</div><div>Etapa</div><div>Origem</div><div /></div>{rows.map((item) => <div className="table-row cols-novas" key={item.id} onClick={() => navigate(`/familias/${item.id}`)}><div className="cell-stack"><strong className="cell-strong">{item.guardian_name}</strong><span>{item.guardian_phone}</span></div><div className="cell-stack"><span className="cell">{item.student_name}</span><span>{dateTime(item.created_at)}</span></div><div className="cell is-secondary">{item.target_grade_name} · {shiftLabel(item.target_shift)}</div><div><Badge tone={statusTone(item.status)}>{item.status_label}</Badge></div><div className="cell is-secondary">{item.origin}</div><div className="cell-open is-secondary">Abrir →</div></div>)}</div></DataState></div><div className="card"><div className="card-title">Cadastrar família</div><div className="card-sub" style={{ marginBottom: 16 }}>Entrada manual para visita, telefone ou indicação.</div><DataState loading={offerings.loading} error={offerings.error} empty={!offerings.loading && !offerings.error && !offerings.data?.offerings?.length}><form onSubmit={submit} style={{ display: 'flex', flexDirection: 'column', gap: 12 }}><Field label="Nome do responsável" ph="Nome completo" value={form.guardianName} onChange={update('guardianName')} required /><Field label="WhatsApp" ph="(83) 9 0000-0000" value={form.phone} onChange={update('phone')} required /><Field label="Nome do aluno" ph="Nome completo" value={form.studentName} onChange={update('studentName')} required /><Field label="Série pretendida" ph="Selecionar série" value={form.gradeId} onChange={update('gradeId')} type="select" options={gradeOptions} required /><Field label="Turno" ph="Selecionar turno" value={form.shift} onChange={update('shift')} type="select" options={shiftOptions} disabled={!form.gradeId} /><Field label="Origem" value={form.source} onChange={update('source')} type="select" options={[{ value: 'indicacao', label: 'Indicação' }, { value: 'instagram', label: 'Instagram' }, { value: 'outro', label: 'Visita ou telefone' }]} />{message ? <div className="notice">{message}</div> : null}<button type="submit" className="btn btn--primary btn--block" disabled={saving}>{saving ? 'Cadastrando…' : 'Cadastrar e iniciar atendimento'}</button></form></DataState></div></div></>;
}
