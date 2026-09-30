import { useEffect, useState } from 'react';
import { NavLink, Outlet, matchPath, useLocation } from 'react-router-dom';
import { FamilyHeaderContext } from '../contexts/FamilyHeaderContext';
import Icon from './Icon';
import cecLogo from '../assets/cec-logo.png';

const navigation = [
  { path: '/dashboard', label: 'Dashboard', icon: 'dashboard', dot: '#E4581C' },
  { path: '/familias', label: 'Famílias', icon: 'families', dot: '#3AA757' },
  { path: '/matriculas-novas', label: 'Matrículas novas', icon: 'newEnroll', dot: '#C77DFF' },
  { path: '/matriculados', label: 'Matriculados', icon: 'enrolled', dot: '#3AA757' },
  { path: '/assinatura-e-pagamento', label: 'Assinatura e pagamento', icon: 'signature', dot: '#3AA757' },
  { path: '/configuracoes', label: 'Configurações', icon: 'settings', dot: '#A8B8E0' }
];

const heads = {
  '/dashboard': ['Campanha 2027', 'Visão geral da operação'],
  '/familias': ['CRM operacional', 'Famílias na campanha'],
  '/matriculas-novas': ['Entrada de novas famílias', 'Matrículas novas'],
  '/matriculados': ['Resultado da campanha', 'Matriculados'],
  '/assinatura-e-pagamento': ['Conclusão da jornada', 'Assinatura digital e pagamento'],
  '/configuracoes': ['Cadastros da campanha', 'Configurações'],
  '/rematricula': ['Jornada online do responsável', 'Página individual de rematrícula'],
  '/matricula': ['Novas matrículas', 'Link público de pré-matrícula'],
  '/links': ['Links das famílias', 'Consultar e copiar links cadastrados']
};

const headerLinks = [
  { path: '/links', label: 'Links individuais', url: 'ver e gerenciar', icon: 'link', dot: '#F07E26' }
];

/** Migalha e título do header, derivados da rota atual. */
function headFor(pathname) {
  const fam = matchPath('/familias/:id/*', pathname) || matchPath('/familias/:id', pathname);
  if (fam) {
    return ['Famílias', 'Detalhe da família'];
  }
  return heads[pathname] || ['', ''];
}

function Sidebar() {
  return (
    <aside className="sidebar">
      <div className="brand">
        <img className="brand-logo" src={cecLogo} alt="Centro Educacional Cristão" />
      </div>

      <nav className="nav">
        <div className="nav-label">Operação</div>
        {navigation.map((item) => (
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
        {headerLinks.map((l) => (
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
  const [familyHeader, setFamilyHeader] = useState(null);
  const familyRoute = matchPath('/familias/:id/*', pathname) || matchPath('/familias/:id', pathname);
  const [fallbackCrumb, fallbackTitle] = headFor(pathname);
  const useLiveHeader = familyRoute && familyHeader?.enrollmentId === familyRoute.params.id;
  const crumb = useLiveHeader ? familyHeader.crumb : fallbackCrumb;
  const title = useLiveHeader ? familyHeader.title : fallbackTitle;

  useEffect(() => { window.scrollTo(0, 0); }, [pathname]);
  useEffect(() => { document.title = title ? `${title} · CEC` : 'CEC · Matrícula Inteligente'; }, [title]);
  useEffect(() => { if (!familyRoute) setFamilyHeader(null); }, [familyRoute]);

  return (
    <div className="shell">
      <Sidebar />
      <main className="main">
        <Topbar crumb={crumb} title={title} />
        <div className="body"><FamilyHeaderContext.Provider value={setFamilyHeader}><Outlet /></FamilyHeaderContext.Provider></div>
      </main>
    </div>
  );
}
