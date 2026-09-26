/**
 * Endpoints an app may call before anybody has signed in.
 *
 * No `requireAuth`. The shared access key still applies — it is checked one
 * level up, on the whole /api/v1 mount — so this is not open to the internet,
 * it is open to the apps.
 */
import { Router } from 'express';
import * as p from '../controllers/publicController.js';

const router = Router();

router.get('/service-area', p.serviceArea);

export default router;
