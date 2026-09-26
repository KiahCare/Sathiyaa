import { Router } from 'express';
import * as c from '../controllers/customerController.js';
import { requireAuth } from '../middleware/auth.js';

const router = Router();
router.use(requireAuth('customer'));

router.get('/me', c.getMe);
router.put('/me', c.updateMe);
router.put('/me/addresses', c.putAddresses);
router.post('/me/accept-terms', c.acceptTerms);

// The business partner's reference code, validated against business_agents
// rather than by counting characters in the app.
router.post('/me/referral', c.applyReferralCode);
router.delete('/me/referral', c.clearReferralCode);

// Where this customer registered from. Sent once, straight after sign-up.
router.put('/me/signup-place', c.putSignupPlace);

router.get('/me/linked-providers', c.listLinkedProviders);
router.post('/me/linked-providers', c.addLinkedProvider);
router.delete('/me/linked-providers/:providerId', c.deleteLinkedProvider);

router.get('/me/vitals', c.listVitals);
router.post('/me/vitals', c.addVital);
router.put('/me/vitals/:id', c.updateVital);
router.delete('/me/vitals/:id', c.deleteVital);

router.get('/me/medications', c.listMedications);
router.post('/me/medications', c.addMedication);
router.put('/me/medications/:id', c.updateMedication);
router.delete('/me/medications/:id', c.deleteMedication);

router.get('/me/surgeries', c.listSurgeries);
router.post('/me/surgeries', c.addSurgery);
router.put('/me/surgeries/:id', c.updateSurgery);
router.delete('/me/surgeries/:id', c.deleteSurgery);

router.get('/me/allergies', c.listAllergies);
router.post('/me/allergies', c.addAllergy);
router.put('/me/allergies/:id', c.updateAllergy);
router.delete('/me/allergies/:id', c.deleteAllergy);

router.get('/me/insurance', c.listInsurance);
router.post('/me/insurance', c.addInsurance);

// Emergency. Above the family routes because it is the one somebody reaches
// for in a hurry, and because it reads the family list rather than editing it.
router.post('/me/sos', c.raiseSos);
router.get('/me/sos', c.listMySos);

router.get('/me/family', c.listFamily);
router.post('/me/family', c.addFamily);
router.put('/me/family/:id', c.updateFamily);
router.delete('/me/family/:id', c.deleteFamily);

router.post('/me/registration-payment', c.registrationPayment);

export default router;
