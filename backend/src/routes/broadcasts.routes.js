/**
 * The broadcast inbox, for whoever is signed in.
 *
 * Mounted once and shared by both roles rather than duplicated under
 * /customers/me and /providers/me: the controller reads the role off the
 * token, so one mount serves both and there is no second copy to forget to
 * change. requireAuth here lists both roles for the same reason -- an admin
 * has no inbox, so they are deliberately not on it.
 */
import { Router } from 'express';
import * as inbox from '../controllers/broadcastInboxController.js';
import { requireAuth } from '../middleware/auth.js';

const router = Router();
router.use(requireAuth('customer', 'provider'));

router.get('/', inbox.listMine);
router.get('/unread', inbox.unreadCount);
router.post('/:id/read', inbox.markRead); // :id is a broadcast id, or "all"

export default router;
