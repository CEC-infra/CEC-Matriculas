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

export function statusTone(status) {
  if (['concluido', 'pago', 'assinado', 'efetivada'].includes(status)) return 'ok';
  if (['precisa_humano', 'vencido', 'falhou', 'link_aberto'].includes(status)) return 'warn';
  if (['pre_matricula', 'formulario_iniciado', 'link_enviado'].includes(status)) return 'info';
  return 'mute';
}

export function shiftLabel(shift) {
  return ({ manha: 'Manhã', tarde: 'Tarde', integral: 'Integral' })[shift] || '—';
}
