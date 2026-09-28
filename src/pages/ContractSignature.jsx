import { useEffect, useRef, useState } from 'react';
import { useNavigate, useParams, useSearchParams } from 'react-router-dom';
import DataState from '../components/DataState';
import { LogoBlocks } from '../components/ui';
import { useAsyncData } from '../hooks/useAsyncData';
import { money } from '../lib/format';
import { openContract, sendContractCode, signContract, verifyContractCode } from '../services/data';

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

export default function ContractSignature() {
  const { token } = useParams();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const contract = useAsyncData(() => openContract(token), [token]);
  const [code, setCode] = useState('');
  const [signerName, setSignerName] = useState('');
  const [signatureImage, setSignatureImage] = useState('');
  const [accepted, setAccepted] = useState(false);
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState('');
  const [verified, setVerified] = useState(false);
  const [resendIn, setResendIn] = useState(60);
  const [codeSent, setCodeSent] = useState(false);

  useEffect(() => {
    if (contract.data?.guardian?.name && !signerName) setSignerName(contract.data.guardian.name);
    setVerified(Boolean(contract.data?.email_verified));
    setCodeSent(contract.data?.status === 'codigo_enviado' || contract.data?.status === 'verificada');
    if (contract.data?.status === 'pronta') setResendIn(0);
  }, [contract.data, signerName]);

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

  const data = contract.data;
  const signed = data?.status === 'assinada';
  const contractPdf = data?.enrollments?.[0]?.contract?.storage_path;
  const emailDeliveryStatus = data?.email_delivery_status;
  const codeAvailable = codeSent && emailDeliveryStatus === 'enviado';
  const emailPending = codeSent && ['pendente', 'processando'].includes(emailDeliveryStatus);
  const emailFailed = codeSent && emailDeliveryStatus === 'falhou';
  const resumeToken = searchParams.get('j');
  const resumeFlow = searchParams.get('f') === 'matricula_nova' ? 'matricula_nova' : 'rematricula';
  const resumePath = resumeFlow === 'matricula_nova' ? '/matricula' : '/rematricula';
  return <DataState loading={contract.loading} error={contract.error} empty={!contract.loading && !contract.error && !data}>{data ? <main className="auth-page" style={{ padding: '32px 18px' }}><section className="public public--single" style={{ width: 'min(860px, 100%)' }}><div className="public-head--navy"><div style={{ display: 'flex', alignItems: 'center', gap: 12 }}><LogoBlocks /><span className="public-kicker">Contrato digital</span></div><h2>Assinatura de matrícula</h2><p>Leia o documento, confirme o e-mail e assine para concluir esta etapa.</p></div><div className="public-body"><div className="notice notice--soft"><span>Responsável: <strong>{data.guardian?.name}</strong> · confirmação em {data.email_masked}</span></div><div><h3 style={{ fontSize: 16, marginBottom: 10 }}>Aluno</h3><div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>{data.enrollments?.map((item) => <div className="row-item" style={{ background: 'var(--surface)' }} key={item.id}><div className="who"><strong>{item.student_name}</strong><span>{item.grade}</span></div><strong>{money(item.amount_cents)}</strong></div>)}</div></div><section className="contract-viewer"><div><strong>Leia o contrato</strong><span>Deslize para ler todo o documento antes de assinar.</span></div>{contractPdf ? <iframe title="Contrato em PDF" src={contractPdf} className="contract-pdf" /> : <div className="contract-pdf-unavailable">O PDF desta versão ainda não foi disponibilizado pela escola.</div>}</section>{signed ? <div className="notice"><span>Contrato já assinado em segurança.</span>{resumeToken ? <button className="btn" onClick={() => navigate(`${resumePath}?j=${encodeURIComponent(resumeToken)}&f=${resumeFlow}`)}>Voltar para a matrícula</button> : null}</div> : <>{!verified ? <form className="contract-confirmation" onSubmit={codeAvailable ? confirmCode : (event) => { event.preventDefault(); if (!emailPending) resendCode(); }}><div className="contract-confirmation__head"><span className={`contract-confirmation__status${codeAvailable ? ' is-sent' : emailFailed ? ' is-failed' : ''}`}>{codeAvailable ? 'Código entregue' : emailFailed ? 'Falha no envio' : emailPending ? 'Aguardando envio' : 'Confirmação por e-mail'}</span><h3>{codeAvailable ? 'Confirme seu e-mail' : emailFailed ? 'Não foi possível entregar o código' : emailPending ? 'Seu código está na fila de envio' : 'Pronto para assinar?'}</h3><p>{codeAvailable ? `Digite os seis caracteres enviados para ${data.email_masked}.` : emailFailed ? `O envio para ${data.email_masked} falhou. Você poderá solicitar um novo código.` : emailPending ? `O código foi solicitado para ${data.email_masked}. Esta página atualizará automaticamente assim que ele for enviado.` : `Ao continuar, solicitaremos um código de confirmação para ${data.email_masked}.`}</p></div>{codeAvailable ? <label className="contract-confirmation__field"><span>Código de confirmação</span><input className="contract-code-input" required inputMode="text" maxLength="6" value={code} onChange={(event) => setCode(event.target.value.toUpperCase().replace(/\s/g, ''))} placeholder="A1B2C3" autoComplete="one-time-code" /></label> : null}<div className="contract-confirmation__actions">{codeAvailable ? <button className="btn btn--primary" disabled={Boolean(busy)}>{busy === 'verify' ? 'Confirmando…' : 'Confirmar código'}</button> : emailPending ? <button type="button" className="btn" disabled>Verificando envio…</button> : <button className="btn btn--primary" disabled={Boolean(busy)}>{busy === 'code' ? 'Solicitando…' : emailFailed ? 'Solicitar novo código' : 'Enviar código para assinar'}</button>}{(codeAvailable || emailFailed) ? <button type="button" className="btn" onClick={resendCode} disabled={Boolean(busy) || resendIn > 0}>{resendIn > 0 ? `Reenviar em ${resendIn}s` : 'Reenviar código'}</button> : null}</div></form> : <form onSubmit={submitSignature} style={{ display: 'flex', flexDirection: 'column', gap: 15 }}><div><h3 style={{ fontSize: 16, marginBottom: 5 }}>Assine o contrato</h3><p className="meta">No celular, vire-o na horizontal se preferir uma área maior. A assinatura, o e-mail confirmado, a data, o PDF e sua impressão digital serão registrados.</p></div><label>Nome completo de quem assina<input className="input" required value={signerName} onChange={(event) => setSignerName(event.target.value)} /></label><SignaturePad onChange={setSignatureImage} /><label className="consent"><input type="checkbox" checked={accepted} onChange={(event) => setAccepted(event.target.checked)} /><span>Li e aceito o contrato referente ao aluno acima.</span></label><button className="cta" disabled={busy === 'sign' || !signatureImage || !accepted}>{busy === 'sign' ? 'Registrando assinatura…' : 'Assinar contrato'}</button></form>}{message ? <div className="notice"><span>{message}</span>{message.includes('sucesso') && resumeToken ? <button className="btn" onClick={() => navigate(`${resumePath}?j=${encodeURIComponent(resumeToken)}&f=${resumeFlow}`)}>Voltar para a matrícula</button> : null}</div> : null}</>}</div></section></main> : null}</DataState>;
}
