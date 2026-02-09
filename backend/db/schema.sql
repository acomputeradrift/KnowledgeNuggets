CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  email_verified_at TIMESTAMP NULL,
  email_verification_token TEXT NULL,
  password_reset_token TEXT NULL,
  password_reset_requested_at TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_settings (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  send_time_local TEXT NOT NULL,
  timezone TEXT NOT NULL,
  marketplace TEXT NOT NULL DEFAULT 'US',
  send_push BOOLEAN NOT NULL DEFAULT true,
  send_email BOOLEAN NOT NULL DEFAULT true,
  anchor_date TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS nuggets (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  text TEXT NOT NULL,
  author_name TEXT NULL,
  book_title TEXT NULL,
  amazon_link TEXT NULL,
  category TEXT NULL,
  position INT NULL,
  active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS devices (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_token TEXT UNIQUE NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS send_log (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  nugget_id UUID NOT NULL REFERENCES nuggets(id) ON DELETE CASCADE,
  send_date_local TEXT NOT NULL,
  channel TEXT NOT NULL,
  status TEXT NOT NULL,
  error TEXT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS enrichment_log (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  nugget_id UUID NOT NULL REFERENCES nuggets(id) ON DELETE CASCADE,
  input TEXT NOT NULL,
  provider TEXT NOT NULL,
  result TEXT NULL,
  status TEXT NOT NULL,
  error TEXT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS amazon_lookup_log (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  nugget_id UUID NOT NULL REFERENCES nuggets(id) ON DELETE CASCADE,
  query TEXT NOT NULL,
  asin TEXT NULL,
  marketplace TEXT NOT NULL,
  status TEXT NOT NULL,
  error TEXT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
