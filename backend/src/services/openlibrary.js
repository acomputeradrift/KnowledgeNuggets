import fetch from 'node-fetch';

const OPEN_LIBRARY_SEARCH = 'https://openlibrary.org/search.json';

const normalize = (value) => {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
};

const normalizeTitle = (value) => {
  const trimmed = normalize(value);
  if (!trimmed) return null;
  return trimmed
    .replace(/[“”]/g, '"')
    .replace(/[‘’]/g, "'")
    .replace(/[–—]/g, '-')
    .replace(/["']/g, '')
    .replace(/\s+/g, ' ')
    .trim();
};

const pickBestDoc = (docs) => {
  if (!Array.isArray(docs) || docs.length === 0) return null;
  return docs[0];
};

const normalizeAuthor = (value) => normalize(value)?.toLowerCase() ?? null;

export const lookupOpenLibrary = async ({ author, book }) => {
  const authorName = normalize(author);
  const bookTitle = normalizeTitle(book);

  if (!authorName && !bookTitle) {
    return { author: null, book: null };
  }

  const params = new URLSearchParams({ limit: '5', fields: 'title,author_name' });
  if (bookTitle) params.set('title', bookTitle);
  if (authorName) params.set('author', authorName);

  let url = `${OPEN_LIBRARY_SEARCH}?${params.toString()}`;
  console.info('OpenLibrary request', { url });
  let res = await fetch(url);
  if (!res.ok) {
    console.warn('OpenLibrary lookup failed', { status: res.status, url });
    return { author: authorName, book: bookTitle };
  }
  let data = await res.json();
  let doc = pickBestDoc(data?.docs);
  if (!doc && bookTitle) {
    const fallbackParams = new URLSearchParams({
      q: bookTitle,
      limit: '5',
      fields: 'title,author_name'
    });
    url = `${OPEN_LIBRARY_SEARCH}?${fallbackParams.toString()}`;
    console.info('OpenLibrary fallback request', { url });
    res = await fetch(url);
    if (res.ok) {
      data = await res.json();
      doc = pickBestDoc(data?.docs);
    } else {
      console.warn('OpenLibrary fallback lookup failed', { status: res.status, url });
    }
  }
  if (!doc) {
    console.info('OpenLibrary lookup found no match', { author: authorName, book: bookTitle });
    return { author: authorName, book: bookTitle };
  }
  const docTitle = normalizeTitle(doc?.title);
  const docAuthor = normalize(doc?.author_name?.[0]);
  const titleMatches = bookTitle ? (docTitle && normalizeTitle(bookTitle) === docTitle) : true;
  const authorMatches = authorName
    ? normalizeAuthor(authorName) === normalizeAuthor(docAuthor)
    : true;

  if (!titleMatches || !authorMatches) {
    console.info('OpenLibrary match rejected (not exact)', {
      inputTitle: bookTitle,
      inputAuthor: authorName,
      docTitle,
      docAuthor
    });
    return { author: authorName, book: bookTitle };
  }

  console.info('OpenLibrary match accepted', { title: docTitle, author: docAuthor });
  const resolvedBook = docTitle ?? bookTitle;
  const resolvedAuthor = docAuthor ?? authorName;

  return { author: resolvedAuthor, book: resolvedBook };
};
