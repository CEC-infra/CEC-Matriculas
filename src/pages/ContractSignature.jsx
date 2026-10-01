import { useEffect, useRef, useState } from 'react';
import { useNavigate, useParams, useSearchParams } from 'react-router-dom';
import DataState from '../components/DataState';
import { LogoBlocks } from '../components/ui';
import { useAsyncData } from '../hooks/useAsyncData';
import { formatCpf, formatPhoneBr, maskEmail, money } from '../lib/format';
import { completeContractRequiredData, contractPdfUrl, dispatchPendingContractEmail, generateContractPdf, openContract, sendContractCode, signContract, verifyContractCode } from '../services/data';

function shiftLabel(shift) {
  return ({ manha: 'Matutino', tarde: 'Vespertino', integral: 'Integral' })[shift] || 'Turno da turma';
}

function ContractPdfPanel({ token, enrollment }) {
  const pdfUrl = contractPdfUrl(token, enrollment.id);
  return <article className="contract-pdf-panel">
    <header className="contract-pdf-panel__head">
      <div><strong>Contrato de {enrollment.student_name}</strong><span>Use os controles do PDF para ampliar e deslize para ler todas as páginas.</span></div>
      <a className="btn" href={pdfUrl} target="_blank" rel="noreferrer">Abrir com zoom</a>
    </header>
    <iframe
      title={`Contrato em PDF — ${enrollment.student_name}`}
      src={`${pdfUrl}#view=FitH&toolbar=1&navpanes=0`}
      className="contract-pdf"
      allowFullScreen
    />
  </article>;
}

function SignaturePad({ onChange }) {
  const canvasRef = useRef(null);
  const drawing = useRef(false);
  const [hasSignature, setHasSignature] = useState(false);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return undefined;
    const context = canvas.getContext('2d');
    context.lineCap = 'round';
    context.lineJoin = 'round';
    context.lineWidth = 2.5;
    context.strokeStyle = '#142D4C';
    return undefined;
  }, []);

  function point(event) {
    const canvas = canvasRef.current;
    const bounds = canvas.getBoundingClientRect();
    return {
      x: (event.clientX - bounds.left) * (canvas.width / bounds.width),
      y: (event.clientY - bounds.top) * (canvas.height / bounds.height)
    };
  }

  function begin(event) {
    const canvas = canvasRef.current;
    const context = canvas.getContext('2d');
    const position = point(event);
    drawing.current = true;
    canvas.setPointerCapture?.(event.pointerId);
    context.beginPath();
    context.moveTo(position.x, position.y);
  }

  function draw(event) {
    if (!drawing.current) return;
    const context = canvasRef.current.getContext('2d');
    const position = point(event);
    context.lineTo(position.x, position.y);
    context.stroke();
    setHasSignature(true);
    onChange(canvasRef.current.toDataURL('image/png'));
  }

  function end(event) {
    drawing.current = false;
    canvasRef.current?.releasePointerCapture?.(event.pointerId);
  }

  function clear() {
    const canvas = canvasRef.current;
    canvas.getContext('2d').clearRect(0, 0, canvas.width, canvas.height);
    setHasSignature(false);
    onChange('');
  }

  return <div style={{ border: '1px solid var(--line)', borderRadius: 'var(--r-lg)', overflow: 'hidden', background: '#fff' }}>
    <canvas ref={canvasRef} width="760" height="210" aria-label="Área para desenhar a assinatura" style={{ display: 'block', width: '100%', height: 180, touchAction: 'none', cursor: 'crosshair' }} onPointerDown={begin} onPointerMove={draw} onPointerUp={end} onPointerCancel={end} />
    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 10, padding: '10px 14px', borderTop: '1px solid var(--line)', flexWrap: 'wrap' }}><span className="meta">Desenhe sua assinatura com o dedo, mouse ou caneta.</span><button type="button" className="btn" onClick={clear} disabled={!hasSignature}>Limpar</button></div>
  </div>;
}

function ContractDataModal({ data, onClose, onSubmit, busy, error }) {
  const guardianValues = data?.guardian?.values || {};
  const [guardian, setGuardian] = useState(() => ({
    full_name: guardianValues.full_name || '', phone: formatPhoneBr(guardianValues.phone), rg: guardianValues.rg || '',
    cpf: formatCpf(guardianValues.cpf), address: guardianValues.address || '', email: guardianValues.email || ''
  }));
  const [students, setStudents] = useState(() => Object.fromEntries((data?.students || []).map((student) => [student.enrollment_id, {
    student_name: student.values?.student_name || student.student_name || '',
    target_grade_id: student.values?.target_grade_id || '', target_shift: student.values?.target_shift || ''
  }])));

  function setGuardianField(field, value) {
    setGuardian((current) => ({ ...current, [field]: value }));
  }

  function setStudentField(enrollmentId, field, value) {
    setStudents((current) => ({ ...current, [enrollmentId]: { ...(current[enrollmentId] || {}), [field]: value } }));
  }

  return <div className="contract-data-modal" role="dialog" aria-modal="true" aria-labelledby="contract-data-title">
    <div className="contract-data-modal__backdrop" />
    <form className="contract-data-modal__card" onSubmit={(event) => { event.preventDefault(); onSubmit(guardian, students); }}>
      <div className="contract-data-modal__head">
        <div><span>Antes de gerar o contrato</span><h2 id="contract-data-title">Revise os dados do contrato</h2><p>Se precisar, faça os ajustes nesta etapa. Ao salvar, uma nova versão do PDF será gerada.</p></div>
        <button type="button" className="btn" onClick={onClose} disabled={busy}>Agora não</button>
      </div>
      <div className="contract-data-modal__body">
        <section className="contract-data-modal__section"><h3>Responsável financeiro</h3><div className="contract-data-modal__grid">
          <label>Nome completo<input className="control" required value={guardian.full_name} onChange={(event) => setGuardianField('full_name', event.target.value)} /></label>
          <label>Contato / WhatsApp<input className="control" required inputMode="tel" maxLength="16" value={guardian.phone} onChange={(event) => setGuardianField('phone', formatPhoneBr(event.target.value))} placeholder="(33) 9 9126-9004" /></label>
          <label>RG<input className="control" required value={guardian.rg} onChange={(event) => setGuardianField('rg', event.target.value)} /></label>
          <label>CPF<input className="control" required inputMode="numeric" maxLength="14" value={guardian.cpf} onChange={(event) => setGuardianField('cpf', formatCpf(event.target.value))} placeholder="000.000.000-00" /></label>
          <label className="contract-data-modal__full">E-mail para confirmação<input className="control" required type="email" value={guardian.email} onChange={(event) => setGuardianField('email', event.target.value)} placeholder="voce@exemplo.com" /></label>
          <label className="contract-data-modal__full">Endereço completo<input className="control" required value={guardian.address} onChange={(event) => setGuardianField('address', event.target.value)} placeholder="Rua, número, bairro, cidade e CEP" /></label>
        </div></section>
        {(data?.students || []).map((student) => {
          const values = students[student.enrollment_id] || {};
          const grades = student.available_grades || [];
          const selectedGrade = grades.find((grade) => grade.id === values.target_grade_id);
          const automaticShift = selectedGrade?.shifts?.length === 1 ? selectedGrade.shifts[0] : (values.target_shift || '');
          return <section className="contract-data-modal__section" key={student.enrollment_id}><h3>{student.student_name || 'Aluno'}</h3><p>{student.grade || 'Série a confirmar'}</p><div className="contract-data-modal__grid">
            <label className="contract-data-modal__full">Nome completo do aluno<input className="control" required value={values.student_name || ''} onChange={(event) => setStudentField(student.enrollment_id, 'student_name', event.target.value)} /></label>
            <label>Série para 2027<select className="control" required value={values.target_grade_id || ''} onChange={(event) => {
              setStudents((current) => ({ ...current, [student.enrollment_id]: { ...values, target_grade_id: event.target.value } }));
            }}><option value="">Selecione</option>{grades.map((grade) => <option key={grade.id} value={grade.id}>{grade.name}</option>)}</select></label>
            <div className="contract-data-modal__readonly"><span>Turno da turma</span><strong>{automaticShift ? shiftLabel(automaticShift) : 'A escola precisa configurar a turma'}</strong><small>Definido automaticamente pela série.</small></div>
          </div></section>;
        })}
      </div>
      <div className="contract-data-modal__actions"><div><span>O PDF individual será gerado depois que você salvar os dados.</span>{error ? <p className="contract-data-modal__error" role="alert">{error}</p> : null}</div><button className="btn btn--primary" disabled={busy}>{busy ? 'Gerando contrato…' : 'Salvar dados e gerar contrato'}</button></div>
    </form>
  </div>;
}

export default function ContractSignature() {
  const { token } = useParams();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const contract = useAsyncData(() => openContract(token), [token]);
  const generatedFor = useRef('');
  const dispatchedEmailFor = useRef('');
  const [code, setCode] = useState('');
  const [signerName, setSignerName] = useState('');
  const [signatureImage, setSignatureImage] = useState('');
  const [accepted, setAccepted] = useState(false);
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState('');
  const [verified, setVerified] = useState(false);
  const [resendIn, setResendIn] = useState(60);
  const [codeSent, setCodeSent] = useState(false);
  const [showDataModal, setShowDataModal] = useState(false);
  const [dataSaveError, setDataSaveError] = useState('');

  useEffect(() => {
    if (contract.data?.guardian?.name && !signerName) setSignerName(contract.data.guardian.name);
    setVerified(Boolean(contract.data?.email_verified));
    setCodeSent(contract.data?.status === 'codigo_enviado' || contract.data?.status === 'verificada');
    if (contract.data?.status === 'pronta') setResendIn(0);
  }, [contract.data, signerName]);

  useEffect(() => {
    if (contract.data?.required_data && !contract.data.required_data.ready) {
      setDataSaveError('');
      setShowDataModal(true);
    }
  }, [contract.data?.required_data]);

  useEffect(() => {
    const ready = contract.data?.required_data?.ready;
    const generated = contract.data?.enrollments?.every((item) => item.contract_generated);
    if (!ready || generated || contract.data?.status === 'assinada' || generatedFor.current === token) return;
    generatedFor.current = token;
    setBusy('generate');
    generateContractPdf(token)
      .then(() => contract.refresh())
      .catch((error) => setMessage(error.message || 'Não foi possível gerar o PDF individual.'))
      .finally(() => setBusy(''));
  }, [contract.data, contract.refresh, token]);

  useEffect(() => {
    if (resendIn <= 0) return undefined;
    const timer = window.setInterval(() => setResendIn((seconds) => Math.max(0, seconds - 1)), 1000);
    return () => window.clearInterval(timer);
  }, [resendIn]);

  useEffect(() => {
    if (!codeSent || !['pendente', 'processando'].includes(contract.data?.email_delivery_status)) return undefined;
    const timer = window.setInterval(() => contract.refresh(), 10000);
    return () => window.clearInterval(timer);
  }, [codeSent, contract.data?.email_delivery_status]);

  useEffect(() => {
    if (!codeSent || contract.data?.email_delivery_status !== 'pendente' || dispatchedEmailFor.current === token) return;
    dispatchedEmailFor.current = token;
    dispatchPendingContractEmail(token)
      .catch((error) => setMessage(error.message || 'Não foi possível enviar o código por e-mail.'))
      .finally(() => contract.refresh());
  }, [codeSent, contract.data?.email_delivery_status, contract.refresh, token]);

  async function resendCode() {
    setBusy('code'); setMessage('');
    try {
      await sendContractCode(token);
      setResendIn(60);
      setCodeSent(true);
      setMessage('Código solicitado. Aguarde a confirmação de envio para informar os seis caracteres.');
      await contract.refresh();
    } catch (error) { setMessage(error.message || 'Não foi possível solicitar o código.'); }
    finally { setBusy(''); }
  }

  async function confirmCode(event) {
    event.preventDefault(); setBusy('verify'); setMessage('');
    try {
      await verifyContractCode(token, code);
      setVerified(true);
      setMessage('E-mail confirmado. Agora você pode assinar o contrato.');
      await contract.refresh();
    } catch (error) { setMessage(error.message || 'Não foi possível confirmar o código.'); }
    finally { setBusy(''); }
  }

  async function submitSignature(event) {
    event.preventDefault(); setBusy('sign'); setMessage('');
    try {
      await signContract(token, { signerName, signatureImage, accepted });
      setMessage('Contrato assinado com sucesso. As parcelas foram geradas para envio pela escola.');
      await contract.refresh();
    } catch (error) { setMessage(error.message || 'Não foi possível concluir a assinatura.'); }
    finally { setBusy(''); }
  }

  async function submitRequiredData(guardian, students) {
    setBusy('required'); setMessage(''); setDataSaveError('');
    try {
      await completeContractRequiredData(token, guardian, students);
      await generateContractPdf(token);
      setShowDataModal(false);
      setMessage('Dados salvos e contrato individual gerado. Agora você pode solicitar o código de confirmação.');
      await contract.refresh();
    } catch (error) {
      const detail = error.message || 'Não foi possível salvar os dados do contrato.';
      setDataSaveError(detail);
      setMessage(detail);
    }
    finally { setBusy(''); }
  }

  const data = contract.data;
  const signed = data?.status === 'assinada';
  const dataReady = Boolean(data?.required_data?.ready);
  const confirmationEmail = maskEmail(data?.required_data?.guardian?.values?.email || data?.email_masked);
  const contractsGenerated = Boolean(data?.enrollments?.length) && data.enrollments.every((item) => item.contract_generated);
  const emailDeliveryStatus = data?.email_delivery_status;
  const codeAvailable = codeSent && emailDeliveryStatus === 'enviado';
  const emailPending = codeSent && ['pendente', 'processando'].includes(emailDeliveryStatus);
  const emailFailed = codeSent && emailDeliveryStatus === 'falhou';
  const resumeToken = searchParams.get('j');
  const resumeFlow = searchParams.get('f') === 'matricula_nova' ? 'matricula_nova' : 'rematricula';
  const resumePath = resumeFlow === 'matricula_nova' ? '/matricula' : '/rematricula';
  return <DataState loading={contract.loading} error={contract.error} empty={!contract.loading && !contract.error && !data}>{data ? <main className="auth-page" style={{ padding: '32px 18px' }}><section className="public public--single" style={{ width: 'min(860px, 100%)' }}>
    <div className="public-head--navy"><div style={{ display: 'flex', alignItems: 'center', gap: 12 }}><LogoBlocks /><span className="public-kicker">Contrato digital</span></div><h2>Assinatura de matrícula</h2><p>Confira os dados, leia o documento preenchido e assine para concluir esta etapa.</p></div>
    <div className="public-body">
      <div className="notice notice--soft"><span>Responsável: <strong>{data.guardian?.name}</strong> · e-mail de confirmação: {confirmationEmail}</span>{!signed ? <button type="button" className="btn" onClick={() => { setDataSaveError(''); setShowDataModal(true); }}>{dataReady ? 'Revisar e editar dados' : 'Completar dados'}</button> : null}</div>
      <div><h3 style={{ fontSize: 16, marginBottom: 10 }}>Aluno</h3><div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>{data.enrollments?.map((item) => <div className="row-item" style={{ background: 'var(--surface)' }} key={item.id}><div className="who"><strong>{item.student_name}</strong><span>{item.grade}{item.shift ? ` · ${shiftLabel(item.shift)}` : ''}</span></div><strong>{money(item.amount_cents)}</strong></div>)}</div></div>
      {signed ? <div className="notice"><span>Contrato já assinado em segurança.</span>{resumeToken ? <button className="btn" onClick={() => navigate(`${resumePath}?j=${encodeURIComponent(resumeToken)}&f=${resumeFlow}`)}>Voltar para a matrícula</button> : null}</div> : contractsGenerated ? <>{!verified ? <form className="contract-confirmation" onSubmit={codeAvailable ? confirmCode : (event) => { event.preventDefault(); if (!emailPending) resendCode(); }}><div className="contract-confirmation__head"><span className={`contract-confirmation__status${codeAvailable ? ' is-sent' : emailFailed ? ' is-failed' : ''}`}>{codeAvailable ? 'Código entregue' : emailFailed ? 'Falha no envio' : emailPending ? 'Aguardando envio' : 'Confirmação por e-mail'}</span><h3>{codeAvailable ? 'Confirme seu e-mail' : emailFailed ? 'Não foi possível entregar o código' : emailPending ? 'Seu código está na fila de envio' : 'Pronto para assinar?'}</h3><p>{codeAvailable ? `Digite os seis caracteres enviados para ${confirmationEmail}.` : emailFailed ? `O envio para ${confirmationEmail} falhou. Você poderá solicitar um novo código.` : emailPending ? `O código foi solicitado para ${confirmationEmail}. Esta página atualizará automaticamente assim que ele for enviado.` : `Ao continuar, solicitaremos um código de confirmação para ${confirmationEmail}.`}</p></div>{codeAvailable ? <label className="contract-confirmation__field"><span>Código de confirmação</span><input className="contract-code-input" required inputMode="text" maxLength="6" value={code} onChange={(event) => setCode(event.target.value.toUpperCase().replace(/\s/g, ''))} placeholder="A1B2C3" autoComplete="one-time-code" /></label> : null}<div className="contract-confirmation__actions">{codeAvailable ? <button className="btn btn--primary" disabled={Boolean(busy)}>{busy === 'verify' ? 'Confirmando…' : 'Confirmar código'}</button> : emailPending ? <button type="button" className="btn" disabled>Verificando envio…</button> : <button className="btn btn--primary" disabled={Boolean(busy)}>{busy === 'code' ? 'Solicitando…' : emailFailed ? 'Solicitar novo código' : 'Enviar código para assinar'}</button>}{(codeAvailable || emailFailed) ? <button type="button" className="btn" onClick={resendCode} disabled={Boolean(busy) || resendIn > 0}>{resendIn > 0 ? `Reenviar em ${resendIn}s` : 'Reenviar código'}</button> : null}</div></form> : <form className="contract-signature" onSubmit={submitSignature}><div><h3 style={{ fontSize: 16, marginBottom: 5 }}>Assine o contrato</h3><p className="meta">Leia o contrato completo antes de aceitar e assinar. No celular, vire-o na horizontal se preferir uma área maior para desenhar sua assinatura.</p></div><label>Nome completo de quem assina<input className="input" required value={signerName} onChange={(event) => setSignerName(event.target.value)} /></label><SignaturePad onChange={setSignatureImage} /><a className="contract-signature__read-link" href="#contrato-completo">Ler o contrato completo ↓</a><label className="consent"><input type="checkbox" checked={accepted} onChange={(event) => setAccepted(event.target.checked)} /><span>Li e aceito o contrato referente ao aluno acima.</span></label><button className="cta" disabled={busy === 'sign' || !signatureImage || !accepted}>{busy === 'sign' ? 'Registrando assinatura…' : 'Assinar contrato'}</button></form>}{message ? <div className="notice"><span>{message}</span>{message.includes('sucesso') && resumeToken ? <button className="btn" onClick={() => navigate(`${resumePath}?j=${encodeURIComponent(resumeToken)}&f=${resumeFlow}`)}>Voltar para a matrícula</button> : null}</div> : null}</> : null}
      {!dataReady ? <div className="contract-pdf-unavailable">Precisamos confirmar alguns dados do responsável ou aluno antes de gerar o contrato.</div> : !contractsGenerated ? <div className="contract-pdf-unavailable">{busy === 'generate' ? 'Gerando seu contrato individual…' : <><span>O PDF individual ainda não foi preparado.</span><button type="button" className="btn" onClick={() => { generatedFor.current = ''; contract.refresh(); }}>Tentar novamente</button></>}</div> : <section className="contract-viewer" id="contrato-completo"><div className="contract-viewer__intro"><strong>Leia o contrato completo</strong><span>O documento foi preenchido com os dados confirmados. Você pode ampliar nele mesmo ou abrir em tela cheia.</span></div>{data.enrollments?.map((item) => <ContractPdfPanel key={item.id} token={token} enrollment={item} />)}</section>}
    </div>
  </section>{showDataModal && !signed ? <ContractDataModal data={data.required_data} busy={busy === 'required'} error={dataSaveError} onClose={() => setShowDataModal(false)} onSubmit={submitRequiredData} /> : null}</main> : null}</DataState>;
}
