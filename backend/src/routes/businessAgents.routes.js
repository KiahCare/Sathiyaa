import { Router } from 'express';
import * as ba from '../controllers/businessAgentController.js';
import { requireAuth } from '../middleware/auth.js';

const router = Router();
router.use(requireAuth('business_agent'));

router.get('/me', ba.getMe);
router.put('/me', ba.updateMe);
router.post('/me/referrals', ba.createReferral);
router.get('/me/referrals', ba.listReferrals);
router.get('/me/revenue', ba.getRevenue);

export default router;
