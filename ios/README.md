# Knowledge Nuggets for iOS

SwiftUI and SwiftData, iOS 17+, iPhone only, portrait. No backend.

## Getting started

The Xcode project is generated from [`project.yml`](project.yml) with [XcodeGen](https://github.com/yonaskolb/XcodeGen), so it is never edited by hand or committed.

```bash
brew install xcodegen
cd ios
xcodegen generate
open KnowledgeNuggets.xcodeproj
```

Run `xcodegen generate` again after adding, moving or deleting files.

### Running on your iPhone

The Apple team is set in `project.yml` (`DEVELOPMENT_TEAM`), so a regenerated project keeps signing. Change it there, not in Xcode. With a free Apple ID the install expires after 7 days; a paid developer account lasts a year.

### Tests

```bash
cd ios
xcodebuild -project KnowledgeNuggets.xcodeproj -scheme KnowledgeNuggets \
  -destination 'platform=iOS Simulator,name=iPhone 14 Pro' test
```

### Debug launch arguments

For screenshots and manual checks (Debug builds only):

| Argument | Effect |
| --- | --- |
| `-inMemoryStore` | Use a throwaway store instead of the real one |
| `-seedSampleData` | Add example nuggets: 7 active, 3 queued, 2 paused |
| `-seedActiveCount N` | N active nuggets only (with `-seedSampleData` too, adds the queued and paused samples) |
| `-tab today\|nuggets\|settings` | Open on that tab |

## How it works

| Piece | File | Job |
| --- | --- | --- |
| `Nugget` | `Models/Nugget.swift` | SwiftData model. Every property is optional or defaulted and nothing is `@Attribute(.unique)`, so CloudKit sync can be turned on later. `state` is `active`, `queued` or `paused`; `sortOrder` is the position within that section. |
| `NuggetText` | `Models/NuggetText.swift` | Pure: strips wrapping quotes for storage, wraps in curly quotes for display, and builds the duplicate match key. |
| `NuggetListLayout` | `Models/NuggetListLayout.swift` | Pure: maps a drop in the flat Nuggets list back to a section and position. |
| `NuggetStore` | `Store/NuggetStore.swift` | Storage protocol: add, edit, place (move within or between sections), delete, duplicates, migrations, export, import. Enforces the 21-active limit. |
| `SwiftDataNuggetStore` | `Store/SwiftDataNuggetStore.swift` | The SwiftData implementation. |
| `RotationEngine` | `Rotation/RotationEngine.swift` | Pure function: today's nugget = active nuggets in list order at (days since rotation start, local calendar) mod count. |
| `NotificationScheduler` | `Notifications/NotificationScheduler.swift` | Clears and re-queues the next 60 days of local notifications. Clock, calendar and notification center are injected. |
| `MetadataLookup` / `OpenLibraryLookup` | `Lookup/MetadataLookup.swift` | Fills in the missing author or book after save, only on an exact match. Fails silently offline. |
| `AppModel` | `App/AppModel.swift` | Runs every change through the store, then reschedules. |

**Notifications.** Title "Knowledge Nugget", body is the passage, subtitle is author and book. Each one carries the nugget id in `userInfo`; tapping it opens that nugget. The queue is rebuilt on every data or settings change, every time the app opens, and in background app refresh. Permission is requested the first time you set a time (or tap Turn On in Settings), never at launch. Nothing is queued while paused or with no active nuggets. Triggers use local date components with no time zone, so the nugget arrives at your chosen local time when you travel.

**Rotation start** is set the first time notifications are scheduled. Rotation uses list position, not stored sort numbers, so deleting or pausing a nugget never leaves an empty day.

**Active, Queued and Paused.** Active is the rotation (at most 21). Queued waits for a spot; a new nugget saved while Active is full goes to the bottom of Queued. Paused is for nuggets you don't want to see any time soon but don't want to delete; pausing puts a nugget at the bottom of Paused. Nothing ever moves into Active on its own: pausing or deleting an active nugget leaves the spot open. In the Nuggets list, swipe an active nugget to Pause and a queued or paused one to Activate, or touch and hold and drag a nugget within or between sections. The list is one `ForEach` with header rows that can't move, because `onMove` never leaves its `ForEach`. A move into a full Active is refused with an alert. Moves between sections confirm with a toast and Undo; only a move into Active plays the success haptic. The add and edit forms have an Active | Queued | Paused pill; Active is greyed out when 21 are active.

**Quotes and duplicates.** Content is stored without wrapping quotation marks and shown everywhere in curly quotes (affirmations too). A nugget whose content matches another (ignoring case, spacing, wrapping quotes and end punctuation) can't be saved; the editor says so with a Show It button. Import skips such duplicates and counts them.

**Migration.** At launch, nuggets saved before states existed are mapped: active stays active; inactive and never moved out on purpose becomes queued, oldest first; moved out on purpose becomes paused, in that order. The old `isActive` and `deactivatedAt` columns are kept (renamed in Swift with `originalName`) so the SwiftData migration stays lightweight. Wrapping quotes are stripped from stored texts once.

**Adding a nugget.** Pick a kind (Book, Movie, Show, Podcast, Lyrics, Quote, Affirmation, Other; the last one used is remembered), type the content, then fill in By and/or From. One of By or From is required for every kind except Affirmation, which has neither. Recently used sources for that kind appear as tap-to-fill chips. Category is optional and tucked behind "Add Category". The Open Library lookup only runs for books.

The stored fields are still `author` (shown as By) and `book` (shown as From), plus `kind`, so older data and backups load unchanged; anything saved before kinds existed reads as a Book.

**Backup.** Settings → Export shares every nugget as JSON. Import merges by id: new nuggets are added to the bottom of their section, existing ones are replaced only when the backup copy is newer, active past the limit goes to the bottom of Queued, and duplicates of a different nugget are skipped. Backups write `state` (version 2); older backups with only `isActive` and `deactivatedAt` are read with the same mapping as the migration.
