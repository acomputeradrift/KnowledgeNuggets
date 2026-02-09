import fetch from 'node-fetch';
import { config } from '../config.js';

export const sendEmail = async ({ to, subject, html }) => {
  if (!config.sendgridApiKey) {
    console.warn('SendGrid not configured. Skipping email to', to);
    return { status: 'skipped' };
  }

  const res = await fetch('https://api.sendgrid.com/v3/mail/send', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${config.sendgridApiKey}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      personalizations: [{ to: [{ email: to }] }],
      from: { email: config.sendgridFromEmail },
      subject,
      content: [{ type: 'text/html', value: html }]
    })
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`SendGrid error: ${res.status} ${body}`);
  }

  return { status: 'sent' };
};
