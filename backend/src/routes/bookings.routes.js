import { Router } from 'express';
import * as b from '../controllers/bookingController.js';
import { requireAuth } from '../middleware/auth.js';

const router = Router();
router.use(requireAuth('customer'));

router.post('/', b.createBooking);
router.get('/', b.listBookings);
router.get('/:id', b.getBooking);
router.post('/:id/pay', b.payBooking);
router.post('/:id/cancel', b.cancelBooking);
router.get('/:id/track', b.trackBooking);
router.post('/:id/rating', b.rateBooking);
router.get('/:id/otp', b.getStartOtp);

// Messages. The same two handlers serve the provider app from its own
// router; messageService is what decides who may read a thread.
router.get('/:id/messages', b.getBookingMessages);
router.post('/:id/messages', b.postBookingMessage);

export default router;
