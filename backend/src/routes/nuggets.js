import express from 'express';
import { query, pool } from '../db.js';
import { requireAuth } from '../middleware/auth.js';
import { enrichNugget, fillMissingMetadata } from '../services/enrichment.js';
import { lookupAmazonLink } from '../services/amazon.js';

export const nuggetsRouter = express.Router();

const countActive = async (userId) => {
  const res = await query('SELECT COUNT(*)::int AS count FROM nuggets WHERE user_id = $1 AND active = true', [userId]);
  return res.rows[0].count;
};

const resetAnchorIfReady = async (userId) => {
  const activeCount = await countActive(userId);
  if (activeCount === 21) {
    await query('UPDATE user_settings SET anchor_date = NOW() WHERE user_id = $1', [userId]);
  }
};

nuggetsRouter.get('/', requireAuth, async (req, res) => {
  const result = await query('SELECT * FROM nuggets WHERE user_id = $1 ORDER BY position ASC', [req.user.userId]);
  return res.json(result.rows);
});

nuggetsRouter.post('/', requireAuth, async (req, res) => {
  const { text, author_name, book_title, category, active } = req.body ?? {};
  if (!text) {
    return res.status(400).json({ error: 'missing_text' });
  }
  const settingsRes = await query('SELECT marketplace FROM user_settings WHERE user_id = $1', [req.user.userId]);
  const marketplace = settingsRes.rows[0]?.marketplace ?? 'US';
  const activeCount = await countActive(req.user.userId);
  if (active && activeCount >= 21) {
    return res.status(400).json({ error: 'active_limit_reached' });
  }
  const enrichment = await enrichNugget({ text, authorName: author_name, bookTitle: book_title });
  const finalCategory = category ?? enrichment.category;
  const normalizedAuthor = enrichment.normalizedAuthor ?? author_name ?? null;
  const normalizedBookTitle = enrichment.normalizedBookTitle ?? book_title ?? null;
  const filled = await fillMissingMetadata({ text, authorName: normalizedAuthor, bookTitle: normalizedBookTitle });
  const finalAuthor = filled.author;
  const finalBookTitle = filled.book;
  const canGenerateAmazon =
    !!finalAuthor &&
    !!finalBookTitle &&
    finalAuthor !== 'Unknown' &&
    finalBookTitle !== 'Unknown';
  const amazon = canGenerateAmazon
    ? await lookupAmazonLink({ bookTitle: finalBookTitle, authorName: finalAuthor, marketplace })
    : { url: null };
  if (!finalAuthor || !finalBookTitle || finalAuthor === 'Unknown' || finalBookTitle === 'Unknown') {
    console.info('Nugget metadata incomplete after enrichment', {
      userId: req.user.userId,
      author: finalAuthor,
      book: finalBookTitle
    });
  }
  if (!amazon?.url) {
    console.info('Amazon link not generated', {
      userId: req.user.userId,
      author: finalAuthor,
      book: finalBookTitle
    });
  }

  const position = active ? activeCount + 1 : null;
  const result = await query(
    `INSERT INTO nuggets (user_id, text, author_name, book_title, category, amazon_link, active, position)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
     RETURNING *`,
    [
      req.user.userId,
      text,
      finalAuthor ?? null,
      finalBookTitle ?? null,
      finalCategory ?? null,
      amazon.url,
      active ?? true,
      position
    ]
  );

  await resetAnchorIfReady(req.user.userId);
  return res.json(result.rows[0]);
});

nuggetsRouter.put('/:id', requireAuth, async (req, res) => {
  const { id } = req.params;
  const { text, author_name, book_title, category, active } = req.body ?? {};
  if (text !== undefined && text.trim().length === 0) {
    return res.status(400).json({ error: 'missing_text' });
  }
  const existing = await query('SELECT * FROM nuggets WHERE id = $1 AND user_id = $2', [id, req.user.userId]);
  if (existing.rowCount === 0) {
    return res.status(404).json({ error: 'not_found' });
  }
  const settingsRes = await query('SELECT marketplace FROM user_settings WHERE user_id = $1', [req.user.userId]);
  const marketplace = settingsRes.rows[0]?.marketplace ?? 'US';
  const current = existing.rows[0];
  if (active && !current.active) {
    const activeCount = await countActive(req.user.userId);
    if (activeCount >= 21) {
      return res.status(400).json({ error: 'active_limit_reached' });
    }
  }

  const hasAuthorField = author_name !== undefined;
  const hasBookField = book_title !== undefined;
  const hasCategoryField = category !== undefined;
  const normalizedAuthorInput = author_name === '' ? null : author_name;
  const normalizedBookInput = book_title === '' ? null : book_title;
  const normalizedCategoryInput = category === '' ? null : category;
  const enrichedAuthor = hasAuthorField ? normalizedAuthorInput : current.author_name;
  const enrichedBookTitle = hasBookField ? normalizedBookInput : current.book_title;
  const enrichment = await enrichNugget({ text: text ?? current.text, authorName: enrichedAuthor, bookTitle: enrichedBookTitle });
  const finalCategory = hasCategoryField ? normalizedCategoryInput ?? enrichment.category : enrichment.category ?? current.category;
  const normalizedAuthor = enrichment.normalizedAuthor ?? enrichedAuthor ?? null;
  const normalizedBookTitle = enrichment.normalizedBookTitle ?? enrichedBookTitle ?? null;
  const filled = await fillMissingMetadata({ text: text ?? current.text, authorName: normalizedAuthor, bookTitle: normalizedBookTitle });
  const finalAuthor = filled.author;
  const finalBookTitle = filled.book;
  const canGenerateAmazon =
    !!finalAuthor &&
    !!finalBookTitle &&
    finalAuthor !== 'Unknown' &&
    finalBookTitle !== 'Unknown';
  const amazon = canGenerateAmazon
    ? await lookupAmazonLink({ bookTitle: finalBookTitle, authorName: finalAuthor, marketplace })
    : { url: null };
  if (!finalAuthor || !finalBookTitle || finalAuthor === 'Unknown' || finalBookTitle === 'Unknown') {
    console.info('Nugget metadata incomplete after enrichment', {
      userId: req.user.userId,
      author: finalAuthor,
      book: finalBookTitle
    });
  }
  if (!amazon?.url) {
    console.info('Amazon link not generated', {
      userId: req.user.userId,
      author: finalAuthor,
      book: finalBookTitle
    });
  }

  const result = await query(
    `UPDATE nuggets
     SET text = COALESCE($1, text),
         author_name = COALESCE($2, author_name),
         book_title = COALESCE($3, book_title),
         category = COALESCE($4, category),
         amazon_link = COALESCE($5, amazon_link),
         active = COALESCE($6, active)
     WHERE id = $7 AND user_id = $8
     RETURNING *`,
    [text, finalAuthor, finalBookTitle, finalCategory, amazon.url, active, id, req.user.userId]
  );

  await resetAnchorIfReady(req.user.userId);
  return res.json(result.rows[0]);
});

nuggetsRouter.delete('/:id', requireAuth, async (req, res) => {
  const { id } = req.params;
  await query('DELETE FROM nuggets WHERE id = $1 AND user_id = $2', [id, req.user.userId]);
  await resetAnchorIfReady(req.user.userId);
  return res.json({ status: 'deleted' });
});

nuggetsRouter.post('/reorder', requireAuth, async (req, res) => {
  const { positions } = req.body ?? {};
  if (!Array.isArray(positions)) {
    return res.status(400).json({ error: 'invalid_positions' });
  }
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    for (const item of positions) {
      if (!item.id || !item.position) continue;
      await client.query(
        'UPDATE nuggets SET position = $1 WHERE id = $2 AND user_id = $3',
        [item.position, item.id, req.user.userId]
      );
    }
    await client.query('COMMIT');
    await resetAnchorIfReady(req.user.userId);
    return res.json({ status: 'ok' });
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
});
