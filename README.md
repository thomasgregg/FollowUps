# FollowUps

FollowUps is a local-first iOS app that helps you turn spoken call or meeting notes into actionable follow-ups.

You explicitly start recording, FollowUps processes the finished audio with OpenAI, extracts a concise list of tasks, and lets you selectively sync those tasks to Apple Reminders.

## Highlights

- One-tap recording flow from the app.
- Quick entry points via Widget and App Shortcuts.
- Live Activity for visible recording state.
- OpenAI-based multilingual transcription + task extraction.
- Session-level task review with editable due dates and reminder selection.
- Reminders sync that can create, update, and remove reminders based on current task selection.
- Local persistence for sessions, settings, and audio files.

## What FollowUps Does

- Records audio from the microphone after explicit user action.
- Uploads finished recordings to OpenAI for transcription and task extraction.
- Generates a short session headline plus task list.
- Saves sessions locally and shows them in a browsable Sessions tab.
- Lets users replay recordings and review transcript text.
- Optionally syncs selected tasks to Apple Reminders.
- Supports optional retention cleanup of old sessions and corresponding audio files.

## What FollowUps Does Not Do

- It cannot monitor or intercept all incoming calls from Phone, FaceTime, WhatsApp, Teams, Zoom, or similar apps.
- It cannot capture another app’s private call stream directly.
- It does not auto-start recording.
- It does not guarantee exact-time background execution (iOS schedules background work opportunistically).

## Product Constraints (iOS-Compliant)

FollowUps is intentionally built around Apple platform constraints:

- Recording starts only after explicit user interaction.
- Recording status is always visible in UI (and Live Activity when active).
- Background processing is best-effort, not guaranteed realtime automation.
- Reminders are only created/updated after explicit user confirmation.

## Tech Stack

- Swift 5.10+
- SwiftUI
- AVFoundation / AVAudioSession
- App Intents / App Shortcuts
- WidgetKit
- ActivityKit
- UserNotifications
- EventKit (Apple Reminders)
- BackgroundTasks

## Architecture

- Pattern: MVVM + service layer
- Main app tabs: `Record`, `Sessions`, `Settings`
- Core service boundaries:
  - `AudioCaptureService`
  - `TranscriptionService`
  - `ActionItemExtractionService`
  - `ReminderService`
  - `CompletionNotificationService`
  - `BackgroundTaskService`
  - `PersistenceService`

## Repository Structure

- `App/` app entry point, dependency container, root navigation
- `Features/Recording/` capture UX, active recording, processing state
- `Features/Sessions/` session list/detail, task review, transcript playback
- `Features/Settings/` API key, extraction preferences, storage policy
- `Services/` protocol-driven implementation of app side effects
- `Models/` domain models (`CallSession`, `ActionItem`, transcript models, states)
- `Widgets/` quick-start widget UI
- `LiveActivity/` recording live activity UI
- `Shortcuts/` App Intents / App Shortcuts
- `Tests/` unit and UI tests
- `project.yml` XcodeGen project definition
- `Resources/` Info.plist + asset catalogs

## Getting Started

### Requirements

- Xcode 16+
- iOS 18 deployment target
- Homebrew (recommended for XcodeGen install)

### Setup

1. Clone the repo:
   ```bash
   git clone https://github.com/thomasgregg/FollowUps.git
   cd FollowUps
   ```
2. Install XcodeGen:
   ```bash
   brew install xcodegen
   ```
3. Generate the project:
   ```bash
   xcodegen generate
   ```
4. Open `FollowUps.xcodeproj` in Xcode.
5. Configure Signing & Capabilities with your Apple Developer team.
6. Run on Simulator or real device.

### OpenAI Configuration

- Open the app → `Settings` → `OpenAI API Key`.
- Paste your key (for example: `sk-...`).
- FollowUps requires a valid key for transcription and task extraction.

## Reminders Behavior

- Tasks are extracted first.
- You choose which tasks are selected.
- `Create Apple Reminders` creates reminders for selected tasks.
- `Update Apple Reminders` reconciles existing reminders with the current task selection:
  - selected tasks are created/updated
  - deselected previously-linked tasks are removed

## Permissions

FollowUps uses:

- Microphone permission (`NSMicrophoneUsageDescription`)
- Reminders permission (`NSRemindersFullAccessUsageDescription`)
- Notifications permission (processing completion notifications)

## Privacy

- Recording starts only when you explicitly tap record.
- Audio is stored locally first, then sent to OpenAI only after user action and cloud-processing consent.
- No automatic interception of third-party call audio.
- Reminders are created only after user review/confirmation.

Privacy policy: [https://thomasgregg.github.io/FollowUps/privacy.html](https://thomasgregg.github.io/FollowUps/privacy.html)
Support: [https://thomasgregg.github.io/FollowUps/support.html](https://thomasgregg.github.io/FollowUps/support.html)

## Testing

- Unit tests: `Tests/Unit`
- UI tests: `Tests/UI`

Run tests in Xcode or via CLI:

```bash
xcodebuild test -scheme FollowUps -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Known Limitations

- Task quality depends on transcription quality and model output quality.
- Long recordings can take noticeable processing time.
- Background continuation is limited by iOS process and task policies.
- Bluetooth/headset routing can impact captured audio characteristics.

## Roadmap Ideas

- Better processing telemetry and error diagnostics
- Richer task controls (owner/date confidence tuning)
- Additional export targets beyond Apple Reminders
- Improved offline UX around deferred processing states
