import { Router } from 'express';
import * as auth from '../controllers/authController.js';

const router = Router();

router.post('/customer/register', auth.customerRegister);
router.post('/customer/verify-otp', auth.customerVerifyOtp);
router.post('/customer/login', auth.customerLogin);
router.post('/customer/reset-otp', auth.customerResetOtp);

router.post('/provider/register', auth.providerRegister);
router.post('/provider/login', auth.providerLogin);
router.post('/provider/reset-pin-otp', auth.providerResetPinOtp);

router.post('/business-agent/login', auth.businessAgentLogin);
router.post('/business-agent/reset-otp', auth.businessAgentResetOtp);

router.post('/admin/login', auth.adminLogin);

export default router;
