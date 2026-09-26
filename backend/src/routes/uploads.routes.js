import { Router } from 'express';
import multer from 'multer';

import * as uploads from '../controllers/uploadController.js';
import { requireAuth } from '../middleware/auth.js';

// In memory, then written by the controller: files are small, and this keeps
// the "where does it get stored" decision in one place.
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: uploads.MAX_UPLOAD_BYTES, files: 1 },
});

const router = Router();

// Any signed-in role may upload; what the URL is then attached to is guarded
// by the endpoint that stores it (a customer can only set their own photo).
router.post(
  '/',
  requireAuth('customer', 'provider', 'business_agent', 'admin'),
  upload.single('file'),
  uploads.uploadFile
);

export default router;
