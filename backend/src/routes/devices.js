import express from 'express';
import { query } from '../db.js';
import { requireAuth } from '../middleware/auth.js';

export const devicesRouter = express.Router();

devicesRouter.post('/register', requireAuth, async (req, res) => {
  const { device_token } = req.body ?? {};
  if (!device_token) {
    return res.status(400).json({ error: 'missing_device_token' });
  }
  await query(
    `INSERT INTO devices (user_id, device_token)
     VALUES ($1, $2)
     ON CONFLICT (device_token) DO UPDATE SET user_id = EXCLUDED.user_id, updated_at = NOW()`,
    [req.user.userId, device_token]
  );
  return res.json({ status: 'registered' });
});

devicesRouter.post('/unregister', requireAuth, async (req, res) => {
  const { device_token } = req.body ?? {};
  if (!device_token) {
    return res.status(400).json({ error: 'missing_device_token' });
  }
  await query('DELETE FROM devices WHERE device_token = $1 AND user_id = $2', [device_token, req.user.userId]);
  return res.json({ status: 'unregistered' });
});
