import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Bar, CardHead, KpiRow, Kv } from '../components/ui';
import DataState from '../components/DataState';
import { useAsyncData } from '../hooks/useAsyncData';
import { getDashboard } from '../services/data';
import { money } from '../lib/format';

export default function Dashboard() {
  const navigate = useNavigate();
  const { loading, data, error } = useAsyncData(getDashboard, []);
  const [copied, setCopied] = useState('');
  if (!data?.campaign) return <DataState loading={loading} error={error} empty={!loading && !error}><span /></DataState>;
  const { campaign, funnel = {}, finance = {}, alerts = {}, queue = {} } = data;
  const total = Number(funnel.elegiveis || 0);
  const pct = (value) => total ? `${Math.round((Number(value || 0) / total) * 100)}%` : '0%';
  const kpis = [
    { label: 'Famílias elegíveis', value: total, sub: campaign.name },
    { label: 'Contatadas', value: funnel.contatadas || 0, sub: `${pct(funnel.contatadas)} da base` },
    { label: 'Concluídas', value: funnel.concluido || 0, sub: 'assinatura e pagamento confirmados' },
    { label: 'A fechar', value: funnel.a_fechar || 0, sub: money(funnel.a_fechar_cents) }
  ];
  const stages = [['Contatadas', funnel.contatadas, '#4A7BD8'], ['Responderam', funnel.responderam, '#5B8DEF'], ['Link enviado', funnel.link_enviado, '#F07E26'], ['Link aberto', funnel.link_aberto, '#8A5D08'], ['Formulário iniciado', funnel.formulario_iniciado, '#8356B8'], ['Assinado', funnel.assinado, '#16805D'], ['Concluído', funnel.concluido, '#16805D']];
  const alertItems = [['Conversas travadas', alerts.conversas_travadas, '/atendimento'], ['Pagamentos vencidos', alerts.pagamentos_vencidos, '/assinatura-e-pagamento'], ['Aguardando humano', alerts.aguardando_humano, '/atendimento'], ['Falhas de webhook', alerts.falhas_webhook, '/automacao']];
  const publicUrl = `${window.location.origin}/matricula`;
  async function copyLink() { await navigator.clipboard?.writeText(publicUrl); setCopied('Link copiado.'); }

  return <DataState loading={loading} error={error} empty={false}>
    <KpiRow items={kpis} />
    <div className="card"><div className="card-title">Links da campanha</div><div className="card-sub" style={{ marginBottom: 16 }}>Use o link público para receber novas matrículas. Links de rematrícula são individuais e gerados no cadastro da família.</div><div className="link-card"><div className="link-card-top"><span className="dot" style={{ background: '#4A7BD8', width: 8, height: 8 }} /><strong>Matrícula nova</strong><span className="meta">campanha ativa</span></div><div className="link-url">{publicUrl}</div><div className="link-actions"><button type="button" className="btn btn--primary" onClick={copyLink}>Copiar link</button><button type="button" className="btn" onClick={() => navigate('/matricula')}>Ver página</button>{copied ? <span className="meta">{copied}</span> : null}</div></div></div>
    <div className="grid grid--3">{[['Fechadas', funnel.concluido, finance.recebido_cents, '#16805D'], ['A fechar', funnel.a_fechar, funnel.a_fechar_cents, '#F07E26'], ['Perdidas', funnel.perdidas, funnel.perdidas_cents, '#6B6A63']].map(([label, value, amount, color]) => <div className="close-card" key={label}><div className="close-head"><span>{label}</span><span>{pct(value)}</span></div><div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginTop: 10 }}><span className="close-n">{value || 0}</span><strong style={{ fontSize: 13.5 }}>famílias</strong></div><div className="close-money">{money(amount)}</div><div className="track"><Bar pct={pct(value)} color={color} /></div></div>)}</div>
    <div className="grid grid--main"><div className="card"><CardHead title="Funil da jornada" sub={campaign.name} /><div style={{ display: 'flex', flexDirection: 'column', gap: 11 }}>{stages.map(([label, value, color]) => <div className="funnel-row" key={label}><div className="funnel-label">{label}</div><div className="funnel-bar"><Bar pct={pct(value)} color={color} /></div><div className="funnel-num"><strong>{value || 0}</strong><span className="meta">{pct(value)}</span></div></div>)}</div></div><div className="stack"><div className="card"><div className="card-title">Alertas</div><div className="card-sub" style={{ marginBottom: 16 }}>Exigem ação humana hoje</div>{alertItems.map(([label, value, path]) => <div className="alert" key={label} onClick={() => navigate(path)}><div className="alert-n">{value || 0}</div><div className="alert-text"><strong>{label}</strong><span>Ver detalhes</span></div></div>)}</div><div className="card card--navy"><div className="card-title" style={{ marginBottom: 14 }}>Motor de mensagens</div><Kv label="Na fila" value={queue.na_fila || 0} /><Kv label="Enviadas hoje" value={queue.enviadas_hoje || 0} /><Kv label="Falhas em retry" value={queue.falhas_retry || 0} /></div></div></div>
    <div className="card"><CardHead title="Financeiro da campanha" sub="Valores calculados a partir das parcelas e jornadas reais" /><div className="grid grid--4">{[['Previsto', finance.previsto_cents], ['Contratado', finance.contratado_cents], ['Recebido', finance.recebido_cents], ['Em atraso', finance.em_atraso_cents]].map(([label, value]) => <div className="tile" key={label}><span className="stat-label">{label}</span><span className="tile-big">{money(value)}</span></div>)}</div></div>
  </DataState>;
}
