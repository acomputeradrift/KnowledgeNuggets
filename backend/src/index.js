import express from 'express';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import { authRouter } from './routes/auth.js';
import { settingsRouter } from './routes/settings.js';
import { nuggetsRouter } from './routes/nuggets.js';
import { devicesRouter } from './routes/devices.js';
import { internalRouter } from './routes/internal.js';
import { config } from './config.js';

const app = express();
app.use(cors());
app.use(express.json());
app.use(rateLimit({ windowMs: 60 * 1000, max: 120 }));

app.get('/health', (req, res) => res.json({ status: 'ok' }));
app.use('/auth', authRouter);
app.use('/settings', settingsRouter);
app.use('/nuggets', nuggetsRouter);
app.use('/devices', devicesRouter);
app.use('/internal', internalRouter);

app.listen(config.port, () => {
  console.log(`API listening on ${config.port}`);
});
