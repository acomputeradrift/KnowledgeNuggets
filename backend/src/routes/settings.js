import express from 'express';
import { query } from '../db.js';
import { requireAuth } from '../middleware/auth.js';
import { config } from '../config.js';

export const settingsRouter = express.Router();

const ensureSettings = async (userId) => {
  const existing = await query('SELECT user_id FROM user_settings WHERE user_id = $1', [userId]);
  if (existing.rowCount === 0) {
    await query(
      `INSERT INTO user_settings (user_id, send_time_local, timezone, marketplace, send_push, send_email)
       VALUES ($1, $2, $3, $4, true, true)`,
      [userId, config.defaultSendTimeLocal, 'UTC', 'US']
    );
  }
};

settingsRouter.get('/', requireAuth, async (req, res) => {
  await ensureSettings(req.user.userId);
  const result = await query('SELECT * FROM user_settings WHERE user_id = $1', [req.user.userId]);
  return res.json(result.rows[0]);
});

settingsRouter.put('/', requireAuth, async (req, res) => {
  await ensureSettings(req.user.userId);
  const { send_time_local, timezone, marketplace, send_push, send_email } = req.body ?? {};
  const result = await query(
    `UPDATE user_settings
     SET send_time_local = COALESCE($1, send_time_local),
         timezone = COALESCE($2, timezone),
         marketplace = COALESCE($3, marketplace),
         send_push = COALESCE($4, send_push),
         send_email = COALESCE($5, send_email)
     WHERE user_id = $6
     RETURNING *`,
    [send_time_local, timezone, marketplace, send_push, send_email, req.user.userId]
  );
  return res.json(result.rows[0]);
});
