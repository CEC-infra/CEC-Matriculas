export function money(cents = 0) {
  return new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format((Number(cents) || 0) / 100);
}

export function dateTime(value) {
  if (!value) return '—';
  return new Intl.DateTimeFormat('pt-BR', { dateStyle: 'short', timeStyle: 'short' }).format(new Date(value));
}

export function date(value) {
  if (!value) return '—';
  return new Intl.DateTimeFormat('pt-BR', { dateStyle: 'short' }).format(new Date(`${value}T12:00:00`));
}

/** Formata a digitação do CPF sem perder os zeros iniciais. */
export function formatCpf(value) {
  const digits = String(value || '').replace(/\D/g, '').slice(0, 11);
  if (digits.length <= 3) return digits;
  if (digits.length <= 6) return `${digits.slice(0, 3)}.${digits.slice(3)}`;
  if (digits.length <= 9) return `${digits.slice(0, 3)}.${digits.slice(3, 6)}.${digits.slice(6)}`;
  return `${digits.slice(0, 3)}.${digits.slice(3, 6)}.${digits.slice(6, 9)}-${digits.slice(9)}`;
}

/**
 * Exibe telefones brasileiros sem o código do país no formulário.
 * O banco continua recebendo o número normalizado com +55.
 */
export function formatPhoneBr(value) {
  let digits = String(value || '').replace(/\D/g, '');
  if (digits.startsWith('55') && digits.length > 11) digits = digits.slice(2);
  digits = digits.slice(0, 11);
  if (digits.length <= 2) return digits;
  const areaCode = digits.slice(0, 2);
  const localNumber = digits.slice(2);
  if (localNumber.startsWith('9')) {
    if (localNumber.length === 1) return `(${areaCode}) ${localNumber}`;
    if (localNumber.length <= 5) return `(${areaCode}) ${localNumber.slice(0, 1)} ${localNumber.slice(1)}`;
    return `(${areaCode}) ${localNumber.slice(0, 1)} ${localNumber.slice(1, 5)}-${localNumber.slice(5)}`;
  }
  if (localNumber.length <= 4) return `(${areaCode}) ${localNumber}`;
  return `(${areaCode}) ${localNumber.slice(0, 4)}-${localNumber.slice(4)}`;
}

/** Oculta a maior parte de um e-mail sem depender de uma expressão regular do banco. */
export function maskEmail(value) {
  const email = String(value || '').trim();
  const atIndex = email.indexOf('@');
  if (atIndex <= 0 || atIndex === email.length - 1) return email;
  return `${email.slice(0, Math.min(2, atIndex))}***${email.slice(atIndex)}`;
}

export function statusTone(status) {
  if (['concluido', 'pago', 'assinado', 'efetivada'].includes(status)) return 'ok';
  if (['precisa_humano', 'vencido', 'falhou', 'link_aberto'].includes(status)) return 'warn';
  if (['pre_matricula', 'formulario_iniciado', 'link_enviado'].includes(status)) return 'info';
  return 'mute';
}
