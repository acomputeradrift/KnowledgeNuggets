import { Queue } from 'bullmq';
import { config } from './config.js';

export const sendQueue = new Queue('send-queue', {
  connection: { url: config.redisUrl }
});
