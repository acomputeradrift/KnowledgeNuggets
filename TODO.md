# KnowledgeNuggets TODO

## Check on the phone
These are built and covered by tests, but nobody has tried them on the iPhone yet.
- [ ] The haptic and the ding when you save a nugget.
- [ ] The Active | Queued | Paused pill, including Active greyed out when all 21 spots are taken.
- [ ] Layout C: the screen you see after saving a nugget as Queued or Paused yourself.
- [ ] "You already have this nugget." when you type one you already have.
- [ ] "Pause at least one to make room" when you drag into a full Active.
- [ ] Dragging a nugget to the very top of Active.

## v2 ideas
- [ ] **Search Nuggets:** browse and add nuggets shared by the community. This needs a backend, so it's out of scope for the local-only v1.

## Done

### 2026-11-23
- [x] **Duplicates are blocked.** The match ignores capital letters, spacing, quotation marks and end punctuation. Import skips duplicates.
- [x] **Every nugget is shown in curly quotes,** affirmations included. Quotes you type yourself aren't doubled up.
- [x] **Three states: Active, Queued and Paused** ("Inactive" is now Paused).
  - A new nugget goes to the bottom of Queued when Active is full.
  - Paused is for nuggets you don't want to see any time soon but don't want to delete.
  - Nuggets can be dragged between all three sections. Dragging into a full Active shows "Pause at least one to make room."
  - Nothing moves into Active on its own.
  - Swipes look the same as before: Active nuggets get "Pause"; Queued and Paused nuggets get "Activate".
  - The add and edit forms use an Active | Queued | Paused pill.
- [x] **The save screen has two layouts, and neither closes on its own.**
  - A progress ring while you fill the 21 active spots.
  - An info box when the nugget goes to Queued or Paused. "Go to Nuggets" appears when Active is full.
- [x] **The Nuggets list has rounded corners at the top and the bottom.**
- [x] **Fixed git:** your name, email and GitHub sign-in are set.

### 2026-11-18 to 2026-11-19
- [x] **Notifications:** the bold top line is who it's by and where it's from, and the full quote gets every line below it. The "Knowledge Nugget" title is gone.
- [x] **Settings → About** shows the version and build code, so you can tell which build is on the phone.

### 2026-11-13
- [x] **The Today page moves on to the new day:** at midnight, on clock or time zone changes, and when the app comes back to the front.
- [x] **Lyrics** is a kind of nugget, with Artist and Song.
- [x] **Deleting** asks with a centered alert that previews the nugget.
- [x] **Adding a nugget is a celebration:** a green check, haptic, the two-note rising ding, and confetti when the 21st spot fills.
- [x] **The maximum stays at 21.** You can have fewer by pausing nuggets.
- [x] **Every action you start confirms that it worked** (except reordering), with Undo for moves. Only moving into Active plays the haptic.
- [x] **Moving between sections is one smooth animation.**

### Decided not to do
- Choosing your own rotation size (the maximum stays at 21).
- Automatically moving nuggets into Active when a spot opens.
- A reminder before the 60 days of queued notifications run out. Opening the app, or iOS's background refresh, keeps the queue topped up.
- Starter nuggets for new users. Search Nuggets (v2) covers this instead.

### Replaced by later decisions
- The single Inactive list and its ordering became Queued and Paused.
- The "Active" switch on the form became the Active | Queued | Paused pill.
- The original celebration (milestone text, a note about where the nugget went, closing on its own) became the two save layouts.
