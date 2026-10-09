# Pomodoro

This is a work-in-progress, pardon our juice 🍅.

Adds a Pomodoro overlay tracking your current intention. 
<img width="427" height="153" alt="image" src="https://github.com/user-attachments/assets/2384e732-36f9-4f2c-9700-01721f9fb20a" />

Feature List:
- 🍅
- Top bar showing timer
- Top bar with shortcuts for setting current task, focus length, break length, start/pause, stop alarm, reset focus, start break, toggle overlay, and quit.
- persistent overlay that shows above all objects. includes: task title, length of time left, whether currently on a focus or a break.
- easy to use buttons for: pause/play, set task title, set task length, reset, quit. buttons should be tasteful icons. and tastefully placed where possible. simpel texdt labels shouldnt be necessary.
- Repeating alarm on session completion (using default macos alarm sound)
- Persistent reminder to start a timer when timer is off
- draggable overlay
- ability to fine-tune what you want your pomodoros to look like. im not sure if i want this in its own dedicated page bc im not sure i love the idea of a dedicated UI page for this.
- support for long brekas
-  18. Auto-start break option
 19. Auto-start next focus option
 20. Idle reminder interval setting
 21. Skip break / skip focus actions
 22. 24. Focus mode / Do Not Disturb integration
 25. signed .app

Design principles
- minimal, FOSS, built-in mac app. native and baremetal as possible.
- modular and composable, such that it's highly extensible
- settings hide any funny business
- as native-as-posisble macos themes.  make as few design decisions as possible.
- No required account, network, database, or backend

- No "Later" button: dismissing a nudge or ending a focus early asks *what are you doing and why?* (50+ characters). Every answer is journaled.
- Journal (menu → Journal…, ⌘J): completed focus sessions and every time you stepped away, with a 7-day summary. Stored as JSON Lines at `~/Library/Application Support/Pomodoro Overlay/journal.jsonl`.
- Calendar sync: completed focus sessions of 5+ minutes become events on any calendar macOS knows about (iCloud, Google via System Settings → Internet Accounts, Exchange). Set up on first run or in Settings.
- First-run setup and a Settings window (⌘,).

## Install

Download the latest `.dmg` from [Releases](https://github.com/codyhxyz/pomodoro/releases), open it, and drag Pomodoro Overlay into Applications.

## Build

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). `project.yml` is the source of truth for `PomodoroOverlay.xcodeproj`.

```sh
make project   # regenerate the Xcode project after editing project.yml or adding files
make run       # build, install to ~/Applications, and launch
make dmg       # build an installer disk image in build/
```

Builds always target `platform=macOS`, so they never boot an iOS simulator.

## Releases (Xcode Cloud)

Create a workflow in Xcode (Integrate → Create Workflow) with an **Archive** action for macOS and **Developer ID** distribution; Xcode Cloud signs and notarizes it. `ci_scripts/ci_post_xcodebuild.sh` then wraps the notarized app in a DMG. If the workflow has a `GITHUB_TOKEN` secret and was started from a tag, it attaches the DMG to that GitHub release.
