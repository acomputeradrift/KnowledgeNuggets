import { query } from '../db.js';
import { sendQueue } from '../queue.js';
import { formatLocalTime } from '../utils/time.js';

export const scheduleDailySends = async () => {
  const now = new Date();
  const settingsRes = await query(
    `SELECT user_id, send_time_local, timezone, send_push, send_email
     FROM user_settings`
  );

  for (const row of settingsRes.rows) {
    const localTime = formatLocalTime(now, row.timezone);
    if (localTime === row.send_time_local) {
      await sendQueue.add('send-nugget', {
        userId: row.user_id
      });
    }
  }
};
