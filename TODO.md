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
  - Done: green check, haptics, progress ring, milestones at 1, 7, 14 and 21 with confetti at 21, Add Another, and the note ("Added to the end of your rotation." or "Added as Inactive. Your rotation is full."). Not yet felt on the phone: haptics, Reduce Motion and VoiceOver.
- [x] ~~**Three states: Active, New and Inactive.**~~ Dropped: nothing is ever pulled into the rotation automatically.
- [ ] **Let the user choose the rotation size instead of a fixed 21.** Apple's limit (about 64 queued notifications) doesn't cap the number of nuggets. Open questions: a setting with a default of 21 or no cap at all, and whether to set a maximum.

## v2 ideas
- [ ] **Search Nuggets:** browse and add nuggets shared by the community. This needs a backend, so it's out of scope for the local-only v1.
