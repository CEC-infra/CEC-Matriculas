import { Navigate, Route, Routes } from 'react-router-dom';
import Layout from './components/Layout';
import Dashboard from './pages/Dashboard';
import Familias from './pages/Familias';
import FamilyDetail from './pages/FamilyDetail';
import FamilyOverview from './pages/FamilyOverview';
import Atendimento from './pages/Atendimento';
import MatriculasNovas from './pages/MatriculasNovas';
import Matriculados from './pages/Matriculados';
import Automacao from './pages/Automacao';
import AssinaturaPagamento from './pages/AssinaturaPagamento';
import Configuracoes from './pages/Configuracoes';
import LinkRematricula from './pages/LinkRematricula';
import PreMatricula from './pages/PreMatricula';

/* Uma rota por tela. O detalhe da família tem rotas filhas — cada subaba é um
   caminho próprio, então recarregar ou compartilhar a URL cai na mesma aba. */
export default function App() {
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route index element={<Navigate to="/dashboard" replace />} />
        <Route path="dashboard" element={<Dashboard />} />

        <Route path="familias" element={<Familias />} />
        <Route path="familias/:id" element={<FamilyDetail />}>
          <Route index element={<FamilyOverview />} />
          <Route path="atendimento" element={<Atendimento />} />
          <Route path="assinatura" element={<AssinaturaPagamento />} />
        </Route>

        <Route path="atendimento" element={<Atendimento />} />
        <Route path="matriculas-novas" element={<MatriculasNovas />} />
        <Route path="matriculados" element={<Matriculados />} />
        <Route path="automacao" element={<Automacao />} />
        <Route path="assinatura-e-pagamento" element={<AssinaturaPagamento />} />
        <Route path="configuracoes" element={<Configuracoes />} />

        <Route path="rematricula" element={<LinkRematricula />} />
        <Route path="matricula" element={<PreMatricula />} />

        <Route path="*" element={<Navigate to="/dashboard" replace />} />
      </Route>
    </Routes>
  );
}
