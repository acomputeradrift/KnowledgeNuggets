# Knowledge Nuggets - Handoff

## What it is
A personal iPhone app (SwiftUI + SwiftData, iOS 17+, iPhone only). Holds up to 21 active "nuggets" (book/movie/show/podcast/lyrics/quote/affirmation/other) and sends one a day as a local notification at a chosen time, cycling in list order.
Fully on-device: no server, account or running cost. Only network call is an optional Open Library lookup for books.

## Start here
- `../CLAUDE.md` - rules for every project (TODO.md workflow, coordinator/agent split, Handoff.md).
- `TODO.md` - dated task list (last section is 2026-11-13; nothing for later days yet).
- `README.md` - product summary. `ios/README.md` - setup, tests, debug launch args, how each piece works.
- No project-level `CLAUDE.md` in this folder.

## Where things are (all under `ios/`)
- `project.yml` - XcodeGen spec (bundle prefix, iOS 17, signing team). The `.xcodeproj` is generated; edit project.yml, not Xcode.
- `KnowledgeNuggets/App/` - app entry, `AppModel` (routes every change through the store, then reschedules), `AppDelegate`, `AppInfo` (version/build), `SampleData`.
- `Models/` - `Nugget`, `NuggetKind`, `SaveCelebration`.
- `Store/` - `NuggetStore` protocol (enforces 21-active limit) and `SwiftDataNuggetStore`.
- `Rotation/RotationEngine.swift` - pure function: today's nugget from active list + days since start.
- `Notifications/NotificationScheduler.swift` - re-queues next 60 days of local notifications.
- `Lookup/MetadataLookup.swift` - Open Library author/book lookup.
- `Backup/NuggetBackup.swift` - JSON export/import (merge by id).
- `Settings/AppSettings.swift`; `Feedback/SoundPlayer.swift`; `Resources/Sounds/success.caf`.
- `Views/` - Root, Today, NuggetList, NuggetEditor, NuggetDetail, Settings, SaveCelebration, ConfirmationToast, PreviewSupport.
- `KnowledgeNuggetsTests/` - unit tests per component (store, rotation, scheduler, app model, toast, celebration, lookup, kinds).
- `ios/build/` - local DerivedData (build output, not source).

## Build and run
- `brew install xcodegen`, then `cd ios && xcodegen generate && open KnowledgeNuggets.xcodeproj`. Re-run generate after adding/moving/deleting files.
- Tests: see `ios/README.md` (xcodebuild, scheme KnowledgeNuggets, iPhone simulator).
- Debug launch args (`-inMemoryStore`, `-seedSampleData`, `-tab ...`): see `ios/README.md`.
- Device install: signing team is set in project.yml. App Store / TestFlight release steps: not documented.

## Status
- Live/working: on-device rotation, notifications, add/edit/delete, Active/Inactive lists, export/import, celebration + toasts, Lyrics kind, version shown in Settings (latest commits, 2026-11-13 work).
- TODO.md items are all ticked except v2 idea "Search Nuggets" (community sharing; needs a backend, out of scope for v1).
- Not yet felt on a real phone (per TODO.md): haptics, Reduce Motion, VoiceOver for the celebration.
- Current branch is `rebuild-local-ios`; the earlier Node/Postgres/Redis version is in git history before it.

## Repo
- origin: https://github.com/acomputeradrift/KnowledgeNuggets.git
