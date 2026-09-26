import { Router } from 'express';
import * as a from '../controllers/adminController.js';
import * as ba from '../controllers/businessAgentController.js';
import { requireAuth } from '../middleware/auth.js';

const router = Router();
router.use(requireAuth('admin'));

router.get('/providers', a.listProviders);
router.post('/providers/:id/approve', a.approveProvider);
router.post('/providers/:id/hold', a.holdProvider);
router.post('/providers/:id/reject', a.rejectProvider);
router.post('/providers/:id/block', a.blockProvider);
router.post('/providers/:id/reset-device', a.resetProviderDevice);
router.post('/providers/:id/unblock', a.unblockProvider);
router.delete('/providers/:id', a.deleteProvider);

router.get('/customers', a.listCustomers);
router.post('/customers/:id/block', a.blockCustomer);
router.post('/customers/:id/unblock', a.unblockCustomer);
router.delete('/customers/:id', a.deleteCustomer);

router.get('/business-agents', a.listBusinessAgents);
router.post('/business-agents', a.createBusinessAgent);
router.put('/business-agents/:id', a.updateBusinessAgent);
router.post('/business-agents/referrals/:id/allocate', a.allocateReferral);
// The console's "View partner" panel. It used to call the partner's own
// /business-agents/me/* routes with a business_partner_id parameter, which an
// admin token cannot pass and those handlers would have ignored anyway.
router.get('/business-agents/:id/referrals', ba.adminListReferrals);
router.get('/business-agents/:id/revenue', ba.adminGetRevenue);

router.get('/config', a.getConfigAll);
router.put('/config', a.putConfig);

router.get('/revenue-sharing', a.getRevenueSharing);
router.put('/revenue-sharing', a.putRevenueSharing);

router.get('/time-bank-config', a.getTimeBankConfig);
router.put('/time-bank-config', a.putTimeBankConfig);

router.post('/broadcast', a.createBroadcast);
router.get('/broadcast', a.listBroadcasts);
// Asked while the form is still being filled in, so nobody discovers that a
// city means two people by sending to them. Writes nothing.
router.post('/broadcast/preview', a.previewBroadcast);
router.get('/broadcast/cities', a.broadcastCities);

router.get('/tracking/providers', a.trackAllProviders);

router.get('/reports/dashboard', a.reportsDashboard);
router.get('/reports/growth', a.reportsGrowth);
// Demand by city, including the cities Sathiyaa does not serve yet.
router.get('/reports/signup-places', a.signupPlaces);

router.get('/audit-log', a.listAuditLog);

router.get('/sos', a.listSosAlerts);
router.post('/sos/:id/acknowledge', a.acknowledgeSosAlert);

router.get('/devices', a.listDevices);
router.get('/devices/by-device/:deviceId', a.listAccountsOnDevice);
router.get('/devices/:userType/:userId', a.listDevicesForUser);

router.post('/me/password', a.changeOwnPassword);

export default router;
