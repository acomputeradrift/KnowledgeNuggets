# KnowledgeNuggets TODO

## 2026-11-13

### In progress
- [x] **Today page didn't update to the new day.** The Today screen still showed yesterday's nugget the next morning. Fixed: it now refreshes at midnight, on clock or time zone changes, and when the app comes back to the front.
- [x] **Add Lyrics as a kind of nugget.** It sits alongside Book, Movie, Show, Podcast, Quote, Affirmation and Other. Done: Artist and Song fields, no lookup.

### To discuss first
- [ ] **Make adding a nugget exciting.**
  - Haptics and a prominent green check.
  - Encourage people to fill all 21 spots at the start.
  - The same green check and text whichever list the new nugget joins.
  - A small note at the bottom saying where the nugget went in line.
- [ ] **Three states: Active, New and Inactive.**
  - A new nugget goes to the bottom of the New list.
  - A nugget made inactive goes to the bottom of the whole list. When that happens, the oldest New nugget moves to the bottom of the Active list.
  - If New is empty, the oldest Inactive nugget moves to the bottom of Active instead.
