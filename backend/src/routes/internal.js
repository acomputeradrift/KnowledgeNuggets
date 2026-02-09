import express from 'express';
import { scheduleDailySends } from '../services/scheduler.js';
import { sendNuggetNow } from '../worker.js';

export const internalRouter = express.Router();

internalRouter.post('/schedule-daily', async (req, res) => {
  await scheduleDailySends();
  return res.json({ status: 'scheduled' });
});

internalRouter.post('/send-nugget', async (req, res) => {
  const { userId } = req.body ?? {};
  if (!userId) {
    return res.status(400).json({ error: 'missing_userId' });
  }
  await sendNuggetNow(userId);
  return res.json({ status: 'sent' });
});
