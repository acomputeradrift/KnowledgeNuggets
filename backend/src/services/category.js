const RULES = [
  { category: 'Leadership', keywords: ['leadership', 'leader', 'manage', 'management'] },
  { category: 'Productivity', keywords: ['productivity', 'focus', 'habit', 'routine'] },
  { category: 'Mindset', keywords: ['mindset', 'belief', 'attitude', 'resilience'] },
  { category: 'Business', keywords: ['business', 'strategy', 'market', 'customer'] },
  { category: 'Health', keywords: ['health', 'sleep', 'exercise', 'nutrition'] },
  { category: 'Creativity', keywords: ['creativity', 'creative', 'idea', 'imagination'] }
];

export const suggestCategoryRules = (input) => {
  if (!input) {
    return { category: null, confidence: 0 };
  }
  const text = input.toLowerCase();
  for (const rule of RULES) {
    for (const keyword of rule.keywords) {
      if (text.includes(keyword)) {
        return { category: rule.category, confidence: 0.6 };
      }
    }
  }
  return { category: null, confidence: 0 };
};
