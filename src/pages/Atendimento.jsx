import { useState } from 'react';
import { useNavigate, useOutletContext } from 'react-router-dom';
import { DATA, findFamily, initials } from '../data/content';

/* Serve a /atendimento e a /familias/:id/atendimento. No segundo caso a família
   chega pelo contexto do <Outlet> e clicar numa conversa troca de rota. */
export default function Atendimento() {
  const contextFamily = useOutletContext();
  const navigate = useNavigate();
  const [localId, setLocalId] = useState(DATA.convos.find((c) => c.active).id);

  const activeId = contextFamily ? contextFamily.id : localId;
  const family = contextFamily || findFamily(activeId);
  const openConvo = (id) => (contextFamily ? navigate(`/familias/${id}/atendimento`) : setLocalId(id));

  return (
    <div className="chat">
      <div className="chat-list">
        <div className="chat-list-head">
          <strong style={{ fontSize: 13.5 }}>Conversas</strong>
          <span className="meta">{DATA.convos.length} abertas</span>
        </div>
        {DATA.convos.map((c) => (
          <div
            className={`convo${c.id === activeId ? ' is-active' : ''}`}
            key={c.id}
            onClick={() => openConvo(c.id)}
          >
            <div className="convo-top"><strong>{c.name}</strong><span>{c.time}</span></div>
            <div className="convo-last">{c.last}</div>
            <div className="convo-tag" style={{ color: c.color }}>{c.tag}</div>
          </div>
        ))}
      </div>

      <div className="chat-main">
        <div className="chat-head">
          <div style={{ display: 'flex', alignItems: 'center', gap: 11 }}>
            <div className="avatar">{initials(family.parent)}</div>
            <div style={{ display: 'flex', flexDirection: 'column' }}>
              <strong style={{ fontSize: 14 }}>{family.parent}</strong>
              <span className="meta">{family.student} · {family.klass}</span>
            </div>
          </div>
          <span className="badge badge--solid-ok">IA respondendo</span>
        </div>

        <div className="chat-thread">
          {DATA.thread.map((m, i) => (
            <div className={`msg msg--${m.dir}`} key={i}>
              <div className="bubble">{m.text}</div>
              <small>{m.meta}</small>
            </div>
          ))}
        </div>

        <div className="chat-compose">
          <div className="control">Assuma a conversa para escrever…</div>
          <button type="button" className="btn btn--primary" style={{ padding: '12px 18px', fontSize: 13 }}>Enviar</button>
        </div>
      </div>

      <div className="chat-aside">
        <div className="card-title" style={{ fontSize: 14, marginBottom: 13 }}>Contexto da IA</div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 11, marginBottom: 20 }}>
          {DATA.chatIntel.map((i) => (
            <div
              key={i.label}
              style={{ display: 'flex', flexDirection: 'column', gap: 3, paddingBottom: 11, borderBottom: '1px solid var(--surface-3)' }}
            >
              <span className="stat-label">{i.label}</span>
              <strong style={{ fontSize: 13 }}>{i.value}</strong>
            </div>
          ))}
        </div>

        <div className="card-title" style={{ fontSize: 14, marginBottom: 12 }}>Handoff</div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 9 }}>
          {DATA.handoff.map((h) => (
            <button type="button" className={`btn ${h.variant} btn--block`} style={{ padding: 12, fontSize: 13 }} key={h.label}>
              {h.label}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
