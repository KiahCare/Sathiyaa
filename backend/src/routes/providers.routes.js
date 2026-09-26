import { Router } from 'express';
import * as pub from '../controllers/providerPublicController.js';
import * as self from '../controllers/providerSelfController.js';
import { requireAuth, optionalAuth } from '../middleware/auth.js';
import * as booking from '../controllers/bookingController.js';

const router = Router();

// --- Public / customer-facing search (order matters: before /:id) ---
router.get('/search', optionalAuth, pub.searchProviders);

// --- Provider self-service (order matters: before /:id) ---
router.get('/me', requireAuth('provider'), self.getMe);
router.put('/me', requireAuth('provider'), self.updateMe);
router.post('/me/registration-payment', requireAuth('provider'), self.registrationPayment);
router.put('/me/work-hours', requireAuth('provider'), self.putWorkHours);
router.get('/me/calendar-blocks', requireAuth('provider'), self.listCalendarBlocks);
router.post('/me/calendar-blocks', requireAuth('provider'), self.addCalendarBlock);
router.delete('/me/calendar-blocks/:id', requireAuth('provider'), self.deleteCalendarBlock);
router.patch('/me/location', requireAuth('provider'), self.patchLocation);
router.put('/me/signup-place', requireAuth('provider'), self.putSignupPlace);

router.get('/me/requests', requireAuth('provider'), self.listMyRequests);
router.post('/me/requests/:bookingId/accept', requireAuth('provider'), self.acceptRequest);
router.post('/me/requests/:bookingId/reject', requireAuth('provider'), self.rejectRequest);

router.post('/me/bookings/:id/transfer', requireAuth('provider'), self.transferBooking);
router.post('/me/transfers/:id/respond', requireAuth('provider'), self.respondTransfer);
router.post('/me/bookings/:id/start', requireAuth('provider'), self.startService);
router.post('/me/bookings/:id/verify-start-otp', requireAuth('provider'), self.verifyStartOtp);
router.post('/me/bookings/:id/end', requireAuth('provider'), self.endService);
router.post('/me/bookings/:id/running-late', requireAuth('provider'), self.runningLate);
router.get('/me/bookings/:id/directions', requireAuth('provider'), self.getDirectionsToCustomer);
router.post('/me/bookings/:id/payments', requireAuth('provider'), self.recordPayment);
router.post('/me/bookings/:id/payment-reminder', requireAuth('provider'), self.sendPaymentReminder);
router.post('/me/bookings/:id/rate-customer', requireAuth('provider'), self.rateCustomer);

router.get('/me/appointments', requireAuth('provider'), self.listAppointments);
router.get('/me/dashboard', requireAuth('provider'), self.getDashboard);
router.get('/me/schedule-overview', requireAuth('provider'), self.getScheduleOverview);
router.get('/me/time-bank', requireAuth('provider'), self.getTimeBank);

router.get('/employees', requireAuth('provider'), self.listEmployees);
router.post('/employees', requireAuth('provider'), self.addEmployee);
router.put('/employees/:id', requireAuth('provider'), self.updateEmployee);
router.patch('/employees/:id/status', requireAuth('provider'), self.setEmployeeStatus);

router.post('/me/bookings/:id/allocate', requireAuth('provider'), self.allocateEmployee);
router.post('/me/bookings/:id/reallocate', requireAuth('provider'), self.reallocateEmployee);
router.post('/me/bookings/:id/org-cancel', requireAuth('provider'), self.orgCancelBooking);
router.get('/me/utilization', requireAuth('provider'), self.getUtilization);

// Messages. The same two handlers the customer router uses — who is asking
// comes from the token, and messageService decides whether they are on the
// booking. One implementation means the two sides cannot drift apart, which is
// how one of them ends up able to read a thread it should not.
router.get('/me/bookings/:id/messages', requireAuth('provider'), booking.getBookingMessages);
router.post('/me/bookings/:id/messages', requireAuth('provider'), booking.postBookingMessage);

// --- Public profile (must be registered last: catches /:id) ---
router.get('/:id', pub.getProviderPublicProfile);

export default router;
