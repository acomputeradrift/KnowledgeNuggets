import apn from 'apn';
import { config } from '../config.js';

let provider = null;

const getProvider = () => {
  if (provider) return provider;
  if (!config.apnsKeyId || !config.apnsTeamId || !config.apnsPrivateKey) {
    return null;
  }
  provider = new apn.Provider({
    token: {
      key: config.apnsPrivateKey,
      keyId: config.apnsKeyId,
      teamId: config.apnsTeamId
    },
    production: false
  });
  return provider;
};

export const sendPush = async ({ deviceToken, title, body, url }) => {
  const apnProvider = getProvider();
  if (!apnProvider) {
    console.warn('APNs not configured. Skipping push to', deviceToken);
    return { status: 'skipped' };
  }

  const notification = new apn.Notification();
  notification.topic = config.apnsBundleId;
  notification.alert = { title, body };
  if (url) {
    notification.payload = { url };
  }
  notification.sound = 'default';

  const result = await apnProvider.send(notification, deviceToken);
  if (result.failed && result.failed.length > 0) {
    const failure = result.failed[0];
    const message = failure?.response?.reason ?? failure?.error?.message ?? 'apns_error';
    throw new Error(message);
  }
  return { status: 'sent' };
};
