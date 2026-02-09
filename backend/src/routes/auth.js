import express from 'express';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { v4 as uuid } from 'uuid';
import { config } from '../config.js';
import { query } from '../db.js';
import { sendEmail } from '../services/email.js';

export const authRouter = express.Router();

const signToken = (user) =>
  jwt.sign({ userId: user.id, email: user.email }, config.jwtSecret, { expiresIn: '7d' });

authRouter.post('/register', async (req, res) => {
  const { email, password } = req.body ?? {};
  if (!email || !password) {
    return res.status(400).json({ error: 'missing_fields' });
  }
  const existing = await query('SELECT id FROM users WHERE email = $1', [email]);
  if (existing.rowCount > 0) {
    return res.status(409).json({ error: 'email_in_use' });
  }
  const passwordHash = await bcrypt.hash(password, 10);
  const verifyToken = uuid();
  const result = await query(
    `INSERT INTO users (email, password_hash, email_verification_token)
     VALUES ($1, $2, $3)
     RETURNING id, email`,
    [email, passwordHash, verifyToken]
  );
  const user = result.rows[0];
  await query(
    `INSERT INTO user_settings (user_id, send_time_local, timezone, marketplace, send_push, send_email)
     VALUES ($1, $2, $3, $4, true, true)`,
    [user.id, config.defaultSendTimeLocal, 'UTC', 'US']
  );

  const verifyLink = `${config.baseUrl}/auth/verify?token=${verifyToken}`;
  await sendEmail({
    to: email,
    subject: 'Verify your Knowledge Nuggets account',
    html: `<p>Verify your account:</p><p><a href="${verifyLink}">${verifyLink}</a></p>`
  }).catch(() => null);

  return res.json({ id: user.id, email: user.email });
});

authRouter.post('/verify', async (req, res) => {
  const { token } = req.body ?? {};
  if (!token) {
    return res.status(400).json({ error: 'missing_token' });
  }
  const result = await query(
    `UPDATE users
     SET email_verified_at = NOW(), email_verification_token = NULL
     WHERE email_verification_token = $1
     RETURNING id, email`,
    [token]
  );
  if (result.rowCount === 0) {
    return res.status(400).json({ error: 'invalid_token' });
  }
  return res.json({ status: 'verified' });
});

authRouter.post('/login', async (req, res) => {
  const { email, password } = req.body ?? {};
  if (!email || !password) {
    return res.status(400).json({ error: 'missing_fields' });
  }
  const result = await query(
    'SELECT id, email, password_hash, email_verified_at FROM users WHERE email = $1',
    [email]
  );
  if (result.rowCount === 0) {
    return res.status(401).json({ error: 'invalid_credentials' });
  }
  const user = result.rows[0];
  const match = await bcrypt.compare(password, user.password_hash);
  if (!match) {
    return res.status(401).json({ error: 'invalid_credentials' });
  }
  if (!user.email_verified_at) {
    return res.status(403).json({ error: 'email_not_verified' });
  }
  const token = signToken(user);
  return res.json({ token });
});

authRouter.post('/request-password-reset', async (req, res) => {
  const { email } = req.body ?? {};
  if (!email) {
    return res.status(400).json({ error: 'missing_email' });
  }
  const token = uuid();
  const result = await query(
    `UPDATE users
     SET password_reset_token = $1, password_reset_requested_at = NOW()
     WHERE email = $2
     RETURNING email`,
    [token, email]
  );
  if (result.rowCount > 0) {
    const resetLink = `${config.baseUrl}/auth/reset-password?token=${token}`;
    await sendEmail({
      to: email,
      subject: 'Reset your Knowledge Nuggets password',
      html: `<p>Reset your password:</p><p><a href="${resetLink}">${resetLink}</a></p>`
    }).catch(() => null);
  }
  return res.json({ status: 'ok' });
});

authRouter.post('/reset-password', async (req, res) => {
  const { token, password } = req.body ?? {};
  if (!token || !password) {
    return res.status(400).json({ error: 'missing_fields' });
  }
  const passwordHash = await bcrypt.hash(password, 10);
  const result = await query(
    `UPDATE users
     SET password_hash = $1, password_reset_token = NULL, password_reset_requested_at = NULL
     WHERE password_reset_token = $2
     RETURNING id`,
    [passwordHash, token]
  );
  if (result.rowCount === 0) {
    return res.status(400).json({ error: 'invalid_token' });
  }
  return res.json({ status: 'password_updated' });
});
