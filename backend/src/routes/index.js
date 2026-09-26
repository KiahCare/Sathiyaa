import { Router } from 'express';
import authRoutes from './auth.routes.js';
import customersRoutes from './customers.routes.js';
import providersRoutes from './providers.routes.js';
import bookingsRoutes from './bookings.routes.js';
import businessAgentsRoutes from './businessAgents.routes.js';
import adminRoutes from './admin.routes.js';
import callsRoutes from './calls.routes.js';
import uploadsRoutes from './uploads.routes.js';
import broadcastsRoutes from './broadcasts.routes.js';
import publicRoutes from './public.routes.js';

const router = Router();

// Before everything that needs a token: the apps read the service area on
// the welcome screen, when nobody has one yet.
router.use('/public', publicRoutes);
router.use('/auth', authRoutes);
router.use('/customers', customersRoutes);
router.use('/providers', providersRoutes);
router.use('/bookings', bookingsRoutes);
router.use('/bookings', callsRoutes); // adds POST /bookings/:id/masked-call
router.use('/business-agents', businessAgentsRoutes);
router.use('/admin', adminRoutes);
router.use('/uploads', uploadsRoutes);
// The receiving end of an admin broadcast. One mount for both roles;
// the controller reads which from the token.
router.use('/broadcasts', broadcastsRoutes);

export default router;
