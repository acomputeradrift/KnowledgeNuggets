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
| `-seedSampleData` | Add a few example nuggets on launch |
| `-tab today\|nuggets\|settings` | Open on that tab |

## How it works

| Piece | File | Job |
| --- | --- | --- |
| `Nugget` | `Models/Nugget.swift` | SwiftData model. Every property is optional or defaulted and nothing is `@Attribute(.unique)`, so CloudKit sync can be turned on later. |
| `NuggetStore` | `Store/NuggetStore.swift` | Storage protocol: add, edit, activate, delete, reorder, export, import. Enforces the 21-active limit. |
| `SwiftDataNuggetStore` | `Store/SwiftDataNuggetStore.swift` | The SwiftData implementation. |
| `RotationEngine` | `Rotation/RotationEngine.swift` | Pure function: today's nugget = active nuggets in list order at (days since rotation start, local calendar) mod count. |
| `NotificationScheduler` | `Notifications/NotificationScheduler.swift` | Clears and re-queues the next 60 days of local notifications. Clock, calendar and notification center are injected. |
| `MetadataLookup` / `OpenLibraryLookup` | `Lookup/MetadataLookup.swift` | Fills in the missing author or book after save, only on an exact match. Fails silently offline. |
| `AppModel` | `App/AppModel.swift` | Runs every change through the store, then reschedules. |

**Notifications.** Title "Knowledge Nugget", body is the passage, subtitle is author and book. Each one carries the nugget id in `userInfo`; tapping it opens that nugget. The queue is rebuilt on every data or settings change, every time the app opens, and in background app refresh. Permission is requested the first time you set a time (or tap Turn On in Settings), never at launch. Nothing is queued while paused or with no active nuggets. Triggers use local date components with no time zone, so the nugget arrives at your chosen local time when you travel.

**Rotation start** is set the first time notifications are scheduled. Rotation uses list position, not stored sort numbers, so deleting or deactivating a nugget never leaves an empty day.

**Backup.** Settings → Export shares every nugget as JSON. Import merges by id: new nuggets are added, existing ones are replaced only when the backup copy is newer, and the 21-active limit still applies.
