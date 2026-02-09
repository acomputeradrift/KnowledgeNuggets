import fetch from 'node-fetch';
import { config } from '../config.js';
import { suggestCategoryRules } from './category.js';
import { lookupOpenLibrary } from './openlibrary.js';

const OPENAI_URL = 'https://api.openai.com/v1/responses';

const callOpenAI = async (payload) => {
  if (!config.openaiApiKey) {
    return null;
  }
  const res = await fetch(OPENAI_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${config.openaiApiKey}`
    },
    body: JSON.stringify(payload)
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`OpenAI error: ${res.status} ${body}`);
  }
  return res.json();
};

export const enrichNugget = async ({ text, authorName, bookTitle }) => {
  const rules = suggestCategoryRules([text, authorName, bookTitle].filter(Boolean).join(' '));
  if (config.enrichmentMode === 'rules') {
    return {
      category: rules.category,
      provider: 'rules',
      confidence: rules.confidence,
      normalizedAuthor: authorName ?? null,
      normalizedBookTitle: bookTitle ?? null
    };
  }

  const prompt = `Given this quote and metadata, suggest a single category and normalize author/book.\nQuote: ${text ?? ''}\nAuthor: ${authorName ?? ''}\nBook: ${bookTitle ?? ''}\nReturn JSON: {"category":"...","author":"...","book":"..."}`;
  const response = await callOpenAI({
    model: 'gpt-4.1-mini',
    input: [{ role: 'user', content: prompt }],
    max_output_tokens: 150
  });

  const content = response?.output?.[0]?.content?.[0]?.text ?? '';
  let parsed = null;
  try {
    parsed = JSON.parse(content);
  } catch (err) {
    parsed = null;
  }

  if (!parsed) {
    return {
      category: rules.category,
      provider: 'rules',
      confidence: rules.confidence,
      normalizedAuthor: authorName ?? null,
      normalizedBookTitle: bookTitle ?? null
    };
  }

  return {
    category: parsed.category ?? rules.category,
    provider: 'openai',
    confidence: 0.7,
    normalizedAuthor: parsed.author ?? authorName ?? null,
    normalizedBookTitle: parsed.book ?? bookTitle ?? null
  };
};

export const fillMissingMetadata = async ({ text, authorName, bookTitle }) => {
  const inputAuthor = authorName?.trim() || null;
  const inputBook = bookTitle?.trim() || null;
  let author = inputAuthor;
  let book = inputBook;

  const authorMissing = !author || author === 'Unknown';
  const bookMissing = !book || book === 'Unknown';
  const needsAuthor = !!book && authorMissing;
  const needsBook = !!author && bookMissing;

  console.info('Metadata fill input', { author, book, needsAuthor, needsBook });

  if (needsAuthor || needsBook) {
    console.info('Calling OpenLibrary for metadata fill');
    const lookup = await lookupOpenLibrary({
      author: authorMissing ? null : author,
      book: bookMissing ? null : book
    });
    if (authorMissing) {
      author = lookup.author ?? author;
    }
    if (bookMissing) {
      book = lookup.book ?? book;
    }
    console.info('OpenLibrary result', { author, book });
  } else {
    console.info('Skipping OpenLibrary (metadata complete)', { author, book });
  }

  if (book && !author) {
    author = 'Unknown';
  }
  if (author && !book) {
    book = 'Unknown';
  }

  return { author, book };
};
