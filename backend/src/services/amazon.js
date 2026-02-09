import { config } from '../config.js';

const MARKETPLACE_MAP = {
  US: 'www.amazon.com',
  UK: 'www.amazon.co.uk',
  CA: 'www.amazon.ca',
  AU: 'www.amazon.com.au',
  DE: 'www.amazon.de'
};

const buildSearchUrl = ({ bookTitle, authorName, marketplace }) => {
  const host = MARKETPLACE_MAP[marketplace] ?? MARKETPLACE_MAP.US;
  const query = [bookTitle, authorName].filter(Boolean).join(' ');
  const params = new URLSearchParams({ k: query });
  if (config.amazonPartnerTag) {
    params.set('tag', config.amazonPartnerTag);
  }
  return `https://${host}/s?${params.toString()}`;
};

export const lookupAmazonLink = async ({ bookTitle, authorName, marketplace = 'US' }) => {
  if (!bookTitle) {
    return { url: null, asin: null, source: 'none' };
  }

  if (!config.amazonAccessKey || !config.amazonSecretKey || !config.amazonPartnerTag) {
    return {
      url: buildSearchUrl({ bookTitle, authorName, marketplace }),
      asin: null,
      source: 'search_fallback'
    };
  }

  // TODO: Implement Amazon Product Advertising API signed request.
  // For now, use search fallback to keep affiliate link populated.
  return {
    url: buildSearchUrl({ bookTitle, authorName, marketplace }),
    asin: null,
    source: 'search_fallback'
  };
};
