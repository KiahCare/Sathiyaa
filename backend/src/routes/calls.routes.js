import { Router } from 'express';
import { startMaskedCall } from '../controllers/callController.js';
import { requireAuth } from '../middleware/auth.js';

const router = Router();
router.post('/:id/masked-call', requireAuth('customer', 'provider'), startMaskedCall);

export default router;
