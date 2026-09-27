import { useEffect, useRef, useState } from 'react';
import { useParams } from 'react-router-dom';
import DataState from '../components/DataState';
import { LogoBlocks } from '../components/ui';
import { useAsyncData } from '../hooks/useAsyncData';
import { money, shiftLabel } from '../lib/format';
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
  const contract = useAsyncData(() => openContract(token), [token]);
  const [code, setCode] = useState('');
  const [signerName, setSignerName] = useState('');
  const [signatureImage, setSignatureImage] = useState('');
  const [accepted, setAccepted] = useState(false);
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState('');
  const [verified, setVerified] = useState(false);

  useEffect(() => {
    if (contract.data?.guardian?.name && !signerName) setSignerName(contract.data.guardian.name);
    setVerified(Boolean(contract.data?.email_verified));
  }, [contract.data, signerName]);

  async function resendCode() {
    setBusy('code'); setMessage('');
    try {
      await sendContractCode(token);
      setMessage('Enviamos um novo código de confirmação para o e-mail informado.');
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
  return <DataState loading={contract.loading} error={contract.error} empty={!contract.loading && !contract.error && !data}>{data ? <main className="auth-page" style={{ padding: '32px 18px' }}><section className="public public--single" style={{ width: 'min(860px, 100%)' }}><div className="public-head--navy"><div style={{ display: 'flex', alignItems: 'center', gap: 12 }}><LogoBlocks /><span className="public-kicker">Contrato digital</span></div><h2>Assinatura de matrícula</h2><p>Confira os dados, confirme o código enviado por e-mail e assine para concluir esta etapa.</p></div><div className="public-body"><div className="notice notice--soft"><span>Responsável: <strong>{data.guardian?.name}</strong> · confirmação em {data.email_masked}</span></div><div><h3 style={{ fontSize: 16, marginBottom: 10 }}>Alunos incluídos</h3><div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>{data.enrollments?.map((item) => <div className="row-item" style={{ background: 'var(--surface)' }} key={item.id}><div className="who"><strong>{item.student_name}</strong><span>{item.grade} · {shiftLabel(item.shift)} · {item.payment_plan || 'Condição a confirmar'}</span></div><strong>{money(item.amount_cents)}</strong></div>)}</div></div>{signed ? <div className="notice"><span>Contrato já assinado em segurança. A escola dará sequência ao envio dos boletos.</span></div> : <>{!verified ? <form onSubmit={confirmCode} style={{ display: 'flex', flexDirection: 'column', gap: 12 }}><div><h3 style={{ fontSize: 16, marginBottom: 5 }}>Confirme seu e-mail</h3><p className="meta">Digite o código de seis caracteres enviado para {data.email_masked}.</p></div><input className="input" required maxLength="6" value={code} onChange={(event) => setCode(event.target.value.toUpperCase())} placeholder="Ex.: A1B2C3" style={{ letterSpacing: 3, maxWidth: 260 }} /><div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}><button className="btn btn--primary" disabled={busy === 'verify'}>{busy === 'verify' ? 'Confirmando…' : 'Confirmar código'}</button><button type="button" className="btn" onClick={resendCode} disabled={Boolean(busy)}>{busy === 'code' ? 'Enviando…' : 'Reenviar código'}</button></div></form> : <form onSubmit={submitSignature} style={{ display: 'flex', flexDirection: 'column', gap: 15 }}><div><h3 style={{ fontSize: 16, marginBottom: 5 }}>Assine o contrato</h3><p className="meta">Sua assinatura, confirmação de e-mail e data serão registradas como evidência do aceite.</p></div><label>Nome completo de quem assina<input className="input" required value={signerName} onChange={(event) => setSignerName(event.target.value)} /></label><SignaturePad onChange={setSignatureImage} /><label className="consent"><input type="checkbox" checked={accepted} onChange={(event) => setAccepted(event.target.checked)} /><span>Li e aceito o contrato referente aos alunos e condições acima.</span></label><button className="cta" disabled={busy === 'sign' || !signatureImage || !accepted}>{busy === 'sign' ? 'Registrando assinatura…' : 'Assinar contrato'}</button></form>}{message ? <div className="notice"><span>{message}</span></div> : null}</>}</div></section></main> : null}</DataState>;
}
