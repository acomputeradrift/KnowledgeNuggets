# KnowledgeNuggets TODO

## 2026-11-13

### In progress
- [x] **Today page didn't update to the new day.** The Today screen still showed yesterday's nugget the next morning. Fixed: it now refreshes at midnight, on clock or time zone changes, and when the app comes back to the front.
- [x] **Add Lyrics as a kind of nugget.** It sits alongside Book, Movie, Show, Podcast, Quote, Affirmation and Other. Done: Artist and Song fields, no lookup.

- [x] **The delete confirmation looked different from the app's other popups and pointed at the wrong nugget.** Fixed: it's now a centered alert showing a preview of the nugget's text.

### To discuss first
- [ ] **Make adding a nugget exciting.**
  - Haptics and a prominent green check.
  - Encourage people to fill all 21 spots at the start.
  - The same green check and text whichever list the new nugget joins.
  - A small note at the bottom saying where the nugget went in line.
  - Decided: the note only ever talks about Active and Inactive, never "New". When the rotation is full: "Added as Inactive. It joins the rotation when a spot opens."
  - Decided: the screen stays with Add Another / Done until the rotation is full, then closes by itself. Milestones at 1, 7, 14 and 21, with confetti at 21. iOS green check. No starter nuggets.
  - In progress (agent dispatched).
- [ ] **Three states: Active, New and Inactive.**
  - Decided: "New" is internal only. People see just Active and Inactive, with Inactive ordered by the algorithm (queued new nuggets first).
  - A new nugget goes to the bottom of the New list.
  - A nugget made inactive goes to the bottom of the whole list. When that happens, the oldest New nugget moves to the bottom of the Active list.
  - If New is empty, the oldest Inactive nugget moves to the bottom of Active instead.

## v2 ideas
- [ ] **Search Nuggets:** browse and add nuggets shared by the community. This needs a backend, so it's out of scope for the local-only v1.
