import { BrowserRouter, HashRouter, Routes, Route, Navigate } from 'react-router-dom';
import { AuthProvider } from './context/AuthContext';
import { ProtectedRoute } from './components/ProtectedRoute';
import Layout from './components/Layout';
import Login from './pages/Login';
import ServiceProviders from './pages/admin/ServiceProviders';
import Customers from './pages/admin/Customers';
import BusinessAgents from './pages/admin/BusinessAgents';
import Configuration from './pages/admin/Configuration';
import Reports from './pages/admin/Reports';
import Broadcast from './pages/admin/Broadcast';
import Tracking from './pages/admin/Tracking';
import Devices from './pages/admin/Devices';
import AuditLog from './pages/admin/AuditLog';
import MyReferrals from './pages/partner/MyReferrals';
import MyRevenue from './pages/partner/MyRevenue';

// A single-file build (see build-single-file.mjs) is opened straight from a
// URL with no server to rewrite paths, so deep links have to live in the hash.
// Local dev keeps the tidier history-API routes.
const Router = import.meta.env.VITE_HASH_ROUTER === 'true' ? HashRouter : BrowserRouter;

export default function App() {
  return (
    <Router>
      <AuthProvider>
        <Routes>
          <Route path="/login" element={<Login />} />

          <Route element={<ProtectedRoute allow="admin" />}>
            <Route element={<Layout />}>
              <Route path="/admin/providers" element={<ServiceProviders />} />
              <Route path="/admin/customers" element={<Customers />} />
              <Route path="/admin/business-agents" element={<BusinessAgents />} />
              <Route path="/admin/configuration" element={<Configuration />} />
              <Route path="/admin/reports" element={<Reports />} />
              <Route path="/admin/broadcast" element={<Broadcast />} />
              <Route path="/admin/tracking" element={<Tracking />} />
              <Route path="/admin/devices" element={<Devices />} />
              <Route path="/admin/audit-log" element={<AuditLog />} />
            </Route>
          </Route>

          <Route element={<ProtectedRoute allow="business_agent" />}>
            <Route element={<Layout />}>
              <Route path="/partner/referrals" element={<MyReferrals />} />
              <Route path="/partner/revenue" element={<MyRevenue />} />
            </Route>
          </Route>

          <Route path="/" element={<Navigate to="/login" replace />} />
          <Route path="*" element={<Navigate to="/login" replace />} />
        </Routes>
      </AuthProvider>
    </Router>
  );
}
