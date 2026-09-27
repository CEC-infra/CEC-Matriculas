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
import ContractSignature from './pages/ContractSignature';
import LinkMatricula from './pages/LinkMatricula';
import LinkGenerator from './pages/LinkGenerator';
import AuthGate from './components/AuthGate';
import EnrollmentOnboarding from './pages/EnrollmentOnboarding';

/* Uma rota por tela. O detalhe da família tem rotas filhas — cada subaba é um
   caminho próprio, então recarregar ou compartilhar a URL cai na mesma aba. */
export default function App() {
  return (
    <Routes>
      <Route path="matricula" element={<EnrollmentOnboarding />} />
      <Route path="matricula/:token" element={<LinkMatricula />} />
      <Route path="rematricula" element={<EnrollmentOnboarding initialFlow="rematricula" />} />
      <Route path="rematricula/:token" element={<LinkRematricula />} />
      <Route path="contrato/:token" element={<ContractSignature />} />
      <Route element={<AuthGate><Layout /></AuthGate>}>
        <Route index element={<Navigate to="/dashboard" replace />} />
        <Route path="dashboard" element={<Dashboard />} />
        <Route path="links" element={<LinkGenerator />} />

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

        <Route path="*" element={<Navigate to="/dashboard" replace />} />
      </Route>
    </Routes>
  );
}
