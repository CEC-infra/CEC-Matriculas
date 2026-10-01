import { useMemo, useState } from 'react';
import { contractPdfUrl } from '../services/data';
import { date, money } from '../lib/format';

const methodLabel = { boleto: 'Boleto', cartao: 'Cartão de crédito', pix: 'Pix' };

// Mesma divisão de public.generate_installments(): a primeira parcela leva o
// resto dos centavos. Calculada por aluno, porque cada matrícula tem as suas.
function splitInstallments(totalCents, count) {
  const base = Math.floor(totalCents / count);
  return Array.from({ length: count }, (_, index) => base + (index === 0 ? totalCents - base * count : 0));
}

export function familySchedule(children, choice) {
  if (!choice) return [];
  const count = Number(choice.installments) || 1;
  const sums = Array(count).fill(0);
  children.forEach((child) => splitInstallments(Number(child.amount_cents) || 0, count).forEach((value, index) => { sums[index] += value; }));
  return sums.map((amount, index) => ({ amount, due: choice.due_dates?.[index] }));
}

export function choiceSummary(choice, children) {
  if (!choice) return '';
  const schedule = familySchedule(children, choice);
  if (schedule.length === 1) return `${methodLabel[choice.method] || choice.method} à vista · ${money(schedule[0].amount)} em ${date(schedule[0].due)}`;
  const sameValue = schedule.every((item) => item.amount === schedule[schedule.length - 1].amount);
  return `${methodLabel[choice.method] || choice.method} em ${schedule.length}x ${sameValue ? `de ${money(schedule[0].amount)}` : `(${schedule.map((item) => money(item.amount)).join(' + ')})`}`;
}

export function ValuesStep({ data, busy, onConfirm, onEditChildren }) {
  const children = (data.children || []).filter((child) => child.selected);
  const choices = data.payment_choices || [];
  const early = Boolean(data.pricing?.early_active);
  const earlyUntil = data.pricing?.early_until;
  const initial = choices.find((item) => item.option === data.payment_choice?.option) || choices[0];
  const [installments, setInstallments] = useState(initial?.installments || 1);
  const [method, setMethod] = useState(initial?.method || 'pix');

  const counts = useMemo(() => [...new Set(choices.map((item) => item.installments))].sort((a, b) => b - a), [choices]);
  const methods = choices.filter((item) => item.installments === installments).map((item) => item.method);
  const current = choices.find((item) => item.installments === installments && item.method === method)
    || choices.find((item) => item.installments === installments);
  const schedule = familySchedule(children, current);

  const total = children.reduce((sum, child) => sum + (Number(child.amount_cents) || 0), 0);
  const fullTotal = children.reduce((sum, child) => sum + (Number(child.full_amount_cents) || Number(child.amount_cents) || 0), 0);
  const savings = early ? Math.max(0, fullTotal - total) : 0;

  function pickInstallments(count) {
    setInstallments(count);
    const available = choices.filter((item) => item.installments === count).map((item) => item.method);
    if (!available.includes(method)) setMethod(available[0]);
  }

  if (!choices.length) {
    return <div className="notice"><span>O prazo de pagamento da rematrícula 2027 terminou. Fale com a secretaria para concluir.</span></div>;
  }

  return <section className="onboarding-form values-step">
    {early ? <div className="values-hero">
      <span className="values-hero__tag">Valor especial até {date(earlyUntil)}</span>
      <div className="values-hero__numbers">
        <div><small>Tabela 2027</small><s>{money(fullTotal)}</s></div>
        <div className="values-hero__main"><small>Fechando em outubro você paga</small><strong>{money(total)}</strong></div>
      </div>
      {savings > 0 ? <p>Você economiza <b>{money(savings)}</b> e ainda pode parcelar em até 3x.</p> : null}
    </div> : <div className="values-hero values-hero--plain">
      <span className="values-hero__tag">Tabela 2027</span>
      <div className="values-hero__numbers"><div className="values-hero__main"><small>Valor da rematrícula</small><strong>{money(total)}</strong></div></div>
      <p>O valor especial de outubro terminou em {date(earlyUntil)}. Agora o pagamento é à vista no Pix, com vencimento em {date(choices[0]?.due_dates?.[0])}.</p>
    </div>}

    <div className="values-children">
      {children.map((child) => <article key={child.student_id}>
        <div><strong>{child.name}</strong><span>{child.target_grade} · 2027</span></div>
        <div className="values-children__price">{early && child.full_amount_cents > child.amount_cents ? <s>{money(child.full_amount_cents)}</s> : null}<b>{money(child.amount_cents)}</b></div>
      </article>)}
      <button type="button" className="text-link" onClick={onEditChildren}>Alterar alunos</button>
    </div>

    <div className="values-config">
      <h3>Como você prefere pagar?</h3>
      {counts.length > 1 ? <div className="values-segment" role="radiogroup" aria-label="Número de parcelas">
        {counts.map((count) => <button type="button" role="radio" aria-checked={installments === count} key={count} className={installments === count ? 'is-active' : ''} onClick={() => pickInstallments(count)}>
          <strong>{count === 1 ? 'À vista' : `${count}x`}</strong>
          <small>{count === 1 ? 'Pix em janeiro' : count === 3 ? 'nov, dez e jan' : 'dez e jan'}</small>
        </button>)}
      </div> : null}
      {methods.length > 1 ? <div className="values-methods" role="radiogroup" aria-label="Forma de pagamento">
        {methods.map((item) => <button type="button" role="radio" aria-checked={method === item} key={item} className={`btn${method === item ? ' btn--primary' : ''}`} onClick={() => setMethod(item)}>{methodLabel[item]}</button>)}
      </div> : null}

      <div className="values-schedule">
        {schedule.map((item, index) => <div key={item.due || index}>
          <span>{schedule.length > 1 ? `${index + 1}ª parcela` : 'Parcela única'} · vence {date(item.due)}</span>
          <b>{money(item.amount)}</b>
        </div>)}
        <div className="values-schedule__total"><span>Total</span><b>{money(total)}</b></div>
      </div>
      <p className="meta">{methodLabel[current?.method]}{current?.method === 'boleto' ? ': um boleto para cada vencimento.' : current?.method === 'cartao' ? ': parcelado no cartão, sem acréscimo no valor.' : ': pagamento único pelo Pix.'} O link de pagamento chega depois da assinatura.</p>
    </div>

    {early ? <div className="notice"><span>O valor fica garantido quando você assinar o contrato. Assinando a partir de 01/11, vale a tabela 2027 em Pix à vista.</span></div> : null}
    <button className="cta" disabled={busy || !current} onClick={() => onConfirm(current.option)}>{busy ? 'Salvando…' : 'Confirmar e seguir para assinatura →'}</button>
  </section>;
}

export function PaymentChoiceBar({ data, onChange }) {
  const children = (data.children || []).filter((child) => child.selected);
  const choice = data.payment_choice;
  if (!choice) return null;
  const anySigned = children.some((child) => child.contract_status === 'assinada');
  return <div className="values-choice-bar">
    <div><small>Forma de pagamento escolhida</small><strong>{choiceSummary(choice, children)}</strong></div>
    {!anySigned && onChange ? <button type="button" className="text-link" onClick={onChange}>Alterar</button> : null}
  </div>;
}

export function SignedContracts({ data }) {
  const children = (data.children || []).filter((child) => child.selected && child.contract_token && child.enrollment_id);
  if (!children.length) return null;
  return <div className="values-downloads">
    <h3>Contratos assinados</h3>
    {children.map((child) => <a key={child.enrollment_id} className="btn" href={contractPdfUrl(child.contract_token, child.enrollment_id)} target="_blank" rel="noreferrer">⬇ Baixar contrato de {child.name.split(' ')[0]}</a>)}
  </div>;
}
