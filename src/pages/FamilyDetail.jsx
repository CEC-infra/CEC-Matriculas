import { useContext, useEffect } from 'react';
import { Link, NavLink, Outlet, useParams } from 'react-router-dom';
import DataState from '../components/DataState';
import { useAsyncData } from '../hooks/useAsyncData';
import { getEnrollmentDetail } from '../services/data';
import { FamilyHeaderContext } from '../contexts/FamilyHeaderContext';

export default function FamilyDetail() {
  const { id } = useParams();
  const { loading, data, error } = useAsyncData(() => getEnrollmentDetail(id), [id]);
  const setFamilyHeader = useContext(FamilyHeaderContext);
  const tabs = [{ to: `/familias/${id}`, label: 'Detalhe da família', end: true }, { to: `/familias/${id}/assinatura`, label: 'Assinatura e pagamento' }];

  useEffect(() => {
    if (!data?.enrollment) return undefined;
    const enrollment = data.enrollment;
    const progression = enrollment.from_class_name
      ? `${enrollment.from_class_name} → ${enrollment.target_grade_name}`
      : enrollment.target_grade_name;
    setFamilyHeader({
      enrollmentId: id,
      crumb: `Famílias / ${enrollment.guardian_name}`,
      title: `${enrollment.guardian_name} · ${enrollment.student_name}, ${progression}`
    });
    return () => setFamilyHeader(null);
  }, [data, id, setFamilyHeader]);

  return <><div className="subnav"><Link className="back-link" to="/familias">← Voltar para Famílias</Link><div className="tabs">{tabs.map((item) => <NavLink key={item.to} to={item.to} end={item.end} className={({ isActive }) => `tab${isActive ? ' is-active' : ''}`}>{item.label}</NavLink>)}</div></div><DataState loading={loading} error={error} empty={!loading && !error && !data}><Outlet context={data} /></DataState></>;
}
