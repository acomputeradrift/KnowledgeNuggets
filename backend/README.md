# Knowledge Nuggets Backend

## Setup

1. Create database and load schema:

```sql
\c knowledge_nuggets
\i db/schema.sql
```

2. Copy env:

```bash
cp .env.example .env
```

3. Install and run:

```bash
npm install
npm run dev
```

4. Start worker:

```bash
npm run worker
```

## Docker (local testing)

1. Copy env:

```bash
cp .env.example .env
```

2. Start stack:

```bash
cd ..
docker compose up --build
```

3. Schema loads automatically on first run (mounted into Postgres init).

## Notes

- MailerSend/APNs/OpenAI are optional. If keys are missing, the server will skip sending.
- Amazon Product Advertising API integration uses a search fallback until signed requests are implemented.
