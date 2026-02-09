import dotenv from 'dotenv';

dotenv.config();

const required = (key, fallback = undefined) => {
  const value = process.env[key] ?? fallback;
  if (value === undefined) {
    throw new Error(`Missing required env: ${key}`);
  }
  return value;
};

export const config = {
  port: Number(process.env.PORT ?? 4000),
  jwtSecret: required('JWT_SECRET', 'dev-change-me'),
  databaseUrl: required('DATABASE_URL', 'postgres://postgres:postgres@localhost:5432/knowledge_nuggets'),
  redisUrl: required('REDIS_URL', 'redis://localhost:6379'),
  mailersendApiKey: process.env.MAILERSEND_API_KEY ?? '',
  mailersendFromEmail: process.env.MAILERSEND_FROM_EMAIL ?? 'no-reply@example.com',
  apnsKeyId: process.env.APNS_KEY_ID ?? '',
  apnsTeamId: process.env.APNS_TEAM_ID ?? '',
  apnsBundleId: process.env.APNS_BUNDLE_ID ?? 'com.example.KnowledgeNuggets',
  apnsPrivateKey: process.env.APNS_PRIVATE_KEY ?? '',
  amazonPartnerTag: process.env.AMAZON_PARTNER_TAG ?? '',
  amazonAccessKey: process.env.AMAZON_ACCESS_KEY ?? '',
  amazonSecretKey: process.env.AMAZON_SECRET_KEY ?? '',
  openaiApiKey: process.env.OPENAI_API_KEY ?? '',
  enrichmentMode: process.env.ENRICHMENT_MODE ?? 'rules',
  baseUrl: process.env.BASE_URL ?? 'http://localhost:4000',
  defaultSendTimeLocal: process.env.DEFAULT_SEND_TIME_LOCAL ?? '08:00'
};
