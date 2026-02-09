import fetch from 'node-fetch';
import { config } from '../config.js';

export const sendEmail = async ({ to, subject, html }) => {
  if (!config.mailersendApiKey) {
    console.warn('MailerSend not configured. Skipping email to', to);
    return { status: 'skipped' };
  }

  const res = await fetch('https://api.mailersend.com/v1/email', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${config.mailersendApiKey}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      from: { email: config.mailersendFromEmail },
      to: [{ email: to }],
      subject,
      html
    })
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`MailerSend error: ${res.status} ${body}`);
  }

  return { status: 'sent' };
};
