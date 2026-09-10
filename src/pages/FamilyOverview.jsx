import { useOutletContext, useParams } from 'react-router-dom';
import { DATA, findFamily, initials } from '../data/content';
import { Badge } from '../components/ui';

export default function FamilyOverview() {
  const { id } = useParams();
  const family = useOutletContext() || findFamily(id);

  const [atual, proxima] = family.klass.split('→').map((s) => s.trim());
  const facts = [
    { label: 'Turma atual', value: atual },
    { label: 'Próxima turma', value: proxima || '—' },
    ...DATA.famFacts.slice(2)
  ];

  return (
    <div className="grid grid--main">
      <div className="stack">
        <div className="card">
          <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 18, flexWrap: 'wrap' }}>
            <div style={{ display: 'flex', gap: 14 }}>
              <div className="avatar avatar--lg">{initials(family.parent)}</div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                <h2 style={{ fontSize: 21, fontWeight: 800 }}>{family.parent}</h2>
                <span className="meta">{family.phone} · CPF 048.***.***-12</span>
              </div>
            </div>
            <Badge tone={family.tone}>{family.status}</Badge>
          </div>

          <div className="grid grid--4" style={{ marginTop: 20, paddingTop: 20, borderTop: '1px solid var(--line-3)' }}>
            {facts.map((f) => (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 5 }} key={f.label}>
                <span className="stat-label">{f.label}</span>
                <strong style={{ fontSize: 14 }}>{f.value}</strong>
              </div>
            ))}
          </div>
        </div>

        <div className="card">
          <div className="card-title" style={{ marginBottom: 18 }}>Linha do tempo da jornada</div>
          {DATA.timeline.map((t) => (
            <div className="timeline-row" key={t.code}>
              <div className="timeline-time">{t.time}</div>
              <div className="timeline-rail"><i style={{ background: t.color }} /><u /></div>
              <div className="timeline-body">
                <div style={{ display: 'flex', alignItems: 'center', gap: 9, flexWrap: 'wrap' }}>
                  <h4>{t.title}</h4>
                  <span className="timeline-code">{t.code}</span>
                </div>
                <p>{t.body}</p>
              </div>
            </div>
          ))}
        </div>
      </div>

      <div className="stack">
        <div className="card">
          <div className="card-title" style={{ marginBottom: 14 }}>Controles</div>
          <div className="grid grid--2">
            {DATA.familyActions.map((a) => (
              <button type="button" className="btn" style={{ padding: '11px 12px' }} key={a}>{a}</button>
            ))}
          </div>
          <div className="notice notice--soft" style={{ marginTop: 14 }}>
            <p>Automação ativa. Ao assumir a conversa, a IA para de responder até você devolver o atendimento.</p>
          </div>
        </div>

        <div className="card">
          <div className="card-title" style={{ marginBottom: 14 }}>Assinatura e pagamento</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 11 }}>
            {DATA.payRows.map((p) => (
              <div className="row-item" style={{ background: 'var(--surface)', borderColor: 'var(--line-2)' }} key={p.label}>
                <div className="who"><strong>{p.label}</strong><span>{p.sub}</span></div>
                <Badge tone={p.tone}>{p.status}</Badge>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
