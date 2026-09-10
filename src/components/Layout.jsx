import { useEffect } from 'react';
import { NavLink, Outlet, matchPath, useLocation } from 'react-router-dom';
import { DATA, findFamily } from '../data/content';
import Icon from './Icon';

/** Migalha e título do header, derivados da rota atual. */
function headFor(pathname) {
  const fam = matchPath('/familias/:id/*', pathname) || matchPath('/familias/:id', pathname);
  if (fam) {
    const f = findFamily(fam.params.id);
    return [`Famílias / ${f.parent}`, `${f.parent} · ${f.student}, ${f.klass}`];
  }
  return DATA.heads[pathname] || ['', ''];
}

function Sidebar() {
  return (
    <aside className="sidebar">
      <div className="brand">
        <div className="logo">
          <span className="logo-c">C</span>
          <span className="logo-e">E</span>
          <span className="logo-c2">C</span>
        </div>
        <div className="brand-text">
          <strong>Matrícula Inteligente</strong>
          <span>Centro Educacional Cristão</span>
        </div>
      </div>

      <nav className="nav">
        <div className="nav-label">Operação</div>
        {DATA.nav.map((item) => (
          <NavLink
            key={item.path}
            to={item.path}
            style={{ '--accent': item.dot }}
            className={({ isActive }) => `nav-item${isActive ? ' is-active' : ''}`}
          >
            <span className="nav-icon" aria-hidden="true"><Icon name={item.icon} /></span>
            <span>{item.label}</span>
          </NavLink>
        ))}
      </nav>

      <div className="sidebar-foot">
        <div className="status-box">
          <div className="status-line"><span className="dot dot-green" /> WhatsApp conectado</div>
          <p>fila: 34 na espera<br />último envio há 2 min</p>
        </div>
      </div>
    </aside>
  );
}

function Topbar({ crumb, title }) {
  return (
    <header className="topbar">
      <div className="topbar-title">
        <div className="crumb">{crumb}</div>
        <h1>{title}</h1>
      </div>
      <div className="topbar-links">
        {DATA.headerLinks.map((l) => (
          <NavLink
            key={l.path}
            to={l.path}
            style={{ '--accent': l.dot }}
            className={({ isActive }) => `topbar-link${isActive ? ' is-active' : ''}`}
          >
            <span className="link-icon" aria-hidden="true"><Icon name={l.icon} /></span>
            <span>{l.label}</span>
            <small>{l.url}</small>
          </NavLink>
        ))}
      </div>
    </header>
  );
}

export default function Layout() {
  const { pathname } = useLocation();
  const [crumb, title] = headFor(pathname);

  useEffect(() => { window.scrollTo(0, 0); }, [pathname]);
  useEffect(() => { document.title = title ? `${title} · CEC` : 'CEC · Matrícula Inteligente'; }, [title]);

  return (
    <div className="shell">
      <Sidebar />
      <main className="main">
        <Topbar crumb={crumb} title={title} />
        <div className="body"><Outlet /></div>
      </main>
    </div>
  );
}
