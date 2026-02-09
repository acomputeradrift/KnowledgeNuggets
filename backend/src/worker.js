import { Worker } from 'bullmq';
import { config } from './config.js';
import { query } from './db.js';
import { sendEmail } from './services/email.js';
import { sendPush } from './services/push.js';
import { formatLocalDate } from './utils/time.js';

const getRotationIndex = (anchorDate, todayLocal) => {
  const anchor = new Date(anchorDate);
  const today = new Date(`${todayLocal}T00:00:00Z`);
  const msPerDay = 24 * 60 * 60 * 1000;
  const daysSince = Math.floor((today - anchor) / msPerDay);
  return (daysSince % 21) + 1;
};

export const sendNuggetNow = async (userId) => {
  const settingsRes = await query(
    `SELECT us.*, u.email
     FROM user_settings us
     JOIN users u ON u.id = us.user_id
     WHERE us.user_id = $1`,
    [userId]
  );
  if (settingsRes.rowCount === 0) {
    return;
  }
  const settings = settingsRes.rows[0];
  const activeCountRes = await query('SELECT COUNT(*)::int AS count FROM nuggets WHERE user_id = $1 AND active = true', [userId]);
  if (activeCountRes.rows[0].count < 21) {
    console.warn('User has fewer than 21 active nuggets', { userId });
    return;
  }

  if (!settings.anchor_date) {
    await query('UPDATE user_settings SET anchor_date = NOW() WHERE user_id = $1', [userId]);
    settings.anchor_date = new Date().toISOString();
  }

  const todayLocal = formatLocalDate(new Date(), settings.timezone);
  const anchorDate = settings.anchor_date ?? new Date();
  const position = getRotationIndex(anchorDate, todayLocal);

  const nuggetRes = await query(
    'SELECT * FROM nuggets WHERE user_id = $1 AND active = true AND position = $2 LIMIT 1',
    [userId, position]
  );
  if (nuggetRes.rowCount === 0) {
    return;
  }
  const nugget = nuggetRes.rows[0];

  if (settings.send_email) {
    await sendEmail({
      to: settings.email,
      subject: `Your Knowledge Nugget for ${todayLocal}`,
      html: `<p>${nugget.text}</p><p>${nugget.author_name ?? ''} ${nugget.book_title ?? ''}</p>${
        nugget.amazon_link ? `<p><a href="${nugget.amazon_link}">Buy on Amazon</a></p>` : ''
      }`
    }).then(() =>
      query(
        'INSERT INTO send_log (user_id, nugget_id, send_date_local, channel, status) VALUES ($1, $2, $3, $4, $5)',
        [userId, nugget.id, todayLocal, 'email', 'sent']
      )
    ).catch(async (err) => {
      await query(
        'INSERT INTO send_log (user_id, nugget_id, send_date_local, channel, status, error) VALUES ($1, $2, $3, $4, $5, $6)',
        [userId, nugget.id, todayLocal, 'email', 'error', err.message]
      );
    });
  }

  if (settings.send_push) {
    const devices = await query('SELECT device_token FROM devices WHERE user_id = $1', [userId]);
    for (const device of devices.rows) {
      await sendPush({
        deviceToken: device.device_token,
        title: 'Knowledge Nugget',
        body: nugget.text,
        url: nugget.amazon_link
      }).then(() =>
        query(
          'INSERT INTO send_log (user_id, nugget_id, send_date_local, channel, status) VALUES ($1, $2, $3, $4, $5)',
          [userId, nugget.id, todayLocal, 'push', 'sent']
        )
      ).catch(async (err) => {
        await query(
          'INSERT INTO send_log (user_id, nugget_id, send_date_local, channel, status, error) VALUES ($1, $2, $3, $4, $5, $6)',
          [userId, nugget.id, todayLocal, 'push', 'error', err.message]
        );
      });
    }
  }
};

if (process.argv[1] && process.argv[1].endsWith('worker.js')) {
  new Worker('send-queue', async (job) => {
    await sendNuggetNow(job.data.userId);
  }, { connection: { url: config.redisUrl } });
}
